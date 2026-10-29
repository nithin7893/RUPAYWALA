from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from app.models.user_subscription import SubscriptionStatus


class SubscribeRequest(BaseModel):
    """Retained for compatibility. Activation now always requires a payment."""

    plan_id: int = Field(..., gt=0)
    number_of_policies: Optional[int] = Field(default=None, ge=0, le=1000)
    number_of_persons: Optional[int] = Field(default=None, ge=0, le=1000)


class PlanResponse(BaseModel):
    id: int
    code: Optional[str] = None
    plan_name: str
    plan_description: Optional[str] = None
    features: list[str] = Field(default_factory=list)
    price: float
    visits_included: int
    additional_visits: Optional[int] = None
    included_visit_distance_km: Optional[float] = None
    document_verification: bool = False
    online_submission: bool = False
    document_storage: bool = False
    storage_duration_days: Optional[int] = None
    priority_support: bool = False
    addon_eligibility: dict[str, bool] = Field(default_factory=dict)
    max_policies: Optional[int] = None
    max_family_members: Optional[int] = None
    max_adult_members: Optional[int] = None
    max_child_members: Optional[int] = None
    validity_days: int
    is_active: bool = True

    @field_validator("features", mode="before")
    @classmethod
    def _features_or_empty(cls, value):
        """Plans created before the features column existed have NULL there."""
        if value is None:
            return []
        if isinstance(value, str):
            return [value] if value.strip() else []
        return value

    @field_validator("addon_eligibility", mode="before")
    @classmethod
    def _addons_or_empty(cls, value):
        return value if isinstance(value, dict) else {}

    class Config:
        from_attributes = True


class SubscriptionResponse(BaseModel):
    id: int
    plan_id: int
    plan_name: Optional[str] = None
    price: Optional[float] = None
    entitlements: dict = Field(default_factory=dict)
    status: str
    total_visits: int
    used_visits: int
    remaining_visits: int
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    days_remaining: Optional[int] = None
    number_of_policies: int = 0
    number_of_persons: int = 0
    activated_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class VisitBalanceResponse(BaseModel):
    has_active_subscription: bool
    subscription_id: Optional[int] = None
    plan_name: Optional[str] = None
    total_visits: int = 0
    used_visits: int = 0
    remaining_visits: int = 0
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    status: str = "none"
    can_request_service: bool = False
    reason: Optional[str] = None


class VisitHistoryEntry(BaseModel):
    id: int
    type: str
    quantity: int
    service_request_id: Optional[int] = None
    note: Optional[str] = None
    created_at: Optional[datetime] = None


class FamilyMemberCreate(BaseModel):
    member_name: str = Field(..., min_length=2, max_length=100)
    relationship: str = Field(..., min_length=2, max_length=50)
    member_type: str = Field(..., pattern="^(adult|child)$")
    date_of_birth: Optional[date] = None

    @field_validator("member_name", "relationship")
    @classmethod
    def _trim_and_validate(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 2:
            raise ValueError("Value must contain at least two non-space characters")
        return value


class FamilyMemberResponse(BaseModel):
    id: int
    member_name: str
    relationship: str
    member_type: str
    date_of_birth: Optional[date] = None

    class Config:
        from_attributes = True


SubscriptionResponse.model_rebuild()
SubscriptionStatus  # re-exported for convenience in routes
