from sqlalchemy import Boolean, Column, Integer, JSON, Numeric, String, TIMESTAMP, Text
from sqlalchemy.sql import func

from app.database import Base


class SubscriptionPlan(Base):
    __tablename__ = "subscription_plans"

    id = Column(Integer, primary_key=True, index=True)

    code = Column(String(50), unique=True, nullable=True, index=True)
    plan_name = Column(String(100), nullable=False)
    plan_description = Column(Text)
    features = Column(JSON, nullable=True)  # list[str] of benefit bullet points

    price = Column(Numeric(10, 2), nullable=False)

    # Entitlements are snapshotted onto each purchased subscription.
    visits_included = Column(Integer, nullable=False, default=0, server_default="0")
    additional_visits = Column(Integer, nullable=True)
    included_visit_distance_km = Column(Numeric(6, 2), nullable=True)
    document_verification = Column(Boolean, nullable=False, default=False, server_default="false")
    online_submission = Column(Boolean, nullable=False, default=False, server_default="false")
    document_storage = Column(Boolean, nullable=False, default=False, server_default="false")
    storage_duration_days = Column(Integer, nullable=True)
    priority_support = Column(Boolean, nullable=False, default=False, server_default="false")
    addon_eligibility = Column(JSON, nullable=False, default=dict, server_default="{}")

    max_policies = Column(Integer)
    max_family_members = Column(Integer)
    max_adult_members = Column(Integer, nullable=True)
    max_child_members = Column(Integer, nullable=True)

    validity_days = Column(Integer, nullable=False, default=365)

    is_active = Column(Boolean, default=True, nullable=False)
    sort_order = Column(Integer, default=0, nullable=False, server_default="0")

    created_at = Column(TIMESTAMP, server_default=func.now())
