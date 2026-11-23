# RUPAYWALA CLIENT DEMO TEST RESULTS

**Date:** 2026-11-21  
**Execution mode:** Safe/static checks only. No destructive DB operations, no schema drop/recreate, no production DB use, no live external integrations.

## 1. Test Execution Summary

| Area | Command / Check | Result | Evidence / Notes |
|---|---|---|---|
| Git/workspace inspection | `git log --oneline -5`, `git status --short` | Executed | Repo at `47a8f7e Initial Stage`; working tree already contains many modified/untracked files unrelated to this Stage 1 pass. |
| Python compile check | `.\venv\Scripts\python.exe -m compileall app -q` | PASS | No compilation errors reported. |
| Backend pytest suite | Not run | BLOCKED | `tests/conftest.py` creates engine to `rupaywala_test` and session fixture drops/recreates schema (`drop_all`/`create_all`). Running against non-disposable DB is unsafe; disposable test DB not confirmed. |
| Backend startup smoke | Not run | NOT RUN | Requires DB/env setup and possible external config; not executed to avoid unintended side effects. |
| Backend `/health` | Not run | NOT RUN | Depends on running server/DB. |
| API workflow smoke (auth/quotes/requests/payments/admin/field) | Not run | NOT RUN | Requires isolated demo DB and seeded accounts. |
| Flutter CLI availability | `where.exe flutter` | BLOCKED | Flutter not found in PATH. |
| Flutter analyze | Not run | BLOCKED | Flutter CLI unavailable. |
| Flutter unit/widget tests | Not run | BLOCKED | Flutter CLI unavailable. |
| Flutter build/run | Not run | BLOCKED | Flutter CLI unavailable. |
| Google Maps/Fast2SMS/SMTP/Google OAuth/UPI live checks | Not run | NOT RUN | External credentials/services and demo environment not verified; avoid accidental real traffic. |
| Stage 6D DB security scripts | Not run | NOT RUN (intentional) | Explicitly prohibited by Stage 1 instructions. |

## 2. Static Verification Performed

| Check | Result | Evidence |
|---|---|---|
| Audit report presence | Missing requested 6 reports | Glob search found no matching RUPAYWALA audit/phase/matrix/bug/readiness report files; Stage 5/6D reports present. |
| Fixed quote backend endpoints exist | PASS (static) | `app/routes/service_routes.py` has `POST /service/quote`, `GET /service/quote/{quote_id}`, `POST /service/quote/{quote_id}/cancel`; request create consumes `quote_id`. |
| Flutter fixed-quote integration | PASS (static) | `rupaywala_app/lib/core/api/repositories/service_repository.dart` adds `createFixedQuote`; `service_request_screen.dart` creates fixed quote and sends `quoteId`. |
| Forgot-password reset brute-force protection | PASS (static) | `auth_routes.py` reset now calls `OTPService.verify(..., purpose=reset_password)`; `otp_service.py` tracks attempts/expiry/use. |
| Google access-token audience check | PASS (static) | `google_auth_service.py` rejects `aud != GOOGLE_CLIENT_ID` and strictly parses `email_verified`. |
| JWT invalidation on password change/reset/logout | PASS (static) | `User.token_version` added; JWT carries `tv`; `dependencies.get_current_user` enforces version; logout endpoint increments version. |
| Upload webp validation | PASS (static) | `upload_service.py` validates RIFF/WEBP signature. |
| Proof file serving mount | PASS (static) | `app/main.py` mounts `/uploads` from `UPLOAD_DIR`. |
| Token store sharing defect | PASS (static) | `rupaywala_app/lib/core/api/api.dart` factory shares same `TokenStore` with `ApiClient`. |

## 3. Runtime-Blocked Demo Workflows

The following required Stage 1 demonstration workflows were **not runtime-verified**:

- Customer: registration, login, OTP, dashboard, profile, service selection, quotation, request creation, tracking, subscriptions, payment, payment history, policies, notifications.
- Admin: login, dashboard, customer/field-member/request/assignment/branch/distance/pricing/plan/payment verification/reports-stats management.
- Field member: login, assigned jobs, job details, start, update status, upload proof, complete, history.

## 4. Known Test Environment Constraints

- No confirmed isolated disposable demo DB credentials in workspace.
- `.env` exists but was not read for secret values; environment suitability unknown.
- Flutter SDK not available in PATH on this machine.
- External service credentials/connectivity (Google Maps, Fast2SMS, SMTP, Google OAuth, UPI) not validated.

## 5. Recommended Safe Next Test Commands

Run only in isolated/disposable environments:

```powershell
# Backend - use a disposable DB (not production)
$env:TESTING="true"
$env:DATABASE_URL="postgresql+psycopg://USER:PASS@HOST:5432/rupaywala_test"
.\venv\Scripts\python.exe -m pytest -q

# Backend smoke (disposable/demo DB)
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000

# Flutter (after installing Flutter SDK)
cd rupaywala_app
flutter pub get
flutter analyze
flutter test
flutter run
```
