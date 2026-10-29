from sqlalchemy import Boolean, Column, Date, ForeignKey, Index, Integer, Numeric, String, TIMESTAMP
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class Policy(Base):
    __tablename__ = "policies"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    policy_type = Column(String(100), nullable=False)
    policy_category = Column(String(20), default="individual", nullable=False)
    provider_name = Column(String(100), nullable=False)
    policy_number = Column(String(100), nullable=False, index=True)

    coverage_amount = Column(Numeric(12, 2), nullable=True)

    start_date = Column(Date, nullable=True)
    expiry_date = Column(Date, nullable=True)

    document_url = Column(String, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)

    number_of_members = Column(Integer, nullable=True)

    members = relationship(
        "PolicyMember", back_populates="policy", cascade="all, delete-orphan"
    )

    created_at = Column(TIMESTAMP, server_default=func.now())
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())

    __table_args__ = (Index("idx_policies_user_active", "user_id", "is_active"),)

    def is_valid_on(self, on=None) -> bool:
        from datetime import date

        today = on or date.today()
        if not self.is_active:
            return False
        if self.expiry_date and today > self.expiry_date:
            return False
        return True
