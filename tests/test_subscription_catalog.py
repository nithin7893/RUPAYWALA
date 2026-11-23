from datetime import timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import func, text

from app.models.subscription_plan import SubscriptionPlan
from app.models.service_request import ServiceRequest
from app.models.user_subscription import UserSubscription
from app.services.payment_service import PaymentService
from app.services.plan_catalog import seed_subscription_plans
from app.services.pricing_service import calculate_extra_charge
from app.services.subscription_service import (
    SubscriptionService,
    plan_entitlements,
)
from app.utils.jwt_handler import create_access_token
from tests import factories as f


EXPECTED_PRICES = {
    "silver": 365,
    "gold": 599,
    "platinum": 799,
    "diamond": 999,
    "family": 1299,
    "elite": 1499,
    "premium_family": 1999,
}


def test_catalog_is_idempotent_and_archives_non_catalog_plans(db):
    legacy = f.make_plan(db, plan_name="Historical plan")

    seed_subscription_plans(db)
    seed_subscription_plans(db)

    active = (
        db.query(SubscriptionPlan)
        .filter(SubscriptionPlan.is_active.is_(True))
        .all()
    )
    assert {plan.code: int(plan.price) for plan in active} == EXPECTED_PRICES
    assert db.query(SubscriptionPlan).filter_by(code="silver").count() == 1
    db.refresh(legacy)
    assert legacy.is_active is False


def test_catalog_repairs_a_behind_postgres_id_sequence(db):
    legacy = f.make_plan(db, plan_name="Historical plan")
    db.flush()
    db.execute(
        text(
            "SELECT setval(pg_get_serial_sequence('subscription_plans', 'id'), 1, false)"
        )
    )

    seed_subscription_plans(db)

    max_id = db.query(func.max(SubscriptionPlan.id)).scalar()
    probe = SubscriptionPlan(
        code="sequence-test",
        plan_name="Sequence test",
        price=0,
        visits_included=0,
        validity_days=365,
        is_active=True,
    )
    db.add(probe)
    db.flush()

    assert max_id >= legacy.id
    assert probe.id > max_id


def test_plan_entitlements_match_the_catalog(db):
    seed_subscription_plans(db)
    plans = {
        plan.code: plan
        for plan in db.query(SubscriptionPlan).filter(
            SubscriptionPlan.code.in_(EXPECTED_PRICES)
        )
    }

    assert [plans[key].visits_included for key in ("silver", "gold", "platinum")] == [
        0,
        0,
        0,
    ]
    assert plans["diamond"].visits_included == 3
    assert plans["diamond"].included_visit_distance_km == 10
    assert plans["family"].visits_included == 5
    assert plans["family"].max_family_members == 5
    assert plans["elite"].visits_included == 3
    assert plans["elite"].document_storage is True
    assert plans["premium_family"].visits_included == 5
    assert plans["premium_family"].additional_visits is None
    assert plans["premium_family"].max_family_members is None


def test_seed_preserves_admin_configured_premium_values_and_activation(db):
    seed_subscription_plans(db)
    premium = db.query(SubscriptionPlan).filter_by(code="premium_family").one()
    silver = db.query(SubscriptionPlan).filter_by(code="silver").one()
    premium.additional_visits = 2
    premium.max_family_members = 8
    silver.is_active = False
    db.commit()

    seed_subscription_plans(db)
    db.refresh(premium)
    db.refresh(silver)
    assert premium.additional_visits == 2
    assert premium.max_family_members == 8
    assert "configured" in " ".join(premium.features).lower()
    assert silver.is_active is False

    premium.additional_visits = None
    premium.max_family_members = None
    silver.is_active = True
    db.commit()
    seed_subscription_plans(db)


def test_digital_entitlement_does_not_consume_a_home_visit(db):
    user = f.make_user(db)
    plan = f.make_plan(db, visits_included=0)
    plan.document_verification = True
    subscription = f.make_subscription(db, user, plan, total_visits=0)
    subscription.entitlements_snapshot = plan_entitlements(plan)
    db.flush()

    resolved, visit_required = SubscriptionService.authorize_request(
        db, user.id, "document_verification"
    )
    assert resolved.id == subscription.id
    assert visit_required is False

    with pytest.raises(HTTPException) as exc:
        SubscriptionService.authorize_request(db, user.id, "online_submission")
    assert exc.value.status_code == 403


def test_distance_plan_override_keeps_round_trip_pricing(db):
    from app.routes.service_routes import _pricing_config_for_user

    user = f.make_user(db)
    plan = f.make_plan(db)
    plan.included_visit_distance_km = 10
    subscription = f.make_subscription(db, user, plan)
    subscription.entitlements_snapshot = plan_entitlements(plan)
    db.flush()

    config = _pricing_config_for_user(db, user.id)
    assert config.threshold_km == 10
    assert calculate_extra_charge(
        distance_km=12,
        threshold_km=config.threshold_km,
        charge_per_km=config.charge_per_km,
        round_trip_factor=config.round_trip_factor,
    ) == config.charge_per_km * 2 * config.round_trip_factor


def test_digital_service_request_is_allowed_without_home_visits(client, db):
    user = f.make_user(db)
    plan = f.make_plan(db, visits_included=0)
    subscription = f.make_subscription(db, user, plan, total_visits=0)
    subscription.entitlements_snapshot = plan_entitlements(plan)
    policy = f.make_policy(db, user)
    branch = f.make_branch(db)
    db.commit()
    headers = {
        "Authorization": f"Bearer {create_access_token({'user_id': user.id})}"
    }

    response = client.post(
        "/service/request",
        headers=headers,
        json={
            "policy_id": policy.id,
            "request_type": "claim_form_assistance",
            "customer_latitude": 13.0827,
            "customer_longitude": 80.2707,
            "customer_address": "1 Test Street",
            "branch_id": branch.id,
        },
    )

    assert response.status_code == 201
    request = db.get(ServiceRequest, response.json()["id"])
    assert request.visit_required is False
    from app.services.visit_service import VisitService

    assert VisitService.consume_for_request(db, request) is False


def test_renewal_preserves_the_previous_period_and_snapshots_new_benefits(db):
    user = f.make_user(db)
    first_plan = f.make_plan(db, plan_name="First period", price=365, visits_included=3)
    first_payment, _, _, _ = PaymentService.create_subscription_payment(
        db, user=user, plan_id=first_plan.id
    )
    first = SubscriptionService.activate_for_payment(
        db, user=user, plan=first_plan, payment_id=first_payment.id
    )
    first_end = first.end_date
    first_total = first.total_visits

    next_plan = f.make_plan(
        db,
        plan_name="Second period",
        price=999,
        visits_included=5,
    )
    next_plan.additional_visits = 2
    db.commit()
    next_payment, _, _, _ = PaymentService.create_subscription_payment(
        db, user=user, plan_id=next_plan.id
    )
    second = SubscriptionService.activate_for_payment(
        db, user=user, plan=next_plan, payment_id=next_payment.id
    )

    db.refresh(first)
    assert first.end_date == first_end
    assert first.total_visits == first_total
    assert first.plan_name_snapshot == "First period"
    assert first.price_snapshot == first_plan.price
    assert second.start_date == first_end + timedelta(days=1)
    assert second.total_visits == 7
    assert second.entitlements_snapshot["additional_visits"] == 2
    assert (
        db.query(UserSubscription)
        .filter(UserSubscription.user_id == user.id)
        .count()
        == 2
    )


def test_family_member_limit_counts_primary_subscriber(client, db):
    user = f.make_user(db)
    plan = f.make_plan(db, visits_included=5, max_family_members=5)
    subscription = f.make_subscription(db, user, plan)
    subscription.entitlements_snapshot = {
        "max_family_members": 5,
        "max_adult_members": 2,
        "max_child_members": 3,
        "visits_included": 5,
    }
    db.commit()
    headers = {
        "Authorization": f"Bearer {create_access_token({'user_id': user.id})}"
    }

    family_members = [
        ("Other adult", "adult"),
        ("Child one", "child"),
        ("Child two", "child"),
        ("Child three", "child"),
    ]
    for member_name, member_type in family_members:
        response = client.post(
            "/subscriptions/family-members",
            headers=headers,
            json={
                "member_name": member_name,
                "relationship": "family",
                "member_type": member_type,
            },
        )
        assert response.status_code == 201

    over_limit = client.post(
        "/subscriptions/family-members",
        headers=headers,
        json={
            "member_name": "Child four",
            "relationship": "family",
            "member_type": "child",
        },
    )
    assert over_limit.status_code == 409


def test_duplicate_family_member_is_rejected(client, db):
    user = f.make_user(db)
    plan = f.make_plan(db, visits_included=5, max_family_members=5)
    subscription = f.make_subscription(db, user, plan)
    subscription.entitlements_snapshot = {
        "max_family_members": 5,
        "max_adult_members": 2,
        "max_child_members": 3,
    }
    db.commit()
    headers = {
        "Authorization": f"Bearer {create_access_token({'user_id': user.id})}"
    }
    payload = {
        "member_name": "Alex Example",
        "relationship": "child",
        "member_type": "child",
    }
    assert client.post(
        "/subscriptions/family-members", headers=headers, json=payload
    ).status_code == 201
    duplicate = client.post(
        "/subscriptions/family-members",
        headers=headers,
        json={
            "member_name": " alex example ",
            "relationship": " CHILD ",
            "member_type": "child",
        },
    )
    assert duplicate.status_code == 409


def test_seed_subscription_plans_concurrent_startup(db):
    import threading

    from sqlalchemy.orm import sessionmaker

    # Derive worker sessions from the fixture's bind so they always use the
    # PostgreSQL test database, even if another module reloaded app.database.
    worker_bind = db.get_bind()
    assert worker_bind.dialect.name == "postgresql"
    assert worker_bind.url.database == "rupaywala_test"
    WorkerSession = sessionmaker(
        bind=worker_bind, autocommit=False, autoflush=False, expire_on_commit=False
    )

    seed_subscription_plans(db)
    baseline = {
        p.code: p.id
        for p in db.query(SubscriptionPlan).filter(SubscriptionPlan.is_active.is_(True)).all()
    }
    db.commit()

    barrier = threading.Barrier(5)
    errors = []
    lock = threading.Lock()

    def worker():
        session = WorkerSession()
        try:
            barrier.wait(timeout=20)
            seed_subscription_plans(session)
        except Exception as exc:
            try:
                session.rollback()
            except Exception:
                pass
            with lock:
                errors.append(str(exc))
        finally:
            session.close()

    threads = [threading.Thread(target=worker) for _ in range(5)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(30)

    assert errors == []
    plans = db.query(SubscriptionPlan).filter(SubscriptionPlan.is_active.is_(True)).all()
    assert len(plans) == 7
    assert {p.code: p.id for p in plans} == baseline
