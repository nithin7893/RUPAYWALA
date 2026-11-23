# RUPAYWALA STAGE 1B BLOCKERS

**Date:** 2026-11-21  
**Stage:** 1B - Isolated Demo Environment Preparation and End-to-End Verification

## Blocker Register

| ID | Severity | Blocker | Evidence | Impact | Required Action | Can Proceed Without? |
|---|---|---|---|---|---|---|
| B-001 | Critical | Configured database is not confirmed disposable/demo (`rupaywala_ori`, localhost:5432) and production/demo separation not established. | Safe env parse: db `rupaywala_ori`, host localhost, name not test/demo/dev. | Any migration, seed, or DB-dependent test risks unintended data impact. | Identify/create separate authorized demo DB; update demo env config; backup/snapshot before changes. | No |
| B-002 | Critical | Alembic migrations 0006 and 0007 pending on configured DB; 0007 required by current code (`users.token_version`). | DB read-only check: alembic `0005_fixed_quotes`; heads `0007_user_token_version`. | Running current code against DB without 0007 may fail auth/user queries. Cannot apply without authorization/safe DB. | On authorized demo DB only: review 0006/0007, backup, `alembic upgrade head`, verify. | No |
| B-003 | Critical | Docker daemon not reachable; cannot inspect/start isolated Postgres containers. | `docker ps -a` failed: dockerDesktopLinuxEngine pipe not found; Docker CLI 29.2.0 installed. | Cannot provision isolated demo DB via Docker in this session. | Start Docker Desktop/daemon or provision approved external demo Postgres. | No, unless external demo DB provided |
| B-004 | Critical | Flutter SDK/Dart unavailable. | `where.exe flutter/dart` not found; no `flutter.bat` in common locations. | Cannot run `flutter doctor/analyze/test/build` or mobile demo verification. | Install/configure Flutter SDK on PATH; run doctor/analyze/test. | No |
| B-005 | High | Pytest cannot be safely executed. | `tests/conftest.py` creates `rupaywala_test`, sets env, and fixtures drop/create schema. | No backend automated regression evidence. | Run pytest only on authorized disposable test DB/server. | No for verified confidence |
| B-006 | High | Demo accounts/seed data not provisioned. | No authorized DB writes; account existence not verified. | Cannot execute customer/admin/field-member E2E demo. | Create sanitized demo accounts/data in authorized demo DB. | No |
| B-007 | High | External integrations not verified (Google Maps, Fast2SMS, SMTP, Google OAuth, UPI). | Env key presence partial; no live calls made. | OTP/map/payment/OAuth demo steps may fail. | Validate demo credentials/connectivity in isolated environment. | No for full demo |
| B-008 | Medium | Backend runtime against configured/real demo DB not verified. | Only isolated sqlite in-process smoke ran; `/health` degraded due missing tables. | Cannot confirm real startup/DB connectivity. | Start backend against authorized demo DB and verify `/health` ok. | No |
| B-009 | Medium | End-to-end workflow evidence absent. | All 29 workflow tests BLOCKED. | Cannot claim demo readiness. | Execute full E2E rehearsal after B-001..B-008 resolved. | No |

## Safe-Next Commands (Authorized Isolated Environment Only)

```powershell
# DB migration (authorized demo DB only)
cd C:\RUPAAY_WALA\rupaywala_backend
.\venv\Scripts\python.exe -m alembic upgrade head

# Backend smoke
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
Invoke-RestMethod http://127.0.0.1:8000/health

# Pytest (disposable test DB only)
$env:TESTING="true"
$env:DATABASE_URL="postgresql+psycopg://USER:PASS@HOST:5432/rupaywala_test"
.\venv\Scripts\python.exe -m pytest -q

# Flutter
cd C:\RUPAAY_WALA\rupaywala_backend\rupaywala_app
flutter doctor -v
flutter pub get
flutter analyze
flutter test
```