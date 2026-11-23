# RUPAYWALA — Stage 5.6D Final Pre-Execution Technical Audit

**Date:** 2026-11-21  
**Mode:** READ-ONLY STATIC AUDIT AND ARTIFACT CORRECTION  
**Target:** Disposable container `rupaywala-pg18-validation`, database `rupaywala_validation`, PostgreSQL `18.1`, client mapping `127.0.0.1:55432 -> 5432`  
**Production:** Strictly out of scope

## Executive verdict

**STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW**

Preparation artifacts are source-verified and internally consistent. The original fail-closed gap is remediated statically: read-only SQL §1A (`:350-1411`) now runs before the first mutation at `:1430`, checking H-05 membership options, H-06 database/schema ACL provenance, the full §13 public relation/sequence allowlist, and the unnormalized Section 7.10 provenance layer (GLOBAL/per-schema `pg_default_acl`, custom type/routine ACLs, effective app access and grant options), with explicit extension-owned-object handling. Post-change SQL §7A (`:3045-3173`), §7B (`:3175-3417`), §7.10 (`:2245-2476`) and §13 (`:3419-3725`) remain intact and read-only. This verdict is not execution readiness and not production readiness. Live identity, parser/catalog, §1A/§7A/§7B/§7.10/§13 catalog, interactive password, collision, enum-state, sequence-state, backup/restore, application-role behavioural, and post-0006 ownership checks remain `UNVERIFIED` or `NOT EXECUTED`. No runtime result may be inferred from static consistency alone. The next stage requires explicit approval and must be performed only against the disposable PostgreSQL 18.1 environment.

Labels used: `SOURCE VERIFIED` = read directly from repository source; `STATICALLY VALIDATED` = internally consistent across artifacts; `UNVERIFIED` = requires live execution evidence; `NOT EXECUTED` = no runtime proof exists.

---

## 1. Scope and method

### 1.1 Artifacts reviewed and corrected

- `database/security/stage_5_6d_disposable_bootstrap_plan.md` (context only; not modified in this remediation pass)
- `database/security/stage_5_6d_postgresql_roles_corrected.sql` (modified)
- `RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md` (modified)

### 1.2 New report

- `RUPAYWALA_STAGE_5_6D_FINAL_PRE_EXECUTION_AUDIT.md` (this file)

### 1.3 Source inspected

- `alembic/env.py`
- `alembic.ini`
- `app/config.py`
- `app/database.py`
- `alembic/versions/0005_fixed_quotes.py`
- `alembic/versions/0006_stage5_security_remediation.py`
- `alembic/versions/b96aae0ed4c8_add_email_otp_support.py`
- `app/models/*.py`
- `app/services/plan_catalog.py`
- `tests/conftest.py`
- The three Stage 5.6D preparation artifacts

### 1.4 No-operation confirmation

`NOT EXECUTED`: during this audit no PostgreSQL connection was opened, no SQL statement was run, no Alembic command was run, no test was run, no Docker container was started/stopped/restarted/removed/modified, no database role or permission was changed, no production resource was accessed, no application runtime code or historical migration was edited, and no password/API key/JWT secret/quote-signing secret was displayed, requested, copied, or modified. SQLite inspection or runtime startup was not performed either. This remains true after adding all four read-only SQL §1A subsections, preserving SQL §7A/§7B/§7.10/§13, and updating all three permitted artifacts: every operation was static file inspection or file editing only.

### 1.5 Final static validation summary

- Files inspected in this final pass: the SQL artifact and the two reports; source/runbook context already listed in §1.3 was not re-opened for live behaviour. Files modified: only the three permitted artifacts.
- SQL line count: **3,725**; file size: **169,201 bytes**; active `DO $$`/`END $$`: **22/22** (one new §1A.4 assertion block); line-commented example pairs: **9/9**; total `$$` tokens: **62** (31 balanced pairs).
- Block-comment delimiters: **5 `/*` / 5 `*/`**; non-ASCII lines: **0**; psql variable references inside dollar-quoted bodies: **0**.
- Static scan of read-only SQL §1A (`:350-1411`), §7A (`:3045-3173`), §7B (`:3175-3417`) and §13 (`:3419-3725`) found **0** `GRANT`, `REVOKE`, `ALTER`, `CREATE`, `DROP`, `TRUNCATE`, `INSERT`, `UPDATE` or `DELETE` statements.
- No permission matrix changed. Post-change §7A/§7B/§7.10/§13 content is unchanged apart from the +416 line-number shift caused by the new §1A.4 block; §1A preflight applies the same allowlists before mutation and allows expected grants and Sections 4-5-normalized per-schema `r`/`S` deltas to be absent or wrong because later sections reconcile them. No unexpected membership, ACL, privilege or object is silently revoked or repaired.
- All three permitted artifacts agree: static review complete — ready for disposable validation review, with all runtime gates still outstanding.

---

## 2. Findings by severity

### 2.1 CRITICAL

| ID | Finding | Evidence | Status |
|---|---|---|---|
| C-01 | Alembic does not explicitly change role. With `rupaywala_migrator` login, `session_user` and `current_user` both start as `rupaywala_migrator`. | `alembic/env.py:13,77` passes `DATABASE_URL` directly to `create_engine(..., NullPool)`; `alembic/env.py:73-82` has no `SET ROLE`; `alembic.ini:5-7` has an empty URL and no role option; `app/config.py:56` reads `DATABASE_URL`. | Artifact strategy corrected; live effect `UNVERIFIED`. |
| C-02 | Earlier exact-version gate `left(server_version,4)='18.1'` could accept `18.10+`. | Original SQL artifact gate; corrected at `stage_5_6d_postgresql_roles_corrected.sql:80` and plan gate at `stage_5_6d_disposable_bootstrap_plan.md:129`. | Corrected; live gate `UNVERIFIED`. |
| C-03 | Interactive `\password` cannot be provisioned non-interactively when a new login role is needed. | SQL artifact uses `\password` at `:1439` and `:1449`; `ON_ERROR_STOP` is set at `stage_5_6d_postgresql_roles_corrected.sql:49`. | Documented workflow; execution prerequisite. |

### 2.2 HIGH

| ID | Finding | Evidence | Status |
|---|---|---|---|
| H-01 | PG18 privilege assertions omitted `REFERENCES`, `MAINTAIN`, DB `TEMP`, strict `CONNECT`/`USAGE`, PUBLIC object ACLs, default-ACL details, type `USAGE`, routine `EXECUTE`, schema owner, and routine owner. | Corrected in SQL §7.5/§7.6 (`:2029-2063`), §7.9 (`:2101-2243`), §7.10 (`:2245-2476`). | Artifacts corrected; live catalog validation `UNVERIFIED`. |
| H-02 | Smoke-test sequence effects are persistent. 18 `nextval()` calls plus `setval(...,900001,true)` are not reversed by `ROLLBACK`. | SQL §8.0 (`:2492-2508`); §8b `nextval()` `:2744-2763` and `setval()` `:2777-2782`; runtime `setval()` at `app/services/plan_catalog.py:171-185`, specifically `:177`. | Documented at SQL §8.0 and §8b; manual prerequisite. |
| H-03 | Fixed IDs and unique literals cannot be proven collision-free statically; dependent rows and enum state are runtime data. | Smoke-test INSERTs at SQL `:2645-2722`; §8.0 prerequisites at `:2492-2508`; enum definitions in `app/models/user.py:18-43`, `app/models/otp_verification.py:18-27`, `app/models/field_member.py:9-20`, `app/models/payment.py:22-38`. | Manual prerequisites added. |
| H-04 | Test infrastructure remains destructive and not hard-gated by host/port. | `tests/conftest.py:35,43-110,123-203`; `DROP SCHEMA` at `:144-152`, `create_all()` at `:146`, `TRUNCATE ... RESTART IDENTITY CASCADE` at `:167`, `DATABASE_URL` override at `:110`. | Documented; no test executed. |
| H-05 | Earlier membership checks covered only selected directions and `admin_option`; `inherit_option`/`set_option` were not audited and INHERIT could be mistaken for proof of startup-role capability. | Preflight SQL §1A.1 (`:363-465`) applies the same option rules before `CREATE ROLE`; post-change SQL §7A (`:3045-3173`) provides both-direction `pg_auth_members` inventory `:3061-3082` and exact role/option assertions `:3084-3173`; report §10.1.3. | Artifact corrected; live preflight/catalog and PGOPTIONS verification `UNVERIFIED`. |
| H-06 | Effective database/schema privileges were checked, but direct `datacl`/`nspacl` provenance, all four grantees and grant options were not exhaustively audited. | Preflight SQL §1A.2 (`:467-691`) checks `datacl`/`nspacl` provenance before grants/schema ownership change; post-change SQL §7B (`:3175-3417`) provides provenance/effective query `:3190-3239` and direct ACL/effective/grant-option assertions `:3241-3417`; report §10.1.4. | Artifact corrected; live preflight/catalog validation `UNVERIFIED`. |
| H-07 | Sections 4/7.9 audited only named public objects; an unexpected legacy table, view, materialized view, foreign table or sequence could retain a direct app grant, a PUBLIC grant or a grant option undetected. | Preflight SQL §1A.3 (`:693-1011`) inventories all public `r`/`p`/`v`/`m`/`f`/`S` objects before mutation and explicitly aborts on extension-owned objects; post-change SQL §13 (`:3419-3725`) provides inventory `:3428-3466`, allowlist `:3486-3529`, `UNLISTED_OBJECT` `:3562-3571`, `RELKIND_MISMATCH` `:3572-3582`, direct ACL/PUBLIC/grant-option rejection `:3583-3617`, missing direct grant detection `:3618-3661`, effective checks `:3662-3700`, exact failure output `:3701-3722`; report §8.1/§10.1.2. | Artifact corrected; live preflight/catalog validation `UNVERIFIED`. |
| H-08 | The artifact previously mutated roles, ACLs and ownership before validating unsafe pre-existing state; H-05/H-06/§13 were only post-change assertions, so an unexpected membership, grant option, ACL or legacy object could be changed or masked before detection. | Read-only fail-closed SQL §1A (`:350-1411`) precedes `CREATE ROLE` at `:1430`: H-05 preflight `:363-465`, H-06 preflight `:467-691`, §13 preflight `:693-1011`, §7.10-provenance preflight `:1013-1411`; every finding raises an exception with exact catalog details before any mutation, with `ON_ERROR_STOP` at `:49`. | Statically remediated; live preflight execution/ordering and catalog results `UNVERIFIED`. |
| H-09 | Section 7.10 provenance conditions not normalized by Sections 2-5 were checked only after mutation; GLOBAL/default ACLs, custom type/routine ACLs and grant options could be detected too late. | New read-only SQL §1A.4 (`:1013-1411`) checks `pg_default_acl` for owner/migrator across all six PG18 classes, GLOBAL PUBLIC `USAGE`/`EXECUTE` preservation, existing custom type/routine ACLs, effective app `USAGE`/`EXECUTE`, app/PUBLIC grant options and unmodified object-level ACLs before `CREATE ROLE`; per-schema `r`/`S` app deltas are allowed because Sections 4-5 normalize them. Findings report exact object/grantee/privilege/ACL source/grant-option state and abort at `:1405-1407`; no ACL is revoked or repaired. | Statically remediated; live catalog validation `UNVERIFIED`. |

### 2.3 MEDIUM

| ID | Finding | Evidence | Status |
|---|---|---|---|
| M-01 | Documentation previously implied existing roles were completely untouched although `GRANT rupaywala_owner TO rupaywala_migrator` mutates membership if absent. | SQL membership grant at `stage_5_6d_postgresql_roles_corrected.sql:1501-1505`; corrected role text at `:1413-1417`; preflight allowance for an absent membership at `:363-465`; report §9 at `RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md:254+`. | Corrected. |
| M-02 | `migrator_schema_create` was called informational although it is expected true through INHERIT from schema ownership. | SQL assertion now in §7.2 (`:1864-1942`); plan §7/§10. | Corrected; live observation `UNVERIFIED`. |
| M-03 | Routine ownership was not previously distinguished from relation/type ownership. | SQL baseline inventory `:198-217`; §7.4 app-owned object check; section 3 transfers no routines. | Documented; no routine ownership transfer performed. |
| M-04 | Default PUBLIC privileges and direct/inherited/effective privileges were conflated. | New provenance query/assertions in SQL §7.10 (`:2245-2476`); report §8 updates. | Corrected. |

### 2.4 LOW

| ID | Finding | Evidence | Status |
|---|---|---|---|
| L-01 | Client port `55432` must not be claimed from `inet_server_port()`. | Plan §3.1 (`68-81`); SQL header `24-27`; SQL gate expects internal `5432` at `:87-92`. | `STATICALLY VALIDATED`. |
| L-02 | Bootstrap inventory is 1 table + 7 indexes + 3 constraints = 11 objects. | `b96aae0ed4c8_add_email_otp_support.py:21,76-79,88,101-102,131,154-155`; plan §5 table and totals at `database/security/stage_5_6d_disposable_bootstrap_plan.md:239-270`. | `SOURCE VERIFIED`. |
| L-03 | Historical migrations must not be edited or stamped over. | Plan §2 (`42-49`) and §6 (`276-281`). | `STATICALLY VALIDATED`. |

---

## 3. Exact source evidence

| Area | Source/line | Finding |
|---|---|---|
| Alembic URL | `alembic/env.py:13`, `alembic/env.py:77` | `DATABASE_URL` imported from `app.config` and passed directly to `create_engine(..., poolclass=pool.NullPool)`. |
| Alembic online path | `alembic/env.py:73-82` | Opens connection, configures context, runs migrations; no `SET ROLE`. |
| Alembic offline path | `alembic/env.py:60-70` | Uses `url=DATABASE_URL`; no connection, so `--sql` cannot validate identity. |
| Alembic config | `alembic.ini:5-7` | `sqlalchemy.url` intentionally empty; no role/options setting. |
| Config loading | `app/config.py:11,13,56` | `load_dotenv()` then required `DATABASE_URL`; process override wins over `.env`. |
| App engine | `app/database.py:6,10-16` | Separate application engine; `connect_args` at `:15` is SQLite-only and is not Alembic's engine. |
| Legacy inventory | `b96aae0ed4c8...py:21,76-79,88,101-102,131,154-155` | One table, seven indexes, three unique constraints dropped by real migration. |
| Revision 0005 quote schema | `0005_fixed_quotes.py:20-80` | Creates `service_quotes` with generated `id`, `quote_ref NOT NULL`, `signature NOT NULL`, `user_id NOT NULL`, `request_type NOT NULL`, and defaults for boolean/amount columns. |
| Revision 0006 schema | `0006_stage5_security_remediation.py:90-147` | Adds two columns, one unique constraint, two partial unique indexes. Duplicate checks at `:108-125`. |
| 0006 downgrade | `0006_stage5_security_remediation.py:150-161` | Drops the five added integrity objects; no data reconstructed. |
| `setval()` runtime | `app/services/plan_catalog.py:171-185`, especially `:177-178` | Runtime seeding calls `setval(pg_get_serial_sequence('subscription_plans','id'), ...)`. |
| `family_members` | `app/models/family_member.py:6-7`; `app/main.py:39`; route grep only finds `max_family_members`/`list_family_members` names | Model/import registration only; no runtime table DML found. |
| Destructive tests | `tests/conftest.py:35,43-110,123-203` | Database-name-only guard, `DROP SCHEMA`, `create_all()`, truncations. |

---

## 4. Corrections made to preparation artifacts

### 4.1 `database/security/stage_5_6d_postgresql_roles_corrected.sql`

- `:32-36` — Section 10 is now the required Alembic ownership runbook, not merely a note.
- `:49` — `ON_ERROR_STOP` remains active; §8.0 now instructs operators to include it in the copied extract.
- `:80-81` — exact PostgreSQL `18.1` gate using `split_part(current_setting('server_version'),' ',1)` and `server_version_num='180001'`.
- `:350-1411` — new read-only fail-closed SQL §1A before the first mutation: H-05 membership/options `:363-465`, H-06 `datacl`/`nspacl` provenance `:467-691`, §13 public relation/sequence allowlist `:693-1011`, and §7.10 provenance not normalized by Sections 4-5 `:1013-1411` (evidence `:1030-1112`, assertions `:1114-1411`), including explicit extension-owned-object handling. Every finding raises an exception before `CREATE ROLE` at `:1430`; no ACL, membership, privilege or object is auto-revoked or repaired.
- `:1413-1417` — role creation comment states attributes/passwords are unchanged but membership is reconciled.
- `:1509-1513` — membership grant explicitly identified as the one configuration mutation; preflight `:363-465` permits an absent membership but validates any existing row.
- `:1516-1521` — PUBLIC defaults documented as asserted, not broadened or revoked.
- `:1784-1788` — migrator default privileges marked defensive; `PGOPTIONS` is the required strategy.
- `:1864-1942` — §7.2 asserts DB `CONNECT`/`TEMP`, schema `USAGE`/`CREATE`, and migrator inherited schema `CREATE`.
- §7.3 — schema owner assertion added.
- `:2029-2063` — `REFERENCES` and `MAINTAIN` added to history and table evidence.
- `:2101-2197` — `REFERENCES`/`MAINTAIN` added to strict positive/negative table assertions and zero-privilege check.
- `:2245-2476` — §7.10 adds PUBLIC ACL, custom-type `USAGE`, routine `EXECUTE`, default-ACL, and provenance assertions.
- `:2492-2508` — §8.0 manual prerequisites: `ON_ERROR_STOP`, revision, collisions, unique literals, FK dependencies, enum labels, sequence capture.
- `:2496` — `service_quotes.id` documented as generated, not fixed `900001`.
- `:2506-2507` — `setval(...,true)` next-id and non-transactional effects documented.
- `:2813-2925` — Section 10 rewritten with concrete `PGOPTIONS='-c role=rupaywala_owner'` runbook and post-0006 catalog checks.
- `:2927-2936` — §11 human attestation now requires the `PGOPTIONS` identity probe.
- `:3045-3173` — post-change SQL §7A (H-05): both-direction `pg_auth_members` audit with `member`, `roleid`, `inherit_option`, `set_option` and `admin_option`; exact migrator-to-owner option triple; exact fail-closed state output; no membership mutation.
- `:3175-3417` — post-change SQL §7B (H-06): direct `datacl`/`nspacl` provenance with `aclexplode()`, `acldefault('d', ...)`/`acldefault('n', ...)`, `pg_get_userbyid()`, PUBLIC OID `0`, separate effective `has_database_privilege()`/`has_schema_privilege()` checks and grant-option rejection; no ACL mutation.
- `:3419-3725` — post-change §13 exhaustive public relation/sequence allowlist audit: full catalog inventory, source-derived table/sequence allowlist, relkind and unlisted-object rejection, direct ACL presence and PUBLIC/grant-option rejection, effective PG18 privilege assertions, and exact failing object/privilege/grantee output. §13 is read-only and issues no `GRANT`, `REVOKE`, `ALTER` or destructive command. Its audit content is unchanged; only line numbers shifted by +416 with the new §1A.4 insertion.

### 4.2 `database/security/stage_5_6d_disposable_bootstrap_plan.md` (context only — not modified in this pass)

The bootstrap plan was reviewed as context only. No concrete inconsistency required a change in this remediation pass, and no report claim should be read as saying this file was modified now. The entries below describe its pre-existing content from the earlier preparation stage.

- `:95-103` — role-specific DSN table: `validation_admin` bootstrap only, `rupaywala_migrator` Alembic only, `rupaywala_app` runtime only.
- `:129` — exact PostgreSQL `18.1` gate.
- `:294-297` — PG18 privilege notes updated for `REFERENCES`, `MAINTAIN`, PUBLIC `TEMP`, custom types, routines, default ACLs.
- `:312-315` — consistency table updated for exact version, DSNs, PUBLIC defaults, PG18 privileges, Alembic owner startup.
- `:320-338` — interactive password workflow added.
- `:340-360` — required Alembic ownership runbook added.
- `:366-368` — final status records the runtime validation prerequisites that remain before any live execution.

### 4.3 `RUPAYWALA_STAGE_5_6D_SQL_REMEDIATION_REPORT.md`

- `:163,165` — exact version gate and interactive `\password` caveat corrected.
- `:254+` — role design corrected for membership mutation and INHERIT consequence; Alembic source-verified vs execution-unverified distinction added.
- `:286+` — catalog checks expanded to eight table privileges, PUBLIC `TEMP`, schema owner, inherited migrator CREATE, type/routine/default-ACL assertions.
- `:447+` — smoke-test corrections and manual prerequisites added.
- `:481+` — 0006 checklist now requires the concrete `PGOPTIONS` strategy.
- `:549+` — blockers updated.
- `:588+` — static validation and final verdict updated to reference this final audit.
- `:236+` and `:353+` — complete exhaustive public-object allowlist and `HIGH` finding for SQL §13 added; blocker 12 at `:562+` and static validation at `:590+` now cover §13 and its live-execution limitation.
- `§10.1.3`/`§10.1.4` — H-05 role-membership and H-06 database/schema ACL findings, exact SQL line ranges, catalog fields, expected configurations, direct-versus-effective explanation, grant-option checks and limitations.
- `§10.1.0` (`:307-318`) — new fail-closed preflight subsection: exact §1A ranges, including §1A.4, abort semantics, allowed absent/normalized states and manual-investigation requirement.
- `:565-568` — blockers 15-18 added for live §1A preflight results, extension-owned public objects, unverified fail-closed ordering and §1A.4 catalog validation.
- `§16.1`/`§16.3`/`§16.4` — static metrics updated to 3,725 SQL lines / 22 active `DO` pairs, the §1A.4 coverage and changed-files list, and the single verdict `STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW`.

---

## 5. Alembic ownership strategy

### 5.1 Established facts

1. After the proposed transfer, existing application tables, sequences, views, enums, domains and standalone composites are owned by `rupaywala_owner` (SQL §3, `:1536-1638`; assertion §7.3).
2. A plain Alembic run with `rupaywala_migrator` login executes as `session_user=rupaywala_migrator` and `current_user=rupaywala_migrator` (`alembic/env.py:13,77`).
3. `INHERIT` membership in `rupaywala_owner` should permit ownership-sensitive DDL on owner-owned objects, but it does not change `pg_class.relowner` for newly created objects. A plain migrator run would record new 0006 objects as migrator-owned. Preflight SQL §1A.1 (`:363-465`) validates an existing migrator-to-owner row's `set_option=true` before mutation, and post-change SQL §7A (`:3045-3173`) reasserts it; INHERIT alone does not prove the `PGOPTIONS='-c role=rupaywala_owner'` startup role can be assumed.
4. Alembic/env.py does not issue `SET ROLE`; neither `alembic.ini` nor migrations do.
5. `app/database.py:15` has SQLite-only `connect_args` and is not the Alembic engine.

### 5.2 Chosen concrete strategy

Use libpq startup role environment on the actual Alembic process:

```text
$env:DATABASE_URL = 'postgresql+psycopg2://rupaywala_migrator@127.0.0.1:55432/rupaywala_validation'
$env:PGOPTIONS = '-c role=rupaywala_owner'
psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=rupaywala_migrator" -c "SELECT current_user, session_user;"
# expected: current_user=rupaywala_owner; session_user=rupaywala_migrator
alembic upgrade 0006_stage5_security_remediation
Remove-Item Env:PGOPTIONS
```

Why this strategy:

- It requires no edit to `alembic/env.py`, `alembic.ini`, or any migration.
- It reaches every libpq connection created by `create_engine()` at `alembic/env.py:77`.
- The identity probe uses the identical environment and must be run before Alembic.
- A separate psql-only `SET ROLE` demonstration is explicitly insufficient.
- URL `?options=-c%20role%3Drupaywala_owner` is a narrower alternative but requires percent-encoding care.
- `connect_args={"options": ...}` is rejected because it requires editing `env.py`.
- Offline `alembic --sql` cannot validate identity (`alembic/env.py:60-70`).

### 5.3 Ownership verification after 0006

Catalog checks in SQL §10 and §12 verify: revision `0006_stage5_security_remediation`; schema owner `rupaywala_owner`; all relations owned by `rupaywala_owner`; expected three indexes and one unique constraint present; `signature_version` and `quote_ref` present; no migrator/app-owned objects; default ACLs unchanged. These are `STATICALLY VALIDATED` requirements only and remain `UNVERIFIED` until executed in the disposable environment.

---

## 6. Smoke-test SQL validation results

### 6.1 Global result

Every smoke-test statement in SQL §8 is statically schema-consistent with revision `0005_fixed_quotes`. No omitted NOT NULL column was found. Success still depends on runtime prerequisites: collision-free fixed IDs, unique literals, FK-dependency absence, committed enum labels, a real `rupaywala_app` login, and pre/post sequence capture.

### 6.2 Per-statement validation

Legend: `YES*` = schema-valid but runtime-data dependent; `DENY` = negative privilege probe expected to fail; `SEQ` = persistent sequence side effect.

| Source | Statement / expected schema | Static result | Supporting source | Setup / persistent state |
|---|---|---|---|---|
| SQL `637-2642` | `INSERT users` with fixed `id=900001`, required enums/booleans supplied | `YES*` | `app/models/user.py:44-69`; b96 `:132-137` | Check id/phone/username; rollback reverses row |
| SQL `644-2645` | `INSERT service_types` fixed id/code | `YES*` | `app/models/service_type.py:14+` | Check id/code; rolled back |
| SQL `647-2649` | `INSERT branches` fixed id | `YES*` | `app/models/branch.py:7+` | Check id; rolled back |
| SQL `651-2653` | `INSERT distance_rate_config` fixed id, `updated_by=900001` | `YES*` | `app/models/distance_rate_config.py:18+` | Requires parent user; rolled back |
| SQL `655-2657` | `INSERT customer_profiles` fixed id/user | `YES*` | `app/models/customer_profile.py:17+` | Requires user; check unique user; rolled back |
| SQL `659-2663` | `INSERT otp_verifications`, `purpose='login'` | `YES*` | `app/models/otp_verification.py:18-54` | Enum label committed; rolled back |
| SQL `665-2667` | `INSERT subscription_plans` fixed id/code | `YES*` | `app/models/subscription_plan.py:7+`; plan catalog `:171-185` | Check id/code; sequence touched later; `SEQ` |
| SQL `669-2671` | `INSERT user_subscriptions` fixed id/FKs/status `active` | `YES*` | `app/models/user_subscription.py:22-79` | Requires user + plan; enum; rolled back |
| SQL `673-2675` | `INSERT subscription_family_members` fixed id/identity key | `YES*` | `app/models/subscription_family_member.py:7+` | Requires subscription; check pair; rolled back |
| SQL `677-2679` | `INSERT policies` fixed id/user | `YES*` | `app/models/policy.py:8+` | Requires user; check no dependents; rolled back |
| SQL `681-2682` | `INSERT policy_members` fixed id/policy | `YES*` | `app/models/policy_member.py:7+`; `app/models/policy.py:32-34` | Requires policy; delete before policy; rolled back |
| SQL `684-2686` | `INSERT field_members`, `approval_status='approved'` | `YES*` | `app/models/field_member.py:9-20` | Requires user; enum; check unique user; rolled back |
| SQL `688-2690` | `INSERT service_requests`, `status='requested'` | `YES*` | `app/models/service_request.py:23-127` | Requires user; enum; rolled back |
| SQL `692-2694` | `INSERT request_assignments`, `status='active'` | `YES*` | `app/models/request_assignment.py:20+` | Requires request + field member; enum; rolled back |
| SQL `698-2701` | `INSERT service_quotes` with generated `id`, `quote_ref`, `signature`, `user_id`, `request_type`, `status` | `YES*` | `0005_fixed_quotes.py:20-80`; `app/models/service_quote.py:56-105` | 18th table does **not** use fixed `900001`; consumes its id sequence; at 0005 no `signature_version` column; rolled back except sequence |
| SQL `703-2706` | `INSERT payments` fixed id/txn, enums, `expires_at` | `YES*` | `app/models/payment.py:22-90` | Requires user; check txn/id; enum; rolled back |
| SQL `708-2710` | `INSERT visit_ledger` fixed id/FKs/`entry_type='allocated'` | `YES*` | `app/models/visit_ledger.py:31+` | Requires subscription + user; enum; rolled back |
| SQL `712-2714` | `INSERT notifications` fixed id/category `account` | `YES*` | `app/models/notification.py:7+` | Requires user; enum; rolled back |
| SQL `717-2734` | SELECT count over all 18 runtime tables | `YES` | Runtime grant matrix in report §8 | Rolled back |
| SQL `736-2756` | `nextval()` on all 18 id sequences | `YES` | `app/services/plan_catalog.py:171-185` for sequence use context | `SEQ`: 18 increments survive rollback |
| SQL `758-2767` | Nine required UPDATE probes | `YES*` | Model files above | Probe rows must exist; enum in progress/consumed/success; rolled back |
| SQL `769-2773` | `setval(plans_seq,900001,true)` | `YES` | `app/services/plan_catalog.py:177-178`; SQL grant at `:1757-1762` | `SEQ`: next id `900002`; persists; coordinate with seeding |
| SQL `775-2780` | Five required DELETE probes | `YES*` | `app/models/policy.py:32-34`; FK refs in quote/request models | Correct child-before-parent order; no pre-existing dependents; rolled back |
| SQL `502-2630` | Negative DDL/role/SELECT/DML probes | `DENY` | SQL §4/§7 ACL assertions | DO-atomic, not `BEGIN/ROLLBACK`; PASS notices required; separate CREATE DATABASE probe |

### 6.3 Corrections applied

- Section 8 header now distinguishes DO-atomic 8a from transaction-wrapped 8b.
- Section 8.0 added as manual prerequisites.
- `\set ON_ERROR_STOP on` inclusion documented.
- `service_quotes.id` generation documented.
- `setval(...,true)` next-id and persistence documented.
- Collision/FK/enum prerequisites documented.
- No smoke-test statement was removed because all are statically supported by the revision 0005 schema.

---

## 7. PostgreSQL 18 privilege completeness

### 7.1 Covered before this audit

Direct app table grants, sequence USAGE, temporary sequence UPDATE, TRUNCATE/TRIGGER negative checks, owner/type ownership, and default privileges for future tables/sequences were present.

### 7.2 Gaps corrected

| Privilege/provenance | Correction |
|---|---|
| DB `CONNECT` | Strict positive assertion for app, plus migrator/owner evidence. |
| DB `TEMP` | PUBLIC default asserted true; app effective TEMP asserted; no broad grant added. |
| DB `CREATE` | Strict false for app, owner, migrator. |
| Schema `USAGE` | Strict positive assertion for app. |
| Schema `CREATE` | PUBLIC false, app false, owner true, migrator true via INHERIT. |
| Table `REFERENCES` | Evidence and strict false assertion added. |
| Table `MAINTAIN` | Evidence and strict false assertion added. |
| Zero-privilege tables | `family_members`/`alembic_version` now cover all eight PG18 table privileges. |
| Sequence `USAGE`/`SELECT`/`UPDATE` | Existing coverage retained and reconciled. |
| Type `USAGE` | ACL-based assertion for custom enum/domain/composite types. |
| Routine `EXECUTE` | ACL-based assertion for public routines. |
| Default ACLs | Four exact expectations plus no-unexpected-app-grant assertion. |
| PUBLIC ACLs | No PUBLIC ACL on relations/sequences; intended PUBLIC database/schema defaults asserted. |
| Ownership | Schema/relation/type/app-owned checks; routines inventoried, not transferred. |
| Exhaustive public objects | SQL §13 inventories every `public` `r`/`p`/`v`/`m`/`f`/`S` object, validates relkind, requires exact direct app grants, rejects all PUBLIC object ACLs and grant options, and checks effective PG18 privileges. |
| Role membership (H-05) | SQL §7A checks both `member`/`roleid` directions and exact `inherit_option`/`set_option`/`admin_option` values after mutation; only migrator-to-owner `(true,true,false)` is allowed. |
| Database/schema ACL provenance (H-06) | SQL §7B checks `datacl`/`nspacl` with `acldefault()` NULL expansion, `aclexplode()`, PUBLIC OID `0`, direct-versus-effective privileges and grant options for PUBLIC/app/owner/migrator after mutation. |
| Preflight H-05 | SQL §1A.1 (`:363-465`) checks existing memberships/options before `CREATE ROLE`; absent migrator-to-owner row is allowed, all other unexpected rows abort. |
| Preflight H-06 | SQL §1A.2 (`:467-691`) checks `datacl`/`nspacl` provenance, required PUBLIC defaults, optional non-grantable target ACLs and unsafe effective CREATE before grants/schema ownership change. |
| Preflight public objects | SQL §1A.3 (`:693-1011`) inventories every public `r`/`p`/`v`/`m`/`f`/`S` object, explicitly aborts on extension-owned objects and rejects unlisted objects, wrong relkinds, unexpected app/PUBLIC ACLs and forbidden effective privileges before mutation. |
| Preflight Section 7.10 provenance | SQL §1A.4 (`:1013-1411`) checks GLOBAL/per-schema `pg_default_acl`, built-in PUBLIC defaults, custom type/routine ACLs, effective app access and app/PUBLIC grant options before mutation; post-change §7.10 (`:2245-2476`) is unchanged. |

### 7.3 Least-privilege position

No broad PUBLIC grant was added. No destructive PUBLIC revoke was performed. PostgreSQL defaults for database `CONNECT`/`TEMP`, schema `USAGE`, type `USAGE`, and routine `EXECUTE` are documented and asserted where relevant. No PUBLIC object ACL is allowed on any `public` relation or sequence audited by §1A.3/§13. Application table privileges remain limited to source-derived S/I/U/D; REFERENCES, TRUNCATE, TRIGGER, MAINTAIN, and schema/database CREATE remain denied. Owner and migrator privileges are not weakened: §1A and §13 are read-only, and earlier ownership assertions remain authoritative. Unexpected pre-existing state is reported and aborts before mutation; the preflight never repairs it automatically.

### 7.4 Distinction of privilege sources

- **Direct grants:** SQL §4 grants exact app table/sequence privileges.
- **Inherited role privileges:** migrator inherits owner privileges via `GRANT ... WITH INHERIT` semantics; app is `NOINHERIT` with no membership.
- **PUBLIC privileges:** DB CONNECT/TEMP, schema USAGE, type USAGE, routine EXECUTE are defaults; schema CREATE is expected false.
- **Ownership privileges:** `rupaywala_owner` owns schema and application objects; indexes/constraints follow table ownership and are not separately re-owned.

All `has_*_privilege()` results are effective; SQL §7.10 adds ACL-level provenance checks.

### 7.5 Complete public-object privilege allowlist

`SOURCE VERIFIED`: the 18 runtime tables below match the active application models and read/write paths. `family_members` is model-only with no runtime DML; `alembic_version` is migration-only. No migration creates a view, materialized view or foreign table. SQL §13 (`:3486-3529`) enforces this exact allowlist; the report's §8.1 is the companion cross-check.

| Public object | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `public.users` | yes | yes | yes | no |
| `public.branches` | yes | yes | yes | no |
| `public.customer_profiles` | yes | yes | yes | no |
| `public.field_members` | yes | yes | yes | no |
| `public.notifications` | yes | yes | yes | yes |
| `public.otp_verifications` | yes | yes | yes | yes |
| `public.payments` | yes | yes | yes | no |
| `public.policies` | yes | yes | no | yes |
| `public.policy_members` | yes | yes | no | yes |
| `public.request_assignments` | yes | yes | yes | no |
| `public.service_quotes` | yes | yes | yes | no |
| `public.service_requests` | yes | yes | yes | no |
| `public.service_types` | yes | yes | yes | no |
| `public.subscription_plans` | yes | yes | yes | no |
| `public.subscription_family_members` | yes | yes | no | yes |
| `public.user_subscriptions` | yes | yes | yes | no |
| `public.visit_ledger` | yes | yes | no | no |
| `public.distance_rate_config` | yes | yes | no | no |
| `public.family_members` (deny) | no | no | no | no |
| `public.alembic_version` (deny) | no | no | no | no |

Every listed expected privilege must exist as a direct `rupaywala_app` ACL entry. TRUNCATE, TRIGGER, REFERENCES and MAINTAIN are always false. Sequences are allowed only at `pg_get_serial_sequence(public.<table>, 'id')` for the same 18 insert tables: USAGE must be true and directly granted, SELECT false, and UPDATE true and directly granted only for `public.subscription_plans` for startup `setval()`. PUBLIC object ACLs and all grant options are rejected. Any other public `r`/`p`/`v`/`m`/`f`/`S` object is an `UNLISTED_OBJECT` violation; a listed name with the wrong relkind is a `RELKIND_MISMATCH` violation. Unknown objects are reported, never revoked.

### 7.6 Finding H-05 — role membership completeness

**Original weakness.** Earlier checks inspected selected membership directions and `admin_option` only. They did not enumerate all rows touching the three target roles in both directions, did not validate PostgreSQL 18 `inherit_option` or `set_option`, and did not distinguish inherited privilege from the SET capability required by the `PGOPTIONS='-c role=rupaywala_owner'` Alembic strategy.

**Exact remediation (SQL §7A, `:3045-3173`).** Evidence query `:3061-3082` resolves `pg_auth_members.member` and `.roleid` with `pg_get_userbyid()` and prints `inherit_option`, `set_option` and `admin_option`. Fail-closed assertions at `:3084-3173` recheck role attributes and require exactly one row touching the target roles:

| Member | Granted role (`roleid`) | `inherit_option` | `set_option` | `admin_option` |
|---|---|---:|---:|---:|
| `rupaywala_migrator` | `rupaywala_owner` | true | true | false |

Any other row where `member` or `roleid` is one of the three target roles is `UNEXPECTED_MEMBERSHIP`; a row with the expected endpoints but wrong options is `INVALID_MIGRATOR_MEMBERSHIP_OPTIONS`. Error text includes exact `member=`, `granted_role=`, `inherit_option=`, `set_option=` and `admin_option=` state. No membership is revoked. `INHERIT` is explicitly not accepted as proof of startup-role capability; `set_option=true` is required and the live PGOPTIONS probe remains mandatory.

**Preflight counterpart.** SQL §1A.1 (`:363-465`) applies the same endpoint/option rules before `CREATE ROLE`. Evidence at `:371-392` reports every existing row touching the three target roles. An absent migrator-to-owner row is allowed because Section 2 adds it; an existing row must be exactly `(true,true,false)`. Violations at `:418-450` and duplicate rows at `:452-461` abort before mutation with exact member/granted-role/option values and no automatic revoke. **Limitation:** actual catalog option values and Alembic identity effect are `UNVERIFIED`.

### 7.7 Finding H-06 — database and schema ACL completeness

**Original weakness.** Effective privilege checks could not reveal whether access came from a direct grant, PUBLIC default, INHERIT membership or ownership. Direct `datacl`/`nspacl` provenance for all four grantees and all applicable grant options was not exhaustively audited.

**Exact remediation (SQL §7B, `:3175-3417`).** Evidence query `:3190-3239` and assertions `:3241-3417` read `pg_database.datacl` and `pg_namespace.nspacl`, expand NULL ACLs with `acldefault('d', datdba)` and `acldefault('n', nspowner)`, expand entries with `aclexplode()`, resolve names with `pg_get_userbyid()`, treat grantee `0` as PUBLIC, normalize `TEMP`/`TEMPORARY`, and separately call `has_database_privilege()`/`has_schema_privilege()` for effective state. Direct/ACL-level allowances are: database PUBLIC CONNECT/TEMP, app CONNECT, migrator CONNECT (all non-grantable); schema PUBLIC USAGE, app USAGE (both non-grantable), and owner schema CREATE/USAGE with ownership grant option tolerated. Everything else for PUBLIC/app/owner/migrator on these two objects is rejected, including PUBLIC schema CREATE, database CREATE for app/owner/migrator, direct app TEMP, direct migrator schema entries, direct owner database entries and any grant option for PUBLIC/app/migrator. Effective checks require PUBLIC DB CONNECT/TEMP and schema USAGE true with schema CREATE false; app CONNECT/TEMP/USAGE true and both CREATE values false; owner DB CREATE false and schema USAGE/CREATE true; migrator DB CREATE false, CONNECT/TEMP true and schema USAGE/CREATE true through the H-05-audited membership. Failures report exact `object_type`, `object`, `grantee`, `privilege`, `grant_option` and detail; no ACL is revoked.

**Preflight counterpart.** SQL §1A.2 (`:467-691`) applies a stricter pre-change model before grants and schema ownership change. Evidence at `:479-533` expands NULL `datacl`/`nspacl` with `acldefault('d', ...)`/`acldefault('n', ...)` and labels `ACL_DEFAULT` versus `DIRECT_ACL`. Required PUBLIC defaults must already exist; optional app/migrator CONNECT and app USAGE entries may be absent but must be non-grantable if present. Unexpected owner database entries, migrator schema entries, PUBLIC CREATE, direct app TEMP, any grant option and unsafe effective CREATE abort at `:685-688`; nothing is revoked or broadened. **Limitation:** actual ACL arrays, `acldefault()` output, grant flags and effective results are `UNVERIFIED` until the disposable catalog gate runs.

---

## 8. Role and password workflow

### 8.1 Existing roles

- Existing role attributes are validated and aborted on conflict; they are not silently altered.
- Existing passwords are never reset by the artifact.
- Existing `rupaywala_migrator` or `rupaywala_app` without a password aborts by design.
- Preflight §1A.1 (`:363-465`) allows an absent migrator-to-owner membership, but an existing row must have `inherit_option=true`, `set_option=true`, `admin_option=false`; every other row touching the target roles aborts before mutation.
- Existing migrator with ADMIN OPTION on owner, any unexpected membership in either direction, or any wrong `inherit_option`/`set_option` value aborts.
- `GRANT rupaywala_owner TO rupaywala_migrator` is idempotent and is the one membership mutation; its intended PG18 option triple is `inherit=true`, `set=true`, `admin=false`.
- The preflight never revokes or repairs an unexpected membership; it reports exact catalog state and stops for manual investigation.
- `rupaywala_app` receives no membership and cannot inherit owner/migrator privileges.

### 8.2 New roles

- Roles are created through `\gset`/`\if` gates.
- `\password` prompts only for newly created login roles.
- `\password` requires an interactive TTY; piped/heredoc execution is unsafe for first-run provisioning.
- Never use `-c`, a shell literal, or exported `PGPASSWORD` containing a secret.

### 8.3 Safe operator sequence

1. Use an interactive terminal.
2. `psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=validation_admin" -W`
3. Confirm `\conninfo`, internal port `5432`, exact PostgreSQL `18.1`, revision `0005_fixed_quotes`.
4. `\i database/security/stage_5_6d_postgresql_roles_corrected.sql`
5. Enter new role passwords twice at prompts only when asked.
6. Confirm attributes, `rolpassword IS NOT NULL AS has_password`, membership, and privilege queries; never select password values or hashes.
7. Use DSN separation: bootstrap `validation_admin`, Alembic `rupaywala_migrator`, runtime `rupaywala_app`.
8. Process-level `DATABASE_URL` override is mandatory because the repository `.env` is non-disposable.

---

## 9. Bootstrap cross-check

- `b96aae0ed4c8_add_email_otp_support.py:21` drops `activity_logs`.
- Additional drops at `:76-79`, `:88`, `:101-102`, `:131`, `:154-155` are seven indexes and three unique constraints.
- Total: **11 objects**, **10 additional beyond the table** (`stage_5_6d_disposable_bootstrap_plan.md:239-270`).
- The bootstrap creates only those shells; it does not insert data, edit migrations, stamp past `b96`, or use `create_all()`.
- Internal port `5432` remains gated; external `55432` is verified only by `\conninfo`.
- Exact PostgreSQL `18.1` gate is now in plan and SQL.

---

## 10. Post-migration verification checklist

### 10.1 Catalog assertions — not executed

- [ ] Read-only SQL §1A preflight (`:350-1411`), including §1A.4, completed first with zero findings, before `CREATE ROLE` at `:1430`; any finding stopped the file and was reviewed manually, not auto-repaired.
- [ ] Preflight H-05: existing target-role memberships/options valid; absent migrator-to-owner row allowed; no unexpected row, wrong option triple or ADMIN OPTION.
- [ ] Preflight H-06: required PUBLIC DB CONNECT/TEMP and schema USAGE provenance present; no unexpected direct ACL, grant option or unsafe effective CREATE.
- [ ] Preflight §13: every public `r`/`p`/`v`/`m`/`f`/`S` object classified; no missing/unlisted object, relkind mismatch, unexpected app/PUBLIC ACL or forbidden effective privilege; no extension-owned object.
- [ ] Identity under identical `PGOPTIONS`: `current_user=rupaywala_owner`, `session_user=rupaywala_migrator`.
- [ ] `public.alembic_version` is `0006_stage5_security_remediation`.
- [ ] `public` schema owner is `rupaywala_owner`.
- [ ] All non-extension relations in `public` have `relowner=rupaywala_owner`.
- [ ] Enum/domain/standalone-composite owners are `rupaywala_owner`.
- [ ] No object in `public` is owned by `rupaywala_app` or `rupaywala_migrator`.
- [ ] `uq_service_requests_quote_ref` exists as a unique constraint.
- [ ] `uq_payments_user_type_idem_open` and `uq_payments_open_extra_charge_request` exist as partial unique indexes; all three new indexes are owner-owned.
- [ ] `service_quotes.signature_version` is integer NOT NULL DEFAULT `1`.
- [ ] `service_requests.quote_ref` is varchar(64) NULL.
- [ ] SQL §7.10 privilege/default-ACL assertions still pass.
- [ ] SQL §7A H-05 membership directions and exact `inherit_option`/`set_option`/`admin_option` state pass.
- [ ] SQL §7B H-06 direct `datacl`/`nspacl` provenance, grant options and effective database/schema privileges pass.
- [ ] No unintended PUBLIC ACLs on relations/sequences.

### 10.2 Behavioral tests — not executed

- [ ] Real `rupaywala_app` login cannot CREATE/ALTER/DROP/TRUNCATE tables, CREATE ROLE/DATABASE, SET ROLE, or access `family_members`/`alembic_version`.
- [ ] Required app DML succeeds after collision/FK/enum prerequisites.
- [ ] `nextval()` and `setval()` effects are captured and restored manually.
- [ ] Application startup with real `rupaywala_app` works after 0006; note model default `SIGNATURE_VERSION=2` (`app/models/service_quote.py:46,69-71`) differs from DB default `1` (`0006...py:90-98`) for raw SQL inserts.

### 10.3 Operational prerequisites — not performed

- [ ] Explicit approval for exact disposable target.
- [ ] Bootstrap reaches `0005_fixed_quotes`.
- [ ] Read-only preflight §1A executed first against the disposable database; findings stop the file and require manual investigation.
- [ ] Interactive password provisioning complete.
- [ ] Verified backup and successful restore test.
- [ ] Maintenance window, stopped sessions, accepted index-build lock impact.
- [ ] `PGOPTIONS` identity probe validated with identical environment.
- [ ] No production access and no Stage 6 work.

---

## 11. Remaining unresolved issues

1. No live PostgreSQL parser/execution validation was performed.
2. Exact server version/catalog state was not observed.
3. Interactive password provisioning was not performed and requires a TTY.
4. The `PGOPTIONS` startup-role identity effect and the live `pg_auth_members.set_option`/`inherit_option` values are source/documented but `UNVERIFIED` live.
5. Post-0006 object ownership is `UNVERIFIED`.
6. Application-role behavioral tests are `NOT EXECUTED`.
7. Fixed-ID/unique-literal collisions, FK dependencies, and enum-label state require manual checks.
8. Sequence values consumed by smoke tests require manual capture/restoration.
9. Backup creation and restore verification remain outstanding.
10. Test infrastructure hardenings in `tests/conftest.py` are recommended but not implemented.
11. All future database/Alembic/container operations require explicit approval.
12. The live SQL §13 exhaustive public relation/sequence audit is `UNVERIFIED`; any `UNLISTED_OBJECT`, `RELKIND_MISMATCH`, unexpected app/PUBLIC `DIRECT_ACL`, `MISSING_DIRECT_ACL`, `WITH GRANT OPTION` or effective-privilege mismatch requires manual review and explicitly approved, non-blind remediation before 0006.
13. Live SQL §7A H-05 membership/option state and SQL §7B H-06 `datacl`/`nspacl` provenance are `UNVERIFIED`; any unexpected membership, option combination, direct ACL, missing expected ACL or grant option requires manual investigation before 0006.
14. Live SQL §1A preflight results are `UNVERIFIED`. Its H-05, H-06, §13 and §7.10-provenance catalog checks must pass before any mutation; any finding aborts the file and requires manual investigation rather than automatic revocation.
15. Any extension-owned public relation or sequence reported by preflight §1A.3 requires manual review. The preflight deliberately aborts instead of treating it as an ordinary application object.
16. The fail-closed ordering has not been parser- or execution-validated. Static inspection only establishes that all four §1A subsections, including §1A.4, precede `CREATE ROLE` at `:1430`, grants and ownership transfer.
17. Live SQL §1A.4 results for `pg_default_acl`, custom-type ACLs, routine ACLs, effective app access and grant options are `UNVERIFIED`; any finding must be manually reviewed before mutation and must not be auto-repaired.

---

## 12. Final verdict

**STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW**

The preparation is internally consistent: all three permitted artifacts agree, read-only SQL §1A (`:350-1411`), including the new Section 7.10 provenance preflight §1A.4 (`:1013-1411`), now fails closed before the first mutation at `:1430`, post-change SQL §7A/§7B/§7.10/§13 remain intact, the role/privilege matrices are unchanged, smoke-test prerequisites are explicit, and the Alembic ownership strategy is concrete via `PGOPTIONS='-c role=rupaywala_owner'`. This is not execution readiness, not production readiness, and not evidence of successful execution. Live identity, parser/catalog, §1A/§7A/§7B/§7.10/§13 catalog, password, collision, sequence, application-role behavioural, backup/restore, and post-migration ownership checks remain unresolved and no execution approval exists. The next stage requires explicit approval and must be performed only against the disposable PostgreSQL 18.1 environment.

---

## 13. Consolidated PUBLIC pseudo-role remediation and final saved-file verification

### 13.1 Original defect and exact correction

The independent review found uppercase `PUBLIC` passed as the role argument to PostgreSQL privilege-inquiry functions. The saved SQL contained twelve affected call sites:

- §7.2 evidence (`:1855-1862`) and assertion (`:1906-1915`): eight direct `has_database_privilege('PUBLIC', ...)` / `has_schema_privilege('PUBLIC', ...)` calls were changed to lowercase `'public'`.
- §1A.2 evidence (`:519-524`) and assertion (`:660-665`), and §7B evidence (`:3230-3235`) and assertion (`:3389-3394`): four ACL-label-derived sites now use `CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END` as the first function argument.

Uppercase `PUBLIC` remains in human-readable labels, CTE/report text, exception messages, comments and ACL output where it is correct. `a.grantee = 0`, `v_public oid := 0`, real role names and ACL catalog semantics were not changed.

### 13.2 Complete static search

The full SQL file was searched for every occurrence of `PUBLIC` and for `has_database_privilege`, `has_schema_privilege`, `has_table_privilege`, `has_sequence_privilege`, `has_function_privilege`, `has_type_privilege`, `aclexplode`, `pg_default_acl`, `acldefault`, `pg_roles`, `pg_auth_members`, `pg_database`, `pg_namespace`, `pg_class`, `pg_type`, `pg_proc` and `pg_depend`. Static and multiline inspection covered dynamic grantee expressions as well as literal calls. Post-edit result: **0** uppercase PUBLIC pseudo-role arguments remain in privilege-inquiry functions. No additional blocking SQL defect was found in this pass.

### 13.3 Final saved-file metrics and boundaries

- File: `database/security/stage_5_6d_postgresql_roles_corrected.sql`; **3,725 lines**, **169,201 bytes**.
- Active `DO $$` / `END $$;`: **22/22**; line-commented example pairs: **9/9**; `$$` tokens: **62** (balanced).
- Block comments: **5/5**; non-ASCII lines: **0**; psql variables inside dollar-quoted bodies: **0**.
- Read-only preflight: `:350-1411`; first mutation: `:1430`. Every preflight assertion completes before role creation, grants and ownership changes.
- Post-change sections present and read-only: §7A `:3045-3173`, §7B `:3175-3417`, §7.10 `:2245-2476`, §13 `:3419-3725`.
- Mutation-statement scan across those read-only ranges: **0** statement starts from the audited `CREATE`/`ALTER`/`DROP`/`GRANT`/`REVOKE`/DML keyword set.

### 13.4 Method, limits and no-operation confirmation

Method: full-file text search, targeted line-by-line inspection, and scoped PowerShell counters for delimiters, dollar-quoted bodies, psql variables and mutation-statement starts. No parser, catalog query, execution, application runtime, Docker action, Alembic command, migration 0006 execution, backup/restore or credential change occurred. No database was modified; production was untouched. These results do not claim PostgreSQL parser validation, catalog validation, runtime success or execution success. `database/security/stage_5_6d_disposable_bootstrap_plan.md` was not modified in this pass.

**Final verdict: STATIC REVIEW COMPLETE — READY FOR DISPOSABLE VALIDATION REVIEW**
