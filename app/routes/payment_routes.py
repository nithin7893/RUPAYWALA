"""
UPI payment endpoints (customer) and verification (admin).

The customer pays by scanning a generated UPI QR and then submits the UTR /
reference number. An admin verifies it in the app, and only that verification
activates the subscription or releases the extra charge - see
``app.services.payment_service``.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.config import QR_EXPIRY_MINUTES
from app.database import get_db
from app.models.payment import Payment, PaymentStatus
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import User
from app.models.user_subscription import UserSubscription
from app.schemas.payment_schema import (
    PaymentCreateRequest,
    PaymentCreateResponse,
    PaymentDetailResponse,
    PaymentListResponse,
    PaymentSubmitRequest,
    PaymentSubmitResponse,
    PaymentVerifyRequest,
    PaymentVerifyResponse,
)
from app.services.payment_service import PaymentService
from app.utils.dependencies import admin_required, customer_required, get_current_user
from app.utils import rate_limit

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/payments", tags=["Payments"])
admin_router = APIRouter(prefix="/admin/payments", tags=["Admin - Payments"])


# ======================================================================
# Customer
# ======================================================================
@router.post(
    "/create",
    response_model=PaymentCreateResponse,
    dependencies=[Depends(rate_limit.rate_limit(20, 60, "payment-create"))],
)
def create_payment(
    payload: PaymentCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """Create - or reuse - a payment intent.

    The client never sends an amount. For a plan the price comes from the plan
    row; for an extra distance charge it comes from the frozen snapshot on the
    service request.
    """
    if payload.plan_id is not None and payload.request_id is not None:
        raise HTTPException(
            status_code=400, detail="Provide either plan_id or request_id, not both"
        )
    if payload.plan_id is None and payload.request_id is None:
        raise HTTPException(
            status_code=400, detail="Provide a plan_id or a request_id"
        )

    if payload.plan_id is not None:
        payment, plan, upi_url, qr_code = PaymentService.create_subscription_payment(
            db,
            user=current_user,
            plan_id=payload.plan_id,
            idempotency_key=payload.idempotency_key,
        )
        return PaymentCreateResponse(
            txn_id=payment.txn_id,
            payment_type=payment.payment_type.value,
            amount=float(payment.amount or 0),
            base_amount=float(payment.base_amount or 0),
            extra_charge=float(payment.extra_charge or 0),
            tax_amount=float(payment.tax_amount or 0),
            currency=payment.currency,
            upi_url=upi_url,
            qr_code=qr_code,
            status=payment.status,
            plan_id=plan.id,
            plan_name=plan.plan_name,
            expires_at=payment.expires_at,
        )

    payment, upi_url, qr_code = PaymentService.create_extra_charge_payment(
        db, user=current_user, request_id=payload.request_id
    )
    return PaymentCreateResponse(
        txn_id=payment.txn_id,
        payment_type=payment.payment_type.value,
        amount=float(payment.amount or 0),
        base_amount=float(payment.base_amount or 0),
        extra_charge=float(payment.extra_charge or 0),
        tax_amount=float(payment.tax_amount or 0),
        currency=payment.currency,
        upi_url=upi_url,
        qr_code=qr_code,
        status=payment.status,
        request_id=payload.request_id,
        expires_at=payment.expires_at,
    )


@router.post(
    "/submit",
    response_model=PaymentSubmitResponse,
    dependencies=[Depends(rate_limit.rate_limit(20, 60, "payment-submit"))],
)
def submit_payment(
    payload: PaymentSubmitRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """Customer declares they have paid and supplies the UTR."""
    payment = PaymentService.submit_payment(
        db, user=current_user, txn_id=payload.txn_id, utr_number=payload.utr_number
    )
    return PaymentSubmitResponse(
        message="Payment submitted. An admin will verify it shortly.",
        txn_id=payment.txn_id,
        status=payment.status,
        attempts=payment.attempts or 0,
    )


@router.get("/status/{txn_id}", response_model=PaymentDetailResponse)
def payment_status(
    txn_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    payment = PaymentService.get_payment(db, current_user, txn_id)
    plan = db.get(SubscriptionPlan, payment.plan_id) if payment.plan_id else None
    return {
        "id": payment.id,
        "txn_id": payment.txn_id,
        "payment_type": payment.payment_type.value,
        "user_id": payment.user_id,
        "plan_id": payment.plan_id,
        "plan_name": plan.plan_name if plan else None,
        "related_request_id": payment.related_request_id,
        "amount": float(payment.amount or 0),
        "base_amount": float(payment.base_amount or 0),
        "extra_charge": float(payment.extra_charge or 0),
        "tax_amount": float(payment.tax_amount or 0),
        "currency": payment.currency,
        "status": payment.status,
        "utr_number": payment.utr_number,
        "attempts": payment.attempts or 0,
        "failure_reason": payment.failure_reason,
        "admin_note": payment.admin_note,
        "verified_at": payment.verified_at,
        "created_at": payment.created_at,
        "expires_at": payment.expires_at,
    }


@router.get("/my-payments", response_model=list[PaymentListResponse])
def my_payments(
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    rows = PaymentService.list_for_user(db, current_user.id, limit=min(limit, 200))
    out = []
    for payment in rows:
        plan = db.get(SubscriptionPlan, payment.plan_id) if payment.plan_id else None
        out.append(
            {
                "id": payment.id,
                "txn_id": payment.txn_id,
                "payment_type": payment.payment_type.value,
                "user_id": payment.user_id,
                "amount": float(payment.amount or 0),
                "status": payment.status,
                "utr_number": payment.utr_number,
                "plan_name": plan.plan_name if plan else None,
                "related_request_id": payment.related_request_id,
                "submitted_at": payment.verified_at,
                "verified_at": payment.verified_at,
                "created_at": payment.created_at,
            }
        )
    return out


# ======================================================================
# Admin
# ======================================================================
@admin_router.get("/list", response_model=list[PaymentListResponse])
def list_payments(
    status_filter: str | None = None,
    payment_type: str | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    query = db.query(Payment)
    if status_filter:
        wanted = {s.strip().lower() for s in status_filter.split(",") if s.strip()}
        try:
            query = query.filter(Payment.status.in_([PaymentStatus(s) for s in wanted]))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=f"Unknown status value: {exc}")
    if payment_type:
        query = query.filter(Payment.payment_type == payment_type)

    rows = query.order_by(Payment.id.desc()).limit(min(limit, 500)).all()

    out = []
    for payment in rows:
        plan = db.get(SubscriptionPlan, payment.plan_id) if payment.plan_id else None
        out.append(
            {
                "id": payment.id,
                "txn_id": payment.txn_id,
                "payment_type": payment.payment_type.value,
                "user_id": payment.user_id,
                "amount": float(payment.amount or 0),
                "status": payment.status,
                "utr_number": payment.utr_number,
                "plan_name": plan.plan_name if plan else None,
                "related_request_id": payment.related_request_id,
                "submitted_at": payment.verified_at,
                "verified_at": payment.verified_at,
                "created_at": payment.created_at,
            }
        )
    return out


@admin_router.post("/verify", response_model=PaymentVerifyResponse)
def verify_payment(
    payload: PaymentVerifyRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Approve or reject a submitted payment.

    Approving is the single activation point: the subscription and its visit
    credits (or the request's payment gate) are updated in the same
    transaction.
    """
    payment = PaymentService.verify_payment(
        db,
        admin=admin,
        txn_id=payload.txn_id,
        approve=payload.action == "approve",
        note=payload.note,
    )

    subscription = None
    if payment.plan_id:
        subscription = (
            db.query(UserSubscription)
            .filter(UserSubscription.payment_id == payment.id)
            .order_by(UserSubscription.id.desc())
            .first()
        )

    message = (
        "Payment verified and the plan is now active"
        if payload.action == "approve"
        else "Payment rejected"
    )
    return PaymentVerifyResponse(
        message=message,
        txn_id=payment.txn_id,
        status=payment.status,
        subscription_id=subscription.id if subscription else None,
    )


@admin_router.get("/summary")
def payments_summary(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    return PaymentService.dashboard_counts(db)


@admin_router.post("/expire-pending")
def expire_pending(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    """Housekeeping: mark stale, unpaid QR intents as expired."""
    return {"expired": PaymentService.expire_pending_transactions(db)}


@admin_router.post("/{txn_id}/refresh")
def refresh_payment(
    txn_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    payment = db.query(Payment).filter(Payment.txn_id == txn_id).first()
    if payment is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return {
        "txn_id": payment.txn_id,
        "status": payment.status.value,
        "amount": float(payment.amount or 0),
        "qr_valid_for_minutes": QR_EXPIRY_MINUTES
        if payment.status == PaymentStatus.pending
        else 0,
    }
