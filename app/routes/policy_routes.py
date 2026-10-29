"""Policy endpoints - a customer may only ever manage their own policies."""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import desc
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.notification import NotificationCategory
from app.models.policy import Policy
from app.models.policy_member import PolicyMember
from app.models.user import User
from app.schemas.policy_schema import PolicyCreate, PolicyResponse
from app.services.notification_service import NotificationService
from app.utils.dependencies import customer_required

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/policies", tags=["Policies"])


@router.post("/add", status_code=status.HTTP_201_CREATED)
def add_policy(
    payload: PolicyCreate,
    db: Session = Depends(get_db),
    user: User = Depends(customer_required),
):
    existing = (
        db.query(Policy)
        .filter(
            Policy.user_id == user.id,
            Policy.policy_number == payload.policy_number,
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(
            status_code=409, detail="You have already added this policy number"
        )

    new_policy = Policy(
        user_id=user.id,
        policy_type=payload.policy_type,
        policy_category=payload.policy_category,
        provider_name=payload.provider_name,
        policy_number=payload.policy_number,
        coverage_amount=payload.coverage_amount,
        start_date=payload.start_date,
        expiry_date=payload.expiry_date,
        number_of_members=payload.number_of_members
        or (len(payload.members) if payload.members else None),
    )
    db.add(new_policy)
    db.flush()

    if payload.members:
        for member in payload.members:
            db.add(
                PolicyMember(
                    policy_id=new_policy.id,
                    member_name=member.member_name,
                    age=member.age,
                    relationship=member.relationship,
                    phone_number=member.phone_number,
                )
            )

    NotificationService.create(
        db=db,
        user_id=user.id,
        title="Policy added",
        message=f"{payload.policy_type} policy ({payload.provider_name}) added successfully",
        category=NotificationCategory.policy,
        reference_type="policy",
        reference_id=new_policy.id,
    )
    db.commit()
    db.refresh(new_policy)
    return {"message": "Policy added successfully", "policy_id": new_policy.id}


@router.get("/list", response_model=list[PolicyResponse])
def list_policies(db: Session = Depends(get_db), user: User = Depends(customer_required)):
    policies = (
        db.query(Policy)
        .filter(Policy.user_id == user.id)
        .order_by(desc(Policy.id))
        .all()
    )
    out = []
    for policy in policies:
        response = PolicyResponse.model_validate(policy)
        response.is_valid = policy.is_valid_on()
        out.append(response)
    return out


@router.get("/{policy_id}", response_model=PolicyResponse)
def get_policy(
    policy_id: int, db: Session = Depends(get_db), user: User = Depends(customer_required)
):
    policy = (
        db.query(Policy)
        .filter(Policy.id == policy_id, Policy.user_id == user.id)
        .first()
    )
    if policy is None:
        raise HTTPException(status_code=404, detail="Policy not found")
    response = PolicyResponse.model_validate(policy)
    response.is_valid = policy.is_valid_on()
    return response


@router.delete("/delete/{policy_id}")
def delete_policy(
    policy_id: int, db: Session = Depends(get_db), user: User = Depends(customer_required)
):
    policy = (
        db.query(Policy)
        .filter(Policy.id == policy_id, Policy.user_id == user.id)
        .first()
    )
    if policy is None:
        raise HTTPException(status_code=404, detail="Policy not found")

    from app.models.service_request import RequestStatus, ServiceRequest
    from sqlalchemy import func

    in_flight = (
        db.query(func.count(ServiceRequest.id))
        .filter(
            ServiceRequest.policy_id == policy_id,
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
    if in_flight:
        raise HTTPException(
            status_code=409,
            detail=(
                "This policy has an open service request. Please wait until it is completed "
                "or cancelled before removing it."
            ),
        )

    NotificationService.create(
        db=db,
        user_id=user.id,
        title="Policy removed",
        message=f"{policy.policy_type} policy ({policy.provider_name}) has been removed",
        category=NotificationCategory.policy,
        reference_type="policy",
        reference_id=policy.id,
    )
    db.delete(policy)
    db.commit()
    return {"message": "Policy deleted successfully"}
