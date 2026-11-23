# RUPAYWALA Stage 5.6M Backend Test Report

## Scope

Safe authentication/backend tests against the running local backend connected to `rupaywala_dev_stage56k` only. No real customer credentials exposed/reset. No destructive conftest/pytest against existing DBs.

## Test Environment

| Item | Value |
|---|---|
| Backend | `http://127.0.0.1:8000` (PID 3172, process-only dev DB config) |
| Target DB | `rupaywala_dev_stage56k` (identity gate verified before test writes) |
| Alembic | `0008_private_document_storage` |
| Test user strategy | Disposable user created in `rupaywala_dev_stage56k` for test, cleaned up by specific ID/username after tests |
| Secret handling | No passwords/tokens/credentials printed in report |

## Automated / Scripted Live Backend Tests

| Check | Method | Result | Status |
|---|---|---|---|
| Identity gate | SQL check before test: `current_database=rupaywala_dev_stage56k`, revision `0008_private_document_storage` | Pass | PASS |
| Health | `GET /health` against running backend | 200, `database=connected` | PASS |
| Customer login (disposable user) | `POST /auth/login` with disposable username/password | 200, bearer access token returned | PASS |
| Token generation | Login response includes `access_token` and `token_type=bearer` | Present | PASS |
| Profile retrieval | `GET /auth/me` with bearer token | 200, returned expected `user_id` and username | PASS |
| Invalid password rejection | `POST /auth/login` with wrong password | 401, "Incorrect username/mobile number or password" | PASS |
| Logout | `POST /auth/logout` with bearer token | 200 | PASS |
| Token invalidation after logout | `GET /auth/me` with old token after logout | 401, "Not authenticated" (token version invalidation) | PASS |
| Login after logout | `POST /auth/login` again with same disposable user | 200, new access token returned | PASS |
| Disposable user cleanup | Deleted only the specifically created test user by ID+username | Pass | PASS |

## Live CORS/Preflight (Running Backend)

| Check | Result | Status |
|---|---|---|
| `OPTIONS /auth/login` Origin `http://localhost:60292` | 200; `Access-Control-Allow-Origin: http://localhost:60292`; `Access-Control-Allow-Credentials: true`; methods include POST,GET,PUT,PATCH,DELETE,OPTIONS | PASS |
| `OPTIONS /auth/send-email-otp` Origin `http://localhost:60292` | 200; `Access-Control-Allow-Origin: http://localhost:60292` | PASS |

## Not Run / Not Claimed

| Check | Status | Reason |
|---|---|---|
| Full pytest suite via `tests/conftest.py` | NOT TESTED | Conftest is destructive (creates/drops `rupaywala_test`, overwrites `DATABASE_URL`) |
| Existing customer password login | NOT TESTED | No real customer credentials exposed/reset |
| Full end-to-end customer flows beyond auth smoke | NOT TESTED | Outside Step 4 scope |

## Observations

- No `UndefinedColumn` or missing-table errors observed in backend logs during startup and auth tests.
- Login/token_version behavior works against migrated dev DB (`0008_private_document_storage`), consistent with 0007 application.

## Status

**PASS** for automated/live backend auth smoke tests listed above. No production readiness claimed.