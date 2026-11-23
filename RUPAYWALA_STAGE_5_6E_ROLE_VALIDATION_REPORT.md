# RUPAYWALA STAGE 5.6E - ROLE VALIDATION REPORT

**Date:** 2026-11-21  
**Stage:** 5.6E - Isolated PostgreSQL Role Separation and Application Compatibility Validation  
**Mode:** Staging-only, disposable DB, evidence-based. No secrets exposed.  
**Overall Status:** **PARTIALLY COMPLETE**

## 1. Executive Summary

Stage 5.6E created a new disposable staging database `rupaywala_role_validation` from `rupaywala_validation` on container `rupaywala-pg18-validation` (PostgreSQL 18.1). The existing `rupaywala_validation` and `rupaywala_ori` were not modified. A corrected least-privilege role model (`rupaywala_owner` NOLOGIN, `rupaywala_migrator` LOGIN, `rupaywala_app` LOGIN NOINHERIT) was applied in staging only. Ownership transfer, grants, default privileges, migrator Alembic compatibility, and app runtime DB smoke checks passed. Production readiness is **not** claimed.

## 2. Environment and Safety Evidence

| Item | Result | Evidence |
|---|---|---|
| Container | `rupaywala-pg18-validation`, postgres:18.1 | `docker ps` / prior validated context |
| Existing DBs before change | `postgres`, `rupaywala_validation`, `template0`, `template1` | `SELECT datname FROM pg_database ORDER BY 1;` |
| `rupaywala_role_validation` pre-existence | Did not exist before creation | DB listing above |
| Staging DB creation | Created from `rupaywala_validation` template | `CREATE DATABASE rupaywala_role_validation TEMPLATE rupaywala_validation;` returned `CREATE DATABASE` |
| Staging DB identity | `rupaywala_role_validation`, `validation_admin`, PG 18.1 | Identity query after creation |
| Staging DB baseline | Alembic `0007_user_token_version`; 20 tables; 19 sequences; public schema owned by `pg_database_owner` before role script | Read-only inspection queries |
| `rupaywala_ori` touched | No | Not present in container; no commands targeted it |
| `rupaywala_validation` modified | No | All role/grant/ownership changes executed only in `rupaywala_role_validation` |
| Backup present | `database_backups\rupaywala_validation_pre_migrations_20261121.dump` (96409 bytes) | `Get-Item` |

## 3. Role Design Review and Corrections

Inspected: `RUPAYWALA_STAGE_5_6D_PROPOSED_PRODUCTION_ROLE_SCRIPT.sql`, `database/security/stage_5_6d_postgresql_roles_corrected.sql`, `app/config.py`, `app/database.py`, `alembic/env.py`, `app/services/plan_catalog.py`, models, migrations, `tests/conftest.py`.

| Issue | Resolution in 5.6E | Classification |
|---|---|---|
| Proposed 5.6D script was placeholder/commented | Created executable staging-corrected script `RUPAYWALA_STAGE_5_6E_CORRECTED_ROLE_SCRIPT.sql` | PASS |
| Existing table/sequence ownership transfer | Transferred all public tables/sequences/views/mviews/foreign tables/types/domains to `rupaywala_owner` as superuser; handled table-owned sequence ordering | PASS |
| Alembic altering owner-owned objects as migrator | Verified `GRANT rupaywala_owner TO rupaywala_migrator`, `SET ROLE rupaywala_owner`, and PGOPTIONS `-c role=rupaywala_owner` work. Alembic current/downgrade/upgrade succeeded with PGOPTIONS. | PASS |
| Default privileges for migration-created objects | Conservative defaults: owner/migrator defaults grant SELECT on tables, USAGE on sequences to app; explicit DML grants required for known app tables. PGOPTIONS owner strategy recommended. | PASS WITH NOTE |
| App table CRUD permissions | Explicit table matrix granted; `alembic_version` revoked; `family_members` denied (no backend runtime path identified by prior corrected script). | PASS |
| Sequence USAGE/SELECT permissions | USAGE granted on runtime insert-table sequences; UPDATE only on `subscription_plans_id_seq` (temporary exception). | PASS WITH EXCEPTION |
| `setval()` startup requirement | Confirmed `plan_catalog.seed_subscription_plans()` uses `setval()`; app can setval on subscription_plans_id_seq, denied on users_id_seq. | PASS WITH EXCEPTION |
| No app CREATE/TRUNCATE/TRIGGER/REFERENCES/superuser/bypassrls | App CREATE TABLE denied; TRUNCATE denied; alembic denied; no dangerous role attrs. | PASS |

## 4. Staging Role Execution Results

| Step | Result | Evidence |
|---|---|---|
| Create roles | PASS | `rupaywala_owner`, `rupaywala_migrator`, `rupaywala_app` created with secure passwords (not recorded); role attrs verified |
| Membership | PASS | `GRANT rupaywala_owner TO rupaywala_migrator` applied |
| Schema/database access | PASS | CONNECT granted to migrator/app on staging DB; USAGE on public; PUBLIC CREATE revoked; schema owner `rupaywala_owner` |
| Ownership transfer | PASS | 20 tables + 19 sequences + schema owned by `rupaywala_owner` (verification query) |
| Explicit app grants | PASS | 54 table privilege rows; 18 sequence USAGE rows; no alembic privileges; app_connect=t, app_usage=t, app_create=f |
| Default privileges | PASS | Owner and migrator default privileges set conservatively for app |

## 5. Effective Privilege / Safety Checks

| Check | Result | Evidence |
|---|---|---|
| `rupaywala_app` SELECT alembic_version | DENIED (PASS) | `has_table_privilege(...,'SELECT')=f` |
| `rupaywala_app` CREATE TABLE | DENIED (PASS) | `ERROR: permission denied for schema public` |
| `rupaywala_app` TRUNCATE notifications | DENIED (PASS) | `permission denied for table notifications` |
| `rupaywala_app` setval users_id_seq | DENIED (PASS) | `permission denied for sequence users_id_seq` |
| `rupaywala_app` setval subscription_plans_id_seq | ALLOWED (EXPECTED EXCEPTION) | `setval` returned 1 |
| `rupaywala_app` nextval notifications_id_seq | ALLOWED (PASS) | `seq_ok=t` |

## 6. Migration Role Validation

| Check | Result | Evidence |
|---|---|---|
| Connect as `rupaywala_migrator` | PASS | `current_database=rupaywala_role_validation, current_user/session_user=rupaywala_migrator` |
| Read alembic version | PASS | `0007_user_token_version` |
| SET ROLE rupaywala_owner | PASS | `current_user=rupaywala_owner, session_user=rupaywala_migrator` |
| PGOPTIONS `-c role=rupaywala_owner` | PASS | same identity result |
| Controlled DDL as owner role (reversible) | PASS | Created `zz_stage56e_probe` table+sequence in transaction; owners `rupaywala_owner`; app SELECT default true; rolled back |
| Alembic current with PGOPTIONS | PASS | `alembic current` returned `0007_user_token_version` |
| Controlled reversible migration test | PASS | `alembic downgrade -1` (0007->0006) succeeded; `alembic upgrade head` restored 0007; `users.token_version` present |

## 7. Application Runtime Role Validation

| Check | Result | Evidence |
|---|---|---|
| DB connect as `rupaywala_app` | PASS | SQL and Python SQLAlchemy connect succeeded |
| ORM SELECT | PASS | User/plan counts queried |
| Controlled INSERT/UPDATE/DELETE with cleanup | PASS | User/profile create/update/delete smoke; notification insert/delete rollback smoke |
| Sequence-generated IDs | PASS | `nextval` on notifications sequence; serial IDs created |
| Startup plan seeding | PASS | `seed_subscription_plans()` ran as app role; 7 plans seeded; `setval` on subscription_plans_id_seq succeeded |
| Subscription operation | PASS | `UserSubscription` insert committed/cleaned |
| Service quote creation/retrieval | PASS | `ServiceQuote` insert committed/cleaned |
| Service request operation | PASS | `ServiceRequest` insert committed/cleaned |
| Payment record operation | PASS WITH NOTE | Insert reached DB constraint check (NotNullViolation on `expires_at`), not permission denial; confirms write path permitted |
| Full auth/quote/request/payment API E2E | NOT EXECUTED | Targeted DB smoke only; no full API run against staging with app role |

## 8. Pytest / Test-Suite Safety

| Check | Result | Evidence |
|---|---|---|
| `tests/conftest.py` inspected | PASS | Creates `rupaywala_test`, sets `DATABASE_URL` to test DB, drops/creates schema, truncates tables; destructive by design |
| Pytest safety proven for this environment | NOT PROVEN | Destructive behavior and env interaction; not run |
| Pytest executed | NOT EXECUTED | Used targeted non-destructive smoke tests instead |

## 9. Remaining Blockers

1. **B-001 (High):** Remove runtime `setval()` in `plan_catalog.seed_subscription_plans()` and revoke `subscription_plans_id_seq` UPDATE from app role.
2. **B-002 (Medium):** Full API/E2E smoke tests under restricted app role not run.
3. **B-003 (Medium):** Pytest not run due destructive conftest safety constraints.
4. **B-004 (Medium):** Default privileges are conservative; migration runbook must include explicit grant reconciliation for new tables.
5. **B-005 (High):** Production infra/security controls unvalidated (TLS, pg_hba, network, backups, secrets, deployment, monitoring).

## 10. Production Deployment Recommendations

- Do **not** apply role changes directly to production without approved window, backup/restore point, and staging evidence.
- Use `rupaywala_owner` (NOLOGIN) as object owner, `rupaywala_migrator` (LOGIN) only for migrations with `PGOPTIONS='-c role=rupaywala_owner'`, and `rupaywala_app` (LOGIN NOINHERIT) for runtime.
- Remove startup `setval()` before finalizing least privilege; revoke sequence UPDATE exception.
- Add post-migration privilege audit: table/sequence ownership, app grants, alembic inaccessible, no PUBLIC CREATE.
- Validate with restricted-role smoke tests and rollback plan.
- Separately validate TLS, pg_hba, network allowlists, secret rotation, backup/restore, monitoring/alerting.

## 11. Final Status

**Stage 5.6E: PARTIALLY COMPLETE**

Staging role separation and core compatibility checks passed in `rupaywala_role_validation`. Production readiness is **not** claimed.