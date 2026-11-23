# RUPAYWALA Stage 5.6L Migration Report

## Scope

Controlled Alembic migration validation against isolated development database `rupaywala_dev_stage56k` only. No migrations applied to `rupaywala_ori`, `rupaywala_dev`, `rupaywala_validation`, `rupaywala_role_validation`, or any other database.

## Database Identity / Safety Gates

| Check | Result | Status |
|---|---|---|
| Target database | `rupaywala_dev_stage56k` | PASS |
| Connected server | localhost:5432 (`inet_server_addr=::1/128`, `inet_server_port=5432`) | PASS |
| Connected user | `postgres` | PASS |
| Identity verified before every migration operation | Yes (before/after 0006, 0007, 0008 attempt) | PASS |
| `rupaywala_ori` untouched | Alembic `0005_fixed_quotes` (unchanged) | PASS |
| `rupaywala_dev` untouched | Alembic `0003_visit_credits_lifecycle` (unchanged) | PASS |
| No passwords/DATABASE_URL printed | Confirmed | PASS |

## Step 1 — Pre-migration Checks

| Check | Result | Status |
|---|---|---|
| Target at expected initial revision | `0005_fixed_quotes` | PASS |
| Verified backup exists | `database_backups/rupaywala_ori_stage56k_20261122_102506.dump` (105,241 bytes) | PASS |
| Migration chain | 0005 -> 0006_stage5_security_remediation -> 0007_user_token_version -> 0008_private_document_storage (single head) | PASS |
| 0006 duplicate open idempotency pre-check | No rows | PASS |
| 0006 duplicate open extra-charge pre-check | No rows | PASS |
| Conflicting objects pre-check (0006/0007/0008 targets) | None found | PASS |
| Initial public table count | 20 | PASS |
| Initial key counts | users=28, alembic_version=1, service_requests=2, payments=9, service_quotes=0, user_subscriptions=2, subscription_plans=10, branches=1, notifications=3 | PASS |

## Step 2 — Sequential Migration Execution

### 0006 `0006_stage5_security_remediation`

| Check | Result | Status |
|---|---|---|
| Pre-identity check | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Pre-revision | `0005_fixed_quotes` | PASS |
| Alembic upgrade | Exit code 0 | PASS |
| Post-identity check | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Post-revision | `0006_stage5_security_remediation` | PASS |
| `service_quotes.signature_version` | integer, NOT NULL, default `1` | PASS |
| `service_requests.quote_ref` | varchar, NULL, no default | PASS |
| `uq_service_requests_quote_ref` | UNIQUE constraint on `(quote_ref)` | PASS |
| `uq_payments_open_extra_charge_request` | Partial unique index present with expected WHERE clause | PASS |
| `uq_payments_user_type_idem_open` | Partial unique index present with expected WHERE clause | PASS |

### 0007 `0007_user_token_version`

| Check | Result | Status |
|---|---|---|
| Pre-identity check | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Pre-revision | `0006_stage5_security_remediation` | PASS |
| Alembic upgrade | Exit code 0 | PASS |
| Post-identity check | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Post-revision | `0007_user_token_version` | PASS |
| `users.token_version` exists | Yes | PASS |
| `users.token_version` type | integer | PASS |
| `users.token_version` nullable | NO (NOT NULL) | PASS |
| `users.token_version` default | `0` | PASS |

### 0008 `0008_private_document_storage`

| Check | Result | Status |
|---|---|---|
| Pre-identity check | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Pre-revision | `0007_user_token_version` | PASS |
| Alembic upgrade | **Exit code 1 - FAILED** | **FAIL** |
| Failure | `sqlalchemy.exc.ProgrammingError: (psycopg2.errors.DuplicateObject) type "document_scan_status" already exists` during `CREATE TYPE document_scan_status AS ENUM (...)` triggered by table auto-create event | **FAIL** |
| Post-failure identity | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Post-failure revision | `0007_user_token_version` (rolled back; no partial 0008 state) | PASS |
| Post-failure 0008 objects | No `document_scan_status` enum, no `document_records`, no `document_audit_logs`, no `service_requests.proof_document_id` | PASS (rollback clean) |

**0008 failure analysis:** Migration manually creates `document_scan_status` with `checkfirst=True` then creates `document_records` using the same `sa.Enum(..., create_type=False)` object. During table creation, SQLAlchemy's PostgreSQL enum event attempted to auto-create the enum again, causing `DuplicateObject`. Because `transaction_per_migration=True` is configured, the migration rolled back cleanly; DB remained at `0007_user_token_version` with no partial 0008 objects. No migration file was modified. No stamp used.

## Step 3 — Application Compatibility (summary)

| Check | Result | Status |
|---|---|---|
| User model has `token_version` | Yes | PASS |
| ServiceQuote model has `signature_version` | Yes | PASS |
| ServiceRequest model has `quote_ref` | Yes | PASS |
| ServiceRequest model has `proof_document_id` | Yes (model expects it) | PASS |
| DocumentRecord model imported | Yes | PASS |
| DocumentAuditLog model imported | Yes | PASS |
| DB has `token_version` | Yes | PASS |
| DB has 0006 columns/indexes/constraints | Yes | PASS |
| DB has 0008 objects | No (0008 failed) | **FAIL** |
| Schema/model mismatch | Models expect `document_records`, `document_audit_logs`, `service_requests.proof_document_id`; DB missing them because 0008 not applied | **FAIL** |

## Step 4 — Regression Tests (summary)

See `RUPAYWALA_STAGE_5_6L_REGRESSION_TEST_RESULTS.md`. Conftest-based pytest not run because it is destructive/creates its own test DB; isolated dev DB smoke checks used where safe.

## Step 5 — Final Verification

| Check | Result | Status |
|---|---|---|
| Database is `rupaywala_dev_stage56k` | Yes | PASS |
| Alembic revision is `0008_private_document_storage` | **No - `0007_user_token_version`** | **FAIL** |
| `users.token_version` exists | Yes | PASS |
| All required document storage objects exist | No - 0008 not applied | **FAIL** |
| Existing restored customer/payment records intact | users=28, payments=9, service_requests=2, user_subscriptions=2, subscription_plans=10 (unchanged from initial) | PASS |
| No migrations applied to any other database | `rupaywala_ori`=0005, `rupaywala_dev`=0003, target only advanced to 0007 | PASS |

## Outcome

**FAIL (partial).** 0006 and 0007 applied and verified successfully on `rupaywala_dev_stage56k` only. 0008 failed with `DuplicateObject: type "document_scan_status" already exists`; transaction rolled back cleanly. Final revision is `0007_user_token_version`, not `0008_private_document_storage`. No other databases modified. No production readiness claimed.