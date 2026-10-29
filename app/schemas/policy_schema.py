from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from app.utils.sms_service import is_valid_phone, normalise_phone


class PolicyMemberCreate(BaseModel):
    member_name: str = Field(..., min_length=2, max_length=120)
    age: int = Field(..., ge=0, le=120)
    relationship: str = Field(..., min_length=2, max_length=50)
    phone_number: Optional[str] = Field(default=None, max_length=20)


class PolicyCreate(BaseModel):
    policy_type: str = Field(..., min_length=2, max_length=100)
    policy_category: str = "individual"
    provider_name: str = Field(..., min_length=2, max_length=100)
    policy_number: str = Field(..., min_length=2, max_length=100)
    coverage_amount: Optional[float] = Field(default=None, gt=0)
    start_date: Optional[date] = None
    expiry_date: Optional[date] = None
    number_of_members: Optional[int] = Field(default=None, ge=0, le=100)
    members: Optional[list[PolicyMemberCreate]] = None

    @field_validator("policy_category")
    @classmethod
    def _validate_category(cls, v: str) -> str:
        allowed = {"individual", "floater", "group"}
        if v not in allowed:
            raise ValueError(f"Policy category must be one of {sorted(allowed)}")
        return v

    @field_validator("expiry_date")
    @classmethod
    def _validate_expiry(cls, v):
        if v and v < date.today():
            raise ValueError("Policy expiry date cannot be in the past")
        return v

    @field_validator("policy_number")
    @classmethod
    def _validate_number(cls, v: str) -> str:
        return v.strip().upper()


class PolicyMemberResponse(BaseModel):
    id: int
    member_name: str
    age: int
    relationship: str
    phone_number: Optional[str] = None

    class Config:
        from_attributes = True


class PolicyResponse(BaseModel):
    id: int
    policy_type: str
    policy_category: str
    provider_name: str
    policy_number: str
    coverage_amount: Optional[float] = None
    start_date: Optional[date] = None
    expiry_date: Optional[date] = None
    document_url: Optional[str] = None
    is_active: bool = True
    number_of_members: Optional[int] = None
    members: list[PolicyMemberResponse] = []
    is_valid: bool = True
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True
