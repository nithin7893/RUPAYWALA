import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.sql import func

from app.database import Base


class DocumentScanStatus(str, enum.Enum):
    pending = "PENDING"
    clean = "CLEAN"
    infected = "INFECTED"
    failed = "FAILED"


class DocumentStorageProvider(str, enum.Enum):
    local = "local"
    s3 = "s3"


class DocumentRecord(Base):
    __tablename__ = "document_records"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    owner_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    document_type = Column(String(50), nullable=False, index=True)
    storage_provider = Column(String(20), nullable=False, default="local")
    storage_key = Column(String(512), nullable=False)
    bucket = Column(String(255), nullable=True)
    original_filename = Column(String(255), nullable=True)
    mime_type = Column(String(100), nullable=False)
    file_size = Column(BigInteger, nullable=False)
    checksum_sha256 = Column(String(64), nullable=False)
    scan_status = Column(
        Enum(DocumentScanStatus, name="document_scan_status"),
        nullable=False,
        default=DocumentScanStatus.pending,
    )
    scan_detail = Column(String(255), nullable=True)
    uploaded_at = Column(DateTime, nullable=False, server_default=func.now())
    updated_at = Column(DateTime, nullable=False, server_default=func.now(), onupdate=func.now())
    expires_at = Column(DateTime, nullable=True)
    deleted_at = Column(DateTime, nullable=True)
    deleted_by_user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    __table_args__ = (
        Index("idx_document_records_owner_type", "owner_id", "document_type"),
        Index("idx_document_records_scan_status", "scan_status"),
        Index("idx_document_records_deleted_at", "deleted_at"),
    )
