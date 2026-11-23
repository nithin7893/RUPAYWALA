"""Add persisted, single-use fixed-price quotations.

Revision ID: 0005_fixed_quotes
Revises: 0004_subscription_entitlements

The table is additive only. No existing table, row or enum is modified.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0005_fixed_quotes"
down_revision: Union[str, None] = "0004_subscription_entitlements"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "service_quotes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("quote_ref", sa.String(length=64), nullable=False),
        sa.Column("signature", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("service_type_id", sa.Integer(), nullable=True),
        sa.Column("request_type", sa.String(length=100), nullable=False),
        sa.Column("branch_id", sa.Integer(), nullable=True),
        sa.Column("policy_id", sa.Integer(), nullable=True),
        sa.Column("subscription_id", sa.Integer(), nullable=True),
        sa.Column("family_member_id", sa.Integer(), nullable=True),
        sa.Column(
            "visit_required",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.Column("customer_latitude", sa.Numeric(precision=10, scale=7), nullable=True),
        sa.Column("customer_longitude", sa.Numeric(precision=10, scale=7), nullable=True),
        sa.Column("customer_address", sa.Text(), nullable=True),
        sa.Column("customer_place_id", sa.String(length=120), nullable=True),
        sa.Column("distance_km", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("duration_minutes", sa.Numeric(precision=10, scale=1), nullable=True),
        sa.Column("distance_rate_config_id", sa.Integer(), nullable=True),
        sa.Column("threshold_km_used", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("charge_per_km_used", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column(
            "round_trip_factor_used", sa.Numeric(precision=4, scale=2), nullable=True
        ),
        sa.Column("excess_distance_km", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column(
            "entitlement_included_distance_km",
            sa.Numeric(precision=10, scale=2),
            nullable=True,
        ),
        sa.Column(
            "base_amount", sa.Numeric(precision=10, scale=2), server_default="0", nullable=False
        ),
        sa.Column(
            "extra_charge", sa.Numeric(precision=10, scale=2), server_default="0", nullable=False
        ),
        sa.Column("tax_percent_used", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column(
            "tax_amount", sa.Numeric(precision=10, scale=2), server_default="0", nullable=False
        ),
        sa.Column(
            "total_amount", sa.Numeric(precision=10, scale=2), server_default="0", nullable=False
        ),
        sa.Column(
            "currency", sa.String(length=3), server_default="INR", nullable=False
        ),
        sa.Column(
            "within_threshold", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
        sa.Column(
            "requires_payment", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
        sa.Column(
            "status",
            sa.Enum(
                "active",
                "consumed",
                "expired",
                "cancelled",
                name="quote_status",
            ),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(), nullable=True),
        sa.Column("service_request_id", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["service_type_id"], ["service_types.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["branch_id"], ["branches.id"]),
        sa.ForeignKeyConstraint(["policy_id"], ["policies.id"]),
        sa.ForeignKeyConstraint(
            ["subscription_id"], ["user_subscriptions.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["family_member_id"],
            ["subscription_family_members.id"],
            ondelete="SET NULL",
            name="fk_service_quotes_family_member_id",
        ),
        sa.ForeignKeyConstraint(
            ["distance_rate_config_id"], ["distance_rate_config.id"]
        ),
        sa.ForeignKeyConstraint(
            ["service_request_id"], ["service_requests.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("quote_ref", name="uq_service_quotes_quote_ref"),
        sa.UniqueConstraint(
            "service_request_id", name="uq_service_quotes_service_request_id"
        ),
    )

    op.create_index(op.f("ix_service_quotes_id"), "service_quotes", ["id"], unique=False)
    op.create_index(
        op.f("ix_service_quotes_user_id"), "service_quotes", ["user_id"], unique=False
    )
    op.create_index(
        op.f("ix_service_quotes_branch_id"), "service_quotes", ["branch_id"], unique=False
    )
    op.create_index(
        "idx_service_quotes_user_status",
        "service_quotes",
        ["user_id", "status"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_service_quotes_user_status", table_name="service_quotes")
    op.drop_index(op.f("ix_service_quotes_branch_id"), table_name="service_quotes")
    op.drop_index(op.f("ix_service_quotes_user_id"), table_name="service_quotes")
    op.drop_index(op.f("ix_service_quotes_id"), table_name="service_quotes")
    op.drop_table("service_quotes")

    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(sa.text("DROP TYPE IF EXISTS quote_status"))
