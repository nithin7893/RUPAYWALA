# RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md

**Stage:** 5.6D — final SQL remediation and static validation  
**Date:** 2026-11-21  
**Mode:** STATIC PREPARATION ONLY — NO DATABASE CONNECTION, NO SQL EXECUTION, NO ALEMBIC EXECUTION  
**Scope:** Disposable PostgreSQL 18.1 validation environment only. Production is strictly out of scope.

**Label legend:** `SOURCE VERIFIED` = read directly from repository source; `STATICALLY VALIDATED` = internally consistent across the final artifacts; `PROPOSED` = future approved action; `UNVERIFIED` = needs runtime evidence; `NOT EXECUTED` = no execution proof exists.

---

## 1. Executive summary

`NOT EXECUTED`: this task updated only the three permitted preparation artifacts. No connection, SQL statement, Alembic command, container operation, role change, permission change, secret access, or Stage 6 work occurred.

`SOURCE VERIFIED`: the actual source and all seven migrations were inspected. The runtime privilege matrix was derived from real code paths, not copied from earlier reports. Important source-derived corrections include:

- server-side port gate must expect internal `5432`, while `127.0.0.1:55432` is a client-side mapping that `inet_server_port()` cannot prove;
- psql variables must not appear inside `DO $$ ... $$`;
- `b96aae0ed4c8` requires 1 table + 7 indexes + 3 constraints, not “nine more” objects;
- `distance_rate_config` needs SELECT/INSERT only — the admin “update” inserts a new immutable row;
- `family_members` and `alembic_version` must have zero application privileges;
- the subscription-plan sequence UPDATE exists only because runtime seeding calls `setval()`.

`STATICALLY VALIDATED`: the three final artifacts are internally consistent on identity gates, revision checkpoints, object inventory, privilege matrix, role model, ownership scope, default privileges, and 0006 preflight structure. The final pre-execution audit additionally corrected the exact version gate, PG18 privilege completeness, smoke-test prerequisites, and the Alembic ownership runbook. SQL §7A (H-05 role-membership completeness) and SQL §7B (H-06 database/schema ACL completeness) remain as post-change assertions, and the read-only SQL §13 exhaustive public-object allowlist remains intact. A new read-only SQL §1A preflight (`:350-1411`) now runs before the first mutation and checks existing target-role memberships/options, direct database/schema ACL provenance, the full public relation/sequence allowlist, and the unnormalized Section 7.10 provenance layer (GLOBAL and per-schema `pg_default_acl`, existing custom-type/routine ACLs, effective PUBLIC/app access, and grant options), including explicit extension-owned-object handling. No unexpected membership, ACL, privilege or object is silently revoked or repaired; every unsafe preflight finding aborts before `CREATE ROLE` with exact object, grantee, privilege, ACL source and grant-option details.

**Final static-review verdict: STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW**. This is not execution readiness and not production readiness. Live PostgreSQL 18.1 parsing/catalog execution, the preflight assertions, role authentication, PGOPTIONS identity verification, application-role behavioural tests, backup restoration and post-0006 ownership verification remain separate mandatory gates. The next stage requires explicit approval and must be performed only against the disposable PostgreSQL 18.1 environment.

`UNVERIFIED`: full PostgreSQL parsing/execution, catalog states, backup/restore success, interactive password provisioning, migration behaviour, and application-role behavioural tests. No SQL parser is installed in the project environment; full execution validation remains pending.

---

## 2. Files inspected

### Existing preparation artifacts

- `database/security/stage_5_6c_postgresql_roles.sql`
- `database/security/stage_5_6d_postgresql_roles_corrected.sql` (updated)
- `database/security/stage_5_6d_disposable_bootstrap_plan.md` (context only; not modified in this remediation pass)
- `RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md` (updated)

### Historical migration chain — `SOURCE VERIFIED`

- `alembic/versions/0001_initial_schema_initial_schema.py`
- `alembic/versions/0002_expand_enums.py`
- `alembic/versions/0003_visit_credits_and_lifecycle.py`
- `alembic/versions/b96aae0ed4c8_add_email_otp_support.py`
- `alembic/versions/0004_subscription_entitlements.py`
- `alembic/versions/0005_fixed_quotes.py`
- `alembic/versions/0006_stage5_security_remediation.py`
- `alembic/env.py`

### Runtime source — `SOURCE VERIFIED`

- `app/main.py`
- `app/database.py`
- `app/config.py`
- `app/services/plan_catalog.py`
- All `app/models/*.py`
- All `app/routes/*.py`
- All `app/services/*.py`
- `app/utils/dependencies.py`

### Test infrastructure — `SOURCE VERIFIED`

- `tests/conftest.py`
- `tests/factories.py`
- `pytest.ini`

---

## 3. Findings from actual source inspection

### 3.1 Migration chain and bootstrap requirement — `SOURCE VERIFIED`

- Chain order is exactly `0001 -> 0002 -> 0003 -> b96aae0ed4c8 -> 0004 -> 0005 -> 0006`.
- `b96aae0ed4c8.upgrade()` line 21 drops `activity_logs`; earlier fresh-chain migrations never create it.
- The same migration drops seven legacy indexes and three legacy unique constraints at lines 76–79, 88, 101–102, 131, 154–155.
- No additional objects are dropped by that migration.
- `0006` changes exactly five schema objects: one column on `service_quotes`, one column and one unique constraint on `service_requests`, and two partial unique indexes on `payments`.

### 3.2 Runtime permission findings — `SOURCE VERIFIED`

- 18 tables have real backend read/write paths.
- `family_members` is only registered as a model (`app/models/family_member.py:7`, `app/models/__init__.py:11,35`, `app/main.py:39`); no route or service queries or mutates it. `max_family_members` is a plan field, not table access.
- `alembic_version` has no reference under `app/`.
- `distance_rate_config` is insert-only: `app/routes/admin_routes.py:831-852` creates a new immutable row instead of updating the old one. The existing UPDATE grant was therefore removed.
- `policy_members` requires DELETE through the ORM cascade declared at `app/models/policy.py:32-34` when `db.delete(policy)` runs at `app/routes/policy_routes.py:166`.
- `SELECT ... FOR UPDATE` appears in request, payment, quote, subscription, assignment, and field-member paths; those tables already require UPDATE from explicit writes.

### 3.3 Sequence finding — `SOURCE VERIFIED`

`app/services/plan_catalog.py:171-185` calls:

- `db.execute(` at line 174;
- `text(` at line 175;
- `setval(` at line 177;
- `pg_get_serial_sequence('subscription_plans', 'id')` at line 178.

The call is reached from `app/main.py:167` inside `seed_reference_data()`, invoked by startup at `app/main.py:186`. The helper is invoked even when `DEBUG` is false; only `TESTING` skips startup seeding.

### 3.4 Alembic executor finding — `SOURCE VERIFIED`

`alembic/env.py` reads `DATABASE_URL` from `app.config` and imports models for metadata. It sets `transaction_per_migration=True`. It does not issue `SET ROLE`. A migration run as `rupaywala_migrator` therefore records new objects as owned by the migrator unless an operator explicitly changes role for the migration session.

### 3.5 Test infrastructure finding — `SOURCE VERIFIED`

`tests/conftest.py` reuses configured server credentials, falls back to a hard-coded local superuser credential pair, creates a dedicated test database, drops/recreates `public`, uses `Base.metadata.create_all()`, truncates all mapped tables with `RESTART IDENTITY CASCADE`, and guards destructive operations only on `engine.url.database == 'rupaywala_test'` (`tests/conftest.py:35,43-110,123-203`). See section 13.

---

## 4. Issues identified in the previous Stage 5.6D artifacts

| ID | Severity | Previous issue | Why it was wrong |
|---|---|---|---|
| P-01 | Critical | Server-side port gate expected `55432` | `inet_server_port()` reports the internal container port `5432`, not the Docker host mapping. |
| P-02 | Critical | `:'db_owner_before'` used inside `DO $$ ... $$` | psql variables are not substituted inside dollar-quoted procedural bodies; ownership verification could fail or never execute correctly. |
| P-03 | Critical | Bootstrap wording said “nine more” legacy objects | Actual migration drops 10 additional objects beyond `activity_logs` (7 indexes + 3 constraints). |
| P-04 | High | `distance_rate_config` had UPDATE | Source shows update is implemented as a new INSERT; UPDATE is unnecessary. |
| P-05 | High | Application-role negative tests were active in the DBA file | Running the file as `validation_admin` would execute destructive-looking probes as the wrong role. They are now a line-commented extract. |
| P-06 | High | Full positive smoke-test SQL was not in the SQL artifact | The artifact only referenced a report section; the application-role extract now contains complete DML tests. |
| P-07 | High | `session_user` was not gated | Only `current_user` was checked; a role-switching session could bypass the intended identity gate. |
| P-08 | Medium | Sequence SELECT granted | No runtime `currval()` path exists; minimum is USAGE plus temporary UPDATE on one sequence. |
| P-09 | Medium | Default privileges were additive only | Stale default INSERT/UPDATE/DELETE/SELECT ACLs could survive from prior state. Defaults are now reconciled. |
| P-10 | Medium | `migrator_schema_create=true` was stated as expected | On PG18 this depends on ownership inheritance and actual execution; it is now informational and marked UNVERIFIED. |
| P-11 | Medium | 0006 checklist lacked backup/restore, maintenance, lock and downgrade details | These are now explicit human prerequisites in both artifacts. |
| P-12 | Medium | Test-infrastructure safety findings were absent | `tests/conftest.py` risks are now documented with future remediation recommendations. |
| P-13 | Low | Client mapping `127.0.0.1:55432` was not separated from server-side verification | `\conninfo` instruction and explicit distinction now exist in both artifacts. |

---

## 5. Corrections implemented

`STATICALLY VALIDATED` in the final artifacts:

1. Server gate changed to `inet_server_port() = 5432`; TCP required via non-null `inet_server_addr()`.
2. Client mapping `127.0.0.1:55432` moved to a separate `\conninfo` verification instruction.
3. Added explicit `current_user`, `session_user`, database, and version gates.
4. Replaced the invalid psql variable inside `DO $$` with `set_config()`/`current_setting()`.
5. Database owner is recorded before any operation and rechecked by ordinary PL/pgSQL — no psql substitution inside dollar quotes.
6. Legacy object inventory corrected to 1 table + 7 indexes + 3 constraints, with a line-by-line migration table.
7. Removed UPDATE from `distance_rate_config`; added strict negative assertion that it has no UPDATE.
8. Added a complete line-commented application-role extract with negative and positive tests.
9. Added exact table privilege reconciliation (`REVOKE ALL` then precise GRANTs) for the app role only.
10. Added sequence reconciliation: USAGE only, no SELECT, plus temporary UPDATE on the subscription-plan sequence.
11. Added default-privilege reconciliation for owner and migrator roles.
12. Added strict catalog assertions for all required permissions and all prohibited permissions.
13. Added explicit ownership assertions for relations, enums, domains, and standalone composites, excluding extension-owned objects.
14. Added explicit note that Alembic does not issue `SET ROLE`; ownership implications are documented.
15. Added full 0006 preflight structure, expected post-upgrade objects, and downgrade consequences.
16. Added test-infrastructure safety findings and future remediation recommendations.
17. Added SQL §7A (H-05): exact `pg_auth_members` direction and option audit for `member`, `roleid`, `inherit_option`, `set_option` and `admin_option`, with fail-closed exact-state output and no silent revoke.
18. Added SQL §7B (H-06): direct `datacl`/`nspacl` provenance audit using `aclexplode()`, `acldefault()`, `pg_get_userbyid()`, `has_database_privilege()` and `has_schema_privilege()`, with separate effective-privilege and grant-option checks and no silent revoke.
19. Added read-only SQL §1A (`:350-1411`) before the first mutation: preflight H-05 membership/option checks (`:363-465`), preflight H-06 `datacl`/`nspacl` provenance checks (`:467-691`), preflight §13 public relation/sequence allowlist checks with explicit extension-owned-object handling (`:693-1011`), and preflight §7.10 provenance checks for states not normalized by Sections 4-5 (`:1013-1411`; evidence `:1030-1112`, assertions `:1114-1411`). Every unsafe preflight finding aborts before `CREATE ROLE` at `:1430`; no finding is automatically revoked or repaired.
20. Added the complete changed-files list in §16.4 and updated all SQL line references to the final 3,725-line artifact.

---

## 6. PostgreSQL 18.1 compatibility assessment

| Item | Assessment | Label |
|---|---|---|
| Catalog views/functions used (`pg_roles`, `pg_auth_members`, `pg_authid`, `pg_database`, `pg_namespace`, `pg_class`, `pg_type`, `pg_proc`, `pg_default_acl`, `pg_extension`, `pg_depend`, `has_*_privilege`, `pg_get_serial_sequence`, `to_regclass`, `format`, `set_config`, `current_setting`) | Available in PostgreSQL 18.1. | `STATICALLY VALIDATED` |
| `split_part(current_setting('server_version'),' ',1) = '18.1'` plus `server_version_num='180001'` | Exact guard: rejects `18.10+` that the earlier four-character check could accept. | `STATICALLY VALIDATED` |
| `inet_server_port()` | Available; reports internal listener port only. | `SOURCE VERIFIED` |
| `psql` meta-commands (`\set`, `\gset`, `\if`, `\password`, `\conninfo`, `\set ON_ERROR_STOP`) | Supported by PostgreSQL 18 psql; file must be run with psql. `\password` requires an interactive TTY when a new login role is created. | `STATICALLY VALIDATED` |
| Table `REFERENCES` and `MAINTAIN` (PG18) | Added to evidence queries and strict negative assertions, including the zero-privilege check for `family_members` and `alembic_version`. | `STATICALLY VALIDATED` |
| Extension exclusion via `pg_depend.deptype IN ('e','x')` | Preserved; `'x'` is legacy but accepted. The same pattern now also classifies extension-owned public objects in preflight §1A.3 and aborts before mutation instead of silently treating them as application objects. | `STATICALLY VALIDATED` |
| Preflight-before-mutation ordering | §1A reads target-role memberships, direct `datacl`/`nspacl` provenance and the full public object inventory before `CREATE ROLE` at `:1430`, before grants and before `ALTER SCHEMA public OWNER TO`; `ON_ERROR_STOP` makes every failure abort the file. | `STATICALLY VALIDATED` |
| `ALTER TYPE ... ADD VALUE IF NOT EXISTS` in `b96` | Commit-sensitive; `transaction_per_migration=True` is present. | `SOURCE VERIFIED` |
| `postgresql_nulls_not_distinct=False` in `b96.downgrade()` | Requires PG15+; 18.1 satisfies. | `SOURCE VERIFIED` |
| Fresh-PG18 `public` schema defaults | `CREATE` for `PUBLIC` normally absent; artifact reports state and does not silently revoke. | `STATICALLY VALIDATED` |
| `pg_auth_members.inherit_option`, `set_option`, `admin_option` (PG16+/PG18) | Audited post-change in SQL §7A and pre-change in SQL §1A.1; an existing migrator-to-owner row must be exactly `true/true/false`, while an absent row is allowed because Section 2 adds it. | `STATICALLY VALIDATED` |
| `acldefault('d', datdba)` and `acldefault('n', nspowner)` | PostgreSQL 18 supported type codes for database and schema; used for NULL `datacl`/`nspacl` in preflight SQL §1A.2 and post-change SQL §7B. | `STATICALLY VALIDATED` |
| `pg_default_acl` inspection in SQL §1A.4 (`:1030-1049`, `:1124-1229`) | Read-only evidence and fail-closed checks of all six PG18 default ACL classes for `rupaywala_owner`/`rupaywala_migrator`; per-schema `r`/`S` app deltas are allowed because Sections 4-5 explicitly normalize them. | `STATICALLY VALIDATED` |
| `has_type_privilege()`, `has_function_privilege()`, `aclexplode()` and `acldefault()` in SQL §1A.4 (`:1051-1112`, `:1230-1389`) | Read-only checks of effective app access, built-in PUBLIC `USAGE`/`EXECUTE`, and app/PUBLIC grant-option state on existing custom types and routines; no ACL is changed. | `STATICALLY VALIDATED` |
| SQL parser availability | `pglast` and `sqlparse` are not installed; no parser was installed. Full execution validation pending. | `UNVERIFIED` |

---

## 7. Exact legacy bootstrap object inventory

See `database/security/stage_5_6d_disposable_bootstrap_plan.md` §5 for the full source-line table. Summary:

| Object | Type | Migration operation | Before | After |
|---|---|---|---|---|
| `activity_logs` | table | `drop_table` line 21 | present | absent |
| `idx_payments_txn_id` | index | `drop_index` line 76 | present | absent |
| `idx_payments_utr` | index | `drop_index` line 77 | present | absent |
| `payments_txn_id_key` | unique constraint | `drop_constraint` line 78 | present | absent |
| `payments_utr_number_key` | unique constraint | `drop_constraint` line 79 | present | absent |
| `idx_policies_user` | index | `drop_index` line 88 | present | absent |
| `idx_requests_policy` | index | `drop_index` line 101 | present | absent |
| `idx_requests_user` | index | `drop_index` line 102 | present | absent |
| `idx_subscription_user` | index | `drop_index` line 131 | present | absent |
| `idx_users_phone` | index | `drop_index` line 154 | present | absent |
| `users_phone_number_key` | unique constraint | `drop_constraint` line 155 | present | absent |

Totals: **1 table + 7 indexes + 3 constraints = 11 objects**; **10 additional objects beyond the table**. No other object is dropped by `b96aae0ed4c8`.

---

## 8. Runtime database permission matrix

`SOURCE VERIFIED`: S/I/U/D = SELECT / INSERT / UPDATE / DELETE. “—” means no privilege. No row is granted merely because it appears in a model.

| Table | S | I | U | D | Source evidence / note |
|---|---:|---:|---:|---:|---|
| `users` | ✓ | ✓ | ✓ | — | Reads `app/utils/dependencies.py:80`, `app/routes/admin_routes.py:216`; inserts `app/routes/auth_routes.py:336,400,484`, `app/routes/admin_routes.py:369`; updates `app/routes/auth_routes.py:282`, `app/routes/admin_routes.py:439,574`. |
| `branches` | ✓ | ✓ | ✓ | — | Reads in service routes; insert `app/routes/admin_routes.py:709`; deactivate `app/routes/admin_routes.py:803`; no delete path. |
| `customer_profiles` | ✓ | ✓ | ✓ | — | Reads `app/routes/field_member_routes.py:49,165`; insert `app/routes/profile_routes.py:57`; update `app/routes/profile_routes.py:76`. |
| `field_members` | ✓ | ✓ | ✓ | — | Reads `app/utils/dependencies.py:80`; insert `app/routes/admin_routes.py:381`; updates `app/routes/admin_routes.py:439-502`, `app/routes/field_member_routes.py:404`. |
| `notifications` | ✓ | ✓ | ✓ | ✓ | `app/services/notification_service.py:25,32,41,54,63,74`. |
| `otp_verifications` | ✓ | ✓ | ✓ | ✓ | `app/services/otp_service.py:97,173,193,205,229,241,264,287`. |
| `payments` | ✓ | ✓ | ✓ | — | Inserts `app/services/payment_service.py:106,211`; updates/locks `:149,271,306,354,376,406,425,473`. |
| `policies` | ✓ | ✓ | — | ✓ | Insert `app/routes/policy_routes.py:54`; delete `:166`; no UPDATE path. |
| `policy_members` | ✓ | ✓ | — | ✓ | Insert `app/routes/policy_routes.py:59`; DELETE via ORM cascade `app/models/policy.py:32-34` + `db.delete(policy)`. |
| `request_assignments` | ✓ | ✓ | ✓ | — | `app/services/assignment_service.py:39,94,104,126`; no delete path. |
| `service_quotes` | ✓ | ✓ | ✓ | — | `app/services/quote_service.py:513,530,551,562,573,617,620,734`; no delete path. |
| `service_requests` | ✓ | ✓ | ✓ | — | Insert `app/routes/service_routes.py:685`, `app/services/quote_service.py:729`; status updates `app/services/request_status_service.py:81`, lock `app/routes/service_routes.py:748`. |
| `service_types` | ✓ | ✓ | ✓ | — | Seed insert/read `app/main.py:143-154`; admin insert/update `app/routes/admin_routes.py:898,911`. |
| `subscription_plans` | ✓ | ✓ | ✓ | — | Seed read/update `app/services/plan_catalog.py:190-201`; admin activate/deactivate `app/routes/admin_routes.py:993,1007`. |
| `subscription_family_members` | ✓ | ✓ | — | ✓ | `app/routes/subscription_routes.py:235,326,349`; no UPDATE path. |
| `user_subscriptions` | ✓ | ✓ | ✓ | — | Insert `app/services/subscription_service.py:177`; updates `:206,222`, `app/services/visit_service.py:202,253`; no delete path. |
| `visit_ledger` | ✓ | ✓ | — | — | `app/services/visit_service.py:130,203,254`; append-only. |
| `distance_rate_config` | ✓ | ✓ | — | — | Read `app/main.py:156`, `app/routes/admin_routes.py:815`; insert `app/main.py:157`, `app/routes/admin_routes.py:843-851`; update path does not exist. |
| `family_members` | — | — | — | — | Model/import registration only; no runtime DML. Explicit `REVOKE ALL` and strict zero-privilege assertion. |
| `alembic_version` | — | — | — | — | No reference under `app/`. Explicit `REVOKE ALL` and strict zero-privilege assertion. |

Sequences:

- USAGE on all 18 insert-target `id` sequences.
- No SELECT on sequences; no runtime `currval()` call found.
- UPDATE only on the sequence returned by `pg_get_serial_sequence('public.subscription_plans','id')`, temporarily.

### 8.1 Complete exhaustive public-object allowlist (SQL §13)

`SOURCE VERIFIED` cross-check: the 18 runtime rows in the matrix above correspond exactly to the 18 model files with backend read/write paths under `app/models/*.py`. `family_members` is registered at `app/models/family_member.py:7` but has no runtime DML; `alembic_version` comes from the migration chain and has no `app/` reference. No migration creates a view, materialized view or foreign table, so relkinds `v`, `m` and `f` are unexpected in `public` and fail closed if present.

The matrix in section 8 plus the following object classes is the complete allowlist used by SQL §13 (`:3486-3529`):

| Object class | Allowed object set | Allowed direct/effective privileges for `rupaywala_app` | PUBLIC |
|---|---|---|---|
| `r`/`p` runtime table | The 18 rows in section 8 | Exactly the S/I/U/D combination shown; each expected privilege must exist as a direct ACL entry; TRUNCATE/TRIGGER/REFERENCES/MAINTAIN always false | No direct ACL entry of any kind |
| `r`/`p` deny table | `family_members`, `alembic_version` | All eight table privileges false; no direct app ACL entry | No direct ACL entry of any kind |
| `r`/`p`/`v`/`m`/`f` unlisted | Any other public relation | All privileges false; object itself reported as `UNLISTED_OBJECT` | No direct ACL entry of any kind |
| `S` runtime sequence | `pg_get_serial_sequence(public.<table>, 'id')` for each of the 18 insert tables | USAGE true and directly granted; SELECT false; UPDATE true and directly granted only for `subscription_plans`, false otherwise | No direct ACL entry of any kind |
| `S` unlisted | Any other public sequence | All privileges false; object itself reported as `UNLISTED_OBJECT` | No direct ACL entry of any kind |

A listed name whose `relkind` is not the expected `r`/`p` or `S` is a `RELKIND_MISMATCH` violation. Grant options are never allowed for `rupaywala_app` or PUBLIC on any object in this audit. Owner and migrator privileges are outside this app/PUBLIC allowlist and are not modified: §13 issues no `GRANT`, `REVOKE`, `ALTER` or destructive command, and the existing ownership assertions remain in force.

---

## 9. Role and ownership design

| Role | Attributes | Membership | Password handling |
|---|---|---|---|
| `rupaywala_owner` | NOLOGIN, INHERIT, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOBYPASSRLS, NOREPLICATION | None | No password provisioned by this artifact. |
| `rupaywala_migrator` | LOGIN, INHERIT, forbidden privilege attributes absent | Sole permitted row: member of `rupaywala_owner` with `inherit_option=true`, `set_option=true`, `admin_option=false`; INHERIT supplies inherited DDL privileges and SET permits the PGOPTIONS startup role | Interactive `\password` only when newly created; existing password never reset. |
| `rupaywala_app` | LOGIN, NOINHERIT, forbidden privilege attributes absent | None | Interactive `\password` only when newly created; existing password never reset. |

`STATICALLY VALIDATED`:

- Role creation is idempotent through psql `\gset`/`\if`. Existing role attributes and passwords are not changed.
- The membership grant is the one role-configuration mutation: it idempotently adds `rupaywala_owner` to `rupaywala_migrator`; it never grants ADMIN OPTION and never adds membership to `rupaywala_app`.
- SQL §1A.1 (`:363-465`) checks existing role memberships before that mutation. An absent migrator-to-owner row is allowed; an existing row must have `inherit_option=true`, `set_option=true`, `admin_option=false`; every other row touching the three target roles aborts before mutation.
- SQL §7A inspects both `pg_auth_members.member` and `.roleid` and requires the exact option triple `inherit_option=true`, `set_option=true`, `admin_option=false` on the sole permitted migrator-to-owner row after the mutation.
- `INHERIT` is not treated as proof that startup role switching works: `set_option=true` is separately required for the Section 10 `PGOPTIONS='-c role=rupaywala_owner'` strategy.
- Existing conflicting role attributes, unexpected memberships in either direction, unexpected membership options, ADMIN OPTION, or a migrator/app role without a password abort explicitly.
- Database ownership is recorded and verified unchanged; no database-owner transfer command is present.
- Schema `public` is owned by `rupaywala_owner`; no routine ownership transfer is performed.
- Object ownership transfer covers tables, sequences, views, materialized views, foreign tables, enums, domains, and standalone composite types.
- SQL §1A.2 (`:467-691`) validates direct `datacl`/`nspacl` provenance before any database/schema grant or the public-schema ownership change; required PUBLIC defaults must exist, optional target CONNECT/USAGE entries may be absent but must be non-grantable if present, and unexpected entries or grant options abort before mutation.
- SQL §1A.3 (`:693-1011`) inventories every public `r`/`p`/`v`/`m`/`f`/`S` object before ownership transfer and grants; unlisted objects, missing expected objects, wrong relkinds, unexpected app/PUBLIC ACLs, grant options and forbidden pre-existing effective privileges abort before mutation.
- Extension-owned objects are excluded from ownership transfer via `pg_depend` → `pg_extension`; preflight §1A.3 uses the same detection pattern and aborts explicitly on any extension-owned public object instead of silently treating it as an ordinary application object.
- Indexes, constraints, TOAST objects, arrays, and table-associated row types are not independently re-owned.
- Default privileges for both owner and migrator are reconciled to SELECT on future tables and USAGE on future sequences and asserted in SQL §7.10.
- `alembic/env.py:13,77` does not issue `SET ROLE`; this is `SOURCE VERIFIED`, not merely unverified.

`UNVERIFIED`: the live effect of the chosen `PGOPTIONS='-c role=rupaywala_owner'` startup setting on the actual Alembic connection, and the observed `set_option`/`inherit_option` values in the disposable catalog. Source and PostgreSQL semantics establish that INHERIT alone permits DDL but does not prove startup role switching and does not change `relowner` for newly created objects; the required runbook in SQL §10/plan §10 must be validated with an identical-environment identity probe before migration. Post-upgrade owner verification remains mandatory.

---

## 10. Positive and negative test specifications

### 10.1 Catalog checks — `STATICALLY VALIDATED`, embedded in SQL §1A and §7

- Identity, version, internal port, TCP, superuser gate.
- Database owner unchanged.
- Revision `0005_fixed_quotes`.
- Role attributes and memberships; no ADMIN OPTION.
- PUBLIC database CONNECT/TEMP and schema USAGE true, schema CREATE false are asserted; no automatic PUBLIC revocation or broad grant.
- App CONNECT/TEMP/USAGE present; app CREATE on schema/database absent.
- Owner/migrator database CREATE false; owner schema CREATE and inherited migrator schema CREATE true.
- Schema owner is asserted as `rupaywala_owner`; no object is owned by `rupaywala_app`.
- `family_members` and `alembic_version`: all eight PG18 table privileges false (S/I/U/D/TRUNCATE/TRIGGER/REFERENCES/MAINTAIN).
- Full S/I/U/D matrix checked; unnecessary UPDATE/DELETE, TRUNCATE, TRIGGER, REFERENCES and MAINTAIN checked.
- Sequence USAGE/SELECT/UPDATE matrix checked.
- Custom-type USAGE and routine EXECUTE are checked two ways in SQL §7.10 (`:2294-2367`): `has_type_privilege()`/`has_function_privilege()` prove effective permissions for `rupaywala_app`, while ACL expansion uses `acldefault('T', typowner)` and `acldefault('f', proowner)` for NULL ACLs. Only the built-in non-grantable PUBLIC `USAGE`/`EXECUTE` entries are accepted; app grant-option escalation is rejected.
- Relation/sequence ACL checks at `:2266-2292` use `acldefault()` (`'s'` for sequences, `'r'` for table-like relations), reject any PUBLIC entry, and reject `is_grantable` for app/PUBLIC. `pg_default_acl.defaclacl` retains `COALESCE(..., ARRAY[]::aclitem[])` because it is an explicit `ALTER DEFAULT PRIVILEGES` delta, not an object ACL with hard-wired defaults.
- Preflight H-05 (SQL §1A.1, `:363-465`) checks all existing membership rows touching the three target roles before any mutation, including `inherit_option`, `set_option` and `admin_option`; an absent migrator-to-owner row is allowed because Section 2 adds it.
- Preflight H-06 (SQL §1A.2, `:467-691`) checks direct `datacl`/`nspacl` provenance before grants and schema ownership change, separating ACL-level state from effective privileges and rejecting unexpected grantees, grant options or unsafe effective CREATE.
- Preflight §13 (SQL §1A.3, `:693-1011`) checks the full public relation/sequence inventory and app/PUBLIC allowlist before ownership transfer and grants, with explicit extension-owned-object reporting.
- H-05 (SQL §7A, `:3045-3173`) audits role membership completeness in both directions and rejects unexpected `inherit_option`, `set_option` or `admin_option` values with the exact member, granted role and options after the mutation.
- H-06 (SQL §7B, `:3175-3417`) audits `datacl`/`nspacl` provenance separately from effective privileges and rejects unexpected grantees, privileges, or grant options with exact object/grantee/privilege/grant-option state after the mutation.

### 10.1.0 Fail-closed preflight before the first mutation

SQL §1A (`:350-1411`) is read-only and precedes `CREATE ROLE` at `:1430`. With `\set ON_ERROR_STOP on` at `:49`, any violation aborts before role creation, the membership grant at `:1513`, database/schema grants at `:1523-1524` and `:1528`, the public-schema ownership change at `:1532`, object ownership transfer at `:1536-1638` and all later grants. Exact ranges:

| Preflight | Range | Catalog evidence and abort condition |
|---|---|---|
| H-05 membership/options | `:363-465` | Evidence `:371-392`; assertions `:394-465`; unexpected row or wrong `inherit_option`/`set_option`/`admin_option` at `:418-450`; duplicate migrator-to-owner row at `:452-461`; failure output `:448-450`. |
| H-06 database/schema ACL provenance | `:467-691` | Evidence `:479-533`; assertions `:535-691`; unexpected direct ACL/grant option `:596-616`; missing required PUBLIC default `:617-634`; effective-privilege check `:635-670`; failure output `:685-688`. |
| §13 public object inventory | `:693-1011` | Evidence `:707-755`; expected relation matrix `:763-785`; sequence matrix `:786-806`; expected object OIDs/relkinds `:807-828`; scope and extension detection `:829-850`; missing objects `:851-868`; extension-owned abort `:869-878`; unlisted/relkind `:879-902`; direct ACL/grant option `:903-942`; forbidden effective privileges `:943-985`; failure output `:1005-1008`. |
| §7.10 provenance not normalized by 2-5 | `:1013-1411` | Default ACL evidence `:1030-1049`; custom-type evidence `:1051-1083`; routine evidence `:1085-1112`; assertions `:1114-1411`; global-only `n`/`L` and missing GLOBAL PUBLIC default checks `:1149-1209`; unnormalized default-entry/grant-option checks `:1210-1229`; custom-type effective/PUBLIC/grant-option checks `:1230-1311`; routine effective/PUBLIC/grant-option checks `:1312-1389`; aggregate `:1390-1403`; failure output `:1405-1407`. Per-schema `r`/`S` app defaults and existing relation/sequence app grants remain allowed because Sections 4-5 normalize them. |

The preflight never revokes an unexpected ACL, membership or privilege and never changes ownership. It reports exact member/granted role/options, object/grantee/privilege/ACL source/grant-option/object-ACL-provenance details and then stops for manual investigation. Missing target roles, absent optional target CONNECT/USAGE ACLs, absent expected app object grants, and wrong-or-absent per-schema `r`/`S` app default ACLs are allowed because later sections create or reconcile them; unsafe pre-existing state that Sections 4-5 do not normalize is not silently repaired.

### 10.1.1 Default ACL completeness audit — Findings 1-3

`SOURCE VERIFIED` / PostgreSQL 18 documentation:

- `pg_default_acl.defaclobjtype` uses six codes: `r` (relation/table), `S` (sequence), `f` (function/procedure), `T` (type/domain), `n` (schema), `L` (large object).
- Global entries have `defaclnamespace = 0` and override hard-wired defaults. Per-schema entries are added to global or hard-wired defaults; a per-schema `REVOKE` cannot remove a global grant.
- `IN SCHEMA` is not allowed for `n` or `L` because schemas cannot be nested and large objects do not belong to a schema. Their default privileges are global-only.
- Built-in PUBLIC defaults exist for type/domain `USAGE` and function/procedure `EXECUTE`; PostgreSQL grants no built-in PUBLIC privileges on tables, sequences, schemas or large objects.
- `acldefault()` represents hard-wired defaults when an object ACL is `NULL`. `pg_default_acl` rows are explicit future-object deltas. `aclexplode()` exposes `is_grantable`.

**Finding 1 — MEDIUM: missing object classes `n` and `L`.** The previous inventory and strict assertion covered only `r`, `S`, `T`, `f`, so global defaults for future schemas and large objects were invisible. Corrections: all six codes are inventoried at `:219-225`, `:2093-2099` and `:2917-2923`; `:2407-2416` rejects any per-schema `n`/`L` row globally; `:2447-2475` rejects any app or PUBLIC grant for `n`/`L`. Expected `n`/`L` defaults are global-only with no app/PUBLIC privileges (no `USAGE`/`CREATE` on future schemas and no `SELECT`/`UPDATE` on future large objects). No `ALTER DEFAULT PRIVILEGES ... ON SCHEMAS/LARGE OBJECTS` is issued.

**Finding 2 — MEDIUM: PUBLIC grantee not audited.** The previous strict assertion checked only `a.grantee = v_app`. PUBLIC (`grantee = 0`) applies to every role, including `rupaywala_app`. Corrections: `:2259-2261` declares `v_public = 0`; `:2266-2279` rejects PUBLIC ACLs on existing relations/sequences; `:2294-2367` accepts only the built-in non-grantable PUBLIC `USAGE`/`EXECUTE` for types/routines; `:2418-2443` requires a global `T`/`f` entry, if present, to retain PUBLIC `USAGE`/`EXECUTE`; `:2447-2475` audits both grantees across global and `public` default ACL entries. Explicit built-in-equivalent PUBLIC `USAGE`/`EXECUTE` entries are tolerated only because they add no privilege beyond the hard-wired default; any other PUBLIC default grant is rejected.

**Finding 3 — MEDIUM: grant option not inspected.** The previous assertion only tested privilege presence, so `WITH GRANT OPTION` could pass. Corrections: `:2281-2292` rejects app/PUBLIC grant options on existing relation/sequence ACLs; `:2294-2367` rejects app/PUBLIC grant options on type/routine ACLs; `:2369-2406` requires ordinary, non-grantable app `SELECT` on future public tables and app `USAGE` on future public sequences; `:2447-2475` rejects `a.is_grantable` for app/PUBLIC in every audited default ACL entry.

Global versus per-schema verification matrix in SQL §7.10:

| Code | Scope checked | Allowed app/PUBLIC default entry |
|---|---|---|
| `r` | GLOBAL and `public` | GLOBAL: none for app/PUBLIC. `public`: app `SELECT`, no grant option; PUBLIC rejected. Positive check at `:2369-2378`. |
| `S` | GLOBAL and `public` | GLOBAL: none for app/PUBLIC. `public`: app `USAGE`, no grant option; PUBLIC rejected. Positive check at `:2379-2387`. |
| `T` | GLOBAL and `public` | Only built-in-equivalent PUBLIC `USAGE`, no grant option; app rejected. GLOBAL entry must retain PUBLIC `USAGE` at `:2418-2431`. |
| `f` | GLOBAL and `public` | Only built-in-equivalent PUBLIC `EXECUTE`, no grant option; app rejected. GLOBAL entry must retain PUBLIC `EXECUTE` at `:2432-2443`. |
| `n` | GLOBAL only | No app/PUBLIC entry; any per-schema row rejected at `:2407-2416`. |
| `L` | GLOBAL only | No app/PUBLIC entry; any per-schema row rejected at `:2407-2416`. |

Only `IN SCHEMA public` defaults are changed at `:1772-1779` and `:1791-1798`. No global `ALTER DEFAULT PRIVILEGES` statement is issued; comments at `:1765-1771`, `:1783-1789` and `:2478-2481` document that a global change affects every schema and would require separate approval and justification.

**Preflight counterpart for Findings 1-3.** SQL §1A.4 (`:1013-1411`) applies these same Section 7.10 provenance rules before `CREATE ROLE`. Default-ACL evidence is at `:1030-1049`; custom-type and routine evidence is at `:1051-1083` and `:1085-1112`. The fail-closed DO block at `:1114-1411` rejects per-schema `n`/`L` rows (`:1149-1166`), missing built-in GLOBAL PUBLIC `USAGE`/`EXECUTE` (`:1168-1209`), every unnormalized default entry including GLOBAL app/`r`/`S`, global-only `n`/`L`, and `T`/`f` entries other than non-grantable PUBLIC defaults (`:1210-1229`), and missing effective app or built-in PUBLIC access plus app/PUBLIC grant options on custom types (`:1230-1311`) and routines (`:1312-1389`). It aggregates findings with exact `object=`, `grantee=`, `privilege=`, `acl_source=` and `grant_option=` state at `:1396-1403` and aborts at `:1405-1407` before any mutation. Per-schema `r`/`S` default entries for `rupaywala_app` and existing relation/sequence app grants remain allowed because Sections 4-5 explicitly reconcile them; no finding is revoked or repaired. Post-change §7.10 assertions at `:2245-2476` are unchanged.

`UNVERIFIED`: actual `pg_default_acl` contents, `is_grantable` flags, and post-creation type/routine ACLs must be inspected in the disposable PostgreSQL 18.1 database. Per-schema entries in namespaces other than `public` are outside this artifact's documented scope; only GLOBAL and `public` entries are audited. Any pre-existing GLOBAL grant to app or PUBLIC must be reviewed manually; no blind revocation is performed. If a GLOBAL remediation is required, its every-schema scope must be documented and separately authorized.

### 10.1.2 Exhaustive public relation/sequence privilege audit — HIGH

`Finding`: section 4 reconciled privileges only on the named runtime tables and sequences, and section 7.9 asserted only those named objects. A legacy table, view, materialized view, foreign table or sequence in `public` could retain a direct app grant, a PUBLIC grant, or a grant option without detection. Severity is `HIGH` because this is a least-privilege bypass on existing objects.

Corrections added as SQL §13 (`:3419-3725`), a read-only fail-closed supplement to §7.9/§7.10:

- `:3428-3466` — inventory of every `public` relation/sequence with `relkind`, owner, raw `relacl`, effective app privileges, and expanded app/PUBLIC ACL entries.
- `:3486-3508` — explicit expected table privilege rows, including zero-privilege `family_members` and `alembic_version`.
- `:3509-3529` — explicit expected sequence rows derived from `pg_get_serial_sequence()` for the 18 insert tables; UPDATE is allowed only for `subscription_plans`.
- `:3530-3561` — expected object OIDs, expected `relkind` sets (`r`/`p` for tables, `S` for sequences), and `acldefault()` expansion for NULL object ACLs.
- `:3562-3571` — `UNLISTED_OBJECT` violation for any other `public` relation/sequence (`r`, `p`, `v`, `m`, `f`, `S`).
- `:3572-3582` — `RELKIND_MISMATCH` violation when a listed name is not the expected relation or sequence kind.
- `:3583-3617` — direct ACL comparison using `aclexplode(COALESCE(relacl, acldefault(...)))`; requires exact class-specific app privileges, rejects every PUBLIC (`grantee = 0`) object ACL, rejects `is_grantable`, and reports failures on unlisted objects.
- `:3618-3661` — `MISSING_DIRECT_ACL` violation when an expected app privilege is absent from the direct ACL, preventing inherited or default-derived access from silently replacing the §4 grants.
- `:3662-3700` — effective privilege comparison using `has_table_privilege()` / `has_sequence_privilege()`, so PUBLIC-derived and inherited access is included; `family_members`, `alembic_version` and all unlisted objects require false for every checked privilege.
- `:3701-3722` — aggregated failure with exact `check_type`, `public.<object>`, `privilege`, `grantee` and `detail`; `ON_ERROR_STOP` makes this fail closed.
- No `GRANT`, `REVOKE`, `ALTER` or destructive command is added in §13. Unknown objects are reported, not modified; owner and migrator privileges cannot be weakened by this read-only audit.

`STATICALLY VALIDATED`: the allowlist matches section 8 and the model/migration cross-check in §8.1. `UNVERIFIED`: actual catalog contents must be observed in the disposable PostgreSQL 18.1 database; §13 has not been executed.

**Preflight counterpart.** SQL §1A.3 (`:693-1011`) applies the same allowlist before any ownership transfer or grant. Evidence at `:707-755` classifies every public `r`/`p`/`v`/`m`/`f`/`S` object with `pg_depend` → `pg_extension` provenance. Missing expected relations/sequences (`:851-868`), extension-owned objects (`:869-878`), unlisted objects and relkind mismatches (`:879-902`), unexpected app/PUBLIC direct ACLs and grant options (`:903-942`), and forbidden pre-existing effective app privileges (`:943-985`) abort at `:1005-1008` before `CREATE ROLE`. Expected app grants may be absent because Section 4 adds them; they are not revoked by the preflight.

### 10.1.3 Finding H-05 — role membership completeness

**Original weakness.** Earlier SQL checked a few membership directions and `admin_option` only. It did not inspect all rows touching the three target roles in both directions, did not validate PostgreSQL 18 `inherit_option`/`set_option`, and did not explicitly tie SET capability to the `PGOPTIONS='-c role=rupaywala_owner'` strategy. `INHERIT` alone could be mistaken for proof that startup role switching works.

**Exact remediation.** SQL §7A (`:3045-3173`) adds a both-direction evidence query and a fail-closed DO block. Catalog fields inspected are `pg_auth_members.member`, `.roleid`, `.inherit_option`, `.set_option`, `.admin_option`, resolved with `pg_get_userbyid()`; role attributes are rechecked from `pg_roles`. Expected configuration:

| Member | Granted role (`roleid`) | `inherit_option` | `set_option` | `admin_option` |
|---|---|---:|---:|---:|
| `rupaywala_migrator` | `rupaywala_owner` | true | true | false |

Every other row where either `member` or `roleid` is `rupaywala_owner`, `rupaywala_migrator` or `rupaywala_app` is an `UNEXPECTED_MEMBERSHIP` violation, including any row making `rupaywala_owner` or `rupaywala_app` a member, any extra member of `rupaywala_owner`, and any member of `rupaywala_migrator` or `rupaywala_app`. The sole permitted row with a wrong option triple is an `INVALID_MIGRATOR_MEMBERSHIP_OPTIONS` violation. Messages include exact `member=`, `granted_role=`, `inherit_option=`, `set_option=` and `admin_option=` values, require manual investigation, and perform no membership mutation. The artifact also requires exactly one migrator-to-owner row and rechecks NOLOGIN/LOGIN/NOINHERIT plus forbidden privilege attributes.

**Preflight counterpart.** SQL §1A.1 (`:363-465`) applies the same endpoint and option rules before the membership mutation. Evidence at `:371-392` reports every existing row touching the three target roles. An absent migrator-to-owner row is explicitly allowed; an existing row must be exactly `inherit_option=true`, `set_option=true`, `admin_option=false`. Violations at `:418-450` and duplicate rows at `:452-461` abort before `CREATE ROLE` with exact `member=`, `granted_role=` and option values; no membership is revoked.

**Limitations.** The live `pg_auth_members` contents, actual option values and the `PGOPTIONS` startup-role effect remain `UNVERIFIED`. A catalog row with `set_option=true` proves the catalog permits SET; it does not prove the Alembic process actually sends the startup option. That identity probe remains a separate disposable gate.

### 10.1.4 Finding H-06 — database and schema ACL completeness

**Original weakness.** Prior checks proved effective privileges with `has_database_privilege()`/`has_schema_privilege()` but did not fully inspect direct `pg_database.datacl` and `pg_namespace.nspacl` provenance for all four grantees. Direct grants, PUBLIC defaults, inherited access and ownership could therefore be conflated, and grant options on database/schema ACLs were not exhaustively rejected.

**Exact remediation.** SQL §7B (`:3175-3417`) adds a provenance/effective evidence query and a fail-closed DO block. Functions and fields: `pg_database.datacl`, `pg_namespace.nspacl`, `aclexplode()`, `acldefault('d', datdba)` and `acldefault('n', nspowner)` for NULL ACLs, `pg_get_userbyid()` for grantee names, PUBLIC grantee `0`, `a.privilege_type`, `a.is_grantable`, `has_database_privilege()` and `has_schema_privilege()`. `TEMP`/`TEMPORARY` is normalized to `TEMPORARY`.

**Preflight counterpart.** SQL §1A.2 (`:467-691`) applies a stricter pre-change model before any grant or schema ownership change. Evidence at `:479-533` reads `datacl`/`nspacl` with `acldefault()` expansion and labels provenance as `ACL_DEFAULT` or `DIRECT_ACL`. Required PUBLIC database CONNECT/TEMP and schema USAGE entries must already exist. Optional app/migrator CONNECT and app USAGE entries may be absent but, if present, must be non-grantable. Unexpected owner database entries, migrator schema entries, PUBLIC CREATE, direct app TEMP, any grant option and unsafe effective CREATE abort at `:685-688`; nothing is revoked or broadened.

Direct/ACL-level expectations (`ACL_DEFAULT` from `acldefault()` counts as ACL provenance when the raw ACL is NULL):

| Object | Grantee | Allowed direct privilege | Grant option |
|---|---|---|---|
| `rupaywala_validation` database | PUBLIC | CONNECT, TEMPORARY | false |
| `rupaywala_validation` database | `rupaywala_app` | CONNECT | false |
| `rupaywala_validation` database | `rupaywala_migrator` | CONNECT | false |
| `public` schema | PUBLIC | USAGE | false |
| `public` schema | `rupaywala_app` | USAGE | false |
| `public` schema | `rupaywala_owner` | CREATE, USAGE | ownership grant option tolerated; no other schema privilege |

No direct database entry is allowed for `rupaywala_owner`; no direct schema entry is allowed for `rupaywala_migrator`; PUBLIC schema CREATE and all audited database CREATE entries are rejected. Effective checks remain separate: PUBLIC DB CONNECT/TEMP and schema USAGE true, schema CREATE false; app CONNECT/TEMP/USAGE true and both CREATE values false; owner DB CREATE false and schema USAGE/CREATE true; migrator DB CREATE false, CONNECT/TEMP true, and schema USAGE/CREATE true only through the H-05-audited owner membership. App TEMP is allowed only as an effective PUBLIC-derived privilege, not as a direct app ACL entry. Unexpected direct ACLs, missing expected direct ACLs and effective mismatches are aggregated with exact `object_type`, `object`, `grantee`, `privilege`, `grant_option` and detail. Nothing is revoked.

**Limitations.** Actual `datacl`/`nspacl` arrays, `acldefault()` results, `is_grantable` flags and effective results require live disposable catalog execution. Schemas other than `public`, non-target grantees and privileges outside the database/schema object classes remain outside this audit; their discovery is reported for manual review rather than silently changed.

### 10.2 Negative behavioural checks — `PROPOSED`, SQL §8a line-commented extract

Run only as `rupaywala_app`, each expected to raise `insufficient_privilege`:

- `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`, `TRUNCATE`.
- `CREATE ROLE`; database-creation probe as a separate autocommit psql invocation.
- `SET ROLE rupaywala_owner`; `SET ROLE rupaywala_migrator`.
- SELECT/INSERT/UPDATE/DELETE on `alembic_version`.
- SELECT on `family_members`.
- Unnecessary DELETE on `users`; unnecessary UPDATE on `distance_rate_config` and `visit_ledger`.

### 10.3 Positive behavioural checks — `PROPOSED`, SQL §8b line-commented extract

Run only as `rupaywala_app` inside `BEGIN ... ROLLBACK`. Sequence values may be consumed despite rollback.

Covered operations:

- users: INSERT/UPDATE/SELECT;
- OTP: INSERT/UPDATE/DELETE/SELECT;
- customer profiles: INSERT/UPDATE/SELECT;
- policies: INSERT/DELETE/SELECT;
- policy members: INSERT/DELETE/SELECT;
- service requests: INSERT/UPDATE/SELECT;
- request assignments: INSERT/UPDATE/SELECT;
- service quotes: INSERT/UPDATE/SELECT;
- payments: INSERT/UPDATE/SELECT;
- visit ledger: INSERT/SELECT;
- subscription plans: INSERT/UPDATE/SELECT plus `setval()`;
- subscription family members: INSERT/DELETE/SELECT;
- notifications: INSERT/UPDATE/DELETE/SELECT;
- branches, service types, field members, user subscriptions, distance rate config: INSERT/SELECT as supported by code;
- `nextval()` exercised on every runtime id sequence.

`STATICALLY VALIDATED` smoke-test corrections from the final audit:

- All 18 positive INSERT/UPDATE/DELETE/SELECT groups are schema-consistent with revision `0005_fixed_quotes`; no omitted NOT NULL column was found.
- Fixed `id=900001` is used by 17 INSERTs, not 18. `service_quotes.id` is generated and its INSERT consumes that sequence.
- The 18 `nextval()` probes and `setval(...,900001,true)` are non-transactional and survive `ROLLBACK`; section 8.0 now requires before/after capture and manual restoration if needed.
- `setval(...,900001,true)` makes the next generated plan id `900002`.
- Section 8a is atomic per DO block, not wrapped in `BEGIN/ROLLBACK`; section 8b is transaction-wrapped. The extract must include `\set ON_ERROR_STOP on`.
- Collision-free fixed IDs, unique literals, FK-dependency absence, enum-label state, and a real `rupaywala_app` login are manual prerequisites; they cannot be proven statically.

`NOT EXECUTED`: none of these tests has been run.

---

## 11. Sequence permission exception

`SOURCE VERIFIED`:

- Runtime call exists at `app/services/plan_catalog.py:177`.
- It uses `pg_get_serial_sequence('subscription_plans', 'id')`, so the physical sequence name is derived dynamically.
- The application call is unqualified and therefore search-path dependent; the SQL artifact uses `pg_get_serial_sequence('public.subscription_plans','id')` for its own grants and assertions.
- `setval()` requires UPDATE on the sequence; serial `nextval()` requires USAGE. No runtime code path requires SELECT on the sequence.

| Question | Determination |
|---|---|
| Does runtime seeding call `setval()`? | Yes — `app/main.py:167` → `seed_subscription_plans()` → `app/services/plan_catalog.py:177`. |
| Is the sequence name derived safely? | Dynamically via `pg_get_serial_sequence()`; no hardcoded physical name in application code, though the app call is unqualified. |
| Is UPDATE genuinely necessary? | Yes, while `setval()` remains in runtime code. |
| Can it be removed by a later code change? | Yes — removing the runtime `setval()` call allows the revocation in SQL §9. |
| What permission remains after removal? | USAGE on the sequence for `nextval()` via the serial default; no SELECT and no UPDATE. |

The exception is explicitly temporary and is not used to justify broader table privileges.

---

## 12. Migration 0006 preflight

### 12.1 Exact schema changes — `SOURCE VERIFIED`

`alembic/versions/0006_stage5_security_remediation.py`:

1. Adds `service_quotes.signature_version` integer NOT NULL DEFAULT `'1'` (lines 90–98).
2. Adds `service_requests.quote_ref` varchar(64) NULL (lines 100–103).
3. Adds unique constraint `uq_service_requests_quote_ref` on `service_requests.quote_ref` (lines 104–106).
4. Creates partial unique index `uq_payments_user_type_idem_open` on `(user_id, payment_type, idempotency_key)` where `idempotency_key IS NOT NULL AND status IN ('pending','pending_verification')` (lines 127–136).
5. Creates partial unique index `uq_payments_open_extra_charge_request` on `(related_request_id)` where `payment_type = 'extra_charge' AND related_request_id IS NOT NULL AND status IN ('pending','pending_verification')` (lines 137–147).

No row is updated, deleted, or backfilled by upgrade.

### 12.2 Pre-migration checklist — `PROPOSED`

- Confirm revision exactly `0005_fixed_quotes`.
- Confirm both duplicate checks return zero rows using the same predicates as the migration.
- Confirm PostgreSQL 18.1 via server-side gate.
- Confirm migration role is `rupaywala_migrator` with required membership and CONNECT.
- Use the concrete `PGOPTIONS='-c role=rupaywala_owner'` strategy from SQL §10; validate `current_user=rupaywala_owner` and `session_user=rupaywala_migrator` with the identical environment before migrating.
- Confirm verified backup identifier and successful restore test.
- Confirm approved maintenance window and stopped application/migration sessions.
- Accept possible table-lock impact while creating two partial unique indexes.
- Run SQL §11 as a hard gate; abort on any duplicate or revision mismatch.
- Do not alter historical migration files.
- Do not execute migration 0006 during this preparation task.

### 12.3 Expected post-migration state — `UNVERIFIED`

- Revision `0006_stage5_security_remediation`.
- Five new objects listed above present.
- Existing rows retain legacy semantics; `quote_ref` is NULL for historical requests and `signature_version` defaults to 1.

### 12.4 Downgrade consequences — `SOURCE VERIFIED`

`downgrade()` drops the two partial unique indexes, the quote-ref unique constraint, the `quote_ref` column, and the `signature_version` column. No data is restored or reconstructed; downgrade removes the integrity controls.

---

## 13. Test infrastructure safety findings

`SOURCE VERIFIED` from `tests/conftest.py`:

| Finding | Evidence | Risk |
|---|---|---|
| Configured `DATABASE_URL` credentials are reused for a separate test database | `tests/conftest.py:43-68,87-110` | The test server identity, including any powerful login, is the application-configured one. |
| Hard-coded fallback local credential pair exists | `tests/conftest.py:61` | If `DATABASE_URL` is unset, tests connect to localhost:5432 with a fixed credential pair. Value not reproduced here. |
| Test database creation requires CREATEDB on the server | `tests/conftest.py:71-84` | The configured role must be able to create `rupaywala_test`. |
| `public` schema is dropped and recreated | `tests/conftest.py:139-146` | Destructive to the connected database’s `public` schema. |
| Session teardown drops `public` again | `tests/conftest.py:149-153,184-188` | Leaves the test database without a `public` schema. |
| Every test truncates all mapped tables with `RESTART IDENTITY CASCADE` | `tests/conftest.py:155-167,195-203` | Destructive and sequence-resetting. |
| Guard checks only `engine.url.database == 'rupaywala_test'` | `tests/conftest.py:35,123-136` | Protects the database name, not host, port, or server identity. It does not by itself prove a non-production server. |
| Test process sets its own signing-secret environment values | `tests/conftest.py:113-118` | Values are source-defined and must not be printed, reused, or confused with production secrets. |

`PROPOSED` future remediation, not implemented here:

1. Require an explicit test-only DSN with a dedicated non-production host and role.
2. Require host/port/database identity gates, not just a database-name guard.
3. Remove the hard-coded fallback credential pair.
4. Use a disposable database that may be dropped entirely rather than dropping/recreating `public` in place.
5. Avoid reusing application credentials for destructive test setup.
6. Keep test-only secret values out of source and never reuse production values.

`NOT EXECUTED`: destructive tests must never be run against production or the ordinary application database. They are out of scope for Stage 5.6D.

---

## 14. Remaining blockers

1. Explicit human approval is required for any SQL, Alembic, or container operation.
2. Disposable bootstrap must first succeed and reach `0005_fixed_quotes`; exact PostgreSQL `18.1` must be observed.
3. Interactive TTY password provisioning is required when either login role is newly created or lacks a password.
4. Backup creation and successful restore test are required before 0006.
5. Maintenance window and the `PGOPTIONS` ownership strategy must be approved.
6. Full PostgreSQL execution/parser validation remains `UNVERIFIED`; no parser is installed.
7. Application-role behavioural tests remain `NOT EXECUTED`; collision, FK-dependency and enum-state prerequisites must be checked manually.
8. Six-class (`r`/`S`/`f`/`T`/`n`/`L`), app/PUBLIC, GLOBAL-versus-per-schema and `is_grantable` ACL assertions are embedded in SQL §7.10, but actual `pg_default_acl` contents and the strict grant/grant-option assertions still require live catalog execution.
9. The `PGOPTIONS` identity probe and post-0006 object ownership must be observed; a psql-only `SET ROLE` is insufficient.
10. Sequence values consumed by smoke tests must be captured and restored manually; `ROLLBACK` does not reverse them.
11. Test infrastructure hardenings are recommended but not implemented.
12. SQL §13 exhaustive public relation/sequence allowlist must be executed live; any `UNLISTED_OBJECT`, `RELKIND_MISMATCH`, unexpected app/PUBLIC `DIRECT_ACL`, `MISSING_DIRECT_ACL`, `WITH GRANT OPTION`, or effective-privilege mismatch must be resolved by an explicitly approved, non-blind remediation before 0006.
13. SQL §7A H-05 membership rows/options must be observed live; any unexpected member, granted role, or `inherit_option`/`set_option`/`admin_option` state requires manual investigation before 0006.
14. SQL §7B H-06 direct `datacl`/`nspacl` provenance and grant options must be observed live; any unexpected direct ACL, missing expected ACL, or effective-privilege mismatch requires manual investigation before 0006.
15. SQL §1A preflight must be executed live before any mutation. Its H-05, H-06, §13 and §7.10-provenance catalog results are `UNVERIFIED`; any finding stops the file and requires manual investigation rather than automatic revocation.
16. Any extension-owned public relation or sequence reported by preflight §1A.3 must be reviewed manually before the script is allowed to continue; the preflight deliberately aborts rather than treating it as an ordinary application object.
17. The fail-closed ordering itself has not been parser- or execution-validated. Static inspection only establishes that all four §1A subsections, including §1A.4, precede `CREATE ROLE` at `:1430`, grants and ownership transfer.
18. Live SQL §1A.4 results for `pg_default_acl`, custom-type ACLs, routine ACLs, effective app access and grant options are `UNVERIFIED`. Any finding must be reviewed manually before mutation; the preflight never revokes or repairs it automatically.

---

## 15. Explicit approval requirements

Before any future execution stage, approval must explicitly cover:

- the exact disposable container, database, user, and client mapping;
- running the bootstrap plan through `0005_fixed_quotes`;
- running the corrected SQL as `validation_admin`;
- interactive setting of test-only role passwords;
- opening a separate `rupaywala_app` connection for the commented extract;
- setting test-only environment values without printing or committing secrets;
- backup creation plus verified restore test;
- a separately approved `0006` migration window and ownership strategy;
- no production access and no Stage 6 work.

---

## 16. Static validation results and final static-review verdict

### 16.1 Static validation — `STATICALLY VALIDATED`

- All three final artifacts were re-read after editing.
- Files inspected for this final pass: `database/security/stage_5_6d_postgresql_roles_corrected.sql`, `RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md`, `RUPAYWALA_STAGE_5_6D_FINAL_PRE_EXECUTION_AUDIT.md`, plus source/runbook context already recorded in §2. Files modified: only those three permitted artifacts.
- SQL line count: **3,725**; file size: **169,201 bytes**. Active `DO $$`/`END $$` pairs: **22/22** (one new §1A.4 assertion block); line-commented example pairs in §8: **9/9**. Total `$$` tokens: **62** (31 balanced pairs).
- Block-comment delimiters: **5 `/*` / 5 `*/`**. Non-ASCII lines: **0**. psql variable references occur only in ordinary SQL/psql meta-commands and **0** appear inside dollar-quoted bodies, including all new preflight blocks.
- No `GRANT`, `REVOKE`, `ALTER`, `CREATE`, `DROP`, `TRUNCATE`, `INSERT`, `UPDATE` or `DELETE` statement appears in read-only SQL §1A (`:350-1411`), §7A (`:3045-3173`), §7B (`:3175-3417`) or §13 (`:3419-3725`); static scans found **0** such statements in those ranges. Section 13 post-change audit logic and allowlist content are unchanged; only its line numbers shifted by +416 with the new §1A.4 insertion.
- No application table or sequence permission matrix changed: §4, §7.9 and the §13 allowlist still contain 18 runtime tables, 18 id sequences, zero privileges for `family_members`/`alembic_version`, and UPDATE only for the `subscription_plans` id sequence. Preflight §1A.3 uses the same matrix and allows expected grants to be absent before Section 4 adds them.
- No unexpected membership, ACL, privilege or object is silently revoked or repaired. Preflight §1A and post-change §7A/§7B/§13 report exact catalog state and fail closed before or after mutation as applicable.
- All three permitted artifacts agree on the final status: static review complete — ready for disposable validation review, with all runtime gates still outstanding.
- Internal port gate is `5432` in SQL and plan; client mapping `55432` is documented separately.
- Owner capture uses no psql variable inside `DO $$`; the only `:'...'` substitution is in an ordinary SQL `set_config()` statement.
- No psql variable reference remains inside a dollar-quoted body.
- Bootstrap object count and names match `b96aae0ed4c8` exactly.
- Permission matrix in SQL §4/§7 matches the source-derived matrix in section 8 and the exhaustive §13 allowlist in §8.1 (`:3419-3725`).
- SQL §13 adds a read-only fail-closed public-object audit covering all `r`/`p`/`v`/`m`/`f`/`S` relations, exact direct app ACL presence, rejection of every PUBLIC object ACL and grant option, relkind mismatches, unlisted objects, and effective PG18 table/sequence privileges with `acldefault()` handling of NULL ACLs.
- SQL §1A repeats the critical pre-change checks before `CREATE ROLE`: membership options, direct database/schema ACL provenance, the complete relation/sequence allowlist, and the unnormalized Section 7.10 provenance layer; extension-owned objects and every §1A.4 finding are reported explicitly and abort before mutation.
- SQL §1A.4 (`:1013-1411`) is read-only and fail-closed. It inspects `pg_default_acl` for `rupaywala_owner`/`rupaywala_migrator` across all six PG18 classes, GLOBAL public defaults, existing custom type/routine ACLs, effective app access and app/PUBLIC grant options. It allows only the per-schema `r`/`S` app deltas and existing relation/sequence app grants that Sections 4-5 reconcile, reports exact object/grantee/privilege/ACL source/grant-option state, and issues no revoke or repair.
- Final-audit corrections now include exact PostgreSQL `18.1` gating, PG18 `REFERENCES`/`MAINTAIN` assertions, PUBLIC `TEMP`/default-ACL/type/routine provenance checks with `acldefault()` handling of NULL object ACLs, all six default-ACL object classes (`r`/`S`/`f`/`T`/`n`/`L`), GLOBAL-versus-per-schema scope, app/PUBLIC and `is_grantable` assertions, and a concrete `PGOPTIONS` Alembic ownership runbook.
- `family_members` and `alembic_version` have zero privileges across all eight PG18 table privilege types.
- `distance_rate_config` has no UPDATE.
- Application-role tests are line-commented and cannot run when the DBA executes the file.
- Smoke-test extract now states that section 8a is DO-atomic, section 8b uses `BEGIN/ROLLBACK`, and `nextval()`/`setval()` survive rollback.
- Revision identifiers `0003_visit_credits_lifecycle`, `0005_fixed_quotes`, and `0006_stage5_security_remediation` are consistent.
- Search results: no production database identifier, password literal, API key, or secret value in the three final artifacts. No executable database-owner transfer or ownership-bulk-removal command is present. The SQL keyword patterns that do appear are limited to: disposable bootstrap DDL, a line-commented negative behavioural test for database creation, and explanatory documentation. These are not prohibited execution commands in this preparation stage.

### 16.2 Execution validation — `UNVERIFIED` / `NOT EXECUTED`

- No PostgreSQL connection was made.
- No SQL statement was executed.
- No Alembic command was run.
- No Docker container was changed.
- No role, permission, schema, or data was modified.
- No backup or restore test was performed.
- `pglast` and `sqlparse` are absent; no parser was installed. Full PostgreSQL syntax validation and behavioural validation remain pending.

### 16.3 Final verdict

**STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW** — preflight §1A (including the new §1A.4 Section 7.10 preflight), post-change §7A/§7B and the intact §13 audit are statically complete, the role/privilege matrices are unchanged, and all three permitted artifacts agree. This is not execution readiness and not production readiness. Execution authorization and the runtime prerequisites listed in sections 14-15 remain outstanding; the `PGOPTIONS` identity effect, interactive password provisioning, backup restoration, application-role behaviour, post-0006 ownership, and live preflight/post-change catalog results are still `UNVERIFIED`/`NOT EXECUTED`. No database, container, SQL, Alembic or runtime operation may begin without explicit approval; any approved next stage must target only the disposable PostgreSQL 18.1 environment. See `RUPAYWALA_STAGE_5_6D_FINAL_PRE_EXECUTION_AUDIT.md` for the complete verdict.

### 16.4 Complete list of changed files

Only these three files were changed during this remediation:

1. `database/security/stage_5_6d_postgresql_roles_corrected.sql` — added read-only, fail-closed §1A.4 Section 7.10 preflight at `:1013-1411` before the first `CREATE ROLE` at `:1430`; no post-change assertion was weakened or removed.
2. `RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md` — updated every SQL line reference to the final 3,725-line artifact, added §1A.4 coverage, updated static metrics and blockers, and added this complete changed-files list.
3. `RUPAYWALA_STAGE_5_6D_FINAL_PRE_EXECUTION_AUDIT.md` — updated shifted SQL anchors and metrics, added §1A.4 coverage and the corresponding live-validation blocker, and preserved the exact final verdict.

No other file was modified by this task. Pre-existing modified and untracked application, Alembic, test, Flutter and Stage 5.6D files were left untouched. Static backups were written only under `%TEMP%` and are not repository changes.

---

## 17. Consolidated PUBLIC pseudo-role remediation and final saved-file verification

### 17.1 Original defect

The final SQL had twelve privilege-inquiry call sites that could receive the uppercase human-readable label `PUBLIC` as the role argument:

- eight direct calls in §7.2: four in the evidence query and four in its strict assertion;
- four dynamic calls where an ACL-derived display label (`e.grantee = 'PUBLIC'`) was passed directly to `has_database_privilege()` or `has_schema_privilege()` in §1A.2 and §7B.

PostgreSQL 18 treats the PUBLIC pseudo-role argument as lowercase `'public'`. Uppercase `PUBLIC` is correct only as a report/ACL label, not as a role argument.

### 17.2 Exact correction

All twelve call sites were corrected in `database/security/stage_5_6d_postgresql_roles_corrected.sql`:

- §7.2 evidence (`:1855-1862`) and assertion (`:1906-1915`): `has_database_privilege('PUBLIC', ...)` and `has_schema_privilege('PUBLIC', ...)` became `has_database_privilege('public', ...)` / `has_schema_privilege('public', ...)`.
- §1A.2 evidence (`:519-524`) and effective assertion (`:660-665`), plus §7B evidence (`:3230-3235`) and effective assertion (`:3389-3394`): the first argument is now `CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END`.

The displayed `grantee` column, CTE labels, ACL provenance strings, `RAISE EXCEPTION` text, comments, real role names, `a.grantee = 0` OID checks and `v_public oid := 0` patterns were intentionally left unchanged. No ACL catalog semantics were altered.

### 17.3 Search coverage and other defects

Static search covered every occurrence of `PUBLIC`, `has_database_privilege`, `has_schema_privilege`, `has_table_privilege`, `has_sequence_privilege`, `has_function_privilege`, `has_type_privilege`, `aclexplode`, `pg_default_acl`, `acldefault`, `pg_roles`, `pg_auth_members`, `pg_database`, `pg_namespace`, `pg_class`, `pg_type`, `pg_proc` and `pg_depend`, including dynamic grantee expressions. A post-edit regex scan found **0** uppercase `PUBLIC` pseudo-role arguments in privilege-inquiry functions. No other new blocking defect was found in this pass; the previously recorded role-model, preflight, catalog-provenance and PG18 privilege findings remain remediated as documented above.

### 17.4 Final static metrics and boundaries

- Final saved SQL: **3,725 lines**, **169,201 bytes**.
- Active `DO $$` blocks: **22**; matching `END $$;`: **22**; line-commented example pairs in §8: **9/9**; `$$` tokens: **62** (31 balanced pairs).
- Block comments: **5 `/*` / 5 `*/`**; non-ASCII lines: **0**; psql variables inside dollar-quoted bodies: **0**.
- Read-only preflight §1A: `:350-1411`. First mutation: `CREATE ROLE rupaywala_owner` at `:1430`; all preflight assertions finish at `:1411`, before that mutation.
- Read-only post-change sections present: §7A `:3045-3173`, §7B `:3175-3417`, §7.10 `:2245-2476`, §13 `:3419-3725`.
- Mutation-statement scan across §1A, §7A, §7B and §13: **0** `CREATE`, `ALTER`, `DROP`, `GRANT`, `REVOKE`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `MERGE`, `COPY`, `SET`, `RESET`, `COMMENT` or `SECURITY LABEL` statement starts.

### 17.5 Limitations and no-operation statement

This was static text inspection and scoped PowerShell counting only. No PostgreSQL parser, catalog, disposable execution, application runtime, PGOPTIONS identity effect, backup/restore, Alembic command, Docker operation or migration 0006 execution was performed. No database was modified; production was untouched; no credentials were changed. Live PostgreSQL 18.1 validation and human approval remain mandatory. `database/security/stage_5_6d_disposable_bootstrap_plan.md` was not modified in this pass.

**Final verdict: STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW**
