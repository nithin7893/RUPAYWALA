"""Customer profile endpoints - always scoped to the signed-in user."""

import logging
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.customer_profile import CustomerProfile
from app.models.policy import Policy
from app.models.user import User
from app.schemas.profile_schema import ProfileCreate, ProfileResponse, ProfileUpdate
from app.services.pricing_service import get_pricing_config
from app.services.subscription_service import SubscriptionService
from app.services.visit_service import VisitService
from app.utils.dependencies import customer_required

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/profile", tags=["Profile"])


def _apply(profile: CustomerProfile, payload) -> CustomerProfile:
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(profile, field, value)
    # Required fields for a "complete" profile.
    profile.profile_completed = bool(profile.full_name and profile.phone_number)
    return profile


@router.post("/create", response_model=ProfileResponse, status_code=status.HTTP_201_CREATED)
def create_profile(
    payload: ProfileCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    existing = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == current_user.id)
        .first()
    )
    if existing is not None:
        raise HTTPException(
            status_code=409, detail="A profile already exists. Use PUT /profile to update it."
        )

    profile = CustomerProfile(user_id=current_user.id)
    _apply(profile, payload)
    if not profile.phone_number:
        profile.phone_number = current_user.phone_number
    if not profile.email:
        profile.email = current_user.email

    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


@router.put("/update", response_model=ProfileResponse)
def update_profile(
    payload: ProfileUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(customer_required),
):
    profile = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == current_user.id)
        .first()
    )
    if profile is None:
        profile = CustomerProfile(user_id=current_user.id, full_name=payload.full_name)
        db.add(profile)

    _apply(profile, payload)
    if not profile.phone_number:
        profile.phone_number = current_user.phone_number

    # Keep the account-level identity in step with the profile.
    if profile.email and not current_user.email:
        current_user.email = profile.email
    if profile.phone_number and current_user.phone_number is None:
        current_user.phone_number = profile.phone_number

    db.commit()
    db.refresh(profile)
    return profile


@router.get("/me", response_model=ProfileResponse)
def my_profile(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    profile = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == current_user.id)
        .first()
    )
    if profile is None:
        # Return a placeholder so the app can render the form straight away.
        return ProfileResponse(
            id=0,
            user_id=current_user.id,
            full_name=current_user.username or "",
            phone_number=current_user.phone_number,
            email=current_user.email,
            profile_completed=False,
        )
    return profile


@router.get("/summary")
def profile_summary(
    db: Session = Depends(get_db), current_user: User = Depends(customer_required)
):
    """Everything the profile screen needs in one call."""
    profile = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == current_user.id)
        .first()
    )
    balance = VisitService.get_balance(db, current_user.id)
    subscription = SubscriptionService.current(db, current_user.id)
    config = get_pricing_config(db)

    policy_count = (
        db.query(func.count(Policy.id))
        .filter(Policy.user_id == current_user.id, Policy.is_active.is_(True))
        .scalar()
        or 0
    )
    active_policies = (
        db.query(func.count(Policy.id))
        .filter(Policy.user_id == current_user.id, Policy.is_active.is_(True))
        .scalar()
        or 0
    )
    expiring_soon = (
        db.query(func.count(Policy.id))
        .filter(
            Policy.user_id == current_user.id,
            Policy.is_active.is_(True),
            Policy.expiry_date.isnot(None),
            Policy.expiry_date >= date.today(),
            Policy.expiry_date <= date.today() + timedelta(days=60),
        )
        .scalar()
        or 0
    )

    plan = subscription.plan if subscription else None
    return {
        "profile": ProfileResponse(
            id=profile.id,
            user_id=current_user.id,
            full_name=profile.full_name if profile else "",
            date_of_birth=profile.date_of_birth if profile else None,
            gender=profile.gender if profile else None,
            email=(profile.email if profile else None) or current_user.email,
            phone_number=(profile.phone_number if profile else None)
            or current_user.phone_number,
            address=profile.address if profile else None,
            city=profile.city if profile else None,
            state=profile.state if profile else None,
            pincode=profile.pincode if profile else None,
            policy_number=profile.policy_number if profile else None,
            insurance_provider=profile.insurance_provider if profile else None,
            policy_type=profile.policy_type if profile else None,
            policy_details=profile.policy_details if profile else None,
            policy_valid_from=profile.policy_valid_from if profile else None,
            policy_valid_till=profile.policy_valid_till if profile else None,
            emergency_contact_name=profile.emergency_contact_name if profile else None,
            emergency_contact_number=profile.emergency_contact_number if profile else None,
            profile_completed=bool(profile and profile.profile_completed),
            created_at=profile.created_at if profile else None,
            updated_at=profile.updated_at if profile else None,
        ),
        "visits": {
            "has_active_subscription": balance["has_active_subscription"],
            "total_visits": balance["total_visits"],
            "used_visits": balance["used_visits"],
            "remaining_visits": balance["remaining_visits"],
            "end_date": balance["end_date"],
            "plan_name": plan.plan_name if plan else None,
        },
        "policies": {
            "active": active_policies,
            "total": policy_count,
            "expiring_within_60_days": expiring_soon,
        },
        "pricing": {
            "threshold_km": config.threshold_km,
            "charge_per_km": config.charge_per_km,
            "tax_percent": config.tax_percent,
            "round_trip_factor": config.round_trip_factor,
        },
    }
