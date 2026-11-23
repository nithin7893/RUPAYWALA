# RUPAYWALA_STAGE_5_6G1_REMAINING_FINDINGS

## Final Classification
**PARTIALLY COMPLETE**

No production readiness is claimed.

## Resolved in 5.6G-1

| ID | Area | Status | Evidence / Fix |
|---|---|---|---|
| B56G-003 | Payment idempotency same-key after terminal/different payload | **FIXED (disposable-DB validated)** | Root cause in `PaymentService._reusable_intent`: keyed lookup was open-only and fell back/allowed new intent; no payload match validation. Fix: keyed lookup checks any status, validates plan/request payload, returns existing terminal/open keyed intent, rejects key reuse for different payload with 409, avoids returning unrelated open intent as keyed. 10/10 regression cases PASS. |
| 5.6G report discrepancy | Shutdown marked NOT EXECUTED in E2E report | **RESOLVED** | Verified uvicorn PID 14508 not running, `rw56g_app` absent, 5.6G temp files removed. Updated `RUPAYWALA_STAGE_5_6G_E2E_VALIDATION_REPORT.md` shutdown row with post-cleanup confirmation. |

## Investigated Follow-ups (5.6G items)

| ID | Area | Status | Evidence | Recommendation |
|---|---|---|---|---|
| B56G-013 | Concurrent subscription-plan startup seeding | **FAIL / CONFIRMED RISK** | Disposable-DB concurrency script (3 threads calling `seed_subscription_plans`) produced 2x `UniqueViolation` on `ix_subscription_plans_code` (silver) while final state had 7 plans. Seeding is not concurrency-safe under simultaneous startup. | Make seeding idempotent under concurrency (e.g., advisory lock, serializable retry, or INSERT ... ON CONFLICT/UPSERT by code with proper transaction handling). Add disposable-DB concurrent regression test. |
| B56G-006 | Quote ownership validation | **PASS (service-level disposable DB)** | `QuoteService.get_quote` for different user returned 404 "Quotation not found". | Add HTTP-level cross-customer quote-get test in disposable E2E harness. |
| B56G-006 | Quote expiration boundary | **PASS (service-level disposable DB)** | Quote with `expires_at` in past and valid signature transitioned to `expired` on get. | Add boundary tests at exact expiry timestamp and concurrent consume/expire race. |
| B56G-006 | Quote signature tampering | **PASS (service-level disposable DB)** | Tampered `total_amount` with stale signature caused 409 "This quotation failed its integrity check. Please request a new quote." | Keep integrity checks on all read/consume paths; add HTTP/API tamper tests. |
| B56G-005 | Family member operations on eligible subscription plan | **PASS (model-level disposable DB)** | Active family-capable subscription (max_family_members=4) accepted family member insert; count=1. | Add API-level test via `/subscriptions/family-members` on eligible plan and verify limits/identity-key constraints. |

## Still Open / Blocked

| ID | Severity | Area | Status | Notes |
|---|---|---|---|---|
| B56G-001 | High | Google Maps live quote/distance | BLOCKED | No live maps config in disposable run. |
| B56G-002 | High | Full live E2E request lifecycle with maps | BLOCKED | Depends on maps/mock boundary. |
| B56G-004 | Medium | Duplicate verify semantics | NEEDS REVIEW | Duplicate admin verify returns idempotent 200 success; confirm product expectation (idempotent vs 409). |
| B56G-007 | Medium | SMS/OTP live delivery | BLOCKED | No Fast2SMS/live provider. |
| B56G-008 | Medium | SMTP/email | NOT TESTED |  |
| B56G-009 | Medium | Google OAuth live flow | NOT TESTED |  |
| B56G-010 | Medium | UPI gateway live settlement | NOT TESTED / MOCKED | Manual/admin verification only. |
| B56G-011 | Medium | File uploads | NOT TESTED |  |
| B56G-012 | High | Pytest full suite | BLOCKED | `tests/conftest.py` destructive; not run. |
| B56G-014 | High | Production readiness controls | NOT TESTED | TLS/pg_hba/secrets/backup/monitoring/HA/deployment not validated. |
| NEW-56G1-001 | Medium | Terminal same-key DB uniqueness | RISK / ACCEPTED FOR NOW | Partial unique index covers open statuses only; app now prevents silent duplicate creation, but a stricter all-status unique index was not added to avoid unsafe migration on unknown historical data. Evaluate with duplicate data audit before migration. |

## Cleanup
- Temp 5.6G-1 scripts created in `C:\Users\NITHIN\AppData\Local\Temp\opencode` should be removed after report handoff: `idem_repro.py`, `idem_followups.py`, `idem_regression.py`.
- Disposable DB `rupaywala_idem_validation` remains for evidence unless explicitly requested to drop.

## Final Rule
No production readiness is claimed.