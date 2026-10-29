"""
Migration script to add duration and completion columns to service_requests.
Run: python migrate_add_duration_columns.py
"""
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg2://postgres:Nithin024%40@localhost:5432/rupaywala_ori")
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    # Add duration_minutes column
    conn.execute(text("""
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS duration_minutes NUMERIC(10, 1)
    """))
    conn.commit()
    print("OK: service_requests.duration_minutes column ready")

    # Add completion_notes column
    conn.execute(text("""
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS completion_notes TEXT
    """))
    conn.commit()
    print("OK: service_requests.completion_notes column ready")

    # Add proof_image_url column
    conn.execute(text("""
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS proof_image_url VARCHAR
    """))
    conn.commit()
    print("OK: service_requests.proof_image_url column ready")

    print("\nAll migrations completed successfully!")
