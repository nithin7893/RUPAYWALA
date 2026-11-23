"""Stage 5.1 security remediation regression suite.

Every test runs against the isolated PostgreSQL test database owned by
``tests/conftest.py``. No live map provider, Google API or production database
is ever touched.

The suite covers the audit findings F1-F10 and F12:

* lifecycle HMAC integrity and the legal state machine (F1/F8)
* NUMERIC(10,7) coordinate normalisation (F2)
* dedicated, non-empty quote signing secret (F3/F4)
* user-scoped payment idempotency and database uniqueness (F5/F9)
* one authoritative extra-charge intent (F6)
* payment eligibility for cancelled/completed requests (F7)
* safe duplicate-UTR handling (F10)
* quote-to-request-payment amount integrity (F12)

Concurrency tests use genuinely overlapping PostgreSQL sessions/transactions
and separate ``SessionLocal`` connections, never mocked locks.
"""

import threading
import time
import uuid
from datetime import datetime, timedelta
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

import app.routes.service_routes as service_routes
from app.config import (
    JWT_SECRET_KEY,
    QUOTE_LEGACY_SIGNING_SECRET,
    resolve_quote_signing_secret,
)
from app.database import SessionLocal
from app.main import app
from app.models.distance_rate_config import DistanceRateConfig
from app.models.payment import Payment, PaymentStatus, PaymentType
from app.models.service_quote import SIGNATURE_VERSION, QuoteStatus, ServiceQuote
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.user import User
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.schemas.service_request_schema import QuoteCreate, ServiceRequestCreate
from app.services import quote_service as qs
from app.services.payment_service import PaymentService
from app.services.quote_service import (
    QuoteService,
    _LEGACY_QUOTE_SIGNING_SECRET,
    _apply_transition,
    _canonical_number,
    _digest,
    _legacy_signing_payload,
    _sign,
    _signing_payload,
    _verify_integrity,
)
from app.utils.jwt_handler import create_access_token
from tests import factories as f

LAT = 13.0827
LNG = 80.2707


# ======================================================================
# helpers
# ======================================================================
def bearer(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token({'user_id': user.id})}"}


def _make_rate(db, *, threshold=10.0, rate=20.0, tax=18.0, factor=2.0):
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
    config = _make_rate(db, threshold=threshold, rate=rate, tax=tax, factor=factor)
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

    # Patch objects captured at collection, not string targets resolved through
    # the current sys.modules.  Other suites deliberately reload app modules;
    # string patching would then replace a different module object than the one
    # the app under test actually calls.
    monkeypatch.setattr(qs, "_calculate_route", fake)
    # The legacy request path (no quote_id) resolves distance through the
    # route-module guard instead of the quote service boundary.
    monkeypatch.setattr(
        service_routes,
        "_maps_guard",
        lambda fn, *args, **kwargs: fake(None, None, None, None),
    )
    return state


def _create_quote(client, ctx, **overrides):
    response = client.post(
        "/service/quote", json=_quote_payload(ctx, **overrides), headers=bearer(ctx["user"])
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_request(client, ctx, quote, **overrides):
    return client.post(
        "/service/request",
        json=_request_payload(quote, **overrides),
        headers=bearer(ctx["user"]),
    )


def _quote_row(db, quote) -> ServiceQuote:
    quote_ref = quote["quote_id"] if isinstance(quote, dict) else quote
    db.expire_all()
    return db.query(ServiceQuote).filter(ServiceQuote.quote_ref == quote_ref).one()


def _resign(db, row: ServiceQuote) -> None:
    row.signature = _sign(row)
    db.commit()
    db.expire_all()


def _expire_legitimately(db, quote_ref: str, *, seconds_ago: int = 1) -> None:
    """Move a quote into the past and re-sign it, as a real clock would."""
    row = _quote_row(db, quote_ref)
    row.expires_at = datetime.utcnow() - timedelta(seconds=seconds_ago)
    _resign(db, row)


def _request_by_id(db, request_id: int) -> ServiceRequest:
    db.expire_all()
    return db.get(ServiceRequest, request_id)


def _quote_backed_request(client, ctx, quote, **overrides):
    response = _create_request(client, ctx, quote, **overrides)
    assert response.status_code == 201, response.text
    return response.json()


def _create_stage5_payment(db, *, user=None, plan=None):
    user = user or f.make_user(db)
    plan = plan or f.make_plan(db)
    payment, _, _, _ = PaymentService.create_subscription_payment(
        db, user=user, plan_id=plan.id
    )
    return user, plan, payment


# ======================================================================
# F1 - lifecycle HMAC protection
# ======================================================================
class TestLifecycleIntegrity:
    def test_version_2_payload_covers_every_lifecycle_field(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _quote_row(db, quote)

        payload = _signing_payload(row)
        for field in (
            "signature_version",
            "status",
            "consumed_at",
            "cancelled_at",
            "service_request_id",
        ):
            assert field in payload
        assert payload["signature_version"] == SIGNATURE_VERSION
        assert payload["status"] == "active"
        assert row.signature_version == SIGNATURE_VERSION

    def test_direct_status_modification_is_detected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        db.execute(
            text("UPDATE service_quotes SET status = 'cancelled' WHERE quote_ref = :r"),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        response = client.get(f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"]))
        assert response.status_code == 409
        assert _create_request(client, ctx, quote).status_code == 409
        assert db.query(ServiceRequest).count() == 0

    def test_direct_consumed_at_modification_is_detected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        db.execute(
            text("UPDATE service_quotes SET consumed_at = now() WHERE quote_ref = :r"),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        assert client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        ).status_code == 409

    def test_direct_cancelled_at_modification_is_detected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        db.execute(
            text("UPDATE service_quotes SET cancelled_at = now() WHERE quote_ref = :r"),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        assert _create_request(client, ctx, quote).status_code == 409

    def test_direct_service_request_id_modification_is_detected(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        other_request = f.make_request(db, ctx["user"])
        db.execute(
            text("UPDATE service_quotes SET service_request_id = :sid WHERE quote_ref = :r"),
            {"sid": other_request.id, "r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        assert _create_request(client, ctx, quote).status_code == 409

    def test_consumed_quote_cannot_be_reactivated_by_database_tampering(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert _create_request(client, ctx, quote).status_code == 201

        db.execute(
            text(
                "UPDATE service_quotes "
                "SET status = 'active', consumed_at = NULL, service_request_id = NULL "
                "WHERE quote_ref = :r"
            ),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        second = _create_request(client, ctx, quote)
        assert second.status_code == 409
        assert db.query(ServiceRequest).count() == 1
        # The database tampering is detected, never silently "repaired": the
        # forged lifecycle row stays as-is but is unusable for a second request.
        assert _quote_row(db, quote).status == QuoteStatus.active

    def test_tampered_quote_cannot_create_a_second_request(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        assert _create_request(client, ctx, quote).status_code == 201

        # Flip just the status field: the lifecycle MAC no longer matches.
        db.execute(
            text("UPDATE service_quotes SET status = 'active' WHERE quote_ref = :r"),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        assert _create_request(client, ctx, quote).status_code == 409
        assert db.query(ServiceRequest).count() == 1

    def test_legitimate_consumption_updates_the_signature(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        before = _quote_row(db, quote).signature

        assert _create_request(client, ctx, quote).status_code == 201

        fresh = _quote_row(db, quote)
        assert fresh.status == QuoteStatus.consumed
        assert fresh.signature != before
        _verify_integrity(fresh)

    def test_legitimate_cancellation_updates_the_signature(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        before = _quote_row(db, quote).signature

        response = client.post(
            f"/service/quote/{quote['quote_id']}/cancel", headers=bearer(ctx["user"])
        )
        assert response.status_code == 200, response.text
        assert response.json()["status"] == "cancelled"

        fresh = _quote_row(db, quote)
        assert fresh.status == QuoteStatus.cancelled
        assert fresh.cancelled_at is not None
        assert fresh.signature != before
        _verify_integrity(fresh)

    def test_legitimate_expiry_updates_the_signature(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        before = _quote_row(db, quote).signature

        _expire_legitimately(db, quote["quote_id"])
        mid = _quote_row(db, quote).signature

        response = client.get(f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"]))
        assert response.status_code == 200
        assert response.json()["status"] == "expired"

        fresh = _quote_row(db, quote)
        assert fresh.status == QuoteStatus.expired
        assert fresh.consumed_at is None
        assert fresh.signature != mid
        assert fresh.signature != before
        _verify_integrity(fresh)

    def test_invalid_lifecycle_transitions_are_rejected(self, db):
        user = f.make_user(db)
        now = datetime.utcnow()

        for terminal in (
            QuoteStatus.consumed,
            QuoteStatus.cancelled,
            QuoteStatus.expired,
        ):
            quote = ServiceQuote(
                quote_ref=f"test-{terminal.value}-{uuid.uuid4().hex}",
                signature="",
                signature_version=SIGNATURE_VERSION,
                user_id=user.id,
                request_type="claim",
                customer_address="1 Test Street",
                created_at=now,
                expires_at=now + timedelta(minutes=5),
                status=terminal,
                total_amount=Decimal("0.00"),
                extra_charge=Decimal("0.00"),
                tax_amount=Decimal("0.00"),
                base_amount=Decimal("0.00"),
            )
            with pytest.raises(HTTPException) as exc:
                _apply_transition(quote, QuoteStatus.active, now)
            assert exc.value.status_code == 409
            assert quote.status == terminal

            for other in (QuoteStatus.cancelled, QuoteStatus.expired):
                if other == terminal:
                    continue
                with pytest.raises(HTTPException) as exc:
                    _apply_transition(quote, other, now)
                assert exc.value.status_code == 409


# ======================================================================
# F2 - coordinate precision
# ======================================================================
class TestCoordinatePrecision:
    def test_seven_decimal_coordinates_remain_valid(self, client, db, stub_route):
        ctx = _setup(db)
        lat, lng = 13.0827123, 80.2707123
        quote = _create_quote(
            client, ctx, customer_latitude=lat, customer_longitude=lng
        )
        row = _quote_row(db, quote)
        assert row.customer_latitude == Decimal("13.0827123")
        _verify_integrity(row)

        response = _create_request(
            client, ctx, quote, customer_latitude=lat, customer_longitude=lng
        )
        assert response.status_code == 201, response.text

    def test_more_than_seven_decimals_are_normalized(self, client, db, stub_route):
        ctx = _setup(db)
        lat, lng = 13.08271236, 80.27071239
        quote = _create_quote(
            client, ctx, customer_latitude=lat, customer_longitude=lng
        )
        row = _quote_row(db, quote)
        # ROUND_HALF_UP to the persisted NUMERIC(10,7) scale.
        assert row.customer_latitude == Decimal("13.0827124")
        assert row.customer_longitude == Decimal("80.2707124")
        _verify_integrity(row)

        # The original full-precision input still matches the normalized row.
        response = _create_request(
            client, ctx, quote, customer_latitude=lat, customer_longitude=lng
        )
        assert response.status_code == 201, response.text

    def test_persisted_and_signed_representations_match(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(
            client, ctx, customer_latitude=13.08271236, customer_longitude=-80.27071239
        )
        raw_lat, raw_lng = db.execute(
            text(
                "SELECT customer_latitude::text, customer_longitude::text "
                "FROM service_quotes WHERE quote_ref = :r"
            ),
            {"r": quote["quote_id"]},
        ).one()
        row = _quote_row(db, quote)

        signed = _signing_payload(row)
        assert signed["customer_latitude"] == raw_lat
        assert signed["customer_longitude"] == raw_lng
        assert _canonical_number(row.customer_latitude) == raw_lat
        _verify_integrity(row)

    def test_negative_coordinates_work(self, client, db, stub_route):
        ctx = _setup(db)
        lat, lng = -13.0827123, -80.2707123
        quote = _create_quote(
            client, ctx, customer_latitude=lat, customer_longitude=lng
        )
        assert _quote_row(db, quote).customer_latitude == Decimal("-13.0827123")
        assert _quote_row(db, quote).customer_longitude == Decimal("-80.2707123")

        assert client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        ).status_code == 200
        assert _create_request(
            client, ctx, quote, customer_latitude=lat, customer_longitude=lng
        ).status_code == 201

    def test_boundary_coordinates_are_validated(self, client, db, stub_route):
        ctx = _setup(db)
        valid = _create_quote(
            client, ctx, customer_latitude=90.0, customer_longitude=180.0
        )
        assert _quote_row(db, valid).customer_latitude == Decimal("90.0000000")

        for lat, lng in ((90.0000001, 180.0), (0.0, 180.0000001), (0.0, 0.0)):
            response = client.post(
                "/service/quote",
                json=_quote_payload(
                    ctx, customer_latitude=lat, customer_longitude=lng
                ),
                headers=bearer(ctx["user"]),
            )
            assert response.status_code == 422, (lat, lng, response.text)

    def test_quote_can_be_retrieved_after_persistence(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        db.expire_all()
        response = client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        )
        assert response.status_code == 200
        assert response.json()["total_amount"] == quote["total_amount"]
        assert response.json()["status"] == "active"

    def test_quote_can_be_consumed_after_persistence(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        db.expire_all()
        response = _create_request(client, ctx, quote)
        assert response.status_code == 201, response.text
        assert _quote_row(db, quote).status == QuoteStatus.consumed


# ======================================================================
# F3/F4 - dedicated signing secret
# ======================================================================
class TestQuoteSigningSecret:
    def test_empty_secret_is_rejected(self):
        with pytest.raises(RuntimeError) as exc:
            resolve_quote_signing_secret("")
        assert "must not be empty" in str(exc.value)
        assert "QUOTE_SIGNING_SECRET" in str(exc.value)

    def test_whitespace_only_secret_is_rejected(self):
        with pytest.raises(RuntimeError) as exc:
            resolve_quote_signing_secret("  \t\n  ")
        assert "whitespace" in str(exc.value)

    def test_missing_secret_is_rejected(self):
        with pytest.raises(RuntimeError) as exc:
            resolve_quote_signing_secret(None)
        assert "Missing required environment variable: QUOTE_SIGNING_SECRET" in str(
            exc.value
        )

    def test_jwt_secret_is_not_silently_reused(self):
        # The resolver never falls back; an absent secret is a hard failure even
        # though JWT_SECRET_KEY is configured in this process.
        assert JWT_SECRET_KEY
        with pytest.raises(RuntimeError):
            resolve_quote_signing_secret(None)
        assert qs.QUOTE_SIGNING_SECRET != JWT_SECRET_KEY
        assert qs.QUOTE_SIGNING_SECRET == "test-quote-signing-secret-stage5-1"

    def test_dedicated_signing_secret_is_accepted(self):
        secret = "a-dedicated-and-random-quote-secret"
        assert resolve_quote_signing_secret(secret) == secret
        assert qs.QUOTE_SIGNING_SECRET.strip()
        assert qs._verify_integrity  # the module was initialised with a real key

    def test_legacy_quote_compatibility_is_verified_and_upgraded(
        self, client, db, stub_route
    ):
        assert QUOTE_LEGACY_SIGNING_SECRET
        assert _LEGACY_QUOTE_SIGNING_SECRET

        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _quote_row(db, quote)

        legacy_signature = _digest(
            _legacy_signing_payload(row), _LEGACY_QUOTE_SIGNING_SECRET
        )
        db.execute(
            text(
                "UPDATE service_quotes SET signature_version = 1, signature = :s "
                "WHERE quote_ref = :r"
            ),
            {"s": legacy_signature, "r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        # A pristine version 1 quote remains readable...
        assert client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        ).status_code == 200
        # ...and consumable, upgrading it to version 2 in the same transition.
        assert _create_request(client, ctx, quote).status_code == 201

        fresh = _quote_row(db, quote)
        assert fresh.signature_version == SIGNATURE_VERSION
        assert fresh.status == QuoteStatus.consumed
        _verify_integrity(fresh)

    def test_legacy_quote_with_tampered_lifecycle_is_rejected(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _quote_row(db, quote)
        legacy_signature = _digest(
            _legacy_signing_payload(row), _LEGACY_QUOTE_SIGNING_SECRET
        )
        db.execute(
            text(
                "UPDATE service_quotes SET signature_version = 1, signature = :s "
                "WHERE quote_ref = :r"
            ),
            {"s": legacy_signature, "r": quote["quote_id"]},
        )
        db.commit()
        db.execute(
            text("UPDATE service_quotes SET consumed_at = now() WHERE quote_ref = :r"),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        assert client.get(
            f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"])
        ).status_code == 409


# ======================================================================
# F5/F9 - payment idempotency ownership and uniqueness
# ======================================================================
class TestPaymentIdempotency:
    def test_cross_user_idempotency_key_cannot_reveal_another_payment(
        self, client, db
    ):
        plan = f.make_plan(db)
        alice = f.make_user(db)
        bob = f.make_user(db)

        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=alice, plan_id=plan.id, idempotency_key="shared-key"
        )
        second, _, _, _ = PaymentService.create_subscription_payment(
            db, user=bob, plan_id=plan.id, idempotency_key="shared-key"
        )

        assert first.txn_id != second.txn_id
        assert second.user_id == bob.id
        assert first.user_id == alice.id

        # The same is true through the API contract.
        response = client.post(
            "/payments/create",
            json={"plan_id": plan.id, "idempotency_key": "shared-key"},
            headers=bearer(bob),
        )
        assert response.status_code == 200, response.text
        assert response.json()["txn_id"] == second.txn_id
        assert response.json()["txn_id"] != first.txn_id

    def test_same_user_retries_remain_safe(self, client, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="retry-key"
        )
        second, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="retry-key"
        )
        assert first.txn_id == second.txn_id
        assert (
            db.query(Payment)
            .filter(Payment.idempotency_key == "retry-key")
            .count()
            == 1
        )

    def test_concurrent_same_key_requests_create_no_duplicate_intents(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        user_id, plan_id = user.id, plan.id
        barrier = threading.Barrier(2)
        results = []

        def worker():
            session = SessionLocal()
            try:
                local_user = session.get(User, user_id)
                barrier.wait(timeout=10)
                payment, _, _, _ = PaymentService.create_subscription_payment(
                    session,
                    user=local_user,
                    plan_id=plan_id,
                    idempotency_key="concurrent-key",
                )
                results.append(("ok", payment.txn_id))
            except Exception as exc:  # pragma: no cover - failure diagnostics
                session.rollback()
                results.append(("error", repr(exc)))
            finally:
                session.close()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(20)
            assert not thread.is_alive()

        oks = [txn for kind, txn in results if kind == "ok"]
        assert len(oks) == 2, results
        assert oks[0] == oks[1]
        db.expire_all()
        assert (
            db.query(Payment)
            .filter(
                Payment.user_id == user_id,
                Payment.idempotency_key == "concurrent-key",
            )
            .count()
            == 1
        )

    def test_database_uniqueness_constraints_work(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        now = datetime.utcnow()

        first = Payment(
            txn_id=str(uuid.uuid4()),
            user_id=user.id,
            plan_id=plan.id,
            payment_type=PaymentType.subscription,
            amount=Decimal("10.00"),
            status=PaymentStatus.pending,
            idempotency_key="db-key",
            expires_at=now + timedelta(minutes=10),
        )
        db.add(first)
        db.commit()

        duplicate = Payment(
            txn_id=str(uuid.uuid4()),
            user_id=user.id,
            plan_id=plan.id,
            payment_type=PaymentType.subscription,
            amount=Decimal("10.00"),
            status=PaymentStatus.pending,
            idempotency_key="db-key",
            expires_at=now + timedelta(minutes=10),
        )
        db.add(duplicate)
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.query(Payment).filter(Payment.idempotency_key == "db-key").count() == 1

        request = f.make_request(
            db, user, status=RequestStatus.payment_pending, extra_charge=100.0
        )
        first_extra = Payment(
            txn_id=str(uuid.uuid4()),
            user_id=user.id,
            payment_type=PaymentType.extra_charge,
            related_request_id=request.id,
            amount=Decimal("100.00"),
            status=PaymentStatus.pending,
            expires_at=now + timedelta(minutes=10),
        )
        db.add(first_extra)
        db.commit()

        second_extra = Payment(
            txn_id=str(uuid.uuid4()),
            user_id=user.id,
            payment_type=PaymentType.extra_charge,
            related_request_id=request.id,
            amount=Decimal("100.00"),
            status=PaymentStatus.pending,
            expires_at=now + timedelta(minutes=10),
        )
        db.add(second_extra)
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert (
            db.query(Payment)
            .filter(
                Payment.related_request_id == request.id,
                Payment.status == PaymentStatus.pending,
            )
            .count()
            == 1
        )

    def test_existing_duplicate_history_is_never_deleted(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        now = datetime.utcnow()

        history = [
            Payment(
                txn_id=str(uuid.uuid4()),
                user_id=user.id,
                plan_id=plan.id,
                payment_type=PaymentType.subscription,
                amount=Decimal("10.00"),
                status=PaymentStatus.failed,
                idempotency_key="historical-key",
                expires_at=now - timedelta(minutes=5),
            )
            for _ in range(2)
        ]
        db.add_all(history)
        db.commit()
        ids = sorted(row.id for row in history)

        fresh, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="historical-key"
        )
        # Stage 5.6G-1 contract: a reused key resolves idempotently to the most
        # recent existing terminal intent, never a new duplicate.  A genuinely
        # new attempt must use a different idempotency key.
        assert fresh.id == max(ids)
        assert fresh.status == PaymentStatus.failed

        db.expire_all()
        rows = (
            db.query(Payment)
            .filter(Payment.idempotency_key == "historical-key")
            .order_by(Payment.id)
            .all()
        )
        assert len(rows) == 2
        assert [row.id for row in rows] == ids
        assert [row.status for row in rows if row.id in ids] == [
            PaymentStatus.failed,
            PaymentStatus.failed,
        ]

        # The original business intent is still covered: a new key creates a
        # fresh pending intent without touching the preserved history.
        retry, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="historical-key-retry"
        )
        assert retry.status == PaymentStatus.pending
        assert retry.id not in ids
        db.expire_all()
        assert (
            db.query(Payment)
            .filter(Payment.idempotency_key == "historical-key")
            .count()
            == 2
        )


# ======================================================================
# F6/F7 - extra-charge intent duplication and eligibility
# ======================================================================
class TestExtraChargeIntent:
    def test_concurrent_intent_creation_produces_one_authoritative_intent(self, db):
        user = f.make_user(db)
        request = f.make_request(
            db, user, status=RequestStatus.payment_pending, extra_charge=236.0
        )
        user_id, request_id = user.id, request.id
        barrier = threading.Barrier(2)
        results = []

        def worker():
            session = SessionLocal()
            try:
                local_user = session.get(User, user_id)
                barrier.wait(timeout=10)
                payment, _, _ = PaymentService.create_extra_charge_payment(
                    session, user=local_user, request_id=request_id
                )
                results.append(("ok", payment.txn_id))
            except Exception as exc:  # pragma: no cover - failure diagnostics
                session.rollback()
                results.append(("error", repr(exc)))
            finally:
                session.close()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(20)
            assert not thread.is_alive()

        oks = [txn for kind, txn in results if kind == "ok"]
        assert len(oks) == 2, results
        assert oks[0] == oks[1]
        db.expire_all()
        assert (
            db.query(Payment)
            .filter(
                Payment.related_request_id == request_id,
                Payment.payment_type == PaymentType.extra_charge,
                Payment.status.in_(
                    (PaymentStatus.pending, PaymentStatus.pending_verification)
                ),
            )
            .count()
            == 1
        )

    def test_cancelled_request_cannot_create_a_payment_intent(self, db):
        user = f.make_user(db)
        request = f.make_request(
            db,
            user,
            status=RequestStatus.cancelled,
            extra_charge=236.0,
        )
        assert request.requires_payment is True

        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=user, request_id=request.id
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).count() == 0

    def test_completed_or_ineligible_request_cannot_create_a_new_intent(self, db):
        user = f.make_user(db)
        completed = f.make_request(
            db, user, status=RequestStatus.completed, extra_charge=100.0
        )
        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=user, request_id=completed.id
            )
        assert exc.value.status_code == 409

        ineligible = f.make_request(
            db, user, status=RequestStatus.waiting_for_assignment, extra_charge=100.0
        )
        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=user, request_id=ineligible.id
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).count() == 0

    def test_existing_eligible_request_payment_remains_functional(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        subscription = f.make_subscription(db, user, plan)
        request = f.make_request(
            db,
            user,
            status=RequestStatus.payment_pending,
            extra_charge=236.0,
            subscription=subscription,
        )

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=user, request_id=request.id
        )
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        admin = f.make_admin(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)

        db.expire_all()
        fresh = db.get(ServiceRequest, request.id)
        assert fresh.charge_paid is True
        assert fresh.status == RequestStatus.waiting_for_assignment

    def test_duplicate_approval_does_not_charge_or_activate_twice(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        subscription = f.make_subscription(db, user, plan)
        request = f.make_request(
            db,
            user,
            status=RequestStatus.payment_pending,
            extra_charge=100.0,
            subscription=subscription,
        )
        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=user, request_id=request.id
        )
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        admin = f.make_admin(db)

        first = PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=True
        )
        second = PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=True
        )

        assert first.status == PaymentStatus.success
        assert second.status == PaymentStatus.success
        assert db.query(Payment).filter(Payment.status == PaymentStatus.success).count() == 1
        db.expire_all()
        fresh_request = db.get(ServiceRequest, request.id)
        fresh_subscription = db.get(UserSubscription, subscription.id)
        assert fresh_request.charge_paid is True
        assert fresh_request.status == RequestStatus.waiting_for_assignment
        assert fresh_subscription.used_visits == 0


# ======================================================================
# F8 - expiry / consumption races
# ======================================================================
def _consume_then_expire_race(*, user_id: int, quote_ref: str, payload):
    """Consumption holds the row lock while the quote expires; expiry then runs.

    The consumption transaction is deliberately kept open past ``expires_at``.
    ``get_quote`` performs its non-locking read (sees an expired clock), then
    blocks on the row lock until consumption commits. This is the exact
    ordering that used to let expiry overwrite a successful consumption.
    """
    result = {}
    consumed = threading.Event()
    release = threading.Event()

    def consume_worker():
        session = SessionLocal()
        try:
            local_user = session.get(User, user_id)
            request = QuoteService.consume_for_request(
                session, user=local_user, payload=payload
            )
            result["request_id"] = request.id
            consumed.set()
            release.wait(15)
            session.commit()
        except Exception as exc:  # pragma: no cover - failure diagnostics
            session.rollback()
            result["consume_error"] = repr(exc)
        finally:
            consumed.set()
            session.close()

    consumer = threading.Thread(target=consume_worker)
    consumer.start()
    assert consumed.wait(10), "consumption never reached the lock-holding point"
    assert "consume_error" not in result, result

    time.sleep(2.7)  # cross the committed expires_at boundary

    def expire_worker():
        session = SessionLocal()
        try:
            local_user = session.get(User, user_id)
            quote = QuoteService.get_quote(
                session, user=local_user, quote_ref=quote_ref
            )
            result["expire_status"] = quote.status
        except Exception as exc:  # pragma: no cover - failure diagnostics
            session.rollback()
            result["expire_error"] = repr(exc)
        finally:
            session.close()

    expirer = threading.Thread(target=expire_worker)
    expirer.start()
    time.sleep(0.4)  # let expiry block on the consumption row lock
    release.set()
    consumer.join(20)
    expirer.join(20)
    assert not consumer.is_alive() and not expirer.is_alive()
    return result


def _expire_then_consume_race(*, user_id: int, quote_ref: str, payload):
    """Expiry holds the row lock first; consumption must wait and then fail.

    This reproduces the locked branch of ``get_quote`` with the same trusted
    ``_verify_integrity`` + ``_apply_transition`` helpers it uses.
    """
    result = {}
    locked = threading.Event()
    release = threading.Event()

    def expire_worker():
        session = SessionLocal()
        try:
            session.get(User, user_id)
            quote = (
                session.query(ServiceQuote)
                .filter(ServiceQuote.quote_ref == quote_ref)
                .with_for_update()
                .one()
            )
            _verify_integrity(quote)
            _apply_transition(quote, QuoteStatus.expired, datetime.utcnow())
            session.flush()
            locked.set()
            release.wait(15)
            session.commit()
        except Exception as exc:  # pragma: no cover - failure diagnostics
            session.rollback()
            result["expire_error"] = repr(exc)
        finally:
            locked.set()
            session.close()

    expirer = threading.Thread(target=expire_worker)
    expirer.start()
    assert locked.wait(10), "expiry never acquired the row lock"
    assert "expire_error" not in result, result

    def consume_worker():
        session = SessionLocal()
        try:
            local_user = session.get(User, user_id)
            QuoteService.consume_for_request(
                session, user=local_user, payload=payload
            )
            result["consumed"] = True
            session.commit()
        except HTTPException as exc:
            session.rollback()
            result["consume_status"] = exc.status_code
        except Exception as exc:  # pragma: no cover - failure diagnostics
            session.rollback()
            result["consume_error"] = repr(exc)
        finally:
            session.close()

    consumer = threading.Thread(target=consume_worker)
    consumer.start()
    time.sleep(0.5)  # consumer is now blocked on the expiry row lock
    release.set()
    expirer.join(20)
    consumer.join(20)
    assert not expirer.is_alive() and not consumer.is_alive()
    return result


class TestExpiryRace:
    def test_expiry_and_consumption_are_transactionally_consistent(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _quote_row(db, quote)
        row.expires_at = datetime.utcnow() + timedelta(seconds=2)
        _resign(db, row)

        payload = ServiceRequestCreate(**_request_payload(quote))
        result = _consume_then_expire_race(
            user_id=ctx["user"].id,
            quote_ref=quote["quote_id"],
            payload=payload,
        )

        assert "consume_error" not in result, result
        assert "expire_error" not in result, result
        assert result.get("request_id")
        assert result.get("expire_status") == QuoteStatus.consumed

        fresh = _quote_row(db, quote)
        request = _request_by_id(db, result["request_id"])
        assert fresh.status == QuoteStatus.consumed
        assert fresh.consumed_at is not None
        assert fresh.cancelled_at is None
        assert fresh.service_request_id == request.id
        assert request.quote_ref == quote["quote_id"]
        _verify_integrity(fresh)

    def test_expiry_cannot_overwrite_consumed_status(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        row = _quote_row(db, quote)
        row.expires_at = datetime.utcnow() + timedelta(seconds=2)
        _resign(db, row)

        payload = ServiceRequestCreate(**_request_payload(quote))
        result = _consume_then_expire_race(
            user_id=ctx["user"].id,
            quote_ref=quote["quote_id"],
            payload=payload,
        )

        fresh = _quote_row(db, quote)
        assert fresh.status == QuoteStatus.consumed
        assert result.get("expire_status") == QuoteStatus.consumed
        assert db.query(ServiceRequest).count() == 1

    def test_consumption_cannot_succeed_after_expiry(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        _expire_legitimately(db, quote["quote_id"])

        payload = ServiceRequestCreate(**_request_payload(quote))
        result = _expire_then_consume_race(
            user_id=ctx["user"].id,
            quote_ref=quote["quote_id"],
            payload=payload,
        )

        assert "consume_error" not in result, result
        assert result.get("consume_status") == 410
        assert "consumed" not in result

        fresh = _quote_row(db, quote)
        assert fresh.status == QuoteStatus.expired
        assert fresh.consumed_at is None
        assert fresh.service_request_id is None
        assert db.query(ServiceRequest).count() == 0

    def test_lifecycle_hmac_remains_valid_after_expiry(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        _expire_legitimately(db, quote["quote_id"])

        response = client.get(f"/service/quote/{quote['quote_id']}", headers=bearer(ctx["user"]))
        assert response.status_code == 200
        assert response.json()["status"] == "expired"

        fresh = _quote_row(db, quote)
        _verify_integrity(fresh)
        assert fresh.status == QuoteStatus.expired

    def test_no_inconsistent_lifecycle_timestamps(self, client, db, stub_route):
        ctx = _setup(db)

        consumed_quote = _create_quote(client, ctx)
        assert _create_request(client, ctx, consumed_quote).status_code == 201
        consumed = _quote_row(db, consumed_quote)
        assert consumed.status == QuoteStatus.consumed
        assert consumed.consumed_at is not None
        assert consumed.cancelled_at is None
        assert consumed.service_request_id is not None

        cancelled_quote = _create_quote(client, ctx, customer_latitude=13.1)
        cancel = client.post(
            f"/service/quote/{cancelled_quote['quote_id']}/cancel",
            headers=bearer(ctx["user"]),
        )
        assert cancel.status_code == 200
        cancelled = _quote_row(db, cancelled_quote)
        assert cancelled.status == QuoteStatus.cancelled
        assert cancelled.cancelled_at is not None
        assert cancelled.consumed_at is None
        assert cancelled.service_request_id is None

        expired_quote = _create_quote(client, ctx, customer_latitude=13.2)
        _expire_legitimately(db, expired_quote["quote_id"])
        client.get(
            f"/service/quote/{expired_quote['quote_id']}", headers=bearer(ctx["user"])
        )
        expired = _quote_row(db, expired_quote)
        assert expired.status == QuoteStatus.expired
        assert expired.consumed_at is None
        assert expired.cancelled_at is None
        assert expired.service_request_id is None


# ======================================================================
# F10 - UTR conflicts
# ======================================================================
class TestUtrConflicts:
    def test_reused_successful_utr_is_rejected(self, db):
        user, plan, first = _create_stage5_payment(db)
        shared = f.utr()
        PaymentService.submit_payment(db, user=user, txn_id=first.txn_id, utr_number=shared)
        admin = f.make_admin(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=first.txn_id, approve=True)

        _, _, second = _create_stage5_payment(db, user=user, plan=plan)
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(
                db, user=user, txn_id=second.txn_id, utr_number=shared
            )
        assert exc.value.status_code == 409

    def test_reused_pending_utr_is_rejected_safely(self, db):
        user, plan, first = _create_stage5_payment(db)
        shared = f.utr()
        PaymentService.submit_payment(db, user=user, txn_id=first.txn_id, utr_number=shared)
        assert first.status == PaymentStatus.pending_verification

        _, _, second = _create_stage5_payment(db, user=user, plan=f.make_plan(db))
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(
                db, user=user, txn_id=second.txn_id, utr_number=shared
            )
        assert exc.value.status_code == 409
        # The rejection is a clean 409, never a database 500 or a silent claim.
        assert db.query(Payment).filter(Payment.utr_number == shared).count() == 1

    def test_concurrent_utr_conflicts_are_handled_safely(self, db):
        user = f.make_user(db)
        plan_a = f.make_plan(db)
        plan_b = f.make_plan(db)
        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan_a.id
        )
        second, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan_b.id
        )
        shared = f.utr()
        user_id = user.id
        txn_ids = [first.txn_id, second.txn_id]
        barrier = threading.Barrier(2)
        results = []

        def submit_worker(txn_id):
            session = SessionLocal()
            try:
                local_user = session.get(User, user_id)
                barrier.wait(timeout=10)
                PaymentService.submit_payment(
                    session,
                    user=local_user,
                    txn_id=txn_id,
                    utr_number=shared,
                )
                results.append(("ok", txn_id))
            except HTTPException as exc:
                session.rollback()
                results.append(("conflict", exc.status_code))
            except Exception as exc:  # pragma: no cover - failure diagnostics
                session.rollback()
                results.append(("error", repr(exc)))
            finally:
                session.close()

        workers = [lambda t=txn: submit_worker(t) for txn in txn_ids]
        threads = [threading.Thread(target=worker) for worker in workers]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(20)
            assert not thread.is_alive()

        assert sorted(kind for kind, _ in results) == ["conflict", "ok"], results
        assert [value for kind, value in results if kind == "conflict"] == [409]

        db.expire_all()
        assert db.query(Payment).filter(Payment.utr_number == shared).count() == 1

    def test_database_unique_violation_maps_to_http_409(self, client):
        before = len(app.router.routes)

        def conflict():
            raise IntegrityError(
                "INSERT INTO payments ...", {}, Exception("duplicate key value")
            )

        app.add_api_route("/__stage51_integrity_conflict__", conflict, methods=["GET"])
        try:
            response = client.get("/__stage51_integrity_conflict__")
        finally:
            del app.router.routes[before:]

        assert response.status_code == 409
        body = response.text.lower()
        assert "duplicate key" not in body
        assert "insert into" not in body
        assert "postgres" not in body

    def test_transaction_rollback_is_correct(self, db):
        user, plan, first = _create_stage5_payment(db)
        shared = f.utr()
        PaymentService.submit_payment(db, user=user, txn_id=first.txn_id, utr_number=shared)

        _, _, second = _create_stage5_payment(db, user=user, plan=f.make_plan(db))
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(
                db, user=user, txn_id=second.txn_id, utr_number=shared
            )
        assert exc.value.status_code == 409

        db.expire_all()
        fresh = db.query(Payment).filter(Payment.txn_id == second.txn_id).one()
        assert fresh.status == PaymentStatus.pending
        assert fresh.utr_number is None
        assert (fresh.attempts or 0) == 0

        # The session is usable and the customer can submit a valid reference.
        retried = PaymentService.submit_payment(
            db, user=user, txn_id=second.txn_id, utr_number=f.utr()
        )
        assert retried.status == PaymentStatus.pending_verification


# ======================================================================
# F12 - quote-to-request-to-payment integrity
# ======================================================================
class TestQuoteRequestPaymentIntegrity:
    def test_quote_amount_is_copied_correctly(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        request = _request_by_id(db, body["id"])
        assert float(request.total_amount) == quote["total_amount"]
        assert float(request.base_amount) == quote["base_amount"]
        assert float(request.extra_charge) == quote["extra_charge"]
        assert float(request.tax_amount) == quote["tax_amount"]
        assert float(request.distance_km) == quote["distance_km"]
        assert request.quote_ref == quote["quote_id"]

    def test_request_quote_reference_remains_associated(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)
        request = _request_by_id(db, body["id"])

        signed = QuoteService.verified_quote_for_request(db, request=request)
        assert signed is not None
        assert signed.quote_ref == quote["quote_id"]
        assert signed.service_request_id == request.id
        assert request.quote_ref == signed.quote_ref

    def test_modified_request_amount_is_detected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        db.execute(
            text("UPDATE service_requests SET total_amount = 1.00 WHERE id = :i"),
            {"i": body["id"]},
        )
        db.commit()
        db.expire_all()

        request = _request_by_id(db, body["id"])
        signed = QuoteService.verified_quote_for_request(db, request=request)
        with pytest.raises(HTTPException) as exc:
            QuoteService.assert_request_matches_quote(request, signed)
        assert exc.value.status_code == 409

        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=ctx["user"], request_id=body["id"]
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).count() == 0

    def test_payment_amount_matches_the_authoritative_quote(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body["id"]
        )
        assert float(payment.amount) == quote["total_amount"]
        assert payment.currency == quote["currency"]

        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )

        # Tamper with the amount after submission: approval must refuse it.
        db.execute(
            text("UPDATE payments SET amount = 1.00 WHERE id = :i"), {"i": payment.id}
        )
        db.commit()
        db.expire_all()

        admin = f.make_admin(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(
                db, admin=admin, txn_id=payment.txn_id, approve=True
            )
        assert exc.value.status_code == 409
        db.rollback()

        db.expire_all()
        assert (
            db.query(Payment).filter(Payment.txn_id == payment.txn_id).one().status
            == PaymentStatus.pending_verification
        )
        assert _request_by_id(db, body["id"]).charge_paid is False

    def test_payment_currency_matches_the_quote_currency(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body["id"]
        )
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )
        db.execute(
            text("UPDATE payments SET currency = 'USD' WHERE id = :i"),
            {"i": payment.id},
        )
        db.commit()
        db.expire_all()

        admin = f.make_admin(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(
                db, admin=admin, txn_id=payment.txn_id, approve=True
            )
        assert exc.value.status_code == 409
        db.rollback()
        db.expire_all()
        assert (
            db.query(Payment).filter(Payment.txn_id == payment.txn_id).one().status
            == PaymentStatus.pending_verification
        )

    def test_approval_detects_tampered_request_pricing(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body["id"]
        )
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )
        db.execute(
            text("UPDATE service_requests SET total_amount = 5.00 WHERE id = :i"),
            {"i": body["id"]},
        )
        db.commit()
        db.expire_all()

        admin = f.make_admin(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(
                db, admin=admin, txn_id=payment.txn_id, approve=True
            )
        assert exc.value.status_code == 409
        db.rollback()
        db.expire_all()
        assert _request_by_id(db, body["id"]).charge_paid is False

    def test_legacy_request_without_a_quote_continues_to_work(self, db, client, stub_route):
        stub_route["km"] = 4.0
        ctx = _setup(db)
        # Create a request through the legacy (recalculation) path: no quote_id.
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
        body = response.json()
        request = _request_by_id(db, body["id"])
        assert request.quote_ref is None
        assert QuoteService.verified_quote_for_request(db, request=request) is None

        # A legacy unpaid charge still uses the existing request snapshot.
        request.extra_charge = Decimal("100.00")
        request.total_amount = Decimal("100.00")
        request.charge_paid = False
        request.status = RequestStatus.payment_pending
        db.commit()
        db.refresh(request)

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=request.id
        )
        assert float(payment.amount) == 100.0
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )
        admin = f.make_admin(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)

        db.expire_all()
        assert _request_by_id(db, request.id).charge_paid is True

    def test_existing_payment_verification_behaviour_remains_intact(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        payment, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        admin = f.make_admin(db)

        verified = PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=True
        )
        assert verified.status == PaymentStatus.success

        subscription = (
            db.query(UserSubscription)
            .filter(UserSubscription.user_id == user.id)
            .one()
        )
        assert subscription.status == SubscriptionStatus.active
        assert subscription.total_visits == 4

        # Duplicate approval remains an idempotent no-op.
        again = PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=True
        )
        assert again.status == PaymentStatus.success
        assert (
            db.query(UserSubscription)
            .filter(UserSubscription.user_id == user.id)
            .count()
            == 1
        )


# ======================================================================
# Real PostgreSQL concurrency: quote consumption
# ======================================================================
def test_concurrent_quote_consumption_allows_exactly_one_request(
    client, db, stub_route
):
    ctx = _setup(db)
    quote = _create_quote(client, ctx)
    payload = ServiceRequestCreate(**_request_payload(quote))
    user_id = ctx["user"].id
    barrier = threading.Barrier(2)
    results = []

    def worker():
        session = SessionLocal()
        try:
            local_user = session.get(User, user_id)
            barrier.wait(timeout=10)
            request = QuoteService.consume_for_request(
                session, user=local_user, payload=payload
            )
            session.commit()
            results.append(("ok", request.id))
        except HTTPException as exc:
            session.rollback()
            results.append(("conflict", exc.status_code))
        except Exception as exc:  # pragma: no cover - failure diagnostics
            session.rollback()
            results.append(("error", repr(exc)))
        finally:
            session.close()

    threads = [threading.Thread(target=worker) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(20)
        assert not thread.is_alive()

    assert sorted(kind for kind, _ in results) == ["conflict", "ok"], results
    assert [value for kind, value in results if kind == "conflict"][0] in (409, 410)

    db.expire_all()
    assert db.query(ServiceRequest).filter(ServiceRequest.user_id == user_id).count() == 1
    assert _quote_row(db, quote).status == QuoteStatus.consumed


# ======================================================================
# Stage 5.3 - two-way quote/request association regression tests (A-I)
# ======================================================================
class TestStage53QuoteAssociationBypass:
    """Direct-SQL tampering must never downgrade a quote-backed request."""

    def test_a_forward_reference_removed_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        db.execute(
            text("UPDATE service_requests SET quote_ref = NULL WHERE id = :i"),
            {"i": body["id"]},
        )
        db.commit()
        db.expire_all()

        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=ctx["user"], request_id=body["id"]
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).count() == 0

    def test_b_forward_reference_removed_and_amount_changed_is_rejected(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        db.execute(
            text(
                "UPDATE service_requests "
                "SET quote_ref = NULL, total_amount = 1.00 WHERE id = :i"
            ),
            {"i": body["id"]},
        )
        db.commit()
        db.expire_all()

        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=ctx["user"], request_id=body["id"]
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).count() == 0
        assert db.query(Payment).filter(Payment.amount == Decimal("1.00")).count() == 0

    def test_c_approval_bypass_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body["id"]
        )
        signed_amount = payment.amount
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )

        db.execute(
            text(
                "UPDATE service_requests "
                "SET quote_ref = NULL, total_amount = 1.00 WHERE id = :i"
            ),
            {"i": body["id"]},
        )
        db.commit()
        db.expire_all()

        admin = f.make_admin(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(
                db, admin=admin, txn_id=payment.txn_id, approve=True
            )
        assert exc.value.status_code == 409

        db.expire_all()
        fresh_payment = db.get(Payment, payment.id)
        fresh_request = _request_by_id(db, body["id"])
        assert fresh_payment.status == PaymentStatus.pending_verification
        assert fresh_payment.amount == signed_amount
        assert fresh_request.charge_paid is False
        assert fresh_request.status == RequestStatus.payment_pending

    def test_d_reverse_reference_corruption_is_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body["id"]
        )
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )

        # Corrupt the reverse link and re-sign. Rejection must therefore come
        # from two-sided association validation, not merely from the F1 HMAC.
        db.execute(
            text(
                "UPDATE service_quotes SET service_request_id = NULL "
                "WHERE quote_ref = :r"
            ),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()
        row = _quote_row(db, quote)
        row.signature = _sign(row)
        db.commit()
        db.expire_all()

        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=ctx["user"], request_id=body["id"]
            )
        assert exc.value.status_code == 409

        admin = f.make_admin(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(
                db, admin=admin, txn_id=payment.txn_id, approve=True
            )
        assert exc.value.status_code == 409

        db.expire_all()
        assert db.get(Payment, payment.id).status == PaymentStatus.pending_verification
        assert _request_by_id(db, body["id"]).charge_paid is False
        assert db.query(Payment).count() == 1

    def test_e_cross_linked_references_are_rejected(self, client, db, stub_route):
        ctx = _setup(db)
        quote_a = _create_quote(client, ctx)
        quote_b = _create_quote(client, ctx)
        body_a = _quote_backed_request(client, ctx, quote_a)
        body_b = _quote_backed_request(client, ctx, quote_b)

        payment_a, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body_a["id"]
        )
        payment_b, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body_b["id"]
        )
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment_a.txn_id, utr_number=f.utr()
        )
        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment_b.txn_id, utr_number=f.utr()
        )

        # Request A now points at quote B; request B loses its forward link.
        # Quote reverse links are left untouched, so the two sides disagree.
        db.execute(
            text("UPDATE service_requests SET quote_ref = NULL WHERE id = :b"),
            {"b": body_b["id"]},
        )
        db.execute(
            text("UPDATE service_requests SET quote_ref = :qb WHERE id = :a"),
            {"qb": quote_b["quote_id"], "a": body_a["id"]},
        )
        db.commit()
        db.expire_all()

        for body in (body_a, body_b):
            with pytest.raises(HTTPException) as exc:
                PaymentService.create_extra_charge_payment(
                    db, user=ctx["user"], request_id=body["id"]
                )
            assert exc.value.status_code == 409

        admin = f.make_admin(db)
        for payment in (payment_a, payment_b):
            with pytest.raises(HTTPException) as exc:
                PaymentService.verify_payment(
                    db, admin=admin, txn_id=payment.txn_id, approve=True
                )
            assert exc.value.status_code == 409

        db.expire_all()
        for payment in (payment_a, payment_b):
            assert (
                db.get(Payment, payment.id).status
                == PaymentStatus.pending_verification
            )
        for body in (body_a, body_b):
            assert _request_by_id(db, body["id"]).charge_paid is False

    def test_f_quote_deletion_or_missing_association_is_rejected(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)

        db.execute(
            text("DELETE FROM service_quotes WHERE quote_ref = :r"),
            {"r": quote["quote_id"]},
        )
        db.commit()
        db.expire_all()

        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(
                db, user=ctx["user"], request_id=body["id"]
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).count() == 0

    def test_g_genuine_legacy_request_keeps_legacy_workflow(self, db):
        user = f.make_user(db)
        request = f.make_request(
            db, user, status=RequestStatus.payment_pending, extra_charge=100.0
        )
        assert request.quote_ref is None
        assert (
            db.query(ServiceQuote)
            .filter(ServiceQuote.service_request_id == request.id)
            .count()
            == 0
        )
        assert QuoteService.verified_quote_for_request(db, request=request) is None

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=user, request_id=request.id
        )
        assert payment.amount == Decimal("100.00")
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        verified = PaymentService.verify_payment(
            db, admin=f.make_admin(db), txn_id=payment.txn_id, approve=True
        )

        assert verified.status == PaymentStatus.success
        assert _request_by_id(db, request.id).charge_paid is True

    def test_h_normal_quote_backed_request_uses_signed_amount(
        self, client, db, stub_route
    ):
        ctx = _setup(db)
        quote = _create_quote(client, ctx)
        body = _quote_backed_request(client, ctx, quote)
        signed_amount = Decimal(str(quote["total_amount"]))

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=ctx["user"], request_id=body["id"]
        )
        assert payment.amount == signed_amount
        assert payment.currency == quote["currency"]

        PaymentService.submit_payment(
            db, user=ctx["user"], txn_id=payment.txn_id, utr_number=f.utr()
        )
        verified = PaymentService.verify_payment(
            db, admin=f.make_admin(db), txn_id=payment.txn_id, approve=True
        )

        assert verified.status == PaymentStatus.success
        db.expire_all()
        fresh_request = _request_by_id(db, body["id"])
        assert fresh_request.charge_paid is True
        assert fresh_request.status == RequestStatus.waiting_for_assignment

    def test_i_concurrent_validation_and_database_constraints(self, client, db, stub_route):
        ctx = _setup(db)
        quote_a = _create_quote(client, ctx)
        quote_b = _create_quote(client, ctx)
        body_a = _quote_backed_request(client, ctx, quote_a)
        body_b = _quote_backed_request(client, ctx, quote_b)

        # The database must reject duplicate forward and reverse associations.
        with pytest.raises(IntegrityError):
            db.execute(
                text("UPDATE service_requests SET quote_ref = :r WHERE id = :i"),
                {"r": quote_a["quote_id"], "i": body_b["id"]},
            )
            db.commit()
        db.rollback()

        with pytest.raises(IntegrityError):
            db.execute(
                text(
                    "UPDATE service_quotes SET service_request_id = :sid "
                    "WHERE quote_ref = :r"
                ),
                {"sid": body_a["id"], "r": quote_b["quote_id"]},
            )
            db.commit()
        db.rollback()
        db.expire_all()

        # Tamper the amount while the quote association is still intact.
        db.execute(
            text("UPDATE service_requests SET total_amount = 1.00 WHERE id = :i"),
            {"i": body_a["id"]},
        )
        db.commit()
        db.expire_all()

        user_id = ctx["user"].id
        request_id = body_a["id"]
        barrier = threading.Barrier(2)
        results = []

        def intent_worker():
            session = SessionLocal()
            try:
                user = session.get(User, user_id)
                barrier.wait(timeout=10)
                try:
                    PaymentService.create_extra_charge_payment(
                        session, user=user, request_id=request_id
                    )
                    results.append(("ok", "intent"))
                except HTTPException as exc:
                    session.rollback()
                    results.append(("rejected", exc.status_code))
                except Exception as exc:  # pragma: no cover - failure diagnostics
                    session.rollback()
                    results.append(("error", repr(exc)))
            finally:
                session.close()

        def tamper_worker():
            session = SessionLocal()
            try:
                barrier.wait(timeout=10)
                session.execute(
                    text("UPDATE service_requests SET quote_ref = NULL WHERE id = :i"),
                    {"i": request_id},
                )
                session.commit()
                results.append(("tampered", True))
            except Exception as exc:  # pragma: no cover - failure diagnostics
                session.rollback()
                results.append(("tamper_error", repr(exc)))
            finally:
                session.close()

        threads = [
            threading.Thread(target=intent_worker),
            threading.Thread(target=tamper_worker),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(20)
        assert all(not thread.is_alive() for thread in threads)

        assert ("ok", "intent") not in results, results
        assert ("rejected", 409) in results, results
        assert ("tampered", True) in results, results

        db.expire_all()
        assert db.query(Payment).count() == 0
        assert (
            db.query(ServiceQuote)
            .filter(ServiceQuote.service_request_id == request_id)
            .count()
            == 1
        )
