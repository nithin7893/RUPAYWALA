"""Private document storage metadata and audit logs.

Revision ID: 0008_private_document_storage
Revises: 0007_user_token_version
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008_private_document_storage"
down_revision: Union[str, None] = "0007_user_token_version"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


DOCUMENT_SCAN_STATUS_VALUES = ("PENDING", "CLEAN", "INFECTED", "FAILED")
SCAN_STATUS_ENUM = postgresql.ENUM(
    *DOCUMENT_SCAN_STATUS_VALUES,
    name="document_scan_status",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    # Explicitly manage enum creation to avoid SQLAlchemy auto-create duplication.
    existing = bind.execute(
        sa.text(
            """
            SELECT e.enumlabel
            FROM pg_type t
            JOIN pg_enum e ON t.oid = e.enumtypid
            JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE t.typname = 'document_scan_status' AND n.nspname = 'public'
            ORDER BY e.enumsortorder
            """
        )
    ).scalars().all()
    if existing:
        if tuple(existing) != DOCUMENT_SCAN_STATUS_VALUES:
            raise RuntimeError(
                "document_scan_status enum already exists with unexpected labels; "
                "manual inspection required before migration 0008"
            )
    else:
        SCAN_STATUS_ENUM.create(bind, checkfirst=True)

    op.create_table(
        "document_records",
        sa.Column("id", sa.String(length=36), primary_key=True, nullable=False),
        sa.Column("owner_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("document_type", sa.String(length=50), nullable=False),
        sa.Column("storage_provider", sa.String(length=20), nullable=False, server_default="local"),
        sa.Column("storage_key", sa.String(length=512), nullable=False),
        sa.Column("bucket", sa.String(length=255), nullable=True),
        sa.Column("original_filename", sa.String(length=255), nullable=True),
        sa.Column("mime_type", sa.String(length=100), nullable=False),
        sa.Column("file_size", sa.BigInteger(), nullable=False),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=False),
        sa.Column("scan_status", SCAN_STATUS_ENUM, nullable=False, server_default="PENDING"),
        sa.Column("scan_detail", sa.String(length=255), nullable=True),
        sa.Column("uploaded_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.Column("expires_at", sa.DateTime(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.Column("deleted_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    )
    op.create_index("idx_document_records_owner_type", "document_records", ["owner_id", "document_type"])
    op.create_index("idx_document_records_scan_status", "document_records", ["scan_status"])
    op.create_index("idx_document_records_deleted_at", "document_records", ["deleted_at"])
    op.create_index(op.f("ix_document_records_owner_id"), "document_records", ["owner_id"])
    op.create_index(op.f("ix_document_records_document_type"), "document_records", ["document_type"])

    op.create_table(
        "document_audit_logs",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("document_id", sa.String(length=36), nullable=True),
        sa.Column("owner_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("outcome", sa.String(length=32), nullable=False),
        sa.Column("detail", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
    )
    op.create_index(op.f("ix_document_audit_logs_id"), "document_audit_logs", ["id"])
    op.create_index(op.f("ix_document_audit_logs_document_id"), "document_audit_logs", ["document_id"])
    op.create_index(op.f("ix_document_audit_logs_owner_id"), "document_audit_logs", ["owner_id"])
    op.create_index(op.f("ix_document_audit_logs_actor_user_id"), "document_audit_logs", ["actor_user_id"])
    op.create_index(op.f("ix_document_audit_logs_action"), "document_audit_logs", ["action"])

    op.add_column("service_requests", sa.Column("proof_document_id", sa.String(length=36), nullable=True))
    op.create_index(op.f("ix_service_requests_proof_document_id"), "service_requests", ["proof_document_id"])
    op.create_foreign_key(
        "fk_service_requests_proof_document_id",
        "service_requests",
        "document_records",
        ["proof_document_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_service_requests_proof_document_id", "service_requests", type_="foreignkey")
    op.drop_index(op.f("ix_service_requests_proof_document_id"), table_name="service_requests")
    op.drop_column("service_requests", "proof_document_id")

    op.drop_index(op.f("ix_document_audit_logs_action"), table_name="document_audit_logs")
    op.drop_index(op.f("ix_document_audit_logs_actor_user_id"), table_name="document_audit_logs")
    op.drop_index(op.f("ix_document_audit_logs_owner_id"), table_name="document_audit_logs")
    op.drop_index(op.f("ix_document_audit_logs_document_id"), table_name="document_audit_logs")
    op.drop_index(op.f("ix_document_audit_logs_id"), table_name="document_audit_logs")
    op.drop_table("document_audit_logs")

    op.drop_index(op.f("ix_document_records_document_type"), table_name="document_records")
    op.drop_index(op.f("ix_document_records_owner_id"), table_name="document_records")
    op.drop_index("idx_document_records_deleted_at", table_name="document_records")
    op.drop_index("idx_document_records_scan_status", table_name="document_records")
    op.drop_index("idx_document_records_owner_type", table_name="document_records")
    op.drop_table("document_records")

    bind = op.get_bind()
    SCAN_STATUS_ENUM.drop(bind, checkfirst=True)
