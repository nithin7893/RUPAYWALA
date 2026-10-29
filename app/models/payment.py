import enum

from sqlalchemy import (
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    TIMESTAMP,
    Text,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.database import Base


class PaymentStatus(enum.Enum):
    pending = "pending"                    # QR issued, awaiting customer UTR
    pending_verification = "pending_verification"
    success = "success"
    failed = "failed"
    expired = "expired"
    cancelled = "cancelled"


class PaymentType(enum.Enum):
    subscription = "subscription"
    extra_charge = "extra_charge"


# Type names match the enums already present in the deployed database.
PAYMENT_STATUS = Enum(PaymentStatus, name="payment_status")
PAYMENT_TYPE = Enum(PaymentType, name="payment_type")


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    txn_id = Column(String(36), unique=True, nullable=False, index=True)

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    plan_id = Column(Integer, ForeignKey("subscription_plans.id"), nullable=True)

    payment_type = Column(PAYMENT_TYPE, default=PaymentType.subscription, nullable=False)
    related_request_id = Column(
        Integer,
        ForeignKey(
            "service_requests.id",
            use_alter=True,
            ondelete="SET NULL",
            name="fk_payments_related_request_id",
        ),
        nullable=True,
    )

    # Itemised amounts. The backend is the only authority for these - the
    # client never sends an amount.
    base_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    extra_charge = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    tax_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    amount = Column(Numeric(10, 2), nullable=False)
    currency = Column(String(10), default="INR", nullable=False)

    utr_number = Column(String(50), unique=True, nullable=True, index=True)
    attempts = Column(Integer, default=0, nullable=False, server_default="0")

    status = Column(PAYMENT_STATUS, default=PaymentStatus.pending, nullable=False)

    # Idempotency guard: a payment intent may only be created once for a given
    # (user, plan) or (user, request) combination while still open.
    idempotency_key = Column(String(120), nullable=True)

    verified_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    verified_at = Column(DateTime, nullable=True)
    failure_reason = Column(String(255), nullable=True)
    admin_note = Column(Text, nullable=True)

    qr_generated_at = Column(TIMESTAMP, nullable=True)
    expires_at = Column(DateTime, nullable=False)

    created_at = Column(TIMESTAMP, server_default=func.now())
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("idx_payments_user_plan", "user_id", "plan_id"),
        Index("idx_payments_status", "status"),
        Index("idx_payments_type_status", "payment_type", "status"),
    )
