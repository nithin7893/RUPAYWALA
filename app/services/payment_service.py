"""
Payment orchestration.

Design rules
------------
* The backend computes every amount. The client never sends a price.
* A payment intent is reusable while it is still open (no duplicate QR spam)
  and is protected by an idempotency key.
* Verification is the single activation point: the subscription is created
  and the visit credits are allocated inside the same transaction as the
  status change, so a crash can never leave a paid-but-unfulfilled order.
* A payment can only move forward through the state machine, so a duplicate
  verification callback is a no-op rather than a second activation.
"""

import base64
import logging
import uuid
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from io import BytesIO

import segno
from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.config import (
    PAYMENT_MAX_SUBMIT_ATTEMPTS,
    QR_EXPIRY_MINUTES,
    UPI_ID,
    UPI_PAYEE_NAME,
)
from app.models.payment import Payment, PaymentStatus, PaymentType
from app.models.service_request import RequestStatus
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.services.request_status_service import RequestStatusService
from app.services.subscription_service import SubscriptionService

logger = logging.getLogger(__name__)

CENTS = Decimal("0.01")


def _q(value) -> Decimal:
    return Decimal(str(value)).quantize(CENTS, rounding=ROUND_HALF_UP)


def build_upi_url(amount, txn_id: str, note: str = "") -> str:
    return (
        f"upi://pay?pa={UPI_ID}&pn={UPI_PAYEE_NAME}"
        f"&am={_q(amount)}&cu=INR&tn={txn_id}"
        + (f"&tr={note}" if note else "")
    )


def generate_qr_code_base64(upi_url: str) -> str:
    buffer = BytesIO()
    segno.make(upi_url, encoding="utf-8").save(buffer, kind="png", scale=6)
    buffer.seek(0)
    return base64.b64encode(buffer.getvalue()).decode("utf-8")


class PaymentService:
    # ------------------------------------------------------------------
    # Intents
    # ------------------------------------------------------------------
    @staticmethod
    def create_subscription_payment(
        db: Session, *, user: User, plan_id: int, idempotency_key: str | None = None
    ) -> tuple[Payment, SubscriptionPlan, str, str]:
        plan = SubscriptionService.get_plan(db, plan_id)

        existing = PaymentService._reusable_intent(
            db,
            user_id=user.id,
            plan_id=plan.id,
            idempotency_key=idempotency_key,
        )
        if existing is not None:
            url = build_upi_url(existing.amount, existing.txn_id, plan.plan_name[:40])
            return existing, plan, url, generate_qr_code_base64(url)

        now = datetime.utcnow()
        txn_id = str(uuid.uuid4())
        price = _q(plan.price)

        payment = Payment(
            txn_id=txn_id,
            user_id=user.id,
            plan_id=plan.id,
            payment_type=PaymentType.subscription,
            base_amount=price,
            extra_charge=Decimal("0"),
            tax_amount=Decimal("0"),
            amount=price,
            currency="INR",
            status=PaymentStatus.pending,
            idempotency_key=idempotency_key,
            qr_generated_at=now,
            expires_at=now + timedelta(minutes=QR_EXPIRY_MINUTES),
        )
        db.add(payment)
        db.commit()
        db.refresh(payment)

        url = build_upi_url(payment.amount, payment.txn_id, plan.plan_name[:40])
        return payment, plan, url, generate_qr_code_base64(url)

    @staticmethod
    def create_extra_charge_payment(
        db: Session, *, user: User, request_id: int
    ) -> tuple[Payment, str, str]:
        from app.models.service_request import ServiceRequest

        request = db.get(ServiceRequest, request_id)
        if request is None or request.user_id != user.id:
            raise HTTPException(status_code=404, detail="Service request not found")
        if not request.requires_payment:
            raise HTTPException(
                status_code=400, detail="There is no pending extra charge on this request"
            )

        existing = PaymentService._reusable_intent(
            db, user_id=user.id, request_id=request_id
        )
        if existing is not None:
            url = build_upi_url(existing.amount, existing.txn_id, f"Request {request_id}")
            return existing, url, generate_qr_code_base64(url)

        now = datetime.utcnow()
        txn_id = str(uuid.uuid4())
        total = _q(request.total_amount or 0)

        payment = Payment(
            txn_id=txn_id,
            user_id=user.id,
            payment_type=PaymentType.extra_charge,
            related_request_id=request_id,
            base_amount=_q(request.base_amount or 0),
            extra_charge=_q(request.extra_charge or 0),
            tax_amount=_q(request.tax_amount or 0),
            amount=total,
            currency="INR",
            status=PaymentStatus.pending,
            idempotency_key=f"request:{request_id}",
            qr_generated_at=now,
            expires_at=now + timedelta(minutes=QR_EXPIRY_MINUTES),
        )
        db.add(payment)
        db.commit()
        db.refresh(payment)

        url = build_upi_url(payment.amount, payment.txn_id, f"Request {request_id}")
        return payment, url, generate_qr_code_base64(url)

    @staticmethod
    def _reusable_intent(
        db: Session,
        *,
        user_id: int,
        plan_id: int | None = None,
        request_id: int | None = None,
        idempotency_key: str | None = None,
    ) -> Payment | None:
        """Return an open payment for the same purpose, or None."""
        if idempotency_key:
            existing = (
                db.query(Payment)
                .filter(
                    Payment.idempotency_key == idempotency_key,
                    Payment.status.in_([PaymentStatus.pending, PaymentStatus.pending_verification]),
                )
                .first()
            )
            if existing is not None:
                if existing.status == PaymentStatus.pending and existing.expires_at < datetime.utcnow():
                    existing.status = PaymentStatus.expired
                    db.commit()
                    return None
                return existing

        query = db.query(Payment).filter(
            Payment.user_id == user_id,
            Payment.status.in_([PaymentStatus.pending, PaymentStatus.pending_verification]),
        )
        if plan_id is not None:
            query = query.filter(
                Payment.plan_id == plan_id, Payment.payment_type == PaymentType.subscription
            )
        if request_id is not None:
            query = query.filter(
                Payment.related_request_id == request_id,
                Payment.payment_type == PaymentType.extra_charge,
            )

        for candidate in query.order_by(Payment.id.desc()).limit(5).all():
            if candidate.status == PaymentStatus.pending_verification:
                raise HTTPException(
                    status_code=409,
                    detail="A payment for this is already awaiting verification",
                )
            if candidate.expires_at >= datetime.utcnow():
                return candidate
            candidate.status = PaymentStatus.expired
            db.commit()
        return None

    # ------------------------------------------------------------------
    # Customer submission
    # ------------------------------------------------------------------
    @staticmethod
    def submit_payment(
        db: Session, *, user: User, txn_id: str, utr_number: str
    ) -> Payment:
        payment = (
            db.query(Payment).filter(Payment.txn_id == txn_id).with_for_update().first()
        )
        if payment is None:
            raise HTTPException(status_code=404, detail="Transaction not found")
        if payment.user_id != user.id:
            raise HTTPException(status_code=403, detail="This transaction belongs to another account")

        if payment.status == PaymentStatus.pending_verification:
            return payment  # idempotent re-submit
        if payment.status != PaymentStatus.pending:
            raise HTTPException(
                status_code=400,
                detail=f"This transaction can no longer be submitted (status: {payment.status.value})",
            )
        if payment.expires_at < datetime.utcnow():
            payment.status = PaymentStatus.expired
            db.commit()
            raise HTTPException(
                status_code=400,
                detail="This payment request has expired. Please generate a new QR code.",
            )
        if (payment.attempts or 0) >= PAYMENT_MAX_SUBMIT_ATTEMPTS:
            payment.status = PaymentStatus.failed
            payment.failure_reason = "Maximum submission attempts exceeded"
            db.commit()
            raise HTTPException(
                status_code=400, detail="Maximum attempts reached for this transaction"
            )

        utr = (utr_number or "").strip().upper()
        if len(utr) < 6 or len(utr) > 50:
            raise HTTPException(status_code=400, detail="Enter a valid UTR / reference number")

        clash = (
            db.query(Payment)
            .filter(
                Payment.utr_number == utr,
                Payment.id != payment.id,
                Payment.status == PaymentStatus.success,
            )
            .first()
        )
        if clash is not None:
            raise HTTPException(
                status_code=409,
                detail="That reference number has already been used for another payment",
            )

        payment.utr_number = utr
        payment.attempts = (payment.attempts or 0) + 1
        payment.status = PaymentStatus.pending_verification
        db.commit()
        db.refresh(payment)
        return payment

    # ------------------------------------------------------------------
    # Admin verification - the activation point
    # ------------------------------------------------------------------
    @staticmethod
    def verify_payment(
        db: Session, *, admin: User, txn_id: str, approve: bool, note: str | None = None
    ) -> Payment:
        payment = (
            db.query(Payment).filter(Payment.txn_id == txn_id).with_for_update().first()
        )
        if payment is None:
            raise HTTPException(status_code=404, detail="Transaction not found")

        if payment.status == PaymentStatus.success and approve:
            return payment  # duplicate callback - already fulfilled
        if payment.status != PaymentStatus.pending_verification:
            raise HTTPException(
                status_code=409,
                detail=f"This payment is not awaiting verification (status: {payment.status.value})",
            )

        payment.verified_by = admin.id
        payment.verified_at = datetime.utcnow()
        payment.admin_note = note

        if not approve:
            payment.status = PaymentStatus.failed
            payment.failure_reason = note or "Rejected by admin"
            db.commit()
            db.refresh(payment)
            return payment

        payment.status = PaymentStatus.success

        if payment.payment_type == PaymentType.extra_charge:
            PaymentService._activate_extra_charge(db, payment)
        else:
            PaymentService._activate_subscription(db, payment)

        db.commit()
        db.refresh(payment)
        return payment

    @staticmethod
    def _activate_extra_charge(db: Session, payment: Payment) -> None:
        from app.models.service_request import ServiceRequest

        request = (
            db.query(ServiceRequest)
            .filter(ServiceRequest.id == payment.related_request_id)
            .with_for_update()
            .first()
        )
        if request is None:
            raise HTTPException(status_code=409, detail="The related service request no longer exists")

        request.charge_paid = True
        if request.status == RequestStatus.payment_pending:
            RequestStatusService.ensure_transition(request, RequestStatus.payment_completed)
            if request.status == RequestStatus.payment_completed:
                request.status = RequestStatus.waiting_for_assignment

    @staticmethod
    def _activate_subscription(db: Session, payment: Payment) -> None:
        user = db.get(User, payment.user_id)
        if user is None:
            raise HTTPException(status_code=409, detail="The customer account no longer exists")
        plan = db.get(SubscriptionPlan, payment.plan_id)
        if plan is None:
            payment.status = PaymentStatus.failed
            payment.failure_reason = "Plan is no longer available"
            db.flush()
            raise HTTPException(status_code=409, detail="This plan is no longer available")

        SubscriptionService.activate_for_payment(
            db, user=user, plan=plan, payment_id=payment.id
        )

    # ------------------------------------------------------------------
    # Maintenance
    # ------------------------------------------------------------------
    @staticmethod
    def expire_pending_transactions(db: Session) -> int:
        now = datetime.utcnow()
        rows = (
            db.query(Payment)
            .filter(Payment.status == PaymentStatus.pending, Payment.expires_at < now)
            .all()
        )
        for row in rows:
            row.status = PaymentStatus.expired
        db.commit()
        return len(rows)

    @staticmethod
    def get_payment(db: Session, user: User, txn_id: str) -> Payment:
        payment = db.query(Payment).filter(Payment.txn_id == txn_id).first()
        if payment is None:
            raise HTTPException(status_code=404, detail="Transaction not found")
        if user.role.value != "admin" and payment.user_id != user.id:
            raise HTTPException(status_code=403, detail="This transaction belongs to another account")
        return payment

    @staticmethod
    def list_for_user(db: Session, user_id: int, limit: int = 50) -> list[Payment]:
        return (
            db.query(Payment)
            .filter(Payment.user_id == user_id)
            .order_by(Payment.id.desc())
            .limit(limit)
            .all()
        )

    @staticmethod
    def dashboard_counts(db: Session) -> dict:
        def count(status: PaymentStatus) -> int:
            return (
                db.query(func.count(Payment.id))
                .filter(Payment.status == status)
                .scalar()
                or 0
            )

        total_amount = (
            db.query(func.coalesce(func.sum(Payment.amount), 0))
            .filter(Payment.status == PaymentStatus.success)
            .scalar()
            or 0
        )
        return {
            "pending_verification": count(PaymentStatus.pending_verification),
            "success": count(PaymentStatus.success),
            "failed": count(PaymentStatus.failed),
            "expired": count(PaymentStatus.expired),
            "cancelled": count(PaymentStatus.cancelled),
            "total_collected": float(total_amount),
        }
