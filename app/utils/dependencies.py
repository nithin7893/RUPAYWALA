"""
Authentication and authorisation dependencies.

The JWT payload is never trusted on its own: the user is re-loaded from the
database on every request so that a suspended account, a changed role or a
deleted record takes effect immediately. Role checks live here so no route can
forget them.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import AccountStatus, User, UserRole
from app.utils.jwt_handler import decode_access_token

security = HTTPBearer(auto_error=False)

_UNAUTHENTICATED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None or not credentials.credentials:
        raise _UNAUTHENTICATED

    try:
        payload = decode_access_token(credentials.credentials)
    except Exception:
        # Deliberately vague: never leak why the token was rejected.
        raise _UNAUTHENTICATED

    user_id = payload.get("user_id")
    if not user_id:
        raise _UNAUTHENTICATED

    user = db.get(User, user_id)
    if user is None:
        raise _UNAUTHENTICATED
    if user.account_status != AccountStatus.active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account has been suspended. Please contact support.",
        )

    token_version = payload.get("tv", 0)
    try:
        token_version = int(token_version)
    except (TypeError, ValueError):
        raise _UNAUTHENTICATED
    current_version = int(getattr(user, "token_version", 0) or 0)
    if token_version != current_version:
        raise _UNAUTHENTICATED
    return user


def _require(role: UserRole):
    def dependency(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role != role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have permission to perform this action",
            )
        return current_user

    return dependency


admin_required = _require(UserRole.admin)
customer_required = _require(UserRole.customer)
field_member_required = _require(UserRole.field_member)


def get_approved_field_member(
    current_user: User = Depends(field_member_required),
    db: Session = Depends(get_db),
):
    """A field member who is approved and available for operational work."""
    from app.models.field_member import FieldMember

    member = (
        db.query(FieldMember).filter(FieldMember.user_id == current_user.id).first()
    )
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No field member profile is linked to this account",
        )
    if not member.is_operational():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Your field member account is awaiting admin approval"
                if member.approval_status.value != "approved"
                else "Your field member account is currently unavailable"
            ),
        )
    return current_user, member
