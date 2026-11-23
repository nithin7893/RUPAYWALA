"""Stage 5: secure fixed quotations.

These tests use the isolated PostgreSQL fixture and a stubbed Google route
function. No live map provider is ever called. The existing pricing formula,
effective database rate, rounding, tax and entitlement rules are exercised
through the real pricing service.
"""

import threading
from datetime import date, datetime, timedelta
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import QUOTE_VALIDITY_MINUTES
from app.database import SessionLocal
from app.models.distance_rate_config import DistanceRateConfig
from app.models.payment import Payment
from app.models.service_quote import QuoteStatus, ServiceQuote
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.subscription_family_member import SubscriptionFamilyMember
from app.models.user import User, UserRole
from app.schemas.service_request_schema import QuoteCreate, ServiceRequestCreate
from app.services import map_service as maps
from app.services.pricing_service import PricingConfig, build_quote, get_pricing_config
from app.services.quote_service import QuoteService
from app.utils.jwt_handler import create_access_token
from tests import factories as f

LAT = 13.0827
LNG = 80.2707


# ======================================================================
# helpers
# ======================================================================
def bearer(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token({'user_id': user.id})}"}


def _make_rate(
    db, *, threshold=10.0, rate=20.0, tax=18.0, factor=2.0
) -> DistanceRateConfig:
    row = DistanceRateConfig(
        threshold_km=threshold,
        rate_per_km=rate,
        tax_percent=tax,
        round_trip_factor=factor,
        effective_at=datetime.utcnow(),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _setup(
    db,
    *,
    threshold=10.0,
    rate=20.0,
    tax=18.0,
    factor=2.0,
    included_distance=None,
    visits=4,
):
    user = f.make_user(db)
    plan = f.make_plan(db, visits_included=visits)
    subscription = f.make_subscription(db, user, plan)
    if included_distance is not None:
        subscription.entitlements_snapshot = {
            "included_visit_distance_km": float(included_distance)
        }
        db.commit()
        db.refresh(subscription)
    policy = f.make_policy(db, user)
    branch = f.make_branch(db)
    service = f.make_service_type(db)
    config = _make_rate(
        db, threshold=threshold, rate=rate, tax=tax, factor=factor
    )
    return {
        "user": user,
        "plan": plan,
        "subscription": subscription,
        "policy": policy,
        "branch": branch,
        "service": service,
        "config": config,
    }


def _quote_payload(ctx, **overrides):
    payload = {
        "service_type_id": ctx["service"].id,
        "request_type": "claim",
        "policy_id": ctx["policy"].id,
        "branch_id": ctx["branch"].id,
        "family_member_id": None,
        "customer_latitude": LAT,
        "customer_longitude": LNG,
        "customer_address": "1 Test Street",
        "customer_place_id": "place-test-1",
    }
    payload.update(overrides)
    return payload


def _request_payload(quote, **overrides):
    payload = {
        "quote_id": quote["quote_id"],
        "service_type_id": quote["service_type_id"],
        "request_type": quote["request_type"],
        "policy_id": quote["policy_id"],
        "branch_id": quote["branch_id"],
        "family_member_id": quote.get("family_member_id"),
        "customer_latitude": LAT,
        "customer_longitude": LNG,
        "customer_address": "1 Test Street",
        "customer_place_id": "place-test-1",
        "description": "Water leak",
    }
    payload.update(overrides)
    return payload


@pytest.fixture()
def stub_route(monkeypatch):
    """Deterministic traffic-aware route, patched at the service boundary."""
    state = {"calls": 0, "km": 15.0, "minutes": 30.0, "error": None}

    class _Distance:
        def __init__(self, km, minutes):
            self.distance_km = km
            self.duration_minutes = minutes

    def fake(origin_lat, origin_lng, dest_lat, dest_lng):
        state["calls"] += 1
        if state["error"] is not None:
            raise state["error"]
        return _Distance(state["km"], state["minutes"])

    # Patch the raw provider call, not the wrapper, so HTTP error translation
    # is covered as well.
    monkeypatch.setattr("app.services.quote_service._calculate_route", fake)
    return state


def _create_quote(client, ctx, **overrides):
    response = client.post(
        "/service/quote", json=_quote_payload(ctx, **overrides), headers=bearer(ctx["user"])
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_quote_backed_request(client, ctx, quote, **overrides):
    response = client.post(
        "/service/request",
        json=_request_payload(quote, **overrides),
        headers=bearer(ctx["user"]),
    )
    return response


def _get_quote_row(db, quote) -> ServiceQuote:
    return (
        db.query(ServiceQuote)
        .filter(ServiceQuote.quote_ref == quote["quote_id"])
        .one()
    )


def _make_family_member(db, subscription, name="Child"):
    member = SubscriptionFamilyMember(
        subscription_id=subscription.id,
        member_name=name,
        relationship="child",
        member_type="child",
        identity_key=f"identity-{name}-{subscription.id}",
    )
    db.add(member)
    db.commit()
    db.refresh(member)
    return member


# ======================================================================
# Quote generation
# ======================================================================
class TestQuoteGeneration:
    def test_successful_quote_generation(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)

        assert quote["status"] == "active"
        assert quote["quote_id"]
        assert quote["service_type_id"] == ctx["service"].id
        assert quote["request_type"] == "claim"
        assert quote["branch_id"] == ctx["branch"].id
        assert quote["policy_id"] == ctx["policy"].id
        assert quote["distance_km"] == 15.0
        assert quote["duration_minutes"] == 30.0
        assert quote["total_amount"] == 236.0
        assert quote["currency"] == "INR"
        assert quote["requires_payment"] is True
        assert _get_quote_row(db, quote).user_id == ctx["user"].id

    def test_existing_pricing_formula_and_tax_are_applied(self, client, db, stub_route):
        ctx = _setup(db, threshold=10.0, rate=20.0, tax=18.0, factor=2.0)
        quote = _create_quote(client, ctx)

        # 2 x (15 - 10) x 20 = 200; tax 18% = 36; total = 236.
        assert quote["base_amount"] == 0.0
        assert quote["extra_charge"] == 200.0
        assert quote["tax_percent"] == 18.0
        assert quote["tax_amount"] == 36.0
        assert quote["total_amount"] == 236.0
        assert quote["within_threshold"] is False

    def test_effective_database_distance_rate_is_used(self, client, db, stub_route):
        ctx = _setup(db, rate=30.0)
        quote = _create_quote(client, ctx)

        # 2 x 5 x 30 = 300; tax 18% = 54; total = 354.
        assert quote["charge_per_km"] == 30.0
        assert quote["extra_charge"] == 300.0
        assert quote["tax_amount"] == 54.0
        assert quote["total_amount"] == 354.0
        assert _get_quote_row(db, quote).distance_rate_config_id == ctx["config"].id

    def test_rounding_rules_are_preserved(self, client, db, stub_route):
        ctx = _setup(db, rate=20.0, tax=18.0)
        stub_route["km"] = 10.333
        stub_route["minutes"] = 21.7

        config = get_pricing_config(db)
        expected = build_quote(distance_km=10.333, config=config)
        quote = _create_quote(client, ctx)

        assert quote["distance_km"] == expected.distance_km
        assert quote["excess_distance_km"] == expected.excess_distance_km
        assert quote["extra_charge"] == expected.extra_charge == 13.32
        assert quote["tax_amount"] == expected.tax_amount == 2.40
        assert quote["total_amount"] == expected.total_amount == 15.72

    def test_subscription_distance_entitlement_is_applied(self, client, db, stub_route):
        ctx = _setup(db, included_distance=5.0, threshold=10.0, rate=20.0)
        quote = _create_quote(client, ctx)

        # The subscription replaces the 10 km threshold with 5 km.
        assert quote["threshold_km"] == 5.0
        assert quote["entitlement_included_distance_km"] == 5.0
        # 2 x (15 - 5) x 20 = 400; tax 72; total 472.
        assert quote["extra_charge"] == 400.0
        assert quote["tax_amount"] == 72.0
        assert quote["total_amount"] == 472.0

    def test_branch_and_policy_are_bound(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _get_quote_row(db, quote)

        assert row.branch_id == ctx["branch"].id
        assert row.policy_id == ctx["policy"].id
        assert row.subscription_id == ctx["subscription"].id
        assert row.customer_latitude == Decimal(str(LAT))
        assert row.customer_longitude == Decimal(str(LNG))

    def test_quote_expiry_is_server_side_and_configurable(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)

        created = datetime.fromisoformat(quote["created_at"])
        expires = datetime.fromisoformat(quote["expires_at"])
        assert expires - created == timedelta(minutes=QUOTE_VALIDITY_MINUTES)
        assert expires > datetime.utcnow()

        response = client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        )
        assert response.status_code == 200
        assert response.json()["status"] == "active"

    def test_missing_coordinates_are_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        payload = _quote_payload(ctx)
        payload.pop("customer_latitude")
        assert (
            client.post(
                "/service/quote", json=payload, headers=bearer(ctx["user"])
            ).status_code
            == 422
        )

        payload = _quote_payload(ctx)
        payload.pop("customer_longitude")
        assert (
            client.post(
                "/service/quote", json=payload, headers=bearer(ctx["user"])
            ).status_code
            == 422
        )
        assert db.query(ServiceQuote).count() == 0

    def test_invalid_coordinates_are_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        for payload in (
            _quote_payload(ctx, customer_latitude=91.0),
            _quote_payload(ctx, customer_longitude=181.0),
            _quote_payload(ctx, customer_latitude=0.0, customer_longitude=0.0),
        ):
            response = client.post(
                "/service/quote", json=payload, headers=bearer(ctx["user"])
            )
            assert response.status_code in (400, 422)
        assert db.query(ServiceQuote).count() == 0

        with pytest.raises(ValidationError):
            QuoteCreate(
                **_quote_payload(
                    ctx,
                    customer_latitude=float("nan"),
                )
            )

    def test_google_route_failure_is_handled_safely(self, client, db, stub_route):
        ctx = _setup(db)
        stub_route["error"] = maps.MapProviderUnavailable("provider down")
        response = client.post(
            "/service/quote",
            json=_quote_payload(ctx),
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 503
        assert db.query(ServiceQuote).count() == 0

    def test_invalid_service_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        response = client.post(
            "/service/quote",
            json=_quote_payload(ctx, service_type_id=999999),
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 404
        assert db.query(ServiceQuote).count() == 0

    def test_inactive_service_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        ctx["service"].is_active = False
        db.commit()
        response = client.post(
            "/service/quote", json=_quote_payload(ctx), headers=bearer(ctx["user"])
        )
        assert response.status_code == 404

    def test_quote_generation_requires_authentication(self, client, db, stub_route):
        ctx = _setup(db)
        assert client.post("/service/quote", json=_quote_payload(ctx)).status_code == 401

    def test_non_customer_cannot_generate_a_quote(self, client, db, stub_route):
        ctx = _setup(db)
        member = f.make_user(db, role=UserRole.field_member)
        response = client.post(
            "/service/quote", json=_quote_payload(ctx), headers=bearer(member)
        )
        assert response.status_code == 403

    def test_quote_requires_an_active_subscription(self, client, db, stub_route):
        user = f.make_user(db)
        policy = f.make_policy(db, user)
        branch = f.make_branch(db)
        service = f.make_service_type(db)
        _make_rate(db)
        response = client.post(
            "/service/quote",
            json={
                "service_type_id": service.id,
                "request_type": "claim",
                "policy_id": policy.id,
                "branch_id": branch.id,
                "customer_latitude": LAT,
                "customer_longitude": LNG,
                "customer_address": "1 Test Street",
            },
            headers=bearer(user),
        )
        assert response.status_code == 403

    def test_quote_rejects_no_remaining_visits(self, client, db, stub_route):
        ctx = _setup(db, visits=0)
        response = client.post(
            "/service/quote", json=_quote_payload(ctx), headers=bearer(ctx["user"])
        )
        assert response.status_code == 403

    def test_quote_rejects_unknown_or_inactive_branch(self, client, db, stub_route):
        ctx = _setup(db)
        assert (
            client.post(
                "/service/quote",
                json=_quote_payload(ctx, branch_id=999999),
                headers=bearer(ctx["user"]),
            ).status_code
            == 404
        )

        ctx["branch"].is_active = False
        db.commit()
        assert (
            client.post(
                "/service/quote", json=_quote_payload(ctx), headers=bearer(ctx["user"])
            ).status_code
            == 400
        )

    def test_quote_rejects_another_customers_policy(self, client, db, stub_route):
        ctx = _setup(db)
        other = f.make_user(db)
        other_policy = f.make_policy(db, other)
        response = client.post(
            "/service/quote",
            json=_quote_payload(ctx, policy_id=other_policy.id),
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 404

    def test_quote_rejects_an_expired_policy(self, client, db, stub_route):
        ctx = _setup(db)
        ctx["policy"].expiry_date = date.today() - timedelta(days=1)
        db.commit()
        response = client.post(
            "/service/quote", json=_quote_payload(ctx), headers=bearer(ctx["user"])
        )
        assert response.status_code == 400

    def test_quote_rejects_unauthorized_family_member(self, client, db, stub_route):
        ctx = _setup(db)
        other = f.make_user(db)
        other_plan = f.make_plan(db)
        other_sub = f.make_subscription(db, other, other_plan)
        foreign_member = _make_family_member(db, other_sub, "Foreign")

        response = client.post(
            "/service/quote",
            json=_quote_payload(ctx, family_member_id=foreign_member.id),
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 404

    def test_digital_service_makes_no_google_call(self, client, db, stub_route):
        ctx = _setup(db)
        digital = f.make_service_type(db, code="document_scanning")
        quote = _create_quote(
            client, ctx, service_type_id=digital.id, request_type="document_scanning"
        )

        assert stub_route["calls"] == 0
        assert quote["distance_km"] == 0.0
        assert quote["extra_charge"] == 0.0
        assert quote["total_amount"] == 0.0
        assert quote["requires_payment"] is False

    def test_quote_token_is_random_and_unique(self, client, db, stub_route):
        ctx = _setup(db)
        first = _create_quote(client, ctx)
        second = _create_quote(client, ctx)

        assert first["quote_id"] != second["quote_id"]
        assert len(first["quote_id"]) >= 32
        assert not first["quote_id"].isdigit()
        assert "signature" not in first
        assert "distance_rate_config_id" not in first


# ======================================================================
# Quote retrieval and validation
# ======================================================================
class TestQuoteRetrieval:
    def test_owner_can_retrieve_quote(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        response = client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        )
        assert response.status_code == 200
        assert response.json()["total_amount"] == quote["total_amount"]

    def test_another_customer_cannot_retrieve_quote(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        other = f.make_user(db)
        response = client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(other)
        )
        assert response.status_code == 404

    def test_quote_retrieval_requires_authentication(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert client.get(f"/service/quote/{quote['quote_id']}").status_code == 401

    def test_another_customer_cannot_cancel_quote(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        other = f.make_user(db)

        response = client.post(
            f"/service/quote/{quote['quote_id']}/cancel", headers=bearer(other)
        )
        assert response.status_code == 404
        assert _get_quote_row(db, quote).status == QuoteStatus.active

    def test_unknown_quote_cannot_be_cancelled(self, client, db, stub_route):
        ctx = _setup(db)
        response = client.post(
            "/service/quote/does-not-exist/cancel", headers=bearer(ctx["user"])
        )
        assert response.status_code == 404

    def test_quote_cancellation_requires_authentication(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert (
            client.post(f"/service/quote/{quote['quote_id']}/cancel").status_code == 401
        )

    def test_tampered_quote_is_rejected_on_read(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _get_quote_row(db, quote)
        row.total_amount = Decimal("1.00")
        db.commit()

        response = client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        )
        assert response.status_code == 409


class TestQuoteValidation:
    def test_valid_quote_is_accepted_and_request_inherits_snapshot(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        body = response.json()

        assert body["total_amount"] == quote["total_amount"]
        assert body["extra_charge"] == quote["extra_charge"]
        assert body["tax_amount"] == quote["tax_amount"]
        assert body["distance_km"] == quote["distance_km"]
        assert body["branch_id"] == quote["branch_id"]
        assert body["policy_id"] == quote["policy_id"]
        assert body["status"] == "payment_pending"

        row = _get_quote_row(db, quote)
        assert row.status == QuoteStatus.consumed
        assert row.consumed_at is not None
        assert row.service_request_id == body["id"]

    def test_expired_quote_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _get_quote_row(db, quote)
        # Expiry is now part of the signed lifecycle payload, so the test must
        # re-sign after moving the clock - exactly as the service does.
        from app.services.quote_service import _sign

        row.expires_at = datetime.utcnow() - timedelta(seconds=1)
        row.signature = _sign(row)
        db.commit()

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 410
        assert db.query(ServiceRequest).filter(ServiceRequest.user_id == ctx["user"].id).count() == 0

        db.expire_all()
        assert _get_quote_row(db, quote).status == QuoteStatus.expired

    def test_cancelled_quote_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        cancel = client.post(
            f"/service/quote/{quote['quote_id']}/cancel", headers=bearer(ctx["user"])
        )
        assert cancel.status_code == 200
        assert cancel.json()["status"] == "cancelled"

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 409
        assert db.query(ServiceRequest).filter(ServiceRequest.user_id == ctx["user"].id).count() == 0

    def test_consumed_quote_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert _create_quote_backed_request(client, ctx, quote).status_code == 201

        second = _create_quote_backed_request(client, ctx, quote)
        assert second.status_code == 409
        assert db.query(ServiceRequest).filter(ServiceRequest.user_id == ctx["user"].id).count() == 1

    def test_quote_belonging_to_another_customer_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        other = f.make_user(db)
        plan = f.make_plan(db)
        f.make_subscription(db, other, plan)
        other_policy = f.make_policy(db, other)

        response = client.post(
            "/service/request",
            json=_request_payload(quote, policy_id=other_policy.id),
            headers=bearer(other),
        )
        assert response.status_code == 404
        assert db.query(ServiceRequest).filter(ServiceRequest.user_id == other.id).count() == 0
        assert _get_quote_row(db, quote).status == QuoteStatus.active

    def test_wrong_service_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        other_service = f.make_service_type(db)
        response = _create_quote_backed_request(
            client, ctx, quote, service_type_id=other_service.id
        )
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_wrong_request_type_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        response = _create_quote_backed_request(
            client, ctx, quote, request_type="inspection"
        )
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_wrong_branch_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        other_branch = f.make_branch(db)
        response = _create_quote_backed_request(
            client, ctx, quote, branch_id=other_branch.id
        )
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_wrong_policy_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        another_policy = f.make_policy(db, ctx["user"])
        response = _create_quote_backed_request(
            client, ctx, quote, policy_id=another_policy.id
        )
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_wrong_family_member_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        family = _make_family_member(db, ctx["subscription"], "Child")
        response = _create_quote_backed_request(
            client, ctx, quote, family_member_id=family.id
        )
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_wrong_coordinates_are_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        response = _create_quote_backed_request(
            client, ctx, quote, customer_latitude=LAT + 0.01
        )
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_tampered_quote_amount_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _get_quote_row(db, quote)
        row.total_amount = Decimal("1.00")
        db.commit()

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_tampered_quote_rate_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _get_quote_row(db, quote)
        row.charge_per_km_used = Decimal("1.00")
        db.commit()

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_client_supplied_amount_is_ignored(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        response = client.post(
            "/service/request",
            json=_request_payload(
                quote, total_amount=1.0, amount=1.0, extra_charge=1.0
            ),
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["total_amount"] == quote["total_amount"] == 236.0
        assert body["extra_charge"] == 200.0

    def test_changed_database_rate_does_not_change_active_quote(
        self, client, db, stub_route
    ):
        ctx = _setup(db, rate=20.0)
        quote = _create_quote(client, ctx)
        assert quote["total_amount"] == 236.0

        _make_rate(db, rate=99.0, threshold=1.0, tax=30.0)
        assert get_pricing_config(db).charge_per_km == 99.0

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["total_amount"] == 236.0
        assert body["extra_charge"] == 200.0
        assert body["charge_per_km"] == 20.0
        assert body["tax_percent"] == 18.0

    def test_changed_pricing_configuration_does_not_change_active_quote(
        self, client, db, stub_route
    ):
        ctx = _setup(db, threshold=10.0, rate=20.0, tax=18.0)
        quote = _create_quote(client, ctx)
        _make_rate(db, threshold=0.0, rate=500.0, tax=50.0, factor=5.0)

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        assert response.json()["total_amount"] == 236.0
        assert response.json()["threshold_km"] == 10.0

    def test_changed_route_cache_or_duration_does_not_change_active_quote(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert stub_route["calls"] == 1

        stub_route["km"] = 99.0
        stub_route["minutes"] = 999.0

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["distance_km"] == 15.0
        assert body["duration_minutes"] == 30.0
        assert body["total_amount"] == 236.0
        assert stub_route["calls"] == 1, "consuming a quote must not call Google again"

    def test_route_failure_after_quote_does_not_block_consumption(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        stub_route["error"] = maps.MapProviderUnavailable("provider down")

        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        assert response.json()["total_amount"] == 236.0
        assert stub_route["calls"] == 1

    def test_unknown_quote_id_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        response = _create_quote_backed_request(client, ctx, quote, quote_id="not-a-quote")
        assert response.status_code == 404
        assert db.query(ServiceRequest).count() == 0


# ======================================================================
# Replay and concurrency
# ======================================================================
class TestReplayAndConcurrency:
    def test_quote_can_only_be_consumed_once(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert _create_quote_backed_request(client, ctx, quote).status_code == 201
        assert _create_quote_backed_request(client, ctx, quote).status_code == 409
        assert db.query(ServiceRequest).count() == 1

    def test_repeated_submission_cannot_create_duplicate_requests(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        responses = [
            _create_quote_backed_request(client, ctx, quote).status_code
            for _ in range(3)
        ]
        assert responses[0] == 201
        assert all(code == 409 for code in responses[1:])
        assert db.query(ServiceRequest).count() == 1

    def test_two_customers_cannot_consume_the_same_quote(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)

        other = f.make_user(db)
        plan = f.make_plan(db)
        f.make_subscription(db, other, plan)
        other_policy = f.make_policy(db, other)

        response = client.post(
            "/service/request",
            json=_request_payload(quote, policy_id=other_policy.id),
            headers=bearer(other),
        )
        assert response.status_code == 404
        assert _get_quote_row(db, quote).status == QuoteStatus.active

        assert _create_quote_backed_request(client, ctx, quote).status_code == 201

    def test_failed_transaction_does_not_leave_quote_consumed(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _get_quote_row(db, quote)
        payload = ServiceRequestCreate(**_request_payload(quote))

        request = QuoteService.consume_for_request(
            db, user=ctx["user"], payload=payload
        )
        assert request.id is not None
        assert row.status == QuoteStatus.consumed

        db.rollback()
        db.expire_all()

        fresh = _get_quote_row(db, quote)
        assert fresh.status == QuoteStatus.active
        assert fresh.service_request_id is None
        assert db.query(ServiceRequest).count() == 0

    def test_concurrent_consumption_is_safe(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        payload = ServiceRequestCreate(**_request_payload(quote))
        user_id = ctx["user"].id

        barrier = threading.Barrier(2)
        results: list[tuple[str, object]] = []

        def worker():
            session = SessionLocal()
            try:
                user = session.get(User, user_id)
                barrier.wait(timeout=10)
                try:
                    request = QuoteService.consume_for_request(
                        session, user=user, payload=payload
                    )
                    session.commit()
                    results.append(("ok", request.id))
                except Exception as exc:  # HTTPException expected for the loser
                    session.rollback()
                    results.append(("error", getattr(exc, "status_code", repr(exc))))
            finally:
                session.close()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=20)
            assert not thread.is_alive()

        assert len(results) == 2, results
        assert sorted(kind for kind, _ in results) == ["error", "ok"]
        errors = [value for kind, value in results if kind == "error"]
        assert errors and errors[0] in (409, 410)

        db.expire_all()
        assert db.query(ServiceRequest).filter(ServiceRequest.user_id == user_id).count() == 1
        assert _get_quote_row(db, quote).status == QuoteStatus.consumed

    def test_idempotent_payment_intent_remains_compatible(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        request = _create_quote_backed_request(client, ctx, quote).json()

        first = client.post(
            f"/service/request/{request['id']}/pay-extra-charge",
            headers=bearer(ctx["user"]),
        )
        second = client.post(
            f"/service/request/{request['id']}/pay-extra-charge",
            headers=bearer(ctx["user"]),
        )
        assert first.status_code == second.status_code == 200
        assert first.json()["txn_id"] == second.json()["txn_id"]
        assert db.query(Payment).count() == 1


# ======================================================================
# Service request and payment integration
# ======================================================================
class TestRequestAndPayment:
    def _request_with_charge(self, client, ctx):
        quote = _create_quote(client, ctx)
        response = _create_quote_backed_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        return quote, response.json()

    def test_request_receives_the_exact_quoted_amount(self, client, db, stub_route):
        ctx = _setup(db)
        quote, request = self._request_with_charge(client, ctx)

        assert request["total_amount"] == quote["total_amount"] == 236.0
        assert request["extra_charge"] == 200.0
        assert request["tax_amount"] == 36.0
        assert request["base_amount"] == 0.0
        assert request["charge_paid"] is False
        assert request["status"] == "payment_pending"

    def test_payment_uses_the_persisted_request_amount(self, client, db, stub_route):
        ctx = _setup(db)
        quote, request = self._request_with_charge(client, ctx)

        response = client.post(
            f"/service/request/{request['id']}/pay-extra-charge",
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["amount"] == quote["total_amount"] == 236.0

        payment = db.query(Payment).filter(Payment.txn_id == body["txn_id"]).one()
        assert float(payment.amount) == 236.0
        assert float(payment.extra_charge) == 200.0
        assert float(payment.tax_amount) == 36.0
        assert payment.idempotency_key == f"request:{request['id']}"

    def test_client_supplied_payment_amount_cannot_override(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        _, request = self._request_with_charge(client, ctx)

        response = client.post(
            f"/service/request/{request['id']}/pay-extra-charge",
            json={"amount": 1.0, "total_amount": 1.0},
            params={"amount": 1.0},
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 200, response.text
        assert response.json()["amount"] == 236.0

        payment = db.query(Payment).filter(Payment.txn_id == response.json()["txn_id"]).one()
        assert float(payment.amount) == 236.0

    def test_payment_is_refused_when_nothing_is_owed(self, client, db, stub_route):
        ctx = _setup(db)
        stub_route["km"] = 4.0
        quote = _create_quote(client, ctx)
        request = _create_quote_backed_request(client, ctx, quote)
        assert request.status_code == 201, request.text
        body = request.json()
        assert body["total_amount"] == 0.0
        assert body["charge_paid"] is True
        assert body["status"] == "waiting_for_assignment"

        response = client.post(
            f"/service/request/{body['id']}/pay-extra-charge",
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 400

    def test_existing_payment_and_request_status_transitions_remain_intact(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        _, request = self._request_with_charge(client, ctx)

        intent = client.post(
            f"/service/request/{request['id']}/pay-extra-charge",
            headers=bearer(ctx["user"]),
        )
        assert intent.status_code == 200
        txn_id = intent.json()["txn_id"]

        submit = client.post(
            f"/service/request/{request['id']}/submit-extra-charge-utr",
            params={"txn_id": txn_id, "utr_number": f.utr()},
            headers=bearer(ctx["user"]),
        )
        assert submit.status_code == 200, submit.text

        admin = f.make_admin(db)
        verify = client.post(
            "/admin/payments/verify",
            json={"txn_id": txn_id, "action": "approve"},
            headers=bearer(admin),
        )
        assert verify.status_code == 200, verify.text

        db.expire_all()
        row = db.get(ServiceRequest, request["id"])
        assert row.charge_paid is True
        assert row.status == RequestStatus.waiting_for_assignment

    def test_legacy_request_without_quote_still_works(
        self, client, db, stub_distance
    ):
        stub_distance(km=4.0)
        ctx = _setup(db)
        response = client.post(
            "/service/request",
            json={
                "policy_id": ctx["policy"].id,
                "branch_id": ctx["branch"].id,
                "service_type_id": ctx["service"].id,
                "request_type": "claim",
                "description": "Legacy path",
                "customer_latitude": LAT,
                "customer_longitude": LNG,
                "customer_address": "1 Test Street",
            },
            headers=bearer(ctx["user"]),
        )
        assert response.status_code == 201, response.text
        assert response.json()["total_amount"] == 0.0
