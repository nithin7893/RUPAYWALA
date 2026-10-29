from typing import Optional
import re

from pydantic import BaseModel, Field, field_validator

from app.utils.sms_service import is_valid_phone, normalise_phone

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class PhoneOnly(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=20)

    @field_validator("phone_number")
    @classmethod
    def _validate(cls, v: str) -> str:
        phone = normalise_phone(v)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid 10-digit mobile number")
        return phone


class EmailOnly(BaseModel):
    email: str = Field(..., min_length=5, max_length=255)

    @field_validator("email")
    @classmethod
    def _validate(cls, v: str) -> str:
        email = v.strip().lower()
        if not EMAIL_RE.match(email):
            raise ValueError("Enter a valid email address")
        return email


class CheckUserRequest(PhoneOnly):
    pass


class SendOTPRequest(PhoneOnly):
    pass


class VerifyOTPRequest(PhoneOnly):
    otp: str = Field(..., min_length=4, max_length=10)


class SendEmailOTPRequest(EmailOnly):
    pass


class VerifyEmailOTPRequest(EmailOnly):
    otp: str = Field(..., min_length=4, max_length=10)


class RegisterRequest(BaseModel):
    """Registration completes a phone-OTP proof.

    The role is NEVER accepted from the client - customers are the only role a
    self-service signup may create.
    """

    phone_number: str = Field(..., min_length=10, max_length=20)
    username: str = Field(..., min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.]+$")
    password: str = Field(..., min_length=8, max_length=72)

    @field_validator("username")
    @classmethod
    def _normalise_username(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("phone_number")
    @classmethod
    def _validate_phone(cls, v: str) -> str:
        phone = normalise_phone(v)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid 10-digit mobile number")
        return phone


class EmailRegisterRequest(BaseModel):
    """Registration completes an email-OTP proof."""

    email: str = Field(..., min_length=5, max_length=255)
    username: str = Field(..., min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.]+$")
    password: str = Field(..., min_length=8, max_length=72)
    phone_number: Optional[str] = Field(default=None, min_length=10, max_length=20)

    @field_validator("username")
    @classmethod
    def _normalise_username(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("email")
    @classmethod
    def _validate_email(cls, v: str) -> str:
        email = v.strip().lower()
        if not EMAIL_RE.match(email):
            raise ValueError("Enter a valid email address")
        return email

    @field_validator("phone_number")
    @classmethod
    def _validate_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is None or v.strip() == "":
            return None
        phone = normalise_phone(v)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid 10-digit mobile number")
        return phone


class LoginRequest(BaseModel):
    """Login accepts EITHER a username or a phone number."""

    identifier: str = Field(..., min_length=3, max_length=120)
    password: str = Field(..., min_length=1, max_length=72)


class GoogleLoginRequest(BaseModel):
    id_token: Optional[str] = Field(default=None, min_length=20)
    access_token: Optional[str] = Field(default=None, min_length=20)

    def token(self) -> str:
        if self.id_token:
            return self.id_token
        if self.access_token:
            return self.access_token
        raise ValueError("Provide a Google ID token")


class ChangePasswordRequest(BaseModel):
    current_password: Optional[str] = Field(default=None, min_length=1, max_length=72)
    new_password: str = Field(..., min_length=8, max_length=72)


class ChangeUsernameRequest(BaseModel):
    username: str = Field(
        ..., min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.]+$"
    )
    current_password: Optional[str] = Field(default=None, min_length=1, max_length=72)

    @field_validator("username")
    @classmethod
    def _normalise_username(cls, value: str) -> str:
        return value.strip().lower()


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    role: str
    username: Optional[str] = None
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    email: Optional[str] = None
    is_verified: bool = True
    profile_completed: bool = False
    has_active_subscription: bool = False
    has_password: bool = False
