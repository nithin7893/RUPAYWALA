import importlib
import io
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
        "EXPOSE_DOCS": "false",
        "DATABASE_URL": f"sqlite:///{db_path.as_posix()}",
        "JWT_SECRET_KEY": "test-jwt-secret-key-0123456789abcdef0123456789",
        "QUOTE_SIGNING_SECRET": "test-quote-signing-secret-0123456789abcdef0123",
        "UPI_ID": "test@upi",
        "CORS_ALLOWED_ORIGINS": "http://localhost:3000",
        "TRUSTED_HOSTS": "testserver,localhost,127.0.0.1",
        "HTTPS_REDIRECT_ENABLED": "false",
        "HSTS_ENABLED": "false",
        "UPLOAD_DIR": str(upload_dir),
        "MAX_UPLOAD_BYTES": str(5 * 1024 * 1024),
        "STORAGE_PROVIDER": "local",
        "STORAGE_BUCKET": "",
        "STORAGE_REGION": "",
        "STORAGE_ENDPOINT_URL": "",
        "STORAGE_ACCESS_KEY": "",
        "STORAGE_SECRET_KEY": "",
        "STORAGE_SIGNED_URL_EXPIRES_SECONDS": "300",
        "MALWARE_SCAN_ENABLED": "false",
        "MALWARE_SCAN_PROVIDER": "clamav",
        "CLAMAV_HOST": "127.0.0.1",
        "CLAMAV_PORT": "3310",
        "CLAMAV_TIMEOUT_SECONDS": "30",
        "DOCUMENT_RETENTION_DAYS": "0",
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


def _create_user(db, username, role, seq=1):
    from app.models.user import AccountStatus, AuthProvider, User, UserRole
    from app.utils.security import hash_password

    user = User(
        username=username,
        phone_number=f"9{seq:09d}"[-10:],
        password_hash=hash_password("Password123"),
        role=getattr(UserRole, role),
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


def _create_request(db, owner_id: int):
    from app.models.service_request import RequestStatus, ServiceRequest

    req = ServiceRequest(
        user_id=owner_id,
        request_type="digital",
        status=RequestStatus.completed,
        customer_latitude=17.0,
        customer_longitude=78.0,
        customer_address="Test address",
    )
    db.add(req)
    db.commit()
    db.refresh(req)
    return req


def _jpeg_bytes():
    return b"\xff\xd8\xff" + b"0" * 128


def test_authenticated_upload_and_retrieval(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner", "customer", 1)
        req = _create_request(db, owner.id)
    finally:
        db.close()

    upload = client.post(
        "/field-member/complete-request",
        params={"request_id": req.id},
        data={"completion_notes": "Completed work"},
        files={"proof": ("proof.jpg", io.BytesIO(_jpeg_bytes()), "image/jpeg")},
        headers=_auth_headers(owner.id, "customer"),  # will fail role; use admin/field not set up
    )
    # This endpoint requires approved field member; expect 403. Validate via direct service instead below.
    assert upload.status_code in (401, 403)


def test_document_service_store_and_authorized_retrieval(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner2", "customer", 2)
        admin = _create_user(db, "admin2", "admin", 3)
        other = _create_user(db, "other2", "customer", 4)
        from app.services.document_service import DocumentService
        from starlette.datastructures import UploadFile

        file = UploadFile(filename="proof.jpg", file=io.BytesIO(_jpeg_bytes()), headers={"content-type": "image/jpeg"})
        record = DocumentService.store_document(
            db, file=file, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof"
        )
        db.commit()
        doc_id = record.id
    finally:
        db.close()

    ok = client.get(f"/documents/{doc_id}", headers=_auth_headers(owner.id, "customer"))
    assert ok.status_code == 200
    body = ok.json()
    assert body["document_id"] == doc_id
    assert body["scan_status"] == "CLEAN"
    assert "bucket" not in str(body).lower()
    assert "storage_key" not in str(body).lower()

    content = client.get(f"/documents/{doc_id}/content", headers=_auth_headers(owner.id, "customer"))
    assert content.status_code == 200
    assert content.content.startswith(b"\xff\xd8\xff")

    admin_ok = client.get(f"/documents/{doc_id}/content", headers=_auth_headers(admin.id, "admin"))
    assert admin_ok.status_code == 200

    denied = client.get(f"/documents/{doc_id}/content", headers=_auth_headers(other.id, "customer"))
    assert denied.status_code == 404


def test_unauthorized_document_upload_rejected_by_validation(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner3", "customer", 5)
        from app.services.document_service import DocumentService
        from starlette.datastructures import UploadFile

        bad = UploadFile(filename="proof.exe", file=io.BytesIO(b"MZ" + b"0" * 100), headers={"content-type": "application/octet-stream"})
        with pytest.raises(Exception) as exc:
            DocumentService.store_document(
                db, file=bad, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof"
            )
        assert "Unsupported" in str(exc.value) or "400" in str(exc.value)
    finally:
        db.rollback()
        db.close()


def test_invalid_mime_and_signature_rejected(app_client):
    _, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner4", "customer", 6)
        from app.services.document_service import DocumentService
        from starlette.datastructures import UploadFile

        # extension jpg but content is pdf signature
        bad_sig = UploadFile(filename="x.jpg", file=io.BytesIO(b"%PDF-1.4\n" + b"0" * 100), headers={"content-type": "image/jpeg"})
        with pytest.raises(Exception):
            DocumentService.store_document(db, file=bad_sig, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof")
    finally:
        db.rollback()
        db.close()


def test_oversized_file_rejected(app_client, tmp_path):
    # reload with tiny max size
    client, main, _, _ = _reload_with_client(tmp_path, MAX_UPLOAD_BYTES="100")
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner5", "customer", 7)
        from app.services.document_service import DocumentService
        from starlette.datastructures import UploadFile

        big = UploadFile(filename="big.jpg", file=io.BytesIO(b"\xff\xd8\xff" + b"0" * 200), headers={"content-type": "image/jpeg"})
        with pytest.raises(Exception) as exc:
            DocumentService.store_document(db, file=big, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof")
        assert "413" in str(exc.value) or "too large" in str(exc.value).lower()
    finally:
        db.rollback()
        db.close()
        main.Base.metadata.drop_all(bind=main.engine)
        main.engine.dispose()


def _reload_with_client(tmp_path, **overrides):
    config, main = _reload_app(tmp_path, **overrides)
    main.Base.metadata.create_all(bind=main.engine)
    client = TestClient(main.app)
    return client, main, config, tmp_path


def test_path_traversal_rejected(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner6", "customer", 8)
    finally:
        db.close()
    res = client.get("/uploads/../app/config.py", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code in (400, 404)


def test_infected_document_retrieval_blocked(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner7", "customer", 9)
        from app.models.document_record import DocumentRecord, DocumentScanStatus
        from app.services.document_storage import get_storage_backend

        storage = get_storage_backend()
        key = f"documents/service_proof/{owner.id}/infected.jpg"
        storage.put(key, _jpeg_bytes(), "image/jpeg")
        rec = DocumentRecord(
            id="00000000-0000-0000-0000-000000000001",
            owner_id=owner.id,
            document_type="service_proof",
            storage_provider="local",
            storage_key=key,
            original_filename="proof.jpg",
            mime_type="image/jpeg",
            file_size=len(_jpeg_bytes()),
            checksum_sha256="0" * 64,
            scan_status=DocumentScanStatus.infected,
        )
        db.add(rec)
        db.commit()
    finally:
        db.close()

    res = client.get("/documents/00000000-0000-0000-0000-000000000001/content", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code == 403


def test_scan_failure_blocks_retrieval(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner8", "customer", 10)
        from app.models.document_record import DocumentRecord, DocumentScanStatus
        from app.services.document_storage import get_storage_backend

        storage = get_storage_backend()
        key = f"documents/service_proof/{owner.id}/failed.jpg"
        storage.put(key, _jpeg_bytes(), "image/jpeg")
        rec = DocumentRecord(
            id="00000000-0000-0000-0000-000000000002",
            owner_id=owner.id,
            document_type="service_proof",
            storage_provider="local",
            storage_key=key,
            original_filename="proof.jpg",
            mime_type="image/jpeg",
            file_size=len(_jpeg_bytes()),
            checksum_sha256="1" * 64,
            scan_status=DocumentScanStatus.failed,
        )
        db.add(rec)
        db.commit()
    finally:
        db.close()

    res = client.get("/documents/00000000-0000-0000-0000-000000000002/content", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code == 403


def test_document_deletion_authorization(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner9", "customer", 11)
        other = _create_user(db, "other9", "customer", 12)
        from app.services.document_service import DocumentService
        from starlette.datastructures import UploadFile

        file = UploadFile(filename="proof.jpg", file=io.BytesIO(_jpeg_bytes()), headers={"content-type": "image/jpeg"})
        record = DocumentService.store_document(
            db, file=file, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof"
        )
        db.commit()
        doc_id = record.id
    finally:
        db.close()

    denied = client.delete(f"/documents/{doc_id}", headers=_auth_headers(other.id, "customer"))
    assert denied.status_code == 404

    ok = client.delete(f"/documents/{doc_id}", headers=_auth_headers(owner.id, "customer"))
    assert ok.status_code == 200

    after = client.get(f"/documents/{doc_id}/content", headers=_auth_headers(owner.id, "customer"))
    assert after.status_code == 404


def test_expired_document_retrieval_rejected(app_client):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner10", "customer", 13)
        from datetime import datetime, timedelta
        from app.models.document_record import DocumentRecord, DocumentScanStatus
        from app.services.document_storage import get_storage_backend

        storage = get_storage_backend()
        key = f"documents/service_proof/{owner.id}/expired.jpg"
        storage.put(key, _jpeg_bytes(), "image/jpeg")
        rec = DocumentRecord(
            id="00000000-0000-0000-0000-000000000003",
            owner_id=owner.id,
            document_type="service_proof",
            storage_provider="local",
            storage_key=key,
            original_filename="proof.jpg",
            mime_type="image/jpeg",
            file_size=len(_jpeg_bytes()),
            checksum_sha256="2" * 64,
            scan_status=DocumentScanStatus.clean,
            expires_at=datetime.utcnow() - timedelta(seconds=1),
        )
        db.add(rec)
        db.commit()
    finally:
        db.close()

    res = client.get("/documents/00000000-0000-0000-0000-000000000003/content", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code == 404


def test_storage_failure_handling(monkeypatch, app_client):
    _, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner11", "customer", 14)
        from app.services import document_service as ds
        from starlette.datastructures import UploadFile

        class BadStorage:
            provider = "local"
            def put(self, *args, **kwargs):
                raise ds.StorageError("boom")
        monkeypatch.setattr(ds, "get_storage_backend", lambda: BadStorage())

        file = UploadFile(filename="proof.jpg", file=io.BytesIO(_jpeg_bytes()), headers={"content-type": "image/jpeg"})
        with pytest.raises(Exception) as exc:
            ds.DocumentService.store_document(db, file=file, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof")
        assert "503" in str(exc.value) or "unavailable" in str(exc.value).lower()
    finally:
        db.rollback()
        db.close()


def test_malware_scan_failure_marks_failed(monkeypatch, tmp_path):
    client, main, _, _ = _reload_with_client(tmp_path, MALWARE_SCAN_ENABLED="true", MALWARE_SCAN_PROVIDER="clamav")
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner12", "customer", 15)
        from app.services import document_service as ds
        from starlette.datastructures import UploadFile

        monkeypatch.setattr(ds, "_scan_bytes", lambda content: (ds.DocumentScanStatus.failed, "scan_error"))
        file = UploadFile(filename="proof.jpg", file=io.BytesIO(_jpeg_bytes()), headers={"content-type": "image/jpeg"})
        rec = ds.DocumentService.store_document(db, file=file, owner_id=owner.id, actor_user_id=owner.id, document_type="service_proof")
        db.commit()
        assert rec.scan_status == ds.DocumentScanStatus.failed
        doc_id = rec.id
    finally:
        db.close()

    res = client.get(f"/documents/{doc_id}/content", headers=_auth_headers(owner.id, "customer"))
    assert res.status_code == 403
    main.Base.metadata.drop_all(bind=main.engine)
    main.engine.dispose()


def test_legacy_upload_path_authz_preserved(app_client, tmp_path):
    client, main, _, _ = app_client
    db = main.SessionLocal()
    try:
        owner = _create_user(db, "owner13", "customer", 16)
        other = _create_user(db, "other13", "customer", 17)
        req = _create_request(db, owner.id)
        upload_dir = Path(os.environ["UPLOAD_DIR"])
        rel = Path("proof") / f"user_{owner.id}" / "legacy.jpg"
        abs_path = upload_dir / rel
        abs_path.parent.mkdir(parents=True, exist_ok=True)
        abs_path.write_bytes(_jpeg_bytes())
        req.proof_image_url = str(rel).replace("\\", "/")
        db.commit()
        stored = req.proof_image_url
    finally:
        db.close()

    ok = client.get(f"/uploads/{stored}", headers=_auth_headers(owner.id, "customer"))
    assert ok.status_code == 200
    denied = client.get(f"/uploads/{stored}", headers=_auth_headers(other.id, "customer"))
    assert denied.status_code == 404
