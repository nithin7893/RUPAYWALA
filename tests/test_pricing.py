"""Pricing must be computed on the backend and stay reproducible.

These tests pin the documented rule so a future refactor cannot quietly change
what customers are charged.
"""

from app.config import (
    DEFAULT_CHARGE_PER_KM,
    DEFAULT_DISTANCE_THRESHOLD_KM,
    DEFAULT_TAX_PERCENT,
    DISTANCE_ROUND_TRIP_FACTOR,
)
from app.services.pricing_service import (
    PricingConfig,
    build_quote,
    calculate_extra_charge,
)


def config(**overrides) -> PricingConfig:
    base = dict(
        threshold_km=DEFAULT_DISTANCE_THRESHOLD_KM,
        charge_per_km=DEFAULT_CHARGE_PER_KM,
        tax_percent=DEFAULT_TAX_PERCENT,
        round_trip_factor=DISTANCE_ROUND_TRIP_FACTOR,
        config_id=1,
    )
    base.update(overrides)
    return PricingConfig(**base)


class TestExtraChargeFormula:
    def test_documented_example(self):
        # threshold 10 km, Rs 20/km, distance 15 km -> 2 x 5 x 20 = Rs 200
        assert (
            calculate_extra_charge(15.0, 10.0, 20.0, 2.0) == 200.0
        )

    def test_distance_below_threshold_is_free(self):
        assert calculate_extra_charge(3.0, 10.0, 20.0, 2.0) == 0.0

    def test_distance_exactly_at_threshold_is_free(self):
        assert calculate_extra_charge(10.0, 10.0, 20.0, 2.0) == 0.0

    def test_slight_overage_is_charged(self):
        assert calculate_extra_charge(10.5, 10.0, 20.0, 2.0) == 20.0

    def test_round_trip_factor_is_applied(self):
        one_way = calculate_extra_charge(15.0, 10.0, 20.0, 1.0)
        round_trip = calculate_extra_charge(15.0, 10.0, 20.0, 2.0)
        assert round_trip == one_way * 2

    def test_result_is_money_rounded_to_paise(self):
        # 7.3 km over at Rs 13.37/km with a return trip must not produce floats
        # with long tails.
        amount = calculate_extra_charge(17.3, 10.0, 13.37, 2.0)
        assert amount == round(amount, 2)
        assert len(str(amount).split(".")[1]) <= 2

    def test_never_negative(self):
        assert calculate_extra_charge(1.0, 10.0, 20.0, 2.0) >= 0.0


class TestBuildQuote:
    def test_within_threshold_quote(self):
        quote = build_quote(5.0, config())
        assert quote.within_threshold is True
        assert quote.excess_distance_km == 0.0
        assert quote.extra_charge == 0.0
        assert quote.tax_amount == 0.0
        assert quote.total_amount == 0.0

    def test_beyond_threshold_includes_tax(self):
        quote = build_quote(15.0, config(threshold_km=10.0, charge_per_km=20.0, tax_percent=18.0))
        assert quote.within_threshold is False
        assert quote.excess_distance_km == 5.0
        assert quote.extra_charge == 200.0
        assert quote.tax_amount == 36.0
        assert quote.total_amount == 236.0

    def test_base_amount_is_carried_into_total(self):
        quote = build_quote(15.0, config(threshold_km=10.0, charge_per_km=20.0, tax_percent=0.0), base_amount=999.0)
        assert quote.base_amount == 999.0
        assert quote.total_amount == 1199.0

    def test_quote_is_immutable(self):
        quote = build_quote(12.0, config())
        try:
            quote.extra_charge = 1.0  # type: ignore[misc]
        except Exception as exc:
            assert "frozen" in str(type(exc).__name__).lower() or isinstance(exc, AttributeError)
        else:
            raise AssertionError("PriceQuote must be frozen")

    def test_quote_snapshots_config_for_audit(self):
        quote = build_quote(15.0, config(threshold_km=10.0, charge_per_km=20.0, round_trip_factor=2.0))
        # Even if the admin later changes the rate, the snapshot must keep the
        # values that were actually charged.
        assert quote.threshold_km == 10.0
        assert quote.charge_per_km == 20.0
        assert quote.config_id == 1

    def test_summary_line_is_customer_safe(self):
        quote = build_quote(15.0, config(threshold_km=10.0, charge_per_km=20.0, tax_percent=18.0))
        text = quote.summary_line()
        assert "Rs" in text
        assert "config_id" not in text
        assert "Decimal" not in text
