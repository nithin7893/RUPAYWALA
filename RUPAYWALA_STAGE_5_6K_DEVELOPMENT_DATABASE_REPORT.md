# RUPAYWALA Stage 5.6K Development Database Report

## Status

- **Part A:** Backup of `rupaywala_ori` created and verified - PASS (see `RUPAYWALA_STAGE_5_6K_BACKUP_VERIFICATION_REPORT.md`).
- **Part B:** **STOPPED** - `rupaywala_dev` already exists. No database created, dropped, restored, or overwritten.
- **Part C:** Source unchanged verified; existing `rupaywala_dev` inspected read-only; no restore performed.
- **Part D:** Safe development DATABASE_URL configuration prepared (instructions only; `.env` not changed).
- **No Alembic migrations executed.**

## Part B — Isolated Development Database (blocked)

| Check | Result |
|---|---|
| Target name | `rupaywala_dev` |
| Pre-create existence check (`pg_database`) | **EXISTS** (`rupaywala_dev_exists = true`) |
| Action taken | **None** - stopped per instruction. Did not drop, did not create, did not restore, did not overwrite. |

**Stop condition triggered:** `rupaywala_dev already exists`. Restore into this database was not performed to avoid overwriting existing data.

## Part C — Verification / Read-Only Inspection

### Source database (`rupaywala_ori`) after Part A

| Check | Result |
|---|---|
| `current_database()` | `rupaywala_ori` |
| Alembic revision | `0005_fixed_quotes` (unchanged) |
| `public.users.token_version` exists | No |
| Public base table count | 20 |
| Key row counts (read-only snapshot) | `users=28`, `alembic_version=1`, `service_requests=2`, `payments=9`, `service_quotes=0`, `user_subscriptions=2`, `subscription_plans=10` |

Source remains at its existing Alembic revision; no modification observed.

### Existing `rupaywala_dev` (read-only inspection; not restored by this stage)

| Check | Result |
|---|---|
| `current_database()` | `rupaywala_dev` |
| `current_user` | `postgres` |
| Alembic revision | `0003_visit_credits_lifecycle` |
| `public.users.token_version` exists | No |
| Public base table count | 18 |
| Key row counts (read-only snapshot) | `users=0`, `alembic_version=1`, `service_requests=0`, `payments=0`, `service_quotes=ERR:ProgrammingError` (table/query not compatible in this revision state), `user_subscriptions=0`, `subscription_plans=0` |

**Important:** Existing `rupaywala_dev` is **not** a restored copy of the verified `rupaywala_ori` backup. It is at an older Alembic revision (`0003_visit_credits_lifecycle`) with different schema/table state than source (`0005_fixed_quotes`, 20 tables). It must not be treated as the Stage 5.6K isolated migration-test copy.

## Part D — Safe Development DATABASE_URL Configuration (prepared, not applied)

### Constraints

- Do **not** change production/original `.env`.
- Do **not** automatically overwrite `.env`.
- Do **not** print credentials or connection strings.
- Ensure the application cannot accidentally connect to `rupaywala_ori` during subsequent development migration testing.

### Recommended safe switching procedure (authorized operator action only)

1. **Do not edit `.env` in place for migration testing.** Keep `.env` as the original configuration.
2. **Use a process-only environment override** in a dedicated PowerShell session for dev migration testing:
   - Set `DATABASE_URL` only in that session to point to the approved isolated dev database (not `rupaywala_ori`).
   - Set it from a secure secret source / prompt; do not hardcode the password in scripts or commit files.
   - Never echo the value.
3. **Or use an explicitly named untracked env file** (e.g., `.env.dev.local`) only if your workflow explicitly loads it. Ensure:
   - File is untracked/ignored and never committed.
   - It points to the approved dev DB name, not `rupaywala_ori`.
   - You do not overwrite `.env`.
4. **Mandatory pre-flight check before every Alembic/app command:**

   ```powershell
   # READ-ONLY pre-flight; run in the same session before any migration/app action.
   $env:PYTHONPATH='.'
   .\venv\Scripts\python.exe -c "from sqlalchemy import text; from app.database import engine; 
   with engine.connect() as c:
       db=c.execute(text('SELECT current_database()')).scalar(); rev=[r[0] for r in c.execute(text('SELECT version_num FROM alembic_version')).fetchall()];
       print({'current_database':db,'alembic':rev});
       assert db != 'rupaywala_ori', 'REFUSING: original DB'"
   ```

   Stop immediately if `current_database` is `rupaywala_ori`.
5. **Do not run Alembic against `rupaywala_ori`.** Do not stamp. Do not restore over any existing DB without authorization.
6. **After testing**, close the dedicated session or unset `DATABASE_URL` process override. Confirm default `.env` still points to intended configuration before normal use.

### Placeholder template (no credentials)

```text
DATABASE_URL=postgresql+psycopg2://<USER>:<PASSWORD>@<HOST>:<PORT>/rupaywala_dev
```

Replace placeholders securely at runtime; do not store real credentials in reports or committed files.

## Outcome

- Backup: **PASS** (verified).
- Isolated dev DB `rupaywala_dev` creation/restore: **NOT PERFORMED** because `rupaywala_dev` already exists.
- `rupaywala_ori`: **unchanged**. No Alembic migrations executed.