from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


# ======================================================================
# Location search / place details
# ======================================================================
class LocationSearchRequest(BaseModel):
    query: str = Field(..., min_length=3, max_length=200)

    @field_validator("query")
    @classmethod
    def _strip(cls, v: str) -> str:
        return v.strip()


class PlaceSuggestionResponse(BaseModel):
    place_id: str
    name: str
    address: str
    latitude: float
    longitude: float


class PlaceDetailsResponse(BaseModel):
    place_id: Optional[str] = None
    name: str
    address: str
    latitude: float
    longitude: float
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None


class PlaceDetailsRequest(BaseModel):
    place_id: str = Field(..., min_length=1, max_length=200)


# ======================================================================
# Distance / charge
# ======================================================================
class DistanceQuoteRequest(BaseModel):
    """Either a branch_id, or an explicit destination coordinate pair."""

    customer_latitude: float = Field(..., ge=-90, le=90)
    customer_longitude: float = Field(..., ge=-180, le=180)
    branch_id: Optional[int] = Field(default=None, gt=0)
    destination_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    destination_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    base_amount: float = Field(default=0.0, ge=0)


class DistanceQuoteResponse(BaseModel):
    branch_id: Optional[int] = None
    branch_name: Optional[str] = None
    distance_km: float
    duration_minutes: float
    threshold_km: float
    charge_per_km: float
    round_trip_factor: float
    excess_distance_km: float
    base_amount: float
    extra_charge: float
    tax_percent: float
    tax_amount: float
    total_amount: float
    within_threshold: bool
    requires_payment: bool
    message: str


# ======================================================================
# Service request
# ======================================================================
class ServiceRequestCreate(BaseModel):
    policy_id: int = Field(..., gt=0)
    family_member_id: Optional[int] = Field(default=None, gt=0)
    request_type: str = Field(..., min_length=2, max_length=100)
    description: Optional[str] = Field(default=None, max_length=2000)
    service_type_id: Optional[int] = Field(default=None, gt=0)

    customer_latitude: float = Field(..., ge=-90, le=90)
    customer_longitude: float = Field(..., ge=-180, le=180)
    customer_address: str = Field(..., min_length=5, max_length=1000)
    customer_place_id: Optional[str] = Field(default=None, max_length=200)

    branch_id: int = Field(..., gt=0)

    @field_validator("request_type", "customer_address")
    @classmethod
    def _strip(cls, v: str) -> str:
        return v.strip()


class ServiceRequestUpdateStatus(BaseModel):
    status: str
    reason: Optional[str] = Field(default=None, max_length=255)


class ServiceRequestResponse(BaseModel):
    id: int
    reference: str
    user_id: int
    policy_id: Optional[int] = None
    policy_label: Optional[str] = None
    service_type_id: Optional[int] = None
    request_type: str
    description: Optional[str] = None

    customer_latitude: Optional[float] = None
    customer_longitude: Optional[float] = None
    customer_address: Optional[str] = None

    branch_id: Optional[int] = None
    branch_name: Optional[str] = None
    branch_address: Optional[str] = None
    branch_latitude: Optional[float] = None
    branch_longitude: Optional[float] = None

    distance_km: Optional[float] = None
    duration_minutes: Optional[float] = None
    threshold_km: Optional[float] = None
    charge_per_km: Optional[float] = None
    round_trip_factor: Optional[float] = None
    excess_distance_km: Optional[float] = None

    base_amount: float = 0.0
    extra_charge: float = 0.0
    tax_percent: Optional[float] = None
    tax_amount: float = 0.0
    total_amount: float = 0.0
    charge_paid: bool = True
    requires_payment: bool = False

    subscription_id: Optional[int] = None
    family_member_id: Optional[int] = None
    visit_required: bool = True
    visit_consumed: bool = False

    status: str
    status_label: str
    cancellation_reason: Optional[str] = None
    completion_notes: Optional[str] = None
    proof_image_url: Optional[str] = None

    assignment: Optional["AssignmentSummary"] = None
    payment: Optional["PaymentSummary"] = None

    assigned_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class AssignmentSummary(BaseModel):
    assignment_id: int
    field_member_id: int
    field_member_name: Optional[str] = None
    field_member_phone: Optional[str] = None
    employee_code: Optional[str] = None
    status: str
    assigned_at: Optional[datetime] = None


class PaymentSummary(BaseModel):
    txn_id: str
    amount: float
    status: str
    utr_number: Optional[str] = None
    created_at: Optional[datetime] = None


class ServiceTypeResponse(BaseModel):
    id: int
    code: str
    name: str
    description: Optional[str] = None
    icon: Optional[str] = None

    class Config:
        from_attributes = True


class CompleteRequestPayload(BaseModel):
    completion_notes: str = Field(..., min_length=5, max_length=2000)


class StartRequestPayload(BaseModel):
    note: Optional[str] = Field(default=None, max_length=500)


ServiceRequestResponse.model_rebuild()
