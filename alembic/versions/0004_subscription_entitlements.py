"""Add database-backed subscription entitlements and purchase snapshots.

Revision ID: 0004_subscription_entitlements
Revises: b96aae0ed4c8
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0004_subscription_entitlements"
down_revision: Union[str, None] = "b96aae0ed4c8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "subscription_plans", sa.Column("code", sa.String(length=50), nullable=True)
    )
    op.execute(
        sa.text(
            "UPDATE subscription_plans SET code = 'legacy-' || id WHERE code IS NULL"
        )
    )
    op.create_index(
        "ix_subscription_plans_code", "subscription_plans", ["code"], unique=True
    )

    plan_columns = (
        sa.Column("additional_visits", sa.Integer(), nullable=True),
        sa.Column("included_visit_distance_km", sa.Numeric(6, 2), nullable=True),
        sa.Column("max_adult_members", sa.Integer(), nullable=True),
        sa.Column("max_child_members", sa.Integer(), nullable=True),
        sa.Column(
            "document_verification",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column(
            "online_submission",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column(
            "document_storage",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("storage_duration_days", sa.Integer(), nullable=True),
        sa.Column(
            "priority_support",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column(
            "addon_eligibility",
            sa.JSON(),
            nullable=False,
            server_default=sa.text("'{}'"),
        ),
    )
    for column in plan_columns:
        op.add_column("subscription_plans", column)

    op.add_column(
        "user_subscriptions",
        sa.Column("plan_name_snapshot", sa.String(length=100), nullable=True),
    )
    op.add_column(
        "user_subscriptions",
        sa.Column("price_snapshot", sa.Numeric(10, 2), nullable=True),
    )
    op.add_column(
        "user_subscriptions",
        sa.Column("entitlements_snapshot", sa.JSON(), nullable=True),
    )
    op.add_column(
        "service_requests",
        sa.Column(
            "visit_required",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("subscription_family_members"):
        op.create_table(
            "subscription_family_members",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "subscription_id",
                sa.Integer(),
                sa.ForeignKey("user_subscriptions.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("member_name", sa.String(length=100), nullable=False),
            sa.Column("relationship", sa.String(length=50), nullable=False),
            sa.Column("member_type", sa.String(length=10), nullable=False),
            sa.Column("date_of_birth", sa.Date(), nullable=True),
            sa.Column("identity_key", sa.String(length=250), nullable=False),
            sa.Column("created_at", sa.TIMESTAMP(), server_default=sa.func.now()),
            sa.UniqueConstraint(
                "subscription_id",
                "identity_key",
                name="uq_subscription_family_identity",
            ),
        )
        inspector = sa.inspect(bind)
    else:
        expected_columns = {
            "id",
            "subscription_id",
            "member_name",
            "relationship",
            "member_type",
            "date_of_birth",
            "identity_key",
            "created_at",
        }
        existing_columns = {
            column["name"]
            for column in inspector.get_columns("subscription_family_members")
        }
        missing_columns = expected_columns - existing_columns
        if missing_columns:
            raise RuntimeError(
                "Existing subscription_family_members table is missing columns: "
                + ", ".join(sorted(missing_columns))
            )

    family_member_indexes = {
        index["name"]
        for index in inspector.get_indexes("subscription_family_members")
    }
    if "ix_subscription_family_members_subscription_id" not in family_member_indexes:
        op.create_index(
            "ix_subscription_family_members_subscription_id",
            "subscription_family_members",
            ["subscription_id"],
        )
    with op.batch_alter_table("service_requests") as batch_op:
        batch_op.add_column(
            sa.Column(
                "family_member_id",
                sa.Integer(),
                sa.ForeignKey(
                    "subscription_family_members.id",
                    ondelete="SET NULL",
                    name="fk_service_requests_family_member_id",
                ),
                nullable=True,
            )
        )
    op.execute(
        sa.text(
            """
            UPDATE user_subscriptions
            SET plan_name_snapshot = (
                    SELECT plan_name FROM subscription_plans
                    WHERE subscription_plans.id = user_subscriptions.plan_id
                ),
                price_snapshot = (
                    SELECT price FROM subscription_plans
                    WHERE subscription_plans.id = user_subscriptions.plan_id
                )
            WHERE plan_name_snapshot IS NULL OR price_snapshot IS NULL
            """
        )
    )


def downgrade() -> None:
    with op.batch_alter_table("service_requests") as batch_op:
        batch_op.drop_column("family_member_id")
    op.drop_index(
        "ix_subscription_family_members_subscription_id",
        table_name="subscription_family_members",
    )
    op.drop_table("subscription_family_members")
    op.drop_column("service_requests", "visit_required")
    op.drop_column("user_subscriptions", "entitlements_snapshot")
    op.drop_column("user_subscriptions", "price_snapshot")
    op.drop_column("user_subscriptions", "plan_name_snapshot")
    op.drop_column("subscription_plans", "addon_eligibility")
    op.drop_column("subscription_plans", "priority_support")
    op.drop_column("subscription_plans", "storage_duration_days")
    op.drop_column("subscription_plans", "document_storage")
    op.drop_column("subscription_plans", "online_submission")
    op.drop_column("subscription_plans", "document_verification")
    op.drop_column("subscription_plans", "included_visit_distance_km")
    op.drop_column("subscription_plans", "additional_visits")
    op.drop_column("subscription_plans", "max_child_members")
    op.drop_column("subscription_plans", "max_adult_members")
    op.drop_index("ix_subscription_plans_code", table_name="subscription_plans")
    op.drop_column("subscription_plans", "code")
