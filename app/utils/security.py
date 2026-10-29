"""Password and token hashing helpers."""

import hashlib
import hmac
import secrets

from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

#: Minimum password length enforced on register / change-password.
MIN_PASSWORD_LENGTH = 8
MAX_PASSWORD_LENGTH = 72  # bcrypt silently truncates beyond 72 bytes


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str | None) -> bool:
    if not hashed_password:
        return False
    try:
        return pwd_context.verify(plain_password, hashed_password)
    except ValueError:
        return False


def validate_password_strength(password: str) -> str | None:
    """Return an error message, or None when the password is acceptable."""
    if not password or len(password) < MIN_PASSWORD_LENGTH:
        return f"Password must be at least {MIN_PASSWORD_LENGTH} characters long"
    if len(password) > MAX_PASSWORD_LENGTH:
        return f"Password must be at most {MAX_PASSWORD_LENGTH} characters long"
    if password.isdigit() or password.isalpha():
        return "Password must contain both letters and numbers"
    return None


def hash_otp(otp: str, salt: str | None = None) -> str:
    """Salted SHA-256 of an OTP.

    A plain SHA-256 would be trivially brute-forceable (6-digit space), so the
    salt plus the OTP length still leaves the code unrecoverable from the DB
    alone in practice only if the salt is secret. To keep the model simple and
    fast while still removing plaintext OTPs, a per-record random salt is
    generated and stored alongside the digest.
    """
    salt = salt or secrets.token_hex(16)
    digest = hashlib.sha256(f"{salt}:{otp}".encode()).hexdigest()
    return f"{salt}${digest}"


def verify_otp(otp: str, stored: str) -> bool:
    try:
        salt, _ = stored.split("$", 1)
    except ValueError:
        return False
    return hmac.compare_digest(hash_otp(otp, salt), stored)
