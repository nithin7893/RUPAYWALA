"""
Customer-facing service endpoints: locations, distances, pricing quotes and
service requests.

Authority rules enforced here
-----------------------------
* The branch and the destination are resolved on the server; the client only
  supplies coordinates or a place id.
* Road distance comes from the map provider (never a straight line), and the
  extra charge is computed by ``pricing_service`` from the *current database
  configuration*.
* On creation the whole price is snapshotted onto the request row, so a later
  admin change to the threshold/rate can never rewrite history.
* A customer may only ever read or cancel their own requests.
"""

import logging
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import desc
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.branch import Branch
from app.models.payment import Payment, PaymentType
from app.models.policy import Policy
from app.models.request_assignment import AssignmentStatus, RequestAssignment
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.subscription_family_member import SubscriptionFamilyMember
from app.models.service_type import ServiceType
from app.models.user import User
from app.schemas.service_request_schema import (
    DistanceQuoteRequest,
    DistanceQuoteResponse,
    LocationSearchRequest,
    PlaceDetailsRequest,
    PlaceDetailsResponse,
    PlaceSuggestionResponse,
    QuoteCreate,
    QuoteResponse,
    ServiceRequestCreate,
    ServiceRequestResponse,
    ServiceTypeResponse,
)
from app.schemas.branch_schema import BranchResponse, BranchWithDistance
from app.services import map_service as maps
from app.services.pricing_service import PricingConfig, build_quote, get_pricing_config
from app.services.quote_service import QuoteService
from app.services.request_status_service import RequestStatusService
from app.services.subscription_service import SubscriptionService
from app.services.visit_service import VisitService
from app.utils.dependencies import customer_required

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/service", tags=["Service Requests"])


# ======================================================================
# helpers
# ======================================================================
def _maps_or_503():
    try:
        return maps.get_map_service()
    except maps.MapProviderNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))


def _maps_guard(fn, *args, **kwargs):
    """Run an async map call from sync route code, mapping provider errors."""
    service = _maps_or_503()
    try:
        return maps.run_async(fn(service, *args, **kwargs))
    except maps.MapProviderNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except maps.MapProviderUnavailable as exc:
        logger.warning("Map provider unavailable: %s", exc)
        raise HTTPException(
            status_code=503,
            detail="Location service is temporarily unavailable. Please try again.",
        )
    except maps.MapProviderError as exc:
        logger.warning("Map provider error: %s", exc)
        raise HTTPException(status_code=400, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


def _active_branch(db: Session, branch_id: int) -> Branch:
    branch = db.get(Branch, branch_id)
    if branch is None:
        raise HTTPException(status_code=404, detail="Branch not found")
    if not branch.is_active:
        raise HTTPException(status_code=400, detail="That branch is no longer available")
    return branch


def _active_assignment(db: Session, request_id: int) -> RequestAssignment | None:
    return (
        db.query(RequestAssignment)
        .filter(
            RequestAssignment.request_id == request_id,
            RequestAssignment.status == AssignmentStatus.active,
        )
        .first()
    )


def _reference(db: Session, request_id: int) -> str:
    return f"RUP-{date.today().year}-{request_id:06d}"


def _policy_label(policy: Policy | None) -> str | None:
    if policy is None:
        return None
    return f"{policy.provider_name} - {policy.policy_number}"


def _payment_summary(db: Session, request_id: int) -> dict | None:
    payment = (
        db.query(Payment)
        .filter(
            Payment.related_request_id == request_id,
            Payment.payment_type == PaymentType.extra_charge,
        )
        .order_by(desc(Payment.id))
        .first()
    )
    if payment is None:
        return None
    return {
        "txn_id": payment.txn_id,
        "amount": float(payment.amount or 0),
        "status": payment.status.value,
        "utr_number": payment.utr_number,
        "created_at": payment.created_at,
    }


def _member_name(db: Session, field_member_id: int) -> tuple[str | None, str | None, str | None]:
    from app.models.field_member import FieldMember
    from app.models.customer_profile import CustomerProfile

    member = db.get(FieldMember, field_member_id)
    if member is None:
        return None, None, None
    profile = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == member.user_id)
        .first()
    )
    return (
        member.full_name or (profile.full_name if profile else None),
        _phone_of(db, member.user_id),
        member.employee_code,
    )


def _phone_of(db: Session, user_id: int) -> str | None:
    user = db.get(User, user_id)
    return user.phone_number if user else None


def _build_response(db: Session, request: ServiceRequest) -> ServiceRequestResponse:
    policy = db.get(Policy, request.policy_id) if request.policy_id else None
    branch = db.get(Branch, request.branch_id) if request.branch_id else None
    assignment = _active_assignment(db, request.id)
    member_summary = None
    if assignment is not None:
        name, phone, code = _member_name(db, assignment.field_member_id)
        member_summary = {
            "assignment_id": assignment.id,
            "field_member_id": assignment.field_member_id,
            "field_member_name": name,
            "field_member_phone": phone,
            "employee_code": code,
            "status": assignment.status.value,
            "assigned_at": assignment.assigned_at,
        }

    return ServiceRequestResponse(
        id=request.id,
        reference=_reference(db, request.id),
        user_id=request.user_id,
        policy_id=request.policy_id,
        policy_label=_policy_label(policy),
        service_type_id=request.service_type_id,
        request_type=request.request_type,
        description=request.description,
        customer_latitude=float(request.customer_latitude) if request.customer_latitude else None,
        customer_longitude=float(request.customer_longitude) if request.customer_longitude else None,
        customer_address=request.customer_address,
        branch_id=request.branch_id,
        branch_name=branch.name if branch else None,
        branch_address=branch.address if branch else None,
        branch_latitude=float(branch.latitude) if branch else None,
        branch_longitude=float(branch.longitude) if branch else None,
        distance_km=float(request.distance_km) if request.distance_km else None,
        duration_minutes=float(request.duration_minutes) if request.duration_minutes else None,
        threshold_km=float(request.threshold_km_used) if request.threshold_km_used else None,
        charge_per_km=float(request.charge_per_km_used) if request.charge_per_km_used else None,
        round_trip_factor=(
            float(request.round_trip_factor_used) if request.round_trip_factor_used else None
        ),
        excess_distance_km=(
            float(request.excess_distance_km) if request.excess_distance_km else None
        ),
        base_amount=float(request.base_amount or 0),
        extra_charge=float(request.extra_charge or 0),
        tax_percent=float(request.tax_percent_used) if request.tax_percent_used else None,
        tax_amount=float(request.tax_amount or 0),
        total_amount=float(request.total_amount or 0),
        charge_paid=bool(request.charge_paid),
        requires_payment=request.requires_payment,
        subscription_id=request.subscription_id,
        family_member_id=request.family_member_id,
        visit_required=bool(request.visit_required),
        visit_consumed=bool(request.visit_consumed),
        status=request.status.value,
        status_label=RequestStatusService.label(request.status),
        cancellation_reason=request.cancellation_reason,
        completion_notes=request.completion_notes,
        proof_image_url=request.proof_image_url,
        proof_document_id=request.proof_document_id,
        assignment=member_summary,
        payment=_payment_summary(db, request.id),
        assigned_at=request.assigned_at,
        started_at=request.started_at,
        completed_at=request.completed_at,
        created_at=request.created_at,
    )


def _quote_summary(db: Session, quote) -> QuoteResponse:
    """Render the persisted quote row. No value is recalculated here."""
    service = db.get(ServiceType, quote.service_type_id) if quote.service_type_id else None
    branch = db.get(Branch, quote.branch_id) if quote.branch_id else None
    policy = db.get(Policy, quote.policy_id) if quote.policy_id else None
    return QuoteResponse(
        quote_id=quote.quote_ref,
        status=quote.status.value,
        service_type_id=quote.service_type_id,
        service_type_name=service.name if service else None,
        request_type=quote.request_type,
        branch_id=quote.branch_id,
        branch_name=branch.name if branch else None,
        branch_address=branch.address if branch else None,
        policy_id=quote.policy_id,
        policy_label=_policy_label(policy),
        family_member_id=quote.family_member_id,
        distance_km=float(quote.distance_km) if quote.distance_km is not None else None,
        duration_minutes=(
            float(quote.duration_minutes) if quote.duration_minutes is not None else None
        ),
        threshold_km=(
            float(quote.threshold_km_used) if quote.threshold_km_used is not None else None
        ),
        charge_per_km=(
            float(quote.charge_per_km_used) if quote.charge_per_km_used is not None else None
        ),
        round_trip_factor=(
            float(quote.round_trip_factor_used)
            if quote.round_trip_factor_used is not None
            else None
        ),
        excess_distance_km=(
            float(quote.excess_distance_km)
            if quote.excess_distance_km is not None
            else None
        ),
        entitlement_included_distance_km=(
            float(quote.entitlement_included_distance_km)
            if quote.entitlement_included_distance_km is not None
            else None
        ),
        base_amount=float(quote.base_amount or 0),
        extra_charge=float(quote.extra_charge or 0),
        tax_percent=(
            float(quote.tax_percent_used) if quote.tax_percent_used is not None else None
        ),
        tax_amount=float(quote.tax_amount or 0),
        total_amount=float(quote.total_amount or 0),
        currency=quote.currency or "INR",
        within_threshold=bool(quote.within_threshold),
        requires_payment=bool(quote.requires_payment),
        created_at=quote.created_at,
        expires_at=quote.expires_at,
        consumed_at=quote.consumed_at,
        service_request_id=quote.service_request_id,
    )


# ======================================================================
# 1. Location services
# ======================================================================
@router.post("/geocode", response_model=list[PlaceSuggestionResponse])
def geocode(payload: LocationSearchRequest, _: User = Depends(customer_required)):
    """Address autocomplete backed by Google Places API (New)."""
    results = _maps_guard(
        lambda svc: svc.autosuggest(
            payload.query, limit=8, session_token=payload.session_token
        )
    )
    return [
        PlaceSuggestionResponse(
            place_id=r.place_id,
            name=r.name,
            address=r.address,
            latitude=r.latitude,
            longitude=r.longitude,
        )
        for r in results
    ]


@router.post("/place-details", response_model=PlaceDetailsResponse)
def place_details(payload: PlaceDetailsRequest, _: User = Depends(customer_required)):
    details = _maps_guard(
        lambda svc: svc.place_details(
            payload.place_id, session_token=payload.session_token
        )
    )
    return PlaceDetailsResponse(
        place_id=details.place_id,
        name=details.name,
        address=details.address,
        latitude=details.latitude,
        longitude=details.longitude,
        city=details.city,
        state=details.state,
        pincode=details.pincode,
        country=details.country,
    )


@router.get("/service-types", response_model=list[ServiceTypeResponse])
def list_service_types(db: Session = Depends(get_db), _: User = Depends(customer_required)):
    rows = (
        db.query(ServiceType)
        .filter(ServiceType.is_active.is_(True))
        .order_by(ServiceType.sort_order, ServiceType.id)
        .all()
    )
    return rows


@router.get("/branches", response_model=list[BranchResponse])
def list_branches(db: Session = Depends(get_db), _: User = Depends(customer_required)):
    rows = db.query(Branch).filter(Branch.is_active.is_(True)).order_by(Branch.name).all()
    return rows


# ======================================================================
# 2. Distance + price quote
# ======================================================================
@router.post("/check-distance", response_model=DistanceQuoteResponse)
def check_distance(
    payload: DistanceQuoteRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """Authoritative quote: real road distance from the branch to the customer.

    Either supply ``branch_id`` (the branch is used as the origin and the
    customer's coordinates as the destination) or an explicit destination pair.
    """
    branch_name: str | None = None
    branch_id: int | None = None

    if payload.branch_id is not None:
        branch = _active_branch(db, payload.branch_id)
        origin_lat, origin_lng = float(branch.latitude), float(branch.longitude)
        branch_name, branch_id = branch.name, branch.id
    elif payload.destination_latitude is not None and payload.destination_longitude is not None:
        origin_lat, origin_lng = payload.destination_latitude, payload.destination_longitude
    else:
        raise HTTPException(
            status_code=400, detail="Provide a branch_id or a destination coordinate"
        )

    distance = _maps_guard(
        lambda svc: svc.calculate_distance(
            origin_lat=origin_lat,
            origin_lng=origin_lng,
            dest_lat=payload.customer_latitude,
            dest_lng=payload.customer_longitude,
        )
    )
    return _quote_response(
        db,
        user_id=current_user.id,
        distance_km=distance.distance_km,
        duration_minutes=distance.duration_minutes,
        base_amount=payload.base_amount,
        branch_id=branch_id,
        branch_name=branch_name,
    )


@router.post("/nearest-branches", response_model=list[BranchWithDistance])
def nearest_branches(
    payload: DistanceQuoteRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """Rank active branches by real road distance, with the charge for each.

    One batched distance-matrix call covers every branch.
    """
    branches = db.query(Branch).filter(Branch.is_active.is_(True)).all()
    if not branches:
        raise HTTPException(status_code=404, detail="No branches are available")

    config = _pricing_config_for_user(db, current_user.id)
    origins = [(float(b.latitude), float(b.longitude)) for b in branches]
    results = _maps_guard(
        lambda svc: svc.distances_from_origin(
            origins=origins,
            dest_lat=payload.customer_latitude,
            dest_lng=payload.customer_longitude,
        )
    )
    if len(results) < len(branches):
        # Fall back to one call per branch if the batch response was partial.
        results = [
            _maps_guard(
                lambda svc, b=b: svc.calculate_distance(
                    origin_lat=payload.customer_latitude,
                    origin_lng=payload.customer_longitude,
                    dest_lat=float(b.latitude),
                    dest_lng=float(b.longitude),
                )
            )
            for b in branches
        ]

    rows: list[BranchWithDistance] = []
    for branch, result in zip(branches, results):
        quote = build_quote(
            distance_km=result.distance_km,
            config=config,
            base_amount=payload.base_amount,
        )
        rows.append(
            BranchWithDistance(
                id=branch.id,
                name=branch.name,
                address=branch.address,
                latitude=float(branch.latitude),
                longitude=float(branch.longitude),
                contact_number=branch.contact_number,
                distance_km=result.distance_km,
                duration_minutes=result.duration_minutes,
                excess_distance_km=quote.excess_distance_km,
                extra_charge=quote.extra_charge,
                tax_amount=quote.tax_amount,
                total_amount=quote.total_amount,
                within_threshold=quote.within_threshold,
            )
        )

    rows.sort(key=lambda r: r.distance_km)
    return rows


def _pricing_config_for_user(db: Session, user_id: int) -> PricingConfig:
    config = get_pricing_config(db)
    subscription = VisitService.get_active_subscription(db, user_id)
    included_distance = (
        (subscription.entitlements_snapshot or {}).get("included_visit_distance_km")
        if subscription is not None
        else None
    )
    if included_distance is None:
        return config
    return PricingConfig(
        threshold_km=float(included_distance),
        charge_per_km=config.charge_per_km,
        tax_percent=config.tax_percent,
        round_trip_factor=config.round_trip_factor,
        config_id=config.config_id,
    )


def _quote_response(
    db: Session,
    *,
    user_id: int,
    distance_km: float,
    duration_minutes: float,
    base_amount: float,
    branch_id: int | None,
    branch_name: str | None,
) -> DistanceQuoteResponse:
    """Turn a road distance into the customer-visible quote.

    The formula (2 x excess km x rate) lives only in ``pricing_service``.
    """
    config = _pricing_config_for_user(db, user_id)
    quote = build_quote(distance_km=distance_km, config=config, base_amount=base_amount)
    return DistanceQuoteResponse(
        branch_id=branch_id,
        branch_name=branch_name,
        distance_km=quote.distance_km,
        duration_minutes=duration_minutes,
        threshold_km=quote.threshold_km,
        charge_per_km=quote.charge_per_km,
        round_trip_factor=quote.round_trip_factor,
        excess_distance_km=quote.excess_distance_km,
        base_amount=quote.base_amount,
        extra_charge=quote.extra_charge,
        tax_percent=quote.tax_percent,
        tax_amount=quote.tax_amount,
        total_amount=quote.total_amount,
        within_threshold=quote.within_threshold,
        requires_payment=quote.extra_charge > 0,
        message=quote.summary_line(),
    )


# ======================================================================
# 3. Fixed quotations
# ======================================================================
@router.post(
    "/quote",
    response_model=QuoteResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_fixed_quote(
    payload: QuoteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """Create a persisted, expiring, single-use fixed-price quotation."""
    quote = QuoteService.create_quote(db, user=current_user, payload=payload)
    return _quote_summary(db, quote)


@router.get("/quote/{quote_id}", response_model=QuoteResponse)
def get_fixed_quote(
    quote_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    quote = QuoteService.get_quote(db, user=current_user, quote_ref=quote_id)
    return _quote_summary(db, quote)


@router.post("/quote/{quote_id}/cancel", response_model=QuoteResponse)
def cancel_fixed_quote(
    quote_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    quote = QuoteService.cancel_quote(db, user=current_user, quote_ref=quote_id)
    return _quote_summary(db, quote)


# ======================================================================
# 4. Create / read / cancel requests
# ======================================================================
@router.post(
    "/request",
    response_model=ServiceRequestResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_request(
    payload: ServiceRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    # Fixed-price path: the quote snapshot is authoritative. No distance or
    # pricing calculation happens again, so a later config/rate/cache change
    # cannot move the amount the customer was promised.
    if payload.quote_id:
        request = QuoteService.consume_for_request(db, user=current_user, payload=payload)
        db.commit()
        db.refresh(request)
        return _build_response(db, request)

    service_type = None
    if payload.service_type_id is not None:
        service_type = db.get(ServiceType, payload.service_type_id)
        if service_type is None or not service_type.is_active:
            raise HTTPException(status_code=404, detail="Service type not found")

    # 1. Check active plan benefits before any external map or pricing work.
    subscription, visit_required = SubscriptionService.authorize_request(
        db, current_user.id, service_type.code if service_type else payload.request_type
    )
    family_member = None
    if payload.family_member_id is not None:
        family_member = (
            db.query(SubscriptionFamilyMember)
            .filter(
                SubscriptionFamilyMember.id == payload.family_member_id,
                SubscriptionFamilyMember.subscription_id == subscription.id,
            )
            .first()
        )
        if family_member is None:
            raise HTTPException(
                status_code=404, detail="Family member is not authorized for this subscription"
            )

    # 2. Policy ownership.
    policy = db.get(Policy, payload.policy_id)
    if policy is None or policy.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Policy not found")
    if not policy.is_valid_on():
        raise HTTPException(
            status_code=400, detail="This policy has expired and cannot be used for a service request"
        )

    branch = _active_branch(db, payload.branch_id)

    # 3. Road distance and pricing are only relevant to a doorstep visit.
    config = get_pricing_config(db)
    included_distance = (subscription.entitlements_snapshot or {}).get(
        "included_visit_distance_km"
    )
    if visit_required:
        distance = _maps_guard(
            lambda svc: svc.calculate_distance(
                origin_lat=payload.customer_latitude,
                origin_lng=payload.customer_longitude,
                dest_lat=float(branch.latitude),
                dest_lng=float(branch.longitude),
            )
        )
        if included_distance is not None:
            config = PricingConfig(
                threshold_km=float(included_distance),
                charge_per_km=config.charge_per_km,
                tax_percent=config.tax_percent,
                round_trip_factor=config.round_trip_factor,
                config_id=config.config_id,
            )
        quote = build_quote(
            distance_km=distance.distance_km,
            config=config,
            base_amount=0.0,
        )
    else:
        class _NoTravel:
            distance_km = 0.0
            duration_minutes = 0.0

        distance = _NoTravel()
        quote = build_quote(distance_km=0.0, config=config, base_amount=0.0)

    requires_payment = quote.extra_charge > 0
    request = ServiceRequest(
        user_id=current_user.id,
        policy_id=policy.id,
        service_type_id=payload.service_type_id,
        request_type=payload.request_type,
        description=payload.description,
        customer_latitude=Decimal(str(payload.customer_latitude)),
        customer_longitude=Decimal(str(payload.customer_longitude)),
        customer_address=payload.customer_address,
        customer_place_id=payload.customer_place_id,
        branch_id=branch.id,
        distance_km=Decimal(str(quote.distance_km)),
        duration_minutes=Decimal(str(distance.duration_minutes)),
        threshold_km_used=Decimal(str(quote.threshold_km)),
        charge_per_km_used=Decimal(str(quote.charge_per_km)),
        round_trip_factor_used=Decimal(str(quote.round_trip_factor)),
        excess_distance_km=Decimal(str(quote.excess_distance_km)),
        distance_rate=Decimal(str(quote.charge_per_km)),
        base_amount=Decimal(str(quote.base_amount)),
        extra_charge=Decimal(str(quote.extra_charge)),
        tax_percent_used=Decimal(str(quote.tax_percent)),
        tax_amount=Decimal(str(quote.tax_amount)),
        total_amount=Decimal(str(quote.total_amount)),
        charge_paid=not requires_payment,
        subscription_id=subscription.id,
        family_member_id=family_member.id if family_member else None,
        visit_required=visit_required,
        status=(
            RequestStatus.payment_pending if requires_payment else RequestStatus.waiting_for_assignment
        ),
    )
    db.add(request)
    db.commit()
    db.refresh(request)

    logger.info(
        "Service request %s created by user %s: distance=%skm extra_charge=Rs %s",
        request.id,
        current_user.id,
        quote.distance_km,
        quote.extra_charge,
    )
    return _build_response(db, request)


@router.get("/my-requests", response_model=list[ServiceRequestResponse])
def my_requests(
    status_filter: str | None = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    query = db.query(ServiceRequest).filter(ServiceRequest.user_id == current_user.id)
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(",") if s.strip()}
        valid = {s.value for s in RequestStatus}
        unknown = wanted - valid
        if unknown:
            raise HTTPException(
                status_code=400, detail=f"Unknown status: {', '.join(sorted(unknown))}"
            )
        query = query.filter(ServiceRequest.status.in_([RequestStatus(s) for s in wanted]))
    rows = (
        query.order_by(desc(ServiceRequest.created_at), desc(ServiceRequest.id))
        .limit(min(limit, 200))
        .offset(max(offset, 0))
        .all()
    )
    return [_build_response(db, r) for r in rows]


@router.get("/request/{request_id}", response_model=ServiceRequestResponse)
def get_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    request = db.get(ServiceRequest, request_id)
    if request is None or request.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Service request not found")
    return _build_response(db, request)


@router.post("/request/{request_id}/cancel", response_model=ServiceRequestResponse)
def cancel_request(
    request_id: int,
    reason: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    request = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.id == request_id)
        .with_for_update()
        .first()
    )
    if request is None or request.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Service request not found")

    RequestStatusService.cancel(
        db, request, actor_user_id=current_user.id, reason=reason or "Cancelled by customer"
    )
    db.commit()
    db.refresh(request)
    return _build_response(db, request)


# ======================================================================
# 4. Extra charge payment shortcuts
# ======================================================================
@router.post("/request/{request_id}/pay-extra-charge")
def pay_extra_charge(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    """Create (or reuse) the UPI intent for the outstanding extra charge."""
    from app.services.payment_service import PaymentService

    payment, upi_url, qr_code = PaymentService.create_extra_charge_payment(
        db, user=current_user, request_id=request_id
    )
    return {
        "txn_id": payment.txn_id,
        "amount": float(payment.amount or 0),
        "upi_url": upi_url,
        "qr_code": qr_code,
        "status": payment.status.value,
        "expires_at": payment.expires_at,
    }


@router.post("/request/{request_id}/submit-extra-charge-utr")
def submit_extra_charge_utr(
    request_id: int,
    txn_id: str,
    utr_number: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    from app.services.payment_service import PaymentService

    request = db.get(ServiceRequest, request_id)
    if request is None or request.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Service request not found")

    payment = PaymentService.submit_payment(
        db, user=current_user, txn_id=txn_id, utr_number=utr_number
    )
    if payment.related_request_id != request_id:
        raise HTTPException(status_code=400, detail="That transaction is for a different request")
    return {
        "message": "Payment submitted. An admin will verify it shortly.",
        "txn_id": payment.txn_id,
        "status": payment.status.value,
    }
