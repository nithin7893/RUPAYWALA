"""
Central pricing authority.

Every rupee the customer is ever shown or charged is produced here, on the
backend. The frontend only renders the result.

Business rules
--------------
    distance <= threshold  ->  extra_charge = 0
    distance >  threshold  ->  extra_charge = round_trip_factor
                                           x (distance - threshold)
                                           x charge_per_km

with the default round_trip_factor of 2.0 because the field member travels to
the customer and returns.

Example (threshold 10 km, charge/km Rs 20, distance 15 km):
    2 x (15 - 10) x 20 = Rs 200

All values are returned as a frozen snapshot so they can be persisted on the
service request and remain reproducible after the admin changes the
configuration.
"""

from dataclasses import asdict, dataclass
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy.orm import Session

from app.config import (
    DEFAULT_CHARGE_PER_KM,
    DEFAULT_DISTANCE_THRESHOLD_KM,
    DEFAULT_TAX_PERCENT,
    DISTANCE_ROUND_TRIP_FACTOR,
)
from app.models.distance_rate_config import DistanceRateConfig, current_config

CENTS = Decimal("0.01")


def _q(value: Decimal | float | int) -> Decimal:
    return Decimal(str(value)).quantize(CENTS, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class PricingConfig:
    threshold_km: float
    charge_per_km: float
    tax_percent: float
    round_trip_factor: float
    config_id: int | None = None

    @property
    def is_default(self) -> bool:
        return self.config_id is None


@dataclass(frozen=True)
class PriceQuote:
    """Immutable pricing result for a single transaction."""

    distance_km: float
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
    config_id: int | None

    def as_dict(self) -> dict:
        return asdict(self)

    # -- human readable, free of API jargon (used for notifications) -----
    def summary_line(self) -> str:
        if self.within_threshold:
            return (
                f"Road distance {self.distance_km:.1f} km is within the "
                f"included {self.threshold_km:.0f} km. No extra charge."
            )
        return (
            f"Road distance {self.distance_km:.1f} km exceeds the included "
            f"{self.threshold_km:.0f} km by {self.excess_distance_km:.1f} km. "
            f"Extra charge Rs {self.extra_charge:.0f} "
            f"({self.excess_distance_km:.1f} km x Rs {self.charge_per_km:.0f}/km x "
            f"{self.round_trip_factor:.0f} return trip) plus "
            f"Rs {self.tax_amount:.0f} tax."
        )


def get_pricing_config(db: Session) -> PricingConfig:
    """Load the admin-managed configuration, falling back to safe defaults."""
    row: DistanceRateConfig | None = current_config(db)
    if row is None:
        return PricingConfig(
            threshold_km=DEFAULT_DISTANCE_THRESHOLD_KM,
            charge_per_km=DEFAULT_CHARGE_PER_KM,
            tax_percent=DEFAULT_TAX_PERCENT,
            round_trip_factor=DISTANCE_ROUND_TRIP_FACTOR,
            config_id=None,
        )
    return PricingConfig(
        threshold_km=float(row.threshold_km),
        charge_per_km=float(row.rate_per_km),
        tax_percent=float(row.tax_percent),
        round_trip_factor=float(row.round_trip_factor),
        config_id=row.id,
    )


def calculate_extra_charge(
    distance_km: float,
    threshold_km: float,
    charge_per_km: float,
    round_trip_factor: float = 2.0,
) -> float:
    """`2 x (distance - threshold) x charge_per_km`, floored at zero."""
    if distance_km <= threshold_km:
        return 0.0
    excess = Decimal(str(distance_km)) - Decimal(str(threshold_km))
    raw = excess * Decimal(str(charge_per_km)) * Decimal(str(round_trip_factor))
    return float(_q(max(raw, Decimal("0"))))


def build_quote(
    distance_km: float,
    config: PricingConfig,
    base_amount: float = 0.0,
) -> PriceQuote:
    """Produce the full, persisted pricing snapshot for one transaction."""
    distance = Decimal(str(distance_km))
    threshold = Decimal(str(config.threshold_km))

    if distance <= threshold:
        excess = Decimal("0")
    else:
        excess = distance - threshold

    extra = calculate_extra_charge(
        distance_km=distance_km,
        threshold_km=config.threshold_km,
        charge_per_km=config.charge_per_km,
        round_trip_factor=config.round_trip_factor,
    )
    tax = _q(Decimal(str(extra)) * Decimal(str(config.tax_percent)) / Decimal("100"))
    base = _q(base_amount)
    total = _q(base + Decimal(str(extra)) + tax)

    return PriceQuote(
        distance_km=round(float(distance), 2),
        threshold_km=config.threshold_km,
        charge_per_km=config.charge_per_km,
        round_trip_factor=config.round_trip_factor,
        excess_distance_km=round(float(excess), 2),
        base_amount=float(base),
        extra_charge=extra,
        tax_percent=config.tax_percent,
        tax_amount=float(tax),
        total_amount=float(total),
        within_threshold=extra == 0.0,
        config_id=config.config_id,
    )
