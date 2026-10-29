"""Email delivery service using SMTP.

Supports configurable SMTP (including Gmail). Never logs credentials, OTPs,
or full sensitive addresses. Fails safely if not configured.
"""

import logging
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr

from app import config

logger = logging.getLogger(__name__)


class EmailDeliveryError(Exception):
    """Raised when email delivery fails in a controlled manner."""


def _is_configured() -> bool:
    return bool(
        config.SMTP_HOST
        and config.SMTP_SENDER_EMAIL
    )


def send_otp_email(email: str, otp: str, purpose: str = "verification") -> bool:
    """Send a professional Rupaywala OTP email. Returns True only if sent."""
    if not _is_configured():
        logger.warning("SMTP not configured - email OTP not delivered")
        return False

    subject = "Your Rupaywala verification code"
    body = (
        "Hello,\n\n"
        f"Your Rupaywala verification code is: {otp}\n\n"
        f"This code is valid for {config.OTP_EXPIRY_MINUTES} minute(s).\n\n"
        "Security warning: Do not share this code with anyone. "
        "Rupaywala will never ask for your OTP by phone or message.\n\n"
        "If you did not request this code, please ignore this email.\n\n"
        "Regards,\n"
        f"{config.SMTP_SENDER_NAME} Team"
    )

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((config.SMTP_SENDER_NAME, config.SMTP_SENDER_EMAIL))
    msg["To"] = email
    msg.set_content(body)

    try:
        if config.SMTP_USE_SSL:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(
                config.SMTP_HOST,
                config.SMTP_PORT,
                context=context,
                timeout=config.SMTP_TIMEOUT,
            ) as server:
                if config.SMTP_USERNAME and config.SMTP_PASSWORD:
                    server.login(config.SMTP_USERNAME, config.SMTP_PASSWORD)
                server.send_message(msg)
        else:
            with smtplib.SMTP(
                config.SMTP_HOST,
                config.SMTP_PORT,
                timeout=config.SMTP_TIMEOUT,
            ) as server:
                if config.SMTP_USE_TLS:
                    context = ssl.create_default_context()
                    server.starttls(context=context)
                if config.SMTP_USERNAME and config.SMTP_PASSWORD:
                    server.login(config.SMTP_USERNAME, config.SMTP_PASSWORD)
                server.send_message(msg)
        return True
    except Exception as exc:
        logger.error("Email delivery failed for purpose=%s: %s", purpose, type(exc).__name__)
        return False
