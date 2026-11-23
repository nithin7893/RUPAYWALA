import enum
from datetime import datetime

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


class RequestStatus(enum.Enum):
    """Service request lifecycle.

    Valid transitions are enforced in
    app.services.request_status_service.REQUEST_TRANSITIONS
    """

    requested = "requested"                    # customer submitted the request
    payment_pending = "payment_pending"        # extra distance charge awaiting payment
    payment_completed = "payment_completed"    # extra charge settled
    waiting_for_assignment = "waiting_for_assignment"
    assigned = "assigned"                      # field member allocated
    in_progress = "in_progress"                # field member started work
    completed = "completed"                    # service done, 1 visit consumed
    cancelled = "cancelled"


#: Statuses that count against the customer's visit balance. A visit is only
#: consumed on COMPLETED - not on request, payment or assignment.
TERMINAL_STATUSES = {RequestStatus.completed, RequestStatus.cancelled}

#: Statuses a field member may act on.
ACTIONABLE_BY_FIELD_MEMBER = {
    RequestStatus.assigned,
    RequestStatus.in_progress,
}

#: Statuses visible to the admin allocation queue.
ASSIGNABLE_STATUSES = {
    RequestStatus.payment_completed,
    RequestStatus.waiting_for_assignment,
}

#: Type name matches the enum already deployed as ``request_status``.
REQUEST_STATUS = Enum(RequestStatus, name="request_status")


class ServiceRequest(Base):
    __tablename__ = "service_requests"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    policy_id = Column(Integer, ForeignKey("policies.id"), nullable=True, index=True)
    service_type_id = Column(
        Integer, ForeignKey("service_types.id", ondelete="SET NULL"), nullable=True
    )

    request_type = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)

    # Fixed-quote linkage. NULL for legacy requests created without a quote.
    # The unique constraint means one quotation can never be attached to two
    # service requests, which complements the reverse unique link on
    # service_quotes.service_request_id.
    quote_ref = Column(String(64), nullable=True)

    # ---------------- customer location ----------------
    customer_latitude = Column(Numeric(10, 7), nullable=True)
    customer_longitude = Column(Numeric(10, 7), nullable=True)
    customer_address = Column(Text, nullable=True)
    customer_place_id = Column(String(120), nullable=True)

    # ---------------- branch selection ----------------
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True, index=True)

    # ---------------- pricing snapshot ----------------
    # Every value below is frozen at creation time so that later configuration
    # changes never alter a historical transaction.
    distance_km = Column(Numeric(10, 2), nullable=True)
    duration_minutes = Column(Numeric(10, 1), nullable=True)

    threshold_km_used = Column(Numeric(10, 2), nullable=True)
    charge_per_km_used = Column(Numeric(10, 2), nullable=True)
    round_trip_factor_used = Column(Numeric(4, 2), nullable=True)
    excess_distance_km = Column(Numeric(10, 2), nullable=True)

    base_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    extra_charge = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    tax_percent_used = Column(Numeric(5, 2), nullable=True)
    tax_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")
    total_amount = Column(Numeric(10, 2), nullable=False, default=0, server_default="0")

    # Legacy alias kept in sync with charge_per_km_used for compatibility.
    distance_rate = Column(Numeric(10, 2), nullable=True)

    charge_paid = Column(Boolean, default=True, nullable=False)

    # ---------------- visit credit ----------------
    subscription_id = Column(
        Integer, ForeignKey("user_subscriptions.id", ondelete="SET NULL"), nullable=True
    )
    family_member_id = Column(
        Integer,
        ForeignKey(
            "subscription_family_members.id",
            ondelete="SET NULL",
            name="fk_service_requests_family_member_id",
        ),
        nullable=True,
    )
    visit_required = Column(Boolean, nullable=False, default=True, server_default="true")
    visit_consumed = Column(Boolean, default=False, nullable=False, server_default="false")

    # ---------------- assignment / completion ----------------
    completion_notes = Column(Text, nullable=True)
    proof_image_url = Column(String, nullable=True)
    proof_document_id = Column(
        String(36),
        ForeignKey("document_records.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    cancellation_reason = Column(String(255), nullable=True)
    cancelled_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    status = Column(
        REQUEST_STATUS, default=RequestStatus.requested, nullable=False, index=True
    )

    assigned_at = Column(DateTime, nullable=True)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    cancelled_at = Column(DateTime, nullable=True)

    created_at = Column(TIMESTAMP, server_default=func.now())
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("quote_ref", name="uq_service_requests_quote_ref"),
        Index("idx_service_requests_user_status", "user_id", "status"),
        Index("idx_service_requests_status_branch", "status", "branch_id"),
    )

    # ---------------- pricing helpers ----------------
    @property
    def requires_payment(self) -> bool:
        return float(self.extra_charge or 0) > 0 and not self.charge_paid

    def snapshot(self) -> dict:
        return {
            "distance_km": float(self.distance_km or 0),
            "threshold_km": float(self.threshold_km_used or 0),
            "charge_per_km": float(self.charge_per_km_used or 0),
            "round_trip_factor": float(self.round_trip_factor_used or 1),
            "excess_distance_km": float(self.excess_distance_km or 0),
            "base_amount": float(self.base_amount or 0),
            "extra_charge": float(self.extra_charge or 0),
            "tax_percent": float(self.tax_percent_used or 0),
            "tax_amount": float(self.tax_amount or 0),
            "total_amount": float(self.total_amount or 0),
        }
