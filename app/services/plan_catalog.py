"""Canonical, idempotent subscription catalog seeding."""

from sqlalchemy import func, or_, text
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


def _ensure_subscription_plans_sequence(db: Session) -> None:
    """Advance subscription_plans.id sequence when behind max(id).

    Uses nextval (USAGE) only - no setval/UPDATE privilege required. Never moves
    the sequence backward. A boundary case where last_value == max(id) may advance
    by one extra value when the sequence was already consistent; this is harmless
    and preserves existing IDs/data.
    """
    bind = db.get_bind()
    if bind is None or bind.dialect.name != "postgresql":
        return

    seq_name = db.execute(
        text("SELECT pg_get_serial_sequence('public.subscription_plans', 'id')")
    ).scalar()
    if not seq_name:
        return

    max_id = db.query(func.max(SubscriptionPlan.id)).scalar()
    if max_id is None:
        return
    max_id = int(max_id)

    row = db.execute(
        text(
            "SELECT last_value "
            "FROM pg_sequences "
            "WHERE schemaname = split_part(:seq, '.', 1) "
            "AND sequencename = split_part(:seq, '.', 2)"
        ),
        {"seq": str(seq_name)},
    ).first()
    last_value = int(row[0]) if row and row[0] is not None else None

    # Already safely ahead.
    if last_value is not None and last_value > max_id:
        return

    # Behind, unknown, or exact boundary: advance until nextval >= max_id.
    while True:
        current = int(
            db.execute(
                text("SELECT nextval(CAST(:seq AS regclass))"),
                {"seq": str(seq_name)},
            ).scalar()
        )
        if current >= max_id:
            return


_SEED_ADVISORY_LOCK_KEY = "rupaywala:subscription_plan_seed"


def seed_subscription_plans(db: Session) -> None:
    """Create/update only canonical rows and archive plans outside the catalog."""
    bind = db.get_bind()
    if bind is not None and bind.dialect.name == "postgresql":
        # Serialize concurrent startup workers. Transaction-scoped lock releases
        # automatically on commit/rollback and cannot leak across pooled connections.
        db.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:lock_key))"),
            {"lock_key": _SEED_ADVISORY_LOCK_KEY},
        )

    _ensure_subscription_plans_sequence(db)

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
