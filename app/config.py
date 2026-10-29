"""
Centralised application configuration.

All environment variables are read and validated exactly once, here.
No other module should call os.getenv() directly.
"""

import os
from typing import List, Optional

from dotenv import load_dotenv

load_dotenv()


def _get(key: str, default: Optional[str] = None, required: bool = False) -> Optional[str]:
    value = os.getenv(key, default)
    if required and not value:
        raise RuntimeError(
            f"Missing required environment variable: {key}. "
            f"Add {key} to your .env file."
        )
    return value


def _get_int(key: str, default: int) -> int:
    raw = os.getenv(key)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw)
    except ValueError:
        raise RuntimeError(f"Environment variable {key} must be an integer, got: {raw!r}")


def _get_float(key: str, default: float) -> float:
    raw = os.getenv(key)
    if raw is None or raw.strip() == "":
        return default
    try:
        return float(raw)
    except ValueError:
        raise RuntimeError(f"Environment variable {key} must be a number, got: {raw!r}")


def _get_bool(key: str, default: bool) -> bool:
    raw = os.getenv(key)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


# ------------------------------------------------------------------
# Database
# ------------------------------------------------------------------
DATABASE_URL = _get("DATABASE_URL", required=True)

# ------------------------------------------------------------------
# JWT
# ------------------------------------------------------------------
JWT_SECRET_KEY = _get("JWT_SECRET_KEY", required=True)
JWT_ALGORITHM = _get("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = _get_int("ACCESS_TOKEN_EXPIRE_MINUTES", 60 * 12)

# ------------------------------------------------------------------
# Security / rate limiting (in-process; swap for Redis in production)
# ------------------------------------------------------------------
OTP_EXPIRY_MINUTES = _get_int("OTP_EXPIRY_MINUTES", 5)
OTP_MAX_SEND_PER_HOUR = _get_int("OTP_MAX_SEND_PER_HOUR", 5)
OTP_RESEND_COOLDOWN_SECONDS = _get_int("OTP_RESEND_COOLDOWN_SECONDS", 45)
OTP_MAX_VERIFY_ATTEMPTS = _get_int("OTP_MAX_VERIFY_ATTEMPTS", 5)
OTP_LENGTH = _get_int("OTP_LENGTH", 6)
# When true the OTP is written to the server log instead of being sent by SMS.
# This is ONLY for local development. Never enable in production.
OTP_DEBUG_LOG = _get_bool("OTP_DEBUG_LOG", False)

# ------------------------------------------------------------------
# Email (SMTP)
# ------------------------------------------------------------------
SMTP_HOST = _get("SMTP_HOST", "")
SMTP_PORT = _get_int("SMTP_PORT", 587)
SMTP_USERNAME = _get("SMTP_USERNAME", "")
SMTP_PASSWORD = _get("SMTP_PASSWORD", "")
SMTP_SENDER_EMAIL = _get("SMTP_SENDER_EMAIL", "")
SMTP_SENDER_NAME = _get("SMTP_SENDER_NAME", "Rupaywala")
SMTP_USE_TLS = _get_bool("SMTP_USE_TLS", True)
SMTP_USE_SSL = _get_bool("SMTP_USE_SSL", False)
SMTP_TIMEOUT = _get_int("SMTP_TIMEOUT", 10)

# ------------------------------------------------------------------
# SMS (Fast2SMS)
# ------------------------------------------------------------------
FAST2SMS_API_KEY = _get("FAST2SMS_API_KEY", "")
FAST2SMS_SENDER_ID = _get("FAST2SMS_SENDER_ID", "")

# ------------------------------------------------------------------
# Google OAuth
#   GOOGLE_CLIENT_ID     - Web client id (used to verify the ID token audience)
#   GOOGLE_CLIENT_SECRET - used for server-side code exchange
# ------------------------------------------------------------------
GOOGLE_CLIENT_ID = _get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = _get("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = _get("GOOGLE_REDIRECT_URI", "")

# ------------------------------------------------------------------
# Payments (UPI)
# ------------------------------------------------------------------
UPI_ID = _get("UPI_ID", required=True)
UPI_PAYEE_NAME = _get("UPI_PAYEE_NAME", "Rupaywala")
QR_EXPIRY_MINUTES = _get_int("QR_EXPIRY_MINUTES", 10)
PAYMENT_MAX_SUBMIT_ATTEMPTS = _get_int("PAYMENT_MAX_SUBMIT_ATTEMPTS", 3)

# ------------------------------------------------------------------
# Maps - Mappls (primary) with Ola Maps as an optional fallback provider.
# MAPPLS_API_KEY is intentionally NOT hard-coded; supply it via .env.
# ------------------------------------------------------------------
MAP_PROVIDER = _get("MAP_PROVIDER", "mappls").strip().lower()  # mappls | ola | none

MAPPLS_API_KEY = _get("MAPPLS_API_KEY", "")
MAPPLS_CLIENT_ID = _get("MAPPLS_CLIENT_ID", "")
MAPPLS_CLIENT_SECRET = _get("MAPPLS_CLIENT_SECRET", "")
MAPPLS_BASE_URL = _get("MAPPLS_BASE_URL", "https://atlas.mappls.com/api/places")
MAPPLS_ROUTING_BASE_URL = _get("MAPPLS_ROUTING_BASE_URL", "https://atlas.mappls.com/api/routes")
MAPPLS_TIMEOUT = _get_float("MAPPLS_TIMEOUT", 10.0)

OLA_MAPS_API_KEY = _get("OLA_MAPS_API_KEY", "")
OLA_MAPS_BASE_URL = _get("OLA_MAPS_BASE_URL", "https://api.olamaps.io")
OLA_MAPS_TIMEOUT = _get_float("OLA_MAPS_TIMEOUT", 10.0)

MAP_CACHE_TTL_SECONDS = _get_int("MAP_CACHE_TTL_SECONDS", 600)
MAP_GEOCODE_CACHE_TTL_SECONDS = _get_int("MAP_GEOCODE_CACHE_TTL_SECONDS", 86400)

# ------------------------------------------------------------------
# Business defaults. These are only used to seed the database when the
# operational configuration table is empty - they are NOT the authority.
# ------------------------------------------------------------------
DEFAULT_DISTANCE_THRESHOLD_KM = _get_float("DEFAULT_DISTANCE_THRESHOLD_KM", 10.0)
DEFAULT_CHARGE_PER_KM = _get_float("DEFAULT_CHARGE_PER_KM", 5.0)
DEFAULT_TAX_PERCENT = _get_float("DEFAULT_TAX_PERCENT", 18.0)
# Round-trip factor: the field member travels to the customer and back.
DISTANCE_ROUND_TRIP_FACTOR = _get_float("DISTANCE_ROUND_TRIP_FACTOR", 2.0)

# ------------------------------------------------------------------
# CORS - comma separated list of allowed origins.
# ------------------------------------------------------------------
_cors_raw = _get("CORS_ALLOWED_ORIGINS", "*")
CORS_ALLOWED_ORIGINS: List[str] = [
    o.strip() for o in _cors_raw.split(",") if o.strip()
] or ["*"]

ALLOW_CREDENTIALS = _cors_raw != "*"

# ------------------------------------------------------------------
# Uploads
# ------------------------------------------------------------------
UPLOAD_DIR = _get("UPLOAD_DIR", "uploads")
MAX_UPLOAD_BYTES = _get_int("MAX_UPLOAD_BYTES", 5 * 1024 * 1024)
ALLOWED_PROOF_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".pdf")

# ------------------------------------------------------------------
# Debug / logging
# ------------------------------------------------------------------
DEBUG = _get_bool("DEBUG", False)


def maps_configured() -> bool:
    """True when the selected map provider has credentials available."""
    if MAP_PROVIDER == "mappls":
        return bool(MAPPLS_API_KEY and MAPPLS_CLIENT_ID and MAPPLS_CLIENT_SECRET)
    if MAP_PROVIDER == "ola":
        return bool(OLA_MAPS_API_KEY)
    return False
