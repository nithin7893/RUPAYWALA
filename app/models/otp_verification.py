import enum
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Enum,
    Index,
    Integer,
    String,
)
from sqlalchemy.sql import func

from app.database import Base


class OTPPurpose(enum.Enum):
    signup = "signup"
    login = "login"
    reset_password = "reset_password"
    email_signup = "email_signup"
    email_login = "email_login"


#: New type - the legacy table stored no purpose at all.
OTP_PURPOSE = Enum(OTPPurpose, name="otp_purpose")


class OTPVerification(Base):
    """One-time passcode issued to a phone number or email address.

    The code itself is never stored - only a salted hash, so a database leak
    cannot be replayed. `attempts` and `is_used` block brute forcing.
    """

    __tablename__ = "otp_verifications"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), nullable=True, index=True)
    email = Column(String(255), nullable=True, index=True)
    otp_hash = Column(String(128), nullable=False)
    purpose = Column(OTP_PURPOSE, default=OTPPurpose.signup, nullable=False)
    verified = Column(Boolean, default=False, nullable=False)
    is_used = Column(Boolean, default=False, nullable=False, server_default="false")
    attempts = Column(Integer, default=0, nullable=False, server_default="0")

    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        Index("idx_otp_phone_created", "phone_number", "created_at"),
        Index("idx_otp_email_created", "email", "created_at"),
    )

    def is_expired(self, now: datetime | None = None) -> bool:
        now = now or datetime.utcnow()
        return self.expires_at < now
