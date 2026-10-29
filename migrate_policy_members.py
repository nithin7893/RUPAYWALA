"""
Migration script to add policy_category, number_of_members columns to policies table
and create the policy_members table.
Run: python migrate_policy_members.py
"""
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg2://postgres:Nithin024%40@localhost:5432/rupaywala_ori")

engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    # Add policy_category column to policies table
    try:
        conn.execute(text(
            "ALTER TABLE policies ADD COLUMN IF NOT EXISTS policy_category VARCHAR(20) DEFAULT 'individual'"
        ))
        print("Added policy_category column to policies table")
    except Exception as e:
        print(f"policy_category column already exists or error: {e}")

    # Add number_of_members column to policies table
    try:
        conn.execute(text(
            "ALTER TABLE policies ADD COLUMN IF NOT EXISTS number_of_members INTEGER"
        ))
        print("Added number_of_members column to policies table")
    except Exception as e:
        print(f"number_of_members column already exists or error: {e}")

    # Create policy_members table
    try:
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS policy_members (
                id SERIAL PRIMARY KEY,
                policy_id INTEGER REFERENCES policies(id) ON DELETE CASCADE,
                member_name VARCHAR(100),
                age INTEGER,
                relationship VARCHAR(50),
                phone_number VARCHAR(15),
                created_at TIMESTAMP DEFAULT NOW()
            )
        """))
        print("Created policy_members table")
    except Exception as e:
        print(f"Error creating policy_members table: {e}")

    conn.commit()
    print("Migration completed successfully!")
