"""
Service catalogue - the list of services a customer can request.

Stored in the database (rather than a hard-coded list) so admin/ops can adjust
the catalogue without a code release.
"""

from sqlalchemy import Boolean, Column, Integer, String, Text, TIMESTAMP
from sqlalchemy.sql import func

from app.database import Base


class ServiceType(Base):
    __tablename__ = "service_types"

    id = Column(Integer, primary_key=True, index=True)

    code = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(120), nullable=False)
    description = Column(Text, nullable=True)
    icon = Column(String(50), default="support_agent")

    is_active = Column(Boolean, default=True, nullable=False)
    sort_order = Column(Integer, default=0, nullable=False, server_default="0")

    created_at = Column(TIMESTAMP, server_default=func.now())
