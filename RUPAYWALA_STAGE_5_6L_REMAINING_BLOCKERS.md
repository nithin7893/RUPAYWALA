# RUPAYWALA Stage 5.6L Remaining Blockers

## Overall Status

**FAIL (partial migration).** 0006 and 0007 applied and verified on `rupaywala_dev_stage56k` only. 0008 failed and rolled back cleanly; final revision is `0007_user_token_version`. No other databases were modified.

## Blockers

| ID | Blocker | Severity | Status | Evidence / Impact | Required action (explicit authorization needed) |
|---|---|---|---|---|---|
| B56L-001 | 0008 `0008_private_document_storage` fails on `rupaywala_dev_stage56k` | **Critical** | Open | Alembic exit code 1: `psycopg2.errors.DuplicateObject: type "document_scan_status" already exists` during `CREATE TYPE ...` triggered by SQLAlchemy enum table-create auto event. Migration rolled back cleanly; DB remains at `0007_user_token_version`. | Investigate/fix 0008 enum creation behavior in a controlled change (review SQLAlchemy Enum/create_type/checkfirst interaction). Test fix on isolated dev DB only. Do not stamp. Do not modify original DB. |
| B56L-002 | 0008 schema objects missing in dev DB | **High** | Open | No `document_scan_status` enum, no `document_records`, no `document_audit_logs`, no `service_requests.proof_document_id`/FK/index. | Resolved only after B56L-001 fixed and 0008 applied successfully. |
| B56L-003 | App models expect 0008 schema not present in migrated dev DB | **High** | Open | `DocumentRecord`/`DocumentAuditLog` models imported; `ServiceRequest.proof_document_id` in model; DB lacks corresponding objects. Any document-related runtime path will fail. | Apply 0008 successfully on isolated dev DB; then run document smoke/regression tests. |
| B56L-004 | Full regression suite not safely runnable against migrated dev DB under current conftest | **Medium** | Open | `tests/conftest.py` creates/drops/truncates `rupaywala_test` and overwrites DATABASE_URL; destructive by design. Quote creation/consumption, payment idempotency runtime, subscription plan seeding not executed. | Create a safe non-destructive test strategy for migrated dev DB, or run selected tests in isolated disposable test DB with equivalent migrated schema. |
| B56L-005 | `rupaywala_ori` still at `0005_fixed_quotes`, missing `users.token_version` | **High** | Open | Original DB unchanged (by design). Login 500 on original runtime remains until authorized safe migration. | Do not migrate original. After dev validation (including 0008 fix), take fresh verified backup, obtain explicit authorization, migrate original in controlled window. |
| B56L-006 | 0008 downgrade is destructive to document data | **Medium** | Informational | If 0008 is later applied and data created, downgrade drops 0008 tables/enum/column. | Prefer backup/restore rollback strategy for production/original migration. |

## Cleared / Passing

| ID | Item | Status |
|---|---|---|
| C56L-001 | Target identity gates enforced before every migration operation | PASS |
| C56L-002 | 0006 applied and schema verified on `rupaywala_dev_stage56k` | PASS |
| C56L-003 | 0007 applied and schema verified (`users.token_version` integer NOT NULL default 0) | PASS |
| C56L-004 | 0006 duplicate pre-checks clean | PASS |
| C56L-005 | Existing restored data counts preserved after 0006/0007 | PASS |
| C56L-006 | `rupaywala_ori` and `rupaywala_dev` untouched | PASS |
| C56L-007 | 0008 failure rolled back cleanly (no partial schema) | PASS |

## Safe Next Step

1. **Do not migrate `rupaywala_ori`.**
2. Investigate and fix 0008 enum creation in `alembic/versions/0008_private_document_storage.py` (likely make enum creation compatible with SQLAlchemy/PG auto-create behavior; e.g., avoid double-create by using PostgreSQL ENUM/create_type/checkfirst pattern consistently). Review carefully - migration files affect all environments.
3. Re-run 0008 only on `rupaywala_dev_stage56k` (currently at `0007_user_token_version`, clean rollback state) after identity pre-checks.
4. Complete Step 3/4/5 verification including document persistence/audit smoke tests.
5. Only after full dev validation and explicit authorization, plan original DB backup+migration.

**No Alembic migrations applied to any non-target database. No production readiness claimed.**