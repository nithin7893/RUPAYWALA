"""OTP issue / verify with abuse protection."""

import logging
import re
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.config import (
    OTP_DEBUG_LOG,
    OTP_EXPIRY_MINUTES,
    OTP_LENGTH,
    OTP_MAX_SEND_PER_HOUR,
    OTP_MAX_VERIFY_ATTEMPTS,
    OTP_RESEND_COOLDOWN_SECONDS,
)
from app.models.otp_verification import OTPPurpose, OTPVerification
from app.services import email_service
from app.utils.otp_generator import generate_otp
from app.utils.security import hash_otp, verify_otp
from app.utils.sms_service import is_valid_phone, normalise_phone, send_otp_sms

logger = logging.getLogger(__name__)

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class OTPService:
    @staticmethod
    def issue(
        db: Session,
        phone_number: str,
        purpose: OTPPurpose = OTPPurpose.signup,
    ) -> tuple[OTPVerification, str, bool]:
        """Create a new OTP for phone.

        Returns (record, code, delivered). Raises 429 when the caller is being
        throttled and 400 when the phone number is not a valid Indian mobile.
        """
        phone = normalise_phone(phone_number)
        if not is_valid_phone(phone):
            raise HTTPException(
                status_code=400, detail="Enter a valid 10-digit mobile number"
            )

        one_hour_ago = datetime.utcnow() - timedelta(hours=1)
        recent = (
            db.query(func.count(OTPVerification.id))
            .filter(
                OTPVerification.phone_number == phone,
                OTPVerification.created_at >= one_hour_ago,
            )
            .scalar()
            or 0
        )
        if recent >= OTP_MAX_SEND_PER_HOUR:
            raise HTTPException(
                status_code=429,
                detail="Too many verification codes requested. Please try again in an hour.",
            )

        last = (
            db.query(OTPVerification)
            .filter(OTPVerification.phone_number == phone)
            .order_by(OTPVerification.id.desc())
            .first()
        )
        if last is not None:
            cooldown = (datetime.utcnow() - (last.created_at or datetime.utcnow())).total_seconds()
            if cooldown < OTP_RESEND_COOLDOWN_SECONDS:
                wait = int(OTP_RESEND_COOLDOWN_SECONDS - cooldown) + 1
                raise HTTPException(
                    status_code=429,
                    detail=f"Please wait {wait} seconds before requesting another code",
                )

        # Invalidate anything still outstanding so only the newest code works.
        (
            db.query(OTPVerification)
            .filter(
                OTPVerification.phone_number == phone,
                OTPVerification.is_used.is_(False),
            )
            .update({OTPVerification.is_used: True}, synchronize_session=False)
        )

        code = generate_otp(OTP_LENGTH)
        record = OTPVerification(
            phone_number=phone,
            email=None,
            otp_hash=hash_otp(code),
            purpose=purpose,
            expires_at=datetime.utcnow() + timedelta(minutes=OTP_EXPIRY_MINUTES),
        )
        db.add(record)
        db.commit()
        db.refresh(record)

        delivered = send_otp_sms(phone, code)

        # Local development aid: with OTP_DEBUG_LOG=true the code is always
        # printed to the console, whether or not the SMS went out, so the login
        # flow can be walked through without a working gateway. This is the
        # plaintext code, so the flag must never be enabled in production.
        if OTP_DEBUG_LOG:
            logger.warning("OTP issued for phone (debug log enabled) - do not enable in production")
        elif not delivered:
            logger.warning("OTP could not be delivered over SMS")

        return record, code, delivered

    @staticmethod
    def issue_email(
        db: Session,
        email: str,
        purpose: OTPPurpose = OTPPurpose.email_signup,
    ) -> tuple[OTPVerification, str, bool]:
        """Create a new OTP for email."""
        email_clean = email.strip().lower()
        if not EMAIL_RE.match(email_clean):
            raise HTTPException(status_code=400, detail="Enter a valid email address")

        one_hour_ago = datetime.utcnow() - timedelta(hours=1)
        recent = (
            db.query(func.count(OTPVerification.id))
            .filter(
                OTPVerification.email == email_clean,
                OTPVerification.created_at >= one_hour_ago,
            )
            .scalar()
            or 0
        )
        if recent >= OTP_MAX_SEND_PER_HOUR:
            raise HTTPException(
                status_code=429,
                detail="Too many verification codes requested. Please try again in an hour.",
            )

        last = (
            db.query(OTPVerification)
            .filter(OTPVerification.email == email_clean)
            .order_by(OTPVerification.id.desc())
            .first()
        )
        if last is not None:
            cooldown = (datetime.utcnow() - (last.created_at or datetime.utcnow())).total_seconds()
            if cooldown < OTP_RESEND_COOLDOWN_SECONDS:
                wait = int(OTP_RESEND_COOLDOWN_SECONDS - cooldown) + 1
                raise HTTPException(
                    status_code=429,
                    detail=f"Please wait {wait} seconds before requesting another code",
                )

        (
            db.query(OTPVerification)
            .filter(
                OTPVerification.email == email_clean,
                OTPVerification.is_used.is_(False),
            )
            .update({OTPVerification.is_used: True}, synchronize_session=False)
        )

        code = generate_otp(OTP_LENGTH)
        record = OTPVerification(
            phone_number=None,
            email=email_clean,
            otp_hash=hash_otp(code),
            purpose=purpose,
            expires_at=datetime.utcnow() + timedelta(minutes=OTP_EXPIRY_MINUTES),
        )
        db.add(record)
        db.commit()
        db.refresh(record)

        delivered = email_service.send_otp_email(email_clean, code, purpose=purpose.value)

        if OTP_DEBUG_LOG:
            logger.warning("OTP issued for email (debug log enabled) - do not enable in production")
        elif not delivered:
            logger.warning("OTP could not be delivered by email")

        return record, code, delivered

    @staticmethod
    def verify(
        db: Session,
        phone_number: str,
        code: str,
        purpose: OTPPurpose | None = None,
    ) -> OTPVerification:
        phone = normalise_phone(phone_number)
        if not is_valid_phone(phone):
            raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number")

        query = db.query(OTPVerification).filter(
            OTPVerification.phone_number == phone,
            OTPVerification.is_used.is_(False),
        )
        if purpose is not None:
            query = query.filter(OTPVerification.purpose == purpose)
        record = query.order_by(OTPVerification.id.desc()).first()
        if record is None:
            raise HTTPException(status_code=400, detail="Request a new verification code")

        if record.is_expired():
            record.is_used = True
            db.commit()
            raise HTTPException(status_code=400, detail="That code has expired. Request a new one.")

        if record.attempts >= OTP_MAX_VERIFY_ATTEMPTS:
            record.is_used = True
            db.commit()
            raise HTTPException(
                status_code=429, detail="Too many incorrect attempts. Request a new code."
            )

        if not verify_otp(str(code).strip(), record.otp_hash):
            record.attempts += 1
            db.commit()
            remaining = max(0, OTP_MAX_VERIFY_ATTEMPTS - record.attempts)
            raise HTTPException(
                status_code=400,
                detail=(
                    f"That code is not correct. {remaining} attempt(s) remaining."
                    if remaining
                    else "That code is not correct. Request a new one."
                ),
            )

        record.verified = True
        record.is_used = True
        db.commit()
        db.refresh(record)
        return record

    @staticmethod
    def verify_email(db: Session, email: str, code: str, purpose: OTPPurpose | None = None) -> OTPVerification:
        """Verify and atomically consume the newest unused email OTP.

        The candidate row is locked while the code is checked, and consumption
        is a conditional update, so concurrent requests cannot both succeed
        with the same code. Email verification now has the same single-use
        semantics as phone verification (``verify``).
        """
        email_clean = email.strip().lower()
        if not EMAIL_RE.match(email_clean):
            raise HTTPException(status_code=400, detail="Enter a valid email address")

        query = db.query(OTPVerification).filter(
            OTPVerification.email == email_clean,
            OTPVerification.is_used.is_(False),
        )
        if purpose is not None:
            query = query.filter(OTPVerification.purpose == purpose)
        # SELECT ... FOR UPDATE keeps code verification and consumption in one
        # atomic critical section across workers.
        record = query.order_by(OTPVerification.id.desc()).with_for_update().first()
        if record is None:
            raise HTTPException(status_code=400, detail="Request a new verification code")
        if record.is_used:
            # Defensive: another transaction consumed the row after the read.
            raise HTTPException(status_code=400, detail="Request a new verification code")

        if record.is_expired():
            record.is_used = True
            db.commit()
            raise HTTPException(status_code=400, detail="That code has expired. Request a new one.")

        if record.attempts >= OTP_MAX_VERIFY_ATTEMPTS:
            record.is_used = True
            db.commit()
            raise HTTPException(
                status_code=429, detail="Too many incorrect attempts. Request a new code."
            )

        if not verify_otp(str(code).strip(), record.otp_hash):
            record.attempts += 1
            db.commit()
            remaining = max(0, OTP_MAX_VERIFY_ATTEMPTS - record.attempts)
            raise HTTPException(
                status_code=400,
                detail=(
                    f"That code is not correct. {remaining} attempt(s) remaining."
                    if remaining
                    else "That code is not correct. Request a new one."
                ),
            )

        # Conditional update is the commit point: only the request that flips
        # is_used from false to true owns the code.
        consumed = (
            db.query(OTPVerification)
            .filter(
                OTPVerification.id == record.id,
                OTPVerification.is_used.is_(False),
            )
            .update(
                {OTPVerification.verified: True, OTPVerification.is_used: True},
                synchronize_session=False,
            )
        )
        if consumed != 1:
            db.rollback()
            raise HTTPException(status_code=400, detail="Request a new verification code")
        db.commit()
        db.refresh(record)
        return record

    @staticmethod
    def purge_expired(db: Session) -> int:
        cutoff = datetime.utcnow() - timedelta(days=1)
        count = (
            db.query(OTPVerification)
            .filter(OTPVerification.created_at < cutoff)
            .delete(synchronize_session=False)
        )
        db.commit()
        return count
