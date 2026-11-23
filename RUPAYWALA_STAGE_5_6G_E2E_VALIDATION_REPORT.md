# RUPAYWALA — Stage 5.6G E2E Validation Report

## Status
**PARTIALLY COMPLETE**

Stage 5.6G executed restricted-runtime validation in a disposable PostgreSQL clone with the actual FastAPI app running under a restricted runtime role. Core auth, admin, field-member, payment, subscription, and security-denial checks passed. Live map-dependent quote/service-request workflows were blocked by missing external Google Maps configuration; those flows were additionally validated with mocked map dependencies in-process and classified as MOCKED PASS. Full production readiness is **not** claimed.

## Scope and Safety
- Existing DBs preserved: `rupaywala_ori` (not present/touched), `rupaywala_validation` (not modified), `rupaywala_role_validation` (not modified).
- New disposable DB created: `rupaywala_e2e_validation` (created only after existence check returned absent).
- Source backup created before clone: `database_backups/rupaywala_role_validation_pre_56g_20261121_223922.dump`.
- No secrets, OTPs, passwords, tokens, or full `DATABASE_URL` are included in this report.
- Stage 6D not executed. Pytest not run (destructive `tests/conftest.py` safety gate).

## Environment / Identity
| Item | Value |
|---|---|
| Container | `rupaywala-pg18-validation` |
| PostgreSQL | `PostgreSQL 18.1 (Debian 18.1-1.pgdg13+2)` |
| Source DB | `rupaywala_role_validation` (owner `validation_admin`, alembic `0007_user_token_version`, 20 tables) |
| Target disposable DB | `rupaywala_e2e_validation` (cloned from source, alembic `0007_user_token_version`) |
| Runtime app role | `rw56g_app` (temporary LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS, mirrors `rupaywala_app` grants on E2E DB only) |
| Runtime DB/user verification | `SELECT current_database(), current_user, session_user` => `rupaywala_e2e_validation | rw56g_app | rw56g_app` |
| FastAPI process | uvicorn PID `14508`, `127.0.0.1:18080` |
| Health | `GET /health` => 200 `{"status":"ok","database":"connected", ...}` |

## Stage 5.6F Privilege Changes Applied (NEW DB only)
Applied in `rupaywala_e2e_validation` only:
- `REVOKE UPDATE ON SEQUENCE public.subscription_plans_id_seq FROM rupaywala_app;`
- `rw56g_app` granted same table/sequence privileges as `rupaywala_app` in E2E DB; sequence UPDATE not granted.

Verified:
- `rupaywala_app`/`rw56g_app` USAGE on `subscription_plans_id_seq`: true.
- `rupaywala_app`/`rw56g_app` UPDATE on `subscription_plans_id_seq`: false.
- `SET ROLE rupaywala_app; setval(...)` => `permission denied for sequence subscription_plans_id_seq` (PASS).
- `SET ROLE rupaywala_app; CREATE TABLE public.zz...` => denied (PASS).
- `SET ROLE rupaywala_app; TRUNCATE TABLE public.notifications;` => denied (PASS).
- `SET ROLE rupaywala_app; SELECT * FROM public.alembic_version;` => denied (PASS).
- Role attributes safe: `rolsuper=false, rolcreatedb=false, rolcreaterole=false, rolbypassrls=false, rolcanlogin=true, rolinherit=false`.

## Startup Validation
| Check | Result | Evidence |
|---|---|---|
| DB connection | PASS | `/health` database connected; runtime identity query returned E2E DB/rw56g_app |
| App startup | PASS | uvicorn started; "Rupaywala API ready" |
| Subscription-plan seeding | PASS | startup logs show seeded service types and distance pricing config; no permission-denied errors |
| No sequence UPDATE required | PASS | startup/seeding completed after revoking `subscription_plans_id_seq` UPDATE from app role in E2E DB |
| Health endpoint | PASS | 200 OK |
| DB-dependent readiness | PASS | health status ok, database connected |
| Shutdown / cleanup | PASS (post-report cleanup confirmed in 5.6G-1) | uvicorn PID 14508 not running; temp role `rw56g_app` absent; 5.6G temp scripts/logs/password/pid files removed. Original report text incorrectly left as NOT EXECUTED; corrected during 5.6G-1 discrepancy review. |

## Workflow Results (HTTP API, restricted runtime role)
| Workflow | Result | Evidence / Notes |
|---|---|---|
| Customer registration | PASS | `POST /auth/send-otp` 200 (delivered=false, SMS not configured), verify OTP via controlled test setup 200, register 201, role=customer |
| Customer login | PASS | `POST /auth/login` 200, role=customer |
| Token validation | PASS | `GET /auth/me` 200 with customer role |
| Profile retrieval/update | PASS | `PUT /profile/update` 200, `GET /profile/me` 200 |
| Logout/session invalidation | PASS | logout 200, old token `/auth/me` 401, re-login 200 |
| Service type retrieval | PASS | `GET /service/service-types` 200, 10 active types |
| Fixed quotation generation (live) | BLOCKED | Maps not configured (`503`/dependency unavailable). Live Google Maps not configured in env |
| Fixed quotation generation (mocked) | MOCKED PASS | In-process TestClient with mocked map distance; `POST /service/quote` 201 |
| Quote persistence | MOCKED PASS | Quote retrieved by ID 200 |
| Quote ownership validation | PARTIAL / MOCKED PASS | Request ownership cross-customer check returned 403/404 in mocked flow; dedicated cross-customer quote-get not separately evidenced (gap) |
| Quote expiry/single-use | PARTIAL / MOCKED PASS | Single-use consumed quote reuse returned 409; explicit expiry-time test not executed |
| Service request creation with valid quote | MOCKED PASS | `POST /service/request` with quote_id 201 (request 2) |
| Service request retrieval | MOCKED PASS | `GET /service/request/2` 200 |
| Invalid quote rejection | MOCKED PASS | random UUID quote_id returned 404 |
| Duplicate request protection | MOCKED PASS | reused consumed quote returned 409 "already been used" |
| Payment initiation | PASS | `POST /payments/create` for subscription plan returned payment intent (txn `649c9b84...`, amount 365.00) |
| Idempotency | FAIL / NEEDS REVIEW | Two create calls with same idempotency key returned 200/200 with different txn_ids in v3 harness; needs focused investigation. Earlier DB showed one row for first payment; behavior may be plan/pending-state specific. |
| Payment submission | PASS | `POST /payments/submit` 200, status pending_verification, attempts 1 |
| Invalid payment rejection | PASS | invalid UTR `A` rejected 422 |
| Duplicate payment prevention | PARTIAL | duplicate submit returned 200 idempotent message (attempts remained 1); classify as idempotent handling, not a hard 409 |
| Payment verification workflow | PASS | `POST /admin/payments/verify` approve 200, status success, subscription activated |
| Duplicate verify behavior | PARTIAL | second approve returned 200 idempotent success; not a blocking error but should be reviewed for desired semantics |
| Subscription plan retrieval | PASS | `GET /subscriptions/plans` 200, 7 plans |
| Subscription purchase workflow | PASS | create->submit->admin verify activated Silver subscription |
| Subscription persistence | PASS | `GET /subscriptions/my-subscription` 200 after verification; balance reflected active subscription |
| Family member operations | FAIL (expected limit) / PARTIAL | `POST /subscriptions/family-members` on Silver plan returned 403 "An active subscription is required" in one run then later plan limits apply; needs retest on family-capable plan. Not fully validated |
| Admin authentication | PASS | admin login 200 role=admin |
| Admin dashboard/data retrieval | PASS | `/admin/dashboard` 200, `/admin/users` 200, `/admin/requests` 200 |
| Admin management operations | PASS (limited) | branch create 201, payment verify 200, assign field member 200 |
| Field member authentication | PASS | field login 200 role=field_member; `/field-member/me` 200 |
| Assigned request retrieval | PASS | `/field-member/my-assignments` 200 |
| Visit workflow/status updates | PASS | start-request 200, complete-request 200 (proof optional path) |
| Job history/completion | PARTIAL | completion done; explicit history filter not tested |

## External Integrations
| Integration | Classification | Notes |
|---|---|---|
| Google Maps / distance | MOCKED PASS | Live maps not configured (`maps.configured=false`). Mocked distance used in in-process TestClient; live uvicorn quote/request blocked |
| Google OAuth | NOT TESTED | No live credentials/test flow executed |
| SMS/OTP delivery | BLOCKED | Fast2SMS not configured; `/auth/send-otp` returned delivered=false. OTP verification tested by controlled hashed OTP insertion in disposable DB |
| SMTP/email | NOT TESTED | SMTP not configured |
| UPI/payment gateway | MOCKED PASS | UPI intent/QR generated; no live gateway/UPI settlement verification. Admin manual verification workflow tested |
| File uploads | NOT TESTED | No upload workflow executed in this pass |

## Security / DB Observations
- No `permission denied` / `InsufficientPrivilege` strings found in uvicorn err log after workflow tests.
- Sequence `setval`, CREATE, TRUNCATE, and `alembic_version` access denied for `rupaywala_app` in E2E DB.
- Runtime role was restricted `rw56g_app` with no superuser/createdb/createrole/bypassrls.
- `plan_catalog._ensure_subscription_plans_sequence` uses `nextval` (USAGE) only; no setval. Concurrent startup seeding safety not fully proven by concurrent test; review recommended before production.

## Evidence (sanitized)
- Health: `{"status":"ok","database":"connected",...}`
- Uvicorn startup: seeded service types/pricing config; "Rupaywala API ready"; SMS warning "Fast2SMS rejected..." (no secrets/OTP values)
- Mocked quote create 201, get 200, cancel 200, request create 201, duplicate quote reuse 409, invalid quote 404, admin requests 200.
- Admin assign 200, field my-assignments 200, start-request 200, complete-request 200.

## Remaining Blockers / Gaps
See `RUPAYWALA_STAGE_5_6G_BLOCKERS.md`.

## Final Classification
**PARTIALLY COMPLETE** — restricted-role E2E validation produced meaningful PASS evidence in disposable staging, but live map-dependent workflows, some negative/ownership/expiry/idempotency semantics, external integrations, pytest safety-gated suite, and production infra controls remain unverified/blocked. No production readiness claim.