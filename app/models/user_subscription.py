import enum
from datetime import date, datetime

from sqlalchemy import (
    Column,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    TIMESTAMP,
    func,
)
from sqlalchemy.orm import relationship

from app.database import Base


class SubscriptionStatus(enum.Enum):
    pending = "pending"
    active = "active"
    expired = "expired"
    cancelled = "cancelled"


#: Type name matches the enum already deployed as ``subscription_status``.
SUBSCRIPTION_STATUS = Enum(SubscriptionStatus, name="subscription_status")


class UserSubscription(Base):
    __tablename__ = "user_subscriptions"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    plan_id = Column(
        Integer, ForeignKey("subscription_plans.id", ondelete="RESTRICT"), nullable=False
    )
    plan_name_snapshot = Column(String(100), nullable=True)
    price_snapshot = Column(Numeric(10, 2), nullable=True)
    entitlements_snapshot = Column(JSON, nullable=True)

    # payments -> user_subscriptions -> service_requests -> payments is a cycle;
    # use_alter breaks it so the constraint is added after all tables exist.
    payment_id = Column(
        Integer,
        ForeignKey(
            "payments.id",
            use_alter=True,
            ondelete="SET NULL",
            name="fk_user_subscriptions_payment_id",
        ),
        nullable=True,
    )

    # Visit credits for this subscription period.
    total_visits = Column(Integer, nullable=False, default=0, server_default="0")
    used_visits = Column(Integer, nullable=False, default=0, server_default="0")

    number_of_policies = Column(Integer, default=0)
    number_of_persons = Column(Integer, default=0)

    start_date = Column(Date)
    end_date = Column(Date)

    status = Column(
        SUBSCRIPTION_STATUS, default=SubscriptionStatus.pending, nullable=False
    )
    activated_at = Column(DateTime, nullable=True)
    cancelled_at = Column(DateTime, nullable=True)

    created_at = Column(TIMESTAMP, server_default=func.now())
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())

    # selectin rather than joined: these queries are locked with
    # SELECT ... FOR UPDATE to serialise visit accounting, and PostgreSQL
    # refuses FOR UPDATE across the nullable side of an outer join.
    plan = relationship("SubscriptionPlan", lazy="selectin")
    user = relationship("User", lazy="selectin")

    # ---------------- visit accounting ----------------
    @property
    def remaining_visits(self) -> int:
        return max(0, (self.total_visits or 0) - (self.used_visits or 0))

    def is_usable_on(self, on: date | None = None) -> bool:
        if self.status != SubscriptionStatus.active:
            return False
        today = on or date.today()
        if self.start_date and today < self.start_date:
            return False
        if self.end_date and today > self.end_date:
            return False
        return self.remaining_visits > 0
