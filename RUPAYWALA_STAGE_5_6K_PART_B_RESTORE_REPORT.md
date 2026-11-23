# RUPAYWALA Stage 5.6K Part B Restore Report

## Status

- **Executed (authorized):** read-only preflight, new database creation, verified backup restore, read-only verification.
- **Not performed:** no DB drops/overwrites, no `rupaywala_ori` modification, no `rupaywala_dev` modification, no Alembic migrations, no role/privilege changes, no `.env` changes, no credentials/connection strings printed.

## Source / Target

| Item | Value |
|---|---|
| Source database | `rupaywala_ori` |
| Verified source backup | `C:\RUPAAY_WALA\rupaywala_backend\database_backups\rupaywala_ori_stage56k_20261122_102506.dump` |
| Backup size | 105,241 bytes |
| Backup verification | `pg_restore --list` exit code 0 (272 TOC lines; dbname `rupaywala_ori`; TOC Entries 261) |
| New target database | `rupaywala_dev_stage56k` |
| Existing untouched database | `rupaywala_dev` |

## Step 1 — Preflight (PASS)

| Check | Result |
|---|---|
| PostgreSQL server identity | PostgreSQL 18.1, `localhost:5432`, user `postgres` |
| Source DB identity | `current_database()=rupaywala_ori`, Alembic `0005_fixed_quotes` |
| Backup file exists | Yes |
| `pg_restore --list` succeeds | Yes (exit code 0) |
| Target `rupaywala_dev_stage56k` exists before create | **No** (safe to create) |
| Existing `rupaywala_dev` exists | Yes - untouched; Alembic `0003_visit_credits_lifecycle` |

Preflight result: **PASS**. No stop condition triggered.

## Step 2 — Create and Restore (PASS)

| Action | Command/tool | Result |
|---|---|---|
| Create database | `psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"rupaywala_dev_stage56k\";"` (DB=postgres) | Exit code 0; `CREATE DATABASE` |
| Restore backup | `pg_restore --dbname rupaywala_dev_stage56k --no-owner --no-privileges --exit-on-error <backup>` | Exit code 0; no stderr errors reported |

- Restore target was `rupaywala_dev_stage56k` only.
- No restore into `rupaywala_ori` or `rupaywala_dev`.
- No restore errors observed; restore exit code 0.

## Step 3 — Post-Restore Verification (PASS)

| Check | `rupaywala_ori` (source) | `rupaywala_dev_stage56k` (restored) | Match |
|---|---|---|---|
| Database name | `rupaywala_ori` | `rupaywala_dev_stage56k` | Expected different |
| PostgreSQL version | 18.1 | 18.1 | Yes |
| Alembic revision | `0005_fixed_quotes` | `0005_fixed_quotes` | Yes |
| `users.token_version` exists | No | No | Yes |
| Public base table count | 20 | 20 | Yes |
| Table list | 20 tables (see verification report) | same 20 tables | Yes |
| Key row counts | users=28, alembic_version=1, service_requests=2, payments=9, service_quotes=0, user_subscriptions=2, subscription_plans=10 | identical | Yes |

## Safety Confirmation

- `rupaywala_ori` unchanged (Alembic `0005_fixed_quotes`, same counts/table set).
- `rupaywala_dev` untouched (Alembic `0003_visit_credits_lifecycle`, 18 tables, prior empty state observed).
- `rupaywala_dev_stage56k` created as new isolated DB; backup restored into it only.
- No Alembic migrations executed.

## Outcome

**PASS.** Verified backup restored into new isolated development database `rupaywala_dev_stage56k`. Ready for authorized migration testing in a future stage (0006->0007->0008), only against `rupaywala_dev_stage56k` with pre-flight DB confirmation.