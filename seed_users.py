"""
Seed script to create dummy users for testing.
Run: python seed_users.py
"""
from app.database import SessionLocal, engine
from app.models.user import User, UserRole, AccountStatus
from app.models.subscription_plan import SubscriptionPlan
from app.database import Base
from app.utils.security import hash_password

# Create tables if they don't exist
Base.metadata.create_all(bind=engine)

db = SessionLocal()

try:
    # --- Dummy Users ---
    users = [
        {
            "phone_number": "9876543210",
            "password": "customer123",
            "role": UserRole.customer,
        },
        {
            "phone_number": "8765432109",
            "password": "fieldmember123",
            "role": UserRole.field_member,
        },
        {
            "phone_number": "7654321098",
            "password": "admin123",
            "role": UserRole.admin,
        },
    ]

    created = []
    for u in users:
        existing = db.query(User).filter(User.phone_number == u["phone_number"]).first()
        if existing:
            print(f"[UPDATE] Updating password for {u['phone_number']} ({u['role'].value})")
            existing.password_hash = hash_password(u["password"])
            db.commit()
            continue
        new_user = User(
            phone_number=u["phone_number"],
            password_hash=hash_password(u["password"]),
            role=u["role"],
            is_verified=True,
            account_status=AccountStatus.active,
        )
        db.add(new_user)
        db.commit()
        created.append(u)

    for u in created:
        print(f"[OK] Created: {u['role'].value} | Phone: {u['phone_number']} | Password: {u['password']}")

    # --- Dummy Subscription Plan (if none exist) ---
    existing_plan = db.query(SubscriptionPlan).first()
    if not existing_plan:
        from app.models.subscription_plan import SubscriptionPlan as SP
        plans = [
            SP(plan_name="Basic Plan", plan_description="Basic service coverage", price=999, max_policies=5, max_family_members=4, validity_days=90),
            SP(plan_name="Premium Plan", plan_description="Premium service coverage with priority", price=1999, max_policies=10, max_family_members=6, validity_days=180),
            SP(plan_name="Ultimate Plan", plan_description="Full coverage with all benefits", price=2999, max_policies=999, max_family_members=10, validity_days=365),
        ]
        for p in plans:
            db.add(p)
        db.commit()
        print("[OK] Created 3 dummy subscription plans")
    else:
        print("[SKIP] Subscription plans already exist")

    print("\n" + "=" * 60)
    print("  DUMMY CREDENTIALS FOR TESTING")
    print("=" * 60)
    print("  Customer:     Phone: 9876543210  | Password: customer123")
    print("  Field Member: Phone: 8765432109  | Password: fieldmember123")
    print("  Admin:        Phone: 7654321098  | Password: admin123")
    print("=" * 60)

finally:
    db.close()
