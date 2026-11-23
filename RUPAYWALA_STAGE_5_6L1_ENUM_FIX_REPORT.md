# RUPAYWALA Stage 5.6L-1 Enum Fix Report

## Scope

Investigated and fixed migration 0008 enum creation conflict on isolated database `rupaywala_dev_stage56k` only. No changes to `rupaywala_ori`, `rupaywala_dev`, or any other database. No Alembic stamp. No credentials printed.

## Problem

- Stage 5.6L: 0006/0007 PASS on `rupaywala_dev_stage56k`; 0008 FAILED and rolled back.
- DB remained at `0007_user_token_version` with no partial 0008 objects.
- Error: `psycopg2.errors.DuplicateObject: type "document_scan_status" already exists` during `CREATE TYPE document_scan_status AS ENUM ('PENDING','CLEAN','INFECTED','FAILED')`.

## Step 1 — Root Cause Inspection

| Inspected | Finding |
|---|---|
| `alembic/versions/0008_private_document_storage.py` | Defined `SCAN_STATUS_ENUM = sa.Enum(..., name="document_scan_status", create_type=False)` and called `SCAN_STATUS_ENUM.create(bind, checkfirst=True)`, then used same object in `document_records.scan_status` column. |
| `app/models/document_record.py` | `DocumentScanStatus(str, enum.Enum)` with values `PENDING/CLEAN/INFECTED/FAILED`; model column uses `Enum(DocumentScanStatus, name="document_scan_status")`. |
| SQLAlchemy behavior (SA 2.0.48, Alembic 1.20.0) | Generic `sa.Enum` in SA 2.0 does **not** expose/honor `create_type` the same way `postgresql.ENUM` does (`create_type` attribute absent; kwarg ineffective). Result: SQLAlchemy auto-created the PG enum during table create despite `create_type=False` intent. Manual `create(checkfirst=True)` ran first, creating the type; table auto-create then attempted `CREATE TYPE` again -> `DuplicateObject`. |
| Transaction behavior | `alembic/env.py` uses `transaction_per_migration=True`; failure rolled back cleanly (confirmed: revision stayed 0007, enum/tables absent). |

**Cause confirmed:** double enum creation - explicit manual create plus SQLAlchemy PostgreSQL table-create auto event, because `sa.Enum(..., create_type=False)` did not disable auto-create in SA 2.0.

## Step 2 — Fix Implemented

**File changed:** `alembic/versions/0008_private_document_storage.py`

### Changes

1. **Import PostgreSQL dialect ENUM:**
   - Added `from sqlalchemy.dialects import postgresql`.

2. **Use `postgresql.ENUM` with effective `create_type=False`:**
   - Replaced `sa.Enum("PENDING","CLEAN","INFECTED","FAILED", name="document_scan_status", create_type=False)` with `postgresql.ENUM(*DOCUMENT_SCAN_STATUS_VALUES, name="document_scan_status", create_type=False)`.
   - Added `DOCUMENT_SCAN_STATUS_VALUES = ("PENDING", "CLEAN", "INFECTED", "FAILED")` as single source of labels.

3. **Idempotent/safe explicit creation guard:**
   - Before creating, query `pg_type/pg_enum/pg_namespace` for existing `public.document_scan_status` labels.
   - If exists with same labels: skip create (idempotent).
   - If exists with different labels: raise `RuntimeError` requiring manual inspection (no blind drop/bypass).
   - If absent: `SCAN_STATUS_ENUM.create(bind, checkfirst=True)`.

4. **Preserved:**
   - Revision/down_revision/chain unchanged (`0008_private_document_storage` revises `0007_user_token_version`).
   - Enum values/order unchanged: `PENDING, CLEAN, INFECTED, FAILED`.
   - Table/column/index/FK definitions unchanged.
   - Downgrade behavior unchanged (drops FK/index/column, audit indexes/table, document_records indexes/table, enum with `checkfirst=True`).
   - No unrelated models/migration history changed.

### Why this fix

- `postgresql.ENUM(create_type=False)` reliably disables SQLAlchemy auto-create in SA 2.0.
- Explicit migration-managed create gives exactly one creation path.
- Label inspection prevents silent mismatch if enum pre-exists unexpectedly.
- Compatible with existing ORM model (`Enum(DocumentScanStatus, name="document_scan_status")`).

## Step 3 — Static Verification

| Check | Result | Status |
|---|---|---|
| Python compile (`py_compile` migration, model, document_service) | No output/errors | PASS |
| Alembic heads | `0008_private_document_storage (head)` | PASS |
| Alembic history/graph | Chain intact through 0001->...->0008 | PASS |
| Enum consistency (model vs migration) | `['PENDING','CLEAN','INFECTED','FAILED'] == ['PENDING','CLEAN','INFECTED','FAILED']` | PASS |
| Focused pytest migration tests | Not run via conftest (conftest creates/drops `rupaywala_test`; Stage 5.6L-1 DB testing constrained to `rupaywala_dev_stage56k`) | NOT TESTED |

## Step 4 — DB Verification / Retry

Pre-DB checks (before every DB operation): `current_database()='rupaywala_dev_stage56k'`, port 5432, addr ::1/128. Alembic revision confirmed `0007_user_token_version`. Enum/table absence confirmed before retry.

| Check | Result | Status |
|---|---|---|
| 0008 retry on `rupaywala_dev_stage56k` | Alembic exit 0; `0007_user_token_version -> 0008_private_document_storage` | PASS |
| Post-migration identity | `rupaywala_dev_stage56k`, localhost:5432 | PASS |
| Post-migration revision | `0008_private_document_storage` | PASS |

## Step 5 — Post-Migration Verification

| Check | Result | Status |
|---|---|---|
| Alembic revision | `0008_private_document_storage` | PASS |
| `document_scan_status` labels | `PENDING, CLEAN, INFECTED, FAILED` (correct order) | PASS |
| `document_records` exists | Yes; expected columns present including scan_status USER-DEFINED default `PENDING::document_scan_status` | PASS |
| `document_audit_logs` exists | Yes; expected columns/indexes present | PASS |
| `service_requests.proof_document_id` exists | Yes; varchar, nullable | PASS |
| FK `fk_service_requests_proof_document_id` | `FOREIGN KEY (proof_document_id) REFERENCES document_records(id) ON DELETE SET NULL` | PASS |
| Required indexes | `document_records_pkey`, `idx_document_records_owner_type`, `idx_document_records_scan_status`, `idx_document_records_deleted_at`, `ix_document_records_owner_id`, `ix_document_records_document_type`, audit indexes, `ix_service_requests_proof_document_id` | PASS |
| Existing data intact | users=28, alembic_version=1, service_requests=2, payments=9, service_quotes=0, user_subscriptions=2, subscription_plans=10, branches=1, notifications=3 | PASS |
| `users.token_version` still present | Yes | PASS |
| `rupaywala_ori` untouched | `0005_fixed_quotes` | PASS |
| `rupaywala_dev` untouched | `0003_visit_credits_lifecycle` | PASS |

## Downgrade Test

| Check | Result | Status |
|---|---|---|
| Downgrade 0008->0007 on separate disposable migration-test DB | Not executed. Stage 5.6L-1 constrains DB testing to `rupaywala_dev_stage56k`; downgrading working dev DB is disallowed. No separate disposable migration-test DB authorized/created in this stage. | NOT TESTED |

## Files Changed

- `alembic/versions/0008_private_document_storage.py` - enum creation fix only; migration chain/history unchanged.

No other application/model/migration files changed. No production readiness claimed.