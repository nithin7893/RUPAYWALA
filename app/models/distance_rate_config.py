"""
Operational configuration managed by admins.

Distance threshold, charge per kilometre, tax percentage and the round-trip
factor are *database* values, never hard-coded constants. Each update creates a
new immutable row so the pricing applied to historical transactions can always
be reconstructed.
"""

from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, Numeric, TIMESTAMP
from sqlalchemy.sql import func

from app.database import Base


class DistanceRateConfig(Base):
    __tablename__ = "distance_rate_config"

    id = Column(Integer, primary_key=True, index=True)

    # Road distance (km) included in the plan at no extra cost.
    threshold_km = Column(
        Numeric(10, 2), nullable=False, default=10.0, server_default="10.0"
    )

    # Charge applied per kilometre beyond the threshold.
    rate_per_km = Column(
        Numeric(10, 2), nullable=False, default=20.0, server_default="20.0"
    )

    # GST / service tax percentage applied to the extra distance charge.
    tax_percent = Column(
        Numeric(5, 2), nullable=False, default=18.0, server_default="18.0"
    )

    # 2.0 means the field member travels to the customer and returns, so the
    # excess distance is billed twice.
    round_trip_factor = Column(
        Numeric(4, 2), nullable=False, default=2.0, server_default="2.0"
    )

    effective_at = Column(TIMESTAMP, server_default=func.now(), nullable=False)
    updated_by = Column(Integer, ForeignKey("users.id"), nullable=True)

    created_at = Column(TIMESTAMP, server_default=func.now())


def current_config(db) -> DistanceRateConfig | None:
    """Return the most recently effective configuration row, or None."""
    return (
        db.query(DistanceRateConfig)
        .order_by(
            DistanceRateConfig.effective_at.desc(),
            DistanceRateConfig.id.desc(),
        )
        .first()
    )
