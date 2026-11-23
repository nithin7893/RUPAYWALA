# RUPAYWALA STAGE 5.6G-3 — Regression Test Results

## Execution Context
- Date: 2026-11-21
- Project: `C:\RUPAAY_WALA\rupaywala_backend`
- Disposable DB: `rupaywala_g3pay_validation` (Postgres 18.1, `rupaywala-pg18-validation`, `127.0.0.1:55432`)
- DB created after existence check; cloned from `rupaywala_role_validation`. Preserved DBs not modified: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`, `rupaywala_g2seed_validation`.
- `tests/conftest.py` inspected: destructive; not used. Focused tests run via isolated disposable-DB scripts with `TESTING=1`.

## Duplicate Preflight (Proposed Full Unique Index)
Proposed index: `UNIQUE (user_id, payment_type, idempotency_key) WHERE idempotency_key IS NOT NULL`

| Check | Result | Evidence |
|---|---:|---|
| Total payments | PASS/INFO | 0 |
| Keyed payments | PASS/INFO | 0 |
| Null idempotency_key rows | PASS/INFO | 0 |
| Duplicate groups across all statuses | PASS/INFO | 0 groups |
| Target-data completeness | **NOT SUFFICIENT** | Disposable clone only; preserved/prod-like target data not preflighted. |

## Required Payment Regression Cases

| # | Case | Result | Evidence |
|---|---|---:|---|
| 1 | Same user, same key, same payload | PASS | same txn_id, 1 row |
| 2 | Same user, same key, different payload | PASS | HTTP 409, 1 row retained |
| 3 | Same key after successful payment | PASS | same txn_id, status=success, 1 row |
| 4 | Same key after failed payment | PASS | same txn_id, status=failed, 1 row |
| 5 | Same key after expired payment | PASS | same txn_id, status=expired, 1 row |
| 6 | Different users using the same key | PASS | different txn_id/user_id |
| 7 | Different payment types using the same key | PASS | synthetic DB semantic check: subscription+extra_charge same key allowed as different payment_type |
| 8 | Extra-charge idempotency | PASS | open extra-charge intent reused, 1 row |
| 9 | Concurrent identical payment requests | PASS | 5 workers, 0 errors, 1 row, same txn |
| 10 | Concurrent conflicting payload requests | PASS | 1 row; one success, one 409 conflict |
| 11 | Payment verification retries | PASS | repeated approve returned success idempotently |
| 12 | Payment history remains unchanged | PASS | single row preserved; amount unchanged; status progressed to success |

## Combined Regression

| Case | Result | Evidence |
|---|---:|---|
| Payment creation and idempotency | PASS | Cases 1-10 |
| Payment verification | PASS | Cases 3,4,11,12 |
| Subscription-plan seeding | PASS | Seeded 7 canonical plans; idempotent |
| Concurrent subscription startup | PASS | 5 concurrent workers, 0 errors, 7 plans, IDs stable |
| Sequence permissions | PASS | restricted role `has_sequence_privilege(USAGE)=true`, `UPDATE=false`; seed succeeded; count=7 |
| Subscription purchase and activation | PASS | payment verified success; re-verification idempotent |

## Additional Probe (Semantic Compatibility)
| Probe | Result | Evidence |
|---|---:|---|
| Extra-charge retry after terminal failure with same deterministic key `request:{id}` | **INCOMPATIBLE WITH PROPOSED FULL INDEX** | Current app behavior created new intent: `rows=2`, same `idempotency_key=request:{id}`, different txn_ids. Full unique index would block this legitimate retry. |

## Not Run / Blocked
- Full pytest suite: **BLOCKED** (destructive conftest).
- Actual restricted-role end-to-end HTTP application tests: **PARTIAL/BLOCKED** (service-level regression and restricted-role seeding/sequence checks run; full restricted-role API test harness not executed).
- Target-data duplicate preflight for preserved/prod-like DBs: **BLOCKED/NOT EXECUTED** (not authorized).
- Live external integrations: **BLOCKED/NOT TESTED**.
- Migration apply/downgrade on preserved DBs: **NOT EXECUTED** (by design).
