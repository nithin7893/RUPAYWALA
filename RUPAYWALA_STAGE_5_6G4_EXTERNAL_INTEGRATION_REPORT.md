# RUPAYWALA STAGE 5.6G-4 — External Integration Report

## Classification
**PARTIALLY COMPLETE / BLOCKED** (no production readiness claim)

## Guardrails
- No API keys/credentials exposed. No real financial transactions performed. No unsolicited SMS/email sent.
- Results classified as **LIVE PASS / MOCKED PASS / FAIL / BLOCKED / NOT TESTED**.

## Environment / Config Inspection (Sanitized)
Source inspected: `app/config.py`, `app/main.py`, health endpoint response from actual running app.

| Integration | Config Present | Runtime Health Signal | Result | Notes |
|---|---:|---|---:|---|
| Google Maps / Mappls | Google Maps API key not configured in this env; Mappls legacy vars present in config but not active provider | `/health` reports `maps.configured=false, key_present=false, provider=google` | **BLOCKED** | No live Places/route/distance test performed. |
| Fast2SMS | Not configured in this env | N/A | **BLOCKED** | No OTP SMS sent. |
| SMTP | Not configured in this env | N/A | **BLOCKED** | No email sent. |
| Google OAuth | Not configured in this env | `/health` reports `google_sign_in=false` | **BLOCKED** | No live token validation flow executed. |
| UPI / Payments | UPI configured at app level (`upi_payments=true`) | `/health` reports `upi_payments=true` | **PARTIAL / MANUAL** | App supports UPI intent/QR generation and admin manual verification. No live payment gateway settlement/reconciliation performed. Duplicate verification idempotency observed in earlier HTTP run (submit 200, verify 200, duplicate 200) but clean retest had script payload mismatch; classify as **MOCKED PASS/PARTIAL** for manual verification logic, **NOT TESTED** for live gateway settlement. |
| File uploads | Upload dir/config present in codebase | Not exercised | **NOT TESTED** | Allowed formats/MIME/magic-byte/size/auth checks not validated in HTTP E2E. |

## Detailed Cases

| Case | Result | Evidence |
|---|---:|---|
| Google Maps Places lookup | **BLOCKED** | No configured key; not tested. |
| Google Maps route/distance calculation | **BLOCKED** | No configured key; quote generation for travel services would be blocked; digital quote path exercised. |
| Google Maps API error handling | **NOT TESTED** | No live calls. |
| Google Maps invalid key handling | **NOT TESTED** | No key manipulation/live test. |
| Fast2SMS OTP request | **BLOCKED** | Not configured; no SMS sent. |
| Fast2SMS provider response/failure/rate limiting | **NOT TESTED** | No live provider interaction. |
| SMTP email config/OTP/notification delivery | **BLOCKED** | Not configured; no email sent. |
| SMTP failure handling | **NOT TESTED** | No live provider interaction. |
| Google OAuth token audience validation | **NOT TESTED** | Not configured/live tested. |
| Google OAuth email verification | **NOT TESTED** | Not configured/live tested. |
| Google OAuth invalid token rejection | **NOT TESTED** | Not configured/live tested. |
| UPI payment intent | **PARTIAL** | Payment create returned 200 with txn in HTTP tests; QR/UPI fields not deeply asserted. |
| UPI UTR submission | **PARTIAL** | Submit returned 200 in HTTP tests. |
| Admin verification | **PARTIAL** | Manual verification endpoint exists; clean retest needed with correct `action` payload. |
| Duplicate verification | **PARTIAL** | Earlier run observed 200/200; clean retest pending. |
| Live payment gateway settlement | **NOT TESTED** | Explicitly not performed. |
| File upload allowed formats | **NOT TESTED** | No HTTP upload tests. |
| MIME validation | **NOT TESTED** | No HTTP upload tests. |
| Magic-byte validation | **NOT TESTED** | No HTTP upload tests. |
| Oversized file rejection | **NOT TESTED** | No HTTP upload tests. |
| Unauthorized upload rejection | **NOT TESTED** | No HTTP upload tests. |
| File retrieval authorization | **NOT TESTED** | No HTTP upload tests. |

## Notes
- All external integration outcomes are environment/config constrained. They are not production clearances.