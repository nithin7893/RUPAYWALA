"""Alembic environment.

The database URL always comes from ``app.config`` (which reads ``.env``) so
there is exactly one place the connection is configured. Metadata is imported
from ``app.models`` to guarantee migrations see the same tables the app does.
"""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine, pool

from app.config import DATABASE_URL
from app.database import Base

# Importing the models registers every table on Base.metadata.
import app.models.branch  # noqa: F401
import app.models.customer_profile  # noqa: F401
import app.models.distance_rate_config  # noqa: F401
import app.models.document_audit_log  # noqa: F401
import app.models.document_record  # noqa: F401
import app.models.family_member  # noqa: F401
import app.models.field_member  # noqa: F401
import app.models.notification  # noqa: F401
import app.models.otp_verification  # noqa: F401
import app.models.payment  # noqa: F401
import app.models.policy  # noqa: F401
import app.models.policy_member  # noqa: F401
import app.models.request_assignment  # noqa: F401
import app.models.service_quote  # noqa: F401
import app.models.service_request  # noqa: F401
import app.models.service_type  # noqa: F401
import app.models.subscription_plan  # noqa: F401
import app.models.subscription_family_member  # noqa: F401
import app.models.user  # noqa: F401
import app.models.user_subscription  # noqa: F401
import app.models.visit_ledger  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _configure(connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
        compare_server_default=True,
        # Required for PostgreSQL enum changes and for SQLite in tests.
        render_as_batch=connection.dialect.name == "sqlite",
        # Commit each revision on its own. PostgreSQL will not let a label added
        # by ALTER TYPE ... ADD VALUE be used until the transaction that added it
        # has committed, which 0002_expand_enums depends on.
        transaction_per_migration=True,
    )


def run_migrations_offline() -> None:
    """Emit SQL to stdout instead of running it (alembic upgrade head --sql)."""
    context.configure(
        url=DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    # The URL is taken straight from app.config. It is deliberately NOT written
    # into alembic.ini: a password containing '%' would break configparser's
    # interpolation, and the connection is configured in exactly one place.
    connectable = create_engine(DATABASE_URL, poolclass=pool.NullPool)
    with connectable.connect() as connection:
        _configure(connection)
        with context.begin_transaction():
            context.run_migrations()
    connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
