# RUPAYWALA_STAGE_5_6D_POSTGRESQL_VALIDATION_REPORT.md

**Stage:** 5.6D — PostgreSQL Security Validation (Isolated Validation DB, Read-Only Continuation)  
**Date:** 2026-11-21  
**Mode:** READ-ONLY / EVIDENCE-BASED / NO DB CHANGES  
**Status:** **PARTIALLY COMPLETE**

---

## 1. Executive Summary

Stage 5.6D validation was continued against the isolated PostgreSQL validation container only. Previously verified migration/schema/index checks remain valid. Additional read-only security checks were completed for RLS/policies, FK/unique/check constraint validation, indexes, role memberships, default privileges, relevant roles, schema/table/sequence/function ownership and ACLs, DB ACL/settings, and pg_hba inspection.

**What passed:** Alembic head `0007_user_token_version`; required 0006/0007 columns and 0006 indexes present; 37 FKs validated; 27 PK/unique/check constraints validated; no RLS/policies; no public-schema user functions; public schema has no PUBLIC CREATE; encoding/collation/extension reasonable.

**What did not pass / remains blocked:** The validation DB runs as superuser/owner `validation_admin` with no `rupaywala_owner/migrator/app` roles, no default privileges, and default/null object/DB ACLs. This is acceptable only as an isolated validation/admin context, not as production runtime posture. PostgreSQL auth/network settings are container-default/insecure for production (`listen_addresses=*`, `ssl=off`, trust local rules in pg_hba). Proposed production role separation has been drafted but **not executed**. No restricted-role application smoke test was run.

**Production readiness:** **Not ready**. Schema migration success does not imply production DB security readiness.

---

## 2. Exact PostgreSQL Environment

| Item | Value | Evidence |
|---|---|---|
| Container | `rupaywala-pg18-validation` | `docker ps` |
| Image | `postgres:18.1` | Prior verified context / container inspection |
| Port mapping | `127.0.0.1:55432->5432/tcp` | Prior verified context |
| DB | `rupaywala_validation` | `SELECT current_database()` |
| User/session | `validation_admin` / `validation_admin` | `SELECT current_user, session_user` |
| PostgreSQL version | `18.1 (Debian 18.1-1.pgdg13+2)` | `SELECT current_setting('server_version')` |
| Server addr/port | `NULL` / `5432` inside container context | `inet_server_addr(), inet_server_port()` |
| Encoding/collation | `UTF8` / `en_US.utf8` / `en_US.utf8` | `pg_database` |
| DB owner | `validation_admin` | `pg_database` |
| Extensions | `plpgsql 1.0` in `pg_catalog`, owner `validation_admin` | `pg_extension` |
| Settings | `listen_addresses=*`, `ssl=off`, `password_encryption=scram-sha-256`, `log_connections=''`, `log_disconnections=off`, `shared_preload_libraries=''` | `pg_settings` |
| Config files | `/var/lib/postgresql/18/docker/postgresql.conf`, `/var/lib/postgresql/18/docker/pg_hba.conf` | `pg_settings` |
| Original DB | `rupaywala_ori` | **Not accessed/modified** |

---

## 3. Verified Migration Status

| Check | Result | Classification | Evidence |
|---|---|---|---|
| Alembic version in validation DB | `0007_user_token_version` | PASS | `SELECT version_num FROM alembic_version ORDER BY version_num;` |
| 0006/0007 applied | Applied in validation DB | PASS | Alembic version + schema objects present |
| Migrations executed in this task | None | NOT EXECUTED | Read-only constraint |

---

## 4. Verified Schema Changes (0006/0007 Relevant)

| Check | Result | Classification | Evidence |
|---|---|---|---|
| `users.token_version` | integer, NOT NULL, default 0 | PASS | Prior verified read-only inspection |
| `service_quotes.signature_version` | integer, NOT NULL, default 1 | PASS | Prior verified |
| `service_requests.quote_ref` | nullable varchar | PASS | Prior verified |
| Public table inventory | 20 tables including `alembic_version` | PASS | `pg_tables`/`pg_class` |
| Sequence inventory | 19 sequences, all owned by `validation_admin` | PASS | `pg_sequences` |

---

## 5. Verified Indexes / Constraints

| Check | Result | Classification | Evidence |
|---|---|---|---|
| `uq_service_requests_quote_ref` | Present | PASS | `pg_indexes` |
| `uq_payments_user_type_idem_open` | Present, partial unique index on open pending/pending_verification idempotent payments | PASS | `pg_indexes` indexdef |
| `uq_payments_open_extra_charge_request` | Present, partial unique index on open extra_charge by related_request_id | PASS | `pg_indexes` indexdef |
| Foreign keys | 37 FKs, all `convalidated=true` | PASS | `pg_constraint WHERE contype='f'` |
| PK/unique/check constraints | 27 constraints, all `convalidated=true` | PASS | `pg_constraint WHERE contype IN ('u','c','p')` |
| Index inventory | 86 indexes total in public schema | PASS | `pg_indexes` |

---

## 6. Database Permissions Findings

| Area | Result | Classification | Evidence |
|---|---|---|---|
| Current role | `validation_admin` superuser/login/createrole/createdb/replication/bypassrls | PASS (identity) / FAIL (production posture) | `pg_roles` |
| Relevant app roles | `rupaywala_owner`, `rupaywala_migrator`, `rupaywala_app` absent | FAIL | `pg_roles` relevant query |
| DB ownership/ACL | `rupaywala_validation` owner `validation_admin`, `datacl NULL` | FAIL (least privilege) | `pg_database` |
| Schema ACL | `public` owner `pg_database_owner`; ACL `{pg_database_owner=UC/pg_database_owner,=U/pg_database_owner}` | PASS (no PUBLIC CREATE) / NOTE | `pg_namespace` |
| Table ownership | All 20 public tables owned by `validation_admin` | FAIL (separation of duties) | `pg_tables` |
| Sequence ownership | All 19 sequences owned by `validation_admin` | FAIL (separation of duties) | `pg_sequences` |
| Table privileges | Only `validation_admin` explicit grants in `role_table_grants` | FAIL (no app role model) | `information_schema.role_table_grants` |
| Sequence privileges | No explicit sequence grants in `role_usage_grants` | NOTE / FAIL for production model | `information_schema.role_usage_grants` |
| Routine privileges | No public routines | PASS | `role_routine_grants` / `pg_proc` |
| Default privileges | None | FAIL (future object control missing) | `pg_default_acl` |
| Role memberships | Only built-in pg_monitor memberships | PASS (no unexpected custom memberships) | `pg_auth_members` |
| RLS | All tables `relrowsecurity=false`, `relforcerowsecurity=false`; no policies | PASS (no misconfig) / NOTE | `pg_class`, `pg_policies` |
| pg_hba | trust local/127.0.0.1/::1, `host all all all scram-sha-256` | FAIL for production hardening | `pg_hba.conf` read-only cat |
| TLS/listen | `ssl=off`, `listen_addresses=*` | FAIL for production hardening | `pg_settings` |

---

## 7. Remaining Security Checks and Results

| Check | Result | Classification |
|---|---|---|
| Database/schema ownership | Inspected | PASS (evidence collected) |
| Table/sequence ownership | Inspected | PASS (evidence collected) |
| Effective/inherited privileges | Partially inspected; effective checks for `validation_admin` only; no restricted app role exists to test | BLOCKED / PARTIAL |
| Sequence-level permissions | Inspected | PASS (evidence collected) |
| PUBLIC access to tables/sequences/functions/schemas | Inspected; schema PUBLIC has USAGE only, no CREATE; object ACLs NULL | PASS / NOTE |
| RLS configuration/policies | Inspected | PASS |
| FK constraints and validation status | Inspected | PASS |
| Unique/check constraints | Inspected | PASS |
| Extensions installed | Inspected | PASS |
| DB encoding/collation | Inspected | PASS |
| DB connection/auth config safely inspectable | Inspected `pg_settings` and `pg_hba.conf` | PASS (evidence collected) / FAIL (hardening) |
| App DB URL handling / accidental validation DB use risk | Inspected config/alembic; no guardrails preventing env mispointing beyond discipline | RISK / BLOCKED for full prod assurance |
| Role/permission remediation execution | Not performed | NOT EXECUTED |
| Restricted-role application smoke tests | Not performed | NOT EXECUTED |

---

## 8. Production Runtime Role Recommendations

**Recommendation:** separate at minimum three roles:

1. **`rupaywala_owner` (NOLOGIN/admin-owned):** owns schema objects; used for controlled ownership/admin operations only.
2. **`rupaywala_migrator` (LOGIN, limited):** runs Alembic/migrations in approved windows; no superuser; inherits or receives required DDL/ownership rights; never used by app runtime.
3. **`rupaywala_app` (LOGIN, least privilege):** runtime only; CONNECT to DB, USAGE on schema, CRUD on required app tables, USAGE/SELECT on sequences; no CREATE/DDL/TRUNCATE/superuser/bypassrls.

**Observed runtime permission needs (from code inspection):**
- SQLAlchemy ORM CRUD across app tables (`users`, `customer_profiles`, `field_members`, `service_requests`, `service_quotes`, `payments`, `user_subscriptions`, `subscription_plans`, `notifications`, `otp_verifications`, `policies`, `policy_members`, `branches`, `distance_rate_config`, `service_types`, `request_assignments`, `visit_ledger`, `family_members`, `subscription_family_members`).
- Sequence usage for serial IDs on inserts.
- `app/services/plan_catalog.py:171-185` executes `setval(pg_get_serial_sequence('subscription_plans','id'), ...)` during startup seeding; this currently requires sequence UPDATE on `subscription_plans_id_seq`. **Preferred:** remove runtime setval and grant USAGE/SELECT only.
- No app runtime need for `alembic_version` DML, DDL, TRUNCATE, TRIGGER, REFERENCES, MAINTAIN, superuser, or BYPASSRLS.

**Proposed script (NOT EXECUTED):** `RUPAYWALA_STAGE_5_6D_PROPOSED_PRODUCTION_ROLE_SCRIPT.sql` (project root). Existing detailed artifact also reviewed: `database/security/stage_5_6d_postgresql_roles_corrected.sql`.

---

## 9. Outstanding Blockers

| ID | Blocker | Severity | Classification |
|---|---|---|---|
| B-001 | No restricted owner/migrator/app roles implemented/validated | Critical | BLOCKED / FAIL |
| B-002 | Validation/admin context uses superuser and owns all objects | Critical | FAIL for prod posture |
| B-003 | pg_hba trust rules, `ssl=off`, `listen_addresses=*` in inspected container config | High | FAIL for prod hardening |
| B-004 | Proposed role SQL not executed in disposable staging with app smoke tests | High | NOT EXECUTED |
| B-005 | Runtime setval() requires sequence UPDATE exception unless code changed | Medium | RISK |
| B-006 | Environment guardrails against accidental DB targeting not fully validated | Medium | RISK |

---

## 10. Commands and SQL Queries Used

```powershell
docker ps --format "{{.Names}}|{{.Image}}|{{.Ports}}|{{.Status}}"
docker exec rupaywala-pg18-validation psql -U validation_admin -d rupaywala_validation -c "SELECT current_database(), current_user, session_user, current_setting('server_version'), inet_server_addr(), inet_server_port();"
Get-Content <temp.sql> | docker exec -i rupaywala-pg18-validation psql -U validation_admin -d rupaywala_validation -v ON_ERROR_STOP=1 -f -
docker exec rupaywala-pg18-validation sh -c "cat /var/lib/postgresql/18/docker/pg_hba.conf"
git ls-files app/models alembic/versions
# Read-only code inspection: app/config.py, app/database.py, app/models/__init__.py, app/services/plan_catalog.py, app/main.py, alembic/env.py, alembic/versions/0006*, 0007*, database/security/stage_5_6d_postgresql_roles_corrected.sql
```

Key SQL (read-only):
```sql
SELECT version_num FROM alembic_version;
SELECT datname, pg_encoding_to_char(encoding), datcollate, datctype, pg_get_userbyid(datdba), datallowconn, datconnlimit FROM pg_database WHERE datname=current_database();
SELECT e.extname, e.extversion, n.nspname, pg_get_userbyid(e.extowner) FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace;
SELECT nspname, pg_get_userbyid(nspowner), nspacl::text FROM pg_namespace WHERE nspname IN ('public');
SELECT schemaname, tablename, tableowner FROM pg_tables WHERE schemaname='public';
SELECT schemaname, sequencename, sequenceowner FROM pg_sequences WHERE schemaname='public';
SELECT grantee, table_name, privilege_type, is_grantable FROM information_schema.role_table_grants WHERE table_schema='public';
SELECT grantee, object_name, privilege_type, is_grantable FROM information_schema.role_usage_grants WHERE object_schema='public' AND object_type='SEQUENCE';
SELECT grantee, specific_schema, routine_name, privilege_type, is_grantable FROM information_schema.role_routine_grants WHERE specific_schema='public';
SELECT n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p');
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check FROM pg_policies WHERE schemaname='public';
SELECT conname, conrelid::regclass::text, pg_get_constraintdef(oid), convalidated FROM pg_constraint WHERE contype='f' AND connamespace='public'::regnamespace;
SELECT conname, conrelid::regclass::text, contype, pg_get_constraintdef(oid), convalidated FROM pg_constraint WHERE contype IN ('u','c','p') AND connamespace='public'::regnamespace;
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname='public';
SELECT r.rolname member, m.rolname role, am.admin_option FROM pg_auth_members am JOIN pg_roles r ON r.oid=am.member JOIN pg_roles m ON m.oid=am.roleid;
SELECT pg_get_userbyid(defaclrole), defaclnamespace::regnamespace::text, defaclobjtype, defaclacl::text FROM pg_default_acl;
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolinherit, rolconnlimit, rolvaliduntil IS NOT NULL FROM pg_roles;
SELECT c.relname, c.relkind, pg_get_userbyid(c.relowner), c.relacl::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S','f');
SELECT datname, pg_get_userbyid(datdba), datacl::text FROM pg_database WHERE datname=current_database();
SELECT name, setting FROM pg_settings WHERE name IN ('hba_file','config_file','ssl','password_encryption','listen_addresses','log_connections','log_disconnections','shared_preload_libraries');
SELECT n.nspname, p.proname, pg_get_userbyid(p.proowner), p.proacl::text, l.lanname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace LEFT JOIN pg_language l ON l.oid=p.prolang WHERE n.nspname='public';
SELECT has_table_privilege('validation_admin','public.users','SELECT,INSERT,UPDATE,DELETE'), has_schema_privilege('validation_admin','public','USAGE,CREATE'), has_database_privilege('validation_admin','rupaywala_validation','CONNECT,TEMP,CREATE');
```

---

## 11. Evidence-Based PASS / FAIL / BLOCKED / NOT EXECUTED

| ID | Check | Classification | Evidence Summary |
|---|---|---:|---|
| C-001 | Alembic head `0007_user_token_version` | PASS | `alembic_version` has `0007_user_token_version` |
| C-002 | Required 0006/0007 columns | PASS | `users.token_version`, `service_quotes.signature_version`, `service_requests.quote_ref` verified |
| C-003 | Required 0006 indexes | PASS | `uq_service_requests_quote_ref`, `uq_payments_user_type_idem_open`, `uq_payments_open_extra_charge_request` present |
| C-004 | FK validation | PASS | 37 FKs, all `convalidated=t` |
| C-005 | Unique/check/PK validation | PASS | 27 constraints, all `convalidated=t` |
| C-006 | RLS/policies | PASS | No RLS enabled, no policies |
| C-007 | Public schema CREATE by PUBLIC | PASS | PUBLIC has USAGE only |
| C-008 | DB encoding/collation/extensions | PASS | UTF8/en_US.utf8, plpgsql |
| C-009 | Public functions/procedures | PASS | None found |
| C-010 | Ownership/privilege separation for production | FAIL | All owned by `validation_admin`; no app/migrator/owner roles |
| C-011 | Default privileges | FAIL | `pg_default_acl` empty |
| C-012 | DB/network/auth hardening | FAIL | `ssl=off`, `listen_addresses=*`, trust pg_hba rules |
| C-013 | Effective privileges under restricted runtime role | BLOCKED | No restricted role created/tested |
| C-014 | Role/grant remediation execution | NOT EXECUTED | Prohibited by task constraints |
| C-015 | App smoke tests under restricted role | NOT EXECUTED | Prohibited / no role model applied |
| C-016 | Accidental validation/prod DB targeting guardrails | RISK | Config/env inspection only; no runtime guardrail test |

---

## 12. Final Readiness Assessment

**Stage 5.6D status:** **PARTIALLY COMPLETE**.

- **Complete:** isolated validation DB inspection, migration/index/schema verification, remaining read-only catalog/security checks, production role recommendation draft, report/findings updates.
- **Incomplete/Blocked:** implementation and validation of least-privilege owner/migrator/app roles; restricted-role smoke testing; production hardening of TLS/pg_hba/listen/network/secret management; environment guardrail verification.

**Final assessment:** The validation database confirms schema migration readiness for 0006/0007 objects, but **does not confirm production PostgreSQL security readiness**. Do not claim production readiness. Do not modify `rupaywala_ori`. Use the proposed script only in an approved disposable staging flow.