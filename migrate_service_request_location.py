"""
Migration script to add location and distance columns to service_requests,
and create branches table.
Run: python migrate_service_request_location.py
"""
from sqlalchemy import create_engine, text

DATABASE_URL = "postgresql+psycopg2://postgres:Nithin024%40@localhost:5432/rupaywala_ori"
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    # Create branches table
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS branches (
            id SERIAL PRIMARY KEY,
            name VARCHAR(200) NOT NULL,
            address TEXT NOT NULL,
            latitude NUMERIC(10, 7) NOT NULL,
            longitude NUMERIC(10, 7) NOT NULL,
            contact_number VARCHAR(20),
            created_at TIMESTAMP DEFAULT NOW()
        )
    """))
    conn.commit()
    print("OK: branches table ready")

    # Add customer location columns
    conn.execute(text("""
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS customer_latitude NUMERIC(10, 7),
        ADD COLUMN IF NOT EXISTS customer_longitude NUMERIC(10, 7),
        ADD COLUMN IF NOT EXISTS customer_address TEXT
    """))
    conn.commit()
    print("OK: service_requests location columns ready")

    # Add branch reference
    conn.execute(text("""
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS branch_id INTEGER REFERENCES branches(id)
    """))
    conn.commit()
    print("OK: service_requests.branch_id column ready")

    # Add distance and charge columns
    conn.execute(text("""
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS distance_km NUMERIC(10, 2),
        ADD COLUMN IF NOT EXISTS extra_charge NUMERIC(10, 2),
        ADD COLUMN IF NOT EXISTS distance_rate NUMERIC(10, 2)
    """))
    conn.commit()
    print("OK: service_requests distance/charge columns ready")

    print("\nAll migrations completed successfully!")
