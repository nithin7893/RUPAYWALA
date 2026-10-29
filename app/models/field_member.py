import enum

from sqlalchemy import Boolean, Column, Enum, ForeignKey, Integer, String, TIMESTAMP
from sqlalchemy.sql import func

from app.database import Base


class FieldMemberApprovalStatus(enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    suspended = "suspended"


#: New type - field members previously had no approval workflow at all.
FIELD_MEMBER_APPROVAL = Enum(
    FieldMemberApprovalStatus, name="field_member_approval_status"
)


class FieldMember(Base):
    __tablename__ = "field_members"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )

    employee_code = Column(String(50), unique=True, nullable=True, index=True)

    full_name = Column(String(120), nullable=True)
    region = Column(String(100), nullable=True)

    approval_status = Column(
        FIELD_MEMBER_APPROVAL,
        default=FieldMemberApprovalStatus.pending,
        nullable=False,
    )
    approved_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    approved_at = Column(TIMESTAMP, nullable=True)
    rejection_reason = Column(String(255), nullable=True)

    is_available = Column(Boolean, default=True, nullable=False)

    created_at = Column(TIMESTAMP, server_default=func.now())

    def is_operational(self) -> bool:
        """Only approved + available field members may take work."""
        return (
            self.approval_status == FieldMemberApprovalStatus.approved
            and self.is_available
        )
