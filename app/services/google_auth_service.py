"""
Google (Gmail) sign-in.

The mobile app obtains a Google ID token and posts it here. The token is
verified server-side against Google's public keys, the audience is checked
against the configured client id, and only then is an account created or linked.

Email is therefore never "accepted because it looked like an email" - it has
been cryptographically proved by Google.
"""

import logging
from dataclasses import dataclass

import httpx
from fastapi import HTTPException
from jose import jwt

from app.config import GOOGLE_CLIENT_ID

logger = logging.getLogger(__name__)

GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
GOOGLE_ISSUER = "accounts.google.com"

_jwks_cache: dict | None = None


@dataclass(frozen=True)
class GoogleIdentity:
    sub: str
    email: str
    email_verified: bool
    name: str | None = None
    picture: str | None = None


class GoogleAuthService:
    @staticmethod
    def is_configured() -> bool:
        return bool(GOOGLE_CLIENT_ID)

    @staticmethod
    def _fetch_jwks() -> dict:
        global _jwks_cache
        if _jwks_cache is not None:
            return _jwks_cache
        try:
            response = httpx.get(GOOGLE_JWKS_URL, timeout=10.0)
            response.raise_for_status()
            _jwks_cache = response.json()
        except Exception as exc:  # pragma: no cover - network dependent
            logger.error("Could not fetch Google signing keys: %s", exc)
            raise HTTPException(
                status_code=503, detail="Google sign-in is temporarily unavailable"
            )
        return _jwks_cache

    @classmethod
    def verify_id_token(cls, id_token: str) -> GoogleIdentity:
        if not cls.is_configured():
            raise HTTPException(
                status_code=503,
                detail="Google sign-in is not configured on this server",
            )
        if not id_token:
            raise HTTPException(status_code=400, detail="A Google ID token is required")

        try:
            jwks = cls._fetch_jwks()
            unverified_header = jwt.get_unverified_header(id_token)
            claims = jwt.decode(
                id_token,
                jwks,
                algorithms=["RS256"],
                audience=GOOGLE_CLIENT_ID,
                access_token=None,
            )
        except HTTPException:
            raise
        except Exception as exc:
            logger.warning("Google ID token rejected: %s", exc)
            raise HTTPException(status_code=401, detail="Google sign-in could not be verified")

        if claims.get("iss") not in (GOOGLE_ISSUER, f"https://{GOOGLE_ISSUER}"):
            raise HTTPException(status_code=401, detail="Google sign-in could not be verified")
        if not claims.get("email_verified"):
            raise HTTPException(
                status_code=403,
                detail="Your Google account email is not verified. Please verify it first.",
            )

        return GoogleIdentity(
            sub=str(claims.get("sub")),
            email=str(claims.get("email", "")).lower(),
            email_verified=bool(claims.get("email_verified")),
            name=claims.get("name"),
            picture=claims.get("picture"),
        )

    @classmethod
    def verify_access_token(cls, access_token: str) -> GoogleIdentity:
        """Fallback path: introspect an OAuth access token via tokeninfo."""
        if not cls.is_configured():
            raise HTTPException(
                status_code=503, detail="Google sign-in is not configured on this server"
            )
        try:
            response = httpx.get(
                GOOGLE_TOKENINFO_URL, params={"access_token": access_token}, timeout=10.0
            )
        except Exception as exc:  # pragma: no cover - network dependent
            logger.error("Google tokeninfo request failed: %s", exc)
            raise HTTPException(
                status_code=503, detail="Google sign-in is temporarily unavailable"
            )

        if response.status_code != 200:
            raise HTTPException(status_code=401, detail="Google sign-in could not be verified")

        data = response.json()
        if data.get("aud") != GOOGLE_CLIENT_ID:
            raise HTTPException(status_code=401, detail="Google sign-in could not be verified")

        email_verified = data.get("email_verified")
        if isinstance(email_verified, str):
            email_verified = email_verified.lower() == "true"
        if not bool(email_verified):
            raise HTTPException(
                status_code=403, detail="Your Google account email is not verified"
            )

        sub = str(data.get("sub") or "").strip()
        email = str(data.get("email") or "").strip().lower()
        if not sub or "@" not in email:
            raise HTTPException(status_code=401, detail="Google sign-in could not be verified")

        return GoogleIdentity(
            sub=sub,
            email=email,
            email_verified=True,
            name=data.get("name"),
            picture=data.get("picture"),
        )
