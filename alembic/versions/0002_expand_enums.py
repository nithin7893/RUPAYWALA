"""rupaywala v2 step 1: widen the enum types

Revision ID: 0002_expand_enums
Revises: 0001_initial_schema
Create Date: 2026-09-27

Why this is a separate revision
-------------------------------
PostgreSQL refuses to *use* a label added by ``ALTER TYPE ... ADD VALUE``
until the transaction that added it has committed:

    ERROR: unsafe use of new value "pending" of enum type subscription_status

So the new labels have to be committed on their own before the next revision
uses them as server defaults or casts. ``alembic/env.py`` sets
``transaction_per_migration=True`` so every revision commits separately.

Nothing else happens here: no data is touched and no column is altered. Enum
TYPE NAMES are preserved (``user_role``, ``request_status``, ``payment_status``,
...) so no column has to be rewritten through a lossy cast.
"""

import functools
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0002_expand_enums"
down_revision: Union[str, None] = "0001_initial_schema"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


@functools.lru_cache(maxsize=1)
def _is_pg() -> bool:
    """Whether the migration runs against PostgreSQL.

    Evaluated lazily and cached: ``op.get_bind()`` is only valid once Alembic is
    executing a revision, never while this module is being imported.
    """
    return op.get_bind().dialect.name == "postgresql"


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


def _enum_values(type_name: str) -> set:
    if not _is_pg():
        return set()
    return {
        row[0]
        for row in op.get_bind()
        .execute(
            sa.text(
                "SELECT enumlabel FROM pg_enum e "
                "JOIN pg_type t ON t.oid = e.enumtypid "
                "JOIN pg_namespace n ON n.oid = t.typnamespace "
                "WHERE t.typname = :t AND n.nspname = current_schema()"
            ),
            {"t": type_name},
        )
    }


def _create_enum_type(type_name: str, values: list) -> None:
    if not _is_pg() or _type_exists(type_name):
        return
    labels = ", ".join(repr(v) for v in values)
    op.execute(sa.text(f"CREATE TYPE {type_name} AS ENUM ({labels})"))


def _add_enum_values(type_name: str, values: list) -> None:
    if not _is_pg() or not _type_exists(type_name):
        return
    existing = _enum_values(type_name)
    for value in values:
        if value not in existing:
            op.execute(sa.text(f"ALTER TYPE {type_name} ADD VALUE IF NOT EXISTS '{value}'"))


def _ensure_type(target: str, legacy_aliases: list, values: list) -> None:
    """Make sure ``target`` exists and carries at least ``values``.

    A live deployment may hold the type under an older name (for example
    ``notificationcategory`` rather than ``notification_category``). In that case
    the new type is created carrying the old labels plus the new ones, so the
    following revision can cast the column across without losing data.
    """
    if not _is_pg():
        return
    if _type_exists(target):
        _add_enum_values(target, values)
        return
    for alias in legacy_aliases:
        if _type_exists(alias):
            merged = list(dict.fromkeys(list(_enum_values(alias)) + list(values)))
            _create_enum_type(target, merged)
            return
    _create_enum_type(target, values)


def upgrade() -> None:
    # New lifecycle labels on the existing request_status type.
    _add_enum_values(
        "request_status",
        [
            "requested",
            "payment_pending",
            "payment_completed",
            "waiting_for_assignment",
            "cancelled",
        ],
    )
    _add_enum_values("subscription_status", ["pending"])
    _add_enum_values("payment_status", ["pending_verification", "expired", "cancelled"])
    # notification_category did not exist under that name on the live database
    # (it is ``notificationcategory`` there), so it is seeded from the old type.
    _ensure_type("notification_category", ["notificationcategory"], ["account", "admin"])

    # Genuinely new types.
    _ensure_type("payment_type", ["paymenttype"], ["subscription", "extra_charge"])
    _ensure_type("auth_provider", ["authprovider"], ["phone_otp", "google"])
    _ensure_type("otp_purpose", ["otppurpose"], ["signup", "login", "reset_password"])
    _ensure_type(
        "assignment_status",
        ["assignmentstatus"],
        ["active", "unassigned", "cancelled", "rejected"],
    )
    _ensure_type(
        "field_member_approval_status",
        ["fieldmemberapprovalstatus"],
        ["pending", "approved", "rejected", "suspended"],
    )
    _ensure_type(
        "visit_entry_type",
        ["visitentrytype"],
        ["allocated", "consumed", "refunded", "expired"],
    )


def downgrade() -> None:
    # PostgreSQL cannot remove an enum label without recreating the type and
    # rewriting every column that uses it, which would drop data that this
    # migration is required to preserve. New labels are left in place.
    pass
