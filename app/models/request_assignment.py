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
    TIMESTAMP,
    UniqueConstraint,
    func,
)

from app.database import Base


class AssignmentStatus(enum.Enum):
    active = "active"
    unassigned = "unassigned"   # superseded by a reassignment
    cancelled = "cancelled"     # request was cancelled while assigned
    rejected = "rejected"       # field member declined / was suspended


#: New type - assignments had no status at all before this revision.
ASSIGNMENT_STATUS = Enum(AssignmentStatus, name="assignment_status")


class RequestAssignment(Base):
    __tablename__ = "request_assignments"

    id = Column(Integer, primary_key=True, index=True)

    request_id = Column(
        Integer,
        ForeignKey("service_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    field_member_id = Column(
        Integer, ForeignKey("field_members.id", ondelete="CASCADE"), nullable=False, index=True
    )

    assigned_by = Column(Integer, ForeignKey("users.id"), nullable=True)

    status = Column(
        ASSIGNMENT_STATUS, default=AssignmentStatus.active, nullable=False
    )

    notes = Column(String(255), nullable=True)
    unassigned_at = Column(DateTime, nullable=True)

    assigned_at = Column(TIMESTAMP, server_default=func.now())

    # "Only one ACTIVE assignment per request" is enforced in
    # app.services.assignment_service using SELECT ... FOR UPDATE, which works
    # identically on PostgreSQL and SQLite and avoids dialect-specific DDL.
    __table_args__ = (
        Index("idx_assignments_request_status", "request_id", "status"),
        Index("idx_assignments_member_status", "field_member_id", "status"),
    )
