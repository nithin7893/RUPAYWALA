# RUPAYWALA Stage 5.6M Remaining Blockers

## Overall Status

**PARTIAL PASS / NOT COMPLETE.** Isolated dev DB `rupaywala_dev_stage56k` is connected, backend startup/health/live CORS preflight/live auth smoke tests PASS. Actual Flutter browser login is NOT TESTED and not claimed.

## Blockers / Open Items

| ID | Blocker | Severity | Status | Evidence / Impact | Safe next action |
|---|---|---|---|---|---|
| B56M-001 | Actual Flutter browser login not verified | **High** | Open | Flutter config correct (`http://127.0.0.1:8000`), backend live, CORS live, auth API smoke PASS, but no real Flutter web browser login/dashboard/profile flow observed. | Run Flutter web (`flutter run -d chrome` or web-server+Chrome) against the running dev backend; perform real login in browser; inspect Chrome console and FastAPI logs; capture evidence. |
| B56M-002 | Backend process uses temp launcher / process-only env override | **Medium** | Open | Dev backend started via `C:\Users\NITHIN\AppData\Local\Temp\opencode\run_stage56m_backend.py` with process-only `DATABASE_URL`; `.env.stage56k` exists but `.env` untouched. This avoids fallback but is not a durable dev startup workflow. | Document/standardize a safe dev startup script that sets dev DB env explicitly and refuses to start if target DB is not `rupaywala_dev_stage56k`. Do not overwrite `.env` automatically. |
| B56M-003 | Full auth/regression suite not run on migrated dev DB | **Medium** | Open | Only scripted live auth smoke tests run. `tests/conftest.py` is destructive by design. | Create non-destructive migrated-schema test strategy or disposable test DB seeded from migrated schema. |
| B56M-004 | `rupaywala_ori` remains at `0005_fixed_quotes` (missing `token_version`) | **High** | Open | Original DB untouched by design. Production/original runtime still incompatible with 0007+ auth model. | After full dev validation including Flutter browser login: fresh verified backup, explicit authorization, controlled migration window for `rupaywala_ori` only. |
| B56M-005 | Subscription plan seeding only observationally PASS | **Low** | Open | No startup seeding error in logs; no explicit seeding result assertion performed. | Add explicit read-only/safe verification of subscription plan seeding state after startup on dev DB. |
| B56M-006 | Background backend process still running | **Low** | Informational | PID 3172 listening on 127.0.0.1:8000 using dev DB override. | Stop when no longer needed; ensure no accidental reuse for wrong DB context. |

## Cleared

| ID | Item | Status |
|---|---|---|
| C56M-001 | `rupaywala_dev_stage56k` identity/Alembic/schema pre-checks | PASS |
| C56M-002 | `.env` not overwritten; `.env.stage56k` prepared (gitignored) | PASS |
| C56M-003 | Backend startup on dev DB config, `/health` database connected | PASS |
| C56M-004 | No UndefinedColumn/missing-table startup errors observed | PASS |
| C56M-005 | Live CORS preflight for `localhost:60292` on running backend | PASS |
| C56M-006 | Live auth smoke tests (login, token, /me, logout, invalidation, invalid password) | PASS |
| C56M-007 | `rupaywala_ori` and `rupaywala_dev` untouched | PASS |

## Clear Classification

- **Automated/scripted live backend tests passed:** Yes (health, CORS preflight, auth smoke).
- **Live backend tests passed:** Yes (running FastAPI on 127.0.0.1:8000, dev DB).
- **Actual Flutter browser login passed:** **No / NOT TESTED**.
- **Not tested:** Actual Flutter browser flow, full pytest suite, existing customer credential login, full end-to-end non-auth flows.

**No production readiness claimed.**