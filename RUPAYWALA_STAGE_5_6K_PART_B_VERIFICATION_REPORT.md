# RUPAYWALA Stage 5.6K Part B Verification Report

## Scope

Read-only verification after restoring verified backup `rupaywala_ori_stage56k_20261122_102506.dump` into newly created `rupaywala_dev_stage56k`. No migrations executed.

## 1) Target Database Verification

| Check | Result |
|---|---|
| Database name | `rupaywala_dev_stage56k` |
| PostgreSQL version | 18.1 |
| Current user | `postgres` |
| Alembic revision | `0005_fixed_quotes` |
| `public.users.token_version` exists | **No** (expected for 0005) |
| Public base table count | 20 |

## 2) Table Inventory (restored target)

| # | Table |
|---:|---|
| 1 | `alembic_version` |
| 2 | `branches` |
| 3 | `customer_profiles` |
| 4 | `distance_rate_config` |
| 5 | `family_members` |
| 6 | `field_members` |
| 7 | `notifications` |
| 8 | `otp_verifications` |
| 9 | `payments` |
| 10 | `policies` |
| 11 | `policy_members` |
| 12 | `request_assignments` |
| 13 | `service_quotes` |
| 14 | `service_requests` |
| 15 | `service_types` |
| 16 | `subscription_family_members` |
| 17 | `subscription_plans` |
| 18 | `user_subscriptions` |
| 19 | `users` |
| 20 | `visit_ledger` |

## 3) Row Count Comparison (practical key tables)

| Table | `rupaywala_ori` (source) | `rupaywala_dev_stage56k` (restored) | Match |
|---|---:|---:|---:|
| `users` | 28 | 28 | Yes |
| `alembic_version` | 1 | 1 | Yes |
| `service_requests` | 2 | 2 | Yes |
| `payments` | 9 | 9 | Yes |
| `service_quotes` | 0 | 0 | Yes |
| `user_subscriptions` | 2 | 2 | Yes |
| `subscription_plans` | 10 | 10 | Yes |

Comparison result: **alembic match=true, table count match=true, table list match=true, key row counts match=true**.

## 4) Source/Other DB Safety Checks

| Database | Alembic | Table count | Status |
|---|---|---:|---|
| `rupaywala_ori` | `0005_fixed_quotes` | 20 | Unchanged; not used as restore/migration target |
| `rupaywala_dev` | `0003_visit_credits_lifecycle` | 18 | Untouched; not used as restore/migration target |
| `rupaywala_dev_stage56k` | `0005_fixed_quotes` | 20 | New restored isolated dev copy |

## 5) Restore Errors

- Create DB exit code: 0
- pg_restore exit code: 0
- pg_restore stderr: empty
- Verification queries: successful read-only execution

**No restore errors observed.**

## 6) Configuration Preparation (safe switching)

Do not modify `.env`. Do not print credentials. Use a dedicated process-only session for dev migration testing.

### Process-only override pattern (template, no secrets)

```powershell
# Dedicated PowerShell session only. Do NOT modify .env. Do NOT echo secrets.
# Set DATABASE_URL to the approved isolated dev DB (rupaywala_dev_stage56k).
# Example template (replace placeholders securely; never print):
# $env:DATABASE_URL = "postgresql+psycopg2://<USER>:<PASSWORD>@<HOST>:<PORT>/rupaywala_dev_stage56k"

# Mandatory read-only pre-flight before any Alembic/app command:
$env:PYTHONPATH='.'
.\venv\Scripts\python.exe -c "from sqlalchemy import text; from app.database import engine; 
with engine.connect() as c:
    db=c.execute(text('SELECT current_database()')).scalar(); rev=[r[0] for r in c.execute(text('SELECT version_num FROM alembic_version')).fetchall()];
    print({'current_database':db,'alembic':rev});
    assert db == 'rupaywala_dev_stage56k', f'REFUSING: expected rupaywala_dev_stage56k, got {db}'"
```

Stop immediately if the pre-flight check does not report `rupaywala_dev_stage56k`.

To preserve original configuration: close the dedicated session or remove the process-only `DATABASE_URL` override before normal work. Keep `.env` unchanged.

## Outcome

**PASS.** `rupaywala_dev_stage56k` is a verified isolated restore of `rupaywala_ori` at Alembic `0005_fixed_quotes`, with `users.token_version` absent and matching key table counts. No migrations executed. No production readiness claimed.