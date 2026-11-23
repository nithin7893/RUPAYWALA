from __future__ import annotations

import hashlib
import logging
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.config import (
    ALLOWED_DOCUMENT_MIME_TYPES,
    ALLOWED_PROOF_EXTENSIONS,
    CLAMAV_HOST,
    CLAMAV_PORT,
    CLAMAV_TIMEOUT_SECONDS,
    DOCUMENT_RETENTION_DAYS,
    MALWARE_SCAN_ENABLED,
    MALWARE_SCAN_PROVIDER,
    MAX_UPLOAD_BYTES,
    STORAGE_BUCKET,
    STORAGE_PROVIDER,
)
from app.models.document_audit_log import DocumentAuditLog
from app.models.document_record import DocumentRecord, DocumentScanStatus
from app.models.field_member import FieldMember
from app.models.request_assignment import RequestAssignment
from app.models.service_request import ServiceRequest
from app.models.user import User, UserRole
from app.services.document_storage import (
    StorageError,
    StorageNotFoundError,
    default_signed_url_ttl,
    get_storage_backend,
)

logger = logging.getLogger(__name__)

_SAFE_FILENAME = re.compile(r"[^A-Za-z0-9._-]")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _sanitize_filename(name: str | None) -> str | None:
    if not name:
        return None
    base = os.path.basename(name).replace("\x00", "").strip()
    base = _SAFE_FILENAME.sub("_", base).strip("._")
    if not base:
        return None
    return base[:255]


def _detect_mime(content: bytes) -> str | None:
    if content.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(content) >= 12 and content.startswith(b"RIFF") and content[8:12] == b"WEBP":
        return "image/webp"
    if content.startswith(b"%PDF-"):
        return "application/pdf"
    return None


def _extension_for_mime(mime: str) -> str | None:
    for ext, allowed_mime in ALLOWED_DOCUMENT_MIME_TYPES.items():
        if allowed_mime == mime:
            # Prefer .jpg over .jpeg for canonicalization
            if mime == "image/jpeg":
                return ".jpg"
            return ext
    return None


def _scan_bytes(content: bytes) -> tuple[DocumentScanStatus, str | None]:
    if not MALWARE_SCAN_ENABLED:
        return DocumentScanStatus.clean, "scan_disabled"
    provider = (MALWARE_SCAN_PROVIDER or "clamav").strip().lower()
    if provider != "clamav":
        logger.warning("Unsupported malware scan provider configured")
        return DocumentScanStatus.failed, "unsupported_provider"
    try:
        import clamd  # type: ignore
    except Exception:
        logger.error("Malware scanning enabled but clamd dependency unavailable")
        return DocumentScanStatus.failed, "scanner_unavailable"

    try:
        client = clamd.ClamdNetworkSocket(
            host=CLAMAV_HOST,
            port=int(CLAMAV_PORT),
            timeout=int(CLAMAV_TIMEOUT_SECONDS),
        )
        result = client.instream(content)
        # clamd returns {'stream': ('OK', None)} or ('FOUND', 'Sig')
        status_tuple = result.get("stream") if isinstance(result, dict) else None
        if not status_tuple or not isinstance(status_tuple, tuple):
            return DocumentScanStatus.failed, "invalid_scan_result"
        verdict = str(status_tuple[0]).upper()
        if verdict == "OK":
            return DocumentScanStatus.clean, None
        if verdict == "FOUND":
            return DocumentScanStatus.infected, "signature_match"
        return DocumentScanStatus.failed, "scan_error"
    except Exception:
        logger.exception("Malware scan failed")
        return DocumentScanStatus.failed, "scan_error"


def record_audit(
    db: Session,
    *,
    action: str,
    outcome: str,
    document_id: str | None = None,
    owner_id: int | None = None,
    actor_user_id: int | None = None,
    detail: str | None = None,
) -> None:
    detail_safe = (detail or "")[:255] or None
    db.add(
        DocumentAuditLog(
            document_id=document_id,
            owner_id=owner_id,
            actor_user_id=actor_user_id,
            action=action[:64],
            outcome=outcome[:32],
            detail=detail_safe,
        )
    )
    logger.info(
        "document_audit action=%s outcome=%s document_id=%s owner_id=%s actor_user_id=%s",
        action,
        outcome,
        document_id,
        owner_id,
        actor_user_id,
    )


class DocumentService:
    @staticmethod
    def validate_and_read_upload(file: UploadFile) -> tuple[bytes, str, str | None]:
        original_name = _sanitize_filename(file.filename)
        ext = os.path.splitext(original_name or file.filename or "")[1].lower()
        if ext not in ALLOWED_PROOF_EXTENSIONS:
            record_detail = "unsupported_extension"
            raise HTTPException(
                status_code=400,
                detail=(
                    "Unsupported file type. Allowed types: "
                    + ", ".join(ALLOWED_PROOF_EXTENSIONS)
                ),
            )

        content = file.file.read(MAX_UPLOAD_BYTES + 1)
        if len(content) > MAX_UPLOAD_BYTES:
            raise HTTPException(
                status_code=413,
                detail=f"File is too large. Maximum size is {MAX_UPLOAD_BYTES // (1024 * 1024)} MB",
            )
        if not content:
            raise HTTPException(status_code=400, detail="Uploaded file is empty")

        detected_mime = _detect_mime(content)
        if not detected_mime:
            raise HTTPException(status_code=400, detail="File content type is not allowed")
        expected_mime = ALLOWED_DOCUMENT_MIME_TYPES.get(ext)
        # Accept jpg/jpeg interchangeably by detected mime.
        if expected_mime != detected_mime:
            raise HTTPException(
                status_code=400, detail="File content does not match its extension"
            )

        client_content_type = (file.content_type or "").split(";")[0].strip().lower()
        if client_content_type and client_content_type not in {
            "image/jpeg",
            "image/png",
            "image/webp",
            "application/pdf",
        }:
            # Do not trust client MIME; reject obvious mismatch/spoofing.
            raise HTTPException(status_code=400, detail="Unsupported file content type")

        return content, detected_mime, original_name

    @staticmethod
    def store_document(
        db: Session,
        *,
        file: UploadFile,
        owner_id: int,
        actor_user_id: int,
        document_type: str,
    ) -> DocumentRecord:
        try:
            content, mime_type, original_name = DocumentService.validate_and_read_upload(file)
        except HTTPException:
            record_audit(
                db,
                action="upload_validation_failed",
                outcome="rejected",
                owner_id=owner_id,
                actor_user_id=actor_user_id,
                detail="invalid_upload",
            )
            try:
                db.flush()
            except Exception:
                db.rollback()
            raise

        checksum = hashlib.sha256(content).hexdigest()
        ext = _extension_for_mime(mime_type) or ".bin"
        doc_id = str(uuid.uuid4())
        storage_key = f"documents/{document_type}/{owner_id}/{doc_id}{ext}"
        scan_status, scan_detail = _scan_bytes(content)

        storage = get_storage_backend()
        provider = (STORAGE_PROVIDER or "local").strip().lower()
        bucket = STORAGE_BUCKET or None if provider == "s3" else None

        try:
            storage.put(storage_key, content, mime_type)
        except StorageError:
            record_audit(
                db,
                action="upload",
                outcome="failed",
                owner_id=owner_id,
                actor_user_id=actor_user_id,
                detail="storage_error",
            )
            try:
                db.flush()
            except Exception:
                db.rollback()
            raise HTTPException(status_code=503, detail="Document storage is unavailable")

        expires_at = None
        if DOCUMENT_RETENTION_DAYS > 0:
            expires_at = _utcnow() + timedelta(days=int(DOCUMENT_RETENTION_DAYS))

        record = DocumentRecord(
            id=doc_id,
            owner_id=owner_id,
            document_type=document_type,
            storage_provider=provider,
            storage_key=storage_key,
            bucket=bucket,
            original_filename=original_name,
            mime_type=mime_type,
            file_size=len(content),
            checksum_sha256=checksum,
            scan_status=scan_status,
            scan_detail=scan_detail,
            expires_at=expires_at,
        )
        db.add(record)
        record_audit(
            db,
            action="upload",
            outcome="stored",
            document_id=doc_id,
            owner_id=owner_id,
            actor_user_id=actor_user_id,
            detail=scan_status.value,
        )
        record_audit(
            db,
            action="malware_scan",
            outcome=scan_status.value.lower(),
            document_id=doc_id,
            owner_id=owner_id,
            actor_user_id=actor_user_id,
            detail=(scan_detail or "")[:255] or None,
        )
        db.flush()
        try:
            db.refresh(record)
        except Exception:
            pass
        return record

    @staticmethod
    def _is_expired(record: DocumentRecord) -> bool:
        if record.deleted_at is not None:
            return True
        if record.expires_at is None:
            return False
        return record.expires_at <= _utcnow()

    @staticmethod
    def can_access(db: Session, *, user: User, record: DocumentRecord) -> bool:
        if record.deleted_at is not None:
            return False
        if user.role == UserRole.admin:
            return True
        if record.owner_id == user.id:
            return True
        if user.role == UserRole.field_member and record.document_type == "service_proof":
            member = db.query(FieldMember).filter(FieldMember.user_id == user.id).first()
            if member is None:
                return False
            assignment = (
                db.query(RequestAssignment.id)
                .join(ServiceRequest, ServiceRequest.id == RequestAssignment.request_id)
                .filter(
                    ServiceRequest.proof_document_id == record.id,
                    RequestAssignment.field_member_id == member.id,
                )
                .first()
            )
            return assignment is not None
        return False

    @staticmethod
    def get_record_or_404(db: Session, document_id: str) -> DocumentRecord:
        record = db.get(DocumentRecord, document_id)
        if record is None:
            raise HTTPException(status_code=404, detail="Document not found")
        return record

    @staticmethod
    def authorize_and_get(
        db: Session, *, document_id: str, user: User, action: str = "retrieve"
    ) -> DocumentRecord:
        record = DocumentService.get_record_or_404(db, document_id)
        if DocumentService._is_expired(record):
            record_audit(
                db,
                action="expired_access",
                outcome="denied",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=user.id,
                detail="expired_or_deleted",
            )
            db.commit()
            raise HTTPException(status_code=404, detail="Document not found")
        if not DocumentService.can_access(db, user=user, record=record):
            record_audit(
                db,
                action="unauthorized_access",
                outcome="denied",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=user.id,
                detail=action,
            )
            db.commit()
            raise HTTPException(status_code=404, detail="Document not found")
        if action == "retrieve" and record.scan_status != DocumentScanStatus.clean:
            record_audit(
                db,
                action="retrieve",
                outcome="blocked",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=user.id,
                detail=record.scan_status.value.lower(),
            )
            db.commit()
            raise HTTPException(status_code=403, detail="Document is not available")
        return record

    @staticmethod
    def get_retrieval_payload(db: Session, *, document_id: str, user: User) -> dict:
        record = DocumentService.authorize_and_get(db, document_id=document_id, user=user)
        storage = get_storage_backend()
        ttl = default_signed_url_ttl()
        safe_name = _sanitize_filename(record.original_filename) or f"document{_extension_for_mime(record.mime_type) or ''}"
        signed = storage.signed_url(record.storage_key, ttl, download_name=safe_name)
        record_audit(
            db,
            action="retrieve",
            outcome="allowed",
            document_id=record.id,
            owner_id=record.owner_id,
            actor_user_id=user.id,
            detail="signed_url" if signed else "stream",
        )
        db.commit()
        payload = {
            "document_id": record.id,
            "mime_type": record.mime_type,
            "file_size": record.file_size,
            "scan_status": record.scan_status.value,
            "expires_in_seconds": ttl if signed else None,
        }
        if signed:
            payload["url"] = signed
            payload["delivery"] = "signed_url"
        else:
            payload["url"] = f"/documents/{record.id}/content"
            payload["delivery"] = "authenticated_stream"
        return payload

    @staticmethod
    def stream_content(db: Session, *, document_id: str, user: User) -> tuple[bytes, DocumentRecord]:
        record = DocumentService.authorize_and_get(db, document_id=document_id, user=user)
        storage = get_storage_backend()
        try:
            content = storage.get(record.storage_key)
        except StorageNotFoundError:
            record_audit(
                db,
                action="retrieve",
                outcome="missing",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=user.id,
            )
            db.commit()
            raise HTTPException(status_code=404, detail="Document not found")
        except StorageError:
            record_audit(
                db,
                action="retrieve",
                outcome="failed",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=user.id,
                detail="storage_error",
            )
            db.commit()
            raise HTTPException(status_code=503, detail="Document storage is unavailable")
        record_audit(
            db,
            action="retrieve",
            outcome="streamed",
            document_id=record.id,
            owner_id=record.owner_id,
            actor_user_id=user.id,
        )
        db.commit()
        return content, record

    @staticmethod
    def delete_document(db: Session, *, document_id: str, actor: User) -> DocumentRecord:
        record = DocumentService.get_record_or_404(db, document_id)
        if record.deleted_at is not None:
            return record
        is_admin = actor.role == UserRole.admin
        if not is_admin and record.owner_id != actor.id:
            record_audit(
                db,
                action="delete",
                outcome="denied",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=actor.id,
            )
            db.commit()
            raise HTTPException(status_code=404, detail="Document not found")

        storage = get_storage_backend()
        try:
            storage.delete(record.storage_key)
        except StorageError:
            record_audit(
                db,
                action="delete",
                outcome="failed",
                document_id=record.id,
                owner_id=record.owner_id,
                actor_user_id=actor.id,
                detail="storage_error",
            )
            db.commit()
            raise HTTPException(status_code=503, detail="Document deletion failed")

        record.deleted_at = _utcnow()
        record.deleted_by_user_id = actor.id
        record_audit(
            db,
            action="delete",
            outcome="deleted",
            document_id=record.id,
            owner_id=record.owner_id,
            actor_user_id=actor.id,
        )
        db.commit()
        db.refresh(record)
        return record
