"""
Visit credit accounting - the single place visits are read, reserved and
consumed.

Rules enforced here
-------------------
* A visit is consumed ONLY when a service reaches COMPLETED.
* Consumption is idempotent: the request's ``visit_consumed`` flag plus a
  unique ledger constraint means a duplicate completion attempt can never
  deduct a second credit.
* The subscription row is locked (``SELECT ... FOR UPDATE``) for the duration
  of a consume/refund so two concurrent completions cannot both read the same
  last remaining credit.
"""

import logging
from datetime import date, datetime

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.service_request import ServiceRequest
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.models.visit_ledger import VisitEntryType, VisitLedgerEntry

logger = logging.getLogger(__name__)


class VisitService:
    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------
    @staticmethod
    def get_active_subscription(
        db: Session, user_id: int, for_update: bool = False
    ) -> UserSubscription | None:
        """Return the customer's usable subscription, or None.

        Expired rows are lazily transitioned to ``expired`` so the customer
        sees an accurate status without needing a cron job.
        """
        today = date.today()

        query = (
            db.query(UserSubscription)
            .filter(
                UserSubscription.user_id == user_id,
                UserSubscription.status == SubscriptionStatus.active,
                (
                    UserSubscription.start_date.is_(None)
                    | (UserSubscription.start_date <= today)
                ),
                (
                    UserSubscription.end_date.is_(None)
                    | (UserSubscription.end_date >= today)
                ),
            )
            .order_by(UserSubscription.end_date.desc().nullslast(), UserSubscription.id.desc())
        )
        if for_update:
            query = query.with_for_update()

        subscription = query.first()
        if subscription is None:
            expired_rows = (
                db.query(UserSubscription)
                .filter(
                    UserSubscription.user_id == user_id,
                    UserSubscription.status == SubscriptionStatus.active,
                    UserSubscription.end_date < today,
                )
                .all()
            )
            for expired in expired_rows:
                expired.status = SubscriptionStatus.expired
            if expired_rows:
                db.flush()
            return None

        return subscription

    @staticmethod
    def get_balance(db: Session, user_id: int) -> dict:
        subscription = VisitService.get_active_subscription(db, user_id)
        if subscription is None:
            return {
                "subscription_id": None,
                "has_active_subscription": False,
                "total_visits": 0,
                "used_visits": 0,
                "remaining_visits": 0,
                "start_date": None,
                "end_date": None,
                "status": "none",
            }
        return {
            "subscription_id": subscription.id,
            "has_active_subscription": True,
            "total_visits": subscription.total_visits or 0,
            "used_visits": subscription.used_visits or 0,
            "remaining_visits": subscription.remaining_visits,
            "start_date": subscription.start_date,
            "end_date": subscription.end_date,
            "status": subscription.status.value,
        }

    @staticmethod
    def can_request_service(db: Session, user_id: int) -> tuple[bool, str, UserSubscription | None]:
        subscription = VisitService.get_active_subscription(db, user_id)
        if subscription is None:
            return False, "You need an active subscription to request a service.", None
        if subscription.remaining_visits <= 0:
            return (
                False,
                "You have used all visits included in your plan. Please renew to continue.",
                subscription,
            )
        return True, "", subscription

    # ------------------------------------------------------------------
    # Allocation
    # ------------------------------------------------------------------
    @staticmethod
    def allocate(db: Session, subscription: UserSubscription, visits: int, note: str | None = None) -> None:
        """Grant credits to a subscription and record the ledger entry."""
        if visits < 0:
            raise ValueError("visits must be non-negative")
        subscription.total_visits = (subscription.total_visits or 0) + visits
        db.add(
            VisitLedgerEntry(
                subscription_id=subscription.id,
                user_id=subscription.user_id,
                entry_type=VisitEntryType.allocated,
                quantity=visits,
                note=note or "Plan activation",
            )
        )
        db.flush()

    # ------------------------------------------------------------------
    # Consumption - the critical path
    # ------------------------------------------------------------------
    @staticmethod
    def consume_for_request(db: Session, service_request: ServiceRequest) -> bool:
        """Deduct exactly one visit for a completed service.

        Returns True when a credit was deducted, False when the request had
        already consumed one (idempotent no-op).
        """
        if not service_request.visit_required:
            return False
        if service_request.visit_consumed:
            logger.info(
                "Request %s already consumed a visit - skipping duplicate deduction",
                service_request.id,
            )
            return False

        # The unique constraint on (subscription_id, service_request_id,
        # entry_type) is the final guard against a double deduction even if two
        # transactions race past the flag check.
        existing = (
            db.query(VisitLedgerEntry)
            .filter(
                VisitLedgerEntry.service_request_id == service_request.id,
                VisitLedgerEntry.entry_type == VisitEntryType.consumed,
            )
            .first()
        )
        if existing is not None:
            service_request.visit_consumed = True
            db.flush()
            return False

        subscription_id = service_request.subscription_id
        subscription = (
            db.query(UserSubscription)
            .filter(UserSubscription.id == subscription_id)
            .with_for_update()
            .first()
            if subscription_id
            else None
        )
        if subscription is None:
            raise HTTPException(
                status_code=409,
                detail="This service is not linked to a subscription and cannot be completed",
            )

        if subscription.status != SubscriptionStatus.active:
            raise HTTPException(
                status_code=409,
                detail="The subscription for this service is not active",
            )
        if subscription.remaining_visits <= 0:
            raise HTTPException(
                status_code=409,
                detail="No visits remaining on this subscription",
            )

        subscription.used_visits = (subscription.used_visits or 0) + 1
        db.add(
            VisitLedgerEntry(
                subscription_id=subscription.id,
                user_id=subscription.user_id,
                entry_type=VisitEntryType.consumed,
                quantity=-1,
                service_request_id=service_request.id,
                note=f"Service request #{service_request.id} completed",
            )
        )
        service_request.visit_consumed = True
        db.flush()

        logger.info(
            "Visit consumed for request %s: subscription %s now %s/%s used",
            service_request.id,
            subscription.id,
            subscription.used_visits,
            subscription.total_visits,
        )
        return True

    @staticmethod
    def refund_for_request(db: Session, service_request: ServiceRequest, note: str = "Admin refund") -> bool:
        """Return a consumed visit (used when an admin cancels a completed job)."""
        if not service_request.visit_consumed:
            return False

        existing = (
            db.query(VisitLedgerEntry)
            .filter(
                VisitLedgerEntry.service_request_id == service_request.id,
                VisitLedgerEntry.entry_type == VisitEntryType.consumed,
            )
            .first()
        )
        if existing is None:
            service_request.visit_consumed = False
            db.flush()
            return False

        subscription = (
            db.query(UserSubscription)
            .filter(UserSubscription.id == existing.subscription_id)
            .with_for_update()
            .first()
        )
        if subscription is None:
            return False

        subscription.used_visits = max(0, (subscription.used_visits or 0) - 1)
        db.add(
            VisitLedgerEntry(
                subscription_id=subscription.id,
                user_id=subscription.user_id,
                entry_type=VisitEntryType.refunded,
                quantity=1,
                service_request_id=None,
                note=note,
            )
        )
        service_request.visit_consumed = False
        db.flush()
        return True

    # ------------------------------------------------------------------
    # History
    # ------------------------------------------------------------------
    @staticmethod
    def history(db: Session, user_id: int, limit: int = 50) -> list[dict]:
        rows = (
            db.query(VisitLedgerEntry)
            .filter(VisitLedgerEntry.user_id == user_id)
            .order_by(VisitLedgerEntry.id.desc())
            .limit(limit)
            .all()
        )
        return [
            {
                "id": r.id,
                "type": r.entry_type.value,
                "quantity": r.quantity,
                "service_request_id": r.service_request_id,
                "note": r.note,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ]

    @staticmethod
    def usage_summary(db: Session, subscription_id: int) -> dict:
        consumed = (
            db.query(func.coalesce(func.sum(VisitLedgerEntry.quantity), 0))
            .filter(
                VisitLedgerEntry.subscription_id == subscription_id,
                VisitLedgerEntry.entry_type == VisitEntryType.consumed,
            )
            .scalar()
        )
        allocated = (
            db.query(func.coalesce(func.sum(VisitLedgerEntry.quantity), 0))
            .filter(
                VisitLedgerEntry.subscription_id == subscription_id,
                VisitLedgerEntry.entry_type == VisitEntryType.allocated,
            )
            .scalar()
        )
        return {"allocated": int(allocated or 0), "consumed": abs(int(consumed or 0))}
