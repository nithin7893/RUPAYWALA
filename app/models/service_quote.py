"""
Persisted, single-use fixed-price quotation.

A quote is the server's promise that a specific customer will pay a specific
amount for a specific service at a specific branch, using a specific policy
and entitlement context, until a specific expiry time.

The row is the authority. Request creation never recalculates a valid quote:
the frozen pricing snapshot below is copied onto the service request. The
``signature`` column is an HMAC over that snapshot so a direct database edit
cannot silently change what a customer is charged.
"""

import enum
import secrets

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    TIMESTAMP,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.database import Base


class QuoteStatus(enum.Enum):
    active = "active"
    consumed = "consumed"
    expired = "expired"
    cancelled = "cancelled"


#: Type name follows the project convention (lowercase enum name).
#: Current integrity payload version. Version 1 was the pre-remediation payload
#: which did not include lifecycle state; version 2 signs the full lifecycle.
SIGNATURE_VERSION = 2

QUOTE_STATUS = Enum(QuoteStatus, name="quote_status")


def new_quote_ref() -> str:
    """A cryptographically unpredictable public quote identifier."""
    return secrets.token_urlsafe(32)


class ServiceQuote(Base):
    __tablename__ = "service_quotes"

    id = Column(Integer, primary_key=True, index=True)

    # Public identifier. Deliberately random rather than a sequential id so a
    # customer cannot enumerate other customers' quotations.
    quote_ref = Column(String(64), nullable=False, default=new_quote_ref)
    signature = Column(String(128), nullable=False)

    # Integrity payload version. New rows are written as version 2 (lifecycle
    # included). Rows created by the pre-remediation code are version 1 and can
    # only be verified with an explicitly configured legacy key.
    signature_version = Column(
        Integer, nullable=False, default=SIGNATURE_VERSION, server_default="1"
    )

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # ---------------- service context ----------------
    service_type_id = Column(
        Integer, ForeignKey("service_types.id", ondelete="SET NULL"), nullable=True
    )
    request_type = Column(String(100), nullable=False)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True, index=True)
    policy_id = Column(Integer, ForeignKey("policies.id"), nullable=True)
    subscription_id = Column(
        Integer, ForeignKey("user_subscriptions.id", ondelete="SET NULL"), nullable=True
    )
    family_member_id = Column(
        Integer,
        ForeignKey(
            "subscription_family_members.id",
            ondelete="SET NULL",
            name="fk_service_quotes_family_member_id",
        ),
        nullable=True,
    )
    visit_required = Column(Boolean, nullable=False, default=True, server_default="true")

    # ---------------- location snapshot ----------------
    customer_latitude = Column(Numeric(10, 7), nullable=True)
    customer_longitude = Column(Numeric(10, 7), nullable=True)
    customer_address = Column(Text, nullable=True)
    customer_place_id = Column(String(120), nullable=True)

    # ---------------- route snapshot ----------------
    distance_km = Column(Numeric(10, 2), nullable=True)
    duration_minutes = Column(Numeric(10, 1), nullable=True)

    # ---------------- pricing snapshot ----------------
    distance_rate_config_id = Column(
        Integer, ForeignKey("distance_rate_config.id"), nullable=True
    )
    threshold_km_used = Column(Numeric(10, 2), nullable=True)
    charge_per_km_used = Column(Numeric(10, 2), nullable=True)
    round_trip_factor_used = Column(Numeric(4, 2), nullable=True)
    excess_distance_km = Column(Numeric(10, 2), nullable=True)
    entitlement_included_distance_km = Column(Numeric(10, 2), nullable=True)

    base_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    extra_charge = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    tax_percent_used = Column(Numeric(5, 2), nullable=True)
    tax_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    total_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")

    currency = Column(String(3), nullable=False, default="INR", server_default="INR")
    within_threshold = Column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    requires_payment = Column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    # ---------------- lifecycle ----------------
    status = Column(QUOTE_STATUS, nullable=False, default=QuoteStatus.active)
    created_at = Column(TIMESTAMP, server_default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    consumed_at = Column(DateTime, nullable=True)
    cancelled_at = Column(DateTime, nullable=True)

    # Set exactly once when the quote is consumed. The unique constraint is the
    # final database-level guarantee that one quote cannot create two requests.
    service_request_id = Column(
        Integer, ForeignKey("service_requests.id", ondelete="SET NULL"), nullable=True
    )

    __table_args__ = (
        UniqueConstraint("quote_ref", name="uq_service_quotes_quote_ref"),
        UniqueConstraint(
            "service_request_id", name="uq_service_quotes_service_request_id"
        ),
        Index("idx_service_quotes_user_status", "user_id", "status"),
    )

    def is_expired(self, now=None) -> bool:
        from datetime import datetime

        now = now or datetime.utcnow()
        return self.status == QuoteStatus.active and self.expires_at <= now
