from sqlalchemy import Column, Integer, String, Text, Boolean, ForeignKey, Enum, TIMESTAMP
from sqlalchemy.sql import func
from app.database import Base
import enum


class NotificationCategory(enum.Enum):
    subscription = "subscription"
    payment = "payment"
    policy = "policy"
    service_request = "service_request"
    assignment = "assignment"
    account = "account"
    admin = "admin"


#: Type name matches the enum already deployed as ``notification_category``.
NOTIFICATION_CATEGORY = Enum(NotificationCategory, name="notification_category")


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    title = Column(String(200), nullable=False)
    message = Column(Text, nullable=False)

    category = Column(NOTIFICATION_CATEGORY, nullable=False)

    reference_type = Column(String(50), nullable=True)
    reference_id = Column(Integer, nullable=True)

    is_read = Column(Boolean, default=False)

    created_at = Column(TIMESTAMP, server_default=func.now())
