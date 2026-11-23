# RUPAYWALA STAGE 5.6G-2 — Concurrent Subscription Seeding & DB Integrity Hardening Report

## Scope
- Stage: 5.6G-2
- Objective: Resolve B56G-013 concurrent `seed_subscription_plans()` startup race; review all-status payment idempotency index safety.
- Status classification: **PARTIALLY COMPLETE**
- Production readiness claim: **None**. This stage does not claim production readiness.

## Safety / Isolation
- No destructive commands used.
- Preserved DBs were **not** modified/dropped/accessed for mutation: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`.
- New disposable DB created only after existence check: `rupaywala_g2seed_validation` on `rupaywala-pg18-validation` (Postgres 18.1, host-mapped `127.0.0.1:55432`), cloned from `rupaywala_role_validation`.
- Temp test scripts/roles used in disposable DB; temp role `rw_g2_app` created and dropped by script. Temp script files remain in user temp until cleanup.
- No pytest run against default destructive `tests/conftest.py`; focused catalog tests executed via isolated disposable-DB runner.

## B56G-013 Root Cause
- `seed_subscription_plans()` in `app/services/plan_catalog.py` had no concurrency serialization. Concurrent startup workers could race on code lookup/insert against `subscription_plans.code` unique index (`ix_subscription_plans_code`), producing `UniqueViolation` even when final state converged to 7 plans.
- Startup path: `app/main.py` lifespan calls `seed_reference_data()` then `seed_subscription_plans()`.

## Fix (Implemented)
- File: `app/services/plan_catalog.py`
- Approach: **transaction-scoped PostgreSQL advisory lock** around the complete seed operation.
  - `SELECT pg_advisory_xact_lock(hashtext(:lock_key))` with lock key `rupaywala:subscription_plan_seed`.
  - Acquired only when bind dialect is PostgreSQL; no-op on non-Postgres binds.
  - Lock is transaction-scoped: automatically released on commit/rollback; cannot leak across pooled connections.
  - No session-level advisory lock used.
  - Unique constraint/index `ix_subscription_plans_code` preserved; not weakened.
  - No destructive table reset; existing upsert/archive/idempotency behavior preserved.
  - No runtime sequence UPDATE permission added; sequence USAGE-only behavior preserved.
  - Plan IDs/pricing/benefits/archive semantics preserved by existing upsert logic.

## Concurrency / Regression Evidence (Disposable DB)
Disposable DB: `rupaywala_g2seed_validation` (fresh clone before tests; data reset inside disposable DB during test runs).

| Case | Result | Evidence |
|---|---|---|
| 1. 3 concurrent seed calls | **PASS** | no errors, active_count=7, total=7, no dup codes, IDs stable |
| 2. 5 concurrent seed calls | **PASS** | no errors, active_count=7, total=7, no dup codes |
| 3. 10 concurrent seed calls | **PASS** | no errors, active_count=7, total=7, no dup codes |
| 4. 10 repeated sequential seed calls | **PASS** | no errors, count=7, IDs stable |
| 5. Concurrent calls, initially empty table | **PASS** | 5 workers, no errors, count=7, no dup codes |
| 6. Concurrent calls, existing plans | **PASS** | 5 workers, no errors, count=7, no dup codes |
| 7. Restricted `rupaywala_app`-like permissions | **PASS** | temp role `rw_g2_app` with CONNECT/USAGE/SELECT,INSERT,UPDATE,DELETE on tables, USAGE,SELECT on sequences; 5 concurrent seeds, no errors, count=7 |
| 8. Sequence-generated inserts without sequence UPDATE | **PASS** | `has_sequence_privilege(...,'USAGE')=true`, `UPDATE=false`; seeding succeeded |
| 9. Transaction failure / rollback behavior | **PASS** | conflicting insert caused rollback; after rollback plan count/IDs preserved; subsequent seed succeeded; IDs preserved |
| 10. Final plan count and IDs | **PASS** | count=7, all expected codes present, IDs stable after rerun |

Canonical plan IDs observed in disposable run: `silver=1, gold=2, platinum=3, diamond=4, family=5, elite=6, premium_family=7`.

## Focused Catalog Regression (Isolated Disposable DB)
Runner: standalone isolated script against `rupaywala_g2seed_validation` (not default conftest DB). `tests/conftest.py` inspected; it is destructive by design (drops/recreates public schema on `rupaywala_test`).

| Test | Result |
|---|---|
| `test_catalog_is_idempotent_and_archives_non_catalog_plans` | PASS |
| `test_catalog_repairs_a_behind_postgres_id_sequence` | PASS |
| `test_digital_entitlement_does_not_consume_a_home_visit` | PASS |
| `test_digital_service_request_is_allowed_without_home_visits` | PASS |
| `test_distance_plan_override_keeps_round_trip_pricing` | PASS |
| `test_duplicate_family_member_is_rejected` | PASS |
| `test_family_member_limit_counts_primary_subscriber` | PASS |
| `test_plan_entitlements_match_the_catalog` | PASS |
| `test_renewal_preserves_the_previous_period_and_snapshots_new_benefits` | PASS |
| `test_seed_preserves_admin_configured_premium_values_and_activation` | PASS |
| `test_seed_subscription_plans_concurrent_startup` (new) | PASS |

Total: 11 passed, 0 failed, 0 skipped.

## Additional Security Review — All-Status Payment Idempotency Index
- Current state: app enforces same-key reuse across terminal statuses (5.6G-1 fix in `PaymentService._reusable_intent`); DB has partial unique index `uq_payments_user_type_idem_open` on `(user_id,payment_type,idempotency_key)` WHERE key IS NOT NULL and status in pending/pending_verification.
- Preflight (read-only, disposable `rupaywala_g2seed_validation`): `payments` table had 0 rows, 0 keyed rows, 0 duplicates for full key `(user_id,payment_type,idempotency_key)` where key IS NOT NULL. This preflight is **not sufficient** to prove absence of historical duplicates in preserved/production-like datasets.
- Compatibility analysis: a full unique index on `(user_id,payment_type,idempotency_key)` WHERE `idempotency_key IS NOT NULL` would align with 5.6G-1 app semantics (same key is primary identity; same payload returns existing intent including terminal; different payload 409). It would prevent DB-level duplicate keyed rows across all statuses. However, migration safety requires duplicate preflight on target data, handling/null-key exclusion review, and consideration of any legitimate historical duplicates or operational retry semantics before adding.
- **Decision:** Do **not** add or modify payment idempotency indexes in 5.6G-2. No payment schema changes combined with seeding fix. Full index remains a candidate pending authorized read-only duplicate preflight/compatibility analysis on target data and migration planning. Tracked as `NEW-56G1-001` / 5.6G-2 finding.

## Files Changed (Code/Test)
- `app/services/plan_catalog.py` — added transaction-scoped advisory lock in `seed_subscription_plans()`.
- `tests/test_subscription_catalog.py` — added `test_seed_subscription_plans_concurrent_startup`.

## Blockers / Not Executed
- Live external integrations remain BLOCKED/NOT TESTED as applicable.
- Default pytest/conftest full suite remains BLOCKED due destructive fixture.
- Full unique all-status payment idempotency index NOT ADDED pending target-data duplicate preflight/migration safety.
- No production readiness/infra/ops controls validated.

## Final Classification
**PARTIALLY COMPLETE** — B56G-013 concurrent seeding race is fixed in code and validated on a disposable PostgreSQL DB with required concurrency/permission/rollback/ID-stability cases passing; focused catalog regression passed in isolated runner. All-status payment idempotency DB unique index was not added because required historical duplicate preflight/compatibility analysis on target data is incomplete. No production readiness claim.
