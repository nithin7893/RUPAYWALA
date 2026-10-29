from sqlalchemy import (
    Boolean,
    Column,
    Date,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    TIMESTAMP,
)
from sqlalchemy.sql import func

from app.database import Base


class CustomerProfile(Base):
    __tablename__ = "customer_profiles"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )

    full_name = Column(String(120), nullable=False)
    date_of_birth = Column(Date, nullable=True)
    gender = Column(String(10), nullable=True)

    email = Column(String(255), nullable=True)
    phone_number = Column(String(20), nullable=True)

    address = Column(Text, nullable=True)
    city = Column(String(100), nullable=True)
    state = Column(String(100), nullable=True)
    pincode = Column(String(10), nullable=True)

    # ---- policy information surfaced on the profile screen ----
    policy_number = Column(String(100), nullable=True, index=True)
    insurance_provider = Column(String(150), nullable=True)
    policy_type = Column(String(100), nullable=True)
    policy_details = Column(Text, nullable=True)
    policy_valid_from = Column(Date, nullable=True)
    policy_valid_till = Column(Date, nullable=True)

    default_address_latitude = Column(String(20), nullable=True)
    default_address_longitude = Column(String(20), nullable=True)

    emergency_contact_name = Column(String(120), nullable=True)
    emergency_contact_number = Column(String(20), nullable=True)

    profile_completed = Column(Boolean, default=False, nullable=False)

    created_at = Column(TIMESTAMP, server_default=func.now())
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())
