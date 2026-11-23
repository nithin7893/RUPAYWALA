"""
Fixed quotation lifecycle.

A quotation is a persisted server-side promise, not a signed price sent to the
client. Creating one freezes the route, the effective database pricing
configuration, any subscription distance entitlement and the resulting amounts.
Consuming one is transactional and single-use: a row lock plus a unique
service-request link stops a quote being spent twice, even under concurrency.

The HMAC stored on the row is defence in depth. It does not replace the
database record; it detects a direct edit to the saved amount, rate, route or
binding fields so a tampered row is rejected instead of silently charged.
"""

import hashlib
import hmac
import json
import logging
import math
from datetime import datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.config import (
    QUOTE_LEGACY_SIGNING_SECRET,
    QUOTE_SIGNING_SECRET as _CONFIGURED_QUOTE_SIGNING_SECRET,
    QUOTE_VALIDITY_MINUTES,
    resolve_quote_signing_secret,
)
from app.models.branch import Branch
from app.models.policy import Policy
from app.models.service_quote import (
    SIGNATURE_VERSION,
    QuoteStatus,
    ServiceQuote,
    new_quote_ref,
)
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.service_type import ServiceType
from app.models.subscription_family_member import SubscriptionFamilyMember
from app.services import map_service as maps
from app.services.pricing_service import PricingConfig, build_quote, get_pricing_config
from app.services.subscription_service import SubscriptionService

logger = logging.getLogger(__name__)

#: Fail fast (at quote-service import, which happens on application startup)
#: rather than ever producing an HMAC with an empty or JWT-reused key.
QUOTE_SIGNING_SECRET = resolve_quote_signing_secret(_CONFIGURED_QUOTE_SIGNING_SECRET)
_LEGACY_QUOTE_SIGNING_SECRET = (QUOTE_LEGACY_SIGNING_SECRET or "").strip() or None

_COORD_QUANTUM = Decimal("0.0000001")


# ======================================================================
# Small helpers
# ======================================================================
def _dec(value) -> Decimal:
    return Decimal(str(value))


def _canonical_number(value):
    """A stable string for a numeric value regardless of database scale."""
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, Decimal):
        return format(value.normalize(), "f")
    if isinstance(value, int):
        return value
    try:
        return format(Decimal(str(value)).normalize(), "f")
    except Exception:  # pragma: no cover - defensive only
        return str(value)


def _normalise_coordinate(value) -> Decimal:
    """Round a coordinate to the exact persisted NUMERIC(10,7) scale.

    The signed canonical form must be byte-for-byte reproducible after the
    database has stored and returned the value. Doing this before signing,
    persisting and comparing removes the float-precision mismatch.
    """
    return _dec(value).quantize(_COORD_QUANTUM, rounding=ROUND_HALF_UP)


def _base_payload(quote: ServiceQuote) -> dict:
    """The immutable price promise shared by both payload versions."""
    return {
        "quote_ref": quote.quote_ref,
        "user_id": quote.user_id,
        "service_type_id": quote.service_type_id,
        "request_type": quote.request_type,
        "branch_id": quote.branch_id,
        "policy_id": quote.policy_id,
        "subscription_id": quote.subscription_id,
        "family_member_id": quote.family_member_id,
        "visit_required": bool(quote.visit_required),
        "customer_latitude": _canonical_number(quote.customer_latitude),
        "customer_longitude": _canonical_number(quote.customer_longitude),
        "customer_address": quote.customer_address,
        "customer_place_id": quote.customer_place_id,
        "distance_km": _canonical_number(quote.distance_km),
        "duration_minutes": _canonical_number(quote.duration_minutes),
        "distance_rate_config_id": quote.distance_rate_config_id,
        "threshold_km_used": _canonical_number(quote.threshold_km_used),
        "charge_per_km_used": _canonical_number(quote.charge_per_km_used),
        "round_trip_factor_used": _canonical_number(quote.round_trip_factor_used),
        "excess_distance_km": _canonical_number(quote.excess_distance_km),
        "entitlement_included_distance_km": _canonical_number(
            quote.entitlement_included_distance_km
        ),
        "base_amount": _canonical_number(quote.base_amount),
        "extra_charge": _canonical_number(quote.extra_charge),
        "tax_percent_used": _canonical_number(quote.tax_percent_used),
        "tax_amount": _canonical_number(quote.tax_amount),
        "total_amount": _canonical_number(quote.total_amount),
        "currency": quote.currency,
        "within_threshold": bool(quote.within_threshold),
        "requires_payment": bool(quote.requires_payment),
        "created_at": _canonical_number(quote.created_at),
        "expires_at": _canonical_number(quote.expires_at),
    }


def _legacy_signing_payload(quote: ServiceQuote) -> dict:
    """Version 1 payload: the price promise without lifecycle state."""
    return _base_payload(quote)


def _signing_payload(quote: ServiceQuote) -> dict:
    """Version 2 payload: price promise plus the complete lifecycle state."""
    payload = _base_payload(quote)
    payload.update(
        {
            "signature_version": int(quote.signature_version or 1),
            "status": quote.status.value if quote.status is not None else None,
            "consumed_at": _canonical_number(quote.consumed_at),
            "cancelled_at": _canonical_number(quote.cancelled_at),
            "service_request_id": quote.service_request_id,
        }
    )
    return payload


def _digest(payload: dict, secret: str) -> str:
    raw = json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    )
    return hmac.new(
        secret.encode("utf-8"), raw.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def _sign(quote: ServiceQuote) -> str:
    return _digest(_signing_payload(quote), QUOTE_SIGNING_SECRET)


def _sign_legacy(quote: ServiceQuote) -> str:
    if _LEGACY_QUOTE_SIGNING_SECRET is None:
        raise RuntimeError("QUOTE_LEGACY_SIGNING_SECRET is not configured")
    return _digest(_legacy_signing_payload(quote), _LEGACY_QUOTE_SIGNING_SECRET)


def _integrity_failure(quote: ServiceQuote) -> HTTPException:
    logger.warning("Quote integrity check failed for quote %s", quote.quote_ref)
    return HTTPException(
        status_code=409,
        detail="This quotation failed its integrity check. Please request a new quote.",
    )


def _inconsistent_binding(request_id: int | None) -> HTTPException:
    """Fail closed when the two sides of a quote/request link disagree."""
    logger.warning("Quote/request association mismatch for request %s", request_id)
    return HTTPException(
        status_code=409,
        detail="This request has an invalid quotation association. Please contact support.",
    )


def _verify_legacy_integrity(quote: ServiceQuote) -> None:
    """Verify a version 1 row without trusting unsigned lifecycle state.

    Version 1 did not sign status, timestamps or the request link, so such a
    row is only accepted while it is pristine and active. The first legitimate
    transition upgrades it to version 2.
    """
    if _LEGACY_QUOTE_SIGNING_SECRET is None:
        raise _integrity_failure(quote)
    if (
        quote.status != QuoteStatus.active
        or quote.consumed_at is not None
        or quote.cancelled_at is not None
        or quote.service_request_id is not None
    ):
        raise _integrity_failure(quote)
    if not quote.signature or not hmac.compare_digest(
        quote.signature, _sign_legacy(quote)
    ):
        raise _integrity_failure(quote)


def _verify_integrity(quote: ServiceQuote) -> None:
    version = int(quote.signature_version or 1)
    if version == 1:
        _verify_legacy_integrity(quote)
        return
    if version != SIGNATURE_VERSION:
        raise _integrity_failure(quote)
    if not quote.signature or not hmac.compare_digest(quote.signature, _sign(quote)):
        raise _integrity_failure(quote)


#: Lifecycle graph. Only an active quote may move; every terminal state is
#: final, so a consumed/cancelled/expired quote can never be reactivated.
_ALLOWED_TRANSITIONS: dict[QuoteStatus, set[QuoteStatus]] = {
    QuoteStatus.active: {
        QuoteStatus.consumed,
        QuoteStatus.cancelled,
        QuoteStatus.expired,
    },
    QuoteStatus.consumed: set(),
    QuoteStatus.cancelled: set(),
    QuoteStatus.expired: set(),
}


def _apply_transition(
    quote: ServiceQuote,
    target: QuoteStatus,
    now: datetime,
    *,
    service_request_id: int | None = None,
) -> None:
    """Apply one legal lifecycle transition and re-sign it atomically.

    The caller must already hold the row lock and must commit in the same
    transaction. Every field that changed is covered by the new signature.
    """
    if target not in _ALLOWED_TRANSITIONS.get(quote.status, set()):
        raise HTTPException(
            status_code=409, detail="This quotation can no longer change state"
        )

    if target == QuoteStatus.consumed:
        quote.consumed_at = now
        quote.service_request_id = service_request_id
    elif target == QuoteStatus.cancelled:
        quote.cancelled_at = now
    elif target == QuoteStatus.expired:
        # Expiry is only legal from active, where consumed_at is already null.
        quote.consumed_at = None

    quote.status = target
    quote.signature_version = SIGNATURE_VERSION
    quote.signature = _sign(quote)


def _validate_coordinates(latitude, longitude) -> tuple[Decimal, Decimal]:
    if latitude is None or longitude is None:
        raise HTTPException(status_code=400, detail="Service location coordinates are required")
    try:
        lat = float(latitude)
        lng = float(longitude)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Invalid service location coordinates")
    if not math.isfinite(lat) or not math.isfinite(lng):
        raise HTTPException(status_code=400, detail="Invalid service location coordinates")
    if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(status_code=400, detail="Invalid service location coordinates")
    if lat == 0.0 and lng == 0.0:
        # Missing coordinates are never silently interpreted as 0,0.
        raise HTTPException(status_code=400, detail="Enter a valid service location")
    # Normalise to the persisted NUMERIC(10,7) scale *before* signing, storing,
    # comparing or returning the snapshot.
    return _normalise_coordinate(lat), _normalise_coordinate(lng)


def _active_branch(db: Session, branch_id: int | None) -> Branch:
    branch = db.get(Branch, branch_id) if branch_id else None
    if branch is None:
        raise HTTPException(status_code=404, detail="Branch not found")
    if not branch.is_active:
        raise HTTPException(status_code=400, detail="That branch is no longer available")
    return branch


def _resolve_service(db: Session, service_type_id: int | None) -> ServiceType | None:
    if service_type_id is None:
        return None
    service = db.get(ServiceType, service_type_id)
    if service is None or not service.is_active:
        raise HTTPException(status_code=404, detail="Service type not found")
    return service


def _validate_policy(db: Session, user_id: int, policy_id: int | None) -> Policy:
    policy = db.get(Policy, policy_id) if policy_id else None
    if policy is None or policy.user_id != user_id:
        raise HTTPException(status_code=404, detail="Policy not found")
    if not policy.is_valid_on():
        raise HTTPException(
            status_code=400,
            detail="This policy has expired and cannot be used for a service request",
        )
    return policy


def _family_member_for_subscription(
    db: Session, subscription_id: int, family_member_id: int
) -> SubscriptionFamilyMember | None:
    return (
        db.query(SubscriptionFamilyMember)
        .filter(
            SubscriptionFamilyMember.id == family_member_id,
            SubscriptionFamilyMember.subscription_id == subscription_id,
        )
        .first()
    )


def _pricing_config_for_subscription(
    db: Session, subscription
) -> tuple[PricingConfig, float | None]:
    config = get_pricing_config(db)
    included = (subscription.entitlements_snapshot or {}).get(
        "included_visit_distance_km"
    )
    if included is None:
        return config, None
    return (
        PricingConfig(
            threshold_km=float(included),
            charge_per_km=config.charge_per_km,
            tax_percent=config.tax_percent,
            round_trip_factor=config.round_trip_factor,
            config_id=config.config_id,
        ),
        float(included),
    )


def _maps_or_503():
    try:
        return maps.get_map_service()
    except maps.MapProviderNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))


def _calculate_route(
    origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
):
    """Raw traffic-aware Google route.

    Tests patch this function, never the network, so the error translation in
    ``_route_distance`` is still exercised.
    """
    service = _maps_or_503()
    return maps.run_async(
        service.calculate_distance(
            origin_lat=origin_lat,
            origin_lng=origin_lng,
            dest_lat=dest_lat,
            dest_lng=dest_lng,
        )
    )


def _route_distance(
    origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
):
    """Traffic-aware Google route, with provider failures mapped to HTTP errors."""
    try:
        return _calculate_route(origin_lat, origin_lng, dest_lat, dest_lng)
    except maps.MapProviderNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except maps.MapProviderUnavailable as exc:
        logger.warning("Map provider unavailable while pricing a quote: %s", exc)
        raise HTTPException(
            status_code=503,
            detail="Location service is temporarily unavailable. Please try again.",
        )
    except maps.MapProviderError as exc:
        logger.warning("Map provider error while pricing a quote: %s", exc)
        raise HTTPException(status_code=400, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


def _coord_equal(client_value: float, stored_value) -> bool:
    left = _dec(client_value).quantize(_COORD_QUANTUM, rounding=ROUND_HALF_UP)
    right = _dec(stored_value).quantize(_COORD_QUANTUM, rounding=ROUND_HALF_UP)
    return left == right


def _binding_mismatch(quote: ServiceQuote, payload) -> str | None:
    if payload.service_type_id != quote.service_type_id:
        return "That quotation is for a different service"
    if (payload.request_type or "").strip() != quote.request_type:
        return "That quotation is for a different request type"
    if payload.branch_id != quote.branch_id:
        return "That quotation is for a different branch"
    if payload.policy_id != quote.policy_id:
        return "That quotation is for a different policy"
    if payload.family_member_id != quote.family_member_id:
        return "That quotation is for a different family member"
    if not _coord_equal(payload.customer_latitude, quote.customer_latitude) or not _coord_equal(
        payload.customer_longitude, quote.customer_longitude
    ):
        return "That quotation is for a different service location"
    return None


# ======================================================================
# Public service
# ======================================================================
class QuoteService:
    @staticmethod
    def create_quote(db: Session, *, user, payload) -> ServiceQuote:
        """Price and persist one fixed quotation for the authenticated customer."""
        service = _resolve_service(db, payload.service_type_id)
        latitude, longitude = _validate_coordinates(
            payload.customer_latitude, payload.customer_longitude
        )

        # Same entitlement authorization the existing request flow uses.
        subscription, visit_required = SubscriptionService.authorize_request(
            db,
            user.id,
            service.code if service is not None else payload.request_type,
        )

        family_member = None
        if payload.family_member_id is not None:
            family_member = _family_member_for_subscription(
                db, subscription.id, payload.family_member_id
            )
            if family_member is None:
                raise HTTPException(
                    status_code=404,
                    detail="Family member is not authorized for this subscription",
                )

        policy = _validate_policy(db, user.id, payload.policy_id)
        branch = _active_branch(db, payload.branch_id)

        config, included_distance = _pricing_config_for_subscription(db, subscription)

        if visit_required:
            # Customer -> branch, matching the existing request-creation path.
            distance = _route_distance(
                origin_lat=float(latitude),
                origin_lng=float(longitude),
                dest_lat=float(branch.latitude),
                dest_lng=float(branch.longitude),
            )
            distance_km = float(distance.distance_km)
            duration_minutes = float(distance.duration_minutes)
        else:
            # Digital services do not travel; no Google call is made.
            distance_km = 0.0
            duration_minutes = 0.0

        price = build_quote(distance_km=distance_km, config=config, base_amount=0.0)

        now = datetime.utcnow()
        validity = max(1, int(QUOTE_VALIDITY_MINUTES))
        quote = ServiceQuote(
            quote_ref=new_quote_ref(),
            signature="",
            signature_version=SIGNATURE_VERSION,
            user_id=user.id,
            service_type_id=payload.service_type_id,
            request_type=(payload.request_type or "").strip(),
            branch_id=branch.id,
            policy_id=policy.id,
            subscription_id=subscription.id,
            family_member_id=family_member.id if family_member is not None else None,
            visit_required=visit_required,
            customer_latitude=latitude,
            customer_longitude=longitude,
            customer_address=payload.customer_address.strip(),
            customer_place_id=payload.customer_place_id,
            distance_km=_dec(price.distance_km),
            duration_minutes=_dec(round(duration_minutes, 1)),
            distance_rate_config_id=config.config_id,
            threshold_km_used=_dec(price.threshold_km),
            charge_per_km_used=_dec(price.charge_per_km),
            round_trip_factor_used=_dec(price.round_trip_factor),
            excess_distance_km=_dec(price.excess_distance_km),
            entitlement_included_distance_km=(
                _dec(included_distance) if included_distance is not None else None
            ),
            base_amount=_dec(price.base_amount),
            extra_charge=_dec(price.extra_charge),
            tax_percent_used=_dec(price.tax_percent),
            tax_amount=_dec(price.tax_amount),
            total_amount=_dec(price.total_amount),
            currency="INR",
            within_threshold=price.within_threshold,
            requires_payment=price.extra_charge > 0,
            status=QuoteStatus.active,
            created_at=now,
            expires_at=now + timedelta(minutes=validity),
        )
        quote.signature = _sign(quote)
        db.add(quote)
        db.commit()
        db.refresh(quote)

        logger.info(
            "Quote %s created for user %s: distance=%skm total=Rs %s valid_until=%s",
            quote.quote_ref,
            user.id,
            quote.distance_km,
            quote.total_amount,
            quote.expires_at,
        )
        return quote

    @staticmethod
    def get_quote(db: Session, *, user, quote_ref: str) -> ServiceQuote:
        quote = (
            db.query(ServiceQuote)
            .filter(ServiceQuote.quote_ref == quote_ref)
            .populate_existing()
            .first()
        )
        if quote is None or quote.user_id != user.id:
            # Same response for missing and foreign quotes: no IDOR signal.
            raise HTTPException(status_code=404, detail="Quotation not found")

        _verify_integrity(quote)

        if not quote.is_expired():
            return quote

        # Expiry writes state. Re-read under a row lock so a concurrent
        # consumption or cancellation is never overwritten by a stale object,
        # and never transition a row whose status changed underneath us.
        locked = (
            db.query(ServiceQuote)
            .filter(ServiceQuote.quote_ref == quote_ref)
            .populate_existing()
            .with_for_update()
            .first()
        )
        if locked is None or locked.user_id != user.id:
            raise HTTPException(status_code=404, detail="Quotation not found")
        _verify_integrity(locked)

        if (
            locked.status == QuoteStatus.active
            and locked.expires_at <= datetime.utcnow()
        ):
            _apply_transition(locked, QuoteStatus.expired, datetime.utcnow())
            db.commit()
            db.refresh(locked)
        return locked

    @staticmethod
    def cancel_quote(db: Session, *, user, quote_ref: str) -> ServiceQuote:
        quote = (
            db.query(ServiceQuote)
            .filter(ServiceQuote.quote_ref == quote_ref)
            .populate_existing()
            .with_for_update()
            .first()
        )
        if quote is None or quote.user_id != user.id:
            raise HTTPException(status_code=404, detail="Quotation not found")

        _verify_integrity(quote)
        now = datetime.utcnow()

        if quote.status == QuoteStatus.cancelled:
            return quote
        if quote.status == QuoteStatus.consumed:
            raise HTTPException(
                status_code=409, detail="This quotation has already been used"
            )
        if quote.status == QuoteStatus.expired:
            raise HTTPException(
                status_code=410, detail="This quotation has expired. Please request a new quote."
            )
        if quote.expires_at <= now:
            _apply_transition(quote, QuoteStatus.expired, now)
            db.commit()
            raise HTTPException(
                status_code=410, detail="This quotation has expired. Please request a new quote."
            )

        _apply_transition(quote, QuoteStatus.cancelled, now)
        db.commit()
        db.refresh(quote)
        logger.info("Quote %s cancelled by user %s", quote.quote_ref, user.id)
        return quote

    @staticmethod
    def consume_for_request(db: Session, *, user, payload) -> ServiceRequest:
        """Validate a quote and turn it into a request in the caller's transaction.

        The caller must commit. Until it does, the quote lock is held and neither
        the consumed status nor the request is visible to another transaction.
        On any failure the caller's rollback restores the quote unchanged.
        """
        if not payload.quote_id:
            raise HTTPException(status_code=400, detail="A quotation is required")

        quote = (
            db.query(ServiceQuote)
            .filter(ServiceQuote.quote_ref == payload.quote_id)
            .populate_existing()
            .with_for_update()
            .first()
        )
        if quote is None or quote.user_id != user.id:
            raise HTTPException(status_code=404, detail="Quotation not found")

        now = datetime.utcnow()

        # Verify the stored lifecycle *before* trusting it or re-signing it.
        # This is what stops a consumed quote being flipped back to active.
        _verify_integrity(quote)

        if quote.status == QuoteStatus.cancelled:
            raise HTTPException(
                status_code=409, detail="This quotation has been cancelled"
            )
        if quote.status == QuoteStatus.consumed:
            raise HTTPException(
                status_code=409, detail="This quotation has already been used"
            )
        if quote.status == QuoteStatus.expired:
            raise HTTPException(
                status_code=410, detail="This quotation has expired. Please request a new quote."
            )
        if quote.status != QuoteStatus.active:
            raise HTTPException(
                status_code=409, detail="This quotation is no longer active"
            )
        if quote.expires_at <= now:
            _apply_transition(quote, QuoteStatus.expired, now)
            db.commit()
            raise HTTPException(
                status_code=410, detail="This quotation has expired. Please request a new quote."
            )

        mismatch = _binding_mismatch(quote, payload)
        if mismatch:
            raise HTTPException(status_code=409, detail=mismatch)

        # Re-run the existing authorization checks: the customer's subscription,
        # policy and service must still be valid at consumption time.
        service = _resolve_service(db, quote.service_type_id)
        _validate_policy(db, user.id, quote.policy_id)
        _active_branch(db, quote.branch_id)

        subscription, visit_required = SubscriptionService.authorize_request(
            db,
            user.id,
            service.code if service is not None else quote.request_type,
        )
        if subscription.id != quote.subscription_id:
            raise HTTPException(
                status_code=409,
                detail="Your active subscription has changed. Please request a new quote.",
            )
        if bool(visit_required) != bool(quote.visit_required):
            raise HTTPException(
                status_code=409,
                detail="This service is no longer covered the same way. Please request a new quote.",
            )
        if quote.family_member_id is not None:
            family_member = _family_member_for_subscription(
                db, subscription.id, quote.family_member_id
            )
            if family_member is None:
                raise HTTPException(
                    status_code=409,
                    detail="The family member on this quotation is no longer authorized",
                )

        requires_payment = bool(quote.requires_payment) or float(
            quote.extra_charge or 0
        ) > 0

        request = ServiceRequest(
            user_id=user.id,
            policy_id=quote.policy_id,
            service_type_id=quote.service_type_id,
            request_type=quote.request_type,
            description=payload.description,
            customer_latitude=quote.customer_latitude,
            customer_longitude=quote.customer_longitude,
            customer_address=quote.customer_address,
            customer_place_id=quote.customer_place_id,
            branch_id=quote.branch_id,
            distance_km=quote.distance_km,
            duration_minutes=quote.duration_minutes,
            threshold_km_used=quote.threshold_km_used,
            charge_per_km_used=quote.charge_per_km_used,
            round_trip_factor_used=quote.round_trip_factor_used,
            excess_distance_km=quote.excess_distance_km,
            distance_rate=quote.charge_per_km_used,
            base_amount=quote.base_amount,
            extra_charge=quote.extra_charge,
            tax_percent_used=quote.tax_percent_used,
            tax_amount=quote.tax_amount,
            total_amount=quote.total_amount,
            charge_paid=not requires_payment,
            subscription_id=quote.subscription_id,
            family_member_id=quote.family_member_id,
            visit_required=quote.visit_required,
            # Permanent association back to the authoritative signed quote.
            quote_ref=quote.quote_ref,
            status=(
                RequestStatus.payment_pending
                if requires_payment
                else RequestStatus.waiting_for_assignment
            ),
        )
        db.add(request)
        db.flush()

        _apply_transition(
            quote, QuoteStatus.consumed, now, service_request_id=request.id
        )
        db.flush()

        logger.info(
            "Quote %s consumed by user %s for request %s (Rs %s)",
            quote.quote_ref,
            user.id,
            request.id,
            quote.total_amount,
        )
        return request

    # ------------------------------------------------------------------
    # Quote-backed request integrity (payment boundary)
    # ------------------------------------------------------------------
    @staticmethod
    def verified_quote_for_request(
        db: Session, *, request: ServiceRequest
    ) -> ServiceQuote | None:
        """Return the signed quote that authorises this request's price.

        ``None`` is returned only for a genuine legacy request: neither the
        request's forward ``quote_ref`` nor any quote's reverse
        ``service_request_id`` contains evidence of a quote association.

        If either side contains evidence, the request is quote-backed and both
        directions must agree exactly. Removing one side, cross-linking two
        requests, pointing the reverse link elsewhere or deleting the quote is
        therefore detected instead of being silently downgraded to legacy.
        """
        forward_ref = getattr(request, "quote_ref", None)
        request_id = getattr(request, "id", None)

        reverse_quote = None
        if request_id is not None:
            reverse_quote = (
                db.query(ServiceQuote)
                .filter(ServiceQuote.service_request_id == request_id)
                .populate_existing()
                .first()
            )

        # A genuine legacy request has no association on either side.
        if not forward_ref and reverse_quote is None:
            return None

        if forward_ref:
            quote = (
                db.query(ServiceQuote)
                .filter(ServiceQuote.quote_ref == forward_ref)
                .populate_existing()
                .first()
            )
            if quote is None:
                raise HTTPException(
                    status_code=409,
                    detail="The quotation linked to this request is missing. Please contact support.",
                )
        else:
            # A reverse association alone proves this was quote-backed. The
            # missing forward reference is itself an inconsistency.
            quote = reverse_quote

        # Both sides must name the same single quote.
        if reverse_quote is not None and reverse_quote.quote_ref != quote.quote_ref:
            raise _inconsistent_binding(request_id)
        if quote.quote_ref != forward_ref:
            raise _inconsistent_binding(request_id)

        _verify_integrity(quote)

        if (
            quote.status != QuoteStatus.consumed
            or quote.service_request_id != request_id
            or quote.user_id != request.user_id
        ):
            raise _inconsistent_binding(request_id)
        return quote

    @staticmethod
    def request_pricing_authority(
        db: Session, *, request: ServiceRequest
    ) -> ServiceQuote | None:
        """Single authoritative quote/legacy classification for payment paths.

        Returns the verified quote for a quote-backed request, or ``None`` for a
        genuine legacy request. Any inconsistent association or frozen-pricing
        mismatch fails closed before a payment amount is trusted.
        """
        quote = QuoteService.verified_quote_for_request(db, request=request)
        if quote is not None:
            QuoteService.assert_request_matches_quote(request, quote)
        return quote

    @staticmethod
    def assert_request_matches_quote(request: ServiceRequest, quote: ServiceQuote) -> None:
        """Detect any edit to the request's quote-backed pricing snapshot.

        The quote is the signed authority, so every frozen pricing field copied
        onto the request must still equal it. Nothing is recalculated from the
        current configuration.
        """
        quantum = Decimal("0.01")
        fields = (
            "distance_km",
            "threshold_km_used",
            "charge_per_km_used",
            "round_trip_factor_used",
            "excess_distance_km",
            "base_amount",
            "extra_charge",
            "tax_percent_used",
            "tax_amount",
            "total_amount",
        )
        mismatched = [
            field
            for field in fields
            if _dec(getattr(request, field) or 0).quantize(quantum)
            != _dec(getattr(quote, field) or 0).quantize(quantum)
        ]
        if mismatched:
            logger.warning(
                "Request %s pricing no longer matches quote %s (fields: %s)",
                request.id,
                quote.quote_ref,
                ", ".join(mismatched),
            )
            raise HTTPException(
                status_code=409,
                detail="The price on this request no longer matches its quotation. Please contact support.",
            )
