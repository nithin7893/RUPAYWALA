# RUPAYWALA STAGE 5.6G-3 — Payment DB Integrity & Final API Regression Report

## Scope
- Stage: 5.6G-3 (continues 5.6G-2)
- Objective: Resolve NEW-56G1-001 database-level payment idempotency and validate recently fixed payment/subscription functionality together.
- Status classification: **PARTIALLY COMPLETE**
- Production readiness claim: **None**.

## Safety / Isolation
- No destructive commands used. No payment records deleted/rewritten.
- Preserved DBs not modified/dropped/accessed for mutation: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`, `rupaywala_g2seed_validation`.
- New disposable DB created only after existence check: `rupaywala_g3pay_validation` (container `rupaywala-pg18-validation`, Postgres 18.1, `127.0.0.1:55432`), cloned from `rupaywala_role_validation`.
- Default destructive `tests/conftest.py` inspected; not used. Focused regression executed via isolated disposable-DB scripts.
- Temp scripts removed after evidence capture.

## 1) Existing Implementation / Semantics Reviewed
- `app/services/payment_service.py`: subscription keyed idempotency is primary identity across any status (5.6G-1 fix); same key+same payload returns existing intent including terminal; different payload => 409; no-key open conflicts handled. Extra-charge creation uses `idempotency_key=f"request:{request_id}"` but calls `_reusable_intent` **without** `idempotency_key`, relying on request open-intent lookup + `uq_payments_open_extra_charge_request`.
- `app/models/payment.py`: `uq_payments_user_type_idem_open` unique partial index on `(user_id,payment_type,idempotency_key)` WHERE key IS NOT NULL AND status IN pending/pending_verification; `uq_payments_open_extra_charge_request` unique partial index on `(related_request_id)` WHERE extra_charge open.
- `alembic/versions/0006_stage5_security_remediation.py`: creates partial indexes with duplicate preflight and safe abort; downgrade drops indexes.
- Stage 5.6G-1/5.6G-2 reports and existing payment tests reviewed.

## 2) Proposed Full Unique Index Evaluation
Proposed: `UNIQUE (user_id, payment_type, idempotency_key) WHERE idempotency_key IS NOT NULL`

| Semantic case | Compatible? | Evidence/Reason |
|---|---:|---|
| Same key across pending payments | Yes | Same tuple blocked; matches app open-idempotency. |
| Same key across successful payments | Yes (for subscription keyed semantics) | 5.6G-1 returns existing terminal intent; no new row. |
| Same key across failed/expired payments | **No for current extra-charge retry semantics; Yes for subscription keyed semantics** | Probe on disposable DB: extra-charge create after terminal failure created a new row with same key `request:{id}` (`rows=2`, same key, different txn). Full unique index would reject legitimate extra-charge retry. Subscription keyed flow returns terminal intent and is compatible. |
| Different keys for separate legitimate payment operations | Yes | Different key => different tuple. |
| Different users using same key | Yes | `user_id` in index. |
| Subscription payments | Yes | Aligns with 5.6G-1 app semantics. |
| Extra-charge payments | **Not as-is** | Deterministic key `request:{id}` reused on retry; terminal retry currently legitimate and creates new row. |
| Related service requests | Partially | Extra-charge request uniqueness already covered by `uq_payments_open_extra_charge_request`; full key index would add cross-status constraint but conflicts with retry behavior. |

**Decision:** Proposed full unique index is **NOT SAFE/NOT COMPATIBLE AS-IS** with current application semantics. Do not add/modify indexes. No migration applied.

## 3) Duplicate-Data Preflight (Disposable DB)
- DB: `rupaywala_g3pay_validation` (new disposable clone of `rupaywala_role_validation`).
- Query scope: all historical payment rows, all statuses, `idempotency_key IS NOT NULL`, grouped by `(user_id,payment_type,idempotency_key)`.
- Result: `total=0, keyed=0, null_key=0, duplicate_groups=0`.
- **Interpretation:** No duplicates observed in this disposable clone. This is **insufficient** to prove absence in preserved/production-like target data. Also, semantic incompatibility (extra-charge terminal retry same key) is an application-behavior blocker independent of historical row duplicates.

## 4) Migration Safety
- **Migration prepared/applied:** **NO**. Index is not compatible as-is.
- **If future migration considered**, required before any schema change:
  1. Resolve extra-charge terminal-retry semantics: either change extra-charge to new idempotency key per retry attempt (and update app/client/API contract) or make extra-charge keyed reuse return terminal intent with explicit retry-key flow; alternatively use a partial full-status unique index excluding extra-charge deterministic request keys only if semantics are formally accepted and documented (fragile; not recommended without strong justification).
  2. Run authorized read-only duplicate preflight on target/prod-like data for full key across all statuses.
  3. Add Alembic migration with preflight duplicate check that aborts safely (pattern from 0006), preserve payment history, no destructive cleanup.
  4. Evaluate `CREATE UNIQUE INDEX CONCURRENTLY` (requires autocommit/non-transactional Alembic handling) vs standard create; consider lock/downtime.
  5. Decide whether `uq_payments_user_type_idem_open` can be replaced after full index exists; keep `uq_payments_open_extra_charge_request`.
  6. Provide safe downgrade and do not apply to preserved DBs without approval.

## 5) Regression Tests (Disposable DB)
Executed via isolated script against `rupaywala_g3pay_validation`. All 12 required scenarios passed:

| # | Case | Result |
|---|---|---:|
| 1 | Same user, same key, same payload | PASS |
| 2 | Same user, same key, different payload | PASS (409) |
| 3 | Same key after successful payment | PASS (same txn, success returned) |
| 4 | Same key after failed payment | PASS (same txn, failed returned) |
| 5 | Same key after expired payment | PASS (same txn, expired returned) |
| 6 | Different users using the same key | PASS |
| 7 | Different payment types using the same key | PASS (DB semantic check; different type allowed) |
| 8 | Extra-charge idempotency | PASS (open intent reused) |
| 9 | Concurrent identical payment requests | PASS (5 workers, 1 row, same txn) |
| 10 | Concurrent conflicting payload requests | PASS (1 row, one 409 conflict) |
| 11 | Payment verification retries | PASS (idempotent success) |
| 12 | Payment history remains unchanged | PASS (single row, amount preserved, status progressed) |

## 6) Combined Regression
| Case | Result | Evidence |
|---|---:|---|
| Payment creation & idempotency | PASS | cases 1-10 |
| Payment verification | PASS | cases 3,4,11,12 |
| Subscription plan seeding | PASS | catalog regression in 5.6G-2; reseed in combined case |
| Concurrent subscription startup | PASS | 5 workers, 0 errors, 7 plans, IDs stable |
| Sequence permissions | PASS | restricted role USAGE=true UPDATE=false; seed succeeded |
| Subscription purchase and activation | PASS | idempotent verify, success status |

## Index/History Preservation
- No payment indexes added/modified/dropped.
- No payment rows deleted/rewritten.
- Payment history unchanged by idempotent retries (case 12).

## Final Classification
**PARTIALLY COMPLETE** — Required duplicate preflight and regression/combined validation completed on a new disposable DB; proposed full unique index was evaluated and found **not compatible as-is** with current extra-charge terminal-retry semantics (and target-data duplicate preflight remains incomplete). No migration applied. No production readiness claim.
