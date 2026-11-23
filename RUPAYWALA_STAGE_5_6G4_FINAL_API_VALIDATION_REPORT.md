# RUPAYWALA STAGE 5.6G-4 — Final Application Integration & Restricted-Role API Validation Report

## Final Classification
**PARTIALLY COMPLETE**

No production readiness claim. Mocked/service-level/partial HTTP checks do **not** establish production readiness.

## Scope
- Stage 5.6G-4: actual HTTP API workflows, external integrations, and application security under restricted PostgreSQL runtime role.
- Preserved DBs not modified/deleted: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`, `rupaywala_g2seed_validation`, `rupaywala_g3pay_validation`.
- New disposable DB: `rupaywala_g4api_validation` (created after existence check; cloned from `rupaywala_g3pay_validation`; Postgres 18.1, container `rupaywala-pg18-validation`, `127.0.0.1:55432`).

## Runtime / Role Identity
- FastAPI app run as actual HTTP process via uvicorn on `127.0.0.1:8011`.
- App DB role: `rw_g4_app` (restricted runtime role; CONNECT on `rupaywala_g4api_validation`, USAGE on schema public, SELECT/INSERT/UPDATE/DELETE on tables, USAGE/SELECT on sequences; no sequence UPDATE). Role created for validation and dropped after cleanup.
- Health check (actual HTTP): `GET /health` => `200 {"status":"ok","database":"connected","integrations":{"maps":{"configured":false,"key_present":false},"google_sign_in":false,"upi_payments":true}}`.
- App started with `TESTING=1` to avoid startup DDL; schema pre-existed in cloned disposable DB; reference data/plan catalog seeded with admin connection in disposable DB.

## Actual HTTP API Results (Sanitized)

| Area | Case | Result | Evidence (sanitized) |
|---|---|---:|---|
| Customer auth | Registration | **NOT TESTED (HTTP E2E)** | OTP-gated flow requires SMS/email delivery; external delivery not configured. |
| Customer auth | Login | **PASS** | `POST /auth/login` => 200, access_token returned. |
| Customer auth | Token validation | **PASS** | `GET /auth/me` with bearer token => 200, username matched. |
| Customer auth | Profile retrieval/update | **PASS** | `GET /profile/me` => 200; `PUT /profile/update` => 200. |
| Customer auth | Logout/token invalidation | **PASS** | `POST /auth/logout` => 200; subsequent `GET /auth/me` with same token => 401. |
| Quotation | Service type retrieval | **PASS** | `GET /service/service-types` => 200. |
| Quotation | Fixed quotation generation (digital, no maps) | **PASS** | `POST /service/quote` => 201, quote_id/status active. |
| Quotation | Quote persistence | **PASS** | `GET /service/quote/{id}` => 200 same quote_id. |
| Quotation | Customer ownership | **PASS** | Other customer `GET /service/quote/{id}` => 404. |
| Quotation | Invalid quote ID | **PASS** | Tampered/nonexistent quote id => 404. |
| Quotation | Quote expiry | **NOT TESTED** | Requires controlled time advance/expiry window; not executed in HTTP E2E. |
| Quotation | Signature validation/tampering | **PARTIAL** | Invalid/nonexistent ID rejected 404; explicit signature-tamper HTTP case not executed. |
| Quotation | Single-use enforcement | **PASS** | Reuse of consumed quote for request creation => 409. |
| Service requests | Valid quote submission | **PASS** | `POST /service/request` with valid quote => 201, request id returned. |
| Service requests | Invalid quote rejection | **PASS** | Nonexistent quote => 404. |
| Service requests | Duplicate request protection | **PASS** | Same consumed quote reuse => 409. |
| Service requests | Request retrieval | **PASS** | Owner `GET /service/request/{id}` => 200. |
| Service requests | Customer isolation | **PASS** | Other customer `GET /service/request/{id}` => 404. |
| Payments | Payment initiation | **PASS** | `POST /payments/create` => 200. |
| Payments | Idempotency same key | **PASS** | Same key/payload => same txn_id. |
| Payments | Changed payload rejection | **PASS** | Same key different plan => 409. |
| Payments | Concurrent retries | **NOT TESTED (HTTP)** | Service-level concurrent coverage exists in 5.6G-3; HTTP concurrent stress not run. |
| Payments | Payment verification | **PARTIAL** | Prior run: submit 200, admin verify 200, duplicate verify 200 (script path corrected later; fixup payload mismatch gave 422). Manual verification flow exists; needs clean retest. |
| Payments | Duplicate verification | **PARTIAL** | See above. |
| Payments | Extra-charge retry behavior | **NOT TESTED (HTTP)** | 5.6G-3 probe confirmed service behavior; HTTP E2E not executed. |
| Subscriptions | Plan listing | **PASS** | `GET /subscriptions/plans` => 200, 7 plans. |
| Subscriptions | Purchase/payment/activation | **PARTIAL** | Payment/verify flow partially exercised; full activation/balance HTTP assertion not completed in clean run. |
| Subscriptions | Balance calculation | **NOT TESTED** | Not asserted in HTTP E2E. |
| Subscriptions | Family-member eligibility/limits | **NOT TESTED (HTTP)** | Prior catalog tests cover logic; HTTP E2E not executed. |
| Subscriptions | Concurrent plan seeding | **PASS (prior 5.6G-2/3)** | Not re-run in 5.6G-4; no regression evidence observed. |
| Admin | Authentication | **PASS** | Admin login => 200 role=admin. |
| Admin | Dashboard | **PASS** | `GET /admin/dashboard` => 200. |
| Admin | Customer management | **PASS** | `GET /admin/users` => 200. |
| Admin | Payment verification | **PARTIAL** | Endpoint reachable; clean HTTP verify retest needed with correct action payload. |
| Admin | Request management | **PASS** | `GET /admin/requests` => 200. |
| Admin | Branch assignment | **NOT TESTED** | Not executed in HTTP E2E. |
| Field member | Authentication | **PASS** | Field login => 200 role=field_member. |
| Field member | Assignment retrieval | **PASS** | `GET /field-member/my-assignments` => 200. |
| Field member | Visit start/completion/status transitions | **NOT TESTED** | Not executed in HTTP E2E (requires assigned request setup). |

## External Integrations (Summary)
See `RUPAYWALA_STAGE_5_6G4_EXTERNAL_INTEGRATION_REPORT.md`. No live keys/config validated as operational in this env; no real SMS/email/financial transactions performed.

## Security Checks (Summary)
See `RUPAYWALA_STAGE_5_6G4_SECURITY_FINDINGS.md`. Basic authz/isolation checks passed; full security validation incomplete.

## Payment Schema Decision (5.6G-4)
- **No full unique payment index introduced in this stage.**
- Separate idempotency scopes documented:
  - **Subscription payments (keyed):** 5.6G-1 app semantics treat idempotency key as primary identity across statuses for same user/type/key; same payload returns existing intent (including terminal), different payload 409. A full-status unique DB index is *semantically aligned* for this scope, but target-data duplicate preflight and migration safety remain incomplete.
  - **Extra-charge payments (request-deterministic):** currently use `idempotency_key=request:{request_id}` and allow legitimate retry after terminal failure/expiry by creating a new intent with same key. 5.6G-3 probe confirmed this creates a second row with same key; a full unique index on `(user_id,payment_type,idempotency_key)` would block legitimate retries.
- **Future recommendation:** introduce a design that preserves legitimate terminal extra-charge retries, e.g. (a) extra-charge retry key includes attempt/nonce or client-supplied retry key with explicit contract, or (b) split constraints by payment type/semantic scope (subscription-keyed full-status uniqueness; extra-charge open-intent uniqueness plus explicit retry-key strategy), with authorized target-data duplicate preflight, Alembic preflight-abort migration, and safe downgrade. Do not apply without target-data analysis.

## Test Suite Safety
- `tests/conftest.py` inspected: destructive (drops/recreates public schema on `rupaywala_test`, truncates, drops schema on teardown). Full pytest suite **NOT RUN**. Safety for full suite against dedicated disposable DB not established under default conftest.

## Blockers
See `RUPAYWALA_STAGE_5_6G4_RELEASE_BLOCKERS.md`. No production readiness claim.