"""Notification endpoints for every role.

Ownership is enforced by the service layer filtering on ``user_id`` from the
token, so one customer can never read or delete another user's notification.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.notification import Notification
from app.models.user import User
from app.schemas.notification_schema import NotificationListResponse, NotificationResponse
from app.services.notification_service import NotificationService
from app.utils.dependencies import get_current_user

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get("", response_model=NotificationListResponse)
def list_notifications(
    limit: int = 50,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    rows = db.query(Notification).filter(Notification.user_id == user.id)
    notifications = (
        rows.order_by(Notification.created_at.desc()).limit(min(limit, 200)).all()
    )
    return NotificationListResponse(
        notifications=[
            NotificationResponse(
                id=n.id,
                title=n.title,
                message=n.message,
                category=n.category.value if n.category else "",
                reference_type=n.reference_type,
                reference_id=n.reference_id,
                is_read=n.is_read,
                created_at=n.created_at,
            )
            for n in notifications
        ],
        unread_count=NotificationService.get_unread_count(db, user.id),
    )


@router.get("/unread-count")
def unread_count(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return {"unread_count": NotificationService.get_unread_count(db, user.id)}


@router.put("/{notification_id}/read")
def mark_read(
    notification_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    notification = NotificationService.mark_as_read(db, notification_id, user.id)
    db.commit()
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"message": "Marked as read"}


@router.put("/mark-all-read")
def mark_all_read(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    NotificationService.mark_all_as_read(db, user.id)
    db.commit()
    return {"message": "All notifications marked as read"}


@router.delete("/{notification_id}")
def delete_notification(
    notification_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    notification = NotificationService.delete_notification(db, notification_id, user.id)
    db.commit()
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"message": "Notification deleted"}
