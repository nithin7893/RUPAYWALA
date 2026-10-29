"""Subscription activation, renewal and reporting."""

import logging
import re
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.services.visit_service import VisitService

logger = logging.getLogger(__name__)


def plan_entitlements(plan: SubscriptionPlan) -> dict:
    """Return the server-authoritative benefits copied into a subscription."""
    return {
        "visits_included": int(plan.visits_included or 0),
        "additional_visits": plan.additional_visits,
        "included_visit_distance_km": (
            float(plan.included_visit_distance_km)
            if plan.included_visit_distance_km is not None
            else None
        ),
        "max_family_members": plan.max_family_members,
        "max_adult_members": plan.max_adult_members,
        "max_child_members": plan.max_child_members,
        "document_verification": bool(plan.document_verification),
        "online_submission": bool(plan.online_submission),
        "document_storage": bool(plan.document_storage),
        "storage_duration_days": plan.storage_duration_days,
        "priority_support": bool(plan.priority_support),
        "addon_eligibility": plan.addon_eligibility or {},
    }


_DIGITAL_SERVICES = {
    "claim_form_assistance",
    "document_scanning",
    "document_organization",
    "claim_document_checklist",
}


class SubscriptionService:
    @staticmethod
    def get_plan(db: Session, plan_id: int) -> SubscriptionPlan:
        plan = db.get(SubscriptionPlan, plan_id)
        if plan is None or not plan.is_active:
            raise HTTPException(status_code=404, detail="This plan is not available")
        return plan

    @staticmethod
    def authorize_request(
        db: Session, user_id: int, service_code: str | None
    ) -> tuple[UserSubscription, bool]:
        """Check the active subscription and report whether this request uses a visit."""
        from app.services.visit_service import VisitService

        subscription = VisitService.get_active_subscription(db, user_id)
        if subscription is None:
            raise HTTPException(
                status_code=403, detail="Choose an active subscription to request a service."
            )
        entitlements = subscription.entitlements_snapshot or (
            plan_entitlements(subscription.plan) if subscription.plan else {}
        )
        code = re.sub(r"[\s-]+", "_", (service_code or "").strip().lower())
        if code in _DIGITAL_SERVICES:
            return subscription, False
        if code == "document_verification":
            if not entitlements.get("document_verification", False):
                raise HTTPException(
                    status_code=403,
                    detail="Document verification is not included in your active plan.",
                )
            return subscription, False
        if code == "online_submission":
            if not entitlements.get("online_submission", False):
                raise HTTPException(
                    status_code=403,
                    detail="Online submission is not included in your active plan.",
                )
            return subscription, False
        if subscription.remaining_visits <= 0:
            raise HTTPException(
                status_code=403,
                detail="No included home visits remain. Purchase an additional visit to continue.",
            )
        return subscription, True

    @staticmethod
    def current(db: Session, user_id: int) -> UserSubscription | None:
        """Return the current period, or the latest period if none is current."""
        today = date.today()
        active = (
            db.query(UserSubscription)
            .filter(
                UserSubscription.user_id == user_id,
                UserSubscription.status == SubscriptionStatus.active,
                (UserSubscription.start_date.is_(None) | (UserSubscription.start_date <= today)),
                (UserSubscription.end_date.is_(None) | (UserSubscription.end_date >= today)),
            )
            .order_by(
                UserSubscription.end_date.desc().nullslast(),
                UserSubscription.id.desc(),
            )
            .first()
        )
        if active is not None:
            return active
        return (
            db.query(UserSubscription)
            .filter(UserSubscription.user_id == user_id)
            .order_by(UserSubscription.end_date.desc().nullslast(), UserSubscription.id.desc())
            .first()
        )

    @staticmethod
    def activate_for_payment(
        db: Session,
        *,
        user: User,
        plan: SubscriptionPlan,
        payment_id: int,
        number_of_policies: int = 0,
        number_of_persons: int = 0,
    ) -> UserSubscription:
        """Activate (or extend) a subscription after a successful payment.

        Called only from PaymentService after verification, which is why it
        trusts the caller. Renewing an unexpired subscription extends the
        existing end date rather than discarding unused days.
        """
        today = date.today()
        existing_period = (
            db.query(UserSubscription)
            .filter(
                UserSubscription.user_id == user.id,
                UserSubscription.status.in_(
                    [SubscriptionStatus.active, SubscriptionStatus.expired]
                ),
            )
            .order_by(UserSubscription.end_date.desc().nullslast(), UserSubscription.id.desc())
            .with_for_update()
            .first()
        )

        visits = int(plan.visits_included or 0) + int(plan.additional_visits or 0)
        validity_days = int(plan.validity_days or 365)

        next_start = today
        if existing_period is not None and existing_period.end_date is not None:
            if existing_period.end_date >= today:
                next_start = existing_period.end_date + timedelta(days=1)

        entitlements = plan_entitlements(plan)
        subscription = UserSubscription(
            user_id=user.id,
            plan_id=plan.id,
            payment_id=payment_id,
            plan_name_snapshot=plan.plan_name,
            price_snapshot=plan.price,
            entitlements_snapshot=entitlements,
            total_visits=0,
            used_visits=0,
            start_date=next_start,
            end_date=next_start + timedelta(days=validity_days),
            status=SubscriptionStatus.active,
            activated_at=datetime.utcnow(),
            number_of_policies=number_of_policies or plan.max_policies or 0,
            number_of_persons=number_of_persons or plan.max_family_members or 0,
        )
        db.add(subscription)
        db.flush()
        note = f"Plan {'renewed' if existing_period else 'activated'}: {plan.plan_name}"

        if visits:
            VisitService.allocate(db, subscription, visits, note=note)

        db.flush()
        logger.info(
            "Subscription %s active for user %s until %s with %s visits",
            subscription.id,
            user.id,
            subscription.end_date,
            subscription.total_visits,
        )
        return subscription

    @staticmethod
    def expire_lapsed(db: Session) -> int:
        today = date.today()
        rows = (
            db.query(UserSubscription)
            .filter(
                UserSubscription.status == SubscriptionStatus.active,
                UserSubscription.end_date < today,
            )
            .all()
        )
        for row in rows:
            row.status = SubscriptionStatus.expired
        db.flush()
        return len(rows)

    @staticmethod
    def cancel(db: Session, subscription_id: int, actor_user_id: int) -> UserSubscription:
        subscription = (
            db.query(UserSubscription)
            .filter(UserSubscription.id == subscription_id)
            .with_for_update()
            .first()
        )
        if subscription is None:
            raise HTTPException(status_code=404, detail="Subscription not found")
        if subscription.status == SubscriptionStatus.cancelled:
            raise HTTPException(status_code=409, detail="Subscription is already cancelled")
        subscription.status = SubscriptionStatus.cancelled
        subscription.cancelled_at = datetime.utcnow()
        db.flush()
        return subscription
