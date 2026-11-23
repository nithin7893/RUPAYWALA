"""C-01 regression: email OTP login must verify the submitted, single-use code.

Previously /auth/email-login trusted the existence of any older OTP row marked
``verified=True``, skipped code verification entirely, and email verification
never marked a code as used. These tests pin the corrected behaviour without
logging or asserting plaintext OTP values beyond the locally generated code.
"""

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from jose import jwt

from app.config import JWT_ALGORITHM, JWT_SECRET_KEY
from app.database import SessionLocal, get_db
from app.main import app
from app.models.otp_verification import OTPPurpose, OTPVerification
from app.utils import rate_limit
from app.utils.security import hash_otp
from tests import factories as f

CODE = "135790"
OTHER_CODE = "246801"
ARBITRARY_CODE = "000000"


@pytest.fixture(autouse=True)
def _clear_rate_limits():
    """Keep the in-process limiter from leaking state between these tests."""
    rate_limit.reset()
    yield
    rate_limit.reset()


def _email(label: str) -> str:
    return f"c01-{label}-{uuid.uuid4().hex[:8]}@example.com"


def _user_with_email(db, email: str):
    user = f.make_user(db)
    user.email = email
    user.email_verified = False
    db.commit()
    db.refresh(user)
    return user


def _otp(
    db,
    email: str,
    code: str,
    *,
    purpose: OTPPurpose = OTPPurpose.email_login,
    expires_at: datetime | None = None,
    verified: bool = False,
    is_used: bool = False,
    attempts: int = 0,
) -> OTPVerification:
    record = OTPVerification(
        email=email,
        otp_hash=hash_otp(code),
        purpose=purpose,
        expires_at=expires_at or datetime.utcnow() + timedelta(minutes=5),
        verified=verified,
        is_used=is_used,
        attempts=attempts,
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return record


def _login(client, email: str, code: str):
    return client.post("/auth/email-login", json={"email": email, "otp": code})


def _claims(token: str) -> dict:
    return jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])


class TestC01EmailLogin:
    def test_correct_otp_succeeds_and_is_consumed(self, client, db):
        email = _email("correct")
        user = _user_with_email(db, email)
        record = _otp(db, email, CODE)

        response = _login(client, email, CODE)

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["user_id"] == user.id
        claims = _claims(body["access_token"])
        assert claims["user_id"] == user.id
        assert claims["tv"] == user.token_version
        assert (
            client.get(
                "/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"}
            ).status_code
            == 200
        )
        db.refresh(record)
        db.refresh(user)
        assert record.verified is True
        assert record.is_used is True
        assert user.email_verified is True
        assert user.is_verified is True
        assert user.auth_provider.value == "email_otp"
        assert user.last_login_at is not None

    def test_incorrect_otp_fails_without_authenticating(self, client, db):
        email = _email("incorrect")
        user = _user_with_email(db, email)
        record = _otp(db, email, CODE)

        response = _login(client, email, OTHER_CODE)

        assert response.status_code == 400
        assert "access_token" not in response.json()
        assert response.json()["detail"] == "Invalid or expired verification code"
        db.refresh(record)
        db.refresh(user)
        assert record.attempts == 1
        assert record.is_used is False
        assert user.email_verified is False

    def test_arbitrary_otp_fails_even_with_prior_verified_record(self, client, db):
        """The exact C-01 takeover path must stay closed."""
        email = _email("arbitrary")
        user = _user_with_email(db, email)
        # Legacy shape left behind by the old verify_email: verified but unused.
        stale = _otp(db, email, CODE, verified=True, is_used=False)

        response = _login(client, email, ARBITRARY_CODE)

        assert response.status_code == 400
        assert "access_token" not in response.json()
        assert response.json()["detail"] == "Invalid or expired verification code"
        db.refresh(user)
        assert user.email_verified is False
        db.refresh(stale)
        assert stale.attempts == 1

    def test_expired_otp_fails(self, client, db):
        email = _email("expired")
        user = _user_with_email(db, email)
        record = _otp(db, email, CODE, expires_at=datetime.utcnow() - timedelta(minutes=1))

        response = _login(client, email, CODE)

        assert response.status_code == 400
        assert "access_token" not in response.json()
        db.refresh(record)
        db.refresh(user)
        assert record.is_used is True
        assert user.email_verified is False

    def test_previously_consumed_otp_fails(self, client, db):
        email = _email("consumed")
        user = _user_with_email(db, email)
        _otp(db, email, CODE, verified=True, is_used=True)

        response = _login(client, email, CODE)

        assert response.status_code == 400
        assert "access_token" not in response.json()
        db.refresh(user)
        assert user.email_verified is False

    def test_otp_from_another_account_fails(self, client, db):
        email_a = _email("account-a")
        email_b = _email("account-b")
        user_a = _user_with_email(db, email_a)
        _user_with_email(db, email_b)
        record_a = _otp(db, email_a, CODE)
        _otp(db, email_b, OTHER_CODE, verified=True, is_used=False)

        wrong = _login(client, email_a, OTHER_CODE)
        assert wrong.status_code == 400
        assert "access_token" not in wrong.json()

        right = _login(client, email_a, CODE)
        assert right.status_code == 200, right.text
        assert right.json()["user_id"] == user_a.id
        db.refresh(record_a)
        assert record_a.is_used is True

    def test_otp_from_another_purpose_fails(self, client, db):
        email = _email("purpose")
        user = _user_with_email(db, email)
        signup_record = _otp(db, email, CODE, purpose=OTPPurpose.email_signup)

        response = _login(client, email, CODE)

        assert response.status_code == 400
        assert "access_token" not in response.json()
        db.refresh(signup_record)
        db.refresh(user)
        assert signup_record.is_used is False
        assert user.email_verified is False

    def test_repeated_submission_fails(self, client, db):
        email = _email("replay")
        _user_with_email(db, email)
        _otp(db, email, CODE)

        first = _login(client, email, CODE)
        second = _login(client, email, CODE)

        assert first.status_code == 200, first.text
        assert second.status_code == 400
        assert "access_token" not in second.json()

    def test_concurrent_reuse_cannot_authenticate_twice(self, db):
        email = _email("concurrent")
        user = _user_with_email(db, email)
        _otp(db, email, CODE)

        original_override = app.dependency_overrides.get(get_db)

        def session_per_request():
            session = SessionLocal()
            try:
                yield session
            finally:
                session.close()

        def post_once():
            with TestClient(app) as test_client:
                return test_client.post(
                    "/auth/email-login", json={"email": email, "otp": CODE}
                )

        app.dependency_overrides[get_db] = session_per_request
        rate_limit.reset()
        try:
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(post_once) for _ in range(2)]
                responses = [future.result(timeout=30) for future in futures]
        finally:
            if original_override is None:
                app.dependency_overrides.pop(get_db, None)
            else:
                app.dependency_overrides[get_db] = original_override
            rate_limit.reset()

        assert sorted(response.status_code for response in responses) == [200, 400]
        with SessionLocal() as session:
            record = (
                session.query(OTPVerification)
                .filter(OTPVerification.email == email)
                .one()
            )
            assert record.is_used is True
            assert record.verified is True

    def test_missing_otp_is_rejected_by_schema(self, client, db):
        email = _email("missing")
        _user_with_email(db, email)
        _otp(db, email, CODE)

        response = client.post("/auth/email-login", json={"email": email})

        assert response.status_code == 422
        assert "access_token" not in response.json()

    def test_existing_email_verification_and_registration_still_work(self, client, db):
        email = _email("verify")
        username = f"c01user{uuid.uuid4().hex[:8]}"
        signup_record = _otp(db, email, CODE, purpose=OTPPurpose.email_signup)

        verification = client.post(
            "/auth/verify-email-otp", json={"email": email, "otp": CODE}
        )
        assert verification.status_code == 200, verification.text
        assert verification.json()["next"] == "register"
        db.refresh(signup_record)
        assert signup_record.verified is True and signup_record.is_used is True

        replay = client.post(
            "/auth/verify-email-otp", json={"email": email, "otp": CODE}
        )
        assert replay.status_code == 400

        registration = client.post(
            "/auth/register/email",
            json={"email": email, "username": username, "password": "TestPass123"},
        )
        assert registration.status_code == 201, registration.text
        assert registration.json()["user_id"] > 0

        _otp(db, email, OTHER_CODE, purpose=OTPPurpose.email_login)
        login = _login(client, email, OTHER_CODE)
        assert login.status_code == 200, login.text
        assert login.json()["user_id"] == registration.json()["user_id"]

    def test_email_login_token_obeys_token_version_invalidation(self, client, db):
        email = _email("token-version")
        user = _user_with_email(db, email)
        _otp(db, email, CODE)

        response = _login(client, email, CODE)
        assert response.status_code == 200, response.text
        token = response.json()["access_token"]
        assert _claims(token)["tv"] == user.token_version

        user.token_version += 1
        db.commit()

        stale = client.get(
            "/auth/me", headers={"Authorization": f"Bearer {token}"}
        )
        assert stale.status_code == 401
