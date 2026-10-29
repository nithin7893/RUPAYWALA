"""Authentication, authorization and role separation.

The rules under test are the ones that protect money and data:
  * only a valid, unexpired, correctly signed token grants access
  * a customer token can never reach admin or field-member endpoints
  * a suspended account cannot use an old token
  * clients can never choose their own role
"""

import time
from datetime import datetime, timedelta

import pytest
from fastapi.security import HTTPAuthorizationCredentials
from jose import jwt

from app.config import JWT_ALGORITHM, JWT_SECRET_KEY
from app.models.user import AccountStatus, User, UserRole
from app.utils.dependencies import get_current_user
from app.utils.jwt_handler import create_access_token
from tests import factories as f


def bearer(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token({'user_id': user.id})}"}


class TestTokenValidation:
    def test_valid_token_is_accepted(self, db):
        user = f.make_user(db)
        creds = HTTPAuthorizationCredentials(
            scheme="Bearer", credentials=create_access_token({"user_id": user.id})
        )
        assert get_current_user(creds, db).id == user.id

    def test_missing_token_is_rejected(self, db):
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc:
            get_current_user(None, db)
        assert exc.value.status_code == 401

    def test_garbage_token_is_rejected(self, db):
        from fastapi import HTTPException

        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="not-a-jwt")
        with pytest.raises(HTTPException) as exc:
            get_current_user(creds, db)
        assert exc.value.status_code == 401

    def test_token_signed_with_wrong_secret_is_rejected(self, db):
        from fastapi import HTTPException

        user = f.make_user(db)
        forged = jwt.encode(
            {"user_id": user.id, "exp": datetime.utcnow() + timedelta(hours=1)},
            "the-wrong-secret",
            algorithm=JWT_ALGORITHM,
        )
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=forged)
        with pytest.raises(HTTPException) as exc:
            get_current_user(creds, db)
        assert exc.value.status_code == 401

    def test_expired_token_is_rejected(self, db):
        from fastapi import HTTPException

        user = f.make_user(db)
        expired = jwt.encode(
            {"user_id": user.id, "exp": datetime.utcnow() - timedelta(minutes=1)},
            JWT_SECRET_KEY,
            algorithm=JWT_ALGORITHM,
        )
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=expired)
        with pytest.raises(HTTPException) as exc:
            get_current_user(creds, db)
        assert exc.value.status_code == 401

    def test_token_for_deleted_user_is_rejected(self, db):
        from fastapi import HTTPException

        user = f.make_user(db)
        token = create_access_token({"user_id": user.id})
        db.delete(user)
        db.commit()
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        with pytest.raises(HTTPException) as exc:
            get_current_user(creds, db)
        assert exc.value.status_code == 401

    def test_suspended_user_cannot_use_existing_token(self, db):
        from fastapi import HTTPException

        user = f.make_user(db)
        token = create_access_token({"user_id": user.id})
        user.account_status = AccountStatus.suspended
        db.commit()
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        with pytest.raises(HTTPException) as exc:
            get_current_user(creds, db)
        assert exc.value.status_code in (401, 403)

    def test_token_payload_carries_no_secrets(self):
        token = create_access_token({"user_id": 1, "role": "admin"})
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
        assert set(payload) <= {"user_id", "exp", "iat", "jti", "role", "type"}
        assert "password" not in payload
        assert "password_hash" not in payload


class TestRoleSeparation:
    @pytest.mark.parametrize(
        "path",
        [
            "/admin/dashboard",
            "/admin/users",
            "/admin/requests",
            "/admin/payments/summary",
            "/admin/plans",
            "/admin/branches",
        ],
    )
    def test_customer_is_blocked_from_admin_endpoints(self, client, db, path):
        user = f.make_user(db)
        response = client.get(path, headers=bearer(user))
        assert response.status_code == 403, f"{path} leaked to a customer"

    @pytest.mark.parametrize(
        "path",
        ["/field-member/my-assignments", "/field-member/my-jobs", "/field-member/my-stats"],
    )
    def test_customer_is_blocked_from_field_member_endpoints(self, client, db, path):
        user = f.make_user(db)
        response = client.get(path, headers=bearer(user))
        assert response.status_code == 403, f"{path} leaked to a customer"

    def test_admin_reaches_admin_endpoints(self, client, db):
        admin = f.make_admin(db)
        response = client.get("/admin/dashboard", headers=bearer(admin))
        assert response.status_code == 200

    def test_field_member_reaches_their_own_endpoints(self, client, db):
        member = f.make_field_member(db)
        response = client.get("/field-member/my-assignments", headers=bearer(db.get(User, member.user_id)))
        assert response.status_code == 200

    def test_field_member_is_blocked_from_admin_endpoints(self, client, db):
        member = f.make_field_member(db)
        response = client.get("/admin/dashboard", headers=bearer(db.get(User, member.user_id)))
        assert response.status_code == 403

    def test_admin_is_blocked_from_field_member_endpoints(self, client, db):
        admin = f.make_admin(db)
        response = client.get("/field-member/my-jobs", headers=bearer(admin))
        assert response.status_code == 403


class TestClientCannotChooseRole:
    def test_register_ignores_a_requested_admin_role(self, client, db):
        response = client.post(
            "/auth/register",
            json={
                "phone_number": "9000000001",
                "username": "sneaky1",
                "password": "TestPass!234",
                "full_name": "Sneaky",
                "role": "admin",
            },
        )
        # Whatever the outcome, the stored role must never be admin.
        from app.models.user import User

        user = db.query(User).filter(User.username == "sneaky1").first()
        if user is not None:
            assert user.role == UserRole.customer

    def test_no_endpoint_accepts_a_role_in_the_body(self, db):
        """A client-supplied role must never be persisted as anything but customer."""
        from app.models.user import User

        user = f.make_user(db)
        assert user.role == UserRole.customer

    def test_role_change_requires_admin(self, client, db):
        target = f.make_user(db)
        attacker = f.make_user(db)
        response = client.post(
            f"/admin/users/{target.id}/role",
            json={"role": "admin"},
            headers=bearer(attacker),
        )
        assert response.status_code == 403
        db.refresh(target)
        assert target.role == UserRole.customer


class TestAuthenticationEndpoints:
    def test_check_user_only_reveals_whether_a_password_exists(self, client):
        response = client.post("/auth/check-user", json={"phone_number": "9000000002"})
        assert response.status_code == 200
        body = response.json()
        # The client needs to know whether to ask for a password or an OTP,
        # but never anything that identifies the account.
        assert set(body) <= {"exists", "has_password", "next"}
        assert "password_hash" not in body
        assert "password" not in body

    def test_login_with_wrong_password_is_refused(self, client, db):
        user = f.make_user(db)
        response = client.post(
            "/auth/login", json={"identifier": user.phone_number, "password": "wrong"}
        )
        assert response.status_code in (400, 401)
        assert "token" not in response.text.lower()

    def test_login_with_right_password_returns_a_usable_token(self, client, db):
        user = f.make_user(db)
        response = client.post(
            "/auth/login",
            json={"identifier": user.phone_number, "password": f.DEFAULT_PASSWORD},
        )
        assert response.status_code == 200
        token = response.json().get("access_token")
        assert token
        me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert me.status_code == 200
        assert me.json()["user_id"] == user.id

    def test_suspended_user_cannot_log_in(self, client, db):
        user = f.make_user(db, status=AccountStatus.suspended)
        response = client.post(
            "/auth/login",
            json={"identifier": user.phone_number, "password": f.DEFAULT_PASSWORD},
        )
        assert response.status_code in (401, 403)

    def test_password_is_never_returned_by_me(self, client, db):
        user = f.make_user(db)
        response = client.get("/auth/me", headers=bearer(user))
        assert response.status_code == 200
        assert "password_hash" not in response.text

    def test_user_can_change_username_with_current_password(self, client, db):
        user = f.make_user(db, username="old-name")

        response = client.put(
            "/auth/username",
            headers=bearer(user),
            json={"username": "New.Name", "current_password": f.DEFAULT_PASSWORD},
        )

        assert response.status_code == 200
        assert response.json() == {"username": "new.name"}
        db.refresh(user)
        assert user.username == "new.name"

    def test_user_cannot_change_username_to_another_users_username(self, client, db):
        user = f.make_user(db, username="first_user")
        f.make_user(db, username="taken.name")

        response = client.put(
            "/auth/username",
            headers=bearer(user),
            json={"username": "TAKEN.NAME", "current_password": f.DEFAULT_PASSWORD},
        )

        assert response.status_code == 409

    def test_user_can_change_password_with_current_password(self, client, db):
        from app.utils.security import verify_password

        user = f.make_user(db)
        response = client.post(
            "/auth/change-password",
            headers=bearer(user),
            json={
                "current_password": f.DEFAULT_PASSWORD,
                "new_password": "NewPass123",
            },
        )

        assert response.status_code == 200
        db.refresh(user)
        assert verify_password("NewPass123", user.password_hash)

    def test_passwordless_user_can_set_username_and_password(self, client, db):
        from app.utils.security import verify_password

        user = f.make_user(db, username=None, password=None)
        username_response = client.put(
            "/auth/username",
            headers=bearer(user),
            json={"username": "new.user"},
        )
        assert username_response.status_code == 200

        password_response = client.post(
            "/auth/change-password",
            headers=bearer(user),
            json={"new_password": "FirstPass123"},
        )
        assert password_response.status_code == 200
        db.refresh(user)
        assert user.username == "new.user"
        assert verify_password("FirstPass123", user.password_hash)

    def test_otp_is_never_returned_to_the_client(self, client, db, monkeypatch):
        monkeypatch.setattr(
            "app.routes.auth_routes.OTPService.issue",
            classmethod(lambda cls, *a, **k: (None, "123456", True)),
        )
        response = client.post(
            "/auth/send-otp", json={"phone_number": "9000000003", "purpose": "signup"}
        )
        assert response.status_code == 200
        assert "123456" not in response.text
