"""
Subscription endpoints.

Activation is impossible without a verified payment: ``/subscribe`` was removed
and the only way to gain visits is to pay for a plan and have an admin verify the
payment. ``/visits/balance`` is what the app shows on the home screen.
"""

import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import desc
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.payment import Payment, PaymentStatus
from app.models.subscription_plan import SubscriptionPlan
from app.models.subscription_family_member import SubscriptionFamilyMember
from app.models.user import User
from app.models.user_subscription import UserSubscription
from app.schemas.subscription_schema import (
    PlanResponse,
    SubscriptionResponse,
    VisitBalanceResponse,
    VisitHistoryEntry,
    FamilyMemberCreate,
    FamilyMemberResponse,
)
from app.services.otp_service import OTPService
from app.services.payment_service import PaymentService
from app.services.subscription_service import SubscriptionService, plan_entitlements
from app.services.visit_service import VisitService
from app.utils.dependencies import customer_required

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])


@router.get("/plans", response_model=list[PlanResponse])
def list_plans(db: Session = Depends(get_db), _: User = Depends(customer_required)):
    plans = (
        db.query(SubscriptionPlan)
        .filter(SubscriptionPlan.is_active.is_(True))
        .order_by(SubscriptionPlan.sort_order, SubscriptionPlan.price)
        .all()
    )
    return plans


@router.get("/plans/{plan_id}", response_model=PlanResponse)
def get_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(customer_required),
):
    return SubscriptionService.get_plan(db, plan_id)


@router.get("/pricing-info")
def pricing_info(db: Session = Depends(get_db), _: User = Depends(customer_required)):
    """The distance/charge rules customers are told about, from the database."""
    from app.services.pricing_service import get_pricing_config

    config = get_pricing_config(db)
    return {
        "threshold_km": config.threshold_km,
        "charge_per_km": config.charge_per_km,
        "tax_percent": config.tax_percent,
        "round_trip_factor": config.round_trip_factor,
        "message": (
            f"Up to {config.threshold_km:g} km is included in your plan. Beyond that, "
            f"Rs {config.charge_per_km:g} per km is charged for the return trip "
            f"(x{config.round_trip_factor:g}), plus {config.tax_percent:g}% tax."
        ),
    }


def _to_response(subscription: UserSubscription | None) -> SubscriptionResponse | None:
    if subscription is None:
        return None
    plan = subscription.plan
    days_remaining = None
    if subscription.end_date:
        days_remaining = max(0, (subscription.end_date - date.today()).days)
    return SubscriptionResponse(
        id=subscription.id,
        plan_id=subscription.plan_id,
        plan_name=subscription.plan_name_snapshot or (plan.plan_name if plan else None),
        price=(
            float(subscription.price_snapshot)
            if subscription.price_snapshot is not None
            else (float(plan.price) if plan else None)
        ),
        entitlements=subscription.entitlements_snapshot
        or (plan_entitlements(plan) if plan else {}),
        status=subscription.status.value,
        total_visits=subscription.total_visits or 0,
        used_visits=subscription.used_visits or 0,
        remaining_visits=subscription.remaining_visits,
        start_date=subscription.start_date,
        end_date=subscription.end_date,
        days_remaining=days_remaining,
        number_of_policies=subscription.number_of_policies or 0,
        number_of_persons=subscription.number_of_persons or 0,
        activated_at=subscription.activated_at,
        created_at=subscription.created_at,
    )


@router.get("/my-subscription", response_model=SubscriptionResponse)
def my_subscription(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    subscription = SubscriptionService.current(db, current_user.id)
    if subscription is None:
        raise HTTPException(
            status_code=404, detail="You do not have a subscription yet. Choose a plan to begin."
        )
    return _to_response(subscription)


@router.get("/my-subscriptions", response_model=list[SubscriptionResponse])
def my_subscriptions(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    rows = (
        db.query(UserSubscription)
        .filter(UserSubscription.user_id == current_user.id)
        .order_by(desc(UserSubscription.id))
        .all()
    )
    return [_to_response(r) for r in rows]


@router.post("/subscribe")
def subscribe_placeholder():
    """Intentionally removed.

    A subscription is activated only after a payment is verified, so this
    endpoint can never grant visits for free. Use:
        POST /payments/create  { "plan_id": n }
        POST /payments/submit  { "txn_id": "...", "utr_number": "..." }
        POST /admin/payments/verify (admin)
    """
    raise HTTPException(
        status_code=410,
        detail=(
            "Direct subscription is no longer available. Complete a payment to activate "
            "your plan."
        ),
    )


# ======================================================================
# Visit balance
# ======================================================================
@router.get("/visits/balance", response_model=VisitBalanceResponse)
def visit_balance(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    balance = VisitService.get_balance(db, current_user.id)
    plan_name = None
    if balance.get("subscription_id"):
        subscription = db.get(UserSubscription, balance["subscription_id"])
        plan = subscription.plan if subscription else None
        plan_name = plan.plan_name if plan else None

    has_active = bool(balance["has_active_subscription"])
    remaining = balance["remaining_visits"]
    reason = None
    if not has_active:
        reason = "Choose a plan to start using our doorstep service."
    elif remaining <= 0:
        reason = "You have used all the visits in your plan. Renew to request another service."

    return VisitBalanceResponse(
        has_active_subscription=has_active,
        subscription_id=balance["subscription_id"],
        plan_name=plan_name,
        total_visits=balance["total_visits"],
        used_visits=balance["used_visits"],
        remaining_visits=remaining,
        start_date=balance["start_date"],
        end_date=balance["end_date"],
        status=balance["status"],
        can_request_service=has_active and remaining > 0,
        reason=reason,
    )


@router.get("/entitlements")
def my_entitlements(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    subscription = VisitService.get_active_subscription(db, current_user.id)
    if subscription is None:
        return {"subscription_id": None, "entitlements": {}}
    return {
        "subscription_id": subscription.id,
        "plan_name": subscription.plan_name_snapshot
        or (subscription.plan.plan_name if subscription.plan else None),
        "entitlements": subscription.entitlements_snapshot
        or (plan_entitlements(subscription.plan) if subscription.plan else {}),
    }


def _family_subscription(db: Session, user_id: int) -> UserSubscription:
    subscription = VisitService.get_active_subscription(db, user_id)
    if subscription is None:
        raise HTTPException(status_code=403, detail="An active subscription is required.")
    entitlements = subscription.entitlements_snapshot or (
        plan_entitlements(subscription.plan) if subscription.plan else {}
    )
    member_limit = entitlements.get("max_family_members")
    if member_limit is None:
        raise HTTPException(
            status_code=409,
            detail="The family member limit has not been configured by an administrator.",
        )
    if member_limit <= 1:
        raise HTTPException(
            status_code=403, detail="Family membership is not included in this plan."
        )
    return subscription


@router.get("/family-members", response_model=list[FamilyMemberResponse])
def list_family_members(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    subscription = _family_subscription(db, current_user.id)
    return (
        db.query(SubscriptionFamilyMember)
        .filter(SubscriptionFamilyMember.subscription_id == subscription.id)
        .order_by(SubscriptionFamilyMember.id)
        .all()
    )


@router.post(
    "/family-members",
    response_model=FamilyMemberResponse,
    status_code=201,
)
def add_family_member(
    payload: FamilyMemberCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    subscription = _family_subscription(db, current_user.id)
    subscription = (
        db.query(UserSubscription)
        .filter(UserSubscription.id == subscription.id)
        .with_for_update()
        .first()
    )
    entitlements = subscription.entitlements_snapshot or (
        plan_entitlements(subscription.plan) if subscription.plan else {}
    )
    member_limit = entitlements.get("max_family_members")
    adult_limit = entitlements.get("max_adult_members")
    child_limit = entitlements.get("max_child_members")
    if payload.member_type == "adult" and adult_limit is not None:
        adult_count = (
            db.query(SubscriptionFamilyMember)
            .filter(
                SubscriptionFamilyMember.subscription_id == subscription.id,
                SubscriptionFamilyMember.member_type == "adult",
            )
            .count()
            + 1
        )
        if adult_count >= adult_limit:
            raise HTTPException(
                status_code=409,
                detail=f"This plan allows {adult_limit} total adults, including the subscriber.",
            )
    if payload.member_type == "child" and child_limit is not None:
        child_count = (
            db.query(SubscriptionFamilyMember)
            .filter(
                SubscriptionFamilyMember.subscription_id == subscription.id,
                SubscriptionFamilyMember.member_type == "child",
            )
            .count()
        )
        if child_count >= child_limit:
            raise HTTPException(
                status_code=409,
                detail=f"This plan allows up to {child_limit} children.",
            )
    count = (
        db.query(SubscriptionFamilyMember)
        .filter(SubscriptionFamilyMember.subscription_id == subscription.id)
        .count()
    )
    if count + 1 >= member_limit:
        raise HTTPException(
            status_code=409,
            detail=f"This plan allows {member_limit} total family members, including the subscriber.",
        )

    name = payload.member_name.strip()
    relationship = payload.relationship.strip()
    dob = payload.date_of_birth.isoformat() if payload.date_of_birth else ""
    identity_key = f"{name.casefold()}|{relationship.casefold()}|{dob}"
    if (
        db.query(SubscriptionFamilyMember)
        .filter(
            SubscriptionFamilyMember.subscription_id == subscription.id,
            SubscriptionFamilyMember.identity_key == identity_key,
        )
        .first()
    ):
        raise HTTPException(status_code=409, detail="This family member is already added.")
    member = SubscriptionFamilyMember(
        subscription_id=subscription.id,
        member_name=name,
        relationship=relationship,
        member_type=payload.member_type,
        date_of_birth=payload.date_of_birth,
        identity_key=identity_key,
    )
    db.add(member)
    db.commit()
    db.refresh(member)
    return member


@router.delete("/family-members/{member_id}", status_code=204)
def remove_family_member(
    member_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    subscription = _family_subscription(db, current_user.id)
    member = (
        db.query(SubscriptionFamilyMember)
        .filter(
            SubscriptionFamilyMember.id == member_id,
            SubscriptionFamilyMember.subscription_id == subscription.id,
        )
        .first()
    )
    if member is None:
        raise HTTPException(status_code=404, detail="Family member not found.")
    db.delete(member)
    db.commit()


@router.get("/visits/history", response_model=list[VisitHistoryEntry])
def visit_history(
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """The auditable ledger: every allocation, consumption and refund."""
    entries = VisitService.history(db, current_user.id, limit=min(limit, 200))
    return [VisitHistoryEntry(**entry) for entry in entries]


@router.get("/payments/summary")
def payments_summary(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    from sqlalchemy import func

    total = (
        db.query(func.coalesce(func.sum(Payment.amount), 0))
        .filter(
            Payment.user_id == current_user.id,
            Payment.status == PaymentStatus.success,
        )
        .scalar()
    )
    pending = (
        db.query(func.count(Payment.id))
        .filter(
            Payment.user_id == current_user.id,
            Payment.status == PaymentStatus.pending_verification,
        )
        .scalar()
    )
    return {"total_paid": float(total or 0), "awaiting_verification": int(pending or 0)}
