# RUPAYWALA STAGE 5.6G-4 — Security Findings

## Classification
**PARTIALLY COMPLETE**

No production readiness claim. No destructive penetration tests performed.

## Scope / Evidence Base
- Actual FastAPI HTTP app running on `127.0.0.1:8011` against disposable DB `rupaywala_g4api_validation`.
- Restricted runtime role `rw_g4_app` used by app (DML + sequence USAGE/SELECT; no sequence UPDATE; role removed after cleanup).
- Synthetic data only.

## Security Check Results

| Check | Result | Evidence / Notes |
|---|---:|---|
| Customer data isolation | **PASS (observed)** | Other customer received 404 for quote GET and service request GET. |
| Admin authorization | **PASS (observed)** | Customer `GET /admin/dashboard` => 403. |
| Field-member authorization | **PASS (observed)** | Field member `GET /admin/users` => 403. |
| Quote ownership | **PASS (observed)** | Other customer cannot access quote => 404. |
| Payment ownership | **NOT TESTED** | Cross-user payment status/detail access not explicitly exercised in 5.6G-4 HTTP run. |
| Token invalidation | **PASS** | Logout returned 200; same token then `/auth/me` => 401. |
| Rate limiting | **NOT TESTED** | No rate-limit stress/bypass test executed. |
| Input validation | **PARTIAL** | Invalid quote/request payloads rejected (404/422 observed). Not comprehensive. |
| File upload validation | **NOT TESTED** | No upload tests. |
| Database least privilege | **PARTIAL PASS** | App ran under restricted role `rw_g4_app` (no sequence UPDATE). Full privilege audit not completed. |
| Error response information leakage | **PARTIAL** | Observed 401/403/404/409/422 responses; no secret leakage observed in sampled responses. Not exhaustive. |

## Payment Idempotency / DB Integrity Decision
- **No full unique payment index introduced in Stage 5.6G-4.**
- Subscription keyed idempotency and extra-charge idempotency have different semantics:
  - Subscription keyed: same key = same logical operation across statuses (5.6G-1 app behavior).
  - Extra-charge: deterministic `request:{request_id}` key currently allows legitimate retry after terminal failure/expiry by creating a new intent (5.6G-3 probe evidence). A full unique `(user_id,payment_type,idempotency_key)` index would block this.
- Future DB constraint design must preserve legitimate terminal extra-charge retries. Recommended direction: split semantic scope or introduce retry-aware extra-charge key/contract, with target-data duplicate preflight and safe migration.

## Findings
- **No critical regression observed** in exercised HTTP flows.
- **Unresolved:** full restricted-role HTTP E2E coverage incomplete; external integrations untested/blocked; file upload security not tested; rate limiting not tested; payment ownership HTTP negative test missing.

## Production Readiness
**Not claimed.**