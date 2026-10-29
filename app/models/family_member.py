from sqlalchemy import Column, Integer, String, Date, ForeignKey, TIMESTAMP
from sqlalchemy.sql import func
from app.database import Base


class FamilyMember(Base):
    __tablename__ = "family_members"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))

    member_name = Column(String(100))
    relationship = Column(String(50))
    date_of_birth = Column(Date)

    created_at = Column(TIMESTAMP, server_default=func.now())