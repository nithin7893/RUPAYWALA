# RUPAYWALA STAGE 5.6F - Runtime Privilege Hardening Report

**Date:** 2026-11-21  
**Stage:** 5.6F - Remove Runtime Sequence UPDATE Privilege and Harden Subscription Seeding  
**Status:** **COMPLETE (staging/code verification scope)**  
**Production readiness:** **NOT CLAIMED**

## 1. Objective

Resolve Stage 5.6E finding F-001 by removing the application runtime need for `UPDATE` on `public.subscription_plans_id_seq` during startup subscription-plan seeding, while preserving plan data/IDs and idempotent behavior.

## 2. Safety / Scope Controls

| Control | Result |
|---|---|
| `rupaywala_ori` modified | No |
| `rupaywala_validation` modified | No |
| `rupaywala_role_validation` modified during 5.6F implementation | No |
| Production migrations executed | No |
| Flutter UI / API contracts changed | No |
| Unrelated subscription logic changed | No |
| Credentials exposed | No (temp secret files used locally, not logged; cleaned up) |
| Destructive pytest run without isolation proof | No - used targeted pytest on disposable `rupaywala_test` DB created by conftest on validation container; cleaned up |

## 3. Root Cause

`app/services/plan_catalog.py` previously executed:

```sql
SELECT setval(
    pg_get_serial_sequence('subscription_plans', 'id'),
    COALESCE(MAX(id), 1),
    MAX(id) IS NOT NULL
)
FROM subscription_plans
```

during `seed_subscription_plans()`, which is called on startup (`app/main.py`). PostgreSQL `setval()` requires `UPDATE` on the sequence, forcing a least-privilege exception for `rupaywala_app` on `subscription_plans_id_seq`.

## 4. Files Changed

| File | Change |
|---|---|
| `app/services/plan_catalog.py` | Removed `setval()`; added `_ensure_subscription_plans_sequence(db)` that advances behind sequences using `nextval()` (USAGE) only, with no backward reset. |

No other runtime code, model, migration, API contract, or Flutter file changed for 5.6F.

## 5. Old vs New Seeding Behavior

| Aspect | Old | New |
|---|---|---|
| Sequence repair | `setval(pg_get_serial_sequence(...), COALESCE(MAX(id),1), MAX(id) IS NOT NULL)` | Detect `max(id)` and `pg_sequences.last_value`; if behind/unknown/boundary, advance with `nextval(CAST(:seq AS regclass))` until `>= max(id)` |
| Privilege required | Sequence `UPDATE` (+ USAGE/ownership context for setval) | Sequence `USAGE` only |
| Backward reset | `setval` could reset to max/id; code path was not intended to go backward but used setval | Never moves backward; only advances when needed |
| Empty table | setval to 1/false | No-op (`max_id is None`), normal sequence behavior preserved |
| Existing plans/IDs | Preserved by update/insert logic | Preserved; no ID rewrites, no deletes of catalog rows |
| Repeated startup | Idempotent upsert logic | Same idempotent upsert logic; sequence helper is safe on repeated runs |
| Boundary case | Exact setval | If `last_value == max(id)`, helper may advance by one extra value to avoid needing `is_called`; harmless, preserves existing IDs |

## 6. Safety / Correctness Properties

- **No `setval()`:** removed from runtime seeding path.
- **No backward sequence reset:** helper returns when sequence is already ahead; only `nextval` is used.
- **No duplicate plans:** existing catalog upsert/archive logic unchanged.
- **Preserves existing plan records/IDs/pricing/rules:** only sequence sync behavior changed; plan upsert still keyed by code/id as before.
- **Handles empty/populated tables:** empty returns no-op; populated repairs behind sequence.
- **Idempotent:** repeated `seed_subscription_plans()` safe; tests confirmed.
- **No runtime sequence UPDATE privilege required:** verified by restricted-role disposable DB test.

## 7. Tests Performed

| Test | Environment | Result | Evidence |
|---|---:|---|---|
| `tests/test_subscription_catalog.py` (10 tests) | Disposable `rupaywala_test` DB created by conftest on `rupaywala-pg18-validation` (127.0.0.1:55432), cleaned up | PASS | `10 passed` including `test_catalog_repairs_a_behind_postgres_id_sequence` |
| Compile check | Local venv | PASS | `python -m py_compile app/services/plan_catalog.py` |
| App-role seeding without sequence UPDATE | Disposable DB `rupaywala_stage56f_check` + temp role with USAGE-only on sequence, cleaned up | PASS | `setval_denied=true`, `app_seed_count=7`, IDs preserved, `repeat_count=7`, `insert_ok=true` |
| Behind-sequence repair without sequence UPDATE | Disposable DB `rupaywala_stage56f_check2` + temp role with USAGE-only, cleaned up | PASS | seeded 7, forced sequence behind as admin, restricted-role seeding repaired, normal insert `probe_id=8` succeeded |

## 8. Sequence Privilege Verification

Restricted-role check (disposable DB, temporary role `rw56f_app_nosequpd`, `USAGE` on `subscription_plans_id_seq`, no `UPDATE`):

- `setval(pg_get_serial_sequence('public.subscription_plans','id'), 1, false)` as app role: **DENIED** (`ProgrammingError`, permission denied).
- `seed_subscription_plans()` as app role: **PASS** (7 plans, IDs `[1..7]` preserved).
- Repeated seeding: **PASS** (count remained 7).
- Normal insert after seeding: **PASS** (`probe_id=9`, sequence-generated ID above max).

Behind-sequence case (temp role `rw56f_app_noseq2`, no sequence UPDATE):
- Sequence set behind as admin setup; restricted-role `seed_subscription_plans()` repaired sequence; insert succeeded (`probe_id=8`).

## 9. Existing Data Preservation

- No migration created; no plan table data rewritten outside normal upsert fields.
- Catalog seeding remains keyed by canonical codes/plan names as before.
- Existing subscription references are unaffected because plan IDs are not changed/reset.
- Sequence repair only advances forward; never resets backward.

## 10. Remaining Limitations / Blockers

| ID | Severity | Status | Notes |
|---|---|---|---|
| L-001 | Medium | Open | Full restricted-role API/E2E startup path not executed against disposable staging with `rupaywala_app`; only focused DB/pytest/script verification performed. |
| L-002 | Medium | Open | `tests/conftest.py` remains destructive by design; pytest should only be run with proven disposable DB isolation. |
| L-003 | Low | Open | `pg_sequences.last_value` visibility is sufficient for this fix; boundary case may advance sequence by one extra ID. Harmless but documented. |
| L-004 | High | Open (outside 5.6F scope) | Production infra/TLS/pg_hba/network/secret/backup/deployment validation still required before any production readiness claim. |
| L-005 | Medium | Open (deployment follow-up) | After deploying code removing `setval()`, staging/production role scripts should revoke `UPDATE` on `subscription_plans_id_seq` from `rupaywala_app` and revalidate. |

## 11. Final Assessment

- **`setval()` removed from runtime seeding:** Yes.
- **Repeated startup seeding works:** Yes.
- **App can operate without sequence UPDATE permission for seeding/inserts:** Yes (verified in disposable restricted-role DB).
- **Focused regression tests passed:** Yes.
- **Production readiness claimed:** No.
