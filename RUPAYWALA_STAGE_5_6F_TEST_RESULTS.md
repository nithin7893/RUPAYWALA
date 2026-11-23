# RUPAYWALA STAGE 5.6F - Test Results

**Date:** 2026-11-21  
**Scope:** Stage 5.6F runtime sequence privilege hardening (`app/services/plan_catalog.py`)  
**Status:** **PASS (focused verification)**

## 1. Test Environment / Safety

- Validation container: `rupaywala-pg18-validation` (PostgreSQL 18.1, 127.0.0.1:55432).
- No changes made to `rupaywala_ori`, `rupaywala_validation`, or `rupaywala_role_validation`.
- Disposable DBs created and cleaned up:
  - `rupaywala_test` (pytest conftest, created/dropped schema by conftest; DB dropped after run)
  - `rupaywala_stage56f_check` (temporary restricted-role privilege test; dropped)
  - `rupaywala_stage56f_check2` (behind-sequence restricted-role repair test; dropped)
- Temporary cluster roles created and dropped: `rw56f_app_nosequpd`, `rw56f_app_noseq2`.
- Temp secret/script files in `C:\Users\NITHIN\AppData\Local\Temp\opencode` cleaned up.

## 2. Automated / Scripted Tests

| ID | Test | Command / Method | Expected | Actual | Result |
|---|---|---|---|---|---|
| T-001 | Compile changed module | `.\\venv\\Scripts\\python.exe -m py_compile app/services/plan_catalog.py` | Compiles | `COMPILE_OK` | PASS |
| T-002 | Existing subscription catalog tests | `.\\venv\\Scripts\\python.exe -m pytest tests/test_subscription_catalog.py -q` (DATABASE_URL pointed to validation container postgres DB; conftest used disposable `rupaywala_test`) | All pass | `10 passed` | PASS |
| T-003 | App-role seeding without sequence UPDATE | Disposable DB + temp role with `GRANT SELECT,INSERT,UPDATE,DELETE ON subscription_plans`, `GRANT USAGE ON subscription_plans_id_seq`, `REVOKE UPDATE ON subscription_plans_id_seq`; run seed/insert as role | `setval` denied; seeding/inserts/repeat idempotent | `setval_denied=true`, `app_seed_count=7`, `ids_preserved=true`, `repeat_count=7`, `insert_ok=true`, `probe_id=9` | PASS |
| T-004 | Behind-sequence repair without sequence UPDATE | Disposable DB seeded as admin, sequence forced behind with admin `setval`, then restricted role (no sequence UPDATE) ran `seed_subscription_plans()` and inserted probe | Repair works; insert succeeds | `behind_repair_insert_ok=true`, `probe_id=8` | PASS |

## 3. Requirement Coverage

| Requirement | Coverage | Result |
|---|---|---|
| Empty subscription-plan table | Helper no-op when `max(id)` is null; normal seed path still inserts canonical plans | PASS (covered by logic and prior catalog behavior; T-002/T-003 seed from schema-created DB) |
| Existing subscription plans | Catalog upsert/active/archive behavior unchanged | PASS (T-002) |
| Repeated startup seeding | Multiple seed calls do not duplicate or corrupt | PASS (T-002, T-003 repeat_count=7) |
| Sequence-generated IDs | Normal insert after seed works | PASS (T-003, T-004) |
| Sequence value after inserting plans | Probe inserts received IDs above max | PASS (probe_id 9 and 8) |
| Existing subscriptions referencing plans | No plan ID reset/backward movement; catalog IDs preserved | PASS (IDs preserved `[1..7]`; no setval backward reset) |
| No duplicate plan creation | Catalog count stable | PASS (T-002, T-003) |
| No accidental sequence reset | No `setval`; only forward `nextval` when needed | PASS (code inspection + T-003/T-004) |
| Seeding under app role with no sequence UPDATE permission | Restricted role with USAGE-only sequence | PASS (T-003, T-004) |
| `setval()` denied to app role | Explicit denied check | PASS (T-003 `setval_denied=true`) |

## 4. Key Evidence (Sanitized)

### T-002
```text
..........                                                               [100%]
10 passed
```

### T-003
```json
{
  "admin_seed_count": 7,
  "admin_seed_ids": [1,2,3,4,5,6,7],
  "setval_denied": true,
  "setval_error": "ProgrammingError",
  "app_seed_count": 7,
  "app_seed_ids": [1,2,3,4,5,6,7],
  "ids_preserved": true,
  "repeat_count": 7,
  "insert_ok": true,
  "probe_id": 9,
  "cleanup": true
}
```

### T-004
```json
{
  "seeded": 7,
  "behind_repair_insert_ok": true,
  "probe_id": 8,
  "cleanup": true
}
```

## 5. Not Run / Limitations

| Item | Status | Reason |
|---|---|---|
| Full pytest suite | NOT RUN | `tests/conftest.py` destructive; only targeted catalog tests run with proven disposable DB isolation |
| Full API/E2E startup under restricted `rupaywala_app` role | NOT RUN | Focused DB/script verification performed; full app stack not exercised in this stage |
| Production role revocation of `subscription_plans_id_seq` UPDATE | NOT EXECUTED | Code fix ready; deployment/role revocation is separate controlled change |

## 6. Result

**Stage 5.6F focused verification: PASS.** Runtime `setval()` removed from subscription plan seeding path, seeding works without sequence UPDATE, and restricted-role checks confirm `setval()` denied while normal inserts/seeding succeed.