"""Shared pytest fixtures.

Integration tests run against a throwaway PostgreSQL database that is created
from the current models on demand, so no live or clone data is ever touched.
Pure unit tests never trigger the database setup.

The test process always owns the database configuration:

* ``DATABASE_URL`` is pointed at the dedicated test database *before* any
  application module is imported, so ``app.database`` (the authoritative
  engine/session factory used by the application) is the only bind the tests
  and the app can ever use;
* schema creation happens before the first TestClient/startup and is serialised
  with a PostgreSQL advisory lock, so two pytest processes cannot drop and
  recreate the schema underneath each other;
* every test starts with an empty schema and committed rows are truncated on
  teardown, in one statement that keeps foreign keys intact.
"""

import os
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

import psycopg2
import pytest
from dotenv import load_dotenv
from psycopg2 import errors as pg_errors
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from sqlalchemy import URL, text

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

TEST_DB_NAME = "rupaywala_test"

# Cluster-wide lock that serialises schema resets between concurrent pytest
# processes (for example two CI jobs sharing one PostgreSQL server).  The value
# is an arbitrary application key.
_SCHEMA_LOCK_KEY = 0x52505754  # "RPWT"


def _configured_dsn() -> str | None:
    """The server credentials configured for the application.

    ``load_dotenv`` does not override real environment variables, exactly like
    ``app.config``, so the same server (and credentials) is reused here without
    hardcoding a password.
    """
    load_dotenv(ROOT / ".env", override=False)
    return os.getenv("DATABASE_URL")


_CONFIGURED_DSN = _configured_dsn()


def _credentials() -> dict:
    """Reuse the configured server credentials without hardcoding a password."""
    raw = _CONFIGURED_DSN
    if not raw:
        return {"user": "postgres", "password": "postgres", "host": "localhost", "port": 5432}
    parts = urlsplit(raw)
    return {
        "user": unquote(parts.username or ""),
        "password": unquote(parts.password or ""),
        "host": parts.hostname,
        "port": parts.port or 5432,
    }


def _ensure_test_database() -> None:
    creds = _credentials()
    admin = psycopg2.connect(database="postgres", **creds)
    admin.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = admin.cursor()
    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (TEST_DB_NAME,))
    if cur.fetchone() is None:
        try:
            cur.execute(f'CREATE DATABASE "{TEST_DB_NAME}"')
        except pg_errors.DuplicateDatabase:
            # Another pytest process created it between our check and CREATE.
            pass
    cur.close()
    admin.close()


def _test_url() -> URL:
    """A URL object, so the percent-encoded password survives intact.

    str(URL) masks the password as "***", which silently breaks the connection.
    """
    creds = _credentials()
    return URL.create(
        "postgresql",
        username=creds["user"] or "postgres",
        password=creds["password"] or None,
        host=creds["host"],
        port=creds["port"] or 5432,
        database=TEST_DB_NAME,
    )


def _test_dsn() -> str:
    return _test_url().render_as_string(hide_password=False)


# Point the application at the test database before app.database / app.main are
# imported.  TESTING tells startup not to create tables or seed reference data:
# this fixture owns those steps and would otherwise race with them.
os.environ["DATABASE_URL"] = _test_dsn()
os.environ["TESTING"] = "1"

# Quotation signing is a dedicated cryptographic domain. The test process owns
# these values so the suite never depends on, and never writes to, .env.
# ``QUOTE_LEGACY_SIGNING_SECRET`` is only used by the version 1 compatibility
# tests; it is not a fallback.
os.environ["QUOTE_SIGNING_SECRET"] = "test-quote-signing-secret-stage5-1"
os.environ["QUOTE_LEGACY_SIGNING_SECRET"] = "test-quote-legacy-secret-stage5"

from app.database import Base, SessionLocal, engine, get_db  # noqa: E402
from app.main import app  # noqa: E402

assert engine.url.database == TEST_DB_NAME, (
    "Refusing to run tests: app.database.engine is not bound to the test "
    f"database (got {engine.url.database!r})"
)


# ---------------------------------------------------------------------------
# Global test-safety guards
# ---------------------------------------------------------------------------
_GOOGLE_STATE_MODULES = (
    "app.config",
    "app.services.map_service",
    "app.services.map_providers.base",
    "app.services.map_providers.google_maps",
)


@pytest.fixture(scope="session")
def _google_module_baseline():
    """Clean provider state captured before any test mutates it."""
    return {
        name: dict(sys.modules[name].__dict__)
        for name in _GOOGLE_STATE_MODULES
        if name in sys.modules
    }


@pytest.fixture(autouse=True)
def _restore_google_module_state(_google_module_baseline):
    """Undo in-place ``importlib.reload`` side effects after every test.

    Google provider tests set dummy API keys and reload shared modules in
    place.  ``monkeypatch`` restores the environment but not the module
    attributes assigned by the reload, which would otherwise make unrelated
    suites believe Google credentials are configured and reach the live API.
    """
    yield
    for name, state in _google_module_baseline.items():
        if name in sys.modules:
            module = sys.modules[name]
            module.__dict__.clear()
            module.__dict__.update(state)


@pytest.fixture(scope="session", autouse=True)
def _block_external_http():
    """Fail immediately if a test attempts a real outbound HTTP call."""
    import httpx

    original_request = httpx.AsyncClient.request

    def guarded_request(self, method, url, *args, **kwargs):
        host = urlsplit(str(url)).hostname or ""
        if host not in {"localhost", "127.0.0.1", "::1", "testserver"}:
            raise AssertionError(
                f"External HTTP call blocked during tests: {method} {url}"
            )
        return original_request(self, method, url, *args, **kwargs)

    httpx.AsyncClient.request = guarded_request  # type: ignore[assignment]
    try:
        yield
    finally:
        httpx.AsyncClient.request = original_request  # type: ignore[assignment]


def _assert_test_bind() -> None:
    """Hard guard: destructive schema work may only target the test database."""
    database = engine.url.database
    if database != TEST_DB_NAME:
        raise RuntimeError(
            "Refusing to reset a non-test database: "
            f"expected {TEST_DB_NAME!r}, got {database!r}"
        )


def _reset_schema() -> None:
    _assert_test_bind()
    with engine.begin() as conn:
        # DROP + CREATE (rather than CREATE IF NOT EXISTS) keeps the result
        # deterministic; the advisory lock makes this safe across processes.
        conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
        conn.execute(text("CREATE SCHEMA public"))
    Base.metadata.create_all(bind=engine)


def _drop_schema() -> None:
    _assert_test_bind()
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))


def _truncate_test_data() -> None:
    """Remove committed rows from every table, keeping foreign keys intact.

    TRUNCATE ... RESTART IDENTITY CASCADE resets the identity sequences and
    lets PostgreSQL handle dependent tables atomically, so no row can leak into
    the next test while referential integrity is preserved.
    """
    _assert_test_bind()
    tables = ", ".join(f'"{table.name}"' for table in Base.metadata.sorted_tables)
    if not tables:
        return
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE {tables} RESTART IDENTITY CASCADE"))


@pytest.fixture(scope="session")
def _database():
    _ensure_test_database()

    # Hold the advisory lock for the whole session.  A second pytest process
    # waits here instead of dropping the schema while this session is running.
    creds = _credentials()
    lock_conn = psycopg2.connect(database=TEST_DB_NAME, **creds)
    lock_conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    lock_cur = lock_conn.cursor()
    lock_cur.execute("SELECT pg_advisory_lock(%s)", (_SCHEMA_LOCK_KEY,))
    try:
        _reset_schema()
        yield
    finally:
        try:
            # Leave the database exactly as we found it: no public schema so the
            # next run starts from a clean, freshly created one.
            _drop_schema()
        finally:
            engine.dispose()
            lock_cur.close()
            lock_conn.close()


@pytest.fixture()
def db(_database):
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()
        _truncate_test_data()


@pytest.fixture()
def stub_distance(monkeypatch):
    """Deterministic road distance so request creation works without Mappls.

    Defaults to a short trip inside the pricing threshold, i.e. no extra charge.
    """

    def _install(km: float = 4.0, minutes: float = 12.0):
        class _Distance:
            distance_km = km
            duration_minutes = minutes

        def fake(fn, *args, **kwargs):
            return _Distance()

        monkeypatch.setattr("app.routes.service_routes._maps_guard", fake)
        return _Distance

    return _install


@pytest.fixture()
def client(db):
    from fastapi.testclient import TestClient

    def override_get_db():
        yield db

    # The schema is created by the _database fixture (through db) before this
    # fixture starts TestClient, whose startup hooks are disabled by TESTING.
    app.dependency_overrides[get_db] = override_get_db
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_db, None)
