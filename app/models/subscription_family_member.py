from sqlalchemy import Column, Date, ForeignKey, Integer, String, TIMESTAMP, UniqueConstraint
from sqlalchemy.sql import func

from app.database import Base


class SubscriptionFamilyMember(Base):
    __tablename__ = "subscription_family_members"

    id = Column(Integer, primary_key=True, index=True)
    subscription_id = Column(
        Integer,
        ForeignKey("user_subscriptions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    member_name = Column(String(100), nullable=False)
    relationship = Column(String(50), nullable=False)
    member_type = Column(String(10), nullable=False)
    date_of_birth = Column(Date, nullable=True)
    identity_key = Column(String(250), nullable=False)
    created_at = Column(TIMESTAMP, server_default=func.now())

    __table_args__ = (
        UniqueConstraint(
            "subscription_id",
            "identity_key",
            name="uq_subscription_family_identity",
        ),
    )
