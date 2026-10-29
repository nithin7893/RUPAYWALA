from app.models.field_member import FieldMember
from app.models.user import AccountStatus, User, UserRole
from app.utils.jwt_handler import create_access_token
from app.utils.security import verify_password
from tests.factories import make_admin, make_field_member


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token({"user_id": user.id, "role": user.role.value})
    return {"Authorization": f"Bearer {token}"}


def test_admin_can_create_approved_field_member(client, db):
    admin = make_admin(db)

    response = client.post(
        "/admin/field-members",
        headers=_auth_headers(admin),
        json={
            "username": "new.agent",
            "password": "AgentPass123",
            "full_name": "New Agent",
            "phone_number": "9000000008",
            "employee_code": "AGENT-008",
            "region": "Chennai",
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["username"] == "new.agent"
    assert body["phone_number"] == "9000000008"
    assert body["approval_status"] == "approved"
    assert body["is_active"] is True
    assert "password" not in body

    user = db.query(User).filter(User.username == "new.agent").one()
    member = db.query(FieldMember).filter(FieldMember.user_id == user.id).one()
    assert user.role == UserRole.field_member
    assert user.account_status == AccountStatus.active
    assert verify_password("AgentPass123", user.password_hash)
    assert member.approved_by == admin.id
    assert member.is_available is True


def test_admin_created_field_member_can_log_in_with_saved_credentials(client, db):
    admin = make_admin(db)
    create_response = client.post(
        "/admin/field-members",
        headers=_auth_headers(admin),
        json={
            "username": "login.agent",
            "password": "AgentPass123",
            "full_name": "Login Agent",
            "phone_number": "9000000011",
        },
    )
    assert create_response.status_code == 201

    user = db.query(User).filter(User.username == "login.agent").one()
    assert verify_password("AgentPass123", user.password_hash)

    identity_response = client.post(
        "/auth/check-user", json={"phone_number": "9000000011"}
    )
    assert identity_response.status_code == 200
    assert identity_response.json() == {
        "exists": True,
        "has_password": True,
        "next": "login",
    }

    login_response = client.post(
        "/auth/login",
        json={"identifier": "login.agent", "password": "AgentPass123"},
    )
    assert login_response.status_code == 200
    assert login_response.json()["role"] == "field_member"

    session_response = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {login_response.json()['access_token']}"},
    )
    assert session_response.status_code == 200
    assert session_response.json()["role"] == "field_member"
    assert session_response.json()["field_member"]["approval_status"] == "approved"


def test_admin_can_remove_field_member_access_without_deleting_history(client, db):
    admin = make_admin(db)
    member = make_field_member(db)
    user = db.get(User, member.user_id)

    response = client.delete(
        f"/admin/field-members/{member.id}",
        headers=_auth_headers(admin),
    )

    assert response.status_code == 200
    assert db.get(FieldMember, member.id) is not None
    db.refresh(member)
    db.refresh(user)
    assert user.account_status == AccountStatus.suspended
    assert member.approval_status.value == "suspended"
    assert member.is_available is False


def test_non_admin_cannot_create_field_member(client, db):
    from tests.factories import make_user

    customer = make_user(db)
    response = client.post(
        "/admin/field-members",
        headers=_auth_headers(customer),
        json={
            "username": "not.allowed",
            "password": "AgentPass123",
            "full_name": "Not Allowed",
            "phone_number": "9000000009",
        },
    )

    assert response.status_code == 403
