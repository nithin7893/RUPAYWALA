from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator

GENDERS = {"male", "female", "other"}


class ProfileBase(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=120)
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    email: Optional[str] = Field(default=None, max_length=255)
    address: Optional[str] = Field(default=None, max_length=500)
    city: Optional[str] = Field(default=None, max_length=100)
    state: Optional[str] = Field(default=None, max_length=100)
    pincode: Optional[str] = Field(default=None, max_length=10)

    # Policy information
    policy_number: Optional[str] = Field(default=None, max_length=100)
    insurance_provider: Optional[str] = Field(default=None, max_length=150)
    policy_type: Optional[str] = Field(default=None, max_length=100)
    policy_details: Optional[str] = Field(default=None, max_length=1000)
    policy_valid_from: Optional[date] = None
    policy_valid_till: Optional[date] = None

    emergency_contact_name: Optional[str] = Field(default=None, max_length=120)
    emergency_contact_number: Optional[str] = Field(default=None, max_length=20)

    @field_validator("email")
    @classmethod
    def _validate_email(cls, v):
        if not v:
            return v
        if "@" not in v or "." not in v.split("@")[-1]:
            raise ValueError("Enter a valid email address")
        return v.strip().lower()

    @field_validator("gender")
    @classmethod
    def _validate_gender(cls, v):
        if v is None or v == "":
            return None
        if v.lower() not in GENDERS:
            raise ValueError("Gender must be male, female or other")
        return v.lower()

    @field_validator("pincode")
    @classmethod
    def _validate_pincode(cls, v):
        if v and not v.isdigit():
            raise ValueError("PIN code must contain digits only")
        return v

    @field_validator("emergency_contact_number")
    @classmethod
    def _validate_emergency(cls, v):
        if v and not v.replace("+", "").isdigit():
            raise ValueError("Emergency contact must be a number")
        return v

    @model_validator(mode="after")
    def _check_dates(self):
        if self.date_of_birth and self.date_of_birth > date.today():
            raise ValueError("Date of birth cannot be in the future")
        if self.policy_valid_from and self.policy_valid_till:
            if self.policy_valid_till < self.policy_valid_from:
                raise ValueError("Policy validity end date cannot be before the start date")
        return self


class ProfileCreate(ProfileBase):
    pass


class ProfileUpdate(ProfileBase):
    pass


class ProfileResponse(BaseModel):
    id: int
    user_id: int
    full_name: str
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    email: Optional[str] = None
    phone_number: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None
    policy_number: Optional[str] = None
    insurance_provider: Optional[str] = None
    policy_type: Optional[str] = None
    policy_details: Optional[str] = None
    policy_valid_from: Optional[date] = None
    policy_valid_till: Optional[date] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_number: Optional[str] = None
    profile_completed: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
