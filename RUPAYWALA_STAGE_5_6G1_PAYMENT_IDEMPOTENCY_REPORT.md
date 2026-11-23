# RUPAYWALA_STAGE_5_6G1_PAYMENT_IDEMPOTENCY_REPORT

## Final Classification
**PARTIALLY COMPLETE**

No production readiness is claimed.

## Scope
- Stage 5.6G-1 payment idempotency investigation/fix in a new disposable DB.
- Follow-up review of Stage 5.6G remaining findings: concurrent plan seeding, quote ownership, quote expiry boundary, quote signature tampering, family-member eligible-plan operation.
- 5.6G cleanup/reporting discrepancy review.

## Preserved DBs / Safety
- Preserved and not modified: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`.
- Disposable DB used: `rupaywala_idem_validation` (created only after existence check returned empty; cloned from `rupaywala_role_validation` in `rupaywala-pg18-validation` docker container).
- No destructive commands used. No schema/role/config changes outside disposable DB and repo code/test/report files.
- Pytest default destructive `tests/conftest.py` was inspected and **not run**. Regression coverage was executed via standalone disposable-DB script and a pytest-style test file was added for repo coverage.

## 1) Implementation Inspection

| Area | Evidence | Finding |
|---|---|---|
| API route | `app/routes/payment_routes.py` `POST /payments/create` passes `idempotency_key` to `PaymentService.create_subscription_payment`; submit/verify routes delegate to service. | Route is thin; idempotency behavior lives in service. |
| Service | `app/services/payment_service.py` `create_subscription_payment`, `_reusable_intent`, `submit_payment`, `verify_payment`. | Pre-fix defect confirmed in `_reusable_intent`. |
| Model/index | `app/models/payment.py` `idempotency_key`, `uq_payments_user_type_idem_open` partial unique index on `(user_id,payment_type,idempotency_key)` WHERE key IS NOT NULL AND status IN (`pending`,`pending_verification`). | Index protects open-state duplicates only; terminal same-key reuse allowed by DB. |
| Migration | `alembic/versions/0006_stage5_security_remediation.py` creates partial unique open index after duplicate precheck. | No migration weakened; no new migration added in this pass. |
| Existing tests | `tests/test_payments.py`, `tests/test_stage5_security_remediation.py` covered open retry, cross-user key, concurrent same key, DB uniqueness for open statuses. | Missing coverage for terminal-state same-key reuse and same-key different payload. |

## 2) Expected Idempotency Behavior (determined)

| Case | Expected behavior | Rationale |
|---|---|---|
| Same user, same key, same payload, open intent exists | Return same intent (same txn_id), no new DB row. | Idempotent retry. |
| Same user, same key, different payload | Reject with 409 conflict; do not return/overwrite different logical payment. | Idempotency key must not be reused for different operation. |
| Different user, same key | Allowed as different intents (user-scoped). | Key scope is user+type+key. |
| Same key while pending/pending_verification | Return same intent; no duplicate. | Open operation retry. |
| Same key after success | Return existing successful payment; do not create second intent. | Prevents silent duplicate intent/charge for same keyed operation. |
| Same key after failure | Return existing failed payment; do not silently create second intent. | Prevents silent duplicate intent; client should use a new key for a new attempt. |
| Same key after expiry | Return existing expired payment; do not silently create second intent. | Prevents silent duplicate intent; client should use a new key. |
| Concurrent same key requests | Exactly one authoritative open intent/row; concurrent callers receive same result or safe idempotent outcome. | Requires DB-level protection + transaction-safe lookup. |

## 3) Root Cause (Confirmed)

`PaymentService._reusable_intent` (pre-fix):
1. For keyed requests, it looked up only **open** rows by same key. If not found (including terminal success/failure/expired), it fell through to generic plan/request open lookup and/or allowed creation of a new row. Because `uq_payments_user_type_idem_open` is partial (open statuses only), DB allowed new row with same key after terminal state. This explains B56G-003 (same key, 200/200, different txn_id).
2. For keyed requests, when a key-match was found, it returned it without validating payload (plan_id/request_id). Same key with different payload could return the old intent for a different plan - confirmed defect.
3. Generic fallback could return/consider unrelated open intents; keyed requests needed stronger key identity.

## 4) Reproduction Evidence (Disposable DB: `rupaywala_idem_validation`)

Pre-fix standalone reproduction (sanitized txn IDs):

| Scenario | Result | Rows | Classification |
|---|---|---:|---|
| A. Same key, same payload, sequential, pending | same txn_id | 1 | PASS (expected) |
| B. Same key, same payload, after success | different txn_id (`...7655` vs `...4f81`) | 2 | **DEFECT CONFIRMED** |
| C. Same key, same payload, after failed verification | different txn_id | 2 | **DEFECT CONFIRMED** |
| D. Same key, same payload, after expiry | different txn_id | 2 | **DEFECT CONFIRMED** |
| E. Same key, while pending_verification | same txn_id | 1 | PASS |
| F. Same key, different payload (different plan) | returned first plan intent, no error | 1 | **DEFECT CONFIRMED** |
| G. Different user, same key | different txn_id, different users | 2 | PASS |

Post-fix reproduction:

| Scenario | Result | Rows | Classification |
|---|---|---:|---|
| A. Sequential same key pending | same txn_id | 1 | PASS |
| B. Same key after success | same txn_id, status success returned | 1 | PASS |
| C. Same key after failure | same txn_id, status failed returned | 1 | PASS |
| D. Same key after expiry | same txn_id, status expired returned | 1 | PASS |
| E. Same key while pending_verification | same txn_id | 1 | PASS |
| F. Same key, different payload | 409 `This idempotency key has already been used for a different payment request` | 1 | PASS |
| G. Different user, same key | different txn_id | 2 | PASS |

## 5) Fix Implemented

File changed: `app/services/payment_service.py`

- `_reusable_intent` now treats idempotency key as primary identity for keyed requests.
- Keyed lookup searches **any status** for same `(user_id, payment_type, idempotency_key)`.
- Payload mismatch (different `plan_id` / `related_request_id`) returns 409.
- If keyed open intent exists, it is returned (expired pending is marked expired and returned idempotently).
- If keyed terminal intent exists, it is returned idempotently (no silent second intent).
- If no keyed match exists, service does **not** return an unrelated open intent as keyed; it checks for conflicting open intent for same logical target and returns 409, or expires stale pending candidates before allowing creation.
- Unkeyed behavior remains plan/request dedup for open intents.

## 6) DB-Level Concurrency Protection

- Preserved: `uq_payments_user_type_idem_open` partial unique index (open statuses). Not weakened.
- `create_subscription_payment` and extra-charge creation keep `IntegrityError` handling and re-query via `_reusable_intent`.
- Concurrent same-key regression (case 3) passed: 2 concurrent requests, 2 OK responses, same txn_id, 1 DB row.
- Limitation: DB currently allows multiple historical terminal rows with same key across statuses only if inserted bypassing application logic; current partial index is open-state only. This pass did not add a stricter all-status unique index to avoid unsafe migration on unknown historical data. Application logic now prevents normal creation path from producing this case.

## 7) 5.6G Cleanup/Reporting Discrepancy

- Verified: uvicorn PID 14508 not running; `rw56g_app` role absent in docker Postgres; no `*56g*`/`*rw56g*` temp files in `C:\Users\NITHIN\AppData\Local\Temp\opencode`.
- Discrepancy resolved: `RUPAYWALA_STAGE_5_6G_E2E_VALIDATION_REPORT.md` line "Shutdown NOT EXECUTED" corrected with post-cleanup confirmation note.

## 8) Remaining Limitations / Not Tested
- Live external integrations still BLOCKED/NOT TESTED: Google Maps live, SMS/OTP delivery, SMTP, Google OAuth, live UPI gateway settlement, file uploads.
- Full pytest suite not run due destructive `tests/conftest.py`.
- Production readiness controls not tested (TLS/pg_hba/secret management/backup restore/monitoring/HA/deployment).
- Concurrent plan startup seeding has a real race finding (see remaining findings); not fixed in this pass.
- No production readiness claim.