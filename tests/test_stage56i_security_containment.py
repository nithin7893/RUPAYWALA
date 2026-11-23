import importlib
import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _set_base_env(tmp_path: Path, **overrides):
    db_path = tmp_path / "test.db"
    upload_dir = tmp_path / "uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)
    env = {
        "ENVIRONMENT": "development",
        "DEBUG": "false",
        "TESTING": "1",
        "EXPOSE_DOCS": "true",
        "DATABASE_URL": f"sqlite:///{db_path.as_posix()}",
        "JWT_SECRET_KEY": "test-jwt-secret-key-0123456789abcdef0123456789",
        "QUOTE_SIGNING_SECRET": "test-quote-signing-secret-0123456789abcdef0123",
        "UPI_ID": "test@upi",
        "CORS_ALLOWED_ORIGINS": "http://localhost:3000",
        "TRUSTED_HOSTS": "testserver,localhost,127.0.0.1",
        "HTTPS_REDIRECT_ENABLED": "false",
        "HSTS_ENABLED": "false",
        "UPLOAD_DIR": str(upload_dir),
    }
    env.update(overrides)
    for k, v in env.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = str(v)
    return upload_dir


def _reload_app(tmp_path: Path, **env_overrides):
    _set_base_env(tmp_path, **env_overrides)
    # Clear cached app modules so config is re-read.
    for mod in list(sys.modules.keys()):
        if mod == "app" or mod.startswith("app."):
            sys.modules.pop(mod, None)
    config = importlib.import_module("app.config")
    importlib.import_module("app.database")
    main = importlib.import_module("app.main")
    return config, main


@pytest.fixture(autouse=True)
def _restore_app_modules():
    """Keep config reloads local to one test.

    These tests deliberately purge ``app.*`` from ``sys.modules`` and re-import
    the application with different environment variables.  Without restoration
    the reloaded modules (including their enum classes) leak into the shared
    PostgreSQL suite, so patches and fixtures silently target different module
    objects.  Restore the exact captured objects; never re-import them.
    """
    saved_modules = {
        name: module
        for name, module in sys.modules.items()
        if name == "app" or name.startswith("app.")
    }
    saved_env = os.environ.copy()
    yield
    for name in list(sys.modules):
        if name == "app" or name.startswith("app."):
            if name not in saved_modules:
                sys.modules.pop(name, None)
    sys.modules.update(saved_modules)
    current_env = os.environ.copy()
    for key in set(saved_env) | set(current_env):
        if key not in saved_env:
            os.environ.pop(key, None)
        elif current_env.get(key) != saved_env[key]:
            os.environ[key] = saved_env[key]


@pytest.fixture()
def app_client(tmp_path):
    config, main = _reload_app(tmp_path)
    main.Base.metadata.create_all(bind=main.engine)
    with TestClient(main.app) as client:
        yield client, main, config, tmp_path
    main.Base.metadata.drop_all(bind=main.engine)
    main.engine.dispose()


def _create_user(db, username, role, user_id=None):
    from app.models.user import User, UserRole, AccountStatus, AuthProvider
    from app.utils.security import hash_password

    role_enum = getattr(UserRole, role)
    user = User(
        username=username,
        phone_number=f"900000{user_id or 1:04d}",
        password_hash=hash_password("Password123"),
        role=role_enum,
        is_verified=True,
        phone_verified=True,
        auth_provider=AuthProvider.phone_otp,
        account_status=AccountStatus.active,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _auth_headers(user_id: int, role: str):
    from app.utils.jwt_handler import create_access_token

    token = create_access_token({"user_id": user_id, "role": role, "tv": 0})
    return {"Authorization": f"Bearer {token}"}


def _create_request_with_proof(main, owner, upload_dir: Path):
    from app.models.service_request import ServiceRequest, RequestStatus

    rel = Path("proof") / f"user_{owner.id}" / "test.jpg"
    abs_path = upload_dir / rel
    abs_path.parent.mkdir(parents=True, exist_ok=True)
    abs_path.write_bytes(b"\xff\xd8\xff" + b"0" * 64)
    db = main.SessionLocal()
    try:
        req = ServiceRequest(
            user_id=owner.id,
            request_type="digital",
            status=RequestStatus.completed,
            proof_image_url=str(rel).replace("\\", "/"),
            customer_latitude=17.0,
            customer_longitude=78.0,
            customer_address="Test address",
        )
        db.add(req)
        db.commit()
        db.refresh(req)
        return req
    finally:
        db.close()


def test_unauthenticated_document_denied(app_client):
    client, main, _, tmp_path = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner1", "customer", 1)
    finally:
        db.close()
    upload_dir = Path(os.environ["UPLOAD_DIR"])
    req = _create_request_with_proof(main, owner, upload_dir)
    res = client.get(f"/uploads/{req.proof_image_url}")
    assert res.status_code == 401


def test_authorized_owner_document_retrieval(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner2", "customer", 2)
    finally:
        db.close()
    upload_dir = Path(os.environ["UPLOAD_DIR"])
    req = _create_request_with_proof(main, owner, upload_dir)
    res = client.get(f"/uploads/{req.proof_image_url}", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code == 200
    assert res.content.startswith(b"\xff\xd8\xff")


def test_cross_user_document_access_denied(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner3", "customer", 3)
        other = _create_user(db, "other3", "customer", 4)
    finally:
        db.close()
    upload_dir = Path(os.environ["UPLOAD_DIR"])
    req = _create_request_with_proof(main, owner, upload_dir)
    res = client.get(f"/uploads/{req.proof_image_url}", headers=_auth_headers(other.id, "customer"))
    assert res.status_code == 404


def test_path_traversal_denied(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner4", "customer", 5)
    finally:
        db.close()
    res = client.get("/uploads/../app/config.py", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code in (400, 404)


def test_admin_can_access_document(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner5", "customer", 6)
        admin = _create_user(db, "admin5", "admin", 7)
    finally:
        db.close()
    upload_dir = Path(os.environ["UPLOAD_DIR"])
    req = _create_request_with_proof(main, owner, upload_dir)
    res = client.get(f"/uploads/{req.proof_image_url}", headers=_auth_headers(admin.id, "admin"))
    assert res.status_code == 200


def test_production_docs_disabled(tmp_path):
    # Production config requires safe secrets and explicit CORS/trusted hosts.
    safe_secret = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2"
    _, main = _reload_app(
        tmp_path,
        ENVIRONMENT="production",
        DEBUG="false",
        TESTING="0",
        EXPOSE_DOCS="false",
        JWT_SECRET_KEY=safe_secret,
        QUOTE_SIGNING_SECRET=safe_secret,
        CORS_ALLOWED_ORIGINS="https://app.example.com",
        TRUSTED_HOSTS="api.example.com,testserver",
        HTTPS_REDIRECT_ENABLED="false",
        HSTS_ENABLED="false",
    )
    main.Base.metadata.create_all(bind=main.engine)
    with TestClient(main.app) as client:
        assert client.get("/docs").status_code == 404
        assert client.get("/redoc").status_code == 404
        assert client.get("/openapi.json").status_code == 404
    main.Base.metadata.drop_all(bind=main.engine)
    main.engine.dispose()


def test_development_docs_configurable(tmp_path):
    _, main = _reload_app(tmp_path, ENVIRONMENT="development", EXPOSE_DOCS="true")
    with TestClient(main.app) as client:
        assert client.get("/docs").status_code == 200


def test_cors_allowlist_behavior(tmp_path):
    _, main = _reload_app(
        tmp_path,
        CORS_ALLOWED_ORIGINS="https://allowed.example.com",
        TRUSTED_HOSTS="testserver",
    )
    with TestClient(main.app) as client:
        ok = client.get("/health", headers={"Origin": "https://allowed.example.com"})
        bad = client.get("/health", headers={"Origin": "https://evil.example.com"})
        assert ok.headers.get("access-control-allow-origin") == "https://allowed.example.com"
        assert bad.headers.get("access-control-allow-origin") is None


def test_unsafe_wildcard_cors_rejected(tmp_path):
    safe_secret = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2"
    with pytest.raises(RuntimeError):
        _reload_app(
            tmp_path,
            ENVIRONMENT="production",
            DEBUG="false",
            TESTING="0",
            EXPOSE_DOCS="false",
            JWT_SECRET_KEY=safe_secret,
            QUOTE_SIGNING_SECRET=safe_secret,
            CORS_ALLOWED_ORIGINS="*",
            TRUSTED_HOSTS="api.example.com",
            HTTPS_REDIRECT_ENABLED="false",
            HSTS_ENABLED="false",
        )


def test_trusted_host_behavior(tmp_path):
    _, main = _reload_app(tmp_path, TRUSTED_HOSTS="allowed.test")
    with TestClient(main.app) as client:
        denied = client.get("/health", headers={"Host": "evil.test"})
        assert denied.status_code == 400


def test_security_headers_present(app_client):
    client, _, _, _ = app_client
    res = client.get("/health")
    assert res.headers.get("X-Content-Type-Options") == "nosniff"
    assert res.headers.get("Referrer-Policy") == "no-referrer"
    assert "Content-Security-Policy" in res.headers


def test_missing_production_secrets_rejected(tmp_path):
    with pytest.raises(Exception):
        _reload_app(
            tmp_path,
            ENVIRONMENT="production",
            JWT_SECRET_KEY="short",
            QUOTE_SIGNING_SECRET="short",
            CORS_ALLOWED_ORIGINS="https://app.example.com",
            TRUSTED_HOSTS="api.example.com",
        )


def test_unsafe_production_config_rejected(tmp_path):
    safe_secret = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2"
    with pytest.raises(RuntimeError) as exc:
        _reload_app(
            tmp_path,
            ENVIRONMENT="production",
            DEBUG="false",
            TESTING="0",
            EXPOSE_DOCS="false",
            JWT_SECRET_KEY=safe_secret,
            QUOTE_SIGNING_SECRET=safe_secret,
            CORS_ALLOWED_ORIGINS="",
            TRUSTED_HOSTS="",
            HTTPS_REDIRECT_ENABLED="false",
            HSTS_ENABLED="false",
        )
    msg = str(exc.value)
    assert "CORS_ALLOWED_ORIGINS" in msg
    assert "TRUSTED_HOSTS" in msg
    assert safe_secret not in msg


def test_secret_values_not_in_validation_errors(tmp_path):
    secret = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2"
    with pytest.raises(RuntimeError) as exc:
        _reload_app(
            tmp_path,
            ENVIRONMENT="production",
            DEBUG="true",
            TESTING="0",
            EXPOSE_DOCS="false",
            JWT_SECRET_KEY=secret,
            QUOTE_SIGNING_SECRET=secret,
            CORS_ALLOWED_ORIGINS="https://app.example.com",
            TRUSTED_HOSTS="api.example.com",
            HTTPS_REDIRECT_ENABLED="false",
            HSTS_ENABLED="false",
        )
    assert secret not in str(exc.value)
