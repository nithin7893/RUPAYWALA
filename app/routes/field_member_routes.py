"""
Field member endpoints.

The previous version of this file trusted a ``request_id`` from the body, so any
field member could complete any customer's job. Every route here now requires an
ACTIVE assignment for the signed-in member (``AssignmentService
.require_active_assignment``), so the object-level check can never be skipped.
"""

import logging
from datetime import date, datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import desc, func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.customer_profile import CustomerProfile
from app.models.field_member import FieldMember
from app.models.notification import NotificationCategory
from app.models.policy import Policy
from app.models.request_assignment import AssignmentStatus, RequestAssignment
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.user import User
from app.schemas.field_member_schema import (
    FieldMemberJobResponse,
    FieldMemberStatsResponse,
    UpdateStatusRequest,
)
from app.schemas.service_request_schema import ServiceRequestResponse
from app.services.assignment_service import AssignmentService
from app.services.notification_service import NotificationService
from app.services.request_status_service import RequestStatusService
from app.services.visit_service import VisitService
from app.utils.dependencies import get_approved_field_member
from app.utils.upload_service import save_upload

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/field-member", tags=["Field Member"])


# ======================================================================
# helpers
# ======================================================================
def _job_response(db: Session, request: ServiceRequest, assignment: RequestAssignment) -> FieldMemberJobResponse:
    policy = db.get(Policy, request.policy_id) if request.policy_id else None
    profile = (
        db.query(CustomerProfile).filter(CustomerProfile.user_id == request.user_id).first()
    )
    from app.models.branch import Branch

    branch = db.get(Branch, request.branch_id) if request.branch_id else None

    return FieldMemberJobResponse(
        assignment_id=assignment.id,
        request_id=request.id,
        reference=f"RUP-{date.today().year}-{request.id:06d}",
        status=request.status.value,
        status_label=RequestStatusService.label(request.status),
        request_type=request.request_type,
        description=request.description,
        customer_name=profile.full_name if profile else None,
        customer_phone=profile.phone_number if profile else None,
        customer_address=request.customer_address,
        customer_latitude=(
            float(request.customer_latitude) if request.customer_latitude else None
        ),
        customer_longitude=(
            float(request.customer_longitude) if request.customer_longitude else None
        ),
        policy_label=(
            f"{policy.provider_name} - {policy.policy_number}" if policy else None
        ),
        branch_name=branch.name if branch else None,
        branch_address=branch.address if branch else None,
        distance_km=float(request.distance_km) if request.distance_km else None,
        completion_notes=request.completion_notes,
        proof_image_url=request.proof_image_url,
        assigned_at=assignment.assigned_at,
        started_at=request.started_at,
        completed_at=request.completed_at,
        created_at=request.created_at,
    )


def _my_jobs_query(db: Session, member: FieldMember):
    return (
        db.query(ServiceRequest, RequestAssignment)
        .join(RequestAssignment, RequestAssignment.request_id == ServiceRequest.id)
        .filter(
            RequestAssignment.field_member_id == member.id,
            RequestAssignment.status == AssignmentStatus.active,
        )
        .order_by(desc(ServiceRequest.created_at))
    )


# ======================================================================
# 1. Jobs
# ======================================================================
@router.get("/my-assignments", response_model=list[FieldMemberJobResponse])
def my_assignments(
    status_filter: str | None = None,
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    _user, member = auth
    query = _my_jobs_query(db, member)
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(",") if s.strip()}
        try:
            query = query.filter(ServiceRequest.status.in_([RequestStatus(s) for s in wanted]))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=f"Unknown status: {exc}")
    return [_job_response(db, request, assignment) for request, assignment in query.all()]


@router.get("/my-jobs", response_model=list[FieldMemberJobResponse])
def my_jobs(
    status_filter: str | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    """Alias kept for clients that speak "jobs" rather than "assignments"."""
    _user, member = auth
    query = _my_jobs_query(db, member)
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(",") if s.strip()}
        query = query.filter(ServiceRequest.status.in_([RequestStatus(s) for s in wanted]))
    rows = query.limit(min(limit, 200)).all()
    return [_job_response(db, request, assignment) for request, assignment in rows]


@router.get("/my-stats", response_model=FieldMemberStatsResponse)
def my_stats(db: Session = Depends(get_db), auth=Depends(get_approved_field_member)):
    _user, member = auth
    today = datetime.combine(date.today(), datetime.min.time())

    def count(*filters) -> int:
        query = db.query(func.count(ServiceRequest.id)).join(
            RequestAssignment, RequestAssignment.request_id == ServiceRequest.id
        )
        query = query.filter(RequestAssignment.field_member_id == member.id)
        for f in filters:
            query = query.filter(f)
        return int(query.scalar() or 0)

    return FieldMemberStatsResponse(
        assigned=count(ServiceRequest.status == RequestStatus.assigned),
        in_progress=count(ServiceRequest.status == RequestStatus.in_progress),
        completed=count(ServiceRequest.status == RequestStatus.completed),
        completed_today=count(
            ServiceRequest.status == RequestStatus.completed,
            ServiceRequest.completed_at >= today,
        ),
    )


@router.get("/my-profile")
def my_profile(db: Session = Depends(get_db), auth=Depends(get_approved_field_member)):
    user, member = auth
    profile = (
        db.query(CustomerProfile).filter(CustomerProfile.user_id == user.id).first()
    )
    return {
        "field_member_id": member.id,
        "employee_code": member.employee_code,
        "full_name": member.full_name or (profile.full_name if profile else None),
        "region": member.region,
        "phone_number": user.phone_number,
        "username": user.username,
        "approval_status": member.approval_status.value,
        "is_available": member.is_available,
        "stats": {
            "assigned": _count_for(db, member.id, RequestStatus.assigned),
            "in_progress": _count_for(db, member.id, RequestStatus.in_progress),
            "completed": _count_for(db, member.id, RequestStatus.completed),
        },
    }


def _count_for(db: Session, member_id: int, status: RequestStatus) -> int:
    return int(
        db.query(func.count(ServiceRequest.id))
        .join(RequestAssignment, RequestAssignment.request_id == ServiceRequest.id)
        .filter(
            RequestAssignment.field_member_id == member_id,
            ServiceRequest.status == status,
        )
        .scalar()
        or 0
    )


@router.get("/request/{request_id}", response_model=FieldMemberJobResponse)
def job_detail(
    request_id: int,
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    _user, member = auth
    assignment = AssignmentService.require_active_assignment(
        db, request_id=request_id, field_member_id=member.id
    )
    request = db.get(ServiceRequest, request_id)
    if request is None:
        raise HTTPException(status_code=404, detail="Service request not found")
    return _job_response(db, request, assignment)


# ======================================================================
# 2. Status transitions
# ======================================================================
@router.post("/start-request", response_model=ServiceRequestResponse)
def start_request(
    request_id: int,
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    _user, member = auth
    AssignmentService.require_active_assignment(
        db, request_id=request_id, field_member_id=member.id
    )
    request = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.id == request_id)
        .with_for_update()
        .first()
    )
    if request is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    RequestStatusService.mark_in_progress(request)

    NotificationService.create(
        db,
        user_id=request.user_id,
        title="Service in progress",
        message="Your field executive has started the service.",
        category=NotificationCategory.service_request,
        reference_type="service_request",
        reference_id=request.id,
    )
    db.commit()
    db.refresh(request)

    from app.routes.service_routes import _build_response

    return _build_response(db, request)


@router.post("/update-status", response_model=ServiceRequestResponse)
def update_status(
    payload: UpdateStatusRequest,
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    """Start, complete or cancel a job the member is actually assigned to.

    Completing a job is the only place a visit is consumed.
    """
    user, member = auth
    AssignmentService.require_active_assignment(
        db, request_id=payload.request_id, field_member_id=member.id
    )

    request = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.id == payload.request_id)
        .with_for_update()
        .first()
    )
    if request is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    if payload.status == "in_progress":
        RequestStatusService.mark_in_progress(request)

    elif payload.status == "completed":
        notes = (payload.completion_notes or "").strip()
        if len(notes) < 5:
            raise HTTPException(
                status_code=400, detail="Please describe the work you completed (5 characters or more)"
            )

        RequestStatusService.mark_completed(request)
        request.completion_notes = notes

        # Exactly one visit is consumed, transactionally, and only now.
        VisitService.consume_for_request(db, request)

        NotificationService.create(
            db,
            user_id=request.user_id,
            title="Service completed",
            message=(
                "Your service request is complete. 1 visit has been used from your plan."
            ),
            category=NotificationCategory.service_request,
            reference_type="service_request",
            reference_id=request.id,
        )
        logger.info(
            "Field member %s completed request %s (visit consumed=%s)",
            member.id,
            request.id,
            request.visit_consumed,
        )

    elif payload.status == "cancelled":
        if not payload.note:
            raise HTTPException(status_code=400, detail="Please give a reason for cancelling")
        RequestStatusService.cancel(
            db, request, actor_user_id=user.id, reason=payload.note
        )
        NotificationService.create(
            db,
            user_id=request.user_id,
            title="Service request cancelled",
            message=payload.note,
            category=NotificationCategory.service_request,
            reference_type="service_request",
            reference_id=request.id,
        )
    else:
        raise HTTPException(status_code=400, detail="Unsupported status")

    db.commit()
    db.refresh(request)

    from app.routes.service_routes import _build_response

    return _build_response(db, request)


@router.post("/complete-request", response_model=ServiceRequestResponse)
def complete_request(
    request_id: int,
    completion_notes: str = Form(...),
    proof: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    """Completion with an optional proof photo.

    The upload is validated (extension, size and magic bytes) and stored under a
    random name, so a client cannot write outside the upload directory.
    """
    user, member = auth
    AssignmentService.require_active_assignment(
        db, request_id=request_id, field_member_id=member.id
    )

    request = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.id == request_id)
        .with_for_update()
        .first()
    )
    if request is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    if len((completion_notes or "").strip()) < 5:
        raise HTTPException(
            status_code=400, detail="Please describe the work you completed (5 characters or more)"
        )

    if proof is not None and proof.filename:
        request.proof_image_url = save_upload(proof, subdir=f"proof/user_{request.user_id}")

    RequestStatusService.mark_completed(request)
    request.completion_notes = completion_notes.strip()
    VisitService.consume_for_request(db, request)

    NotificationService.create(
        db,
        user_id=request.user_id,
        title="Service completed",
        message="Your service request is complete. 1 visit has been used from your plan.",
        category=NotificationCategory.service_request,
        reference_type="service_request",
        reference_id=request.id,
    )
    db.commit()
    db.refresh(request)

    from app.routes.service_routes import _build_response

    return _build_response(db, request)


# ======================================================================
# 3. Availability
# ======================================================================
@router.post("/availability")
def set_availability(
    is_available: bool,
    db: Session = Depends(get_db),
    auth=Depends(get_approved_field_member),
):
    _user, member = auth
    member.is_available = is_available
    db.commit()
    return {"message": "Availability updated", "is_available": member.is_available}


@router.get("/me")
def whoami(db: Session = Depends(get_db), auth=Depends(get_approved_field_member)):
    user, member = auth
    return {
        "user_id": user.id,
        "role": user.role.value,
        "field_member_id": member.id,
        "employee_code": member.employee_code,
        "approval_status": member.approval_status.value,
        "is_available": member.is_available,
    }
