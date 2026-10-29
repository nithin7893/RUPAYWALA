"""Shared pytest fixtures.

Integration tests run against a throwaway PostgreSQL database that is created
from the current models on demand, so no live or clone data is ever touched.
Pure unit tests never trigger the database setup.
"""

import os
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit, urlunsplit

import psycopg2
import pytest
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from sqlalchemy import URL, create_engine, text
from sqlalchemy.orm import sessionmaker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

TEST_DB_NAME = "rupaywala_test"


def _credentials() -> dict:
    """Reuse the configured server credentials without hardcoding a password."""
    raw = None
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("DATABASE_URL"):
            raw = line.split("=", 1)[1].strip().strip('"').strip("'")
            break
    if raw is None:
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
        cur.execute(f'CREATE DATABASE "{TEST_DB_NAME}"')
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


os.environ["DATABASE_URL"] = _test_dsn()

from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402

engine = create_engine(_test_url(), poolclass=None)
TestingSessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def _reset_schema() -> None:
    with engine.begin() as conn:
        # IF EXISTS / IF NOT EXISTS because an earlier run may have torn the
        # schema down already.
        conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS public"))
    Base.metadata.create_all(bind=engine)


@pytest.fixture(scope="session")
def _database():
    _ensure_test_database()
    _reset_schema()
    yield
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA public CASCADE"))


@pytest.fixture()
def db(_database):
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


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

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
