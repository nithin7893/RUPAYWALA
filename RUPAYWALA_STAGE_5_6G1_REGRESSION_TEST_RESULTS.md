# RUPAYWALA_STAGE_5_6G1_REGRESSION_TEST_RESULTS

## Final Classification
**PARTIALLY COMPLETE** (required payment idempotency regression cases passed in disposable DB; full suite and live integrations not run)

No production readiness is claimed.

## Execution Safety
- Disposable DB: `rupaywala_idem_validation` (docker `rupaywala-pg18-validation`, cloned from `rupaywala_role_validation`).
- Preserved DBs untouched: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`.
- `tests/conftest.py` inspected: destructive (creates/drops `rupaywala_test`, schema reset/truncate, advisory lock). Default pytest **NOT RUN**.
- Regression executed via standalone disposable-DB script: `C:\Users\NITHIN\AppData\Local\Temp\opencode\idem_regression.py`.
- Machine-readable result: `RUPAYWALA_STAGE_5_6G1_REGRESSION_TEST_RESULTS.json`.

## Required Case Results

| # | Case | Result | Evidence (sanitized) |
|---:|---|---|---|
| 1 | First payment creation | PASS | txn `8481e4af...`, status `pending`, rows=1 |
| 2 | Sequential duplicate request | PASS | same txn `c95d1d79...` returned; rows=1 |
| 3 | Concurrent duplicate request | PASS | 2 concurrent OK responses, same txn `185e87db...`, rows=1 |
| 4 | Same key with changed payload | PASS | first txn `933749e4...`; second attempt rejected with 409 |
| 5 | Different user with same key | PASS | different txns `ca338420...` vs `882bf1de...`, different user_ids |
| 6 | Retry after pending status | PASS | same txn `5541133f...`, rows=1 |
| 7 | Retry after successful verification | PASS | verified/retry same txn `800d334e...`, status success, rows=1 |
| 8 | Retry after failure | PASS | rejected/retry same txn `9dd81e0e...`, status failed, rows=1 |
| 9 | Duplicate payment submission | PASS | same pending_verification, attempts remained 1 |
| 10 | Duplicate admin verification | PASS | both responses success, same txn `9d...?`/same txn; idempotent success |

> Note: Case 10 txn from summary: `status1=success,status2=success` (same txn as created in case; see JSON for exact sanitized value). All 10 passed.

## Summary
- Passed: **10/10**
- Failed: **0/10**
- Blocked: **0/10** (within disposable DB scope)

## Additional Evidence
- Pre-fix reproduction confirmed defects for same-key after success/failure/expiry and same-key different payload.
- Post-fix reproduction confirmed same-key terminal states return existing intent and different payload returns 409.
- Existing pytest-style regression file added: `tests/test_stage56g1_payment_idempotency.py` (not executed under destructive default conftest).

## Not Run / Blocked
- Full pytest suite under default `tests/conftest.py` - BLOCKED (destructive). 
- Live integration tests (Maps/SMS/SMTP/OAuth/UPI gateway/file uploads) - NOT TESTED/BLOCKED.
- Production infra/security/ops validation - NOT TESTED.