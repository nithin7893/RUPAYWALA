"""Outbound SMS delivery (Fast2SMS DLT route)."""

import logging
import os

import requests

from app.config import FAST2SMS_API_KEY, FAST2SMS_SENDER_ID

logger = logging.getLogger(__name__)

FAST2SMS_URL = "https://www.fast2sms.com/dev/bulkV2"


def send_otp_sms(phone_number: str, otp: str) -> bool:
    """Deliver an OTP by SMS. Returns True when the gateway accepted it."""
    if not FAST2SMS_API_KEY:
        logger.warning("FAST2SMS_API_KEY is not configured - OTP not delivered over SMS")
        return False

    params = {
        "route": "dlt",
        "sender_id": FAST2SMS_SENDER_ID,
        "message": f"{otp} is your Rupaywala verification code. Valid for a few minutes. Do not share it.",
        "variables_values": otp,
        "flash": 0,
        "numbers": phone_number,
    }

    try:
        resp = requests.get(
            FAST2SMS_URL,
            params=params,
            headers={"authorization": FAST2SMS_API_KEY},
            timeout=10,
        )
        data = resp.json()
        if data.get("return"):
            return True
        logger.warning("Fast2SMS rejected the message: %s", data.get("message"))
        return False
    except Exception as exc:  # pragma: no cover - network dependent
        logger.error("Fast2SMS request failed: %s", exc)
        return False


def normalise_phone(phone: str) -> str:
    """Strip spaces/dashes and drop a leading country code."""
    cleaned = "".join(ch for ch in phone if ch.isdigit())
    if len(cleaned) == 12 and cleaned.startswith("91"):
        cleaned = cleaned[2:]
    if len(cleaned) == 11 and cleaned.startswith("0"):
        cleaned = cleaned[1:]
    return cleaned


def is_valid_phone(phone: str) -> bool:
    p = normalise_phone(phone)
    return len(p) == 10 and p[0] in "6789" and p.isdigit()
