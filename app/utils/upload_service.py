"""Safe file upload handling for completion proof images."""

import logging
import os
import re
import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile

from app.config import ALLOWED_PROOF_EXTENSIONS, MAX_UPLOAD_BYTES, UPLOAD_DIR

logger = logging.getLogger(__name__)

_SAFE_CHARS = re.compile(r"[^A-Za-z0-9._-]")

# Magic-number prefixes for the formats we accept.
_SIGNATURES = (
    b"\xff\xd8\xff",                 # jpeg
    b"\x89PNG\r\n\x1a\n",           # png
)
_PDF_SIGNATURE = b"%PDF-"


def _upload_root() -> Path:
    root = Path(UPLOAD_DIR).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def save_upload(file: UploadFile, subdir: str = "proof") -> str:
    """Persist an upload and return its public relative path.

    The client-supplied filename is never used for the path on disk - only a
    random name plus a validated extension - which removes path traversal and
    overwrite risks entirely.
    """
    original = file.filename or ""
    ext = os.path.splitext(original)[1].lower()

    if ext not in ALLOWED_PROOF_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=(
                "Unsupported file type. Allowed types: "
                + ", ".join(ALLOWED_PROOF_EXTENSIONS)
            ),
        )

    safe_subdir = _SAFE_CHARS.sub("_", subdir).strip("_") or "proof"
    target_dir = _upload_root() / safe_subdir

    # Defence in depth: ensure the resolved directory stays inside the root.
    try:
        target_dir.resolve().relative_to(_upload_root())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid upload path")

    target_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid.uuid4().hex}{ext}"
    destination = target_dir / filename

    content = file.file.read(MAX_UPLOAD_BYTES + 1)
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File is too large. Maximum size is {MAX_UPLOAD_BYTES // (1024 * 1024)} MB",
        )
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")

    if not _looks_valid(content, ext):
        raise HTTPException(
            status_code=400, detail="File content does not match its extension"
        )

    destination.write_bytes(content)
    return f"{safe_subdir}/{filename}"


def _looks_valid(content: bytes, ext: str) -> bool:
    if ext == ".pdf":
        return content.startswith(_PDF_SIGNATURE)
    return any(content.startswith(sig) for sig in _SIGNATURES) or ext in (
        ".webp",
    )
