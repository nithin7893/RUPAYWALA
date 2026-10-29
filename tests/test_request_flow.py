"""The customer request flow end to end, through the HTTP API.

This is the regression net for the path a real customer walks: sign in, see a
balance, ask for a service, pay any extra charge, watch it get assigned,
started and completed - with a visit credit consumed exactly once.
"""

import pytest
from fastapi.testclient import TestClient

from app.models.service_request import RequestStatus, ServiceRequest
from app.models.user_subscription import UserSubscription
from app.utils.jwt_handler import create_access_token
from tests import factories as f


def bearer(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token({'user_id': user.id})}"}


def body(response):
    return response.json()


def _assign(db, request, member):
    """Give a field member the active assignment the routes require."""
    from app.models.request_assignment import AssignmentStatus, RequestAssignment

    assignment = RequestAssignment(
        request_id=request.id,
        field_member_id=member.id,
        status=AssignmentStatus.active,
    )
    db.add(assignment)
    db.commit()
    return assignment


class TestRequestCreation:
    PAYLOAD_EXTRA = {
        "request_type": "claim",
        "description": "Water leak",
        "customer_address": "1 Test Street",
        "customer_latitude": 13.0827,
        "customer_longitude": 80.2707,
    }

    def _payload(self, db, user, **overrides):
        payload = dict(
            policy_id=f.make_policy(db, user).id,
            branch_id=f.make_branch(db).id,
            service_type_id=f.make_service_type(db).id,
            **self.PAYLOAD_EXTRA,
        )
        payload.update(overrides)
        return payload

    def test_customer_creates_a_request(self, client, db, stub_distance):
        stub_distance()
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        f.make_subscription(db, user, plan)

        response = client.post(
            "/service/request", json=self._payload(db, user), headers=bearer(user)
        )
        assert response.status_code in (200, 201), response.text
        assert db.query(ServiceRequest).filter(ServiceRequest.user_id == user.id).count() == 1

    def test_request_does_not_consume_a_visit(self, client, db, stub_distance):
        stub_distance()
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        sub = f.make_subscription(db, user, plan)

        client.post("/service/request", json=self._payload(db, user), headers=bearer(user))
        db.refresh(sub)
        assert sub.used_visits == 0
        assert sub.remaining_visits == 4

    def test_request_without_a_subscription_is_refused(self, client, db, stub_distance):
        stub_distance()
        user = f.make_user(db)
        response = client.post(
            "/service/request", json=self._payload(db, user), headers=bearer(user)
        )
        assert response.status_code in (400, 403, 409)
        assert (
            db.query(ServiceRequest).filter(ServiceRequest.user_id == user.id).count() == 0
        )

    def test_request_for_another_customers_policy_is_refused(self, client, db, stub_distance):
        stub_distance()
        owner = f.make_user(db)
        attacker = f.make_user(db)
        plan = f.make_plan(db)
        f.make_subscription(db, attacker, plan)
        victim_policy = f.make_policy(db, owner)

        response = client.post(
            "/service/request",
            json=self._payload(db, attacker, policy_id=victim_policy.id),
            headers=bearer(attacker),
        )
        assert response.status_code in (400, 403, 404), "a policy leaked across accounts"

    def test_anonymous_user_cannot_create_a_request(self, client, db, stub_distance):
        stub_distance()
        user = f.make_user(db)
        response = client.post("/service/request", json=self._payload(db, user))
        assert response.status_code == 401


class TestRequestVisibility:
    def test_customer_cannot_read_another_customers_request(self, client, db):
        owner = f.make_user(db)
        other = f.make_user(db)
        request = f.make_request(db, owner)

        response = client.get(f"/service/request/{request.id}", headers=bearer(other))
        assert response.status_code in (403, 404), "a request leaked across accounts"

    def test_owner_can_read_their_own_request(self, client, db):
        owner = f.make_user(db)
        request = f.make_request(db, owner)
        response = client.get(f"/service/request/{request.id}", headers=bearer(owner))
        assert response.status_code == 200

    def test_customer_cannot_cancel_someone_elses_request(self, client, db):
        owner = f.make_user(db)
        other = f.make_user(db)
        request = f.make_request(db, owner)
        response = client.post(
            f"/service/request/{request.id}/cancel",
            json={"reason": "not mine"},
            headers=bearer(other),
        )
        assert response.status_code in (403, 404)
        db.refresh(request)
        assert request.status != RequestStatus.cancelled


class TestAssignmentAndCompletion:
    def test_admin_assigns_a_field_member(self, client, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=3)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(db, user, status=RequestStatus.waiting_for_assignment, subscription=sub)
        member = f.make_field_member(db)
        admin = f.make_admin(db)

        response = client.post(
            "/admin/assign-field-member",
            json={"request_id": request.id, "field_member_id": member.id},
            headers=bearer(admin),
        )
        assert response.status_code in (200, 201), response.text
        db.refresh(request)
        assert request.status == RequestStatus.assigned

    def test_a_customer_cannot_assign_a_field_member(self, client, db):
        user = f.make_user(db)
        request = f.make_request(db, user)
        member = f.make_field_member(db)
        response = client.post(
            "/admin/assign-field-member",
            json={"request_id": request.id, "field_member_id": member.id},
            headers=bearer(user),
        )
        assert response.status_code == 403

    def test_an_unapproved_field_member_cannot_be_assigned(self, client, db):
        user = f.make_user(db)
        request = f.make_request(db, user)
        member = f.make_field_member(db, approved=False)
        admin = f.make_admin(db)
        response = client.post(
            "/admin/assign-field-member",
            json={"request_id": request.id, "field_member_id": member.id},
            headers=bearer(admin),
        )
        assert response.status_code in (400, 409)

    def test_full_journey_consumes_exactly_one_visit(self, client, db, stub_distance):
        stub_distance()
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=3)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(
            db, user, status=RequestStatus.waiting_for_assignment, subscription=sub
        )
        member = f.make_field_member(db)
        admin = f.make_admin(db)

        assert client.post(
            "/admin/assign-field-member",
            json={"request_id": request.id, "field_member_id": member.id},
            headers=bearer(admin),
        ).status_code in (200, 201)

        member_user = db.get(type(member.user_id and user).__mro__[0], 1) if False else None
        from app.models.user import User

        member_user = db.get(User, member.user_id)

        # start-request / complete-request take request_id as a query parameter
        # and completion_notes as form data.
        assert client.post(
            f"/field-member/start-request?request_id={request.id}", headers=bearer(member_user)
        ).status_code == 200

        assert client.post(
            f"/field-member/complete-request?request_id={request.id}",
            data={"completion_notes": "Fixed the leak"},
            headers=bearer(member_user),
        ).status_code == 200

        db.refresh(request)
        db.refresh(sub)
        assert request.status == RequestStatus.completed
        assert request.visit_consumed is True
        assert sub.used_visits == 1
        assert sub.remaining_visits == 2

    def test_completing_twice_does_not_double_consume(self, client, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=3)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(
            db, user, status=RequestStatus.in_progress, subscription=sub
        )
        member = f.make_field_member(db)
        from app.models.user import User

        member_user = db.get(User, member.user_id)
        _assign(db, request, member)

        client.post(
            f"/field-member/complete-request?request_id={request.id}",
            data={"completion_notes": "Fixed the leak"},
            headers=bearer(member_user),
        )
        db.refresh(sub)
        used_after_first = sub.used_visits

        client.post(
            f"/field-member/complete-request?request_id={request.id}",
            data={"completion_notes": "Fixed again"},
            headers=bearer(member_user),
        )
        db.refresh(sub)
        assert sub.used_visits == used_after_first, "a repeated completion must not consume a second visit"

    def test_a_field_member_cannot_complete_someone_elses_job(self, client, db):
        owner = f.make_user(db)
        plan = f.make_plan(db)
        sub = f.make_subscription(db, owner, plan)
        request = f.make_request(db, owner, status=RequestStatus.in_progress, subscription=sub)
        intruder = f.make_field_member(db)
        from app.models.user import User

        response = client.post(
            f"/field-member/complete-request?request_id={request.id}",
            data={"completion_notes": "Not my job"},
            headers=bearer(db.get(User, intruder.user_id)),
        )
        assert response.status_code in (403, 404)
        db.refresh(sub)
        assert sub.used_visits == 0


class TestBalanceEndpoint:
    def test_balance_is_visible_to_the_owner(self, client, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=6)
        f.make_subscription(db, user, plan, used_visits=2)
        response = client.get("/subscriptions/visits/balance", headers=bearer(user))
        assert response.status_code == 200
        data = body(response)
        assert data["remaining_visits"] == 4
        assert data["total_visits"] == 6

    def test_balance_requires_authentication(self, client, db):
        assert client.get("/subscriptions/visits/balance").status_code == 401

    def test_plans_are_listed(self, client, db):
        f.make_plan(db, plan_name="Basic")
        response = client.get("/subscriptions/plans", headers=bearer(f.make_user(db)))
        assert response.status_code == 200
        assert isinstance(body(response), list)

    def test_plan_with_null_features_does_not_break_the_response(self, client, db):
        plan = f.make_plan(db, features=[])
        plan.features = None
        db.commit()
        response = client.get("/subscriptions/plans", headers=bearer(f.make_user(db)))
        assert response.status_code == 200
        assert body(response)[0]["features"] == []
