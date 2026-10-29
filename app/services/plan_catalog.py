"""Canonical, idempotent subscription catalog seeding."""

from sqlalchemy import or_, text
from sqlalchemy.orm import Session

from app.models.subscription_plan import SubscriptionPlan


_ADD_ONS = {
    "additional_home_visit": True,
    "distance": True,
    "document_verification": True,
    "online_submission": True,
    "document_storage": True,
    "additional_family_member": True,
}

_PLANS = (
    {
        "code": "silver",
        "plan_name": "Silver",
        "plan_description": "Essential claim documentation, approximately Rs 1 per day.",
        "features": [
            "Claim form filling",
            "Document scanning",
            "Soft-copy document delivery",
            "Digital document organization",
            "Claim-document checklist",
        ],
        "price": 365,
        "visits_included": 0,
        "max_family_members": 1,
        "document_verification": False,
        "online_submission": False,
        "document_storage": False,
        "priority_support": False,
        "sort_order": 10,
    },
    {
        "code": "gold",
        "plan_name": "Gold",
        "plan_description": "Documentation plus document verification.",
        "features": [
            "All Silver benefits",
            "Document verification",
            "Missing-document identification",
            "Basic claim-document review",
            "Digital document organization",
        ],
        "price": 599,
        "visits_included": 0,
        "max_family_members": 1,
        "document_verification": True,
        "online_submission": False,
        "document_storage": False,
        "priority_support": False,
        "sort_order": 20,
    },
    {
        "code": "platinum",
        "plan_name": "Platinum",
        "plan_description": "Complete digital claim assistance.",
        "features": [
            "All Gold benefits",
            "Online document submission",
            "Submission assistance and checklist",
            "Status and support assistance",
        ],
        "price": 799,
        "visits_included": 0,
        "max_family_members": 1,
        "document_verification": True,
        "online_submission": True,
        "document_storage": False,
        "priority_support": False,
        "sort_order": 30,
    },
    {
        "code": "diamond",
        "plan_name": "Diamond",
        "plan_description": "Insurance assistance at the customer's doorstep.",
        "features": [
            "All Platinum benefits",
            "Document pickup",
            "Basic verification",
            "Up to 3 home visits within 10 km per subscription year",
        ],
        "price": 999,
        "visits_included": 3,
        "included_visit_distance_km": 10,
        "max_family_members": 1,
        "document_verification": True,
        "online_submission": True,
        "document_storage": False,
        "priority_support": False,
        "sort_order": 40,
    },
    {
        "code": "family",
        "plan_name": "Family",
        "plan_description": "One shared membership for up to five family members.",
        "features": [
            "Claim form assistance",
            "Document scanning and digital copies",
            "Document verification",
            "Online submission",
            "5 shared home visits per subscription year",
            "Document pickup and basic verification",
        ],
        "price": 1299,
        "visits_included": 5,
        "max_family_members": 5,
        "max_adult_members": 2,
        "max_child_members": 3,
        "document_verification": True,
        "online_submission": True,
        "document_storage": False,
        "priority_support": False,
        "sort_order": 50,
    },
    {
        "code": "elite",
        "plan_name": "Elite",
        "plan_description": "Individual doorstep assistance with one-year document storage.",
        "features": [
            "All Diamond benefits",
            "One-year digital document storage entitlement",
            "Claim-document history",
            "Priority support",
            "Digital document organization",
        ],
        "price": 1499,
        "visits_included": 3,
        "included_visit_distance_km": 10,
        "max_family_members": 1,
        "document_verification": True,
        "online_submission": True,
        "document_storage": True,
        "storage_duration_days": 365,
        "priority_support": True,
        "sort_order": 60,
    },
    {
        "code": "premium_family",
        "plan_name": "Premium Family",
        "plan_description": "Extended family assistance, with limits configurable by an administrator.",
        "features": [
            "All Family benefits",
            "5 shared base home visits per subscription year",
            "One-year digital document storage entitlement",
            "Priority support",
            "Claim submission assistance",
            "Additional visits and extended-family limit are not yet configured",
        ],
        "price": 1999,
        "visits_included": 5,
        "additional_visits": None,
        "max_family_members": None,
        "max_adult_members": None,
        "max_child_members": None,
        "document_verification": True,
        "online_submission": True,
        "document_storage": True,
        "storage_duration_days": 365,
        "priority_support": True,
        "sort_order": 70,
    },
)


def seed_subscription_plans(db: Session) -> None:
    """Create/update only canonical rows and archive plans outside the catalog."""
    if db.get_bind().dialect.name == "postgresql":
        db.execute(
            text(
                """
                SELECT setval(
                    pg_get_serial_sequence('subscription_plans', 'id'),
                    COALESCE(MAX(id), 1),
                    MAX(id) IS NOT NULL
                )
                FROM subscription_plans
                """
            )
        )

    catalog_codes = {plan["code"] for plan in _PLANS}
    for values in _PLANS:
        plan = (
            db.query(SubscriptionPlan)
            .filter(SubscriptionPlan.code == values["code"])
            .first()
        )
        data = {
            **values,
            "validity_days": 365,
            "addon_eligibility": _ADD_ONS,
        }
        if plan is None:
            plan = SubscriptionPlan(**data, is_active=True)
            db.add(plan)
        else:
            for key, value in data.items():
                if values["code"] == "premium_family" and key in {
                    "additional_visits",
                    "max_family_members",
                    "max_adult_members",
                    "max_child_members",
                }:
                    continue
                setattr(plan, key, value)

        if values["code"] == "premium_family":
            configured = (
                plan.additional_visits is not None
                and plan.max_family_members is not None
            )
            plan.features = [
                feature
                for feature in values["features"]
                if "not yet configured" not in feature
            ]
            if configured:
                plan.features.append(
                    "Additional home visits and extended-family limit are configured"
                )
            else:
                plan.features.append(
                    "Additional visits and extended-family limit are awaiting admin configuration"
                )

    (
        db.query(SubscriptionPlan)
        .filter(
            SubscriptionPlan.is_active.is_(True),
            or_(
                SubscriptionPlan.code.is_(None),
                SubscriptionPlan.code.notin_(catalog_codes),
            ),
        )
        .update({SubscriptionPlan.is_active: False}, synchronize_session=False)
    )
    db.commit()
