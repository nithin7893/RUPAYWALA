"""Factories for test data.

Kept in one place so tests do not depend on each other or on the contents of
any real database.
"""

import random
from datetime import datetime, timedelta

from app.models.branch import Branch
from app.models.customer_profile import CustomerProfile
from app.models.field_member import FieldMember, FieldMemberApprovalStatus
from app.models.policy import Policy
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.service_type import ServiceType
from app.models.subscription_plan import SubscriptionPlan
from app.models.user import AccountStatus, AuthProvider, User, UserRole
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.utils.security import hash_password

DEFAULT_PASSWORD = "TestPass!234"


def _tail() -> str:
    return str(random.randint(1000000, 9999999))


def utr() -> str:
    """A unique UTR so tests never trip the duplicate-reference guard."""
    return f"UTR{_tail()}"


def make_user(
    db,
    *,
    role: UserRole = UserRole.customer,
    phone: str | None = None,
    username: str | None = None,
    password: str | None = DEFAULT_PASSWORD,
    verified: bool = True,
    status: AccountStatus = AccountStatus.active,
) -> User:
    phone = phone or f"9{_tail()}"
    user = User(
        phone_number=phone,
        username=username or f"user{phone}",
        role=role,
        auth_provider=AuthProvider.phone_otp,
        password_hash=hash_password(password) if password else None,
        is_verified=verified,
        account_status=status,
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def make_admin(db, **kwargs) -> User:
    return make_user(db, role=UserRole.admin, **kwargs)


def make_profile(db, user: User, **overrides) -> CustomerProfile:
    profile = CustomerProfile(
        user_id=user.id,
        full_name=overrides.pop("full_name", f"Customer {user.id}"),
        email=overrides.pop("email", f"c{user.id}@example.com"),
        phone_number=overrides.pop("phone_number", user.phone_number),
        address=overrides.pop("address", "1 Test Street"),
        city=overrides.pop("city", "Chennai"),
        state=overrides.pop("state", "Tamil Nadu"),
        pincode=overrides.pop("pincode", "600001"),
        profile_completed=overrides.pop("profile_completed", True),
        created_at=datetime.utcnow(),
    )
    for key, value in overrides.items():
        setattr(profile, key, value)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


def make_branch(db, **overrides) -> Branch:
    branch = Branch(
        name=overrides.pop("name", f"Branch {_tail()}"),
        address=overrides.pop("address", "2 Test Road"),
        latitude=overrides.pop("latitude", 13.0827),
        longitude=overrides.pop("longitude", 80.2707),
        contact_number=overrides.pop("contact_number", "04412345678"),
        city=overrides.pop("city", "Chennai"),
        state=overrides.pop("state", "Tamil Nadu"),
        pincode=overrides.pop("pincode", "600002"),
        is_active=overrides.pop("is_active", True),
        created_at=datetime.utcnow(),
    )
    db.add(branch)
    db.commit()
    db.refresh(branch)
    return branch


def make_service_type(db, **overrides) -> ServiceType:
    code = overrides.pop("code", f"st{_tail()[:6]}")
    service_type = ServiceType(
        code=code,
        name=overrides.pop("name", f"Service {code}"),
        description=overrides.pop("description", "Test service"),
        icon=overrides.pop("icon", "support_agent"),
        is_active=overrides.pop("is_active", True),
        sort_order=overrides.pop("sort_order", 0),
        created_at=datetime.utcnow(),
    )
    db.add(service_type)
    db.commit()
    db.refresh(service_type)
    return service_type


def make_field_member(
    db,
    user: User | None = None,
    *,
    approved: bool = True,
    available: bool = True,
    **overrides,
) -> FieldMember:
    user = user or make_user(db, role=UserRole.field_member)
    member = FieldMember(
        user_id=user.id,
        employee_code=overrides.pop("employee_code", f"FM{_tail()[:6]}"),
        full_name=overrides.pop("full_name", f"Field {user.id}"),
        region=overrides.pop("region", "Chennai"),
        approval_status=(
            FieldMemberApprovalStatus.approved
            if approved
            else FieldMemberApprovalStatus.pending
        ),
        is_available=available,
        created_at=datetime.utcnow(),
    )
    db.add(member)
    db.commit()
    db.refresh(member)
    return member


def make_policy(db, user: User, **overrides) -> Policy:
    policy = Policy(
        user_id=user.id,
        policy_type=overrides.pop("policy_type", "Motor"),
        policy_category=overrides.pop("policy_category", "individual"),
        provider_name=overrides.pop("provider_name", "Test Insurance"),
        policy_number=overrides.pop("policy_number", f"POL{_tail()}"),
        coverage_amount=overrides.pop("coverage_amount", 500000.0),
        is_active=overrides.pop("is_active", True),
        number_of_members=overrides.pop("number_of_members", 1),
        created_at=datetime.utcnow(),
    )
    db.add(policy)
    db.commit()
    db.refresh(policy)
    return policy


def make_plan(db, **overrides) -> SubscriptionPlan:
    plan = SubscriptionPlan(
        plan_name=overrides.pop("plan_name", f"Plan {_tail()[:5]}"),
        plan_description=overrides.pop("plan_description", "Test plan"),
        features=overrides.pop("features", []),
        price=overrides.pop("price", 999.0),
        visits_included=overrides.pop("visits_included", 4),
        validity_days=overrides.pop("validity_days", 365),
        max_policies=overrides.pop("max_policies", 5),
        max_family_members=overrides.pop("max_family_members", 10),
        is_active=overrides.pop("is_active", True),
        created_at=datetime.utcnow(),
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan


def make_subscription(
    db,
    user: User,
    plan: SubscriptionPlan,
    *,
    status: SubscriptionStatus = SubscriptionStatus.active,
    total_visits: int | None = None,
    used_visits: int = 0,
) -> UserSubscription:
    sub = UserSubscription(
        user_id=user.id,
        plan_id=plan.id,
        total_visits=plan.visits_included if total_visits is None else total_visits,
        used_visits=used_visits,
        status=status,
        start_date=datetime.utcnow().date(),
        end_date=(datetime.utcnow() + timedelta(days=plan.validity_days)).date(),
        activated_at=datetime.utcnow(),
        created_at=datetime.utcnow(),
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


def make_request(
    db,
    user: User,
    *,
    service_type: ServiceType | None = None,
    branch: Branch | None = None,
    status: RequestStatus = RequestStatus.waiting_for_assignment,
    request_type: str = "claim",
    extra_charge: float = 0.0,
    subscription: UserSubscription | None = None,
) -> ServiceRequest:
    request = ServiceRequest(
        user_id=user.id,
        service_type_id=(service_type or make_service_type(db)).id,
        branch_id=(branch or make_branch(db)).id,
        request_type=request_type,
        status=status,
        charge_paid=extra_charge == 0.0,
        extra_charge=extra_charge,
        tax_amount=0.0,
        total_amount=extra_charge,
        customer_address="1 Test Street",
        customer_latitude=13.0827,
        customer_longitude=80.2707,
        subscription_id=subscription.id if subscription else None,
        created_at=datetime.utcnow(),
    )
    db.add(request)
    db.commit()
    db.refresh(request)
    return request
