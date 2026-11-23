# RUPAYWALA — Stage 5.6G Blockers / Gaps

## Overall
Stage 5.6G is **PARTIALLY COMPLETE**. Restricted-role disposable E2E validation ran successfully for core flows, but several required workflows/integrations/security cases remain BLOCKED, NOT TESTED, or need follow-up.

## Blockers / Gaps

| ID | Severity | Area | Status | Detail | Required Action |
|---|---|---|---|---|---|
| B56G-001 | High | Google Maps / quote distance | BLOCKED (live) | `maps.configured=false` in runtime. Live `/service/quote` and map-dependent legacy request creation could not be fully validated through live uvicorn. | Configure test Google Maps credentials in isolated env or provide local mock service; rerun live quote/request/nearest-branches flows. Mocked PASS obtained in-process only. |
| B56G-002 | High | End-to-end service request lifecycle with live maps | BLOCKED | Full quote->request->payment->assignment->field completion path under live maps not exercised. Mocked path passed. | Rerun with maps configured/mocked at HTTP boundary in disposable env. |
| B56G-003 | Medium | Payment idempotency semantics | FAIL/NEEDS REVIEW | Idempotency check with same `idempotency_key` returned 200/200 but different `txn_id` values in harness; needs definitive product/DB behavior review. | Add focused disposable-DB regression test for payment-create idempotency and fix if required. |
| B56G-004 | Medium | Duplicate verify semantics | NEEDS REVIEW | Second admin approve returned 200 idempotent success; may be acceptable, but "duplicate payment prevention/rejection" expectation is ambiguous. | Confirm desired behavior; enforce 409/400 if strict duplicate prevention required. |
| B56G-005 | Medium | Family member operations | PARTIAL | Family add on Silver plan returned 403 (plan limit/eligibility). Not validated on family-capable plan with active subscription. | Test on Family/Premium Family plan in disposable DB. |
| B56G-006 | Medium | Quote ownership/expiry exhaustive tests | PARTIAL | Reused consumed quote 409 PASS; invalid quote 404 PASS. Cross-customer quote-get and expiry boundary not fully tested. | Add explicit ownership and expiry tests. |
| B56G-007 | Medium | SMS/OTP live delivery | BLOCKED | Fast2SMS not configured; send-otp delivered=false. OTP verification tested via controlled hashed OTP insertion in disposable DB. | Configure test SMS provider or local SMS mock; classify LIVE PASS only when real delivery path verified. |
| B56G-008 | Medium | SMTP/email | NOT TESTED | No email workflow exercised. | Test email OTP/reset flows with local SMTP mock/test mailbox. |
| B56G-009 | Medium | Google OAuth live flow | NOT TESTED | No credentials/flow executed. | Test in isolated env with test OAuth client or mocked provider boundary. |
| B56G-010 | Medium | UPI gateway live verification | NOT TESTED / MOCKED | UPI intent/QR generated; admin manual verification tested; no live gateway settlement. | Use sandbox/mock gateway for end-to-end settlement verification; keep classification separate from live. |
| B56G-011 | Medium | File uploads | NOT TESTED | Field completion supports proof upload; upload path not exercised in this pass. | Add multipart upload test with safe test files in disposable env. |
| B56G-012 | High | Pytest suite | BLOCKED | `tests/conftest.py` is destructive (creates/drops `rupaywala_test`, schema reset/truncate). Running it is unsafe for this environment. | Run only after proving tests target disposable DB; prefer isolated disposable test DB and non-destructive fixtures. |
| B56G-013 | Medium | Concurrent plan catalog seeding safety | NOT PROVEN | `plan_catalog` uses `nextval` (USAGE) but concurrent startup seeding race not tested. | Add focused concurrent seeding regression test in disposable DB. |
| B56G-014 | High | Production readiness controls | NOT TESTED | No TLS/pg_hba/network perimeter/secret management/backup restore/monitoring/HA/deployment validation. | Complete Stage 6/ops hardening and production runbooks before any production claim. |
| B56G-015 | Low | Cleanup | ACTION REQUIRED | Temp uvicorn PID 14508, temp role `rw56g_app`, and temp files under `C:\Users\NITHIN\AppData\Local\Temp\opencode` were used for Stage 5.6G. | Stop uvicorn, drop temp role from postgres, remove temp pw/log/script files after report delivery. Do not touch source/validation DBs. |

## Not Modified / Preserved
- `rupaywala_ori`: untouched.
- `rupaywala_validation`: untouched.
- `rupaywala_role_validation`: untouched.
- `rupaywala_e2e_validation`: created for Stage 5.6G; left in place for evidence unless explicitly instructed to remove.

## Final Rule
No production readiness is claimed from these Stage 5.6G results.