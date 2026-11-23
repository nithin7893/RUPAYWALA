# RUPAYWALA STAGE 5.6E - ROLE VALIDATION FINDINGS

**Date:** 2026-11-21  
**Scope:** Isolated disposable staging DB `rupaywala_role_validation` on container `rupaywala-pg18-validation` (PG 18.1).  
**Safety:** `rupaywala_ori` and `rupaywala_validation` were NOT modified, dropped, or overwritten. No secrets/passwords recorded.

## Status: PARTIALLY COMPLETE

Core role separation, ownership transfer, grants, migrator compatibility, and app runtime DB privilege smoke checks passed in staging. Remaining items block production claim: full application E2E under restricted role not executed, runtime `setval()` exception remains, pytest safety not proven for this environment, and production infra/TLS/network/secret/deployment controls not validated.

## Findings

| ID | Severity | Status | Finding | Evidence | Impact | Recommended Remediation |
|---|---|---|---|---|---|---|
| F-001 | High | PASS WITH EXCEPTION | App runtime needs `UPDATE` on `subscription_plans_id_seq` because `app/services/plan_catalog.py` calls `setval()` during startup seeding. | App-role smoke: `SELECT setval(pg_get_serial_sequence('subscription_plans','id'),1,false)` succeeded as `rupaywala_app`; `setval` on `users_id_seq` denied. Code: `plan_catalog.py:171-185`, `app/main.py:176`. | Least-privilege gap: app can reset subscription plan sequence value. | Remove runtime `setval()` and use normal sequence/identity behavior; then revoke `UPDATE` on `subscription_plans_id_seq` from `rupaywala_app` and revalidate. |
| F-002 | Medium | PASS WITH NOTE | Default privileges for future tables are conservative (SELECT for app, USAGE for sequences). Explicit DML grants are required for new app-managed tables. | Migrator SET ROLE create-table probe in transaction: new table owned by `rupaywala_owner`, app had SELECT but not full DML by default. | New migrations may create tables app cannot write until grants reconciled. | Include grant reconciliation in migration/role-change runbook; validate post-migration privileges in staging. |
| F-003 | Medium | BLOCKED | Full application end-to-end compatibility under `rupaywala_app` was not executed. | Only targeted DB/ORM smoke tests were run (connect/select/insert/update/delete, seed plans, basic subscription/quote/service_request/payment inserts). No full API/UI/Flutter/E2E flow run. | Runtime role may still miss a required privilege in untested paths. | Run targeted integration smoke tests in disposable staging with app role credentials: auth, quote, request, payment, subscription, admin/field flows; monitor permission errors. |
| F-004 | Medium | NOT EXECUTED | `pytest` not run. | `tests/conftest.py` creates/drops `rupaywala_test` schema and sets test DB env at import; destructive behavior. Safety for current environment not proven beyond its own DB-name logic. | No automated regression evidence under role model. | Run pytest only in a dedicated disposable test DB/environment after confirming isolation. |
| F-005 | Medium | RISK | `family_members` table is denied to app role by design (no backend runtime path identified in corrected script), but model exists. | Grants show no `family_members` table/sequence privileges for `rupaywala_app`. | Future code using `family_members` may fail under restricted role. | Confirm intended use; if table becomes active, add least-privilege grants and tests. |
| F-006 | High | BLOCKED | Production infrastructure/security controls not validated. | Out of scope/unvalidated: production TLS, pg_hba hardening, network controls, backups/restore drills, secret management, deployment config, monitoring. | Staging role success does not equal production readiness. | Complete infra/security/deployment validation before production rollout. |
| F-007 | Low | PASS | App role cannot perform dangerous operations. | As `rupaywala_app`: `CREATE TABLE` denied (schema permission), `TRUNCATE` denied, `SELECT alembic_version` denied, `setval` on non-exception sequence denied. | Confirms least-privilege boundaries for tested operations. | Keep assertions in post-deploy verification. |

## Passed Controls

| ID | Status | Control | Evidence |
|---|---|---|---|
| P-001 | PASS | Staging DB created separately; existing DBs untouched. | `rupaywala_role_validation` created from `rupaywala_validation` template; `rupaywala_ori` not present in container; `rupaywala_validation` not modified. |
| P-002 | PASS | Role model created with least-privilege attributes. | Roles: `rupaywala_owner` NOLOGIN INHERIT; `rupaywala_migrator` LOGIN INHERIT; `rupaywala_app` LOGIN NOINHERIT; no superuser/createdb/createrole/replication/bypassrls. |
| P-003 | PASS | Ownership transferred to `rupaywala_owner`. | All public tables/sequences/types owned by `rupaywala_owner`; schema public owned by `rupaywala_owner`. |
| P-004 | PASS | App has no schema CREATE/DB CREATE and no alembic access. | `has_schema_privilege(app,public,CREATE)=f`; alembic SELECT/UPDATE false. |
| P-005 | PASS | Migrator can connect, read alembic, SET ROLE, PGOPTIONS role startup. | `current_user/session_user` checks passed; `alembic current` returned `0007_user_token_version`. |
| P-006 | PASS | Controlled reversible migration test by migrator. | `alembic downgrade -1` then `alembic upgrade head` on `rupaywala_role_validation` succeeded; head restored to `0007_user_token_version`; `users.token_version` present. |
| P-007 | PASS | App runtime DB smoke checks. | Connect/select/insert/update/delete/sequence nextval passed; seed_subscription_plans inserted 7 plans; basic subscription/quote/service_request inserts passed. |