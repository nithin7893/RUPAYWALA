# RUPAYWALA Stage 5.6L Schema Validation Report

## Target

- Database: `rupaywala_dev_stage56k` (identity verified before every migration operation)
- Server: localhost:5432, PostgreSQL 18.1
- Initial revision: `0005_fixed_quotes`
- Final revision after stage: `0007_user_token_version` (0008 failed)

## 0006 Validation

| Object | Expected | Actual | Status |
|---|---|---|---|
| `service_quotes.signature_version` | integer, NOT NULL, default 1 | integer, NOT NULL, default `1` | PASS |
| `service_requests.quote_ref` | varchar(64), NULL | character varying, NULL, no default | PASS |
| `uq_service_requests_quote_ref` | UNIQUE constraint on `quote_ref` | `UNIQUE (quote_ref)` | PASS |
| `uq_payments_open_extra_charge_request` | Partial unique index on `related_request_id` for open extra_charge | Present with expected WHERE predicate | PASS |
| `uq_payments_user_type_idem_open` | Partial unique index on `(user_id,payment_type,idempotency_key)` for open pending/pending_verification | Present with expected WHERE predicate | PASS |
| 0006 duplicate pre-check (idempotency) | No rows | No rows | PASS |
| 0006 duplicate pre-check (extra charge) | No rows | No rows | PASS |

## 0007 Validation

| Object | Expected | Actual | Status |
|---|---|---|---|
| `users.token_version` column exists | Yes | Yes | PASS |
| Type | integer | integer | PASS |
| NOT NULL | Yes | NO (NOT NULL) | PASS |
| Default | 0 | `0` | PASS |
| Existing user rows readable with token_version | Yes | Sample rows returned token_version=0 | PASS |

## 0008 Validation

| Object | Expected | Actual | Status |
|---|---|---|---|
| Migration applied | Yes, revision `0008_private_document_storage` | **No - failed with DuplicateObject on `document_scan_status`** | **FAIL** |
| `document_scan_status` enum | PENDING,CLEAN,INFECTED,FAILED | Missing (rolled back) | **FAIL** |
| `document_records` table | Exists with required columns/indexes | Missing | **FAIL** |
| `document_audit_logs` table | Exists with required columns/indexes | Missing | **FAIL** |
| `service_requests.proof_document_id` | varchar(36), nullable, FK to document_records.id | Missing | **FAIL** |
| `ix_service_requests_proof_document_id` | Present | Missing | **FAIL** |
| `fk_service_requests_proof_document_id` | FK to document_records.id ON DELETE SET NULL | Missing | **FAIL** |
| `idx_document_records_owner_type` | Present | Missing | **FAIL** |
| `idx_document_records_scan_status` | Present | Missing | **FAIL** |
| `idx_document_records_deleted_at` | Present | Missing | **FAIL** |
| Document audit indexes | Present | Missing | **FAIL** |

## Data Integrity / Existing Records

| Check | Initial (pre-0006) | Final (post-0007, 0008 failed) | Status |
|---|---:|---:|---|
| `users` | 28 | 28 | PASS |
| `alembic_version` rows | 1 | 1 | PASS |
| `service_requests` | 2 | 2 | PASS |
| `payments` | 9 | 9 | PASS |
| `service_quotes` | 0 | 0 | PASS |
| `user_subscriptions` | 2 | 2 | PASS |
| `subscription_plans` | 10 | 10 | PASS |
| `branches` | 1 | 1 | PASS |
| `notifications` | 3 | 3 | PASS |

## Other Databases (untouched confirmation)

| Database | Alembic revision | Status |
|---|---|---|
| `rupaywala_ori` | `0005_fixed_quotes` | PASS (untouched) |
| `rupaywala_dev` | `0003_visit_credits_lifecycle` | PASS (untouched) |
| `rupaywala_dev_stage56k` | `0007_user_token_version` | Expected given 0008 failure |

## Summary

- 0006 schema objects: **PASS**.
- 0007 schema objects: **PASS**.
- 0008 schema objects: **FAIL** (migration failed, rolled back cleanly).
- Existing data integrity: **PASS**.
- Other databases untouched: **PASS**.