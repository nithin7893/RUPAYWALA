"""Stage 5.1 security remediation.

Revision ID: 0006_stage5_security_remediation
Revises: 0005_fixed_quotes

Additive only:

* ``service_quotes.signature_version`` - distinguishes the pre-remediation
  payload (version 1) from the lifecycle-signed payload (version 2). Existing
  rows default to 1, so they are never silently treated as version 2.
* ``service_requests.quote_ref`` - permanent link from a request to the signed
  quotation that authorised its price. NULL for every historical request, so
  legacy rows keep their existing behaviour.
* ``uq_service_requests_quote_ref`` - one quotation can authorise at most one
  request.
* ``uq_payments_user_type_idem_open`` - one open payment intent per
  (customer, payment type, idempotency key).
* ``uq_payments_open_extra_charge_request`` - one open extra-charge intent per
  service request.

No row is updated, deleted or backfilled. Before creating either unique index
the migration inspects existing data and aborts with a clear report if
historical duplicates would make the constraint unsafe. No destructive
fallback is ever attempted.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0006_stage5_security_remediation"
down_revision: Union[str, None] = "0005_fixed_quotes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _require_postgresql() -> None:
    name = op.get_bind().dialect.name
    if name != "postgresql":
        raise RuntimeError(
            "Migration 0006 requires PostgreSQL (partial unique indexes and the "
            f"existing enum columns). Current dialect: {name!r}."
        )


def _duplicate_open_idempotency() -> list:
    return op.get_bind().execute(
        sa.text(
            """
            SELECT user_id, payment_type, idempotency_key, COUNT(*) AS duplicates
            FROM payments
            WHERE idempotency_key IS NOT NULL
              AND status IN ('pending', 'pending_verification')
            GROUP BY user_id, payment_type, idempotency_key
            HAVING COUNT(*) > 1
            ORDER BY duplicates DESC, user_id, payment_type, idempotency_key
            """
        )
    ).fetchall()


def _duplicate_open_extra_charge() -> list:
    return op.get_bind().execute(
        sa.text(
            """
            SELECT related_request_id, COUNT(*) AS duplicates
            FROM payments
            WHERE payment_type = 'extra_charge'
              AND related_request_id IS NOT NULL
              AND status IN ('pending', 'pending_verification')
            GROUP BY related_request_id
            HAVING COUNT(*) > 1
            ORDER BY duplicates DESC, related_request_id
            """
        )
    ).fetchall()


def _describe_duplicates(rows: list) -> str:
    lines = []
    for row in rows:
        lines.append(" | ".join(str(value) for value in row))
    return "\n".join(lines)


def upgrade() -> None:
    _require_postgresql()

    op.add_column(
        "service_quotes",
        sa.Column(
            "signature_version",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
    )

    op.add_column(
        "service_requests",
        sa.Column("quote_ref", sa.String(length=64), nullable=True),
    )
    op.create_unique_constraint(
        "uq_service_requests_quote_ref", "service_requests", ["quote_ref"]
    )

    # ---- duplicate inspection before any unique constraint -------------
    duplicate_idempotency = _duplicate_open_idempotency()
    if duplicate_idempotency:
        raise RuntimeError(
            "Cannot add uq_payments_user_type_idem_open: historical open payment "
            "rows already share (user_id, payment_type, idempotency_key). "
            "No data was changed. Resolve these duplicates manually and re-run:\n"
            + _describe_duplicates(duplicate_idempotency)
        )

    duplicate_extra_charge = _duplicate_open_extra_charge()
    if duplicate_extra_charge:
        raise RuntimeError(
            "Cannot add uq_payments_open_extra_charge_request: historical open "
            "extra-charge intents already share a service request. "
            "No data was changed. Resolve these duplicates manually and re-run:\n"
            + _describe_duplicates(duplicate_extra_charge)
        )

    op.create_index(
        "uq_payments_user_type_idem_open",
        "payments",
        ["user_id", "payment_type", "idempotency_key"],
        unique=True,
        postgresql_where=sa.text(
            "idempotency_key IS NOT NULL "
            "AND status IN ('pending', 'pending_verification')"
        ),
    )
    op.create_index(
        "uq_payments_open_extra_charge_request",
        "payments",
        ["related_request_id"],
        unique=True,
        postgresql_where=sa.text(
            "payment_type = 'extra_charge' "
            "AND related_request_id IS NOT NULL "
            "AND status IN ('pending', 'pending_verification')"
        ),
    )


def downgrade() -> None:
    _require_postgresql()

    op.drop_index("uq_payments_open_extra_charge_request", table_name="payments")
    op.drop_index("uq_payments_user_type_idem_open", table_name="payments")

    op.drop_constraint(
        "uq_service_requests_quote_ref", "service_requests", type_="unique"
    )
    op.drop_column("service_requests", "quote_ref")

    op.drop_column("service_quotes", "signature_version")
