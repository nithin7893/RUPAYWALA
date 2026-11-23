# RUPAYWALA BACKEND VERIFICATION REPORT

**Date:** 2026-11-21  
**Mode:** Safe/non-destructive checks only. No migrations, no schema drops, no production/demo DB modification.

## 1. Checks Executed

| Check | Command | Result | Classification | Evidence / Notes |
|---|---|---|---|---|
| Python environment | `.\venv\Scripts\python.exe --version` | Python 3.12.6 | PASS | venv Python present. |
| Pip/dependency tool | `.\venv\Scripts\python.exe -m pip --version` | pip 26.0.1 | PASS | Present in venv. |
| Dependency consistency (full) | Not run | NOT TESTED | NOT TESTED | `pip check` not executed; could be run safely but not performed. |
| Compile check | `.\venv\Scripts\python.exe -m compileall app -q` | No errors | PASS | Exit 0, no output. |
| FastAPI app import (isolated dummy env) | `TESTING=1 DATABASE_URL=sqlite+pysqlite:///:memory: JWT_SECRET_KEY=test QUOTE_SIGNING_SECRET=test UPI_ID=test@upi python -c "from app.main import app; print(type(app).__name__)"` | `FastAPI` | PASS (isolated smoke) | Import succeeded; used dummy env vars, no configured DB touched. |
| App startup / health (isolated in-process) | TestClient GET `/health` with same dummy env/sqlite memory | HTTP 200, `{"status":"degraded","database":"unavailable","integrations":...}` | PASS (isolated smoke, limited) | Endpoint responded; DB unavailable in sqlite memory without tables; SQLAlchemy traceback logged internally but request handled. Not a real DB startup verification. |
| DB connectivity to configured DB | Read-only `SELECT version_num FROM alembic_version` / `SELECT version()` / `SELECT current_database()` | Connected, returned metadata | PASS (read-only) | DB `rupaywala_ori`, Postgres 18.1, alembic `0005_fixed_quotes`. No writes performed. |
| Backend startup against configured DB | Not run | NOT TESTED | NOT TESTED | Would connect to non-disposable-named DB; startup behavior not verified. |
| Health endpoint against configured DB | Not run | NOT TESTED | NOT TESTED | Requires running server. |
| Auth endpoints runtime | Not run | NOT TESTED | NOT TESTED | Requires isolated DB. |
| Customer/Admin/Field-member/Quote/Payment/Upload API runtime | Not run | NOT TESTED | NOT TESTED | Requires isolated DB and seeded data. |
| Pytest collection/execution | Not run | BLOCKED | BLOCKED | `tests/conftest.py` imports app DB, sets test DATABASE_URL, creates `rupaywala_test` DB if missing, and fixtures drop/create schema. Not safe against non-disposable environment. |

## 2. Static Verification (Not Runtime)

| Area | Classification | Evidence |
|---|---|---|
| Auth routes/endpoints present | STATICALLY VERIFIED | `app/routes/auth_routes.py` includes register/login/OTP/google/forgot/logout/me/username/change-password. |
| Fixed quote endpoints present | STATICALLY VERIFIED | `app/routes/service_routes.py` has `/service/quote` POST/GET/cancel and request creation accepts `quote_id`. |
| Payment endpoints present | STATICALLY VERIFIED | `app/routes/payment_routes.py` has create/submit/status/my-payments/admin verify/list/summary. |
| Upload handling present | STATICALLY VERIFIED | `app/utils/upload_service.py`; field member complete endpoint accepts proof; `/uploads` mounted in `main.py`. |
| Role guards present | STATICALLY VERIFIED | `app/utils/dependencies.py` role dependencies; route-level guards used. |

## 3. Blockers

- **B-001:** Configured DB `rupaywala_ori` is not confirmed disposable; 0006/0007 pending. Cannot safely run startup/migrations/DB-dependent tests against it.
- **B-002:** `tests/conftest.py` is DB-destructive by design for `rupaywala_test` schema; no disposable test DB authorized.
- **B-003:** No isolated demo DB/seed data for end-to-end API verification.

## 4. Safe Next Commands (Authorized Isolated Demo DB Only)

```powershell
# Set demo env vars in process/session only (do not print secrets)
$env:DATABASE_URL="postgresql+psycopg://USER:PASS@HOST:5432/rupaywala_demo"
$env:JWT_SECRET_KEY="..."
$env:QUOTE_SIGNING_SECRET="..."
$env:UPI_ID="..."
.\venv\Scripts\python.exe -m alembic upgrade head  # authorized demo DB only
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
# In another shell:
Invoke-RestMethod http://127.0.0.1:8000/health
```