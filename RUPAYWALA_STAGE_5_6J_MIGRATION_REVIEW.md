# RUPAYWALA Stage 5.6J Migration Review

## Scope

Read-only review of pending Alembic migrations against active runtime database `rupaywala_ori` (PostgreSQL 18.1, Alembic `0005_fixed_quotes`, repo head `0008_private_document_storage`). No migrations executed. No database modified.

## Pending Migration Chain

| Order | Revision | File | Revises | Depends on head before it |
|---:|---|---|---|---|
| 1 | `0006_stage5_security_remediation` | `alembic/versions/0006_stage5_security_remediation.py` | `0005_fixed_quotes` | Yes - directly applies after current DB revision |
| 2 | `0007_user_token_version` | `alembic/versions/0007_user_token_version.py` | `0006_stage5_security_remediation` | Yes |
| 3 | `0008_private_document_storage` | `alembic/versions/0008_private_document_storage.py` | `0007_user_token_version` | Yes |

## 0006 — `0006_stage5_security_remediation`

**Purpose:** Additive Stage 5.1 security remediation: quotation signature versioning, request-to-quote linkage, and partial unique indexes preventing duplicate open payment intents.

### Tables/Columns Affected

| Object | Change | Details |
|---|---|---|
| `service_quotes.signature_version` | Add column | `Integer`, `nullable=False`, `server_default="1"` |
| `service_requests.quote_ref` | Add column | `String(64)`, `nullable=True` |
| `service_requests` | Add unique constraint | `uq_service_requests_quote_ref` on `quote_ref` |
| `payments` | Add partial unique index | `uq_payments_user_type_idem_open` on `(user_id, payment_type, idempotency_key)` WHERE `idempotency_key IS NOT NULL AND status IN ('pending','pending_verification')` |
| `payments` | Add partial unique index | `uq_payments_open_extra_charge_request` on `(related_request_id)` WHERE `payment_type='extra_charge' AND related_request_id IS NOT NULL AND status IN ('pending','pending_verification')` |

### Indexes / Constraints

- `uq_service_requests_quote_ref` - unique constraint (PostgreSQL allows multiple NULLs; historical NULL `quote_ref` rows are safe).
- `uq_payments_user_type_idem_open` - partial unique index.
- `uq_payments_open_extra_charge_request` - partial unique index.

### Data Transformations

- **No row updates/deletes/backfills.** Existing `service_quotes` rows get `signature_version=1` via server default; existing `service_requests.quote_ref` remains NULL.
- **Pre-migration duplicate inspection:** before creating either payment unique index, migration queries for existing duplicates in open payment rows. If duplicates exist, it raises `RuntimeError` with duplicate details and **no data is changed**. No destructive fallback.

### Destructive?

- **Non-destructive/additive** in normal case. No drops, no data deletion. It can **abort** (fail safely) if historical duplicate open payment data violates the new uniqueness invariants.

### Downgrade Behavior

- Requires PostgreSQL dialect.
- Drops `uq_payments_open_extra_charge_request` index.
- Drops `uq_payments_user_type_idem_open` index.
- Drops `uq_service_requests_quote_ref` unique constraint.
- Drops `service_requests.quote_ref` column.
- Drops `service_quotes.signature_version` column.
- Downgrade is schema-reverting but would remove columns/constraints; any application code depending on them would break. Data stored in those columns would be lost on downgrade.

### Dependencies / Risks

- **PostgreSQL required**; migration explicitly raises on non-PostgreSQL dialects.
- Depends on `0005_fixed_quotes`.
- Payment duplicate pre-check may block upgrade until duplicates are manually resolved (manual resolution requires explicit authorization and careful data review; not part of this plan).
- Application code expects `signature_version`/`quote_ref` behavior per Stage 5.1; running code against pre-0006 DB can be incompatible depending on code paths.

## 0007 — `0007_user_token_version`

**Purpose:** Add `users.token_version` for JWT invalidation.

### Tables/Columns Affected

| Object | Change | Details |
|---|---|---|
| `users.token_version` | Add column | `Integer`, `nullable=False`, `server_default=sa.text("0")` |

### Indexes / Constraints

- None added.

### Data Transformations

- No row updates. Existing users receive `token_version=0` via server default.

### Destructive?

- **Non-destructive/additive.**

### Downgrade Behavior

- Drops `users.token_version` column. Any JWT invalidation logic relying on token_version would break; column data lost on downgrade.

### Dependencies / Risks

- Depends on `0006_stage5_security_remediation`.
- **Directly related to current production symptom:** missing `users.token_version` causes login 500 `UndefinedColumn`. Applying 0007 fixes schema prerequisite for that code path, but 0008 is also pending and repo head is 0008; stopping at 0007 leaves DB behind head and may leave 0008-expected schema absent.

## 0008 — `0008_private_document_storage`

**Purpose:** Private document storage metadata, audit logs, and service request proof-document linkage.

### Tables/Columns Affected

| Object | Change | Details |
|---|---|---|
| PostgreSQL enum `document_scan_status` | Create enum | Values: `PENDING`, `CLEAN`, `INFECTED`, `FAILED`; `create_type=False` in SQLAlchemy Enum but explicitly `SCAN_STATUS_ENUM.create(bind, checkfirst=True)`. |
| `document_records` | Create table | Metadata for stored documents; see schema below. |
| `document_audit_logs` | Create table | Audit trail for document actions; see schema below. |
| `service_requests.proof_document_id` | Add column | `String(36)`, nullable, FK to `document_records.id` `ON DELETE SET NULL`. |

### `document_records` schema

| Column | Type | Null | Default / Notes |
|---|---|---|---|
| `id` | `String(36)` | No | Primary key |
| `owner_id` | `Integer` | No | FK `users.id` ON DELETE CASCADE |
| `document_type` | `String(50)` | No | Indexed |
| `storage_provider` | `String(20)` | No | server default `local` |
| `storage_key` | `String(512)` | No |  |
| `bucket` | `String(255)` | Yes |  |
| `original_filename` | `String(255)` | Yes |  |
| `mime_type` | `String(100)` | No |  |
| `file_size` | `BigInteger` | No |  |
| `checksum_sha256` | `String(64)` | No |  |
| `scan_status` | `document_scan_status` enum | No | server default `PENDING` |
| `scan_detail` | `String(255)` | Yes |  |
| `uploaded_at` | `DateTime` | No | server default `CURRENT_TIMESTAMP` |
| `updated_at` | `DateTime` | No | server default `CURRENT_TIMESTAMP` |
| `expires_at` | `DateTime` | Yes |  |
| `deleted_at` | `DateTime` | Yes |  |
| `deleted_by_user_id` | `Integer` | Yes | FK `users.id` ON DELETE SET NULL |

### `document_audit_logs` schema

| Column | Type | Null | Default / Notes |
|---|---|---|---|
| `id` | `Integer` | No | Primary key |
| `document_id` | `String(36)` | Yes | Indexed; no FK constraint declared in migration |
| `owner_id` | `Integer` | Yes | FK `users.id` ON DELETE SET NULL |
| `actor_user_id` | `Integer` | Yes | FK `users.id` ON DELETE SET NULL |
| `action` | `String(64)` | No | Indexed |
| `outcome` | `String(32)` | No |  |
| `detail` | `String(255)` | Yes |  |
| `created_at` | `DateTime` | No | server default `CURRENT_TIMESTAMP` |

### Indexes / Constraints

- `document_records`: `idx_document_records_owner_type` (`owner_id`,`document_type`), `idx_document_records_scan_status` (`scan_status`), `idx_document_records_deleted_at` (`deleted_at`), `ix_document_records_owner_id`, `ix_document_records_document_type`.
- `document_audit_logs`: `ix_document_audit_logs_id`, `ix_document_audit_logs_document_id`, `ix_document_audit_logs_owner_id`, `ix_document_audit_logs_actor_user_id`, `ix_document_audit_logs_action`.
- `service_requests`: `ix_service_requests_proof_document_id`, FK `fk_service_requests_proof_document_id` (`proof_document_id`) -> `document_records.id` ON DELETE SET NULL.

### Data Transformations

- No existing data transformation/backfill. New tables start empty. `service_requests.proof_document_id` added as nullable for existing rows.

### Destructive?

- **Additive/non-destructive on upgrade.** Creates objects; does not drop existing user data.
- **Downgrade is destructive to 0008-created objects/data:** drops FK/index/column on `service_requests`, drops `document_audit_logs` table and indexes, drops `document_records` table and indexes, drops `document_scan_status` enum. Any document metadata/audit records created after upgrade would be lost on downgrade.

### Downgrade Behavior

- Drop `fk_service_requests_proof_document_id`, drop `ix_service_requests_proof_document_id`, drop `service_requests.proof_document_id`.
- Drop audit log indexes/table.
- Drop document_records indexes/table.
- Drop `document_scan_status` enum with `checkfirst=True`.

### Dependencies / Risks

- Depends on `0007_user_token_version`.
- Creates enum type `document_scan_status`; repeated create guarded by `checkfirst=True`. Downgrade drops it - safe only if no dependent objects remain.
- `document_audit_logs.document_id` is indexed but not FK-constrained in migration; audit rows may reference deleted/nonexistent document IDs by design/audit retention choice - confirm intended.
- Application code already contains `DocumentRecord`/`DocumentAuditLog` models, `document_service`, `document_routes`, `proof_document_id` in request schemas/models/routes, and `/uploads` handling in `app/main.py` that prefers `DocumentRecord` metadata when present. **Code appears already aligned with 0008 schema.** Applying migration is required for this code to operate against DB; missing tables/columns will cause runtime errors on document-related paths.

## 0008 Code Impact Assessment

| Area | Observation | Impact |
|---|---|---|
| Models | `app/models/document_record.py`, `app/models/document_audit_log.py`, `app/models/__init__.py` register DocumentRecord/DocumentAuditLog | Code expects 0008 tables/enums. |
| Service routes/schemas | `app/routes/document_routes.py`, `app/services/document_service.py`, `app/services/document_storage.py`, `proof_document_id` in service/field schemas and routes | Document upload/retrieval paths expect 0008 schema. |
| Main uploads | `app/main.py` checks `DocumentRecord` by `storage_key` for `/uploads` authz/scan gating; falls back to legacy proof path when record absent | Legacy local proof files remain accessible via legacy path; DocumentRecord-backed enforcement activates when records exist. |
| Service request model | `service_requests.proof_document_id` FK present in model | Requires migration column/FK. |
| Tests | `tests/test_stage56j_private_documents.py` exercises DocumentRecord behavior | Confirms 0008-era code path exists. |

**Conclusion:** 0008 is a schema migration required by already-present application code. It does not itself require additional code changes beyond what is already in the repository; rather, the database must be migrated to match the code. Runtime behavior on pre-0008 DB will error when 0008 objects are queried/inserted.

## Overall Risk Summary

| Migration | Destructive upgrade? | Destructive downgrade? | Data backfill? | Blocks on bad data? | Notes |
|---|---:|---:|---:|---:|---|
| 0006 | No | Yes (drops added cols/constraints) | No | Yes, duplicate open payment rows cause safe abort | PostgreSQL-only; inspect duplicates before applying on any target. |
| 0007 | No | Yes (drops `users.token_version`) | No | No | Fixes current login schema blocker. |
| 0008 | No | Yes (drops 0008 tables/enum/column) | No | No | Required by code already present; creates enum/tables/FKs. |

**Recommended order:** 0006 -> 0007 -> 0008, only on an explicitly authorized, backed-up, isolated non-original target after pre-checks. No migration should be run on `rupaywala_ori` without explicit authorization and verified backup.