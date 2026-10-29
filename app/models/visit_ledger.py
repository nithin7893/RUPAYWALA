"""
Visit credit ledger.

A visit is a credit belonging to a subscription. Exactly one visit is consumed
when a service is *successfully completed*, never at request/payment/assignment
time. Every consumption is recorded here so the deduction is auditable and
idempotent (the unique constraint on service_request_id guarantees that a
duplicate completion can never consume a second credit).
"""

import enum
from datetime import datetime

from sqlalchemy import (
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    TIMESTAMP,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.database import Base


class VisitEntryType(enum.Enum):
    allocated = "allocated"        # credits granted by a subscription
    consumed = "consumed"          # 1 credit used by a completed service
    refunded = "refunded"          # credit returned (admin adjustment)
    expired = "expired"            # credits dropped when the period ended


#: New type - the visit ledger did not exist before this revision.
VISIT_ENTRY_TYPE = Enum(VisitEntryType, name="visit_entry_type")


class VisitLedgerEntry(Base):
    __tablename__ = "visit_ledger"

    id = Column(Integer, primary_key=True, index=True)

    subscription_id = Column(
        Integer,
        ForeignKey("user_subscriptions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    entry_type = Column(VISIT_ENTRY_TYPE, nullable=False)

    # Signed delta: allocation is +N, consumption is -1, refund is +1.
    quantity = Column(Integer, nullable=False, default=0)

    # Only set for `consumed` rows. The unique constraint makes consumption
    # idempotent - a second completion attempt violates it.
    service_request_id = Column(
        Integer, ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=True
    )

    note = Column(String(255), nullable=True)

    created_at = Column(TIMESTAMP, server_default=func.now())

    __table_args__ = (
        UniqueConstraint(
            "subscription_id",
            "service_request_id",
            "entry_type",
            name="uq_visit_ledger_request_once",
        ),
        Index("idx_visit_ledger_sub_type", "subscription_id", "entry_type"),
    )
