# RUPAYWALA DEMO ENVIRONMENT ASSESSMENT

**Date:** 2026-11-21  
**Stage:** 1B - Isolated Demo Environment Preparation and End-to-End Verification  
**Mode:** Read-only inspection / safe non-destructive checks only. No secrets exposed. No DB modifications, no migrations, no installs.

## 1. Environment Inspection

| Component | Finding | Evidence |
|---|---|---|
| OS/Shell | Windows PowerShell environment | Commands executed via PowerShell. |
| Python | Python 3.12.6 | `.\venv\Scripts\python.exe --version` |
| Pip | pip 26.0.1 in venv | `.\venv\Scripts\python.exe -m pip --version` |
| Backend venv | Present at `venv/` | Workspace listing |
| FastAPI config | `app/config.py`, `.env` present; `.env.example` missing | File inspection; env keys listed by name only |
| Docker | Docker CLI 29.2.0 installed; daemon not reachable | `docker --version`; `docker ps -a` failed with dockerDesktopLinuxEngine pipe not found |
| PostgreSQL containers | Unknown - Docker daemon unavailable | Cannot inspect containers |
| PostgreSQL target (from env) | localhost:5432, db `rupaywala_ori`, user/password present, name does not suggest disposable | Safe parsed from `DATABASE_URL` without exposing credentials |
| Alembic | Configured (`alembic.ini`, `alembic/versions`) | Workspace inspection |
| Current DB Alembic revision | `0005_fixed_quotes` | Read-only query against configured DB: `SELECT version_num FROM alembic_version` |
| Pending migrations | `0006_stage5_security_remediation`, `0007_user_token_version` | Alembic heads/history vs DB current |
| Flutter SDK | Not found in PATH; no `flutter.bat` found under `C:\Users\NITHIN` search | `where.exe flutter`; `Get-ChildItem` search |
| Dart | Not found in PATH | `where.exe dart` |
| Android/web build config | Flutter project exists (`rupaywala_app/pubspec.yaml`, android/web dirs expected in project) - not fully build-verified | Workspace inspection; Flutter CLI unavailable |
| Test infrastructure | pytest configured (`pytest.ini`); `tests/conftest.py` creates/drops `rupaywala_test` schema and sets test DB env at import time | File inspection |

## 2. Environment Variable Names (values not exposed)

Present in `.env` (names only): `ACCESS_TOKEN_EXPIRE_MINUTES, DATABASE_URL, DISTANCE_RATE_PER_KM, FAST2SMS_API_KEY, FAST2SMS_SENDER_ID, FREE_DISTANCE_KM, JWT_ALGORITHM, JWT_SECRET_KEY, OLA_MAPS_API_KEY, OLA_MAPS_CACHE_TTL, OLA_MAPS_TIMEOUT, OPENROUTE_API_KEY, OTP_DEBUG_LOG, QR_EXPIRY_MINUTES, SMTP_HOST, SMTP_PASSWORD, SMTP_PORT, SMTP_SENDER_EMAIL, SMTP_SENDER_NAME, SMTP_USE_SSL, SMTP_USE_TLS, SMTP_USERNAME, UPI_ID`.

Notable: `OTP_DEBUG_LOG` appears twice in `.env` keys; `QUOTE_SIGNING_SECRET`/`GOOGLE_CLIENT_ID`/`GOOGLE_MAPS_API_KEY`/CORS vars not visible in `.env` key list (may be missing or set elsewhere) - requires confirmation before demo.

## 3. Demo Environment Readiness

| Requirement | Status | Notes |
|---|---|---|
| Separate demo database | **NOT CONFIRMED** | Configured DB is `rupaywala_ori` on localhost; name does not suggest demo/test. Treat as non-disposable. |
| Separate environment configuration | **NOT CONFIRMED** | Single `.env` present; no `.env.example`; no demo-specific env file observed. |
| Demo-only credentials | **NOT CONFIRMED** | No credential audit performed; no demo credential set created. |
| Sanitized seed data | **NOT CONFIRMED** | Seed scripts exist (`seed_users.py`, `seed_branches.py`) but not inspected for demo-safety/execution; no authorized seeding done. |
| Customer demo account | **NOT CONFIRMED** | No DB account creation/inspection performed. |
| Admin demo account | **NOT CONFIRMED** | No DB account creation/inspection performed. |
| Field-member demo account | **NOT CONFIRMED** | No DB account creation/inspection performed. |
| Migration requirements | **PENDING** | DB at 0005; 0006 and 0007 pending. Applying migrations requires explicit authorization and safe target DB. |
| Backend startup configuration | **PARTIALLY KNOWN** | App imports cleanly with dummy env vars; real env/startup not verified against configured DB. |

## 4. Demo Environment Preparation Plan (No actions taken)

1. **Authorize a safe target**: create/identify a separate disposable demo PostgreSQL database (e.g., `rupaywala_demo`) - not `rupaywala_ori`.
2. **Create demo env file**: copy env template to `.env.demo` with demo-only `DATABASE_URL`, `JWT_SECRET_KEY`, `QUOTE_SIGNING_SECRET`, `UPI_ID`, `CORS_ALLOWED_ORIGINS`, Maps/SMS/SMTP/Google credentials (or explicit mock/fallback plan).
3. **Migrations**: on authorized demo DB only, run `alembic upgrade head` after backup/snapshot. Confirm 0006/0007 applied.
4. **Seed sanitized data**: branches, service types, distance rate, subscription plans, demo customer/admin/approved field member, sample policies/subscriptions. Use authorized scripts or reviewed SQL; no real PII.
5. **Backend startup**: `uvicorn app.main:app --host 0.0.0.0 --port 8000` with demo env; verify `/health` returns `ok`.
6. **Flutter config**: point `API_BASE_URL` dart-define or config to demo backend; install Flutter SDK if needed.
7. **Rehearsal**: run end-to-end demo script on demo devices with test UPI/admin verification flow.

## 5. Blockers

- **B-001 (Critical):** Configured DB `rupaywala_ori` is not confirmed disposable/demo; migrations 0006/0007 pending. No migration or data-modifying test can be run safely.
- **B-002 (Critical):** Docker daemon unavailable; cannot inspect/start isolated Postgres containers.
- **B-003 (Critical):** Flutter SDK/Dart not available; Flutter analyze/test/build cannot run.
- **B-004 (High):** Demo accounts/data/environment not provisioned.
- **B-005 (High):** External integration credentials/readiness unknown (Maps/SMS/SMTP/Google OAuth/UPI).