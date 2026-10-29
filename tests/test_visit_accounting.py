"""Visit credit accounting and request lifecycle.

The money-critical invariants:
  * a visit is consumed exactly once, and only on completion
  * requesting, paying or assigning never consumes a visit
  * a cancelled request that never completed never consumes a visit
  * the ledger always reconciles with the subscription counters
"""

from datetime import date, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.models.service_request import RequestStatus, ServiceRequest
from app.models.user_subscription import SubscriptionStatus
from app.models.visit_ledger import VisitEntryType, VisitLedgerEntry
from app.services.request_status_service import (
    REQUEST_TRANSITIONS,
    RequestStatusService,
)
from app.services.visit_service import VisitService
from tests import factories as f


class TestBalance:
    def test_no_subscription_reports_no_balance(self, db):
        user = f.make_user(db)
        balance = VisitService.get_balance(db, user.id)
        assert balance["has_active_subscription"] is False
        assert balance["remaining_visits"] == 0

    def test_balance_reflects_remaining_visits(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        f.make_subscription(db, user, plan, used_visits=1)
        balance = VisitService.get_balance(db, user.id)
        assert balance["total_visits"] == 4
        assert balance["used_visits"] == 1
        assert balance["remaining_visits"] == 3

    def test_never_reports_negative_remaining(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=2)
        f.make_subscription(db, user, plan, used_visits=5)
        assert VisitService.get_balance(db, user.id)["remaining_visits"] == 0

    def test_expired_subscription_is_transitioned_lazily(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        sub = f.make_subscription(db, user, plan)
        sub.end_date = date.today() - timedelta(days=1)
        db.commit()

        assert VisitService.get_active_subscription(db, user.id) is None
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.expired

    def test_not_yet_started_subscription_is_not_usable(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        sub = f.make_subscription(db, user, plan)
        sub.start_date = date.today() + timedelta(days=3)
        db.commit()
        assert VisitService.get_active_subscription(db, user.id) is None

    def test_cannot_request_without_a_subscription(self, db):
        user = f.make_user(db)
        allowed, reason, _ = VisitService.can_request_service(db, user.id)
        assert allowed is False
        assert "subscription" in reason.lower()

    def test_cannot_request_when_all_visits_are_used(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=2)
        f.make_subscription(db, user, plan, used_visits=2)
        allowed, reason, _ = VisitService.can_request_service(db, user.id)
        assert allowed is False
        assert "renew" in reason.lower()

    def test_can_request_with_remaining_visits(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=3)
        f.make_subscription(db, user, plan, used_visits=1)
        allowed, reason, _ = VisitService.can_request_service(db, user.id)
        assert allowed is True
        assert reason == ""


class TestConsumeExactlyOnce:
    def _completed_request(self, db, total=3, used=0):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=total)
        sub = f.make_subscription(db, user, plan, used_visits=used)
        request = f.make_request(db, user, status=RequestStatus.in_progress, subscription=sub)
        return user, sub, request

    def test_completion_consumes_one_visit(self, db):
        _, sub, request = self._completed_request(db)
        assert VisitService.consume_for_request(db, request) is True
        db.flush()
        assert sub.used_visits == 1
        assert sub.remaining_visits == 2
        assert request.visit_consumed is True

    def test_second_completion_does_not_double_charge(self, db):
        _, sub, request = self._completed_request(db)
        assert VisitService.consume_for_request(db, request) is True
        assert VisitService.consume_for_request(db, request) is False
        db.flush()
        assert sub.used_visits == 1, "a repeat completion must not deduct a second visit"

    def test_repeat_is_blocked_even_if_the_flag_was_lost(self, db):
        """The ledger, not just the flag, protects against a double deduction."""
        _, sub, request = self._completed_request(db)
        VisitService.consume_for_request(db, request)
        request.visit_consumed = False  # simulate a lost flag / retry
        db.flush()

        assert VisitService.consume_for_request(db, request) is False
        db.flush()
        assert sub.used_visits == 1

    def test_ledger_row_is_written(self, db):
        _, _, request = self._completed_request(db)
        VisitService.consume_for_request(db, request)
        db.flush()
        entries = (
            db.query(VisitLedgerEntry)
            .filter(VisitLedgerEntry.service_request_id == request.id)
            .all()
        )
        assert len(entries) == 1
        entry = entries[0]
        assert entry.entry_type == VisitEntryType.consumed
        assert entry.quantity == -1

    def test_completion_without_subscription_is_refused(self, db):
        user = f.make_user(db)
        request = f.make_request(db, user, status=RequestStatus.in_progress)
        with pytest.raises(HTTPException) as exc:
            VisitService.consume_for_request(db, request)
        assert exc.value.status_code == 409

    def test_completion_on_inactive_subscription_is_refused(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        sub = f.make_subscription(db, user, plan, status=SubscriptionStatus.cancelled)
        request = f.make_request(db, user, status=RequestStatus.in_progress, subscription=sub)
        with pytest.raises(HTTPException) as exc:
            VisitService.consume_for_request(db, request)
        assert exc.value.status_code == 409

    def test_completion_with_no_visits_left_is_refused(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=1)
        sub = f.make_subscription(db, user, plan, used_visits=1)
        request = f.make_request(db, user, status=RequestStatus.in_progress, subscription=sub)
        with pytest.raises(HTTPException) as exc:
            VisitService.consume_for_request(db, request)
        assert exc.value.status_code == 409
        assert "no visits" in exc.value.detail.lower()

    def test_each_request_consumes_its_own_credit(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=3)
        sub = f.make_subscription(db, user, plan)
        first = f.make_request(db, user, status=RequestStatus.in_progress, subscription=sub)
        second = f.make_request(db, user, status=RequestStatus.in_progress, subscription=sub)

        VisitService.consume_for_request(db, first)
        VisitService.consume_for_request(db, second)
        db.flush()
        assert sub.used_visits == 2
        assert sub.remaining_visits == 1


class TestNoVisitSpentBeforeCompletion:
    @pytest.mark.parametrize(
        "status",
        [
            RequestStatus.requested,
            RequestStatus.payment_pending,
            RequestStatus.payment_completed,
            RequestStatus.waiting_for_assignment,
            RequestStatus.assigned,
        ],
    )
    def test_pre_completion_states_consume_nothing(self, db, status):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(db, user, status=status, subscription=sub)
        db.refresh(request)
        assert request.visit_consumed is False
        assert sub.used_visits == 0
        assert sub.remaining_visits == 4


class TestRefund:
    def test_refund_returns_the_credit(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=2)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(db, user, status=RequestStatus.completed, subscription=sub)
        VisitService.consume_for_request(db, request)
        db.flush()
        assert sub.used_visits == 1

        assert VisitService.refund_for_request(db, request) is True
        db.flush()
        assert sub.used_visits == 0
        assert request.visit_consumed is False

    def test_refund_of_an_unconsumed_request_is_a_no_op(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=2)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(db, user, status=RequestStatus.assigned, subscription=sub)
        assert VisitService.refund_for_request(db, request) is False
        db.flush()
        assert sub.used_visits == 0

    def test_double_refund_does_not_credit_twice(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=2)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(db, user, status=RequestStatus.completed, subscription=sub)
        VisitService.consume_for_request(db, request)
        db.flush()

        assert VisitService.refund_for_request(db, request) is True
        assert VisitService.refund_for_request(db, request) is False
        db.flush()
        assert sub.used_visits == 0


class TestAllocation:
    def test_allocation_increases_the_balance_and_logs_it(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=1)
        sub = f.make_subscription(db, user, plan)
        VisitService.allocate(db, sub, 5, note="Renewal")
        db.flush()
        assert sub.total_visits == 6
        assert sub.remaining_visits == 6
        entries = (
            db.query(VisitLedgerEntry)
            .filter(
                VisitLedgerEntry.subscription_id == sub.id,
                VisitLedgerEntry.entry_type == VisitEntryType.allocated,
            )
            .all()
        )
        assert sum(e.quantity for e in entries) == 5

    def test_negative_allocation_is_rejected(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        sub = f.make_subscription(db, user, plan)
        with pytest.raises(ValueError):
            VisitService.allocate(db, sub, -1)


class TestLedgerReconciliation:
    def test_ledger_matches_the_used_counter(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=5)
        sub = f.make_subscription(db, user, plan)
        for _ in range(3):
            request = f.make_request(db, user, status=RequestStatus.in_progress, subscription=sub)
            VisitService.consume_for_request(db, request)
        db.flush()

        consumed_total = (
            db.query(VisitLedgerEntry)
            .filter(
                VisitLedgerEntry.subscription_id == sub.id,
                VisitLedgerEntry.entry_type == VisitEntryType.consumed,
            )
            .count()
        )
        assert consumed_total == sub.used_visits

    def test_every_ledger_row_points_at_a_real_request(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=2)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(db, user, status=RequestStatus.completed, subscription=sub)
        VisitService.consume_for_request(db, request)
        db.flush()

        for entry in db.query(VisitLedgerEntry).all():
            if entry.service_request_id is not None:
                assert db.get(ServiceRequest, entry.service_request_id) is not None


class TestLifecycleTransitions:
    def test_happy_path_is_allowed(self):
        for source, target in [
            (RequestStatus.requested, RequestStatus.payment_pending),
            (RequestStatus.payment_pending, RequestStatus.payment_completed),
            (RequestStatus.payment_completed, RequestStatus.waiting_for_assignment),
            (RequestStatus.waiting_for_assignment, RequestStatus.assigned),
            (RequestStatus.assigned, RequestStatus.in_progress),
            (RequestStatus.in_progress, RequestStatus.completed),
        ]:
            assert RequestStatusService.can_transition(source, target) is True, f"{source} -> {target}"

    def test_cannot_skip_completion(self):
        assert RequestStatusService.can_transition(RequestStatus.assigned, RequestStatus.completed) is False

    def test_cannot_move_backwards(self):
        assert RequestStatusService.can_transition(RequestStatus.completed, RequestStatus.assigned) is False
        assert RequestStatusService.can_transition(RequestStatus.in_progress, RequestStatus.assigned) is False

    def test_cannot_resurrect_a_cancelled_request(self):
        assert RequestStatusService.can_transition(RequestStatus.cancelled, RequestStatus.assigned) is False
        assert RequestStatusService.can_transition(RequestStatus.cancelled, RequestStatus.requested) is False

    def test_completed_is_terminal(self):
        assert RequestStatusService.can_transition(RequestStatus.completed, RequestStatus.requested) is False

    def test_every_status_has_a_transition_entry(self):
        for status in RequestStatus:
            assert status in REQUEST_TRANSITIONS
