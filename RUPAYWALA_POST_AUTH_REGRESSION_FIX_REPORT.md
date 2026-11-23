# RUPAYWALA — Post-auth regression fix implementation report

Date: 2026-11-23
Scope: implementation of the approved four-stage test/environment remediation from
`RUPAYWALA_POST_AUTH_REGRESSION_INVESTIGATION_REPORT.md`.
All work was confined to test files. No production code, database data, schema,
migration state, authentication code, or JWT implementation was changed.

## 1. Outcome

| Metric | Before | After |
|---|---:|---:|
| Full pytest passed | 370 | **416** |
| Full pytest failed | 46 | **0** |
| Total tests | 416 | 416 |

No test was skipped, removed, or weakened. No assertion was relaxed to manufacture a
pass; the single assertion change is a correction of a stale expectation to the
documented 5.6G-1 contract, with an additional case added to preserve the original
business intent.

## 2. Files modified

| File | Stage | Nature |
|---|---|---|
| `tests/test_stage56i_security_containment.py` | 1, 2 | Test isolation (autouse restore fixture) |
| `tests/test_stage56j_private_documents.py` | 1, 2 | Test isolation (autouse restore fixture) |
| `tests/test_stage5_security_remediation.py` | 1, 3 | Object-based patching; stale expectation corrected and companion case added |
| `tests/conftest.py` | 1 | Google module-state restore fixture; external HTTP guard |
| `tests/test_subscription_catalog.py` | 4 | Worker sessions bound to the fixture's PostgreSQL engine |

Production files touched: **none**.
Alembic files touched: **none**.
`.env` touched: **none**.

Note: `tests/test_auth.py` already showed as modified in git before this task (from the
earlier token-version work). It was **not** edited during this implementation.

## 3. Exact changes

### Stage 1 — Test isolation and Google Maps mocking

**3.1 `tests/test_stage56i_security_containment.py:56-79` and
`tests/test_stage56j_private_documents.py:70-93`**

Added a module-level autouse fixture `_restore_app_modules()` that:

- snapshots every `sys.modules` entry named `app` or starting with `app.`, plus a copy of
  `os.environ`, before each test;
- after the test, removes any newly imported `app*` module objects and restores the
  **exact captured objects** (never re-imports), and restores only the environment keys
  that changed (removing keys that were added).

This keeps the config-reload tests' intent intact while preventing the reloaded modules
and their enum classes from leaking into the shared PostgreSQL suite.

**3.2 `tests/test_stage5_security_remediation.py:33,156-187`**

- Added `import app.routes.service_routes as service_routes` at module scope.
- Changed `stub_route` from string targets
  (`monkeypatch.setattr("app.services.quote_service._calculate_route", ...)` and
  `"app.routes.service_routes._maps_guard"`) to object targets using the module objects
  captured at collection (`qs` and `service_routes`). This guarantees the stub patches
  the same objects the `client` fixture's app calls.

**3.3 `tests/conftest.py:129-183`**

- Added `_GOOGLE_STATE_MODULES`, a session-scoped `_google_module_baseline` fixture, and
  an autouse `_restore_google_module_state` fixture. It snapshots the `__dict__` of
  `app.config`, `app.services.map_service`, `app.services.map_providers.base`, and
  `app.services.map_providers.google_maps` before any test mutates them, and restores
  them after every test. This prevents dummy `GOOGLE_MAPS_API_KEY` values set by
  `importlib.reload()` in the `test_google_*` modules from surviving into unrelated tests.
- Added a session-scoped autouse `_block_external_http` fixture that replaces
  `httpx.AsyncClient.request` with a guard raising
  `AssertionError("External HTTP call blocked during tests: ...")` for any host other
  than `localhost`, `127.0.0.1`, `::1`, or `testserver`, and restores the original on
  teardown. TestClient uses `httpx.Client`, so it is unaffected; the Google unit tests
  install their own fake clients via `svc._http`, so they are unaffected.

### Stage 2 — RequestStatus enum consistency

No additional change was needed. Stage 1's `sys.modules` restoration eliminates the
duplicate enum class identities at their source: application code and test fixtures now
reference the same generation of `app.models.service_request.RequestStatus`. The
production `payment_service.py` function-local imports were deliberately left untouched
(no production code change). HTTP 409 extra-charge protection is unchanged and still
asserted by the existing tests.

### Stage 3 — Payment idempotency test

`tests/test_stage5_security_remediation.py:847-880`:

- Replaced `assert fresh.status == PaymentStatus.pending` with
  `assert fresh.id == max(ids)` and `assert fresh.status == PaymentStatus.failed`,
  documenting the 5.6G-1 terminal-key idempotency contract.
- Changed the expected row count from 3 to 2 and added
  `assert [row.id for row in rows] == ids`.
- Kept the original history-preservation assertions unchanged.
- Added a companion case with a **new** idempotency key (`historical-key-retry`) proving a
  fresh `pending` intent is still created without modifying the two historical rows.

Payment processing logic (`_reusable_intent`, status handling, indexes) was not changed.

### Stage 4 — Database worker binding

`tests/test_subscription_catalog.py:318-345`:

- Replaced the in-test `from app.database import SessionLocal` with a `sessionmaker`
  created from `db.get_bind()`.
- Added explicit assertions that the worker bind is `postgresql` and targets
  `rupaywala_test`.
- Worker threads now call `WorkerSession()` instead of `SessionLocal()`.

The concurrency barrier, error collection, and all three postconditions (zero errors,
exactly 7 active plans, stable code→id map) are unchanged.

## 4. Tests executed after each stage

| Stage | Command (abridged) | Result |
|---|---|---|
| 1 | `pytest tests/test_stage5_security_remediation.py tests/test_stage56i_security_containment.py tests/test_stage56j_private_documents.py tests/test_google_{maps_stage1,geocoding_stage2,routes_stage3,places_stage4}.py` | 202 passed, 1 failed — the only failure was the known stale Stage 3 payment test. Final re-run of the same group after all stages: **203 passed**. |
| 2 | `pytest tests/test_stage5_security_remediation.py::TestExtraChargeIntent ...::test_g_genuine_legacy_request_keeps_legacy_workflow tests/test_auth.py` | **43 passed** (all four Group B tests plus all 37 auth tests). |
| 3 | `pytest tests/test_stage5_security_remediation.py::TestPaymentIdempotency tests/test_payments.py tests/test_stage56g1_payment_idempotency.py` | **41 passed**. |
| 4 | `pytest tests/test_subscription_catalog.py` | **11 passed**. |
| Final security/payment regression | `pytest tests/test_auth.py tests/test_payments.py tests/test_stage5_security_remediation.py tests/test_stage56g1_payment_idempotency.py` | **136 passed**. |
| Final isolation/Google/DB group | `pytest tests/test_google_* tests/test_stage56i_security_containment.py tests/test_stage56j_private_documents.py tests/test_subscription_catalog.py` | **151 passed**. |
| Final full suite | `pytest --tb=no -ra` | **416 passed in 252.58s**. |

Full-suite output is saved at
`C:\Users\NITHIN\AppData\Local\Temp\opencode\full_pytest_final.txt`.

## 5. Remaining failures

**None.** The full suite reports 416 passed, 0 failed, 0 skipped.

No genuine application defect was discovered during implementation; nothing required
escalation.

## 6. Security regression results

- All 37 `tests/test_auth.py` tests pass (including the three token-version regressions).
- All 45 `tests/test_stage5_security_remediation.py` tests pass, including lifecycle HMAC
  tamper detection, coordinate normalisation, quote signing, amount integrity, concurrency
  and extra-charge 409 protections.
- All payment idempotency tests pass (`test_payments.py`,
  `test_stage56g1_payment_idempotency.py`, `TestPaymentIdempotency`), with the keyed
  terminal-replay contract explicitly asserted.
- No security control, uniqueness constraint, HMAC assertion, or authentication check was
  disabled or relaxed.

## 7. Google Maps external-call verification

- The session-scoped `httpx.AsyncClient.request` guard raises on any non-local host.
- The complete suite passed with this guard active, which confirms no test attempted a
  real call to `https://routes.googleapis.com/directions/v2:computeRoutes` (or any other
  external endpoint).
- Google provider unit tests continue to use their own injected fake clients; their
  assertions were not modified.

## 8. PostgreSQL worker-session confirmation

- `test_seed_subscription_plans_concurrent_startup` now asserts
  `worker_bind.dialect.name == "postgresql"` and
  `worker_bind.url.database == "rupaywala_test"`.
- The worker `sessionmaker` is derived from `db.get_bind()`, i.e. the same engine the
  conftest guards at import (`engine.url.database == TEST_DB_NAME`).
- The test passes, confirming the five workers exercised the real PostgreSQL advisory-lock
  path rather than SQLite.

## 9. Production database and migration history

- No command was run against `rupaywala_ori` or any production/clone database.
- No Alembic command (`upgrade`, `downgrade`, `stamp`, `current`, `history`) was executed.
- Migration `0008_private_document_storage` remains pending by design; no migration file
  was edited.
- No users, business records, or schema objects in any preserved database were created,
  modified, or deleted.
- Test runs only used the disposable `rupaywala_test` database owned by `tests/conftest.py`,
  which is destructively reset by design.
