"""
Migration script to add new columns to existing tables.
Run: python migrate_add_columns.py
"""
from sqlalchemy import create_engine, text

DATABASE_URL = "postgresql+psycopg2://postgres:Nithin024%40@localhost:5432/rupaywala_ori"

engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    # Add user_id to customer_profiles if not exists
    conn.execute(text("""
        ALTER TABLE customer_profiles
        ADD COLUMN IF NOT EXISTS user_id INTEGER REFERENCES users(id) ON DELETE CASCADE
    """))
    conn.commit()
    print("OK: customer_profiles.user_id column ready")

    # Add profile_completed to customer_profiles if not exists
    conn.execute(text("""
        ALTER TABLE customer_profiles
        ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE
    """))
    conn.commit()
    print("OK: customer_profiles.profile_completed column ready")

    # Add number_of_policies and number_of_persons to user_subscriptions
    conn.execute(text("""
        ALTER TABLE user_subscriptions
        ADD COLUMN IF NOT EXISTS number_of_policies INTEGER DEFAULT 0,
        ADD COLUMN IF NOT EXISTS number_of_persons INTEGER DEFAULT 0
    """))
    conn.commit()
    print("OK: user_subscriptions new columns ready")

    print("\nAll migrations completed successfully!")
