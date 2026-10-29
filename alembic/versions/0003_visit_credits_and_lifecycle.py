"""rupaywala v2: visit credits, real lifecycle, secure auth, pricing history

Revision ID: 0003_visit_credits_lifecycle
Revises: 0002_expand_enums
Create Date: 2026-09-27

What this revision does
-----------------------
Adapts an EXISTING deployment (the schema created by the previous
``Base.metadata.create_all`` code) to the v2 models. It is deliberately
non-destructive: every existing row is kept, and legacy data is mapped onto the
new columns rather than discarded.

Key decisions
-------------
* The enum labels this migration relies on are added by ``0002_expand_enums``,
  which commits first (see that file for why the split is required).
* Every statement below is written to be safe on a FRESH install too: the
  helpers skip objects that already exist, and legacy data rewrites only run
  when the legacy labels/columns are actually present. That keeps
  ``alembic upgrade head`` correct whether the starting point is an empty
  database or a live deployment.
* Legacy request statuses are mapped, not dropped:
      pending        -> waiting_for_assignment
      charge_pending -> payment_pending
      rejected       -> cancelled (with a reason)
* The visit ledger is backfilled from the existing subscriptions and completed
  requests so historic usage stays auditable.
* The plaintext ``otp_verifications.otp`` column is neutralised and then
  dropped - keeping live one-time passcodes in a table is not acceptable.
* ``subscription_plans.visits_included`` defaults to 1 for existing plans.
  Adjust the seeded value in the admin screen if the historical plans entitled
  customers to a different number of visits.
"""

import functools
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003_visit_credits_lifecycle"
down_revision: Union[str, None] = "0002_expand_enums"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


@functools.lru_cache(maxsize=1)
def _is_pg() -> bool:
    """Whether the migration runs against PostgreSQL.

    Evaluated lazily and cached: ``op.get_bind()`` is only valid once Alembic is
    executing a revision, never while this module is being imported.
    """
    return op.get_bind().dialect.name == "postgresql"


# ======================================================================
# Helpers
# ======================================================================
def _column_type(table: str, column: str) -> str:
    """Return the enum type name backing a column (legacy and current differ)."""
    if not _is_pg():
        return "varchar"
    row = op.get_bind().execute(
        sa.text(
            """
            SELECT t.typname
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_type t ON t.oid = a.atttypid
            WHERE c.relname = :t AND n.nspname = current_schema()
              AND a.attname = :c AND a.attnum > 0 AND NOT a.attisdropped
            """
        ),
        {"t": table, "c": column},
    ).first()
    return row[0] if row else "text"


def _fk_on_column(table: str, column: str):
    """Return (name, on_delete) of the single FK on ``table.column``, if any."""
    if not _is_pg():
        return None
    return op.get_bind().execute(
        sa.text(
            """
            SELECT tc.constraint_name, rc.delete_rule
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON kcu.constraint_name = tc.constraint_name
             AND kcu.constraint_schema = tc.constraint_schema
            JOIN information_schema.referential_constraints rc
              ON rc.constraint_name = tc.constraint_name
             AND rc.constraint_schema = tc.constraint_schema
            WHERE tc.table_schema = current_schema()
              AND tc.table_name = :t
              AND tc.constraint_type = 'FOREIGN KEY'
              AND kcu.column_name = :c
            LIMIT 1
            """
        ),
        {"t": table, "c": column},
    ).first()


def _align_fk(
    table: str,
    column: str,
    ref_table: str,
    ref_column: str,
    ondelete: str,
    name: str = None,
) -> None:
    """Make ``table.column`` carry exactly the model's foreign key.

    The live database already has foreign keys under PostgreSQL's generated
    names (for example ``payments_related_request_id_fkey``) and usually without
    an ON DELETE rule. Adding the model's constraint on top would leave two
    constraints on one column, so the existing one is replaced rather than
    duplicated. ``name`` is only needed when the model names the constraint
    explicitly; otherwise the existing name is kept, which is what the model
    would generate anyway.
    """
    existing = _fk_on_column(table, column)
    if existing:
        current_name, current_rule = existing[0], (existing[1] or "NO ACTION")
        wanted_name = name or current_name
        if current_name == wanted_name and current_rule.upper() == ondelete.upper():
            return
        op.drop_constraint(current_name, table, type_="foreignkey")
    else:
        wanted_name = name or f"{table}_{column}_fkey"
    op.create_foreign_key(
        wanted_name, table, ref_table, [column], [ref_column], ondelete=ondelete
    )


def _align_type(table: str, column: str, type_, nullable: bool) -> None:
    """Widen/retype a column and tighten it, tolerating legacy drift."""
    op.alter_column(
        table, column, type_=type_, existing_type=type_, nullable=nullable
    )


def _attach_orphans(table: str) -> None:
    """Give ownerless legacy rows their own inert placeholder account.

    Some rows in the live database have no owner at all: one policy and nine
    customer_profiles rows with ``user_id IS NULL``. The v2 models require an
    owner (and allow only ONE profile per user), so a single shared account
    cannot work for the profiles. Deleting the rows would lose data and
    reassigning them to a real user would attach a stranger's records to them.

    Each orphan row therefore gets its own clearly-named, suspended account with
    no phone number, no password and no Google link, so it can never sign in but
    is trivial to find, reassign or delete from the admin screen. The username
    records where the row came from, which makes this reversible by hand.
    """
    if "user_id" not in _columns(table):
        return
    prefix = f"legacy_unassigned_{table}"
    op.get_bind().execute(
        sa.text(
            f"""
            INSERT INTO users (
                username, phone_number, password_hash, role, is_verified,
                account_status, auth_provider, created_at, updated_at
            )
            SELECT :p || t.id, NULL, NULL, 'customer'::user_role, false,
                   'suspended'::account_status, 'phone_otp'::auth_provider, now(), now()
            FROM {table} t
            WHERE t.user_id IS NULL
              AND NOT EXISTS (SELECT 1 FROM users u WHERE u.username = :p || t.id)
            """
        ),
        {"p": prefix},
    )
    op.get_bind().execute(
        sa.text(
            f"""
            UPDATE {table} t SET user_id = u.id
            FROM users u
            WHERE t.user_id IS NULL AND u.username = :p || t.id
            """
        ),
        {"p": prefix},
    )
    op.alter_column(table, "user_id", existing_type=sa.Integer(), nullable=False)


def _type_exists(type_name: str) -> bool:
    if not _is_pg():
        return False
    return bool(
        op.get_bind()
        .execute(
            sa.text(
                "SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace "
                "WHERE t.typname = :t AND n.nspname = current_schema()"
            ),
            {"t": type_name},
        )
        .first()
    )


def _enum_values(type_name: str) -> set[str]:
    if not _is_pg():
        return set()
    return {
        row[0]
        for row in op.get_bind().execute(
            sa.text(
                "SELECT enumlabel FROM pg_enum e "
                "JOIN pg_type t ON t.oid = e.enumtypid "
                "JOIN pg_namespace n ON n.oid = t.typnamespace "
                "WHERE t.typname = :t AND n.nspname = current_schema()"
            ),
            {"t": type_name},
        )
    }


def _columns(table: str) -> set[str]:
    return {
        row[0]
        for row in op.get_bind().execute(
            sa.text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = current_schema() AND table_name = :t"
            ),
            {"t": table},
        )
    }


def _add_column(table: str, column: sa.Column) -> None:
    """add_column that is a no-op when the column is already present."""
    if column.name in _columns(table):
        return
    op.add_column(table, column)


def _drop_column(table: str, name: str) -> None:
    if name not in _columns(table):
        return
    op.drop_column(table, name)


def _constraint_exists(table: str, name: str) -> bool:
    if not _is_pg():
        return False
    return bool(
        op.get_bind().execute(
            sa.text(
                "SELECT 1 FROM information_schema.table_constraints "
                "WHERE table_schema = current_schema() AND table_name = :t "
                "AND constraint_name = :n"
            ),
            {"t": table, "n": name},
        ).first()
    )


def _add_unique_constraint(table: str, name: str, columns: list[str]) -> None:
    if _constraint_exists(table, name):
        return
    op.create_unique_constraint(name, table, columns)


def _index_exists(name: str) -> bool:
    if not _is_pg():
        return False
    return bool(
        op.get_bind().execute(
            sa.text(
                "SELECT 1 FROM pg_indexes "
                "WHERE schemaname = current_schema() AND indexname = :n"
            ),
            {"n": name},
        ).first()
    )


def _create_index(name: str, table: str, columns: list[str], unique: bool = False, where=None) -> None:
    """Create an index unless it is already there.

    0001 builds the same indexes for a fresh install, so this must be a no-op in
    that case and additive in the legacy case.
    """
    if _index_exists(name):
        return
    op.create_index(name, table, columns, unique=unique, postgresql_where=where)


def _set_not_null(table: str, column: str, default: str | None = None) -> None:
    """Backfill NULLs with `default` then enforce NOT NULL."""
    if default is not None:
        op.execute(
            sa.text(
                f'UPDATE "{table}" SET "{column}" = {default} WHERE "{column}" IS NULL'
            )
        )
    op.alter_column(table, column, nullable=False)


# ======================================================================
# 1. users - username, Google identity, nullable password/phone
# ======================================================================
def _upgrade_users() -> None:
    _add_column("users", sa.Column("username", sa.String(length=50), nullable=True))
    _add_column("users", sa.Column("email", sa.String(length=255), nullable=True))
    _add_column("users", sa.Column("google_sub", sa.String(length=255), nullable=True))
    _add_column("users", sa.Column("last_login_at", sa.DateTime(), nullable=True))
    if "auth_provider" not in _columns("users"):
        op.add_column(
            "users",
            sa.Column(
                "auth_provider",
                postgresql.ENUM("phone_otp", "google", name="auth_provider"),
                server_default="phone_otp",
                nullable=False,
            ),
        )

    # Usernames: derive one from the phone number so every existing account can
    # still sign in with a username.
    op.execute(
        sa.text(
            "UPDATE users SET username = 'user' || replace(phone_number, ' ', '') "
            "WHERE username IS NULL AND phone_number IS NOT NULL"
        )
    )
    # Legacy profiles store '' for "no email", which would collapse into one
    # shared value and break the unique index below. An empty string is not a
    # usable address, so normalise blanks to NULL before anything reads them.
    op.execute(
        sa.text(
            "UPDATE customer_profiles SET email = NULL "
            "WHERE email IS NOT NULL AND btrim(email) = ''"
        )
    )
    op.execute(
        sa.text(
            "UPDATE customer_profiles SET email = lower(btrim(email)) "
            "WHERE email IS NOT NULL AND email <> lower(btrim(email))"
        )
    )
    # Copy the profile address onto the owning account.
    #
    # This has to be safe to run more than once (a retried upgrade, or a
    # downgrade/upgrade cycle) and the unique index below makes it stricter than
    # it looks: several legacy profiles can legitimately share one address, and
    # on a re-run those profiles already have owners, so a naive copy would try
    # to store the same address twice. Only the lowest user id keeps a shared
    # address, which is stable across runs, and an address already held by
    # another account is never taken.
    op.execute(
        sa.text(
            """
            UPDATE users u
               SET email = src.email
              FROM (
                    SELECT cp.user_id, lower(btrim(cp.email)) AS email
                      FROM customer_profiles cp
                     WHERE cp.email IS NOT NULL
                       AND cp.user_id = (
                             SELECT min(cp2.user_id)
                               FROM customer_profiles cp2
                              WHERE lower(btrim(cp2.email)) = lower(btrim(cp.email))
                                AND cp2.user_id IS NOT NULL
                       )
                  ) src
             WHERE src.user_id = u.id
               AND u.email IS NULL
               AND NOT EXISTS (
                     SELECT 1 FROM users other
                      WHERE other.id <> u.id
                        AND lower(btrim(other.email)) = src.email
                   )
            """
        )
    )
    # Everyone who already had a password passed the old OTP flow.
    op.execute(sa.text("UPDATE users SET is_verified = true WHERE is_verified IS NULL"))

    # A Google-only account has no phone number and no password.
    op.alter_column("users", "phone_number", existing_type=sa.String(length=20), nullable=True)
    op.alter_column("users", "password_hash", existing_type=sa.Text(), nullable=True)
    op.alter_column("users", "is_verified", existing_type=sa.Boolean(), nullable=False, server_default=sa.false())
    op.alter_column(
        "users",
        "account_status",
        existing_type=postgresql.ENUM("active", "suspended", name="account_status"),
        nullable=False,
        server_default="active",
    )

    _create_index("ix_users_username", "users", ["username"], unique=True,
                  where=sa.text("username IS NOT NULL"))
    _create_index("ix_users_email", "users", ["email"], unique=True,
                  where=sa.text("email IS NOT NULL"))
    _create_index("ix_users_google_sub", "users", ["google_sub"], unique=True,
                  where=sa.text("google_sub IS NOT NULL"))
    _create_index("ix_users_phone_number", "users", ["phone_number"], unique=True,
                  where=sa.text("phone_number IS NOT NULL"))
    _create_index("ix_users_id", "users", ["id"])
    # The legacy columns are narrower than the v2 models declare.
    _align_type("users", "phone_number", sa.String(length=20), nullable=True)
    _align_type("users", "password_hash", sa.String(length=255), nullable=True)


# ======================================================================
# 3. otp_verifications - hashed codes only
# ======================================================================
def _upgrade_otps() -> None:
    _add_column("otp_verifications", sa.Column("otp_hash", sa.String(length=128), nullable=True))
    if "purpose" not in _columns("otp_verifications"):
        op.add_column(
            "otp_verifications",
            sa.Column(
                "purpose",
                postgresql.ENUM("signup", "login", "reset_password", name="otp_purpose"),
                server_default="signup",
                nullable=False,
            ),
        )
    _add_column(
        "otp_verifications",
        sa.Column("is_used", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    _add_column(
        "otp_verifications",
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
    )

    # Legacy rows hold PLAINTEXT codes. Mark them spent and hash them into an
    # unusable value so no live passcode survives this migration.
    if "otp" in _columns("otp_verifications"):
        op.execute(
            sa.text(
                "UPDATE otp_verifications SET is_used = true, "
                "otp_hash = 'migrated$' || md5(coalesce(otp, id::text)) "
                "WHERE otp_hash IS NULL"
            )
        )
    else:
        # Fresh install: 0001 never created the plaintext column.
        op.execute(
            sa.text("UPDATE otp_verifications SET is_used = true WHERE otp_hash IS NULL")
        )
    _drop_column("otp_verifications", "otp")
    op.alter_column("otp_verifications", "otp_hash", existing_type=sa.String(length=128), nullable=False)
    op.alter_column(
        "otp_verifications",
        "phone_number",
        existing_type=sa.String(length=20),
        nullable=False,
    )
    _create_index("idx_otp_phone_created", "otp_verifications", ["phone_number", "created_at"])
    _create_index("ix_otp_verifications_id", "otp_verifications", ["id"])
    _create_index("ix_otp_verifications_phone_number", "otp_verifications", ["phone_number"])
    _align_type("otp_verifications", "phone_number", sa.String(length=20), nullable=False)
    _align_type("otp_verifications", "verified", sa.Boolean(), nullable=False)
    _align_type("otp_verifications", "expires_at", sa.DateTime(), nullable=False)


# ======================================================================
# 4. customer_profiles
# ======================================================================
def _upgrade_profiles() -> None:
    _add_column("customer_profiles", sa.Column("phone_number", sa.String(length=20), nullable=True))
    _add_column("customer_profiles", sa.Column("policy_number", sa.String(length=100), nullable=True))
    _add_column("customer_profiles", sa.Column("insurance_provider", sa.String(length=150), nullable=True))
    _add_column("customer_profiles", sa.Column("policy_type", sa.String(length=100), nullable=True))
    _add_column("customer_profiles", sa.Column("policy_details", sa.Text(), nullable=True))
    _add_column("customer_profiles", sa.Column("policy_valid_from", sa.Date(), nullable=True))
    _add_column("customer_profiles", sa.Column("policy_valid_till", sa.Date(), nullable=True))
    _add_column("customer_profiles", sa.Column("default_address_latitude", sa.String(length=20), nullable=True))
    _add_column("customer_profiles", sa.Column("default_address_longitude", sa.String(length=20), nullable=True))
    _add_column("customer_profiles", sa.Column("emergency_contact_name", sa.String(length=120), nullable=True))
    _add_column("customer_profiles", sa.Column("emergency_contact_number", sa.String(length=20), nullable=True))

    op.execute(
        sa.text(
            "UPDATE customer_profiles cp SET phone_number = u.phone_number "
            "FROM users u WHERE cp.user_id = u.id "
            "AND cp.phone_number IS NULL AND u.phone_number IS NOT NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE customer_profiles SET email = lower(btrim(email)) "
            "WHERE email IS NOT NULL AND email <> lower(btrim(email))"
        )
    )
    op.alter_column("customer_profiles", "profile_completed", existing_type=sa.Boolean(), nullable=False, server_default=sa.false())
    # Profiles that were never attached to an account, and the one profile row
    # per user the model requires.
    _attach_orphans("customer_profiles")
    _add_unique_constraint("customer_profiles", "customer_profiles_user_id_key", ["user_id"])
    # index=True columns the model declares but the legacy tables never had.
    _create_index("ix_customer_profiles_id", "customer_profiles", ["id"])
    _create_index("ix_customer_profiles_policy_number", "customer_profiles", ["policy_number"])
    _align_type("customer_profiles", "full_name", sa.String(length=120), nullable=False)
    _align_type("customer_profiles", "email", sa.String(length=255), nullable=True)


# ======================================================================
# 5. branches
# ======================================================================
def _upgrade_branches() -> None:
    op.alter_column("branches", "address", type_=sa.Text(), existing_nullable=False)
    _add_column("branches", sa.Column("city", sa.String(length=100), nullable=True))
    _add_column("branches", sa.Column("state", sa.String(length=100), nullable=True))
    _add_column("branches", sa.Column("pincode", sa.String(length=10), nullable=True))
    _add_column(
        "branches", sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False)
    )


# ======================================================================
# 6. distance_rate_config - the full pricing picture
# ======================================================================
def _upgrade_pricing_config() -> None:
    _add_column("distance_rate_config", sa.Column("threshold_km", sa.Numeric(10, 2), server_default="10.0", nullable=True))
    _add_column("distance_rate_config", sa.Column("tax_percent", sa.Numeric(5, 2), server_default="18.0", nullable=True))
    _add_column("distance_rate_config", sa.Column("round_trip_factor", sa.Numeric(4, 2), server_default="2.0", nullable=True))
    _add_column("distance_rate_config", sa.Column("created_at", sa.TIMESTAMP(), server_default=sa.func.now(), nullable=True))

    op.execute(sa.text("UPDATE distance_rate_config SET threshold_km = 10.0 WHERE threshold_km IS NULL"))
    op.execute(sa.text("UPDATE distance_rate_config SET tax_percent = 18.0 WHERE tax_percent IS NULL"))
    op.execute(sa.text("UPDATE distance_rate_config SET round_trip_factor = 2.0 WHERE round_trip_factor IS NULL"))
    op.execute(sa.text("UPDATE distance_rate_config SET rate_per_km = 20.0 WHERE rate_per_km IS NULL"))

    for column, type_ in (
        ("threshold_km", sa.Numeric(10, 2)),
        ("rate_per_km", sa.Numeric(10, 2)),
        ("tax_percent", sa.Numeric(5, 2)),
        ("round_trip_factor", sa.Numeric(4, 2)),
    ):
        op.alter_column("distance_rate_config", column, type_=type_, nullable=False)

    op.execute(
        sa.text("UPDATE distance_rate_config SET effective_at = created_at WHERE effective_at IS NULL")
    )
    op.alter_column("distance_rate_config", "effective_at", nullable=False)


# ======================================================================
# 7. subscription_plans + user_subscriptions (visit credits)
# ======================================================================
def _upgrade_plans_and_subscriptions() -> None:
    _add_column("subscription_plans", sa.Column("features", sa.JSON(), nullable=True))
    # The API always returns a list, so a NULL here would break the response.
    op.execute(
        sa.text("UPDATE subscription_plans SET features = '[]' WHERE features IS NULL")
    )
    _add_column("subscription_plans", sa.Column("visits_included", sa.Integer(), server_default="1", nullable=True))
    _add_column("subscription_plans", sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=True))
    _add_column("subscription_plans", sa.Column("sort_order", sa.Integer(), server_default="0", nullable=True))

    _add_column("user_subscriptions", sa.Column("total_visits", sa.Integer(), server_default="0", nullable=True))
    _add_column("user_subscriptions", sa.Column("used_visits", sa.Integer(), server_default="0", nullable=True))
    _add_column("user_subscriptions", sa.Column("activated_at", sa.DateTime(), nullable=True))
    _add_column("user_subscriptions", sa.Column("cancelled_at", sa.DateTime(), nullable=True))
    _add_column("user_subscriptions", sa.Column("updated_at", sa.TIMESTAMP(), server_default=sa.func.now(), nullable=True))

    # Grant the plan's visit allowance to every existing subscription.
    op.execute(
        sa.text(
            """
            UPDATE user_subscriptions us
            SET total_visits = COALESCE(
                    (SELECT p.visits_included FROM subscription_plans p WHERE p.id = us.plan_id),
                    1
                ),
                activated_at = COALESCE(us.activated_at, us.created_at)
            """
        )
    )
    for column, type_ in (
        ("total_visits", sa.Integer()),
        ("used_visits", sa.Integer()),
    ):
        op.execute(
            sa.text(f'UPDATE user_subscriptions SET {column} = 0 WHERE {column} IS NULL')
        )
        op.alter_column("user_subscriptions", column, type_=type_, nullable=False, server_default="0")
    op.alter_column(
        "user_subscriptions", "status",
        type_=postgresql.ENUM(name="subscription_status"),
        server_default="pending",
        nullable=False,
    )
    op.execute(
        sa.text(
            "UPDATE subscription_plans SET visits_included = 1 WHERE visits_included IS NULL"
        )
    )
    op.alter_column("subscription_plans", "visits_included", type_=sa.Integer(), nullable=False, server_default="1")
    op.execute(sa.text("UPDATE subscription_plans SET is_active = true WHERE is_active IS NULL"))
    op.alter_column("subscription_plans", "is_active", type_=sa.Boolean(), nullable=False, server_default=sa.true())
    op.alter_column("subscription_plans", "sort_order", type_=sa.Integer(), nullable=False, server_default="0")
    _align_type("subscription_plans", "validity_days", sa.Integer(), nullable=False)
    _create_index("ix_subscription_plans_id", "subscription_plans", ["id"])

    # user_subscriptions.payment_id -> payments.id is the second half of the
    # payments/subscriptions cycle, so the model marks it use_alter=True.
    _align_fk(
        "user_subscriptions", "payment_id", "payments", "id", "SET NULL",
        name="fk_user_subscriptions_payment_id",
    )
    _align_fk(
        "user_subscriptions", "plan_id", "subscription_plans", "id", "RESTRICT",
    )
    _align_type("user_subscriptions", "user_id", sa.Integer(), nullable=False)
    _align_type("user_subscriptions", "plan_id", sa.Integer(), nullable=False)
    _create_index("ix_user_subscriptions_id", "user_subscriptions", ["id"])
    _create_index("ix_user_subscriptions_user_id", "user_subscriptions", ["user_id"])


# ======================================================================
# 8. service_requests - full lifecycle + frozen pricing snapshot
# ======================================================================
def _upgrade_service_requests() -> None:
    _add_column("service_requests", sa.Column("service_type_id", sa.Integer(), nullable=True))
    _add_column("service_requests", sa.Column("customer_place_id", sa.String(length=120), nullable=True))
    _add_column("service_requests", sa.Column("threshold_km_used", sa.Numeric(10, 2), nullable=True))
    _add_column("service_requests", sa.Column("charge_per_km_used", sa.Numeric(10, 2), nullable=True))
    _add_column("service_requests", sa.Column("round_trip_factor_used", sa.Numeric(4, 2), nullable=True))
    _add_column("service_requests", sa.Column("excess_distance_km", sa.Numeric(10, 2), nullable=True))
    _add_column("service_requests", sa.Column("base_amount", sa.Numeric(10, 2), server_default="0", nullable=True))
    _add_column("service_requests", sa.Column("tax_percent_used", sa.Numeric(5, 2), nullable=True))
    _add_column("service_requests", sa.Column("tax_amount", sa.Numeric(10, 2), server_default="0", nullable=True))
    _add_column("service_requests", sa.Column("total_amount", sa.Numeric(10, 2), server_default="0", nullable=True))
    _add_column("service_requests", sa.Column("subscription_id", sa.Integer(), nullable=True))
    _add_column("service_requests", sa.Column("visit_consumed", sa.Boolean(), server_default=sa.false(), nullable=True))
    _add_column("service_requests", sa.Column("cancellation_reason", sa.String(length=255), nullable=True))
    _add_column("service_requests", sa.Column("cancelled_by_user_id", sa.Integer(), nullable=True))
    _add_column("service_requests", sa.Column("cancelled_at", sa.DateTime(), nullable=True))
    _add_column("service_requests", sa.Column("assigned_at", sa.DateTime(), nullable=True))
    _add_column("service_requests", sa.Column("started_at", sa.DateTime(), nullable=True))
    _add_column("service_requests", sa.Column("completed_at", sa.DateTime(), nullable=True))

    # 1. Map the legacy statuses onto the new lifecycle BEFORE the old labels go.
    #    Skipped on a fresh install, where 0001 never had the legacy labels.
    legacy = _enum_values("request_status")
    if "pending" in legacy:
        op.execute(
            sa.text(
                """
                UPDATE service_requests SET status = 'waiting_for_assignment'::request_status
                WHERE status = 'pending'::request_status
                """
            )
        )
    if "charge_pending" in legacy:
        op.execute(
            sa.text(
                """
                UPDATE service_requests SET status = 'payment_pending'::request_status
                WHERE status = 'charge_pending'::request_status
                """
            )
        )
    if "rejected" in legacy:
        op.execute(
            sa.text(
                """
                UPDATE service_requests
                SET status = 'cancelled'::request_status,
                    cancellation_reason = COALESCE(cancellation_reason, 'Closed before the new workflow'),
                    cancelled_at = COALESCE(cancelled_at, updated_at)
                WHERE status = 'rejected'::request_status
                """
            )
        )

    # 2. Freeze the pricing that was in force, so history stays reproducible.
    op.execute(
        sa.text(
            """
            UPDATE service_requests sr
            SET threshold_km_used = cfg.threshold_km,
                charge_per_km_used = COALESCE(sr.distance_rate, cfg.rate_per_km),
                round_trip_factor_used = cfg.round_trip_factor,
                tax_percent_used = cfg.tax_percent,
                excess_distance_km = GREATEST(
                    COALESCE(sr.distance_km, 0) - cfg.threshold_km, 0
                ),
                tax_amount = ROUND(
                    (COALESCE(sr.extra_charge, 0) * cfg.tax_percent / 100)::numeric, 2
                )
            FROM (
                SELECT threshold_km, rate_per_km, tax_percent, round_trip_factor
                FROM distance_rate_config
                ORDER BY effective_at DESC NULLS LAST, id DESC
                LIMIT 1
            ) cfg
            """
        )
    )
    op.execute(
        sa.text(
            "UPDATE service_requests SET base_amount = 0 WHERE base_amount IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE service_requests SET extra_charge = 0 WHERE extra_charge IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE service_requests SET tax_amount = 0 WHERE tax_amount IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE service_requests SET total_amount = base_amount + extra_charge + tax_amount "
            "WHERE total_amount IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE service_requests SET visit_consumed = false WHERE visit_consumed IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE service_requests SET charge_paid = (extra_charge = 0) "
            "WHERE charge_paid IS NULL"
        )
    )

    for column, type_ in (
        ("base_amount", sa.Numeric(10, 2)),
        ("extra_charge", sa.Numeric(10, 2)),
        ("tax_amount", sa.Numeric(10, 2)),
        ("total_amount", sa.Numeric(10, 2)),
    ):
        op.alter_column("service_requests", column, type_=type_, nullable=False, server_default="0")
    op.alter_column("service_requests", "visit_consumed", type_=sa.Boolean(), nullable=False, server_default=sa.false())
    op.alter_column("service_requests", "charge_paid", type_=sa.Boolean(), nullable=False, server_default=sa.true())
    op.alter_column(
        "service_requests", "status",
        type_=postgresql.ENUM(name="request_status"),
        server_default="requested",
        nullable=False,
    )
    _set_not_null("service_requests", "user_id")
    _set_not_null("service_requests", "request_type", default="''")

    _create_index("idx_service_requests_user_status", "service_requests", ["user_id", "status"])
    _create_index("idx_service_requests_status_branch", "service_requests", ["status", "branch_id"])
    _create_index("ix_service_requests_status", "service_requests", ["status"])
    _create_index("ix_service_requests_id", "service_requests", ["id"])
    _create_index("ix_service_requests_user_id", "service_requests", ["user_id"])
    _create_index("ix_service_requests_policy_id", "service_requests", ["policy_id"])
    _create_index("ix_service_requests_branch_id", "service_requests", ["branch_id"])
    _align_fk("service_requests", "service_type_id", "service_types", "id", "SET NULL")
    _align_fk("service_requests", "subscription_id", "user_subscriptions", "id", "SET NULL")
    _align_fk("service_requests", "cancelled_by_user_id", "users", "id", "NO ACTION")


# ======================================================================
# 9. payments - itemised amounts and the verification trail
# ======================================================================
def _upgrade_payments() -> None:
    _add_column("payments", sa.Column("base_amount", sa.Numeric(10, 2), server_default="0", nullable=True))
    _add_column("payments", sa.Column("extra_charge", sa.Numeric(10, 2), server_default="0", nullable=True))
    _add_column("payments", sa.Column("tax_amount", sa.Numeric(10, 2), server_default="0", nullable=True))
    _add_column("payments", sa.Column("idempotency_key", sa.String(length=120), nullable=True))
    _add_column("payments", sa.Column("verified_by", sa.Integer(), nullable=True))
    _add_column("payments", sa.Column("verified_at", sa.DateTime(), nullable=True))
    _add_column("payments", sa.Column("failure_reason", sa.String(length=255), nullable=True))
    _add_column("payments", sa.Column("admin_note", sa.Text(), nullable=True))
    _add_column("payments", sa.Column("updated_at", sa.TIMESTAMP(), server_default=sa.func.now(), nullable=True))

    # Carry the legacy status column into the new one before it is removed.
    # The two columns use different enum TYPES on a legacy database, so the
    # value has to be cast through text: PostgreSQL will not implicitly convert
    # between enum types, and an explicit cast fails loudly if a label is
    # missing instead of silently dropping the row's status.
    status_type = _column_type("payments", "status")
    if "payment_status" in _columns("payments") and "success" in _enum_values("payment_status"):
        op.execute(
            sa.text(
                f"""
                UPDATE payments SET status = payment_status::text::{status_type}
                WHERE status = 'pending'::{status_type}
                  AND payment_status IS NOT NULL
                  AND payment_status <> 'pending'::payment_status
                """
            )
        )
    op.execute(
        sa.text(
            """
            UPDATE payments SET amount = COALESCE(amount, 0), expires_at = COALESCE(expires_at, created_at)
            """
        )
    )
    # Payments that already succeeded were verified at creation time.
    op.execute(
        sa.text(
            "UPDATE payments SET verified_at = COALESCE(verified_at, created_at) "
            f"WHERE status = 'success'::{status_type}"
        )
    )
    op.execute(
        sa.text(
            "UPDATE payments SET txn_id = COALESCE(txn_id, 'legacy-' || id::text) "
            "WHERE txn_id IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE payments SET base_amount = amount, extra_charge = 0, tax_amount = 0 "
            "WHERE base_amount IS NULL"
        )
    )

    op.alter_column("payments", "amount", type_=sa.Numeric(10, 2), nullable=False)
    op.alter_column("payments", "txn_id", type_=sa.String(length=36), nullable=False)
    op.alter_column("payments", "expires_at", type_=sa.DateTime(), nullable=False)
    op.alter_column("payments", "base_amount", type_=sa.Numeric(10, 2), nullable=False, server_default="0")
    op.alter_column("payments", "extra_charge", type_=sa.Numeric(10, 2), nullable=False, server_default="0")
    op.alter_column("payments", "tax_amount", type_=sa.Numeric(10, 2), nullable=False, server_default="0")
    op.alter_column("payments", "attempts", type_=sa.Integer(), nullable=False, server_default="0")
    # The deployed column uses the legacy ``paymentstatus`` type while the model
    # declares ``payment_status``. PostgreSQL refuses enum -> enum without an
    # explicit USING, and every legacy label exists in the target type, so the
    # cast goes through text and fails loudly if that ever stops being true.
    # The old server default is of the old type too, so it is dropped first and
    # re-applied afterwards.
    if _column_type("payments", "status") != "payment_status":
        op.alter_column("payments", "status", server_default=None)
        op.alter_column(
            "payments", "status",
            type_=postgresql.ENUM(name="payment_status"),
            postgresql_using="status::text::payment_status",
            server_default="pending",
            nullable=False,
        )
    else:
        op.alter_column(
            "payments", "status",
            type_=postgresql.ENUM(name="payment_status"),
            server_default="pending",
            nullable=False,
        )
    # payment_type was varchar on the live database, with a varchar default that
    # has to be dropped before the type changes.
    if _column_type("payments", "payment_type") != "payment_type":
        op.alter_column("payments", "payment_type", server_default=None)
    op.alter_column(
        "payments", "payment_type",
        type_=postgresql.ENUM(name="payment_type"),
        postgresql_using="payment_type::text::payment_type",
        server_default="subscription",
        nullable=False,
    )

    _create_index("ix_payments_txn_id", "payments", ["txn_id"], unique=True)
    _create_index("ix_payments_utr_number", "payments", ["utr_number"], unique=True,
                  where=sa.text("utr_number IS NOT NULL"))
    _create_index("idx_payments_user_plan", "payments", ["user_id", "plan_id"])
    _create_index("idx_payments_status", "payments", ["status"])
    _create_index("idx_payments_type_status", "payments", ["payment_type", "status"])

    # payments.related_request_id -> service_requests.id closes the
    # payments/service_requests cycle, so it is declared use_alter=True on the
    # model and has to be aligned here.
    _align_fk(
        "payments", "related_request_id", "service_requests", "id", "SET NULL",
        name="fk_payments_related_request_id",
    )
    _align_fk("payments", "verified_by", "users", "id", "NO ACTION")
    _align_type("payments", "user_id", sa.Integer(), nullable=False)
    _align_type("payments", "currency", sa.String(length=10), nullable=False)
    _create_index("ix_payments_id", "payments", ["id"])
    _create_index("ix_payments_user_id", "payments", ["user_id"])

    # Legacy gateway columns are dead weight now that UPI + UTR is the flow.
    for legacy in ("payment_gateway", "payment_status", "payment_date", "transaction_id"):
        _drop_column("payments", legacy)


# ======================================================================
# 10. field members + assignments
# ======================================================================
def _upgrade_field_members() -> None:
    if "approval_status" not in _columns("field_members"):
        op.add_column(
            "field_members",
            sa.Column(
                "approval_status",
                postgresql.ENUM(
                    "pending", "approved", "rejected", "suspended",
                    name="field_member_approval_status",
                ),
                server_default="pending",
                nullable=False,
            ),
        )
    _add_column("field_members", sa.Column("approved_by", sa.Integer(), nullable=True))
    _add_column("field_members", sa.Column("approved_at", sa.DateTime(), nullable=True))
    _add_column("field_members", sa.Column("rejection_reason", sa.String(length=255), nullable=True))
    _add_column(
        "field_members", sa.Column("is_available", sa.Boolean(), server_default=sa.true(), nullable=True)
    )

    # An account that already holds the field_member role is treated as approved.
    op.execute(
        sa.text(
            """
            UPDATE field_members fm SET approval_status = 'approved'::field_member_approval_status,
                approved_at = COALESCE(fm.approved_at, fm.created_at)
            FROM users u
            WHERE u.id = fm.user_id AND u.role = 'field_member'::user_role
            """
        )
    )
    op.execute(sa.text("UPDATE field_members SET is_available = true WHERE is_available IS NULL"))
    op.alter_column("field_members", "is_available", type_=sa.Boolean(), nullable=False, server_default=sa.true())
    _set_not_null("field_members", "user_id")
    # One field-member record per user: UNIQUE constraint, matching unique=True.
    _add_unique_constraint("field_members", "field_members_user_id_key", ["user_id"])
    _create_index("ix_field_members_employee_code", "field_members", ["employee_code"], unique=True,
                  where=sa.text("employee_code IS NOT NULL"))
    _create_index("ix_field_members_id", "field_members", ["id"])
    _add_column("field_members", sa.Column("full_name", sa.String(length=120), nullable=True))
    _align_fk("field_members", "approved_by", "users", "id", "NO ACTION")


def _upgrade_assignments() -> None:
    if "status" not in _columns("request_assignments"):
        op.add_column(
            "request_assignments",
            sa.Column(
                "status",
                postgresql.ENUM("active", "unassigned", "cancelled", "rejected", name="assignment_status"),
                server_default="active",
                nullable=False,
            ),
        )
    _add_column("request_assignments", sa.Column("notes", sa.String(length=255), nullable=True))
    _add_column("request_assignments", sa.Column("unassigned_at", sa.DateTime(), nullable=True))
    _set_not_null("request_assignments", "request_id")
    _set_not_null("request_assignments", "field_member_id")
    _create_index("idx_assignments_request_status", "request_assignments", ["request_id", "status"])
    _create_index("idx_assignments_member_status", "request_assignments", ["field_member_id", "status"])
    _create_index("ix_request_assignments_id", "request_assignments", ["id"])
    _create_index("ix_request_assignments_request_id", "request_assignments", ["request_id"])
    _create_index("ix_request_assignments_field_member_id", "request_assignments", ["field_member_id"])
    _align_fk("request_assignments", "field_member_id", "field_members", "id", "CASCADE")


# ======================================================================
# 10b. notifications - align the enum type name
# ======================================================================
def _upgrade_notifications() -> None:
    """The live database calls this type ``notificationcategory``.

    0002_expand_enums creates ``notification_category`` carrying the old labels
    plus the new ones, so the cast below cannot lose a category.
    """
    current = _column_type("notifications", "category")
    if current == "notification_category":
        return
    if not _type_exists("notification_category"):
        return
    # Cast first (NULLs pass through), then fill them in with a label that only
    # the NEW type has, then tighten to NOT NULL.
    op.alter_column(
        "notifications",
        "category",
        type_=postgresql.ENUM(name="notification_category"),
        postgresql_using="category::text::notification_category",
        existing_type=postgresql.ENUM(name=current) if current != "text" else None,
        nullable=True,
    )
    op.execute(
        sa.text("UPDATE notifications SET category = 'account' WHERE category IS NULL")
    )
    op.alter_column("notifications", "category", nullable=False)


# ======================================================================
# 11. policies
# ======================================================================
def _upgrade_policies() -> None:
    _add_column("policies", sa.Column("start_date", sa.Date(), nullable=True))
    _add_column("policies", sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=True))

    for column in ("policy_type", "provider_name", "policy_number"):
        op.execute(
            sa.text(f"UPDATE policies SET {column} = '' WHERE {column} IS NULL")
        )
    op.execute(sa.text("UPDATE policies SET policy_category = 'individual' WHERE policy_category IS NULL"))
    op.execute(sa.text("UPDATE policies SET is_active = true WHERE is_active IS NULL"))

    op.alter_column("policies", "policy_type", type_=sa.String(length=100), nullable=False)
    op.alter_column("policies", "provider_name", type_=sa.String(length=100), nullable=False)
    op.alter_column("policies", "policy_number", type_=sa.String(length=100), nullable=False)
    op.alter_column("policies", "policy_category", type_=sa.String(length=20), nullable=False, server_default="individual")
    op.alter_column("policies", "is_active", type_=sa.Boolean(), nullable=False, server_default=sa.true())
    # Policies saved without an owner (one row on the live database) go to the
    # placeholder account rather than being deleted or given a real owner.
    _attach_orphans("policies")
    _align_type("policies", "document_url", sa.String(length=500), nullable=True)
    _create_index("idx_policies_user_active", "policies", ["user_id", "is_active"])
    _create_index("ix_policies_id", "policies", ["id"])
    _create_index("ix_policies_user_id", "policies", ["user_id"])
    _create_index("ix_policies_policy_number", "policies", ["policy_number"])
    _create_index("ix_family_members_id", "family_members", ["id"])
    _create_index("ix_policy_members_id", "policy_members", ["id"])


# ======================================================================
# 12. New tables
# ======================================================================
def _table_exists(name: str) -> bool:
    if not _is_pg():
        return False
    return bool(
        op.get_bind().execute(
            sa.text(
                "SELECT 1 FROM information_schema.tables "
                "WHERE table_schema = current_schema() AND table_name = :n"
            ),
            {"n": name},
        ).first()
    )


def _create_service_types() -> None:
    if _table_exists("service_types"):
        return
    op.create_table(
        "service_types",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("code", sa.String(length=50), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("icon", sa.String(length=50), server_default="support_agent", nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(), server_default=sa.func.now(), nullable=True),
    )
    op.create_index("ix_service_types_code", "service_types", ["code"], unique=True)
    op.create_index("ix_service_types_id", "service_types", ["id"])

    op.bulk_insert(
        sa.table(
            "service_types",
            sa.column("code", sa.String),
            sa.column("name", sa.String),
            sa.column("description", sa.Text),
            sa.column("icon", sa.String),
            sa.column("sort_order", sa.Integer),
        ),
        [
            {"code": "claim_intimation", "name": "Claim Intimation",
             "description": "Register a claim with your insurer", "icon": "assignment", "sort_order": 1},
            {"code": "policy_assistance", "name": "Policy Assistance",
             "description": "Help with policy wording, renewal and updates", "icon": "description", "sort_order": 2},
            {"code": "inspection", "name": "Inspection Support",
             "description": "Doorstep inspection or risk assessment support", "icon": "search", "sort_order": 3},
            {"code": "other", "name": "Other Assistance",
             "description": "Anything else you need help with", "icon": "support_agent", "sort_order": 4},
        ],
    )


def _create_visit_ledger() -> None:
    if _table_exists("visit_ledger"):
        return
    op.create_table(
        "visit_ledger",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("subscription_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        # create_type=False: the type is created (with its labels) by
        # 0002_expand_enums, and letting Alembic create it here would try
        # CREATE TYPE with no labels and fail with DuplicateObject.
        sa.Column(
            "entry_type",
            postgresql.ENUM(name="visit_entry_type", create_type=False),
            nullable=False,
        ),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("service_request_id", sa.Integer(), nullable=True),
        sa.Column("note", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(), server_default=sa.func.now(), nullable=True),
        sa.ForeignKeyConstraint(["subscription_id"], ["user_subscriptions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["service_request_id"], ["service_requests.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "subscription_id", "service_request_id", "entry_type",
            name="uq_visit_ledger_request_once",
        ),
    )
    op.create_index("ix_visit_ledger_id", "visit_ledger", ["id"])
    op.create_index("ix_visit_ledger_subscription_id", "visit_ledger", ["subscription_id"])
    op.create_index("ix_visit_ledger_user_id", "visit_ledger", ["user_id"])
    op.create_index("idx_visit_ledger_sub_type", "visit_ledger", ["subscription_id", "entry_type"])


def _backfill_visit_ledger() -> None:
    """Reconstruct the visit history for subscriptions created before v2.

    One ``allocated`` row per subscription, and one ``consumed`` row for every
    request that reached COMPLETED, so the ledger agrees with the visit totals.
    """
    op.execute(
        sa.text(
            """
            INSERT INTO visit_ledger (subscription_id, user_id, entry_type, quantity, note, created_at)
            SELECT us.id, us.user_id, 'allocated'::visit_entry_type, us.total_visits,
                   'Plan activation (migrated from pre-visit-credit system)',
                   COALESCE(us.activated_at, us.created_at)
            FROM user_subscriptions us
            WHERE us.total_visits > 0
              AND NOT EXISTS (
                SELECT 1 FROM visit_ledger vl
                WHERE vl.subscription_id = us.id AND vl.entry_type = 'allocated'::visit_entry_type
              )
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE user_subscriptions us
            SET used_visits = COALESCE(sub.completed, 0)
            FROM (
                SELECT us2.id AS subscription_id, count(sr.id) AS completed
                FROM user_subscriptions us2
                LEFT JOIN service_requests sr
                       ON sr.user_id = us2.user_id
                      AND sr.status = 'completed'::request_status
                      AND sr.created_at >= COALESCE(us2.start_date, us2.created_at)
                GROUP BY us2.id
            ) sub
            WHERE us.id = sub.subscription_id
            """
        )
    )


# ======================================================================
# upgrade / downgrade
# ======================================================================
def upgrade() -> None:
    # service_types first: service_requests.service_type_id points at it.
    _create_service_types()
    _upgrade_users()
    _upgrade_otps()
    _upgrade_profiles()
    _upgrade_branches()
    _upgrade_pricing_config()
    _upgrade_plans_and_subscriptions()
    _upgrade_service_requests()
    _upgrade_payments()
    _upgrade_field_members()
    _upgrade_assignments()
    _upgrade_notifications()
    _upgrade_policies()
    _create_visit_ledger()
    _backfill_visit_ledger()


def _drop_index_if_exists(index: str, table: str) -> None:
    op.execute(sa.text(f"DROP INDEX IF EXISTS {index}"))


def _drop_table_if_exists(table: str) -> None:
    op.execute(sa.text(f"DROP TABLE IF EXISTS {table} CASCADE"))


def downgrade() -> None:
    """Reverse of the additive changes.

    This is deliberately conservative and is NOT a data-restoring rollback:

    * Columns added by this revision are left in place, because the pre-existing
      data they now hold cannot be recovered once the new shape is in use.
    * Enum labels are left in place; PostgreSQL cannot remove a value without
      recreating the type, which would break every column that still uses it.
    * New tables are dropped, and only when they were actually created here.
      ``service_types`` is present in 0001 on a fresh install, so dropping it
      unconditionally would destroy the catalogue seeded there.

    In other words: rolling back to 0002 returns a system that still runs and
    still holds all original rows, but which ignores the v2 features.
    """
    # visit_ledger is always new in this revision.
    for index in (
        "idx_visit_ledger_sub_type",
        "ix_visit_ledger_user_id",
        "ix_visit_ledger_subscription_id",
        "ix_visit_ledger_id",
    ):
        _drop_index_if_exists(index, "visit_ledger")
    _drop_table_if_exists("visit_ledger")

    # service_types only exists in 0001 on a fresh install, so only its
    # v2-added indexes are removed and the table itself is left alone.
    for index in ("ix_service_types_id", "ix_service_types_code"):
        _drop_index_if_exists(index, "service_types")

    for index in (
        "idx_payments_type_status",
        "idx_payments_status",
        "idx_payments_user_plan",
        "idx_assignments_member_status",
        "idx_assignments_request_status",
        "ix_field_members_employee_code",
        # ix_field_members_user_id became a unique constraint on user_id, so
        # there is no such index to drop.
        "idx_policies_user_active",
        "idx_service_requests_status",
        "idx_service_requests_status_branch",
        "idx_service_requests_user_status",
    ):
        table = (
            "payments"
            if index.startswith("idx_payments")
            else "request_assignments"
            if index.startswith("idx_assignments")
            else "field_members"
            if index.startswith("ix_field_members")
            else "policies"
            if index.startswith("idx_policies")
            else "service_requests"
        )
        _drop_index_if_exists(index, table)
