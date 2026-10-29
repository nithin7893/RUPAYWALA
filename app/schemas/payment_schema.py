from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.payment import PaymentStatus


class PaymentCreateRequest(BaseModel):
    """The amount is NEVER accepted from the client - the backend prices it."""

    plan_id: Optional[int] = Field(default=None, gt=0, description="Subscription plan id")
    request_id: Optional[int] = Field(
        default=None, gt=0, description="Service request id for an extra-distance charge"
    )
    idempotency_key: Optional[str] = Field(default=None, max_length=120)

    def validate_purpose(self) -> "PaymentCreateRequest":
        if bool(self.plan_id) == bool(self.request_id):
            raise ValueError("Provide exactly one of plan_id or request_id")
        return self


class PaymentCreateResponse(BaseModel):
    txn_id: str
    payment_type: str
    amount: float
    base_amount: float = 0.0
    extra_charge: float = 0.0
    tax_amount: float = 0.0
    currency: str = "INR"
    upi_url: str
    qr_code: str
    status: PaymentStatus
    plan_id: Optional[int] = None
    plan_name: Optional[str] = None
    request_id: Optional[int] = None
    expires_at: datetime


class PaymentSubmitRequest(BaseModel):
    txn_id: str = Field(..., min_length=1, max_length=36)
    utr_number: str = Field(..., min_length=6, max_length=50)

    @field_validator("utr_number")
    @classmethod
    def sanitize_utr(cls, v: str) -> str:
        cleaned = "".join(ch for ch in v.strip() if ch.isalnum())
        if not cleaned:
            raise ValueError("Enter a valid UTR / reference number")
        return cleaned.upper()


class PaymentSubmitResponse(BaseModel):
    message: str
    txn_id: str
    status: PaymentStatus
    attempts: int = 0


class PaymentDetailResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    txn_id: str
    payment_type: str
    user_id: int
    plan_id: Optional[int] = None
    plan_name: Optional[str] = None
    related_request_id: Optional[int] = None
    amount: float
    base_amount: float = 0.0
    extra_charge: float = 0.0
    tax_amount: float = 0.0
    currency: str = "INR"
    status: PaymentStatus
    utr_number: Optional[str] = None
    attempts: int = 0
    failure_reason: Optional[str] = None
    admin_note: Optional[str] = None
    verified_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None


class PaymentListResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    txn_id: str
    payment_type: str
    user_id: int
    amount: float
    status: PaymentStatus
    utr_number: Optional[str] = None
    plan_name: Optional[str] = None
    related_request_id: Optional[int] = None
    submitted_at: Optional[datetime] = None
    verified_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class PaymentVerifyRequest(BaseModel):
    txn_id: str = Field(..., min_length=1, max_length=36)
    action: str = Field(..., pattern="^(approve|reject)$")
    note: Optional[str] = Field(default=None, max_length=500)


class PaymentVerifyResponse(BaseModel):
    message: str
    txn_id: str
    status: PaymentStatus
    subscription_id: Optional[int] = None
