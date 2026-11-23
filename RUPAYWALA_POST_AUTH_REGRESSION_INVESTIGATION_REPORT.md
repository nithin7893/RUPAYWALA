# RUPAYWALA — Post-authentication full regression investigation

Date: 2026-11-23
Scope: read-only investigation of all 46 failures from the full `pytest` suite after the
successful `0007_user_token_version` migration and authentication validation.
No production database access, no Alembic commands, no code changes were performed during this investigation.

## 1. Re-run evidence

Command:
```
.\venv\Scripts\python.exe -m pytest --tb=no -q
```

Result: **46 failed, 370 passed** (identical failure set to the previous run).
All failures are in `tests/test_stage5_security_remediation.py` (45) and
`tests/test_subscription_catalog.py` (1). **None are in `tests/test_auth.py`.**

## 2. Complete failure inventory (46)

### Group A — Google Maps HTTP 400 at quote creation (40 tests)

All of these fail at `_create_quote()` / `/service/quote` with:
`AssertionError: {"detail":"Google Maps returned an unexpected status"}` (400 instead of 201).

| # | Test |
|---:|---|
| 1 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_version_2_payload_covers_every_lifecycle_field` |
| 2 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_direct_status_modification_is_detected` |
| 3 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_direct_consumed_at_modification_is_detected` |
| 4 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_direct_cancelled_at_modification_is_detected` |
| 5 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_direct_service_request_id_modification_is_detected` |
| 6 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_consumed_quote_cannot_be_reactivated_by_database_tampering` |
| 7 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_tampered_quote_cannot_create_a_second_request` |
| 8 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_legitimate_consumption_updates_the_signature` |
| 9 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_legitimate_cancellation_updates_the_signature` |
| 10 | `tests/test_stage5_security_remediation.py::TestLifecycleIntegrity::test_legitimate_expiry_updates_the_signature` |
| 11 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_seven_decimal_coordinates_remain_valid` |
| 12 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_more_than_seven_decimals_are_normalized` |
| 13 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_persisted_and_signed_representations_match` |
| 14 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_negative_coordinates_work` |
| 15 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_boundary_coordinates_are_validated` |
| 16 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_quote_can_be_retrieved_after_persistence` |
| 17 | `tests/test_stage5_security_remediation.py::TestCoordinatePrecision::test_quote_can_be_consumed_after_persistence` |
| 18 | `tests/test_stage5_security_remediation.py::TestQuoteSigningSecret::test_legacy_quote_compatibility_is_verified_and_upgraded` |
| 19 | `tests/test_stage5_security_remediation.py::TestQuoteSigningSecret::test_legacy_quote_with_tampered_lifecycle_is_rejected` |
| 20 | `tests/test_stage5_security_remediation.py::TestExpiryRace::test_expiry_and_consumption_are_transactionally_consistent` |
| 21 | `tests/test_stage5_security_remediation.py::TestExpiryRace::test_expiry_cannot_overwrite_consumed_status` |
| 22 | `tests/test_stage5_security_remediation.py::TestExpiryRace::test_consumption_cannot_succeed_after_expiry` |
| 23 | `tests/test_stage5_security_remediation.py::TestExpiryRace::test_lifecycle_hmac_remains_valid_after_expiry` |
| 24 | `tests/test_stage5_security_remediation.py::TestExpiryRace::test_no_inconsistent_lifecycle_timestamps` |
| 25 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_quote_amount_is_copied_correctly` |
| 26 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_request_quote_reference_remains_associated` |
| 27 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_modified_request_amount_is_detected` |
| 28 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_payment_amount_matches_the_authoritative_quote` |
| 29 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_payment_currency_matches_the_quote_currency` |
| 30 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_approval_detects_tampered_request_pricing` |
| 31 | `tests/test_stage5_security_remediation.py::TestQuoteRequestPaymentIntegrity::test_legacy_request_without_a_quote_continues_to_work` |
| 32 | `tests/test_stage5_security_remediation.py::test_concurrent_quote_consumption_allows_exactly_one_request` |
| 33 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_a_forward_reference_removed_is_rejected` |
| 34 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_b_forward_reference_removed_and_amount_changed_is_rejected` |
| 35 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_c_approval_bypass_is_rejected` |
| 36 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_d_reverse_reference_corruption_is_rejected` |
| 37 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_e_cross_linked_references_are_rejected` |
| 38 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_f_quote_deletion_or_missing_association_is_rejected` |
| 39 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_h_normal_quote_backed_request_uses_signed_amount` |
| 40 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_i_concurrent_validation_and_database_constraints` |

### Group B — enum identity split after module purge / extra-charge request state 409 (4 tests)

| # | Test | Immediate error |
|---:|---|---|
| 41 | `tests/test_stage5_security_remediation.py::TestExtraChargeIntent::test_concurrent_intent_creation_produces_one_authoritative_intent` | workers return `HTTPException 409: This request is not awaiting an extra-charge payment` |
| 42 | `tests/test_stage5_security_remediation.py::TestExtraChargeIntent::test_existing_eligible_request_payment_remains_functional` | `HTTPException 409: This request is not awaiting an extra-charge payment` |
| 43 | `tests/test_stage5_security_remediation.py::TestExtraChargeIntent::test_duplicate_approval_does_not_charge_or_activate_twice` | `HTTPException 409: This request is not awaiting an extra-charge payment` |
| 44 | `tests/test_stage5_security_remediation.py::TestStage53QuoteAssociationBypass::test_g_genuine_legacy_request_keeps_legacy_workflow` | `HTTPException 409: This request is not awaiting an extra-charge payment` |

### Group C — payment idempotency expectation mismatch (1 test)

| # | Test | Immediate error |
|---:|---|---|
| 45 | `tests/test_stage5_security_remediation.py::TestPaymentIdempotency::test_existing_duplicate_history_is_never_deleted` | `assert <PaymentStatus.failed> == <PaymentStatus.pending>` |

### Group D — SQLite seeding concurrency (1 test)

| # | Test | Immediate error |
|---:|---|---|
| 46 | `tests/test_subscription_catalog.py::test_seed_subscription_plans_concurrent_startup` | worker threads: `sqlite3.OperationalError: no such table: subscription_plans` |

## 3. Root cause analysis

### Group C — payment idempotency expectation mismatch (test #45)

**Immediate cause.** The test inserts two `failed` subscription payments sharing
`idempotency_key="historical-key"` with past `expires_at`
(`tests/test_stage5_security_remediation.py:819-838`), then calls
`create_subscription_payment(..., idempotency_key="historical-key")` at `:841-843`.
`_reusable_intent` (`app/services/payment_service.py:264-274`) queries **all statuses**
for the same `(user_id, payment_type, idempotency_key)`, finds no payload mismatch, sees
no open candidate (`_OPEN_STATUSES` at `:239` excludes `failed`), and returns the most
recent terminal row at `:301`. No new row is inserted, so `fresh.status` is `failed`, not
`pending` (`:844`). A second stale expectation at `:853` expects 3 rows; 2 are correct.

**Root cause.** The test encodes pre-5.6G-1 behavior. The application contract was
deliberately changed so a reused key returns the original terminal payment idempotently
regardless of status (`app/services/payment_service.py:251-261`;
`RUPAYWALA_STAGE_5_6G1_PAYMENT_IDEMPOTENCY_REPORT.md:29-40,63-85`;
`RUPAYWALA_STAGE_5_6G3_PAYMENT_DB_INTEGRITY_REPORT.md:17,29,61-63`).
The regression test `tests/test_stage56g1_payment_idempotency.py:136-153` already asserts
the current behavior. A new attempt must use a **new idempotency key**.

**Classification: test defect (stale expectation).** No application defect and no
security-control weakness. History is still preserved; only the "fresh pending row"
expectation is obsolete.

**Recommended fix.** Update only the test:
- assert `fresh.id == max(ids)` and `fresh.status == PaymentStatus.failed`;
- change the row-count expectation from 3 to 2;
- keep the existing history-preservation assertions (`:854-857`);
- add a companion case with a **new** key (e.g. `"historical-key-retry"`) proving a fresh
  `pending` intent is still created while the two failed rows remain untouched.

**Do not** change `_reusable_intent` to ignore terminal keyed rows — that reverts the
5.6G-1 fix and reintroduces duplicate intents/QRs. **Do not** add an all-status unique
index — it breaks extra-charge terminal retries (G3 report).

**Files:** `tests/test_stage5_security_remediation.py:819-857` (required);
optional comment clarification in `app/models/payment.py:96-98` and
`app/services/payment_service.py:7-8`. No production code, schema, or data changes.

### Group D — SQLite seeding concurrency (test #46)

**Root cause.** Global-state leakage between test modules:

- `tests/conftest.py:87-126` correctly forces `DATABASE_URL` to the PostgreSQL
  `rupaywala_test` DSN before importing app modules, and guards `engine.url.database`.
  The `db` fixture session is therefore PostgreSQL.
- `tests/test_stage56i_security_containment.py:15-52` and
  `tests/test_stage56j_private_documents.py:16-66` overwrite `os.environ["DATABASE_URL"]`
  with a temporary SQLite URL and **reload all `app*` modules** via `_reload_app`, with no
  teardown restoration. Additional bare `_reload_app` calls occur throughout both modules.
- `tests/test_subscription_catalog.py:321` imports `SessionLocal` *inside* the test, so it
  resolves the mutated SQLite-bound module attribute. Worker threads at `:335` therefore
  use SQLite sessions while the fixture session remains PostgreSQL.
- `seed_subscription_plans` first touches the DB at `app/services/plan_catalog.py:240-243`.
  Its advisory lock is deliberately skipped for SQLite (`:227-233`), so all five workers
  hit `sqlite3.OperationalError: no such table: subscription_plans` and `assert errors == []`
  at `tests/test_subscription_catalog.py:355` fails.

Order-dependent: appears in default alphabetical collection, not necessarily in isolation.

**Classification: test defect / test-isolation leak.** Not an application defect and not a
configuration defect. The concurrency scenario is valid (guards the B56G-013 startup race)
and must keep its PostgreSQL semantics — `plan_catalog.py:227` skips the advisory lock on
SQLite, so switching workers to SQLite would stop testing the fix.

**Recommended fix.**
1. Minimal: in `tests/test_subscription_catalog.py:321,335`, create worker sessions from
   `sessionmaker(bind=db.get_bind(), ...)` so they always use the fixture's PostgreSQL bind.
2. Root cause: add autouse teardown in both SQLite modules to restore the exact captured
   `os.environ` values and `sys.modules["app*"]` objects (restore captured objects, not
   re-imports, or conftest references become invalid).
3. Optional hardening: autouse guard in `tests/conftest.py` asserting
   `sys.modules["app.database"].engine is engine`.

**Files:** `tests/test_subscription_catalog.py`, `tests/test_stage56i_security_containment.py`,
`tests/test_stage56j_private_documents.py`, optional `tests/conftest.py`. Optional stale
comment in `app/database.py:14`. No production code, config, or schema changes.

### Group A — Google Maps HTTP 400 at quote creation (40 tests, #1–40)

**Immediate cause.** Every affected test calls `_create_quote()`
(`tests/test_stage5_security_remediation.py:27-31,186`), which POSTs `/service/quote`.
Instead of 201 it receives 400 `{"detail":"Google Maps returned an unexpected status"}`.
The path is `app/routes/service_routes.py:526-538` → `QuoteService.create_quote` →
`_route_distance` (`app/services/quote_service.py:425,457-462`) → `_calculate_route`
(`:375-393`) → `maps.get_map_service()` (`:356-372`) →
`app/services/map_providers/google_maps.py:1058-1095` → real
`POST https://routes.googleapis.com/directions/v2:computeRoutes` (`:49`).
Unrecognised provider statuses become `MalformedProviderResponseError` (`:126-159`), which
`quote_service.py:389-391` translates into HTTP 400.

**Root cause: cross-test global-state pollution, not a broken quote feature.**

1. `tests/test_stage5_security_remediation.py:156-179` patches by **string**
   (`monkeypatch.setattr("app.services.quote_service._calculate_route", ...)` and the
   `service_routes._maps_guard`). Pytest resolves strings through the *current*
   `sys.modules`.
2. `tests/test_stage56i_security_containment.py:43-52` and
   `tests/test_stage56j_private_documents.py:58-66` call `_reload_app()`, which removes every
   `app`/`app.*` module from `sys.modules` and re-imports them. These files sort before
   `test_stage5_security_remediation.py`, so the patch targets the **new** module objects.
3. `tests/conftest.py:120-121` and the Stage 5 module hold the **original** module objects;
   the `client` fixture (`:227-241`) uses that original app. The patch misses the object the
   app actually calls.
4. `.env` has no `GOOGLE_MAPS_API_KEY`, so a clean process would return 503 from
   `_maps_or_503` (`quote_service.py:349-353`). The dummy key that makes the live call possible
   leaks from earlier Google test modules that call `importlib.reload()` on shared config/map
   modules while a fake key is set:
   `test_google_maps_stage1.py:25-50`, `test_google_geocoding_stage2.py:45-60`,
   `test_google_places_stage4.py:69-80,813-819`, `test_google_routes_stage3.py:44-55`.
   `importlib.reload` keeps the same module object, so fake credentials survive `monkeypatch`
   teardown.

**Classification: test defect + test-environment/config leakage.** No evidence of a genuine
defect in quote signing, coordinate precision, lifecycle HMAC, or PostgreSQL concurrency.
The pure signing tests that do not create quotes pass; only client/quote-creating tests fail.
Static review confirms fail-closed quote secrets, canonical numeric signing, HMAC lifecycle
re-signing, `SELECT … FOR UPDATE` consumption, and two-sided integrity checks.

### Group B — extra-charge 409 (4 tests, #41–44)

**Root cause: enum identity split from the same module purge.** `app/services/payment_service.py`
uses function-local imports of `ServiceRequest` at `:141`, `:474`, `:524`. After the
Stage 56I/J module purge, those imports resolve the post-purge (generation B) `RequestStatus`
enum, while the test row was created by `tests/factories.py:212-242` with the original
(generation A) enum. The guard at `app/services/payment_service.py:162` (and `:494`) compares
two distinct Python enum classes that happen to share a name, so the request is judged not to
be `payment_pending` and raises `HTTPException 409: This request is not awaiting an
extra-charge payment`.

**Classification: test-isolation defect.** The application guard is correct in a single
module-generation process. Not an application defect.

## 4. Classification summary

| Group | Count | Classification | Actual application defect? |
|---|---:|---|---|
| A — Maps 400 at quote creation | 40 | Test defect + test-environment credential leakage (`sys.modules` purge, string-based patching, `importlib.reload`) | No |
| B — extra-charge 409 | 4 | Test-isolation defect (dual enum classes after module purge) | No |
| C — payment idempotency | 1 | Test defect — stale expectation after intentional 5.6G-1 behavior change | No |
| D — SQLite seeding | 1 | Test-isolation defect — global `DATABASE_URL`/`sys.modules` leakage | No |
| **Total** | **46** | **All test/environment issues; zero application defects** | **No** |

None of the 46 failures are auth-related. The only genuine application changes noted are
non-blocking hardening opportunities (see §5), not causes of these failures.

## 5. Recommended fixes and files requiring changes

All required changes are **test-only**. No production code, no schema, no `.env`, and no
database data changes are needed to clear the 46 failures.

### Priority 1 — restore module/env isolation (fixes Groups A and B, 44 tests)

| File | Lines | Change |
|---|---|---|
| `tests/test_stage56i_security_containment.py` | `_reload_app` `:43-52`, fixture `:55-62`, bare calls at `:188-312` | Snapshot and restore `os.environ` and the exact `sys.modules["app*"]` objects per test; restore captured objects, never re-import. |
| `tests/test_stage56j_private_documents.py` | `_reload_app` `:58-66`, fixture `:69-76`, bare calls at `:241-245` | Same snapshot/restore of env and `sys.modules` per test. |

This removes the root cause of both the string-patch miss (Group A) and the dual `RequestStatus`
enum classes (Group B).

### Priority 2 — stop credential leakage from Google test modules (supports Group A)

| File | Lines | Change |
|---|---|---|
| `tests/test_google_maps_stage1.py` | `:25-50` | Replace `importlib.reload()` of shared config/map modules with `monkeypatch.setattr` on attributes and per-test fake HTTP clients. |
| `tests/test_google_geocoding_stage2.py` | `:45-60` | Same. |
| `tests/test_google_places_stage4.py` | `:69-80`, `:813-819` | Same. |
| `tests/test_google_routes_stage3.py` | `:44-55` | Same. |

### Priority 3 — make the Stage 5 stub patch the right objects (hardening for Group A)

| File | Lines | Change |
|---|---|---|
| `tests/test_stage5_security_remediation.py` | `stub_route` `:156-179` | Import `app.routes.service_routes` as a module at collection and patch object references directly (`monkeypatch.setattr(qs, "_calculate_route", fake)` using `qs` imported at `:47`, and the service_routes object) instead of string targets. |
| `tests/conftest.py` | near `:120-126` | Add an identity guard asserting the app/service modules in `sys.modules` match the objects the fixtures hold; optionally add a no-external-network guard for the PostgreSQL suite so a missed stub fails locally instead of calling Google. |

### Priority 4 — stale payment-idempotency test (Group C, 1 test)

| File | Lines | Change |
|---|---|---|
| `tests/test_stage5_security_remediation.py` | `:819-857` | Assert `fresh.id == max(ids)` and `fresh.status == failed`; change expected row count from 3 to 2; keep history-preservation assertions `:854-857`; add a companion case using a **new** idempotency key that creates a fresh `pending` intent. Do **not** change `_reusable_intent` or add an all-status unique index. |

### Priority 5 — SQLite seeding worker sessions (Group D, 1 test)

| File | Lines | Change |
|---|---|---|
| `tests/test_subscription_catalog.py` | `:321`, `:335` (+ import near `:5`) | Build worker sessions with `sessionmaker(bind=db.get_bind(), ...)` so they always use the fixture's PostgreSQL bind, independent of module reloads. |
| `tests/conftest.py` (optional) | near `:129-146` | Autouse guard asserting `sys.modules["app.database"].engine is engine`. |
| `app/database.py` (optional) | `:14` | Correct stale comment claiming SQLite is the primary test DB. |

### Optional, separate application hardening (not required for these failures)

Defer until after the suite is green and review as its own patch:
- `app/services/map_providers/google_maps.py:126-159` — explicit error mapping for credential/argument statuses.
- `app/services/map_service.py:568-583` — honour `MAP_PROVIDER` or remove dead config.
- `app/services/payment_service.py:141,474,524` — move function-local `ServiceRequest` imports to module scope to defensively avoid split-brain risk.
- `app/models/payment.py:96-98`, `app/services/payment_service.py:7-8` — clarify idempotency comments.

## 6. Risk assessment

- **Test-only isolation/patching fixes (Priorities 1–5): low risk.** No production behavior
  changes; all security assertions remain intact and PostgreSQL testing is preserved. Main
  care point: restoring captured `sys.modules` objects must be exact (not re-imports), or
  conftest's `app`, `get_db`, and engine references break.
- **Google credential leakage fix: low risk.** Must still allow the dedicated `test_google_*`
  unit tests to install their own fake transports; a global no-network guard is low-to-moderate
  risk and needs that exemption.
- **Payment idempotency test update: low risk.** No security control touched. Changing
  `_reusable_intent` instead would be **high risk** — reverts the 5.6G-1 fix, reintroducing
  duplicate intents/QR codes and ambiguous fulfilment. An all-status unique index is also
  **high risk** — breaks extra-charge terminal retries.
- **Optional application hardening: moderate risk.** Changes externally visible error codes
  or provider selection; requires its own regression pass with all `test_google_*` tests.
- **Environment risk:** `tests/conftest.py` is destructive by design (drops/recreates `public`
  and truncates tables on `rupaywala_test`). Never run against `.env` database `rupaywala_ori`.
- **Migration 0008: deferred, not part of this remediation.** Any future upgrade needs
  explicit authorization, verified backup, read-only prechecks, and an approved target.

## 7. Safe execution order

1. Confirm the disposable PostgreSQL test target (`rupaywala_test`) and that resetting its
   schema is acceptable. **Never** point tests at `rupaywala_ori`.
2. Apply Priority 1: restore `sys.modules`/env isolation in `test_stage56i_security_containment.py`
   and `test_stage56j_private_documents.py`.
3. Apply Priority 2: convert the four `test_google_*` modules from `importlib.reload()` to
   scoped `monkeypatch.setattr` + per-test fake clients.
4. Re-run `pytest tests/test_stage5_security_remediation.py -q` against PostgreSQL. Groups A
   and B should clear without weakening any assertion.
5. Apply Priority 3: object-based `stub_route` patching and conftest identity/no-network guards.
6. Apply Priority 4 (payment-idempotency test) and Priority 5 (worker sessions from
   `db.get_bind()`).
7. Re-run the full suite (`.\venv\Scripts\python.exe -m pytest -q`) in one process to prove
   order-independence; triage any genuinely residual failures.
8. Only after the suite is green, consider the optional application hardening as a separate,
   reviewed patch with its own `test_google_*` regression run.
9. Do not run Alembic commands, modify production data, or change authentication controls at
   any point in this remediation unless explicitly authorized in a new task.

## 8. Pending migration 0008 review

**No migration commands were executed during this investigation.** `0008_private_document_storage`
remains pending by design (the authorized scope was the minimal `0007` fix). The current
revision was previously verified as `0007_user_token_version`; read-only confirmation should
precede any future work.

**File:** `alembic/versions/0008_private_document_storage.py`

**Objects:** PostgreSQL enum `document_scan_status` (`PENDING, CLEAN, INFECTED, FAILED`);
tables `document_records` (17 columns, FKs to `users.id`) and `document_audit_logs`
(8 columns); 10 indexes; `service_requests.proof_document_id` nullable column; FK
`fk_service_requests_proof_document_id` with `ON DELETE SET NULL`.

**Additive:** yes — no row updates/deletes/backfills; tables start empty and the new column
is nullable. Downgrade is destructive (drops all 0008 objects) and remains untested.

**Historical failure and fix:** Stage 5.6L first attempt failed with
`DuplicateObject: type "document_scan_status" already exists` because generic `sa.Enum` with
`create_type=False` still triggered SQLAlchemy 2.0 auto-create. `transaction_per_migration=True`
(`alembic/env.py:55-58`) rolled back cleanly to `0007` with no partial objects. The current
file uses `postgresql.ENUM(..., create_type=False)`, a `pg_type`/`pg_enum` label pre-check, and
one explicit `SCAN_STATUS_ENUM.create(bind, checkfirst=True)` path (`:19-49`). The corrected
migration was successfully applied to `rupaywala_dev_stage56k` (Stage 5.6L1).

**Residual risks:** enum pre-check hard-codes schema `public`; no `IF NOT EXISTS` on
tables/indexes, so pre-existing partial objects abort the migration; `document_audit_logs.document_id`
has no FK (appears intentional for audit retention); offline `--sql` mode is not valid because
lines 28-41 query the live catalog; conftest builds schema from ORM metadata, not migrations,
so it does not validate 0008; no live document-persistence smoke on a migrated DB yet.

**Safe order if ever authorized:** confirm authorization + target identity read-only;
fresh verified `pg_dump -Fc` + `pg_restore -l`; verify `alembic current` and absence of
pre-existing 0008 objects; prefer an isolated disposable copy (e.g. already-migrated
`rupaywala_dev_stage56k` as reference); run only `alembic upgrade 0008_private_document_storage`
with process-only `DATABASE_URL` pinned to the approved target (no `stamp`, no downgrade);
post-check revision, enum labels/order, objects and unchanged row counts; then application
smoke. Restore from verified backup on failure only with authorization.

**Classification:** operational/deferred work, not a cause of any of the 46 test failures.

## 9. Authentication regression coverage review

**Files:** `tests/test_auth.py`, `tests/conftest.py`. Current coverage after the token-version
fix: 37 passing tests including the three new `TestTokenVersionInvalidation` regressions
(JWT `tv` issuance, logout increment + old-token invalidation, stale-`tv` rejection).

Covered: token validity (missing/garbage/wrong-secret/expired/deleted/suspended), role
separation, client-supplied role rejection, check-user disclosure limits, login success/failure,
`/auth/me` hygiene, username/password changes, OTP non-disclosure, conftest DB pinning and
safety guards.

**Gaps (not failures):** no tests yet for password-change/forgot-password reset invalidating
old tokens, legacy tokens without `tv`, malformed non-integer `tv`, cross-user isolation on
logout, concurrent logout/password-change increments, `tv` on Google/OTP login paths, or
`tv` interplay with expired/deleted/suspended tokens. These are coverage improvements only;
no evidence of an auth defect.

**Zero of the 46 failures are auth-related.** All 45 failures in
`tests/test_stage5_security_remediation.py` and the one seeding failure in
`tests/test_subscription_catalog.py` concern quotes, lifecycle HMAC, payments, or test
isolation. None touch login, JWT, `users.token_version`, login, or Alembic state.
The 37 auth tests continued to pass in every run.
