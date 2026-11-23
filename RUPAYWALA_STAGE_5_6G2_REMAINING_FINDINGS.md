# RUPAYWALA STAGE 5.6G-2 — Remaining Findings

## Final Classification
**PARTIALLY COMPLETE**

No production readiness claim. Stage 5.6G-2 fixes and validates the B56G-013 concurrent subscription seeding race on a disposable PostgreSQL DB, but unresolved blockers remain.

## Resolved in 5.6G-2
- **B56G-013 / Concurrent subscription seeding race** — **RESOLVED (code + disposable-DB validated)**. `seed_subscription_plans()` now uses a PostgreSQL transaction-scoped advisory lock (`pg_advisory_xact_lock(hashtext('rupaywala:subscription_plan_seed'))`) around the complete seed operation. Concurrent 3/5/10 worker runs, sequential reruns, empty/existing table, restricted-role, no-sequence-UPDATE, rollback, and final count/ID stability all passed with no `UniqueViolation` or duplicates.

## Open Findings

### NEW-56G1-001 / B56G-003 DB-level hardening gap — OPEN (carry-forward)
- **Severity:** Medium (integrity hardening gap; app-layer fix exists).
- **Status:** App enforces same-key idempotency across terminal statuses (5.6G-1). DB partial unique index `uq_payments_user_type_idem_open` covers only open statuses.
- **5.6G-2 review:** Read-only preflight on disposable `rupaywala_g2seed_validation` found no payment rows/duplicates for `(user_id,payment_type,idempotency_key)` where key IS NOT NULL. This is insufficient for target/production-like data.
- **Required before any index change:** authorized read-only duplicate preflight on target datasets; compatibility review for null keys, payment type, user ownership, related request uniqueness, existing payment history, and migration safety; migration precheck/cleanup plan if duplicates exist.
- **Action taken:** No index added/modified; no payment schema changes combined with seeding fix.

### Testing / Isolation blockers — OPEN
- **Default `tests/conftest.py` is destructive** (drops/recreates `public` schema on `rupaywala_test`). Full pytest suite remains **BLOCKED** under normal execution. Focused catalog tests were run only via isolated disposable-DB runner.
- **Target-data payment duplicate preflight** for full all-status idempotency index: **BLOCKED/NOT EXECUTED**.

### External integration / operational blockers — OPEN (carry-forward)
- Live Google Maps/Mappls distance: BLOCKED/NOT TESTED.
- SMS/OTP delivery: BLOCKED/NOT TESTED.
- SMTP/email: BLOCKED/NOT TESTED.
- Google OAuth live flow: BLOCKED/NOT TESTED.
- Live UPI gateway settlement/reconciliation: BLOCKED/NOT TESTED.
- File upload/storage hardening end-to-end: NOT TESTED in this stage.
- Production infra/ops controls (backups, monitoring, secrets rotation, rate limiting/WAF, deployment hardening, DR): NOT TESTED.

## Preserved Databases
The following DBs were not modified/dropped/accessed for mutation: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`. Disposable `rupaywala_g2seed_validation` was created and used for 5.6G-2 validation.

## Production Readiness
**Not claimed.**