"""
Seed script to create dummy branches for testing.
Run: python seed_branches.py
"""
from app.database import SessionLocal
from app.models.branch import Branch

db = SessionLocal()

try:
    branches_data = [
        {
            "name": "Rupaywala - City Center",
            "address": "123 MG Road, City Center, Mumbai - 400001",
            "latitude": 19.0760,
            "longitude": 72.8777,
            "contact_number": "022-23456789",
        },
        {
            "name": "Rupaywala - Andheri West",
            "address": "45 SV Road, Andheri West, Mumbai - 400058",
            "latitude": 19.1365,
            "longitude": 72.8315,
            "contact_number": "022-26253456",
        },
        {
            "name": "Rupaywala - Bandra",
            "address": "78 Hill Road, Bandra West, Mumbai - 400050",
            "latitude": 19.0596,
            "longitude": 72.8295,
            "contact_number": "022-26567890",
        },
        {
            "name": "Rupaywala - Navi Mumbai",
            "address": "Plot 56, Sector 15, CBD Belapur, Navi Mumbai - 400614",
            "latitude": 19.0207,
            "longitude": 73.0486,
            "contact_number": "022-27561234",
        },
        {
            "name": "Rupaywala - Thane",
            "address": "90 Ghodbunder Road, Thane West - 400607",
            "latitude": 19.2183,
            "longitude": 72.9781,
            "contact_number": "022-25437890",
        },
    ]

    existing = db.query(Branch).count()
    if existing > 0:
        print(f"[SKIP] {existing} branches already exist. Delete them first if you want to re-seed.")
    else:
        for b in branches_data:
            branch = Branch(**b)
            db.add(branch)
        db.commit()
        print(f"[OK] Inserted {len(branches_data)} dummy branches")

        print("\nBranches:")
        for b in db.query(Branch).all():
            print(f"  {b.id}. {b.name} ({b.latitude}, {b.longitude})")

finally:
    db.close()
