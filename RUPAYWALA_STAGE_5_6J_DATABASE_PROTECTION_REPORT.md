# RUPAYWALA Stage 5.6J Database Protection & Development Database Preparation Report

## Status

- **Planning/reporting only.** No Alembic migrations executed. No database created/dropped/restored/modified. No PostgreSQL roles/privileges modified. No `DATABASE_URL` changed. No credentials/connection strings/secrets printed.
- **Original database `rupaywala_ori` must remain untouched.**

## Current Findings (confirmed read-only)

| Item | Value |
|---|---|
| Active runtime database | `rupaywala_ori` |
| PostgreSQL server version | 18.1 |
| Connected DB user | `postgres` |
| Host/Port | `localhost:5432` (driver `postgresql`) |
| Current Alembic revision | `0005_fixed_quotes` |
| Repository Alembic head | `0008_private_document_storage` |
| Missing column | `public.users.token_version` (required by 0007 / current app behavior) |
| Pending migrations | `0006_stage5_security_remediation`, `0007_user_token_version`, `0008_private_document_storage` |
| Verified backup of `rupaywala_ori` | **None identified** in scanned workspace backup area |

## 1) Pending Migration Inspection Summary

Detailed review: `RUPAYWALA_STAGE_5_6J_MIGRATION_REVIEW.md`.

| Migration | Summary | Destructive upgrade | Downgrade | Key risk |
|---|---|---:|---|---|
| 0006 `stage5_security_remediation` | Adds `service_quotes.signature_version`, `service_requests.quote_ref` unique constraint, two partial unique payment indexes; pre-checks duplicate open payment rows and aborts safely if found | No (additive) | Drops added columns/constraints/indexes | PostgreSQL-only; may abort on historical duplicate open payment data; no data backfill |
| 0007 `user_token_version` | Adds `users.token_version` NOT NULL default 0 | No (additive) | Drops column | Fixes current login `UndefinedColumn`; code depends on it |
| 0008 `private_document_storage` | Creates `document_scan_status` enum, `document_records`, `document_audit_logs`; adds `service_requests.proof_document_id` FK/index | No (additive) | Drops 0008 objects/column/enum; data in 0008 tables lost | App code already contains 0008-era document models/services/routes; DB must be migrated to match code; downgrade destructive to 0008 data |

All three are additive on upgrade, schema-reverting/destructive on downgrade to their own objects. No data-transform/backfill migrations. 0006 has a safe abort guard for duplicate payment data.

## 2) Backup Preparation

### Existing Backup Directory

| Path | Contents |
|---|---|
| `C:\RUPAAY_WALA\rupaywala_backend\database_backups\` | `rupaywala_role_validation_pre_56g_20261121_223922.dump` (109338 bytes, 2026-11-21 22:39:22); `rupaywala_validation_pre_migrations_20261121.dump` (96409 bytes, 2026-11-21 21:47:06) |

No `rupaywala_ori` backup found. Existing backups must not be deleted or overwritten.

### Available PostgreSQL Backup Tools (inspected)

| Tool | Status | Version | Location |
|---|---|---|---|
| `pg_dump` | Found | PostgreSQL 18.1 | `C:\Program Files\PostgreSQL\18\bin\pg_dump.exe` |
| `pg_restore` | Found | PostgreSQL 18.1 | `C:\Program Files\PostgreSQL\18\bin\pg_restore.exe` |
| `psql` | Found | PostgreSQL 18.1 | `C:\Program Files\PostgreSQL\18\bin\psql.exe` |

PATH lookup for `pg_dump/pg_restore/psql` returned not found; use full PostgreSQL 18 bin paths in commands.

### Prepared Backup Command (DO NOT EXECUTE without authorization)

See `RUPAYWALA_STAGE_5_6J_SAFE_COMMANDS.md` section "Backup: rupaywala_ori (prepared, not executed)".

Backup requirements satisfied by the prepared command:
- Timestamped custom-format `pg_dump -Fc`.
- Never prints credentials; uses secure auth (`.pgpass` or session `PGPASSWORD` set without echoing). Do not put password in command line.
- Refuses to overwrite existing backup file (`Test-Path` guard).
- Checks dump exit code (`$LASTEXITCODE` / `$?`).
- Verifies dump with `pg_restore --list`.
- Records backup file size and timestamp.
- Not executed.

## 3) Isolated Development Database Plan

### Goal

Create a separate, disposable development/migration-test database from a **verified** backup of `rupaywala_ori`, apply pending migrations there, validate, and only then decide on authorized production/original migration. `rupaywala_ori` remains untouched throughout.

### Safety Rules

1. `rupaywala_ori` is read-only for this effort - no migrations, no writes, no schema changes, no restore target.
2. Create/use a separate database name (proposal: `rupaywala_dev_56j` or equivalent explicitly approved name). Do not reuse `rupaywala_ori`.
3. Use separate connection configuration for the dev DB (session env override or dedicated untracked `.env.dev.local` used only by explicit operator action). **Do not modify `.env` `DATABASE_URL`.**
4. Before any future migration command, confirm active target DB name, host, port, user, and Alembic revision via read-only checks.
5. Never point development migrations at `rupaywala_ori`.
6. No database stamping to bypass migrations.
7. Any DB creation/restore/migration requires explicit authorization.

### Proposed Flow (authorization required per step)

| Step | Action | Safety gate |
|---:|---|---|
| B1 | Take verified custom-format backup of `rupaywala_ori` | Backup file exists, non-zero, `pg_restore --list` succeeds, size/timestamp recorded; no overwrite. |
| B2 | Verify backup integrity on disposable target only if needed | Never restore over `rupaywala_ori`. |
| D1 | Create separate empty dev DB (name approved) | Confirm not `rupaywala_ori`; confirm not validation/role_validation unless explicitly intended. |
| D2 | Restore verified backup into dev DB | Restore target is dev DB only; confirm `current_database()` before restore. |
| D3 | Point a separate session/config to dev DB | Do not change `.env`; use process env override or explicitly selected dev env file. Confirm effective DB. |
| M1 | Run pre-migration duplicate checks for 0006 on dev DB | Read-only SQL checks; if duplicates exist, stop and report. |
| M2 | Apply 0006 -> 0007 -> 0008 sequentially on dev DB | Confirm target DB before every step; capture output; stop on error. |
| V1 | Verify schema/Alembic/relevant app smoke tests on dev DB | Read-only verification queries + selected tests against disposable dev/test DB only. |
| P1 | Only after authorization: plan original DB backup + migration window | Requires fresh verified `rupaywala_ori` backup, explicit approval, rollback/downgrade risk review. |

## 4) Migration Test Plan (Isolated Dev DB only, not executed)

Exact commands and verification queries are prepared in `RUPAYWALA_STAGE_5_6J_SAFE_COMMANDS.md`.

Plan covers:
- Pre-check active DB is the approved dev DB (not `rupaywala_ori`).
- Read-only pre-check for 0006 duplicate payment rows.
- Sequential `alembic upgrade 0006_stage5_security_remediation`, `0007_user_token_version`, `0008_private_document_storage`.
- Verification queries for Alembic revision, `users.token_version`, 0008 tables/columns/indexes/constraints/enum.
- App smoke checks to be run only against the isolated dev DB after explicit authorization.

## Risks / Blockers

| Risk | Severity | Notes |
|---|---|---|
| No verified `rupaywala_ori` backup | High | Must be resolved before any migration of original DB. |
| `rupaywala_ori` may be original/non-disposable | High | Name and prior reports indicate caution; explicit confirmation required. |
| 0006 may abort on duplicate open payments | Medium | Safe abort; requires manual data review/remediation only with authorization. |
| 0008 downgrade destructive | Medium | Document metadata/audit data created after upgrade would be lost on downgrade. |
| Code already expects 0007/0008 schema | High for runtime | Login currently broken on pre-0007 DB; fix requires authorized migration on correct target. |
| Legacy scripts contain hardcoded connection strings | Medium security hygiene | Not modified; credentials not reproduced. Cleanup should be handled separately. |

## Recommendation

1. **Do not migrate `rupaywala_ori` now.**
2. Obtain explicit authorization to create a verified backup of `rupaywala_ori`.
3. After backup verification, obtain authorization to create/restore a separate dev DB from that backup.
4. Run 0006-0008 only on the isolated dev DB, verify, then decide on original DB with a fresh backup and explicit approval.

## Generated Artifacts

- `RUPAYWALA_STAGE_5_6J_DATABASE_PROTECTION_REPORT.md` (this report)
- `RUPAYWALA_STAGE_5_6J_MIGRATION_REVIEW.md`
- `RUPAYWALA_STAGE_5_6J_SAFE_COMMANDS.md`

**Stop: awaiting explicit authorization before any backup, database creation, restoration, or migration.**