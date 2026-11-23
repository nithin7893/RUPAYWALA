from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.field_member import FieldMemberApprovalStatus
from app.utils.sms_service import is_valid_phone, normalise_phone


# ======================================================================
# Field member self-service
# ======================================================================
class UpdateStatusRequest(BaseModel):
    """Field member status update.

    `status` is intentionally limited to the transitions a field member owns.
    Admin-only states (assignment, payment) are not reachable from here.
    """

    request_id: int = Field(..., gt=0)
    status: str
    completion_notes: Optional[str] = Field(default=None, max_length=2000)
    note: Optional[str] = Field(default=None, max_length=500)

    @field_validator("status")
    @classmethod
    def _validate_status(cls, v: str) -> str:
        allowed = {"in_progress", "completed", "cancelled"}
        if v not in allowed:
            raise ValueError(f"Status must be one of {sorted(allowed)}")
        return v

    @field_validator("completion_notes")
    @classmethod
    def _require_notes(cls, v):
        return v.strip() if v else v


class FieldMemberApplicationRequest(BaseModel):
    """Self-service application to become a field member.

    The account role is still assigned by an admin - this only creates a
    pending profile.
    """

    full_name: str = Field(..., min_length=2, max_length=120)
    employee_code: Optional[str] = Field(default=None, max_length=50, pattern=r"^[A-Za-z0-9_-]+$")
    region: Optional[str] = Field(default=None, max_length=100)


class FieldMemberAvailabilityRequest(BaseModel):
    is_available: bool


class AdminFieldMemberCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.]+$")
    password: str = Field(..., min_length=8, max_length=72)
    full_name: str = Field(..., min_length=2, max_length=120)
    phone_number: str = Field(..., min_length=10, max_length=20)
    employee_code: Optional[str] = Field(
        default=None, max_length=50, pattern=r"^[A-Za-z0-9_-]+$"
    )
    region: Optional[str] = Field(default=None, max_length=100)

    @field_validator("username")
    @classmethod
    def _normalise_username(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator("full_name", "employee_code", "region")
    @classmethod
    def _strip_optional_text(cls, value: Optional[str]) -> Optional[str]:
        return value.strip() if value else value

    @field_validator("phone_number")
    @classmethod
    def _validate_phone(cls, value: str) -> str:
        phone = normalise_phone(value)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid 10-digit mobile number")
        return phone


# ======================================================================
# Admin views
# ======================================================================
class FieldMemberAdminResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    employee_code: Optional[str] = None
    full_name: Optional[str] = None
    region: Optional[str] = None
    phone_number: Optional[str] = None
    username: Optional[str] = None
    approval_status: FieldMemberApprovalStatus
    is_available: bool = True
    is_active: bool = True
    active_jobs: int = 0
    completed_jobs: int = 0
    rejection_reason: Optional[str] = None
    approved_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class FieldMemberApproveRequest(BaseModel):
    action: str = Field(..., pattern="^(approve|reject)$")
    reason: Optional[str] = Field(default=None, max_length=255)
    promote_role: bool = Field(
        default=True,
        description="Switch the linked user account to the field_member role",
    )


class AssignFieldMemberRequest(BaseModel):
    request_id: int = Field(..., gt=0)
    field_member_id: int = Field(..., gt=0)
    notes: Optional[str] = Field(default=None, max_length=255)


class FieldMemberJobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    assignment_id: int
    request_id: int
    reference: str
    status: str
    status_label: str
    request_type: str
    description: Optional[str] = None
    customer_name: Optional[str] = None
    customer_phone: Optional[str] = None
    customer_address: Optional[str] = None
    customer_latitude: Optional[float] = None
    customer_longitude: Optional[float] = None
    policy_label: Optional[str] = None
    branch_name: Optional[str] = None
    branch_address: Optional[str] = None
    distance_km: Optional[float] = None
    completion_notes: Optional[str] = None
    proof_image_url: Optional[str] = None
    proof_document_id: Optional[str] = None
    assigned_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class FieldMemberStatsResponse(BaseModel):
    assigned: int = 0
    in_progress: int = 0
    completed: int = 0
    completed_today: int = 0


# ======================================================================
# Admin dashboard
# ======================================================================
class DashboardStatsResponse(BaseModel):
    total_customers: int = 0
    total_field_members: int = 0
    pending_field_members: int = 0
    total_service_requests: int = 0
    open_requests: int = 0
    in_progress_requests: int = 0
    completed_today: int = 0
    cancelled_requests: int = 0
    active_subscriptions: int = 0
    expiring_subscriptions: int = 0
    payments: dict = {}


class DistanceRateResponse(BaseModel):
    threshold_km: float
    rate_per_km: float
    tax_percent: float
    round_trip_factor: float
    effective_at: Optional[datetime] = None
    updated_by: Optional[int] = None
    config_id: Optional[int] = None
    is_default: bool = True


class DistanceRateUpdate(BaseModel):
    threshold_km: float = Field(..., gt=0, le=500)
    rate_per_km: float = Field(..., ge=0, le=10000)
    tax_percent: float = Field(default=18.0, ge=0, le=100)
    round_trip_factor: float = Field(
        default=2.0, gt=0, le=10, description="2.0 for a return trip"
    )

    def describe_change(self, current_threshold: float, current_rate: float) -> str:
        if current_threshold != self.threshold_km or current_rate != self.rate_per_km:
            return (
                f"Distance pricing updated: included distance is now "
                f"{self.threshold_km:g} km at Rs {self.rate_per_km:g}/km beyond it."
            )
        return "Distance pricing re-published with the same values."


class ServiceTypeCreate(BaseModel):
    code: str = Field(..., min_length=2, max_length=50, pattern=r"^[A-Za-z0-9_]+$")
    name: str = Field(..., min_length=2, max_length=120)
    description: Optional[str] = Field(default=None, max_length=500)
    icon: Optional[str] = Field(default="support_agent", max_length=50)
    sort_order: int = 0


class SubscriptionPlanCreate(BaseModel):
    code: Optional[str] = Field(default=None, min_length=2, max_length=50, pattern=r"^[a-z0-9_]+$")
    plan_name: str = Field(..., min_length=2, max_length=100)
    plan_description: Optional[str] = Field(default=None, max_length=1000)
    features: list[str] = Field(default_factory=list)
    price: float = Field(..., ge=0)
    visits_included: int = Field(..., ge=0, le=1000)
    additional_visits: Optional[int] = Field(default=None, ge=0, le=1000)
    included_visit_distance_km: Optional[float] = Field(default=None, ge=0, le=1000)
    document_verification: bool = False
    online_submission: bool = False
    document_storage: bool = False
    storage_duration_days: Optional[int] = Field(default=None, ge=1, le=3650)
    priority_support: bool = False
    addon_eligibility: dict[str, bool] = Field(default_factory=dict)
    validity_days: int = Field(default=365, ge=1, le=3650)
    max_policies: Optional[int] = Field(default=None, ge=0)
    max_family_members: Optional[int] = Field(default=None, ge=0)
    max_adult_members: Optional[int] = Field(default=None, ge=0)
    max_child_members: Optional[int] = Field(default=None, ge=0)
    is_active: bool = True


class SubscriptionPlanUpdate(BaseModel):
    code: Optional[str] = Field(default=None, min_length=2, max_length=50, pattern=r"^[a-z0-9_]+$")
    plan_name: Optional[str] = Field(default=None, min_length=2, max_length=100)
    plan_description: Optional[str] = Field(default=None, max_length=1000)
    features: Optional[list[str]] = None
    price: Optional[float] = Field(default=None, ge=0)
    visits_included: Optional[int] = Field(default=None, ge=0, le=1000)
    additional_visits: Optional[int] = Field(default=None, ge=0, le=1000)
    included_visit_distance_km: Optional[float] = Field(default=None, ge=0, le=1000)
    document_verification: Optional[bool] = None
    online_submission: Optional[bool] = None
    document_storage: Optional[bool] = None
    storage_duration_days: Optional[int] = Field(default=None, ge=1, le=3650)
    priority_support: Optional[bool] = None
    addon_eligibility: Optional[dict[str, bool]] = None
    validity_days: Optional[int] = Field(default=None, ge=1, le=3650)
    max_policies: Optional[int] = Field(default=None, ge=0)
    max_family_members: Optional[int] = Field(default=None, ge=0)
    max_adult_members: Optional[int] = Field(default=None, ge=0)
    max_child_members: Optional[int] = Field(default=None, ge=0)
    is_active: Optional[bool] = None


class AdminUserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: Optional[str] = None
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    email: Optional[str] = None
    role: str
    is_verified: bool = False
    account_status: str = "active"
    profile_completed: bool = False
    active_subscription: bool = False
    created_at: Optional[datetime] = None
    last_login_at: Optional[datetime] = None


class UserStatusUpdate(BaseModel):
    action: str = Field(..., pattern="^(suspend|activate)$")
    reason: Optional[str] = Field(default=None, max_length=255)


class MaintenanceTaskResponse(BaseModel):
    expired_payments: int = 0
    expired_subscriptions: int = 0
    purged_otps: int = 0
