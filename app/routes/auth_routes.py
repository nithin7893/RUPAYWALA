"""
Authentication endpoints.

Security model
--------------
* Phone signup is gated by a server-issued OTP. Registering therefore REQUIRES
  ``phone_number`` + ``username`` + ``password`` - no role, no ``is_verified``.
* The role is always ``customer``. Admin and field-member roles are granted by
  an admin through /admin/users, never by the client.
* Login accepts a username OR a phone number, so a customer can use whichever
  they remember.
* Google sign-in verifies Google's signature server-side; the email is only
  trusted because Google proved it.
* Every response includes the role so the app can route to the right shell.
"""

import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import Field
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.customer_profile import CustomerProfile
from app.models.otp_verification import OTPPurpose, OTPVerification
from app.models.user import AuthProvider, User, UserRole
from app.schemas.auth_schema import (
    AuthResponse,
    ChangePasswordRequest,
    ChangeUsernameRequest,
    EmailOnly,
    EmailRegisterRequest,
    GoogleLoginRequest,
    LoginRequest,
    PhoneOnly,
    RegisterRequest,
    SendEmailOTPRequest,
    SendOTPRequest,
    VerifyEmailOTPRequest,
    VerifyOTPRequest,
)
from app.services.google_auth_service import GoogleAuthService
from app.services.otp_service import OTPService
from app.services.subscription_service import SubscriptionService
from app.utils import rate_limit
from app.utils.dependencies import get_current_user
from app.utils.jwt_handler import create_access_token
from app.utils.security import (
    hash_password,
    validate_password_strength,
    verify_password,
)
from app.utils.sms_service import normalise_phone

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Authentication"])


# ======================================================================
# helpers
# ======================================================================
def _profile_completed(db: Session, user_id: int) -> bool:
    profile = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == user_id)
        .first()
    )
    return bool(profile and profile.profile_completed)


def _display_name(db: Session, user: User) -> str | None:
    profile = (
        db.query(CustomerProfile)
        .filter(CustomerProfile.user_id == user.id)
        .first()
    )
    return profile.full_name if profile else None


def _build_auth_response(db: Session, user: User) -> AuthResponse:
    current = SubscriptionService.current(db, user.id)
    return AuthResponse(
        access_token=create_access_token(
            {"user_id": user.id, "role": user.role.value}
        ),
        user_id=user.id,
        role=user.role.value,
        username=user.username,
        full_name=_display_name(db, user),
        phone_number=user.phone_number,
        email=user.email,
        is_verified=bool(user.is_verified),
        profile_completed=_profile_completed(db, user.id),
        has_active_subscription=bool(
            current and current.status.value == "active" and current.is_usable_on()
        ),
        has_password=bool(user.password_hash),
    )


def _password_problem(payload: str) -> str | None:
    return validate_password_strength(payload)


# ======================================================================
# 1. Pre-login identity check
# ======================================================================
@router.post("/check-user")
def check_user(payload: PhoneOnly, db: Session = Depends(get_db)) -> dict:
    """Tell the app which screen to show next for a phone number."""
    phone = normalise_phone(payload.phone_number)
    user = db.query(User).filter(User.phone_number == phone).first()

    if user is None:
        return {"exists": False, "has_password": False, "next": "send_otp"}

    if user.account_status.value != "active":
        raise HTTPException(
            status_code=403, detail="This account has been suspended. Please contact support."
        )
    return {
        "exists": True,
        "has_password": bool(user.password_hash),
        "next": "login" if user.password_hash else "send_otp",
    }


# ======================================================================
# 2. OTP issue / verify (phone)
# ======================================================================
@router.post(
    "/send-otp", dependencies=[Depends(rate_limit.rate_limit(5, 60, "auth-send-otp"))]
)
def send_otp(payload: SendOTPRequest, db: Session = Depends(get_db)) -> dict:
    _record, code, delivered = OTPService.issue(
        db, payload.phone_number, purpose=OTPPurpose.signup
    )
    # The code is NEVER returned to the client.
    return {
        "message": (
            "Verification code sent. It is valid for a few minutes."
            if delivered
            else "We could not deliver the code by SMS right now. Please try again shortly."
        ),
        "delivered": delivered,
        "expires_in_minutes": 5,
    }


@router.post(
    "/verify-otp", dependencies=[Depends(rate_limit.rate_limit(10, 60, "auth-verify-otp"))]
)
def verify_otp(payload: VerifyOTPRequest, db: Session = Depends(get_db)) -> dict:
    record = OTPService.verify(db, payload.phone_number, payload.otp)

    phone = normalise_phone(payload.phone_number)
    user = db.query(User).filter(User.phone_number == phone).first()

    if user is not None:
        if user.account_status.value != "active":
            raise HTTPException(
                status_code=403,
                detail="This account has been suspended. Please contact support.",
            )
        if user.is_verified and user.password_hash:
            # Known device, known user: the OTP proved ownership, so log in.
            return {
                "verified": True,
                "next": "login",
                "user_exists": True,
                "message": "Verified. Please enter your password.",
            }
        return {
            "verified": True,
            "next": "set_password",
            "user_exists": True,
            "message": "Verified. Please create your username and password.",
        }

    return {
        "verified": True,
        "next": "register",
        "user_exists": False,
        "message": "Verified. Please create your username and password.",
    }


# ======================================================================
# 2b. OTP issue / verify (email)
# ======================================================================
@router.post(
    "/send-email-otp", dependencies=[Depends(rate_limit.rate_limit(5, 60, "auth-send-email-otp"))]
)
def send_email_otp(payload: SendEmailOTPRequest, db: Session = Depends(get_db)) -> dict:
    email = payload.email.strip().lower()
    user = db.query(User).filter(func.lower(User.email) == email).first()
    purpose = OTPPurpose.email_login if user else OTPPurpose.email_signup
    _record, _code, delivered = OTPService.issue_email(db, email, purpose=purpose)
    return {
        "message": (
            "Verification code sent to your email. It is valid for a few minutes."
            if delivered
            else "We could not deliver the code by email right now. Please try again shortly."
        ),
        "delivered": delivered,
        "expires_in_minutes": 5,
    }


@router.post(
    "/verify-email-otp",
    dependencies=[Depends(rate_limit.rate_limit(10, 60, "auth-verify-email-otp"))],
)
def verify_email_otp(payload: VerifyEmailOTPRequest, db: Session = Depends(get_db)) -> dict:
    email = payload.email.strip().lower()
    user = db.query(User).filter(func.lower(User.email) == email).first()
    purpose = OTPPurpose.email_login if user else OTPPurpose.email_signup
    _record = OTPService.verify_email(db, email, payload.otp, purpose=purpose)

    if user is not None:
        if user.account_status.value != "active":
            raise HTTPException(
                status_code=403,
                detail="This account has been suspended. Please contact support.",
            )
        if user.is_verified and user.password_hash:
            return {
                "verified": True,
                "next": "login",
                "user_exists": True,
                "message": "Verified. Please continue to login.",
            }
        return {
            "verified": True,
            "next": "set_password",
            "user_exists": True,
            "message": "Verified. Please create your username and password.",
        }

    return {
        "verified": True,
        "next": "register",
        "user_exists": False,
        "message": "Verified. Please create your username and password.",
    }


@router.post(
    "/email-login",
    dependencies=[Depends(rate_limit.rate_limit(10, 60, "auth-email-login"))],
)
def email_login(payload: VerifyEmailOTPRequest, db: Session = Depends(get_db)) -> AuthResponse:
    email = payload.email.strip().lower()
    user = db.query(User).filter(func.lower(User.email) == email).first()
    if user is None:
        # Do not reveal whether email exists
        raise HTTPException(status_code=400, detail="Request a new verification code")
    if user.account_status.value != "active":
        raise HTTPException(
            status_code=403, detail="This account has been suspended. Please contact support."
        )
    proof = (
        db.query(OTPVerification)
        .filter(
            OTPVerification.email == email,
            OTPVerification.purpose == OTPPurpose.email_login,
            OTPVerification.verified.is_(True),
        )
        .order_by(OTPVerification.id.desc())
        .first()
    )
    if proof is None:
        _record = OTPService.verify_email(db, email, payload.otp, purpose=OTPPurpose.email_login)
    else:
        _record = proof
    if not user.password_hash and not user.is_verified:
        raise HTTPException(status_code=400, detail="Complete registration first")
    user.auth_provider = AuthProvider.email_otp
    user.email_verified = True
    user.is_verified = True
    user.last_login_at = datetime.utcnow()
    db.commit()
    db.refresh(user)
    return _build_auth_response(db, user)


# ======================================================================
# 3. Registration (OTP proof + username + password)
# ======================================================================
@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> AuthResponse:
    phone = normalise_phone(payload.phone_number)
    username = payload.username.strip().lower()

    # The phone must have been proved by a successful OTP within this session.
    proof = (
        db.query(OTPVerification)
        .filter(
            OTPVerification.phone_number == phone,
            OTPVerification.verified.is_(True),
            OTPVerification.is_used.is_(True),
        )
        .order_by(OTPVerification.id.desc())
        .first()
    )
    if proof is None:
        raise HTTPException(
            status_code=400, detail="Verify your mobile number before registering"
        )
    if proof.purpose not in (OTPPurpose.signup,):
        raise HTTPException(status_code=400, detail="Invalid verification purpose")

    problem = _password_problem(payload.password)
    if problem:
        raise HTTPException(status_code=400, detail=problem)

    if db.query(User).filter(User.phone_number == phone).first():
        raise HTTPException(status_code=409, detail="This mobile number is already registered")
    if db.query(User).filter(User.username == username).first():
        raise HTTPException(status_code=409, detail="That username is already taken")

    user = User(
        phone_number=phone,
        username=username,
        password_hash=hash_password(payload.password),
        # Hard-coded: a public signup can only ever create a customer.
        role=UserRole.customer,
        is_verified=True,
        phone_verified=True,
        auth_provider=AuthProvider.phone_otp,
        last_login_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    logger.info("Customer registered via phone OTP")
    return _build_auth_response(db, user)


@router.post("/register/email", status_code=status.HTTP_201_CREATED)
def register_email(payload: EmailRegisterRequest, db: Session = Depends(get_db)) -> AuthResponse:
    email = payload.email.strip().lower()
    username = payload.username.strip().lower()
    phone = normalise_phone(payload.phone_number) if payload.phone_number else None

    proof = (
        db.query(OTPVerification)
        .filter(
            OTPVerification.email == email,
            OTPVerification.verified.is_(True),
            OTPVerification.purpose == OTPPurpose.email_signup,
        )
        .order_by(OTPVerification.id.desc())
        .first()
    )
    if proof is None:
        raise HTTPException(status_code=400, detail="Verify your email before registering")

    if phone is not None:
        phone_proof = (
            db.query(OTPVerification)
            .filter(
                OTPVerification.phone_number == phone,
                OTPVerification.verified.is_(True),
                OTPVerification.purpose == OTPPurpose.signup,
            )
            .order_by(OTPVerification.id.desc())
            .first()
        )
        if phone_proof is None:
            raise HTTPException(status_code=400, detail="Verify your mobile number before registering")

    problem = _password_problem(payload.password)
    if problem:
        raise HTTPException(status_code=400, detail=problem)

    if db.query(User).filter(func.lower(User.email) == email).first():
        raise HTTPException(status_code=409, detail="This email is already registered")
    if db.query(User).filter(User.username == username).first():
        raise HTTPException(status_code=409, detail="That username is already taken")
    if phone and db.query(User).filter(User.phone_number == phone).first():
        raise HTTPException(status_code=409, detail="This mobile number is already registered")

    user = User(
        email=email,
        phone_number=phone,
        username=username,
        password_hash=hash_password(payload.password),
        role=UserRole.customer,
        is_verified=True,
        email_verified=True,
        phone_verified=bool(phone),
        auth_provider=AuthProvider.email_otp,
        last_login_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    logger.info("Customer registered via email OTP")
    return _build_auth_response(db, user)


# ======================================================================
# 4. Login - username OR phone
# ======================================================================
@router.post(
    "/login", dependencies=[Depends(rate_limit.rate_limit(10, 60, "auth-login"))]
)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> AuthResponse:
    identifier = payload.identifier.strip()
    if not identifier:
        raise HTTPException(status_code=400, detail="Enter your username or mobile number")

    query = db.query(User).filter(
        or_(
            func.lower(User.username) == identifier.lower(),
            User.phone_number == normalise_phone(identifier),
        )
    )
    user = query.first()

    # Identical error for "no such user" and "wrong password" so the endpoint
    # cannot be used to enumerate accounts.
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=401, detail="Incorrect username/mobile number or password"
        )
    if user.account_status.value != "active":
        raise HTTPException(
            status_code=403, detail="This account has been suspended. Please contact support."
        )

    user.last_login_at = datetime.utcnow()
    db.commit()
    db.refresh(user)
    return _build_auth_response(db, user)


# ======================================================================
# 5. Google sign-in
# ======================================================================
@router.post("/google")
def google_login(payload: GoogleLoginRequest, db: Session = Depends(get_db)) -> AuthResponse:
    try:
        token = payload.token()
    except ValueError:
        raise HTTPException(status_code=400, detail="Provide a Google ID or access token")

    if payload.id_token:
        identity = GoogleAuthService.verify_id_token(payload.id_token)
    else:
        identity = GoogleAuthService.verify_access_token(token)

    if not identity.sub or "@" not in identity.email:
        raise HTTPException(status_code=401, detail="Google sign-in could not be verified")

    user = (
        db.query(User)
        .filter(
            or_(
                User.google_sub == identity.sub,
                User.email == identity.email,
            )
        )
        .first()
    )

    if user is None:
        user = User(
            email=identity.email,
            google_sub=identity.sub,
            # Google-only accounts have no password until they set one.
            password_hash=None,
            role=UserRole.customer,
            is_verified=True,
            auth_provider=AuthProvider.google,
            last_login_at=datetime.utcnow(),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        logger.info("Google sign-in created user_id=%s", user.id)
    else:
        if user.google_sub is None:
            user.google_sub = identity.sub
        if not user.email:
            user.email = identity.email
        user.is_verified = True
        if user.account_status.value != "active":
            raise HTTPException(
                status_code=403, detail="This account has been suspended. Please contact support."
            )
        user.last_login_at = datetime.utcnow()
        db.commit()
        db.refresh(user)

    return _build_auth_response(db, user)


# ======================================================================
# 6. Session
# ======================================================================
@router.get("/me")
def me(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Used on app launch to restore a session and pick the right shell."""
    subscription = SubscriptionService.current(db, current_user.id)
    field_member = None

    if current_user.role == UserRole.field_member:
        from app.models.field_member import FieldMember

        member = (
            db.query(FieldMember).filter(FieldMember.user_id == current_user.id).first()
        )
        if member is not None:
            field_member = {
                "id": member.id,
                "employee_code": member.employee_code,
                "full_name": member.full_name,
                "region": member.region,
                "approval_status": member.approval_status.value,
                "is_available": member.is_available,
            }

    return {
        "user_id": current_user.id,
        "role": current_user.role.value,
        "username": current_user.username,
        "full_name": _display_name(db, current_user),
        "phone_number": current_user.phone_number,
        "email": current_user.email,
        "auth_provider": current_user.auth_provider.value,
        "is_verified": bool(current_user.is_verified),
        "profile_completed": _profile_completed(db, current_user.id),
        "account_status": current_user.account_status.value,
        "has_password": bool(current_user.password_hash),
        "field_member": field_member,
        "subscription": {
            "id": subscription.id,
            "status": subscription.status.value,
            "total_visits": subscription.total_visits,
            "used_visits": subscription.used_visits,
            "remaining_visits": subscription.remaining_visits,
            "start_date": subscription.start_date,
            "end_date": subscription.end_date,
            "usable": subscription.is_usable_on(),
        }
        if subscription
        else None,
    }


@router.put("/username")
def change_username(
    payload: ChangeUsernameRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    if current_user.password_hash:
        if not payload.current_password or not verify_password(
            payload.current_password, current_user.password_hash
        ):
            raise HTTPException(
                status_code=400, detail="Your current password is incorrect"
            )
    elif payload.current_password:
        raise HTTPException(
            status_code=400,
            detail="This account has no current password. Leave that field blank.",
        )

    existing_user = (
        db.query(User)
        .filter(
            func.lower(User.username) == payload.username,
            User.id != current_user.id,
        )
        .first()
    )
    if existing_user is not None:
        raise HTTPException(status_code=409, detail="That username is already taken")

    current_user.username = payload.username
    db.commit()
    return {"username": current_user.username}


@router.post("/change-password")
def change_password(
    payload: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    if current_user.password_hash:
        if not payload.current_password or not verify_password(
            payload.current_password, current_user.password_hash
        ):
            raise HTTPException(
                status_code=400, detail="Your current password is incorrect"
            )
    elif payload.current_password:
        raise HTTPException(
            status_code=400,
            detail="This account has no current password. Leave that field blank.",
        )

    if payload.current_password == payload.new_password:
        raise HTTPException(
            status_code=400, detail="Your new password must be different from the old one"
        )

    problem = _password_problem(payload.new_password)
    if problem:
        raise HTTPException(status_code=400, detail=problem)

    current_user.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"message": "Password updated successfully"}


# ======================================================================
# 7. Password reset via phone OTP
# ======================================================================
@router.post(
    "/forgot-password/send-otp",
    dependencies=[Depends(rate_limit.rate_limit(5, 60, "auth-forgot-otp"))],
)
def forgot_password_send_otp(payload: PhoneOnly, db: Session = Depends(get_db)) -> dict:
    phone = normalise_phone(payload.phone_number)
    user = db.query(User).filter(User.phone_number == phone).first()
    if user is None or not user.password_hash:
        # Do not reveal whether the number is registered.
        return {"message": "If that number is registered, a code has been sent."}
    _record, _code, _delivered = OTPService.issue(
        db, phone, purpose=OTPPurpose.reset_password
    )
    return {"message": "If that number is registered, a code has been sent."}


class ResetPasswordRequest(PhoneOnly):
    otp: str = Field(..., min_length=4, max_length=10)
    new_password: str = Field(..., min_length=8, max_length=72)


@router.post(
    "/forgot-password/reset",
    dependencies=[Depends(rate_limit.rate_limit(10, 60, "auth-forgot-reset"))],
)
def forgot_password_reset(payload: ResetPasswordRequest, db: Session = Depends(get_db)) -> dict:
    phone = normalise_phone(payload.phone_number)
    user = db.query(User).filter(User.phone_number == phone).first()
    if user is None:
        raise HTTPException(status_code=400, detail="Request a new verification code")

    proof = (
        db.query(OTPVerification)
        .filter(
            OTPVerification.phone_number == phone,
            OTPVerification.purpose == OTPPurpose.reset_password,
        )
        .order_by(OTPVerification.id.desc())
        .first()
    )
    if proof is None:
        raise HTTPException(status_code=400, detail="Request a new verification code")

    from app.utils.security import verify_otp as verify_otp_hash

    if not verify_otp_hash(payload.otp, proof.otp_hash) or proof.is_expired():
        raise HTTPException(status_code=400, detail="That code is not correct or has expired")

    problem = _password_problem(payload.new_password)
    if problem:
        raise HTTPException(status_code=400, detail=problem)

    user.password_hash = hash_password(payload.new_password)
    proof.is_used = True
    db.commit()
    return {"message": "Password updated. You can now sign in."}
