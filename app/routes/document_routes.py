from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.document_service import DocumentService
from app.utils.dependencies import get_current_user

router = APIRouter(prefix="/documents", tags=["Documents"])


@router.get("/{document_id}")
def get_document(
    document_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return DocumentService.get_retrieval_payload(db, document_id=document_id, user=current_user)


@router.get("/{document_id}/content")
def get_document_content(
    document_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    content, record = DocumentService.stream_content(db, document_id=document_id, user=current_user)
    headers = {
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
    }
    return Response(content=content, media_type=record.mime_type, headers=headers)


@router.delete("/{document_id}")
def delete_document(
    document_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    record = DocumentService.delete_document(db, document_id=document_id, actor=current_user)
    return {"message": "Document deleted", "document_id": record.id}
