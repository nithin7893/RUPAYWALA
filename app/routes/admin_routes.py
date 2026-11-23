"""
Admin endpoints.

Everything here is gated by ``admin_required`` AND by a fresh database read of
the user, so a demoted or suspended admin loses access immediately. The one
rule that matters most: **a role is only ever granted by an admin**, never
taken from a request body during signup.
"""

import logging
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import desc, func, or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.branch import Branch
from app.models.customer_profile import CustomerProfile
from app.models.distance_rate_config import DistanceRateConfig
from app.models.field_member import FieldMember, FieldMemberApprovalStatus
from app.models.notification import NotificationCategory
from app.models.policy import Policy
from app.models.request_assignment import AssignmentStatus, RequestAssignment
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.service_type import ServiceType
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import AccountStatus, User, UserRole
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.schemas.branch_schema import BranchCreate, BranchResponse, BranchUpdate
from app.schemas.field_member_schema import (
    AdminFieldMemberCreate,
    AdminUserResponse,
    AssignFieldMemberRequest,
    DashboardStatsResponse,
    DistanceRateResponse,
    DistanceRateUpdate,
    FieldMemberAdminResponse,
    FieldMemberApproveRequest,
    MaintenanceTaskResponse,
    ServiceTypeCreate,
    SubscriptionPlanCreate,
    SubscriptionPlanUpdate,
    UserStatusUpdate,
)
from app.schemas.service_request_schema import ServiceRequestResponse, ServiceTypeResponse
from app.services import map_service as maps
from app.services.assignment_service import AssignmentService
from app.services.notification_service import NotificationService
from app.services.otp_service import OTPService
from app.services.payment_service import PaymentService
from app.services.pricing_service import get_pricing_config
from app.services.request_status_service import RequestStatusService
from app.services.subscription_service import SubscriptionService
from app.services.visit_service import VisitService
from app.utils.dependencies import admin_required
from app.utils.security import hash_password, validate_password_strength

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["Admin"])


# ======================================================================
# 1. Dashboard
# ======================================================================
@router.get("/dashboard", response_model=DashboardStatsResponse)
def dashboard(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    today = date.today()
    week_away = today + timedelta(days=7)

    def count(model, *filters) -> int:
        query = db.query(func.count(model.id))
        for f in filters:
            query = query.filter(f)
        return int(query.scalar() or 0)

    return DashboardStatsResponse(
        total_customers=count(User, User.role == UserRole.customer),
        total_field_members=count(FieldMember),
        pending_field_members=count(
            FieldMember, FieldMember.approval_status == FieldMemberApprovalStatus.pending
        ),
        total_service_requests=count(ServiceRequest),
        open_requests=count(
            ServiceRequest,
            ServiceRequest.status.in_(
                [
                    RequestStatus.requested,
                    RequestStatus.payment_pending,
                    RequestStatus.payment_completed,
                    RequestStatus.waiting_for_assignment,
                    RequestStatus.assigned,
                    RequestStatus.in_progress,
                ]
            ),
        ),
        in_progress_requests=count(ServiceRequest, ServiceRequest.status == RequestStatus.in_progress),
        completed_today=count(
            ServiceRequest,
            ServiceRequest.status == RequestStatus.completed,
            ServiceRequest.completed_at >= datetime.combine(today, datetime.min.time()),
        ),
        cancelled_requests=count(ServiceRequest, ServiceRequest.status == RequestStatus.cancelled),
        active_subscriptions=count(
            UserSubscription, UserSubscription.status == SubscriptionStatus.active
        ),
        expiring_subscriptions=count(
            UserSubscription,
            UserSubscription.status == SubscriptionStatus.active,
            UserSubscription.end_date <= week_away,
        ),
        payments=PaymentService.dashboard_counts(db),
    )


# ======================================================================
# 2. Requests
# ======================================================================
@router.get("/requests", response_model=list[ServiceRequestResponse])
def list_requests(
    status_filter: str | None = None,
    branch_id: int | None = None,
    unassigned_only: bool = False,
    limit: int = 100,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    query = db.query(ServiceRequest)
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(",") if s.strip()}
        try:
            query = query.filter(ServiceRequest.status.in_([RequestStatus(s) for s in wanted]))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=f"Unknown status: {exc}")
    if branch_id:
        query = query.filter(ServiceRequest.branch_id == branch_id)
    if unassigned_only:
        query = query.filter(
            ServiceRequest.status.in_(
                [
                    RequestStatus.payment_completed,
                    RequestStatus.waiting_for_assignment,
                ]
            )
        )
    rows = query.order_by(desc(ServiceRequest.created_at)).limit(min(limit, 500)).all()

    from app.routes.service_routes import _build_response  # shared shaping

    return [_build_response(db, r) for r in rows]


@router.post("/assign-field-member")
def assign_field_member(
    payload: AssignFieldMemberRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Allocate a job. Locks the request so it can never get two owners."""
    assignment = AssignmentService.assign(
        db,
        request_id=payload.request_id,
        field_member_id=payload.field_member_id,
        assigned_by_user_id=admin.id,
        notes=payload.notes,
    )

    member = db.get(FieldMember, payload.field_member_id)
    request = db.get(ServiceRequest, payload.request_id)

    NotificationService.create(
        db,
        user_id=member.user_id,
        title="New service assigned",
        message=(
            f"{request.request_type} at {request.customer_address}. "
            "Please start the visit from your My Jobs screen."
        ),
        category=NotificationCategory.assignment,
        reference_type="service_request",
        reference_id=request.id,
    )
    db.commit()

    return {
        "message": "Field member assigned",
        "assignment_id": assignment.id,
        "request_id": payload.request_id,
        "status": request.status.value,
    }


@router.post("/unassign-field-member")
def unassign_field_member(
    request_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    AssignmentService.unassign(db, request_id=request_id, actor_user_id=admin.id)
    db.commit()
    return {"message": "Assignment released", "request_id": request_id}


@router.post("/requests/{request_id}/cancel")
def admin_cancel_request(
    request_id: int,
    reason: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Cancel a request; a consumed visit is refunded when the job had finished."""
    request = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.id == request_id)
        .with_for_update()
        .first()
    )
    if request is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    refunded = False
    if request.status == RequestStatus.completed:
        refunded = VisitService.refund_for_request(
            db, request, note=f"Refund: cancelled by admin #{admin.id}"
        )
        # A completed request has no outgoing transition, so the cancellation is
        # recorded explicitly.
        request.status = RequestStatus.cancelled
        request.cancelled_at = datetime.utcnow()
        request.cancellation_reason = reason or "Cancelled by admin"
        request.cancelled_by_user_id = admin.id
    else:
        RequestStatusService.cancel(
            db, request, actor_user_id=admin.id, reason=reason or "Cancelled by admin"
        )

    NotificationService.create(
        db,
        user_id=request.user_id,
        title="Service request cancelled",
        message=request.cancellation_reason or "Your service request was cancelled.",
        category=NotificationCategory.service_request,
        reference_type="service_request",
        reference_id=request.id,
    )
    db.commit()
    return {
        "message": "Request cancelled",
        "visit_refunded": refunded,
        "status": request.status.value,
    }


# ======================================================================
# 3. Field members
# ======================================================================
@router.get("/field-members", response_model=list[FieldMemberAdminResponse])
def list_field_members(
    approval_status: str | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    query = db.query(FieldMember).outerjoin(User, FieldMember.user_id == User.id)
    if approval_status:
        try:
            query = query.filter(
                FieldMember.approval_status == FieldMemberApprovalStatus(approval_status)
            )
        except ValueError:
            raise HTTPException(
                status_code=400, detail="approval_status must be pending, approved, rejected or suspended"
            )

    out = []
    for member in query.order_by(FieldMember.id.desc()).all():
        user = db.get(User, member.user_id)
        profile = (
            db.query(CustomerProfile).filter(CustomerProfile.user_id == member.user_id).first()
        )
        active_jobs = (
            db.query(func.count(ServiceRequest.id))
            .join(
                RequestAssignment,
                ServiceRequest.id == RequestAssignment.request_id,
            )
            .filter(
                RequestAssignment.field_member_id == member.id,
                RequestAssignment.status == AssignmentStatus.active,
                ServiceRequest.status.in_(
                    [RequestStatus.assigned, RequestStatus.in_progress]
                ),
            )
            .scalar()
            or 0
        )
        completed_jobs = (
            db.query(func.count(ServiceRequest.id))
            .join(
                RequestAssignment,
                ServiceRequest.id == RequestAssignment.request_id,
            )
            .filter(
                RequestAssignment.field_member_id == member.id,
                ServiceRequest.status == RequestStatus.completed,
            )
            .scalar()
            or 0
        )
        out.append(
            FieldMemberAdminResponse(
                id=member.id,
                user_id=member.user_id,
                employee_code=member.employee_code,
                full_name=member.full_name or (profile.full_name if profile else None),
                region=member.region,
                phone_number=user.phone_number if user else None,
                username=user.username if user else None,
                approval_status=member.approval_status,
                is_available=member.is_available,
                is_active=bool(user and user.account_status == AccountStatus.active),
                active_jobs=int(active_jobs),
                completed_jobs=int(completed_jobs),
                rejection_reason=member.rejection_reason,
                approved_at=member.approved_at,
                created_at=member.created_at,
            )
        )
    return out


@router.post(
    "/field-members",
    response_model=FieldMemberAdminResponse,
    status_code=201,
)
def create_field_member(
    payload: AdminFieldMemberCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Create an approved field-member account directly from the admin panel."""
    password_problem = validate_password_strength(payload.password)
    if password_problem:
        raise HTTPException(status_code=400, detail=password_problem)

    if db.query(User).filter(func.lower(User.username) == payload.username).first():
        raise HTTPException(status_code=409, detail="That username is already taken")
    if db.query(User).filter(User.phone_number == payload.phone_number).first():
        raise HTTPException(
            status_code=409, detail="This mobile number is already registered"
        )
    if payload.employee_code and db.query(FieldMember).filter(
        FieldMember.employee_code == payload.employee_code
    ).first():
        raise HTTPException(
            status_code=409, detail="That employee code is already in use"
        )

    user = User(
        phone_number=payload.phone_number,
        username=payload.username,
        password_hash=hash_password(payload.password),
        role=UserRole.field_member,
        is_verified=True,
        phone_verified=True,
        account_status=AccountStatus.active,
    )
    db.add(user)
    db.flush()
    member = FieldMember(
        user_id=user.id,
        employee_code=payload.employee_code,
        full_name=payload.full_name,
        region=payload.region,
        approval_status=FieldMemberApprovalStatus.approved,
        approved_by=admin.id,
        approved_at=datetime.utcnow(),
        is_available=True,
    )
    db.add(member)
    db.commit()
    db.refresh(user)
    db.refresh(member)

    logger.info("Field member %s created by admin %s", member.id, admin.id)
    return FieldMemberAdminResponse(
        id=member.id,
        user_id=user.id,
        employee_code=member.employee_code,
        full_name=member.full_name,
        region=member.region,
        phone_number=user.phone_number,
        username=user.username,
        approval_status=member.approval_status,
        is_available=member.is_available,
        is_active=user.account_status == AccountStatus.active,
        created_at=member.created_at,
        approved_at=member.approved_at,
    )


@router.delete("/field-members/{field_member_id}")
def deactivate_field_member(
    field_member_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Revoke access without deleting assignment and service history."""
    member = db.get(FieldMember, field_member_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Field member not found")

    active_jobs = (
        db.query(func.count(ServiceRequest.id))
        .join(RequestAssignment, ServiceRequest.id == RequestAssignment.request_id)
        .filter(
            RequestAssignment.field_member_id == member.id,
            RequestAssignment.status == AssignmentStatus.active,
            ServiceRequest.status.in_(
                [RequestStatus.assigned, RequestStatus.in_progress]
            ),
        )
        .scalar()
        or 0
    )
    if active_jobs:
        raise HTTPException(
            status_code=409,
            detail=(
                f"This field member has {active_jobs} active job(s). "
                "Reassign or close them before removing access."
            ),
        )

    user = db.get(User, member.user_id)
    if user is None:
        raise HTTPException(status_code=409, detail="The linked account no longer exists")
    user.account_status = AccountStatus.suspended
    member.approval_status = FieldMemberApprovalStatus.suspended
    member.is_available = False
    db.commit()

    logger.info("Field member %s deactivated by admin %s", member.id, admin.id)
    return {"message": "Field member access removed"}


@router.post("/field-members/{field_member_id}/review")
def review_field_member(
    field_member_id: int,
    payload: FieldMemberApproveRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Approve or reject a field member.

    Approval also promotes the linked user account to the ``field_member`` role
    when ``promote_role`` is set - the only place in the app where a role is
    granted.
    """
    member = db.get(FieldMember, field_member_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Field member not found")

    user = db.get(User, member.user_id)
    if user is None:
        raise HTTPException(status_code=409, detail="The linked account no longer exists")

    if payload.action == "approve":
        member.approval_status = FieldMemberApprovalStatus.approved
        member.approved_by = admin.id
        member.approved_at = datetime.utcnow()
        member.rejection_reason = None
        if payload.promote_role and user.role == UserRole.customer:
            user.role = UserRole.field_member
    else:
        if not payload.reason:
            raise HTTPException(status_code=400, detail="Please give a reason for rejection")
        member.approval_status = FieldMemberApprovalStatus.rejected
        member.rejection_reason = payload.reason

    db.commit()
    return {
        "message": (
            "Field member approved" if payload.action == "approve" else "Field member rejected"
        ),
        "approval_status": member.approval_status.value,
        "user_role": user.role.value,
    }


@router.post("/field-members/{field_member_id}/availability")
def set_availability(
    field_member_id: int,
    is_available: bool,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    member = db.get(FieldMember, field_member_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Field member not found")
    member.is_available = is_available
    db.commit()
    return {"message": "Availability updated", "is_available": member.is_available}


# ======================================================================
# 4. Users
# ======================================================================
@router.get("/users", response_model=list[AdminUserResponse])
def list_users(
    role: str | None = None,
    search: str | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    query = db.query(User)
    if role:
        try:
            query = query.filter(User.role == UserRole(role))
        except ValueError:
            raise HTTPException(status_code=400, detail="role must be customer, field_member or admin")
    if search:
        term = f"%{search.strip()}%"
        query = query.filter(
            or_(
                User.username.ilike(term),
                User.phone_number.ilike(term),
                User.email.ilike(term),
            )
        )

    out = []
    for user in query.order_by(User.id.desc()).limit(min(limit, 500)).all():
        profile = (
            db.query(CustomerProfile).filter(CustomerProfile.user_id == user.id).first()
        )
        subscription = SubscriptionService.current(db, user.id)
        out.append(
            AdminUserResponse(
                id=user.id,
                username=user.username,
                full_name=profile.full_name if profile else None,
                phone_number=user.phone_number,
                email=user.email,
                role=user.role.value,
                is_verified=bool(user.is_verified),
                account_status=user.account_status.value,
                profile_completed=bool(profile and profile.profile_completed),
                active_subscription=bool(
                    subscription and subscription.status == SubscriptionStatus.active
                ),
                created_at=user.created_at,
                last_login_at=user.last_login_at,
            )
        )
    return out


@router.post("/users/{user_id}/status")
def update_user_status(
    user_id: int,
    payload: UserStatusUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    if user.id == admin.id:
        raise HTTPException(status_code=400, detail="You cannot change your own account status")

    user.account_status = (
        AccountStatus.suspended if payload.action == "suspend" else AccountStatus.active
    )
    if payload.action == "suspend":
        # A suspended field member must not keep taking jobs.
        member = db.query(FieldMember).filter(FieldMember.user_id == user.id).first()
        if member is not None:
            member.approval_status = FieldMemberApprovalStatus.suspended
            member.is_available = False

    db.commit()
    return {"message": "Account updated", "account_status": user.account_status.value}


@router.post("/users/{user_id}/role")
def update_user_role(
    user_id: int,
    role: str,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    if user.id == admin.id:
        raise HTTPException(status_code=400, detail="You cannot change your own role")
    try:
        new_role = UserRole(role)
    except ValueError:
        raise HTTPException(
            status_code=400, detail="role must be customer, field_member or admin"
        )

    user.role = new_role
    if new_role == UserRole.field_member:
        member = db.query(FieldMember).filter(FieldMember.user_id == user.id).first()
        if member is None:
            db.add(
                FieldMember(
                    user_id=user.id,
                    full_name=(
                        db.query(CustomerProfile)
                        .filter(CustomerProfile.user_id == user.id)
                        .first()
                    ).full_name
                    if db.query(CustomerProfile).filter(CustomerProfile.user_id == user.id).first()
                    else None,
                    approval_status=FieldMemberApprovalStatus.approved,
                    approved_by=admin.id,
                    approved_at=datetime.utcnow(),
                )
            )
    db.commit()
    return {"message": "Role updated", "role": user.role.value}


# ======================================================================
# 5. Branches
# ======================================================================
def _branch_address_for_geocode(
    address: str, city: str | None = None, state: str | None = None, pincode: str | None = None
) -> str:
    parts = [address]
    if city:
        parts.append(city)
    if state:
        parts.append(state)
    if pincode:
        parts.append(pincode)
    return ", ".join(str(p).strip() for p in parts if p and str(p).strip())


def _geocode_branch_address(address: str):
    """Resolve a branch address to coordinates via the active map provider."""
    try:
        service = maps.get_map_service()
        return maps.run_async(service.geocode_address(address))
    except maps.MapProviderNotConfigured as exc:
        logger.warning("Branch geocoding unavailable: provider not configured")
        raise HTTPException(status_code=503, detail=str(exc))
    except maps.MapProviderUnavailable as exc:
        logger.warning("Branch geocoding unavailable: provider unavailable")
        raise HTTPException(
            status_code=503,
            detail="Location service is temporarily unavailable. Please try again later.",
        )
    except (maps.MapProviderError, ValueError) as exc:
        logger.warning("Branch geocoding failed: %s", exc.__class__.__name__)
        message = str(exc).strip() or "Could not resolve this address to coordinates."
        raise HTTPException(status_code=400, detail=message)


def _validate_branch_coordinates(latitude: float, longitude: float) -> tuple[float, float]:
    try:
        maps.validate_coordinates(latitude, longitude, "branch location")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return float(latitude), float(longitude)


@router.get("/branches", response_model=list[BranchResponse])
def list_branches(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    return db.query(Branch).order_by(Branch.name).all()


@router.post("/branches/add", response_model=BranchResponse, status_code=201)
def create_branch(
    payload: BranchCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    latitude, longitude = payload.latitude, payload.longitude
    if latitude is not None and longitude is not None:
        latitude, longitude = _validate_branch_coordinates(latitude, longitude)
    elif latitude is None and longitude is None:
        geo = _geocode_branch_address(
            _branch_address_for_geocode(payload.address, payload.city, payload.state, payload.pincode)
        )
        latitude, longitude = geo.latitude, geo.longitude
    else:
        raise HTTPException(
            status_code=400,
            detail="Provide both latitude and longitude, or omit both to geocode the address.",
        )

    branch = Branch(
        name=payload.name,
        address=payload.address,
        latitude=latitude,
        longitude=longitude,
        contact_number=payload.contact_number,
        city=payload.city,
        state=payload.state,
        pincode=payload.pincode,
    )
    db.add(branch)
    db.commit()
    db.refresh(branch)
    logger.info("Branch %s added by admin %s", branch.id, admin.id)
    return branch


@router.put("/branches/{branch_id}", response_model=BranchResponse)
def update_branch(
    branch_id: int,
    payload: BranchUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    branch = db.get(Branch, branch_id)
    if branch is None:
        raise HTTPException(status_code=404, detail="Branch not found")

    updates = payload.model_dump(exclude_unset=True)

    new_address = updates.get("address", branch.address)
    new_city = updates.get("city", branch.city)
    new_state = updates.get("state", branch.state)
    new_pincode = updates.get("pincode", branch.pincode)

    explicit_lat = "latitude" in updates
    explicit_lng = "longitude" in updates
    address_changed = "address" in updates and str(updates["address"]).strip() != str(branch.address or "").strip()

    # Determine coordinates for the updated branch without mutating the persisted
    # record until validation/geocoding succeeds.
    if explicit_lat or explicit_lng:
        if not (explicit_lat and explicit_lng):
            raise HTTPException(
                status_code=400,
                detail="Provide both latitude and longitude when updating coordinates explicitly.",
            )
        latitude, longitude = _validate_branch_coordinates(
            updates["latitude"], updates["longitude"]
        )
    elif address_changed:
        geo = _geocode_branch_address(
            _branch_address_for_geocode(new_address, new_city, new_state, new_pincode)
        )
        latitude, longitude = geo.latitude, geo.longitude
    else:
        latitude, longitude = float(branch.latitude), float(branch.longitude)

    # Apply all requested field updates only after coordinates are resolved.
    for field, value in updates.items():
        setattr(branch, field, value)
    branch.latitude, branch.longitude = latitude, longitude

    db.commit()
    db.refresh(branch)
    return branch


@router.delete("/branches/{branch_id}")
def delete_branch(
    branch_id: int, db: Session = Depends(get_db), _: User = Depends(admin_required)
):
    """Deactivate rather than delete - historical requests must stay intact."""
    branch = db.get(Branch, branch_id)
    if branch is None:
        raise HTTPException(status_code=404, detail="Branch not found")

    open_count = (
        db.query(func.count(ServiceRequest.id))
        .filter(
            ServiceRequest.branch_id == branch_id,
            ServiceRequest.status.in_(
                [
                    RequestStatus.requested,
                    RequestStatus.payment_pending,
                    RequestStatus.payment_completed,
                    RequestStatus.waiting_for_assignment,
                    RequestStatus.assigned,
                    RequestStatus.in_progress,
                ]
            ),
        )
        .scalar()
        or 0
    )
    if open_count:
        raise HTTPException(
            status_code=409,
            detail=(
                f"This branch has {open_count} open service request(s). Reassign or close them "
                "before deactivating it."
            ),
        )

    branch.is_active = False
    db.commit()
    return {"message": "Branch deactivated"}


# ======================================================================
# 6. Distance / rate configuration
# ======================================================================
@router.get("/distance-rate", response_model=DistanceRateResponse)
def get_distance_rate(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    config = get_pricing_config(db)
    row = (
        db.query(DistanceRateConfig)
        .order_by(DistanceRateConfig.id.desc())
        .first()
    )
    return DistanceRateResponse(
        threshold_km=config.threshold_km,
        rate_per_km=config.charge_per_km,
        tax_percent=config.tax_percent,
        round_trip_factor=config.round_trip_factor,
        effective_at=row.effective_at if row else None,
        updated_by=row.updated_by if row else None,
        config_id=config.config_id,
        is_default=config.is_default,
    )


@router.put("/distance-rate", response_model=DistanceRateResponse)
def update_distance_rate(
    payload: DistanceRateUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(admin_required),
):
    """Publish a new pricing configuration.

    A new immutable row is created rather than editing the old one, so historical
    requests keep the values that were in force when they were raised.
    """
    current = get_pricing_config(db)
    row = DistanceRateConfig(
        threshold_km=payload.threshold_km,
        rate_per_km=payload.rate_per_km,
        tax_percent=payload.tax_percent,
        round_trip_factor=payload.round_trip_factor,
        effective_at=datetime.utcnow(),
        updated_by=admin.id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    logger.info(
        "Distance pricing updated by admin %s: threshold=%s rate=%s",
        admin.id,
        payload.threshold_km,
        payload.rate_per_km,
    )
    NotificationService.create(
        db,
        user_id=admin.id,
        title="Pricing configuration updated",
        message=payload.describe_change(current.threshold_km, current.charge_per_km),
        category=NotificationCategory.admin,
    )
    db.commit()
    return DistanceRateResponse(
        threshold_km=float(row.threshold_km),
        rate_per_km=float(row.rate_per_km),
        tax_percent=float(row.tax_percent),
        round_trip_factor=float(row.round_trip_factor),
        effective_at=row.effective_at,
        updated_by=row.updated_by,
        config_id=row.id,
        is_default=False,
    )


# ======================================================================
# 7. Catalogue
# ======================================================================
@router.get("/service-types", response_model=list[ServiceTypeResponse])
def list_service_types(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    return db.query(ServiceType).order_by(ServiceType.sort_order, ServiceType.id).all()


@router.post("/service-types", response_model=ServiceTypeResponse, status_code=201)
def create_service_type(
    payload: ServiceTypeCreate,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    if db.query(ServiceType).filter(ServiceType.code == payload.code).first():
        raise HTTPException(status_code=409, detail="That service code already exists")
    row = ServiceType(**payload.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.post("/service-types/{service_type_id}/toggle")
def toggle_service_type(
    service_type_id: int, db: Session = Depends(get_db), _: User = Depends(admin_required)
):
    row = db.get(ServiceType, service_type_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Service type not found")
    row.is_active = not row.is_active
    db.commit()
    return {"message": "Updated", "is_active": row.is_active}


@router.get("/plans", response_model=list[dict])
def list_plans(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    return (
        db.query(SubscriptionPlan).order_by(SubscriptionPlan.sort_order, SubscriptionPlan.price).all()
    )


@router.post("/plans", status_code=201)
def create_plan(
    payload: SubscriptionPlanCreate,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    values = payload.model_dump()
    if values["code"] is None:
        values["code"] = "".join(
            character.lower() if character.isalnum() else "_"
            for character in values["plan_name"]
        ).strip("_")
    if db.query(SubscriptionPlan).filter(SubscriptionPlan.code == values["code"]).first():
        raise HTTPException(status_code=409, detail="A plan with that code already exists")
    plan = SubscriptionPlan(**values)
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return {"id": plan.id, "plan_name": plan.plan_name, "price": float(plan.price)}


@router.patch("/plans/{plan_id}")
def update_plan(
    plan_id: int,
    payload: SubscriptionPlanUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    plan = db.get(SubscriptionPlan, plan_id)
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    if (
        db.query(UserSubscription.id)
        .filter(UserSubscription.plan_id == plan_id)
        .first()
        is not None
    ):
        raise HTTPException(
            status_code=409,
            detail=(
                "This plan is referenced by subscription history and cannot be edited. "
                "Create a replacement plan instead."
            ),
        )
    values = payload.model_dump(exclude_unset=True, exclude_none=True)
    code = values.get("code")
    if code and code != plan.code:
        duplicate = (
            db.query(SubscriptionPlan)
            .filter(SubscriptionPlan.code == code, SubscriptionPlan.id != plan.id)
            .first()
        )
        if duplicate:
            raise HTTPException(status_code=409, detail="A plan with that code already exists")
    for key, value in values.items():
        setattr(plan, key, value)
    db.commit()
    db.refresh(plan)
    return plan


@router.post("/plans/{plan_id}/deactivate")
def deactivate_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    plan = db.get(SubscriptionPlan, plan_id)
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    plan.is_active = False
    db.commit()
    return {"id": plan.id, "is_active": plan.is_active}


@router.post("/plans/{plan_id}/activate")
def activate_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(admin_required),
):
    plan = db.get(SubscriptionPlan, plan_id)
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    plan.is_active = True
    db.commit()
    return {"id": plan.id, "is_active": plan.is_active}


@router.get("/policies")
def list_all_policies(
    limit: int = 200, db: Session = Depends(get_db), _: User = Depends(admin_required)
):
    rows = (
        db.query(Policy)
        .order_by(desc(Policy.id))
        .limit(min(limit, 1000))
        .all()
    )
    return [
        {
            "id": p.id,
            "user_id": p.user_id,
            "policy_number": p.policy_number,
            "provider_name": p.provider_name,
            "policy_type": p.policy_type,
            "is_active": p.is_active,
            "expiry_date": p.expiry_date,
        }
        for p in rows
    ]


# ======================================================================
# 8. Maintenance
# ======================================================================
@router.post("/maintenance/run", response_model=MaintenanceTaskResponse)
def run_maintenance(db: Session = Depends(get_db), _: User = Depends(admin_required)):
    """Idempotent housekeeping: expire stale payments, lapsed subscriptions, OTPs."""
    return MaintenanceTaskResponse(
        expired_payments=PaymentService.expire_pending_transactions(db),
        expired_subscriptions=SubscriptionService.expire_lapsed(db),
        purged_otps=OTPService.purge_expired(db),
    )
