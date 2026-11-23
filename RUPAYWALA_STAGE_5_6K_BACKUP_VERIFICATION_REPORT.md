# RUPAYWALA Stage 5.6K Backup Verification Report

## Status

- **Part A executed (authorized).** Backup created and verified.
- **No Alembic migrations executed.** No database dropped/restored/modified. No PostgreSQL roles/privileges modified. No `.env`/`DATABASE_URL` changed. No credentials/connection strings/secrets printed.
- Existing backups were not deleted or overwritten.

## 1) Source Identity Verification (read-only)

| Check | Result |
|---|---|
| PostgreSQL server version | 18.1 |
| Server host:port | `localhost:5432` (server reported `::1/128:5432`) |
| Driver | `postgresql` (psycopg2) |
| Configured/active database | `rupaywala_ori` |
| Connected DB user | `postgres` |
| `current_database()` | `rupaywala_ori` |
| `current_user` | `postgres` |
| Alembic revision | `0005_fixed_quotes` |
| `public.users.token_version` exists | No (false) |
| Public base table count | 20 |

Source identity confirmed as `rupaywala_ori` on PostgreSQL 18.1 at Alembic `0005_fixed_quotes`. Identity was not uncertain.

## 2) Backup Execution

| Item | Result |
|---|---|
| Tool | `C:\Program Files\PostgreSQL\18\bin\pg_dump.exe` (PostgreSQL 18.1) |
| Format | Custom (`-Fc -Z 6`) |
| Backup file | `C:\RUPAAY_WALA\rupaywala_backend\database_backups\rupaywala_ori_stage56k_20261122_102506.dump` |
| Overwrite existing backup? | No - timestamped new file; existence checked before write |
| pg_dump exit code | 0 |
| pg_dump stdout/stderr | empty |

## 3) Backup Verification

| Item | Result |
|---|---|
| Verification tool | `C:\Program Files\PostgreSQL\18\bin\pg_restore.exe --list` (PostgreSQL 18.1) |
| pg_restore --list exit code | 0 |
| Verification result | **PASS** |
| TOC/list line count | 272 |
| Archive header (safe) | `Archive created at 2026-11-22 10:25:06`; `dbname: rupaywala_ori`; `TOC Entries: 261`; `Compression: gzip` |
| Backup file size | 105,241 bytes |
| Backup mtime (local) | 2026-11-22T10:25:06.519856 |

## 4) Backup Safety Checks

- Source database was not modified (pg_dump read-only).
- No previous backup deleted or overwritten.
- Existing backups remain: `rupaywala_role_validation_pre_56g_20261121_223922.dump`, `rupaywala_validation_pre_migrations_20261121.dump`.
- No passwords or connection strings printed.

## 5) Result

**Backup PASS.** Verified custom-format backup of `rupaywala_ori` created successfully. Part B may be evaluated against stop conditions.