"""Cryptographically secure OTP generation."""

import secrets


def generate_otp(length: int = 6) -> str:
    """Return a numeric OTP drawn from the system CSPRNG."""
    if length < 4 or length > 10:
        raise ValueError("OTP length must be between 4 and 10 digits")
    lo = 10 ** (length - 1)
    hi = (10**length) - 1
    return str(secrets.randbelow(hi - lo + 1) + lo)
