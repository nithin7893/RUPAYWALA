# RUPAYWALA STAGE 5.6G-3 — Remaining Findings

## Final Classification
**PARTIALLY COMPLETE**

No production readiness claim.

## Stage 5.6G-3 Outcome
- NEW-56G1-001 was investigated with duplicate preflight and semantic compatibility analysis on a new disposable DB (`rupaywala_g3pay_validation`, clone of `rupaywala_role_validation`, created after existence check). No preserved DBs were modified.
- Proposed full unique index `UNIQUE (user_id, payment_type, idempotency_key) WHERE idempotency_key IS NOT NULL` is **NOT SAFE/COMPATIBLE AS-IS** with current extra-charge retry semantics. No migration was created/applied.

## Key Findings

### NEW-56G1-001 — OPEN (design blocker identified)
- **Severity:** Medium.
- **Current state:** App-layer keyed idempotency across terminal statuses exists for subscription keyed flows (5.6G-1). DB has partial unique open-only index `uq_payments_user_type_idem_open`.
- **Duplicate preflight:** Disposable clone had `total=0, keyed=0, duplicates=0` for full-key all-status check; insufficient for preserved/prod-like target data.
- **Semantic incompatibility:** Extra-charge payments use deterministic `idempotency_key=f"request:{request_id}"` and currently allow legitimate retry after terminal failure/expiry by creating a new intent with the same key. Disposable probe confirmed: after failed extra-charge, retry created second row with same `request:{id}` key (2 rows, different txn_ids). Proposed full unique index would block this.
- **Required before any index change:**
  1. Product/semantics decision for extra-charge terminal retries: either new key per retry attempt (API/client/app contract change) or explicit terminal-intent reuse semantics with controlled retry mechanism.
  2. Authorized read-only duplicate preflight on target/prod-like datasets.
  3. Alembic migration with preflight abort, no destructive data rewrite, careful lock/downtime strategy (`CONCURRENTLY` considerations), and downgrade.
  4. Re-evaluate replacement of `uq_payments_user_type_idem_open` only after full index is proven safe; preserve `uq_payments_open_extra_charge_request`.

### Regression status
- Required 12 payment idempotency/verification/history cases: **PASS** on disposable DB.
- Combined seeding/concurrent startup/sequence-permission/subscription purchase+activation: **PASS**.
- Restricted-role API end-to-end coverage: **PARTIAL** (restricted-role seeding/sequence check done; full restricted-role HTTP app tests not executed).

## Open Blockers (carry-forward)
- Full pytest suite blocked by destructive `tests/conftest.py`.
- Target-data duplicate preflight for full payment idempotency index not authorized/executed.
- Live external integrations BLOCKED/NOT TESTED: Google Maps live, SMS/OTP delivery, SMTP, Google OAuth, live UPI gateway settlement, file uploads.
- Production infra/ops controls NOT TESTED: backups/restore, monitoring, secrets rotation, rate limiting/WAF, deployment hardening, DR, HA.

## Preserved Databases
Not modified/dropped/accessed for mutation: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`, `rupaywala_g2seed_validation`. `rupaywala_g3pay_validation` is disposable Stage 5.6G-3 DB.

## Production Readiness
**Not claimed.**