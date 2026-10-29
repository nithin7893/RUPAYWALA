"""Service request lifecycle: the only place a request status may change."""

import logging
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.request_assignment import AssignmentStatus, RequestAssignment
from app.models.service_request import RequestStatus, ServiceRequest

logger = logging.getLogger(__name__)

#: Allowed transitions. Anything not listed here is rejected with a 409.
REQUEST_TRANSITIONS: dict[RequestStatus, set[RequestStatus]] = {
    RequestStatus.requested: {
        RequestStatus.payment_pending,
        RequestStatus.payment_completed,
        RequestStatus.waiting_for_assignment,
        RequestStatus.cancelled,
    },
    RequestStatus.payment_pending: {
        RequestStatus.payment_completed,
        RequestStatus.cancelled,
    },
    RequestStatus.payment_completed: {
        RequestStatus.waiting_for_assignment,
        RequestStatus.assigned,
        RequestStatus.cancelled,
    },
    RequestStatus.waiting_for_assignment: {
        RequestStatus.assigned,
        RequestStatus.cancelled,
    },
    RequestStatus.assigned: {
        # `completed` is deliberately NOT reachable from here: a visit credit is
        # consumed on completion, so the job must be started first.
        RequestStatus.in_progress,
        RequestStatus.cancelled,
        RequestStatus.waiting_for_assignment,  # reassignment
    },
    RequestStatus.in_progress: {
        RequestStatus.completed,
        RequestStatus.cancelled,
    },
    RequestStatus.completed: set(),
    RequestStatus.cancelled: set(),
}

#: Friendly labels used in notifications and the mobile UI.
STATUS_LABELS: dict[RequestStatus, str] = {
    RequestStatus.requested: "Submitted",
    RequestStatus.payment_pending: "Payment Pending",
    RequestStatus.payment_completed: "Payment Complete",
    RequestStatus.waiting_for_assignment: "Waiting for Assignment",
    RequestStatus.assigned: "Assigned",
    RequestStatus.in_progress: "In Progress",
    RequestStatus.completed: "Completed",
    RequestStatus.cancelled: "Cancelled",
}


class RequestStatusService:
    @staticmethod
    def can_transition(current: RequestStatus, target: RequestStatus) -> bool:
        return target in REQUEST_TRANSITIONS.get(current, set())

    @staticmethod
    def ensure_transition(request: ServiceRequest, target: RequestStatus) -> None:
        current = request.status
        if current == target:
            return
        if not RequestStatusService.can_transition(current, target):
            raise HTTPException(
                status_code=409,
                detail=(
                    f"A request that is '{STATUS_LABELS.get(current, current.value)}' "
                    f"cannot be moved to '{STATUS_LABELS.get(target, target.value)}'"
                ),
            )
        request.status = target

    # ------------------------------------------------------------------
    @staticmethod
    def mark_assigned(db: Session, request: ServiceRequest) -> None:
        RequestStatusService.ensure_transition(request, RequestStatus.assigned)
        request.assigned_at = datetime.utcnow()
        db.flush()

    @staticmethod
    def mark_in_progress(request: ServiceRequest) -> None:
        RequestStatusService.ensure_transition(request, RequestStatus.in_progress)
        request.started_at = datetime.utcnow()

    @staticmethod
    def mark_completed(request: ServiceRequest) -> None:
        RequestStatusService.ensure_transition(request, RequestStatus.completed)
        request.completed_at = datetime.utcnow()

    @staticmethod
    def cancel(
        db: Session,
        request: ServiceRequest,
        actor_user_id: int,
        reason: str | None = None,
    ) -> None:
        RequestStatusService.ensure_transition(request, RequestStatus.cancelled)
        request.cancelled_at = datetime.utcnow()
        request.cancellation_reason = reason
        request.cancelled_by_user_id = actor_user_id

        # Release any active assignment so the queue stays accurate.
        active = (
            db.query(RequestAssignment)
            .filter(
                RequestAssignment.request_id == request.id,
                RequestAssignment.status == AssignmentStatus.active,
            )
            .with_for_update()
            .all()
        )
        for assignment in active:
            assignment.status = AssignmentStatus.cancelled
            assignment.unassigned_at = datetime.utcnow()
        db.flush()

    @staticmethod
    def label(status: RequestStatus | None) -> str:
        if status is None:
            return "Unknown"
        return STATUS_LABELS.get(status, status.value)
