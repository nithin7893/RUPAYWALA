"""Private document storage abstraction.

Local storage is kept for controlled development/migration. Object storage
credentials are backend-only and never exposed to clients.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from app.config import (
    STORAGE_ACCESS_KEY,
    STORAGE_BUCKET,
    STORAGE_ENDPOINT_URL,
    STORAGE_PROVIDER,
    STORAGE_REGION,
    STORAGE_SECRET_KEY,
    STORAGE_SIGNED_URL_EXPIRES_SECONDS,
    STORAGE_USE_SSL,
    UPLOAD_DIR,
)

logger = logging.getLogger(__name__)


class StorageError(RuntimeError):
    pass


class StorageNotFoundError(StorageError):
    pass


@dataclass
class StoredObject:
    key: str
    content_type: str | None = None


class StorageBackend(Protocol):
    provider: str

    def put(self, key: str, content: bytes, content_type: str) -> None: ...

    def get(self, key: str) -> bytes: ...

    def delete(self, key: str) -> None: ...

    def exists(self, key: str) -> bool: ...

    def signed_url(self, key: str, expires_seconds: int, download_name: str | None = None) -> str | None: ...


def _normalize_key(key: str) -> str:
    normalized = (key or "").replace("\\", "/").lstrip("/")
    if not normalized or any(part in {"", ".", ".."} for part in normalized.split("/")):
        raise StorageError("Invalid storage key")
    return normalized


class LocalStorageBackend:
    provider = "local"

    def __init__(self, root: str | Path | None = None):
        self.root = Path(root or UPLOAD_DIR).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        normalized = _normalize_key(key)
        candidate = (self.root / normalized).resolve()
        try:
            candidate.relative_to(self.root)
        except ValueError as exc:
            raise StorageError("Invalid storage key") from exc
        return candidate

    def put(self, key: str, content: bytes, content_type: str) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def get(self, key: str) -> bytes:
        path = self._path(key)
        if not path.is_file():
            raise StorageNotFoundError("Object not found")
        return path.read_bytes()

    def delete(self, key: str) -> None:
        path = self._path(key)
        try:
            path.unlink()
        except FileNotFoundError:
            return

    def exists(self, key: str) -> bool:
        return self._path(key).is_file()

    def signed_url(self, key: str, expires_seconds: int, download_name: str | None = None) -> str | None:
        # Local dev/migration uses authenticated backend streaming.
        return None


class S3StorageBackend:
    provider = "s3"

    def __init__(self):
        if not STORAGE_BUCKET:
            raise StorageError("STORAGE_BUCKET is required for s3 storage")
        try:
            import boto3  # type: ignore
            from botocore.config import Config  # type: ignore
        except Exception as exc:  # pragma: no cover - depends on optional dep
            raise StorageError(
                "S3 storage requires boto3 to be installed"
            ) from exc

        config = Config(signature_version="s3v4", s3={"addressing_style": "virtual"})
        session = boto3.session.Session(
            aws_access_key_id=STORAGE_ACCESS_KEY or None,
            aws_secret_access_key=STORAGE_SECRET_KEY or None,
            region_name=STORAGE_REGION or None,
        )
        self.bucket = STORAGE_BUCKET
        self.client = session.client(
            "s3",
            endpoint_url=STORAGE_ENDPOINT_URL or None,
            use_ssl=STORAGE_USE_SSL,
            config=config,
        )

    def put(self, key: str, content: bytes, content_type: str) -> None:
        key = _normalize_key(key)
        self.client.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=content,
            ContentType=content_type or "application/octet-stream",
        )

    def get(self, key: str) -> bytes:
        key = _normalize_key(key)
        try:
            obj = self.client.get_object(Bucket=self.bucket, Key=key)
        except Exception as exc:
            # Avoid leaking provider internals; callers map to 404/503 as needed.
            code = getattr(getattr(exc, "response", {}), "get", lambda *_: None)("Error", {})
            if isinstance(code, dict) and code.get("Code") in {"NoSuchKey", "404", "NotFound"}:
                raise StorageNotFoundError("Object not found") from exc
            raise StorageError("Storage retrieval failed") from exc
        body = obj.get("Body")
        if body is None:
            raise StorageNotFoundError("Object not found")
        return body.read()

    def delete(self, key: str) -> None:
        key = _normalize_key(key)
        try:
            self.client.delete_object(Bucket=self.bucket, Key=key)
        except Exception as exc:
            raise StorageError("Storage deletion failed") from exc

    def exists(self, key: str) -> bool:
        key = _normalize_key(key)
        try:
            self.client.head_object(Bucket=self.bucket, Key=key)
            return True
        except Exception:
            return False

    def signed_url(self, key: str, expires_seconds: int, download_name: str | None = None) -> str | None:
        key = _normalize_key(key)
        params = {"Bucket": self.bucket, "Key": key}
        if download_name:
            # Content-Disposition attachment; filename sanitized by caller.
            params["ResponseContentDisposition"] = f'inline; filename="{download_name}"'
        try:
            return self.client.generate_presigned_url(
                "get_object",
                Params=params,
                ExpiresIn=max(1, int(expires_seconds)),
            )
        except Exception as exc:
            raise StorageError("Could not generate signed URL") from exc


def get_storage_backend() -> StorageBackend:
    provider = (STORAGE_PROVIDER or "local").strip().lower()
    if provider == "local":
        return LocalStorageBackend()
    if provider == "s3":
        return S3StorageBackend()
    raise StorageError(f"Unsupported STORAGE_PROVIDER: {provider}")


def default_signed_url_ttl() -> int:
    return max(1, int(STORAGE_SIGNED_URL_EXPIRES_SECONDS or 300))
