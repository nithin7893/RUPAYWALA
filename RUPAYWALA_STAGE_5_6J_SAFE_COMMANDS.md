# RUPAYWALA Stage 5.6J Safe Commands (Prepared — NOT Executed)

## Hard Safety Rules

- **DO NOT EXECUTE** any command in this document without explicit authorization.
- **DO NOT** run Alembic migrations against `rupaywala_ori`.
- **DO NOT** create/drop/restore databases without explicit authorization.
- **DO NOT** modify PostgreSQL roles/privileges.
- **DO NOT** change `.env` or `DATABASE_URL`.
- **DO NOT** print passwords, connection strings, or secrets.
- **DO NOT** delete or overwrite existing backups.
- **DO NOT** use Alembic stamping to bypass migrations.
- Before any migration/restore/create step, confirm target database is the approved isolated dev DB and **not** `rupaywala_ori`.

## 1) Backup: `rupaywala_ori` (prepared, not executed)

### Preconditions

- PostgreSQL 18 tools available at `C:\Program Files\PostgreSQL\18\bin\` (verified present: `pg_dump`, `pg_restore`, `psql` v18.1).
- Backup directory exists: `C:\RUPAAY_WALA\rupaywala_backend\database_backups\` (existing files must not be overwritten).
- Use secure authentication: prefer `.pgpass` or set `PGPASSWORD` only in the current PowerShell session from a secure prompt. **Never echo, log, or commit the password.**

### PowerShell (prepared)

```powershell
# === PREPARED - DO NOT EXECUTE WITHOUT EXPLICIT AUTHORIZATION ===
# Run in a fresh PowerShell session. Do not paste secrets into command history.

$ErrorActionPreference = 'Stop'

# Tool paths (PostgreSQL 18.1)
$pgDump    = 'C:\Program Files\PostgreSQL\18\bin\pg_dump.exe'
$pgRestore = 'C:\Program Files\PostgreSQL\18\bin\pg_restore.exe'

# Target (original DB - backup source only; never a migration/restore target)
$env:PGHOST = 'localhost'
$env:PGPORT = '5432'
$env:PGUSER = 'postgres'
$env:PGDATABASE = 'rupaywala_ori'

# Secure password: set PGPASSWORD in-session only if .pgpass is not configured.
# Do NOT type password in a command that gets logged; do NOT echo it.
# Example secure prompt (uncomment only when authorized):
# $secure = Read-Host "Enter PostgreSQL password for $env:PGUSER" -AsSecureString
# $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
# try { $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
# finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

# Timestamped custom-format backup file (no overwrite)
$backupDir = 'C:\RUPAAY_WALA\rupaywala_backend\database_backups'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = Join-Path $backupDir "rupaywala_ori_pre_56j_$ts.dump"

if (Test-Path -LiteralPath $backupFile) {
    throw "Refusing to overwrite existing backup file: $backupFile"
}

# Create custom-format dump
& $pgDump -Fc -Z 6 --file $backupFile
if ($LASTEXITCODE -ne 0) {
    throw "pg_dump failed with exit code $LASTEXITCODE. Do not use backup file."
}

# Verify dump is readable
& $pgRestore --list $backupFile | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "pg_restore --list verification failed with exit code $LASTEXITCODE."
}

# Record evidence
$item = Get-Item -LiteralPath $backupFile
[pscustomobject]@{
    BackupFile = $item.FullName
    SizeBytes  = $item.Length
    LastWriteTime = $item.LastWriteTime.ToString('o')
    PgDumpVersion = (& $pgDump --version)
    PgRestoreListExitCode = 0
} | Format-List

# Cleanup sensitive session var if set
if (Test-Path Env:\PGPASSWORD) { Remove-Item Env:\PGPASSWORD }
```

### Backup Notes

- `-Fc` = custom format (suitable for `pg_restore`). `-Z 6` = moderate compression.
- Do **not** add `--clean --if-exists` to restore over original. Any restore must target an approved isolated dev DB only.
- Consider `--no-owner --no-privileges` only for restore into a different-role dev environment; record the chosen option. For a faithful pre-migration backup, default full dump is acceptable.
- After backup, store hash/checksum in a separate record if required by ops policy.

## 2) Isolated Development Database Plan (prepared, not executed)

### Proposed Dev DB Name

- Proposal: `rupaywala_dev_56j` (or another explicitly approved name).
- Must not be `rupaywala_ori`, `rupaywala_validation`, or `rupaywala_role_validation` unless explicitly authorized for a different purpose.

### Create Empty Dev DB (DO NOT EXECUTE without authorization)

```powershell
# === PREPARED - DO NOT EXECUTE WITHOUT EXPLICIT AUTHORIZATION ===
$ErrorActionPreference = 'Stop'
$psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
$env:PGHOST='localhost'; $env:PGPORT='5432'; $env:PGUSER='postgres'; $env:PGDATABASE='postgres'
# Set PGPASSWORD securely in-session if needed; do not echo.

# Safety: confirm target name is not original
$devDb = 'rupaywala_dev_56j'  # approved name only
if ($devDb -eq 'rupaywala_ori') { throw 'Refusing: target is original DB' }

& $psql -v ON_ERROR_STOP=1 -c "SELECT current_database(), current_user;"
# Create database only after explicit authorization:
# & $psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE $devDb;"
```

### Restore Verified Backup Into Dev DB (DO NOT EXECUTE without authorization)

```powershell
# === PREPARED - DO NOT EXECUTE WITHOUT EXPLICIT AUTHORIZATION ===
$ErrorActionPreference = 'Stop'
$pgRestore = 'C:\Program Files\PostgreSQL\18\bin\pg_restore.exe'
$backupFile = 'C:\RUPAAY_WALA\rupaywala_backend\database_backups\<VERIFIED_RUPAYWALA_ORI_BACKUP>.dump'
$devDb = 'rupaywala_dev_56j'

if ($devDb -eq 'rupaywala_ori') { throw 'Refusing: restore target is original DB' }
if (-not (Test-Path -LiteralPath $backupFile)) { throw "Backup file not found: $backupFile" }

# Verify backup readability before restore
& $pgRestore --list $backupFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Backup verification failed; do not restore.' }

# Restore target must be approved dev DB only
$env:PGHOST='localhost'; $env:PGPORT='5432'; $env:PGUSER='postgres'
# Set PGPASSWORD securely in-session if needed; do not echo.
& $pgRestore --dbname $devDb --no-owner --no-privileges --exit-on-error $backupFile
if ($LASTEXITCODE -ne 0) { throw "pg_restore failed with exit code $LASTEXITCODE" }
```

### Separate Application Connection Configuration (DO NOT modify .env)

- **Do not edit** `C:\RUPAAY_WALA\rupaywala_backend\.env`.
- For migration testing, use a **process-only environment variable override** in the same PowerShell session, pointing `DATABASE_URL` to the approved dev DB. Do not print the value.
- Alternatively, use an explicitly selected untracked env file only if the workflow supports it; ensure it is never committed and never points to `rupaywala_ori`.
- Before running any Alembic/app command, run the read-only active DB check below.

## 3) Pre-Migration Read-Only Checks (safe to run only as read-only queries; still require care)

### Confirm Active Target DB (read-only)

```powershell
# === READ-ONLY CHECK - run only after setting process env to approved dev DB ===
# Do not print DATABASE_URL. Do not modify .env.
$ErrorActionPreference = 'Stop'
.\venv\Scripts\python.exe -c "import json; from sqlalchemy import text; from app.database import engine; 
print(json.dumps({'db':engine.url.database,'host':engine.url.host,'port':engine.url.port,'user':engine.url.username}, default=str));
with engine.connect() as c: print(json.dumps({'current_database':c.execute(text('SELECT current_database()')).scalar(),'current_user':c.execute(text('SELECT current_user')).scalar(),'alembic': [r[0] for r in c.execute(text('SELECT version_num FROM alembic_version')).fetchall()]}, default=str))"
```

**Stop immediately if `current_database` is `rupaywala_ori`.**

### 0006 Duplicate Pre-Check (read-only, on approved dev DB only)

```sql
-- READ-ONLY. Run on approved isolated dev DB only after confirming current_database().
-- 0006 aborts if these return rows.
SELECT user_id, payment_type, idempotency_key, COUNT(*) AS duplicates
FROM payments
WHERE idempotency_key IS NOT NULL
  AND status IN ('pending', 'pending_verification')
GROUP BY user_id, payment_type, idempotency_key
HAVING COUNT(*) > 1
ORDER BY duplicates DESC, user_id, payment_type, idempotency_key;

SELECT related_request_id, COUNT(*) AS duplicates
FROM payments
WHERE payment_type = 'extra_charge'
  AND related_request_id IS NOT NULL
  AND status IN ('pending', 'pending_verification')
GROUP BY related_request_id
HAVING COUNT(*) > 1
ORDER BY duplicates DESC, related_request_id;
```

If either query returns rows, **do not run 0006**. Resolve duplicates only with explicit authorization and a reviewed data-remediation plan.

## 4) Migration Test Plan (isolated dev DB only, DO NOT EXECUTE without authorization)

### Preconditions

- Verified backup of `rupaywala_ori` exists and `pg_restore --list` passed.
- Approved dev DB created and restored from verified backup.
- Process `DATABASE_URL` points to approved dev DB only; `.env` unchanged.
- Read-only active DB check confirms `current_database != 'rupaywala_ori'`.
- 0006 duplicate pre-check returns no rows.
- Current Alembic revision on dev DB is `0005_fixed_quotes` (expected after restore from current original backup).

### Sequential Migration Commands (prepared)

```powershell
# === PREPARED - DO NOT EXECUTE WITHOUT EXPLICIT AUTHORIZATION ===
# Must run in repo root with process env DATABASE_URL pointing to approved dev DB only.
$ErrorActionPreference = 'Stop'
Set-Location C:\RUPAAY_WALA\rupaywala_backend

# Confirm target DB first (read-only). STOP if rupaywala_ori.
.\venv\Scripts\python.exe -c "from sqlalchemy import text; from app.database import engine; 
with engine.connect() as c: 
    db=c.execute(text('SELECT current_database()')).scalar(); print('current_database=',db);
    assert db != 'rupaywala_ori', 'REFUSING: original DB'"

# Step 1: 0006
.\venv\Scripts\alembic.exe upgrade 0006_stage5_security_remediation
if ($LASTEXITCODE -ne 0) { throw '0006 failed; stop and investigate' }

# Step 2: 0007
.\venv\Scripts\alembic.exe upgrade 0007_user_token_version
if ($LASTEXITCODE -ne 0) { throw '0007 failed; stop and investigate' }

# Step 3: 0008
.\venv\Scripts\alembic.exe upgrade 0008_private_document_storage
if ($LASTEXITCODE -ne 0) { throw '0008 failed; stop and investigate' }
```

## 5) Verification Queries (read-only, approved dev DB only)

```sql
-- READ-ONLY verification. Run only on approved dev DB after confirming current_database().
SELECT current_database(), current_user, version();

-- Alembic revision
SELECT version_num FROM alembic_version;

-- 0007: users.token_version
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='users' AND column_name='token_version';

-- 0006: service_quotes.signature_version
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='service_quotes' AND column_name='signature_version';

-- 0006: service_requests.quote_ref
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public' AND table_name='service_requests' AND column_name='quote_ref';

-- 0006: unique constraint/index presence
SELECT conname, contype
FROM pg_constraint
WHERE conname = 'uq_service_requests_quote_ref';

SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND indexname IN (
  'uq_payments_user_type_idem_open',
  'uq_payments_open_extra_charge_request'
);

-- 0008: enum
SELECT t.typname, e.enumlabel
FROM pg_type t
JOIN pg_enum e ON t.oid=e.enumtypid
WHERE t.typname='document_scan_status'
ORDER BY e.enumsortorder;

-- 0008: tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema='public' AND table_name IN ('document_records','document_audit_logs')
ORDER BY table_name;

-- 0008: document_records columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='document_records'
ORDER BY ordinal_position;

-- 0008: document_audit_logs columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='document_audit_logs'
ORDER BY ordinal_position;

-- 0008: service_requests.proof_document_id
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public' AND table_name='service_requests' AND column_name='proof_document_id';

-- 0008: indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND (
  tablename='document_records' OR tablename='document_audit_logs'
  OR indexname='ix_service_requests_proof_document_id'
)
ORDER BY tablename, indexname;

-- 0008: FK
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conname='fk_service_requests_proof_document_id';
```

### Expected Verification Outcomes (after successful 0006-0008 on dev DB)

- `alembic_version.version_num = '0008_private_document_storage'`
- `users.token_version` exists: integer, NOT NULL, default 0.
- `service_quotes.signature_version` exists: integer, NOT NULL, default 1.
- `service_requests.quote_ref` exists: varchar(64), nullable; unique constraint `uq_service_requests_quote_ref` present.
- Partial unique indexes `uq_payments_user_type_idem_open` and `uq_payments_open_extra_charge_request` present.
- `document_scan_status` enum exists with `PENDING,CLEAN,INFECTED,FAILED`.
- `document_records` and `document_audit_logs` tables exist with expected columns/indexes.
- `service_requests.proof_document_id` exists with FK `fk_service_requests_proof_document_id` to `document_records(id)` ON DELETE SET NULL.

## 6) Post-Migration App Smoke (isolated dev DB only, authorized)

After schema verification passes on the approved dev DB only:

- Run targeted tests that do not touch original DB and are compatible with the disposable dev/test strategy used by the project. **Do not use destructive tests against `rupaywala_ori`.**
- Candidate read-only/app smoke: start API against dev DB and verify `GET /health`, then test login path on a test user in dev DB only.
- Any test using `tests/conftest.py` must be reviewed for DB create/drop behavior before execution; conftest creates/drops `rupaywala_test` schema/DB patterns - run only when safe and authorized.

## 7) Original DB Migration (future, NOT authorized now)

Only after dev DB validation passes and explicit authorization is given:

1. Take fresh verified backup of `rupaywala_ori` (same backup procedure; new timestamped file).
2. Confirm backup readability and record size/timestamp.
3. Confirm maintenance window and rollback plan (downgrade is destructive for 0008-created data; prefer restore-from-backup rollback strategy).
4. Confirm `current_database()` is the intended target before every command.
5. Apply 0006->0007->0008 sequentially, verify after each step.
6. Run read-only verification queries and authorized smoke tests.

**No original DB migration is authorized by this document.**