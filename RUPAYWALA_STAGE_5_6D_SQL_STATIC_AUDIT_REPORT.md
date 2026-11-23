# RUPAYWALA_STAGE_5_6D_SQL_STATIC_AUDIT_REPORT.md

**Stage:** 5.6D — Read-only pre-execution static audit of the Stage 5.6C SQL artifact  
**Date:** 2026-11-20  
**Mode:** STATIC INSPECTION ONLY — NO DATABASE CONNECTION, NO SQL EXECUTION  
**Artifact audited:** `database/security/stage_5_6c_postgresql_roles.sql` (743 lines)  
**Target:** PostgreSQL 18.1, container `rupaywala-pg18-validation`, database `rupaywala_validation`, user `validation_admin`, host port `55432`

---

## 1. Artifact completeness verdict

| Required element | Present | Assessment |
|---|---:|---|
| Header with "PROPOSED — NOT EXECUTED" and disposable-environment warning | Yes | Good |
| 1.1 Read-only preflight queries | Yes | Mostly complete; missing current Alembic revision and explicit superuser check |
| 1.2 Role creation with least-privilege attributes | Yes | Present; non-idempotent |
| 1.3 Database and schema access | Yes | Present; commented CREATE-grant ordering is misleading |
| 1.4 Corrected ownership transfer (relations, enums, domains, standalone composites) | Yes | Present; extension exclusions present; routine/other object classes intentionally omitted |
| 1.5 Explicit runtime table grants | Yes | **Incomplete** — `family_members` is absent |
| 1.6 Sequence grants including temporary `subscription_plans` UPDATE | Yes | Present; temporary UPDATE is a documented gap |
| 1.7 Conservative default privileges | Yes | Present; effectiveness depends on which role actually creates objects |
| 1.8 Post-setup verification queries | Yes | Present; lacks negative tests, PUBLIC-privilege checks, revision check |
| 1.9 Rollback / recovery plan | Yes | Prose only; no executable restore SQL |
| Placeholder policy | Partial | 9 angle-bracket placeholders found; no substitution register in the file |

**VERDICT: INCOMPLETE — NOT EXECUTION-READY.**

The artifact is structurally coherent and contains all nine numbered sections, but it must not be executed as-is. Two independent blockers exist:

1. **Schema prerequisite blocker:** the Alembic chain cannot build revision `0005_fixed_quotes` on a fresh PostgreSQL 18.1 database because `b96aae0ed4c8` drops objects that no earlier migration creates.
2. **Artifact blocker:** unresolved placeholders, a missing `family_members` grant set, non-idempotent role creation, missing negative verification, and undocumented privilege prerequisites.

No execution, container modification, or production contact is authorized by this audit.

---

## 2. SQL findings by severity

### CRITICAL / BLOCKER

| ID | Location | Finding | Impact | Required action |
|---|---|---|---|---|
| C-01 | Migration `b96aae0ed4c8...py:21` | `op.drop_table('activity_logs')` is unconditional. No migration creates `activity_logs` on a fresh chain; the only `CREATE TABLE activity_logs` is in that migration's **downgrade** (line 279). | `alembic upgrade 0005_fixed_quotes` fails on a fresh database at this revision. The required representative schema cannot be built with the unmodified chain. | Use the disposable-only bootstrap in Section 5. Do not modify the migration. |
| C-02 | Artifact lines 162, 167, 174 | `CREATE ROLE` statements have no existence guard. | A second run, or a database where any role already exists, fails with `duplicate_object`. | Start from a fresh disposable database or add an external, approved idempotency guard before any rerun. |
| C-03 | Artifact lines 347–412 | `family_members` is absent from `select_tables`, `insert_tables` and `update_tables`. The table exists at revision 0005 (created in `0001`, indexed in `0003`, model still registered in `alembic/env.py`). | `rupaywala_app` receives no privileges on a real runtime table. The verification summary at lines 636–647 will show `family_members` with all `false` flags. | Either add `family_members` to the approved arrays or record a formally approved exclusion with rationale. |

### HIGH

| ID | Location | Finding | Impact | Required action |
|---|---|---|---|---|
| H-01 | Artifact lines 162–179, 195, 218–336, 535–553 | Active statements require a superuser (or, at minimum, membership in both old and new owning roles plus `CREATEROLE` for role creation). The artifact never asserts this. | `CREATE ROLE`, `ALTER ... OWNER TO`, and `ALTER DEFAULT PRIVILEGES FOR ROLE <other>` can fail partially. | Gate execution on `SELECT rolsuper FROM pg_roles WHERE rolname = current_user` being true in the disposable DB, or document the exact minimal role memberships. |
| H-02 | Artifact lines 168, 175 | Passwords are embedded as SQL string literals (`'<MIGRATOR_PASSWORD>'`, `'<APP_PASSWORD>'`). | Even test-only values can leak into shell history, psql history, or logs if substituted carelessly. | Inject via approved secret handling / psql variables; never commit real values. See Section 3. |
| H-03 | Artifact lines 508–521, 526–528 | `rupaywala_app` is granted `UPDATE` on `public.subscription_plans_id_seq` solely because `plan_catalog.py:177` calls `setval()`. The revoke is commented out. | A live security gap: the app role can advance the sequence. | Keep as an explicitly time-boxed temporary exception; revoke immediately when runtime `setval()` is removed. Record acceptance before sign-off. |
| H-04 | Artifact section 1.8 | Verification uses `has_*_privilege()` only. There are no actual negative tests (no `SET ROLE`/direct-login attempt to prove DDL, DELETE, or Alembic-history access is denied). | Privileges may appear correct in catalogs while behavior differs (e.g., inherited PUBLIC grants). | Add the negative tests listed in Section 6 after section 1.8. |
| H-05 | Artifact section 1.1 vs 1.9 | Rollback plan requires recording "Current Alembic revision", but preflight never queries `public.alembic_version`. | Rollback evidence is incomplete. | Add `SELECT version_num FROM public.alembic_version;` to preflight. |
| H-06 | Artifact lines 535–553 vs 1.4 | Default privileges are declared for both `rupaywala_owner` and `rupaywala_migrator`, but ownership is transferred to `rupaywala_owner`. If migrations run with `SET ROLE rupaywala_owner`, the migrator defaults never apply; if they run as `rupaywala_migrator`, new objects are owned by the migrator until re-transferred. | Ownership end-state and default-privilege end-state can diverge from intent. | Decide and document which role actually creates objects during migrations; verify with the object-owner query after any later migration. |
| H-07 | Artifact lines 431–452 | Only the SELECT loop checks table existence. INSERT/UPDATE/DELETE loops issue unguarded `GRANT ... ON TABLE public.%I`. | A missing table causes a partial run: some grants applied, others not. | Pre-validate the complete table inventory, or add the same existence guard to every loop. |

### MEDIUM

| ID | Location | Finding | Impact | Required action |
|---|---|---|---|---|
| M-01 | Artifact lines 192–198, 210–211 | The commented `GRANT CREATE ON DATABASE <DB_NAME> TO rupaywala_owner` / revoke is presented as part of ownership transfer. `GRANT CREATE ON DATABASE` does **not** enable `ALTER SCHEMA ... OWNER TO`; membership/superuser does. On PostgreSQL 15+ the `REVOKE CREATE ON SCHEMA public FROM PUBLIC` is normally a no-op on a fresh database. | Misleading ordering; on upgraded clusters PUBLIC CREATE may still exist and permit app-side object creation. | Do not enable the database CREATE grant for this step. Explicitly verify PUBLIC CONNECT/CREATE as shown in Section 6. |
| M-02 | Artifact lines 218–336 | Ownership loop intentionally omits routines, collations, text-search objects, publications, large objects, operator classes, etc. | Those objects keep their prior owners. The verification query at lines 684–692 checks function EXECUTE but not function owner. | Accept explicitly or extend the audit scope; do not assume "all public objects" are owned by `rupaywala_owner`. |
| M-03 | Artifact lines 83–117 vs 258–331 | Preflight type query lists array types (`typtype='b'`), while the ownership loop correctly handles only `e`, `d`, and standalone `c`. | Cosmetic noise in evidence; no unsafe action. | Note in evidence that array/table-row composite types are intentionally skipped. |
| M-04 | Artifact lines 497–500, 518–520 | `seq::regclass` is rendered with `%s`, not a forced schema-qualified `%I`. | Name resolution depends on `search_path`; low risk but avoidable. | Confirm `search_path` in the executing session, or change to a fully qualified identifier in an approved revision. |
| M-05 | Artifact lines 347–366 vs 368–387 | `select_tables` and `insert_tables` are identical literal arrays. | Duplication invites drift if one list is edited later. | Keep them synchronized; prefer a single approved source list. |
| M-06 | Artifact lines 419–421, 513–516 | Hard-coded expectations: `service_quotes` must exist (0005 applied) and `public.subscription_plans.id` must have a serial sequence. | Aborts if schema is at 0004 or if sequence naming differs. | Verify revision and `pg_get_serial_sequence()` before execution (Section 6). |

### LOW / INFORMATIONAL

| ID | Finding |
|---|---|
| L-01 | `inet_server_addr()` returns NULL for a Unix-socket connection. Use TCP to `localhost:55432` so identity evidence includes a server IP. |
| L-02 | `current_setting('server_version')` is the correct version source; expect a string beginning with `18.1`. |
| L-03 | The artifact uses `public.%I` / qualified catalog names throughout the PL/pgSQL, so `search_path` dependence is minimal. |
| L-04 | `pg_depend.deptype IN ('e','x')` is used for extension exclusion; `'x'` is legacy but still accepted. Confirm during execution if any extension-owned objects are present. |
| L-05 | The artifact contains no `SET ROLE`. Any `SET ROLE rupaywala_owner` test belongs to a separate migration-role check; `rupaywala_migrator` is a member of the owner, `rupaywala_app` is not. |
| L-06 | The commented `REVOKE UPDATE ON SEQUENCE public.subscription_plans_id_seq ...` hard-codes the expected sequence name; confirm with `pg_get_serial_sequence()` rather than assuming it. |
| L-07 | Role attribute checks are intentionally duplicated in 1.1 and 1.8 (before/after evidence). This is not a defect. |

---

## 3. Required placeholder substitutions

Exactly nine angle-bracket placeholders occur in the artifact.

| Placeholder | Lines | Context | Required substitution form | Notes |
|---|---|---|---|---|
| `<DB_NAME>` | 66 | `WHERE datname = '<DB_NAME>'` | SQL string literal, e.g. `'rupaywala_validation'` | Use the exact disposable database name only. |
| `<DB_NAME>` | 193 | Commented `GRANT CREATE ON DATABASE <DB_NAME> ...` | Bare SQL identifier (double-quote if the name needs it). Prefer leaving commented. | Do not enable for ownership transfer; see M-01. |
| `<DB_NAME>` | 198 | Commented `REVOKE CREATE ON DATABASE <DB_NAME> ...` | Bare SQL identifier. Prefer leaving commented. | Pairs with line 193. |
| `<DB_NAME>` | 202 | `GRANT CONNECT ON DATABASE <DB_NAME> TO rupaywala_migrator` | Bare SQL identifier (quote if needed). | Active statement. |
| `<DB_NAME>` | 203 | `GRANT CONNECT ON DATABASE <DB_NAME> TO rupaywala_app` | Bare SQL identifier (quote if needed). | Active statement. |
| `<DB_NAME>` | 588 | `has_database_privilege('rupaywala_app', '<DB_NAME>', 'CONNECT')` | SQL string literal. | Verification. |
| `<DB_NAME>` | 600 | `has_database_privilege('rupaywala_owner', '<DB_NAME>', 'CREATE')` | SQL string literal. | Verification; expected `false`. |
| `<MIGRATOR_PASSWORD>` | 168 | `LOGIN PASSWORD '<MIGRATOR_PASSWORD>'` | Test-only credential, injected securely; escape `'` if literal substitution is used. | Never use a production or real secret. |
| `<APP_PASSWORD>` | 175 | `LOGIN PASSWORD '<APP_PASSWORD>'` | Test-only credential, injected securely; escape `'` if literal substitution is used. | Never use a production or real secret. |

**Additional hard-coded values that must be confirmed, even though they are not angle-bracket placeholders:**

| Value | Location | Confirmation required |
|---|---|---|
| `public` | Throughout | Target schema is `public` in `rupaywala_validation`. |
| `rupaywala_owner`, `rupaywala_migrator`, `rupaywala_app` | Throughout | Exact role names approved for the disposable environment. |
| `public.subscription_plans_id_seq` | 527–528 | Confirm via `SELECT pg_get_serial_sequence('public.subscription_plans','id')`. |
| Table name arrays | 347–412, 466–485 | Confirm against the actual revision-0005 inventory; `family_members` gap (C-03). |
| `'id'` as sequence column | 491–494, 508–511 | All target tables use `id` as the serial/identity column at 0005. |

No real password, API key, or production connection string is reproduced in this report.

---

## 4. Migration-chain analysis

### 4.1 Actual chain

```
0001_initial_schema
  -> 0002_expand_enums
    -> 0003_visit_credits_lifecycle
      -> b96aae0ed4c8_add_email_otp_support
        -> 0004_subscription_entitlements
          -> 0005_fixed_quotes
            -> 0006_stage5_security_remediation   (head)
```

`b96aae0ed4c8` is **not** a side branch. It is the direct parent of `0004`, so any normal upgrade to `0005_fixed_quotes` must execute it.

### 4.2 Why the chain fails on a fresh database

`b96aae0ed4c8.upgrade()` begins with:

```python
op.drop_table('activity_logs')
```

A repository-wide search found `activity_logs` only inside this migration: the unconditional drop at line 21 and the recreate in `downgrade()` at lines 279–288. No earlier migration creates it. Therefore a fresh upgrade aborts immediately with an undefined-table error.

Even if `activity_logs` were pre-created, the same migration contains further unconditional drops of names that the fresh chain never creates:

| Line | Statement | Actually created by 0001/0003 |
|---|---|---|
| 76 | `DROP INDEX idx_payments_txn_id` | No — created `ix_payments_txn_id` (unique index) |
| 77 | `DROP INDEX idx_payments_utr` | No — created `ix_payments_utr_number` |
| 78 | `DROP CONSTRAINT payments_txn_id_key` | No — uniqueness is a unique index, not a named constraint |
| 79 | `DROP CONSTRAINT payments_utr_number_key` | No — uniqueness is a partial unique index |
| 88 | `DROP INDEX idx_policies_user` | No — created `idx_policies_user_active` / `ix_policies_user_id` |
| 101 | `DROP INDEX idx_requests_policy` | No — created `ix_service_requests_policy_id` |
| 102 | `DROP INDEX idx_requests_user` | No — created `ix_service_requests_user_id` |
| 131 | `DROP INDEX idx_subscription_user` | No — created `ix_user_subscriptions_user_id` |
| 154 | `DROP INDEX idx_users_phone` | No — created `ix_users_phone_number` |
| 155 | `DROP CONSTRAINT users_phone_number_key` | No — uniqueness is a partial unique index |

These names exist only in `b96aae0ed4c8.downgrade()`, confirming the upgrade was generated for a legacy deployed schema, not for a fresh database. The fix must therefore recreate the **legacy starting state**, not merely the one `activity_logs` table.

### 4.3 Schema-preparation options

| Option | Verdict | Reason |
|---|---|---|
| `alembic upgrade 0005_fixed_quotes` on an empty DB | **Reject** | Fails at `b96aae0ed4c8` (C-01 and the additional drops above). |
| `alembic upgrade 0003_visit_credits_lifecycle` then `alembic stamp b96aae0ed4c8` then `upgrade 0005` | **Reject for 5.6D** | Skips b96's real changes: `otp_verifications.email`, `users.email_verified/phone_verified`, enum labels `email_signup`, `email_login`, `email_otp`, and removal of legacy indexes/unique constraints. Not representative of revision 0005. |
| `Base.metadata.create_all()` then `stamp 0005_fixed_quotes` | **Reject for 5.6D** | `tests/conftest.py` uses this path only for its own test DB. It builds the *final model* shape (including 0006-era columns/indexes) and misses revision-specific history; not a 0005-faithful schema. |
| `alembic upgrade 0001:0005 --sql` and patch the emitted script | **Reject** | Offline mode cannot run 0002/0003/0004, which query `op.get_bind()` at runtime. Patching a SQL file is also outside this task's safety rules. |
| Fresh upgrade to 0003 + disposable-only bootstrap of the legacy objects expected by b96 + `upgrade 0005` | **Accept, with approval** | Preserves all real migrations unchanged, yields a genuine revision-0005 schema, and confines the workaround to the disposable database. |

---

## 5. Safe schema preparation procedure

This procedure is a **proposal only**. It has not been executed and must be executed only by an approved operator against `rupaywala_validation` in `rupaywala-pg18-validation`.

1. Confirm the disposable target with the identity gate in Section 6. Do not use `rupaywala_ori`, `postgres`, or any production host/port/role.
2. Point Alembic at the disposable database **without editing files**: set `DATABASE_URL` in the process environment before invoking Alembic. `app/config.py` calls `python-dotenv` with `override=False` (default), so an existing process environment value takes precedence over `.env`. Do not read or print `.env`.
3. Supply test-only values in the process environment for the other import-time required variables (`JWT_SECRET_KEY`, `UPI_ID`). No production secrets.
4. Run `alembic upgrade 0003_visit_credits_lifecycle`. This revision is explicitly written to be fresh-install safe.
5. In the disposable database **only**, apply a bootstrap DDL that recreates the legacy objects that `b96aae0ed4c8` unconditionally drops:

```sql
-- Disposable-only legacy-state bootstrap; applied after revision 0003, before b96aae0ed4c8.
CREATE TABLE public.activity_logs (
    id integer PRIMARY KEY,
    user_id integer REFERENCES public.users(id),
    action varchar(200),
    description text,
    ip_address varchar(50),
    created_at timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_txn_id ON public.payments (txn_id);
CREATE INDEX idx_payments_utr ON public.payments (utr_number);
ALTER TABLE public.payments ADD CONSTRAINT payments_txn_id_key UNIQUE (txn_id);
ALTER TABLE public.payments ADD CONSTRAINT payments_utr_number_key UNIQUE (utr_number);

CREATE INDEX idx_policies_user ON public.policies (user_id);
CREATE INDEX idx_requests_policy ON public.service_requests (policy_id);
CREATE INDEX idx_requests_user ON public.service_requests (user_id);
CREATE INDEX idx_subscription_user ON public.user_subscriptions (user_id);
CREATE INDEX idx_users_phone ON public.users (phone_number);
ALTER TABLE public.users ADD CONSTRAINT users_phone_number_key UNIQUE (phone_number);
```

   These objects are intentionally consumed (dropped) by the real `b96aae0ed4c8` upgrade. No production database, migration file, or SQL artifact is modified.

6. Run `alembic upgrade 0005_fixed_quotes`. `env.py` uses `transaction_per_migration=True`, which keeps the enum-label commits in `b96aae0ed4c8` valid on PostgreSQL 18.
7. Verify the revision and inventory using the queries in Section 6. Expected revision: `0005_fixed_quotes`. Expected: `activity_logs` absent; `service_quotes`, `subscription_family_members`, and `family_members` present.
8. Proceed with the SQL artifact only after these gates pass.

**Explicitly prohibited:** rewriting `b96aae0ed4c8`, adding a new migration file, editing `alembic.ini`/`env.py`/`.env`, or applying any part of this bootstrap outside the disposable database.

---

## 6. Exact PostgreSQL 18.1 execution sequence

All steps below are proposed order only. Nothing in this section has been run.

### Step 0 — Identity and privilege gate (read-only)

```sql
SELECT current_database() AS db,
       current_user,
       session_user,
       current_setting('server_version') AS server_version,
       inet_server_addr()::text AS server_ip,
       inet_server_port() AS server_port,
       (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS is_superuser;
```

Assertions before any DDL/DML:

- `db = 'rupaywala_validation'`
- `current_user = 'validation_admin'`
- `server_version LIKE '18.1%'`
- `server_port = 55432` and `server_ip IS NOT NULL` (use TCP, not a Unix socket)
- `is_superuser = true` (or the documented minimal privilege set from H-01)
- `current_database() NOT IN ('rupaywala_ori', 'postgres')`

### Step 1 — Read-only preflight (artifact section 1.1)

Run all queries in section 1.1 after substituting `<DB_NAME>` as a string literal at line 66. Add:

```sql
SELECT version_num FROM public.alembic_version;   -- record before any changes
SELECT has_database_privilege('public', 'rupaywala_validation', 'CONNECT') AS public_connect,
       has_schema_privilege('public', 'public', 'CREATE') AS public_schema_create;
```

Expected at this point: no `rupaywala_*` roles, no application objects, revision absent or already at the prepared value depending on ordering chosen below.

### Step 2 — Create roles (artifact section 1.2)

Only after Step 1 confirms a clean disposable database. Then re-check with the role-attributes query from section 1.8.

### Step 3 — Build the representative schema (Section 5)

Upgrade to `0005_fixed_quotes` using the disposable-only bootstrap. Then verify:

```sql
SELECT version_num FROM public.alembic_version;
-- expected: 0005_fixed_quotes

SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
-- must include: users, branches, customer_profiles, field_members, notifications,
-- otp_verifications, payments, policies, policy_members, request_assignments,
-- service_quotes, service_requests, service_types, subscription_plans,
-- subscription_family_members, user_subscriptions, visit_ledger,
-- distance_rate_config, alembic_version
-- must NOT include: activity_logs

SELECT pg_get_serial_sequence('public.subscription_plans', 'id');
-- expected: public.subscription_plans_id_seq
```

### Step 4 — Database and schema access (artifact section 1.3)

Keep lines 193, 198, 211 commented unless separately approved. Verify with the "Schema access" query from section 1.8 plus:

```sql
SELECT has_database_privilege('rupaywala_migrator', 'rupaywala_validation', 'CONNECT') AS migrator_connect,
       has_schema_privilege('rupaywala_owner', 'public', 'USAGE') AS owner_usage;
```

### Step 5 — Ownership transfer (artifact section 1.4)

Follow with the "Object owners", "Type owners" and "Function EXECUTE privileges" queries from section 1.8.

### Step 6 — Runtime table grants (artifact section 1.5)

Follow with the "Table privilege summary" query from section 1.8. Special attention:

```sql
SELECT c.relname,
       has_table_privilege('rupaywala_app', c.oid, 'SELECT') AS sel,
       has_table_privilege('rupaywala_app', c.oid, 'INSERT') AS ins,
       has_table_privilege('rupaywala_app', c.oid, 'UPDATE') AS upd,
       has_table_privilege('rupaywala_app', c.oid, 'DELETE') AS del
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('family_members', 'service_quotes', 'alembic_version')
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;
-- alembic_version must be all false; family_members flags depend on the C-03 decision.
```

### Step 7 — Sequence grants (artifact section 1.6)

Follow with the "Sequence privilege summary" query from section 1.8. `subscription_plans_id_seq` should show `upd = true` only while the temporary setval exception is active.

### Step 8 — Default privileges (artifact section 1.7)

```sql
SELECT defaclrole::regrole AS owner_role,
       defaclobjtype,
       defaclacl
FROM pg_default_acl
WHERE defaclnamespace = 'public'::regnamespace
ORDER BY owner_role::text, defaclobjtype;
```

Expect entries for both `rupaywala_owner` and `rupaywala_migrator` covering tables (SELECT) and sequences (USAGE, SELECT).

### Step 9 — Full verification (artifact section 1.8) plus additions

Run every query in section 1.8, then:

```sql
-- Alembic history must remain inaccessible to the application role.
SELECT has_table_privilege('rupaywala_app', 'public.alembic_version', 'SELECT') AS history_select,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'INSERT') AS history_insert,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'UPDATE') AS history_update,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'DELETE') AS history_delete;
-- all expected false

-- PUBLIC posture (usually CONNECT true, CREATE false on fresh PG18).
SELECT has_database_privilege('public', 'rupaywala_validation', 'CONNECT') AS public_connect,
       has_schema_privilege('public', 'public', 'CREATE') AS public_schema_create;
```

### Step 10 — Negative behavioral tests (disposable DB only)

Connect as `rupaywala_app` and confirm each of the following is **denied**:

```sql
CREATE TABLE public.probe (id integer);                 -- must fail
SELECT * FROM public.alembic_version;                   -- must fail
DELETE FROM public.users WHERE id = 1;                  -- must fail
SELECT nextval('public.subscription_plans_id_seq');     -- allowed (USAGE)
SELECT setval('public.subscription_plans_id_seq', 1, false); -- currently allowed only via temporary UPDATE
```

Connect as `rupaywala_migrator` and confirm:

```sql
CREATE TABLE public.migrator_probe (id integer);        -- must succeed before ownership re-transfer check
SET ROLE rupaywala_owner;                               -- must succeed (membership, no ADMIN OPTION needed)
```

Drop any probe objects immediately afterwards in the disposable database.

### Step 11 — Temporary exception closure

When the runtime `setval()` call is removed, execute the previously commented revoke (after confirming the actual sequence name):

```sql
REVOKE UPDATE ON SEQUENCE public.subscription_plans_id_seq FROM rupaywala_app;
```

Then re-run the sequence summary and the negative `setval()` test; the latter must now fail.

### Step 12 — Not in this artifact's execution sequence

Migration `0006_stage5_security_remediation` and application compatibility tests are separate follow-ups. They must not be folded into this SQL run.

---

## 7. Remaining blockers

1. **Approval of the disposable-only bootstrap** for the broken `b96aae0ed4c8` chain (Section 5). Without it, revision 0005 cannot be built.
2. **Placeholder substitution register**: exact disposable database name (`rupaywala_validation`) and two test-only passwords, with a secret-safe injection method. No real credentials may be used or committed.
3. **Decision on C-03 (`family_members`)**: add grants or record an approved, reasoned exclusion.
4. **Privilege confirmation**: `validation_admin` must be superuser in the disposable container, or the exact minimal role memberships must be documented and verified.
5. **Temporary sequence UPDATE exception (H-03)**: accept with an owner and removal criterion, or remove the runtime `setval()` dependency before final validation.
6. **PUBLIC CONNECT/CREATE posture (M-01)**: confirm that inherited PUBLIC privileges in the disposable database are acceptable; the artifact does not revoke them.
7. **Negative tests**: add the behavioral checks in Step 10; catalog `has_*_privilege()` queries alone are insufficient for sign-off.
8. **Revision evidence in preflight**: add the `alembic_version` query required by the rollback plan.
9. **Idempotency policy**: confirm the disposable database is fresh, or define an approved cleanup/rebuild procedure before any rerun.
10. **Human authorization**: execution of any SQL, Alembic command, or container operation remains blocked until the above are resolved and explicitly approved.

---

## 8. Operations not performed

- No connection to any PostgreSQL database, including `rupaywala_validation`, `rupaywala_ori`, or `postgres`.
- No SQL statement executed; no Alembic command run.
- No container started, stopped, restarted, or modified.
- No `.env` file, API key, password, or production connection string read or displayed.
- No source code, migration, SQL file, configuration, or database record modified.
- No role, grant, ownership, sequence, schema, or table created or changed.
- No Stage 6 work started.

---

## Final status

`STAGE 5.6D — SQL STATIC AUDIT COMPLETE; EXECUTION NOT AUTHORIZED`

The SQL artifact is **incomplete and not execution-ready**. The migration chain **cannot** safely build the required revision-0005 schema on a fresh PostgreSQL 18.1 database without the controlled, disposable-only reconstruction described in Section 5. All findings, substitutions, verification queries, and blockers are documented above for human review.
