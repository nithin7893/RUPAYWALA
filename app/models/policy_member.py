from sqlalchemy import Column, Integer, String, ForeignKey, TIMESTAMP
from sqlalchemy.orm import relationship as orm_relationship
from sqlalchemy.sql import func
from app.database import Base


class PolicyMember(Base):
    __tablename__ = "policy_members"

    id = Column(Integer, primary_key=True, index=True)

    policy_id = Column(Integer, ForeignKey("policies.id", ondelete="CASCADE"))

    member_name = Column(String(100))
    age = Column(Integer)
    relationship = Column(String(50))
    phone_number = Column(String(15), nullable=True)

    policy = orm_relationship("Policy", back_populates="members")

    created_at = Column(TIMESTAMP, server_default=func.now())
