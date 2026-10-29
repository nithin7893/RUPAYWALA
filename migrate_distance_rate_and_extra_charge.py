"""
Migration: Add distance_rate_config table, charge_paid to service_requests,
payment_type and related_request_id to payments.
"""
import psycopg2
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")


def migrate():
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True
    cur = conn.cursor()

    # 1. Create distance_rate_config table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS distance_rate_config (
            id SERIAL PRIMARY KEY,
            rate_per_km NUMERIC(10, 2) NOT NULL DEFAULT 10.0,
            effective_at TIMESTAMP DEFAULT NOW(),
            updated_by INTEGER REFERENCES users(id)
        );
    """)
    print("Created distance_rate_config table")

    # 2. Seed default rate if table is empty
    cur.execute("SELECT COUNT(*) FROM distance_rate_config")
    if cur.fetchone()[0] == 0:
        cur.execute(
            "INSERT INTO distance_rate_config (rate_per_km) VALUES (10.0)"
        )
        print("Seeded default rate: Rs 10.0/km")

    # 3. Add charge_paid to service_requests
    cur.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'service_requests' AND column_name = 'charge_paid'
            ) THEN
                ALTER TABLE service_requests ADD COLUMN charge_paid BOOLEAN DEFAULT TRUE;
            END IF;
        END $$;
    """)
    print("Ensured charge_paid column on service_requests")

    # 4. Add payment_type and related_request_id to payments
    cur.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'payments' AND column_name = 'payment_type'
            ) THEN
                ALTER TABLE payments ADD COLUMN payment_type VARCHAR(20) DEFAULT 'subscription';
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'payments' AND column_name = 'related_request_id'
            ) THEN
                ALTER TABLE payments ADD COLUMN related_request_id INTEGER REFERENCES service_requests(id);
            END IF;
        END $$;
    """)
    print("Ensured payment_type and related_request_id on payments")

    # 5. Make plan_id nullable (was NOT NULL for subscription-only)
    cur.execute("""
        ALTER TABLE payments ALTER COLUMN plan_id DROP NOT NULL;
    """)
    print("Made payments.plan_id nullable")

    cur.close()
    conn.close()
    print("Migration complete!")


if __name__ == "__main__":
    migrate()
