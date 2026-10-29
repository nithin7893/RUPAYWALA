"""Field-member allocation.

Concurrency: the service request row is locked with ``SELECT ... FOR UPDATE``
before inspecting or mutating assignments, so two admins assigning (or an admin
and a reassignment) cannot end up with two active assignments for one request.
"""

import logging
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.field_member import FieldMember
from app.models.request_assignment import AssignmentStatus, RequestAssignment
from app.models.service_request import ASSIGNABLE_STATUSES, RequestStatus, ServiceRequest
from app.services.request_status_service import RequestStatusService

logger = logging.getLogger(__name__)


class AssignmentService:
    @staticmethod
    def get_active(db: Session, request_id: int) -> RequestAssignment | None:
        return (
            db.query(RequestAssignment)
            .filter(
                RequestAssignment.request_id == request_id,
                RequestAssignment.status == AssignmentStatus.active,
            )
            .first()
        )

    @staticmethod
    def lock_request(db: Session, request_id: int) -> ServiceRequest:
        request = (
            db.query(ServiceRequest)
            .filter(ServiceRequest.id == request_id)
            .with_for_update()
            .first()
        )
        if request is None:
            raise HTTPException(status_code=404, detail="Service request not found")
        return request

    @staticmethod
    def assign(
        db: Session,
        *,
        request_id: int,
        field_member_id: int,
        assigned_by_user_id: int,
        notes: str | None = None,
        allow_reassign: bool = True,
    ) -> RequestAssignment:
        request = AssignmentService.lock_request(db, request_id)

        if request.requires_payment:
            raise HTTPException(
                status_code=400,
                detail="The extra distance charge for this request is still unpaid",
            )
        if request.status in (RequestStatus.completed, RequestStatus.cancelled):
            raise HTTPException(
                status_code=409,
                detail=f"A {RequestStatusService.label(request.status).lower()} request cannot be assigned",
            )

        member = db.get(FieldMember, field_member_id)
        if member is None:
            raise HTTPException(status_code=404, detail="Field member not found")
        if not member.is_operational():
            raise HTTPException(
                status_code=400,
                detail="That field member is not approved or not currently available",
            )

        current = AssignmentService.get_active(db, request_id)
        if current is not None:
            if current.field_member_id == field_member_id:
                raise HTTPException(
                    status_code=409, detail="This field member is already assigned to the request"
                )
            if not allow_reassign:
                raise HTTPException(status_code=409, detail="Request is already assigned")
            if request.status not in (
                RequestStatus.assigned,
                RequestStatus.waiting_for_assignment,
            ):
                raise HTTPException(
                    status_code=409,
                    detail="Only an assigned request can be reassigned",
                )
            current.status = AssignmentStatus.unassigned
            current.unassigned_at = datetime.utcnow()

        assignment = RequestAssignment(
            request_id=request_id,
            field_member_id=field_member_id,
            assigned_by=assigned_by_user_id,
            status=AssignmentStatus.active,
            notes=notes,
        )
        db.add(assignment)
        db.flush()

        request.assigned_at = datetime.utcnow()
        RequestStatusService.ensure_transition(request, RequestStatus.assigned)
        db.flush()

        logger.info(
            "Request %s assigned to field member %s (assignment %s)",
            request_id,
            field_member_id,
            assignment.id,
        )
        return assignment

    @staticmethod
    def unassign(db: Session, *, request_id: int, actor_user_id: int) -> None:
        request = AssignmentService.lock_request(db, request_id)
        current = AssignmentService.get_active(db, request_id)
        if current is None:
            raise HTTPException(status_code=409, detail="This request has no active assignment")

        current.status = AssignmentStatus.unassigned
        current.unassigned_at = datetime.utcnow()

        if request.status in (RequestStatus.assigned,):
            request.status = RequestStatus.waiting_for_assignment
        db.flush()

    @staticmethod
    def require_active_assignment(
        db: Session, *, request_id: int, field_member_id: int
    ) -> RequestAssignment:
        """Authorisation guard: a field member may only act on their own work."""
        assignment = AssignmentService.get_active(db, request_id)
        if assignment is None:
            raise HTTPException(
                status_code=403, detail="You are not assigned to this service request"
            )
        if assignment.field_member_id != field_member_id:
            raise HTTPException(
                status_code=403, detail="You are not assigned to this service request"
            )
        return assignment
