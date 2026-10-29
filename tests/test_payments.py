"""Payment intent, UTR submission and activation.

The rules under test:
  * the backend decides every amount; a client cannot influence the price
  * a payment activates exactly once, even under duplicate verification
  * one customer cannot touch another's transaction
  * the ledger and the visit balance move in the same transaction
"""

from datetime import datetime, timedelta
from decimal import Decimal

import pytest
from fastapi import HTTPException

from app.models.payment import Payment, PaymentStatus, PaymentType
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.models.visit_ledger import VisitEntryType, VisitLedgerEntry
from app.services.payment_service import (
    PaymentService,
    build_upi_url,
    generate_qr_code_base64,
)
from app.services.visit_service import VisitService
from tests import factories as f


class TestAmounts:
    def test_amount_comes_from_the_plan_not_the_client(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, price=1499.0)
        payment, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        assert payment.amount == Decimal("1499.00")

    def test_upi_url_carries_the_amount_and_txn_id(self):
        url = build_upi_url(499.5, "TXN123", "Premium")
        assert "am=499.50" in url
        assert "tn=TXN123" in url
        assert url.startswith("upi://pay?pa=")

    def test_qr_code_is_generated_offline(self):
        png = generate_qr_code_base64(build_upi_url(100, "TXN1"))
        assert isinstance(png, str) and len(png) > 100


class TestIntents:
    def test_creating_an_intent_produces_a_pending_payment(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, price=999.0)
        payment, _, url, qr = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        assert payment.status == PaymentStatus.pending
        assert payment.payment_type == PaymentType.subscription
        assert payment.txn_id
        assert url and qr

    def test_repeat_request_reuses_the_open_intent(self, db):
        """No duplicate QR spam while an intent is still open."""
        user = f.make_user(db)
        plan = f.make_plan(db)
        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        second, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        assert first.txn_id == second.txn_id
        assert db.query(Payment).filter(Payment.plan_id == plan.id).count() == 1

    def test_expired_intent_is_replaced_not_reused(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        first.expires_at = datetime.utcnow() - timedelta(minutes=1)
        db.commit()

        second, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        assert second.txn_id != first.txn_id
        db.refresh(first)
        assert first.status == PaymentStatus.expired

    def test_idempotency_key_is_honoured(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="abc-123"
        )
        second, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="abc-123"
        )
        assert first.txn_id == second.txn_id

    def test_no_subscription_is_created_before_payment(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        PaymentService.create_subscription_payment(db, user=user, plan_id=plan.id)
        assert db.query(UserSubscription).filter(UserSubscription.user_id == user.id).count() == 0


class TestSubmission:
    def _pending(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, price=999.0)
        payment, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        return user, payment

    def test_valid_utr_moves_to_pending_verification(self, db):
        user, payment = self._pending(db)
        submitted = f.utr()
        updated = PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=submitted
        )
        assert updated.status == PaymentStatus.pending_verification
        assert updated.utr_number == submitted
        assert updated.attempts == 1

    def test_utr_is_normalised(self, db):
        user, payment = self._pending(db)
        updated = PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number="  utrabc123  "
        )
        assert updated.utr_number == "UTRABC123"

    def test_short_utr_is_rejected(self, db):
        user, payment = self._pending(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(db, user=user, txn_id=payment.txn_id, utr_number="123")
        assert exc.value.status_code == 400

    def test_reused_utr_is_rejected(self, db):
        user_a, payment_a = self._pending(db)
        admin = f.make_admin(db)
        shared_utr = f.utr()
        PaymentService.submit_payment(
            db, user=user_a, txn_id=payment_a.txn_id, utr_number=shared_utr
        )
        PaymentService.verify_payment(db, admin=admin, txn_id=payment_a.txn_id, approve=True)

        user_b = f.make_user(db)
        plan_b = f.make_plan(db)
        payment_b, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user_b, plan_id=plan_b.id
        )
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(
                db, user=user_b, txn_id=payment_b.txn_id, utr_number=shared_utr
            )
        assert exc.value.status_code == 409

    def test_resubmitting_is_idempotent(self, db):
        user, payment = self._pending(db)
        first = PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        second = PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        assert first.txn_id == second.txn_id
        assert second.attempts == 1, "a repeated submit must not burn another attempt"

    def test_another_customers_transaction_is_forbidden(self, db):
        _, payment = self._pending(db)
        attacker = f.make_user(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(
                db, user=attacker, txn_id=payment.txn_id, utr_number=f.utr()
            )
        assert exc.value.status_code == 403

    def test_expired_intent_cannot_be_submitted(self, db):
        user, payment = self._pending(db)
        payment.expires_at = datetime.utcnow() - timedelta(minutes=1)
        db.commit()
        with pytest.raises(HTTPException) as exc:
            PaymentService.submit_payment(
                db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
            )
        assert exc.value.status_code == 400

    def test_submission_does_not_activate_anything_yet(self, db):
        user, payment = self._pending(db)
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        assert db.query(UserSubscription).filter(UserSubscription.user_id == user.id).count() == 0


class TestVerification:
    def _submitted(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, price=999.0, visits_included=4)
        payment, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id
        )
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f._tail()
        )
        return user, plan, payment, f.make_admin(db)

    def test_approval_activates_the_subscription(self, db):
        user, plan, payment, admin = self._submitted(db)
        verified = PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=True
        )
        assert verified.status == PaymentStatus.success
        assert verified.verified_by == admin.id

        sub = (
            db.query(UserSubscription)
            .filter(UserSubscription.user_id == user.id)
            .first()
        )
        assert sub is not None
        assert sub.status == SubscriptionStatus.active
        assert sub.total_visits == plan.visits_included

    def test_approval_allocates_visit_credits_in_the_ledger(self, db):
        user, plan, payment, admin = self._submitted(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)

        sub = (
            db.query(UserSubscription)
            .filter(UserSubscription.user_id == user.id)
            .first()
        )
        entries = (
            db.query(VisitLedgerEntry)
            .filter(
                VisitLedgerEntry.subscription_id == sub.id,
                VisitLedgerEntry.entry_type == VisitEntryType.allocated,
            )
            .all()
        )
        assert sum(e.quantity for e in entries) == plan.visits_included

    def test_double_verification_activates_only_once(self, db):
        user, plan, payment, admin = self._submitted(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)

        subs = (
            db.query(UserSubscription)
            .filter(UserSubscription.user_id == user.id)
            .all()
        )
        assert len(subs) == 1, "a duplicate callback must not create a second subscription"
        assert subs[0].total_visits == plan.visits_included

    def test_rejection_does_not_activate(self, db):
        user, _, payment, admin = self._submitted(db)
        rejected = PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=False, note="Amount mismatch"
        )
        assert rejected.status == PaymentStatus.failed
        assert db.query(UserSubscription).filter(UserSubscription.user_id == user.id).count() == 0

    def test_a_rejected_payment_cannot_be_re_approved(self, db):
        user, _, payment, admin = self._submitted(db)
        PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=False, note="Bad UTR"
        )
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)
        assert exc.value.status_code == 409

    def test_cannot_verify_a_payment_that_was_never_submitted(self, db):
        user, plan, payment, admin = self._submitted(db)
        PaymentService.verify_payment(
            db, admin=admin, txn_id=payment.txn_id, approve=False, note="x"
        )
        other = f.make_user(db)
        other_plan = f.make_plan(db)
        fresh, _, _, _ = PaymentService.create_subscription_payment(
            db, user=other, plan_id=other_plan.id
        )
        with pytest.raises(HTTPException) as exc:
            PaymentService.verify_payment(db, admin=admin, txn_id=fresh.txn_id, approve=True)
        assert exc.value.status_code == 409


class TestExtraChargePayments:
    def test_extra_charge_payment_moves_the_request_out_of_payment_pending(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(
            db, user, status=RequestStatus.payment_pending, extra_charge=236.0, subscription=sub
        )
        assert request.requires_payment is True

        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=user, request_id=request.id
        )
        assert payment.payment_type == PaymentType.extra_charge
        assert payment.amount == Decimal("236.00")

        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        admin = f.make_admin(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)

        db.refresh(request)
        assert request.charge_paid is True
        assert request.requires_payment is False

    def test_extra_charge_payment_does_not_consume_a_visit(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db, visits_included=4)
        sub = f.make_subscription(db, user, plan)
        request = f.make_request(
            db, user, status=RequestStatus.payment_pending, extra_charge=100.0, subscription=sub
        )
        payment, _, _ = PaymentService.create_extra_charge_payment(
            db, user=user, request_id=request.id
        )
        PaymentService.submit_payment(
            db, user=user, txn_id=payment.txn_id, utr_number=f.utr()
        )
        admin = f.make_admin(db)
        PaymentService.verify_payment(db, admin=admin, txn_id=payment.txn_id, approve=True)

        db.refresh(sub)
        db.refresh(request)
        assert sub.used_visits == 0
        assert request.visit_consumed is False

    def test_cannot_pay_another_customers_request(self, db):
        user = f.make_user(db)
        request = f.make_request(db, user, extra_charge=100.0)
        attacker = f.make_user(db)
        with pytest.raises(HTTPException) as exc:
            PaymentService.create_extra_charge_payment(db, user=attacker, request_id=request.id)
        assert exc.value.status_code == 404

    def test_no_payment_needed_when_the_charge_is_zero(self, db):
        user = f.make_user(db)
        request = f.make_request(db, user, extra_charge=0.0)
        with pytest.raises(HTTPException):
            PaymentService.create_extra_charge_payment(db, user=user, request_id=request.id)
