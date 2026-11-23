# RUPAYWALA Stage 5.6L Regression Test Results

## Test Constraints

- Target database: `rupaywala_dev_stage56k` only.
- No destructive tests/conftest run against existing databases.
- Project `tests/conftest.py` overwrites `DATABASE_URL`, creates/drops `rupaywala_test`, and truncates schema - **not used** to avoid destructive behavior against existing DBs and because it is model-schema based, not migrated-dev-DB based.
- 0008 migration failed and rolled back; document storage DB objects are absent. Document-related DB persistence tests are blocked by this.

## Results

| Check | Method | Result | Status |
|---|---|---|---|
| Login token-version DB behavior | Read-only SQL smoke on `rupaywala_dev_stage56k`: `SELECT id, token_version FROM users LIMIT 3` | Returned rows with `token_version=0` | PASS |
| User model includes `token_version` | Model import/column inspection (`app.models.user.User`) | `token_version` present in model columns | PASS |
| 0006 service_quotes.signature_version queryable | Read-only SQL smoke: `SELECT id, signature_version FROM service_quotes LIMIT 1` | Query succeeded | PASS |
| 0006 service_requests.quote_ref queryable | Read-only SQL smoke: `SELECT id, quote_ref FROM service_requests LIMIT 1` | Query succeeded | PASS |
| Quote creation and consumption | Not executed (would require write operations/app flow on dev DB; full pytest conftest unsafe here) | - | NOT TESTED |
| Payment idempotency (runtime) | Not executed as end-to-end test; schema pre-checks verified 0006 partial unique indexes exist | Indexes present; runtime behavior not exercised | NOT TESTED |
| Document model persistence | 0008 failed; `document_records` table missing | Cannot persist without schema | BLOCKED |
| Document audit records | 0008 failed; `document_audit_logs` table missing | Cannot persist without schema | BLOCKED |
| Subscription plan seeding | Not executed (seeding is write behavior; conftest-based tests not used). Existing data shows `subscription_plans=10` preserved after 0006/0007. | Existing rows preserved | NOT TESTED |
| 0006 duplicate-payment preconditions | Read-only SQL duplicate checks on target | No duplicate open idempotency or extra-charge rows | PASS |
| Existing restored data integrity | Read-only count comparison before/after 0006-0007 | Key counts unchanged (users=28, payments=9, service_requests=2, user_subscriptions=2, subscription_plans=10) | PASS |

## Model/Schema Compatibility (regression-relevant)

| Check | Result | Status |
|---|---|---|
| `ServiceQuote` model expects `signature_version` and DB has it | Match | PASS |
| `ServiceRequest` model expects `quote_ref` and DB has it | Match | PASS |
| `ServiceRequest` model expects `proof_document_id` but DB missing it (0008 failed) | Mismatch | **FAIL** |
| `DocumentRecord` model imported; DB table missing | Mismatch | **FAIL** |
| `DocumentAuditLog` model imported; DB table missing | Mismatch | **FAIL** |

## Summary

- PASS: 6
- FAIL: 3 (0008-dependent model/schema mismatches; blocked by 0008 failure)
- BLOCKED: 2 (document persistence/audit require missing 0008 schema)
- NOT TESTED: 3 (quote creation/consumption, payment idempotency runtime, subscription plan seeding - not safely executed under no-destructive-conftest constraint)

No destructive pytest/conftest run against existing databases. No production readiness claimed.