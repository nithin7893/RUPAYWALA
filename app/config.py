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

# Test-only switch. When enabled, the application startup hook performs no
# schema creation and no reference-data seeding: the test suite owns both
# steps. It has no effect unless explicitly set, so development and production
# startup behaviour is unchanged. Never enable this in production.
TESTING = _get_bool("TESTING", False)
# Explicit environment name. Production must set ENVIRONMENT=production and
# provide all required production configuration. Development defaults are only
# for local use.
ENVIRONMENT = (_get("ENVIRONMENT", "development") or "development").strip().lower()
if ENVIRONMENT not in {"development", "production", "staging", "test"}:
    raise RuntimeError(
        "ENVIRONMENT must be one of: development, production, staging, test"
    )
IS_PRODUCTION = ENVIRONMENT == "production"

# ------------------------------------------------------------------
# JWT
# ------------------------------------------------------------------
JWT_SECRET_KEY = _get("JWT_SECRET_KEY", required=True)
JWT_ALGORITHM = _get("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = _get_int("ACCESS_TOKEN_EXPIRE_MINUTES", 60 * 12)

# ------------------------------------------------------------------
# Fixed quotations
#   A quote is a persisted, single-use, integrity-protected price promise.
#   It expires server-side after the configured number of minutes.
# ------------------------------------------------------------------
QUOTE_VALIDITY_MINUTES = _get_int("QUOTE_VALIDITY_MINUTES", 15)

# Quote signing is a separate cryptographic domain. There is deliberately no
# fallback to JWT_SECRET_KEY: reusing the access-token key would mean a token
# key compromise also compromises every quotation MAC (and vice versa).
#
# Validation happens in ``resolve_quote_signing_secret`` so it can be tested as
# a pure function and enforced when the quote service is initialised. The raw
# value is never logged or returned in an error message.
QUOTE_SIGNING_SECRET = _get("QUOTE_SIGNING_SECRET")

# Optional, explicit migration bridge for quotations issued before this
# revision. Only used to verify rows whose ``signature_version`` is 1. If it is
# not configured, legacy rows fail closed with a clear conflict instead of
# being silently accepted under the wrong key.
QUOTE_LEGACY_SIGNING_SECRET = _get("QUOTE_LEGACY_SIGNING_SECRET")


def resolve_quote_signing_secret(value: Optional[str]) -> str:
    """Return a usable quote signing secret or refuse to start.

    An unset, empty or whitespace-only value is unsafe: HMAC with an empty key
    is still a valid MAC that anyone can compute. The message never includes
    the configured value.
    """
    if value is None:
        raise RuntimeError(
            "Missing required environment variable: QUOTE_SIGNING_SECRET. "
            "Quotation signing must use a dedicated secret; JWT_SECRET_KEY is "
            "not used as a fallback."
        )
    if not value.strip():
        raise RuntimeError(
            "QUOTE_SIGNING_SECRET must not be empty or whitespace-only. "
            "Set a dedicated, random secret before starting the application."
        )
    return value

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
# Maps - Google Maps is the only active distance/location provider.
# Credentials are loaded from the environment and never hard-coded.
# ------------------------------------------------------------------
# Provider selection / Google-only mode. Google is always the active provider.
MAP_PROVIDER = _get("MAP_PROVIDER", "google").strip().lower()  # google

GOOGLE_MAPS_API_KEY = _get("GOOGLE_MAPS_API_KEY", "")
GOOGLE_MAPS_TIMEOUT = _get_float("GOOGLE_MAPS_TIMEOUT", 10.0)
GOOGLE_MAPS_RETRY_LIMIT = _get_int("GOOGLE_MAPS_RETRY_LIMIT", 2)
GOOGLE_MAPS_GEOCODE_CACHE_TTL = _get_int("GOOGLE_MAPS_GEOCODE_CACHE_TTL", 86400)
GOOGLE_MAPS_ROUTES_CACHE_TTL = _get_int("GOOGLE_MAPS_ROUTES_CACHE_TTL", 600)
GOOGLE_MAPS_PLACES_CACHE_TTL = _get_int("GOOGLE_MAPS_PLACES_CACHE_TTL", 86400)

# Legacy provider configuration retained for compatibility; not used as fallbacks.
MAPPLS_API_KEY = _get("MAPPLS_API_KEY", "")
MAPPLS_CLIENT_ID = _get("MAPPLS_CLIENT_ID", "")
MAPPLS_CLIENT_SECRET = _get("MAPPLS_CLIENT_SECRET", "")
MAPPLS_BASE_URL = _get("MAPPLS_BASE_URL", "https://atlas.mappls.com/api/places")
MAPPLS_ROUTING_BASE_URL = _get("MAPPLS_ROUTING_BASE_URL", "https://atlas.mappls.com/api/routes")
MAPPLS_TIMEOUT = _get_float("MAPPLS_TIMEOUT", 10.0)

OLA_MAPS_API_KEY = _get("OLA_MAPS_API_KEY", "")
OLA_MAPS_BASE_URL = _get("OLA_MAPS_BASE_URL", "https://api.olamaps.io")
OLA_MAPS_TIMEOUT = _get_float("OLA_MAPS_TIMEOUT", 10.0)

MAP_CACHE_TTL_SECONDS = _get_int("MAP_CACHE_TTL_SECONDS", GOOGLE_MAPS_ROUTES_CACHE_TTL)
MAP_GEOCODE_CACHE_TTL_SECONDS = _get_int(
    "MAP_GEOCODE_CACHE_TTL_SECONDS", GOOGLE_MAPS_GEOCODE_CACHE_TTL
)

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
# API documentation exposure
# ------------------------------------------------------------------
# Explicit configuration only. Production defaults to disabled.
EXPOSE_DOCS = _get_bool("EXPOSE_DOCS", not IS_PRODUCTION)

# ------------------------------------------------------------------
# CORS - comma separated list of allowed origins.
# ------------------------------------------------------------------
_cors_raw = (_get("CORS_ALLOWED_ORIGINS", "") or "").strip()
if _cors_raw:
    CORS_ALLOWED_ORIGINS: List[str] = [
        o.strip() for o in _cors_raw.split(",") if o.strip()
    ]
else:
    CORS_ALLOWED_ORIGINS = (
        []
        if IS_PRODUCTION
        else [
            "http://localhost:3000",
            "http://127.0.0.1:3000",
            "http://localhost:5173",
            "http://127.0.0.1:5173",
            "http://localhost:8080",
            "http://127.0.0.1:8080",
        ]
    )

_cors_has_wildcard = "*" in CORS_ALLOWED_ORIGINS
if _cors_has_wildcard and len(CORS_ALLOWED_ORIGINS) > 1:
    raise RuntimeError("CORS_ALLOWED_ORIGINS cannot include '*' with other origins")

# Development-only origin regex: allows localhost/127.0.0.1 on any numeric port
# (e.g. Flutter web random dev ports). Narrowly scoped - no other hosts.
_DEV_CORS_ORIGIN_REGEX = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
_cors_origin_regex_raw = (_get("CORS_ALLOWED_ORIGIN_REGEX", "") or "").strip()
if _cors_origin_regex_raw:
    CORS_ALLOWED_ORIGIN_REGEX: str | None = _cors_origin_regex_raw
else:
    CORS_ALLOWED_ORIGIN_REGEX = None if IS_PRODUCTION else _DEV_CORS_ORIGIN_REGEX

# Never allow credentials with wildcard origins. Regex is only used for
# narrowly-scoped dev localhost origins; credentials remain enabled.
ALLOW_CREDENTIALS = not _cors_has_wildcard
if _cors_has_wildcard and ALLOW_CREDENTIALS:
    raise RuntimeError("Wildcard CORS cannot be used when credentials are enabled")

# ------------------------------------------------------------------
# Host / HTTPS / proxy security
# ------------------------------------------------------------------
_trusted_hosts_raw = (_get("TRUSTED_HOSTS", "") or "").strip()
TRUSTED_HOSTS: List[str] = [
    h.strip() for h in _trusted_hosts_raw.split(",") if h.strip()
]
TRUST_PROXY_HEADERS = _get_bool("TRUST_PROXY_HEADERS", False)
TRUSTED_PROXY_IPS: List[str] = [
    h.strip()
    for h in (_get("TRUSTED_PROXY_IPS", "127.0.0.1") or "").split(",")
    if h.strip()
]
HTTPS_REDIRECT_ENABLED = _get_bool("HTTPS_REDIRECT_ENABLED", IS_PRODUCTION)
HSTS_ENABLED = _get_bool("HSTS_ENABLED", IS_PRODUCTION)
HSTS_MAX_AGE_SECONDS = _get_int("HSTS_MAX_AGE_SECONDS", 31536000)
CONTENT_SECURITY_POLICY = _get(
    "CONTENT_SECURITY_POLICY",
    "default-src 'self' https: data: blob:; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; "
    "style-src 'self' 'unsafe-inline' https:; "
    "img-src 'self' data: blob: https:; "
    "font-src 'self' data: https:; "
    "connect-src 'self' https:; "
    "frame-ancestors 'none'; object-src 'none'; base-uri 'self'",
)

# ------------------------------------------------------------------
# Uploads / document storage
# ------------------------------------------------------------------
UPLOAD_DIR = _get("UPLOAD_DIR", "uploads")
MAX_UPLOAD_BYTES = _get_int("MAX_UPLOAD_BYTES", 5 * 1024 * 1024)
ALLOWED_PROOF_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".pdf")
ALLOWED_DOCUMENT_MIME_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
}

# Storage provider: local (dev/migration) or s3-compatible private object storage.
STORAGE_PROVIDER = (_get("STORAGE_PROVIDER", "local") or "local").strip().lower()
STORAGE_BUCKET = _get("STORAGE_BUCKET", "")
STORAGE_REGION = _get("STORAGE_REGION", "")
STORAGE_ENDPOINT_URL = _get("STORAGE_ENDPOINT_URL", "")
STORAGE_ACCESS_KEY = _get("STORAGE_ACCESS_KEY", "")
STORAGE_SECRET_KEY = _get("STORAGE_SECRET_KEY", "")
STORAGE_USE_SSL = _get_bool("STORAGE_USE_SSL", True)
STORAGE_SIGNED_URL_EXPIRES_SECONDS = _get_int("STORAGE_SIGNED_URL_EXPIRES_SECONDS", 300)

# Malware scanning
MALWARE_SCAN_ENABLED = _get_bool("MALWARE_SCAN_ENABLED", False)
MALWARE_SCAN_PROVIDER = (_get("MALWARE_SCAN_PROVIDER", "clamav") or "clamav").strip().lower()
CLAMAV_HOST = _get("CLAMAV_HOST", "127.0.0.1")
CLAMAV_PORT = _get_int("CLAMAV_PORT", 3310)
CLAMAV_TIMEOUT_SECONDS = _get_int("CLAMAV_TIMEOUT_SECONDS", 30)

# Document retention (days). 0 disables automatic expiry.
DOCUMENT_RETENTION_DAYS = _get_int("DOCUMENT_RETENTION_DAYS", 0)

# ------------------------------------------------------------------
# Debug / logging
# ------------------------------------------------------------------
DEBUG = _get_bool("DEBUG", False)


def maps_configured() -> bool:
    """True when the active Google Maps provider has credentials available."""
    return bool(GOOGLE_MAPS_API_KEY)


_UNSAFE_SECRET_MARKERS = (
    "change-me",
    "changeme",
    "replace",
    "example",
    "default",
    "secret",
    "password",
    "admin",
    "test",
    "dev",
    "local",
)


def _looks_unsafe_secret(value: str | None) -> bool:
    if not value:
        return True
    v = value.strip()
    if len(v) < 32:
        return True
    lowered = v.lower()
    return any(marker in lowered for marker in _UNSAFE_SECRET_MARKERS)


def validate_runtime_configuration() -> None:
    """Fail fast on unsafe production configuration.

    Never include secret values in errors.
    """
    errors: list[str] = []

    if IS_PRODUCTION:
        if DEBUG:
            errors.append("DEBUG must be false in production")
        if TESTING:
            errors.append("TESTING must be false in production")
        if EXPOSE_DOCS:
            errors.append("EXPOSE_DOCS must be false in production")
        if not CORS_ALLOWED_ORIGINS:
            errors.append("CORS_ALLOWED_ORIGINS must be explicitly configured in production")
        if _cors_has_wildcard:
            errors.append("Wildcard CORS is not allowed in production")
        if CORS_ALLOWED_ORIGIN_REGEX:
            errors.append(
                "CORS_ALLOWED_ORIGIN_REGEX is not allowed in production; "
                "use explicit CORS_ALLOWED_ORIGINS"
            )
        if not TRUSTED_HOSTS:
            errors.append("TRUSTED_HOSTS must be explicitly configured in production")
        if any(h == "*" for h in TRUSTED_HOSTS):
            errors.append("Wildcard TRUSTED_HOSTS is not allowed in production")
        if ALLOW_CREDENTIALS and _cors_has_wildcard:
            errors.append("Wildcard CORS cannot be used when credentials are enabled")
        if _looks_unsafe_secret(JWT_SECRET_KEY):
            errors.append("JWT_SECRET_KEY is missing or unsafe for production")
        if _looks_unsafe_secret(QUOTE_SIGNING_SECRET):
            errors.append("QUOTE_SIGNING_SECRET is missing or unsafe for production")

    # Apply to all envs: wildcard+credentials is never safe.
    if _cors_has_wildcard and ALLOW_CREDENTIALS:
        errors.append("Wildcard CORS cannot be used when credentials are enabled")

    if errors:
        raise RuntimeError(
            "Unsafe runtime configuration: " + "; ".join(errors)
        )


validate_runtime_configuration()
