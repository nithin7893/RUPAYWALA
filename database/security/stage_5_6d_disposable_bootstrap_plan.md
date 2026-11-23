# RUPAYWALA — Stage 5.6D Disposable Bootstrap Plan

**Purpose:** Make the disposable PostgreSQL 18.1 database `rupaywala_validation` reach Alembic revision `0005_fixed_quotes` **without modifying any historical migration, production data, production credentials, or production migration history**.

**Status:** PREPARED — NOT EXECUTED. No database connection, SQL execution, Alembic command, or container operation was performed while producing this plan.

**Labels used below:** `SOURCE VERIFIED` = read directly from repository source; `STATICALLY VALIDATED` = checked for internal consistency in these artifacts; `PROPOSED` = future action; `UNVERIFIED` = requires execution evidence; `NOT EXECUTED` = no runtime proof exists.

---

## 1. Problem being solved

`SOURCE VERIFIED`: the real migration chain is linear:

```text
0001_initial_schema
  -> 0002_expand_enums
    -> 0003_visit_credits_lifecycle
      -> b96aae0ed4c8_add_email_otp_support
        -> 0004_subscription_entitlements
          -> 0005_fixed_quotes
            -> 0006_stage5_security_remediation
```

`SOURCE VERIFIED`: `b96aae0ed4c8.upgrade()` was generated against a legacy deployed database. Its first operation is `op.drop_table('activity_logs')` at line 21. Earlier fresh-chain migrations never create that table.

`SOURCE VERIFIED`: the same migration drops ten more legacy index/constraint objects at lines 76–79, 88, 101–102, 131, 154–155. The total historical bootstrap requirement is therefore **1 table + 7 indexes + 3 named unique constraints = 11 objects**, of which **10 are additional objects beyond the table**. An earlier plan wording of “nine more” was incorrect and has been removed.

A plain `alembic upgrade 0005_fixed_quotes` from an empty database would fail at the first missing legacy object. This bootstrap recreates exactly those object shells in the disposable database only, lets the real `b96aae0ed4c8` consume (drop) them, then continues through `0004` and `0005` normally.

---

## 2. Safety boundary

Allowed:

- The container `rupaywala-pg18-validation`.
- The database `rupaywala_validation`.
- Process-environment overrides for `DATABASE_URL` and required test-only non-secret values.
- Creating throwaway objects that the real migration drops immediately afterwards.

Forbidden:

- Connecting to production, any production host/port/role, or using production data, snapshots, or credentials.
- Editing any file under `alembic/versions/`, `alembic/env.py`, `alembic.ini`, application code, `.env`, or the original Stage 5.6C SQL file.
- Stamping past `b96aae0ed4c8`.
- Using `Base.metadata.create_all()` followed by `stamp` as a substitute for the real revision chain.
- Modifying or skipping any historical migration operation.
- Claiming this plan was executed or tested.

---

## 3. Exact disposable connection details

`SOURCE VERIFIED` from the task environment and `alembic/env.py`:

| Item | Value |
|---|---|
| Docker container | `rupaywala-pg18-validation` |
| PostgreSQL image | `postgres:18.1` |
| Database | `rupaywala_validation` |
| Login role used for bootstrap | `validation_admin` |
| Client host | `127.0.0.1` |
| Client/host port | `55432` |
| Container PostgreSQL port | `5432` |
| Server version expected | PostgreSQL `18.1` |

### 3.1 Internal versus external port

- PostgreSQL's `inet_server_port()` reports the **internal listener port**, which is `5432` inside the container.
- It cannot report the external Docker mapping `127.0.0.1:55432`.
- Therefore any SQL-side port gate must expect `5432`.
- The client mapping must be verified separately from the client connection metadata.

`PROPOSED` client-side verification, to be performed in a future approved stage:

```text
psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=validation_admin" -c '\conninfo'
```

Expected evidence from `\conninfo`: host `127.0.0.1`, port `55432`, database `rupaywala_validation`, user `validation_admin`. No password is included in this instruction.

### 3.2 Environment without file edits

`SOURCE VERIFIED`: `alembic/env.py` imports `app.config`, and `app/config.py` calls `load_dotenv()`. Python-dotenv does not override real environment variables by default, so a process-level `DATABASE_URL` wins without reading or changing `.env`.

`PROPOSED` process-environment shape (no secret values shown or generated):

```text
DATABASE_URL=postgresql+psycopg2://validation_admin@127.0.0.1:55432/rupaywala_validation
```

Other import-time required environment values (including the JWT secret key and UPI identifier) must be supplied out of band as test-only values. Their names are noted here only so the operator can provide them; no values are shown, generated, printed, or committed. Do not source production values.

### 3.3 Role-specific DSNs

`SOURCE VERIFIED`: `alembic/env.py:13,77` uses `DATABASE_URL` directly, and `app/config.py:56` reads the same variable for both Alembic and application startup. The DSN must therefore be overridden per process:

| Process | Login role | Purpose |
|---|---|---|
| Bootstrap psql / DBA SQL | `validation_admin` | Reach `0005_fixed_quotes`, then run the corrected SQL. Bootstrap-only. |
| Alembic | `rupaywala_migrator` | Run revisions with the owner-startup strategy in §10. |
| Application runtime | `rupaywala_app` | Normal application access only. |

The repository `.env` DSN points at a non-disposable database. A process-level `DATABASE_URL` override is mandatory for every disposable step. Never place a password in a DSN literal, shell command, or this plan; use a protected local pgpass file or the psql interactive prompt.

---

## 4. Exact bootstrap sequence (proposed order only)

### Step 1 — Preflight

Run in the disposable database only:

```sql
SELECT current_database(),
       current_user,
       session_user,
       current_setting('server_version'),
       inet_server_addr()::text AS server_ip,
       inet_server_port() AS internal_server_port;
```

Gates:

- `current_database() = 'rupaywala_validation'`
- `current_user = 'validation_admin'`
- `session_user = 'validation_admin'`
- `split_part(current_setting('server_version'), ' ', 1) = '18.1'`
- `current_setting('server_version_num') = '180001'`
- `inet_server_port() = 5432`
- `inet_server_addr() IS NOT NULL`
- Client-side `\conninfo` confirms `127.0.0.1:55432` separately.

Refuse to continue if any gate fails. Do not claim the external port from `inet_server_port()`.

### Step 2 — Build to the last fresh-safe revision

```text
alembic upgrade 0003_visit_credits_lifecycle
```

`SOURCE VERIFIED`: `0003` is explicitly written to be safe on a fresh install (`_create_index`/helpers skip existing objects and legacy data rewrites are conditional). Do not go directly to `0005`.

Confirm:

```sql
SELECT version_num FROM public.alembic_version;
-- expected: 0003_visit_credits_lifecycle
```

### Step 3 — Apply the disposable-only legacy-state bootstrap

Apply the following DDL **only** to `rupaywala_validation`, after revision `0003` and before `b96aae0ed4c8`:

```sql
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

`STATICALLY VALIDATED`: all referenced columns exist in the fresh chain at revision `0003` (`payments.txn_id`, `payments.utr_number`, `users.phone_number`, `policies.user_id`, `service_requests.policy_id/user_id`, `user_subscriptions.user_id`). No rows are inserted, copied, or updated by this bootstrap.

### Step 4 — Verify the bootstrap objects exist

```sql
SELECT to_regclass('public.activity_logs') IS NOT NULL AS activity_logs_ok;

SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'idx_payments_txn_id', 'idx_payments_utr', 'idx_policies_user',
      'idx_requests_policy', 'idx_requests_user', 'idx_subscription_user',
      'idx_users_phone'
  )
ORDER BY indexname;
-- expected: 7 rows

SELECT conname FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conname IN (
      'payments_txn_id_key', 'payments_utr_number_key', 'users_phone_number_key'
  )
ORDER BY conname;
-- expected: 3 rows
```

### Step 5 — Let the real chain finish

```text
alembic upgrade 0005_fixed_quotes
```

This runs `b96aae0ed4c8`, `0004_subscription_entitlements`, and `0005_fixed_quotes` unchanged. No historical migration is edited, skipped, or stamped over.

### Step 6 — Verify the resulting 0005 schema

```sql
SELECT version_num FROM public.alembic_version;
-- expected: 0005_fixed_quotes

SELECT to_regclass('public.activity_logs') IS NULL AS activity_logs_absent;
-- expected: true

SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'idx_payments_txn_id', 'idx_payments_utr', 'idx_policies_user',
      'idx_requests_policy', 'idx_requests_user', 'idx_subscription_user',
      'idx_users_phone'
  );
-- expected: 0 rows

SELECT conname FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conname IN (
      'payments_txn_id_key', 'payments_utr_number_key', 'users_phone_number_key'
  );
-- expected: 0 rows

SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
-- must include all 18 runtime grant tables plus family_members and alembic_version;
-- must NOT include activity_logs.

SELECT pg_get_serial_sequence('public.subscription_plans', 'id');
-- expected: public.subscription_plans_id_seq
```

Only after these checks pass may `stage_5_6d_postgresql_roles_corrected.sql` be considered for a separately approved execution stage.

---

## 5. Exact `b96aae0ed4c8` legacy object inventory

`SOURCE VERIFIED` line by line from `alembic/versions/b96aae0ed4c8_add_email_otp_support.py`. No additional object is dropped by the migration; the list below is exhaustive for the drop operations in `upgrade()`.

| Object | Object type | Source migration operation | Required before migration | Expected after migration |
|---|---|---|---|---|
| `public.activity_logs` | Table | `op.drop_table('activity_logs')` line 21 | Present | Absent |
| `public.idx_payments_txn_id` | Index | `op.drop_index(op.f('idx_payments_txn_id'), table_name='payments')` line 76 | Present | Absent |
| `public.idx_payments_utr` | Index | `op.drop_index(op.f('idx_payments_utr'), table_name='payments')` line 77 | Present | Absent |
| `public.payments_txn_id_key` | Unique constraint | `op.drop_constraint(..., 'payments', type_='unique')` line 78 | Present | Absent |
| `public.payments_utr_number_key` | Unique constraint | `op.drop_constraint(..., 'payments', type_='unique')` line 79 | Present | Absent |
| `public.idx_policies_user` | Index | `op.drop_index(op.f('idx_policies_user'), table_name='policies')` line 88 | Present | Absent |
| `public.idx_requests_policy` | Index | `op.drop_index(op.f('idx_requests_policy'), table_name='service_requests')` line 101 | Present | Absent |
| `public.idx_requests_user` | Index | `op.drop_index(op.f('idx_requests_user'), table_name='service_requests')` line 102 | Present | Absent |
| `public.idx_subscription_user` | Index | `op.drop_index(op.f('idx_subscription_user'), table_name='user_subscriptions')` line 131 | Present | Absent |
| `public.idx_users_phone` | Index | `op.drop_index(op.f('idx_users_phone'), table_name='users')` line 154 | Present | Absent |
| `public.users_phone_number_key` | Unique constraint | `op.drop_constraint(op.f('users_phone_number_key'), 'users', type_='unique')` line 155 | Present | Absent |

Totals: **1 table + 7 indexes + 3 unique constraints = 11 objects**; **10 additional objects beyond the legacy table**.

`SOURCE VERIFIED`: `downgrade()` would recreate these objects, but downgrade is not part of this plan. The bootstrap plan only prepares the disposable starting state for the real `upgrade()`.

---

## 6. Why stamping is rejected

| Shortcut | Why it is not acceptable here |
|---|---|
| `alembic stamp b96aae0ed4c8` after `0003` | Skips the real b96 changes: `otp_verifications.email`, `users.email_verified`, `users.phone_verified`, enum labels `email_signup`, `email_login`, `email_otp`, and removal of all legacy indexes/constraints. Not revision-faithful. |
| `create_all()` + `stamp 0005` | Builds a model-shaped schema and bypasses revision history. It may also include later-shape columns and is not representative of `0005_fixed_quotes`. |
| Patch `b96` or add a “fix” migration | Explicitly forbidden; changes production migration history. |
| Skip the legacy drops | Leaves objects the real migration expects to consume, so the chain fails or is not executed as authored. |

---

## 7. PostgreSQL 18.1 compatibility notes for the bootstrap

- `SOURCE VERIFIED`: `alembic/env.py` sets `transaction_per_migration=True`. This matters because `b96aae0ed4c8` adds enum values with `ALTER TYPE ... ADD VALUE IF NOT EXISTS`; new labels cannot be used until their adding transaction commits.
- `SOURCE VERIFIED`: the two `ADD VALUE IF NOT EXISTS` calls are wrapped in broad `try/except` blocks. This is a pre-existing source concern; do not modify the migration during this task.
- `SOURCE VERIFIED`: `b96aae0ed4c8.downgrade()` uses `postgresql_nulls_not_distinct=False`, implying PostgreSQL 15+; 18.1 satisfies that floor.
- `STATICALLY VALIDATED`: fresh PostgreSQL 18 normally does not grant `CREATE` on `public` to `PUBLIC`. The corrected SQL asserts `PUBLIC` schema `USAGE=true` and `CREATE=false`, and does not silently revoke either.
- `STATICALLY VALIDATED`: PostgreSQL default `PUBLIC` database privileges include `CONNECT` and `TEMP`; `TEMP` is not granted by this artifact and is asserted as a default-derived effective privilege for the app role.
- `STATICALLY VALIDATED`: the corrected SQL now includes PG18 table `REFERENCES` and `MAINTAIN` in both the evidence queries and strict zero-privilege assertions for `family_members` and `alembic_version`.
- `STATICALLY VALIDATED`: custom-type `USAGE`, routine `EXECUTE`, `PUBLIC` object-ACL, schema-owner and default-ACL provenance are asserted in SQL §7.10 without adding broad grants.
- `UNVERIFIED`: actual parser acceptance, catalog states, interactive password provisioning, and migration behaviour remain pending until a future approved execution stage.

---

## 8. Consistency with the corrected SQL artifact

| Check | Bootstrap plan | Corrected SQL artifact | Status |
|---|---|---|---|
| Database | `rupaywala_validation` | Same hard gate | `STATICALLY VALIDATED` |
| Bootstrap user | `validation_admin` | `current_user`/`session_user` hard gate | `STATICALLY VALIDATED` |
| Client mapping | `127.0.0.1:55432` | `\conninfo` instruction; no server-side claim | `STATICALLY VALIDATED` |
| Internal port | `5432` | `inet_server_port() = 5432` | `STATICALLY VALIDATED` |
| Required revision before grants | `0005_fixed_quotes` | Strict gate in §0 and §6 | `STATICALLY VALIDATED` |
| Legacy object count | 1 table + 7 indexes + 3 constraints | Referenced by revision gate, not recreated by SQL | `STATICALLY VALIDATED` |
| Stamping / `create_all()` | Prohibited | Not used | `STATICALLY VALIDATED` |
| Historical migration edits | Prohibited | Not used | `STATICALLY VALIDATED` |
| Exact server version | `18.1`, not `18.1x` | Exact `split_part(server_version,' ',1)='18.1'` gate | `STATICALLY VALIDATED` |
| Role DSNs | bootstrap/migrator/app separated | §3.3 and §10 | `STATICALLY VALIDATED` |
| PUBLIC defaults | not broadened or revoked | asserted in SQL §7.2/§7.10 | `STATICALLY VALIDATED` |
| PG18 `REFERENCES`/`MAINTAIN` | must be absent for app | strict assertions in SQL §7.5/§7.9 | `STATICALLY VALIDATED` |
| Alembic owner startup | required, not psql-only | `PGOPTIONS` strategy in §10 | `STATICALLY VALIDATED` / runtime `UNVERIFIED` |

---

## 9. Interactive role and password workflow

`PROPOSED` — no role or password operation has been performed.

1. Use an interactive terminal; psql `\password` prompts require a TTY. Do not pipe the SQL file from a heredoc, redirect stdin, or place a password in `-c`, an environment variable, or shell history.
2. Start DBA psql without embedding a password:
   ```text
   psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=validation_admin" -W
   ```
3. Confirm `\conninfo` and §1 gates, then run:
   ```text
   \i database/security/stage_5_6d_postgresql_roles_corrected.sql
   ```
4. `\password` is reached only for roles that do not yet exist. Enter each new login password twice at the prompt. Existing roles are not prompted and their passwords are never reset.
5. If `rupaywala_migrator` or `rupaywala_app` already exists without a password, the preflight aborts by design. Provision that password separately with an explicitly approved `\password <role>`; do not weaken the gate.
6. Confirm configuration without ever displaying credentials: report `rolcanlogin`, `rolinherit`, restricted attributes, `rolpassword IS NOT NULL AS has_password`, membership rows, and `has_*_privilege` results. Never select password hashes or password values.
7. The SQL adds `rupaywala_owner` membership to `rupaywala_migrator` idempotently. Existing role attributes and passwords remain unchanged; `rupaywala_app` gains no membership.

---

## 10. Required Alembic ownership runbook

`SOURCE VERIFIED`: `alembic/env.py:13,77` creates the engine directly from `DATABASE_URL` with `NullPool`; `alembic.ini:5-7` has no URL or role option; `alembic/env.py:73-82` issues no `SET ROLE`. Login as `rupaywala_migrator` therefore starts with `current_user=rupaywala_migrator`. `INHERIT` membership allows the DDL to pass ownership checks, but new objects would be recorded as migrator-owned.

`PROPOSED` concrete strategy — libpq startup role on the actual Alembic process:

```text
$env:DATABASE_URL = 'postgresql+psycopg2://rupaywala_migrator@127.0.0.1:55432/rupaywala_validation'
$env:PGOPTIONS = '-c role=rupaywala_owner'
psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=rupaywala_migrator" -c "SELECT current_user, session_user;"
# expected: current_user=rupaywala_owner; session_user=rupaywala_migrator
alembic upgrade 0006_stage5_security_remediation
Remove-Item Env:PGOPTIONS
```

- Use the identical environment for the identity probe and Alembic. A separate psql `SET ROLE` demonstration does not prove Alembic's connection state.
- `PGOPTIONS` is chosen because it reaches every libpq connection created by `env.py:77` without editing runtime code or historical migrations. URL `?options=...` is a narrower alternative; `connect_args` is rejected because it would require editing `env.py`.
- Passwords must come from a protected pgpass/secret store, never a shell literal.
- Offline `alembic --sql` cannot validate identity because `env.py:60-70` opens no connection.

Post-0006 verification is defined in SQL §10: revision `0006_stage5_security_remediation`, schema/relation/type owner `rupaywala_owner`, three expected indexes and one unique constraint, two expected columns, no migrator- or app-owned objects, and unchanged default ACLs. Catalog assertions are separate from future behavioral tests; neither has been executed.

---

## Final status

`BOOTSTRAP PLAN PREPARED — NOT EXECUTED`

Production migration history is unchanged. No production data, credentials, or connection instructions are used. No Stage 6 work is included. Execution remains `PROPOSED` and `UNVERIFIED` pending explicit approval, interactive first-run password provisioning, and the successful completion of every gate above. The `PGOPTIONS` ownership strategy is concretely documented but its live identity effect remains `UNVERIFIED`; the final readiness decision is therefore `BLOCKED`.
