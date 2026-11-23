import enum
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Enum,
    Integer,
    String,
    TIMESTAMP,
    func,
)

from app.database import Base


class UserRole(enum.Enum):
    customer = "customer"
    field_member = "field_member"
    admin = "admin"


class AccountStatus(enum.Enum):
    active = "active"
    suspended = "suspended"


class AuthProvider(enum.Enum):
    """How the account was originally proved to the backend."""

    phone_otp = "phone_otp"
    google = "google"
    email_otp = "email_otp"


# Explicit type names keep PostgreSQL compatible with the enums that already
# exist in the deployed database, so migrations only ever need ADD VALUE.
USER_ROLE = Enum(UserRole, name="user_role")
ACCOUNT_STATUS = Enum(AccountStatus, name="account_status")
AUTH_PROVIDER = Enum(AuthProvider, name="auth_provider")


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), unique=True, nullable=True, index=True)
    username = Column(String(50), unique=True, nullable=True, index=True)
    email = Column(String(255), unique=True, nullable=True, index=True)

    password_hash = Column(String(255), nullable=True)

    role = Column(USER_ROLE, nullable=False, default=UserRole.customer)

    is_verified = Column(Boolean, default=False, nullable=False)

    # Incremented on password change/reset/logout-all to invalidate old JWTs.
    token_version = Column(Integer, default=0, nullable=False)

    account_status = Column(ACCOUNT_STATUS, default=AccountStatus.active, nullable=False)

    auth_provider = Column(AUTH_PROVIDER, default=AuthProvider.phone_otp, nullable=False)
    google_sub = Column(String(255), unique=True, nullable=True, index=True)

    email_verified = Column(Boolean, default=False, nullable=False)
    phone_verified = Column(Boolean, default=False, nullable=False)

    last_login_at = Column(DateTime, nullable=True)

    created_at = Column(TIMESTAMP, server_default=func.now())
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())

    def is_active(self) -> bool:
        return self.account_status == AccountStatus.active
