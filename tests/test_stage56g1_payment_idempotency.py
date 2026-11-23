"""Stage 5.6G-1 payment idempotency regression coverage.

Run only against a disposable database. Do NOT run with the default destructive
tests/conftest.py against shared/protected environments.
"""
from datetime import datetime, timedelta
import threading

import pytest
from fastapi import HTTPException

from app.database import SessionLocal
from app.models.payment import Payment, PaymentStatus
from app.models.user import User
from app.services.payment_service import PaymentService
from tests import factories as f


class TestStage56G1PaymentIdempotency:
    def test_1_first_payment_creation(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        p, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t1"
        )
        assert p.status == PaymentStatus.pending
        assert p.idempotency_key == "g1-t1"
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t1").count() == 1

    def test_2_sequential_duplicate_request(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        p1, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t2"
        )
        p2, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t2"
        )
        assert p1.txn_id == p2.txn_id
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t2").count() == 1

    def test_3_concurrent_duplicate_request(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        uid, pid = user.id, plan.id
        barrier = threading.Barrier(2)
        out = []

        def worker():
            s = SessionLocal()
            try:
                local_user = s.get(User, uid)
                barrier.wait(timeout=10)
                p, _, _, _ = PaymentService.create_subscription_payment(
                    s, user=local_user, plan_id=pid, idempotency_key="g1-t3"
                )
                out.append(("ok", p.txn_id))
            except Exception as exc:
                s.rollback()
                out.append(("err", repr(exc)))
            finally:
                s.close()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(20)
            assert not t.is_alive()

        oks = [x for x in out if x[0] == "ok"]
        assert len(oks) == 2
        assert oks[0][1] == oks[1][1]
        db.expire_all()
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t3").count() == 1

    def test_4_same_key_changed_payload(self, db):
        user = f.make_user(db)
        p1 = f.make_plan(db, name="Silver G1", code="silver_g1")
        p2 = f.make_plan(db, name="Gold G1", code="gold_g1", price=500)
        first, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=p1.id, idempotency_key="g1-t4"
        )
        with pytest.raises(HTTPException) as exc:
            PaymentService.create_subscription_payment(
                db, user=user, plan_id=p2.id, idempotency_key="g1-t4"
            )
        assert exc.value.status_code == 409
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t4").count() == 1
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t4").first().txn_id == first.txn_id

    def test_5_different_user_same_key(self, db):
        u1 = f.make_user(db)
        u2 = f.make_user(db)
        plan = f.make_plan(db)
        a, _, _, _ = PaymentService.create_subscription_payment(
            db, user=u1, plan_id=plan.id, idempotency_key="g1-t5"
        )
        b, _, _, _ = PaymentService.create_subscription_payment(
            db, user=u2, plan_id=plan.id, idempotency_key="g1-t5"
        )
        assert a.txn_id != b.txn_id
        assert a.user_id != b.user_id

    def test_6_retry_after_pending(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        a, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t6"
        )
        b, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t6"
        )
        assert a.txn_id == b.txn_id
        assert a.status == PaymentStatus.pending

    def test_7_retry_after_success(self, db):
        user = f.make_user(db)
        admin = f.make_user(db, role="admin")
        plan = f.make_plan(db)
        a, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t7"
        )
        a.utr_number = "UTRG1T7001"
        a.status = PaymentStatus.pending_verification
        a.attempts = 1
        db.commit()
        verified = PaymentService.verify_payment(db, admin=admin, txn_id=a.txn_id, approve=True)
        b, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t7"
        )
        assert verified.status == PaymentStatus.success
        assert b.txn_id == a.txn_id
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t7").count() == 1

    def test_8_retry_after_failure(self, db):
        user = f.make_user(db)
        admin = f.make_user(db, role="admin")
        plan = f.make_plan(db)
        a, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t8"
        )
        a.utr_number = "UTRG1T8001"
        a.status = PaymentStatus.pending_verification
        a.attempts = 1
        db.commit()
        rejected = PaymentService.verify_payment(db, admin=admin, txn_id=a.txn_id, approve=False, note="bad")
        b, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t8"
        )
        assert rejected.status == PaymentStatus.failed
        assert b.txn_id == a.txn_id
        assert db.query(Payment).filter(Payment.idempotency_key == "g1-t8").count() == 1

    def test_9_duplicate_payment_submission(self, db):
        user = f.make_user(db)
        plan = f.make_plan(db)
        a, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t9"
        )
        s1 = PaymentService.submit_payment(db, user=user, txn_id=a.txn_id, utr_number="UTRG1T9001")
        s2 = PaymentService.submit_payment(db, user=user, txn_id=a.txn_id, utr_number="UTRG1T9001")
        assert s1.status == PaymentStatus.pending_verification
        assert s2.status == PaymentStatus.pending_verification
        assert s1.attempts == s2.attempts == 1

    def test_10_duplicate_admin_verification(self, db):
        user = f.make_user(db)
        admin = f.make_user(db, role="admin")
        plan = f.make_plan(db)
        a, _, _, _ = PaymentService.create_subscription_payment(
            db, user=user, plan_id=plan.id, idempotency_key="g1-t10"
        )
        a.utr_number = "UTRG1T10001"
        a.status = PaymentStatus.pending_verification
        a.attempts = 1
        db.commit()
        v1 = PaymentService.verify_payment(db, admin=admin, txn_id=a.txn_id, approve=True)
        v2 = PaymentService.verify_payment(db, admin=admin, txn_id=a.txn_id, approve=True)
        assert v1.status == PaymentStatus.success
        assert v2.status == PaymentStatus.success
        assert v1.txn_id == v2.txn_id
