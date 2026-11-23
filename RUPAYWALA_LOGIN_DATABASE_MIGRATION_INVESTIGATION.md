# RUPAYWALA Login Database Migration Mismatch Investigation

## Status

- **Read-only investigation only.** No database changes, no Alembic upgrade/downgrade, no schema/data modifications, no database/role creation.
- `rupaywala_ori` was inspected only via read-only identification/queries required for this investigation; no modifications performed.
- No credentials, DATABASE_URL values, passwords, tokens, or secret values are included in this report.

## Observed Runtime Error (from report)

- `OPTIONS /auth/login -> 200 OK`
- `POST /auth/login -> 500 Internal Server Error`
- PostgreSQL error: `psycopg2.errors.UndefinedColumn: column users.token_version does not exist`
- Application code expects migration: `0007_user_token_version`

## 1) Effective Database Configuration (no secrets)

| Check | Evidence | Result |
|---|---|---|
| App DB config source | `app/config.py` loads `DATABASE_URL` via required env/config (`_get("DATABASE_URL", required=True)`). | Effective DB is configured by `DATABASE_URL`. |
| Engine/session | `app/database.py` creates SQLAlchemy engine from `DATABASE_URL` with `pool_pre_ping=True`; `SessionLocal`/`get_db` use that engine. | Runtime backend uses this configured engine. |
| Alembic config | `alembic.ini` has empty `sqlalchemy.url`; `alembic/env.py` imports `DATABASE_URL` from `app.config` and creates engine from it for migrations. | Alembic targets the same configured `DATABASE_URL` as the app. |
| `.env` presence/keys (names only) | `.env` exists and contains `DATABASE_URL` key (value not inspected/reported). | Local env file supplies DB configuration. |

**Safe connection identity (from SQLAlchemy engine URL, password excluded):**

- Driver: `postgresql`
- Host: `localhost`
- Port: `5432`
- Database: `rupaywala_ori`
- Username: `postgres`

## 2) PostgreSQL Read-Only Checks

Queries executed via read-only `SELECT`/catalog inspection using the configured engine:

| Check | Result |
|---|---|
| Current database name | `rupaywala_ori` |
| Connected database user | `postgres` |
| Server version | `18.1` |
| `public.users` table exists | `true` |
| `public.users.token_version` column exists | **No** (`null` / not found in `information_schema.columns`) |
| `alembic_version` revision(s) | `0005_fixed_quotes` |
| Known DBs present on same server (`pg_database`) | `rupaywala_ori` only among `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation` |

## 3) Alembic Repository Head / Migration Chain

Repository migration inspection (`alembic heads`, migration files):

| Check | Result |
|---|---|
| Alembic head(s) | `0008_private_document_storage` (single head) |
| Migration chain tail | `0005_fixed_quotes` -> `0006_stage5_security_remediation` -> `0007_user_token_version` -> `0008_private_document_storage` |
| 0007 migration | `alembic/versions/0007_user_token_version.py` adds `users.token_version` `Integer NOT NULL server_default=0` |
| 0008 migration | `alembic/versions/0008_private_document_storage.py` adds document storage tables/indexes/FK; depends on 0007 |

## 4) Exact Mismatch

| Item | Expected | Actual (active DB) | Status |
|---|---|---|---|
| Active database | Intended local dev DB should be confirmed explicitly | `rupaywala_ori` | **Needs confirmation** - `rupaywala_ori` name does not indicate disposable/dev test DB; prior project reports treat it as non-disposable. |
| Alembic revision | `0008_private_document_storage` (repo head) | `0005_fixed_quotes` | **Mismatch** (3 revisions behind) |
| `users.token_version` | Present (added by 0007) | Missing | **Mismatch** - causes login 500 `UndefinedColumn` |
| Pending migrations on active DB | None | `0006_stage5_security_remediation`, `0007_user_token_version`, `0008_private_document_storage` | **Pending** |

**Conclusion:** The running backend is connected to `rupaywala_ori` on localhost:5432 (Postgres 18.1) as `postgres`. That database is at Alembic `0005_fixed_quotes` and lacks `public.users.token_version`, while the application/codebase expects at least 0007 (and repo head is 0008). This exactly explains `POST /auth/login -> 500` with `column users.token_version does not exist`.

## 5) Active Database Identity Classification

| Candidate | Classification |
|---|---|
| `rupaywala_ori` | **Active database** (confirmed by current_database/engine URL database name). |
| `rupaywala_validation` | Not active; not present on this PostgreSQL server instance per `pg_database` check. |
| `rupaywala_role_validation` | Not active; not present on this PostgreSQL server instance per `pg_database` check. |
| Another database | No other active DB detected; runtime config points to `rupaywala_ori`. |

## 6) Intended Local Development Database?

**Not confirmed as safe/intended disposable local development database.**

Evidence:
- The configured/active DB name is `rupaywala_ori` (name suggests "original", not disposable/dev scratch).
- Prior repo reports (`RUPAYWALA_DEMO_ENVIRONMENT_ASSESSMENT.md`, `RUPAYWALA_BACKEND_VERIFICATION_REPORT.md`, DB migration assessment reports) already flag `rupaywala_ori` as not confirmed disposable and treat it as non-disposable.
- Validation/role-validation DBs used in Stage 5.6 workflows are separate DBs; those names were not present on this server.

Before any remediation, a human must explicitly confirm whether `rupaywala_ori` is the intended mutable development target or a protected/original database.

## 7) Backup Availability

Filesystem scan (read-only) for backup/dump/sql artifacts under `C:\RUPAAY_WALA` (excluding venv/node_modules/.git noise) found:

| Backup/artifact | Path | Size | Last Write Time | Relevance to active DB |
|---|---:|---:|---|---|
| `rupaywala_role_validation_pre_56g_20261121_223922.dump` | `C:\RUPAAY_WALA\rupaywala_backend\database_backups\` | 109338 bytes | 2026-11-21 22:39:22 | Not a backup of `rupaywala_ori` |
| `rupaywala_validation_pre_migrations_20261121.dump` | `C:\RUPAAY_WALA\rupaywala_backend\database_backups\` | 96409 bytes | 2026-11-21 21:47:06 | Not a backup of `rupaywala_ori` |

**No suitable backup for active DB `rupaywala_ori` was found in the scanned workspace area.** Backup availability for `rupaywala_ori` is therefore **unconfirmed/insufficient**.

## 8) Safest Recommended Remediation (NOT performed)

1. **Do not run migrations yet.** Obtain explicit authorization confirming the intended target database.
2. **If `rupaywala_ori` is protected/original:** do not migrate it. Point local development to a separate disposable dev database (new or restored copy), take/verify backup, then migrate that disposable DB to head.
3. **If and only if `rupaywala_ori` is explicitly confirmed as the intended mutable local dev DB:** take a fresh verified PostgreSQL backup/dump of `rupaywala_ori` before any schema change; store it outside the DB; verify restore viability on a disposable copy where possible.
4. **After backup confirmation and authorization:** run Alembic upgrade in a controlled maintenance window on the confirmed target only, moving `0005_fixed_quotes` -> `0008_private_document_storage` (or at least through 0007 for the token_version error). Review 0006-0008 migration impact first; 0008 creates document tables/indexes/FK.
5. **Post-migration verification (read-only checks after change):** confirm `alembic_version == 0008_private_document_storage`, `public.users.token_version` exists, and login endpoint no longer fails with UndefinedColumn. Then perform application-level login test.
6. **Operational hygiene:** address legacy scripts containing hardcoded DB connection strings/credentials separately as a security cleanup task; this investigation did not modify them and does not reproduce their secret values.

## Stop Point

Investigation complete. **No remediation performed.** Awaiting explicit authorization before any migration/backup/DB-target change.