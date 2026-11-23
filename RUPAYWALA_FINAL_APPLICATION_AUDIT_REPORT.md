# RUPAYWALA — Final application-wide production readiness audit

Date: 2026-11-23
Mode: **read-only audit**. No application code, database, migration state, or configuration
was modified. No Alembic command was executed. No secret values are reproduced in this report.

## 0. Baseline verification (executed during this audit)

Command: `.\venv\Scripts\python.exe -m pytest --tb=no -ra`

Result: **416 passed in 251.78s (0:04:11)** — confirms the stated baseline of
416 passing tests, 0 failures. Output saved to
`C:\Users\NITHIN\AppData\Local\Temp\opencode\final_audit_baseline.txt`.

## 1. Current development phase

**Stage 5.6M is documented as PARTIAL PASS / NOT COMPLETE**
(`RUPAYWALA_STAGE_5_6M_REMAINING_BLOCKERS.md:3-16,30-37`). The latest verified engineering
state is:

- Backend security/payment remediation (Stage 5.x) implemented; token-version migration 0007
  applied to `rupaywala_ori` with backup; auth validated; 416 pytest tests pass.
- 0008 private document storage is implemented in code and migrations but **pending** by design.
- Flutter client is substantially implemented across customer, field-member and admin roles,
  but Flutter analyze/test results are not evidenced and release artifacts are stale/unconfigured.
- External integrations (Google Maps live API, ClamAV, S3, UPI settlement) are not live-validated.
- No production packaging, deployment runbook, DR drill, or browser E2E proof exists.

Assessment: **advanced implementation / verification phase, not a production-release phase.**

**Evidence labels used in this report:** *Implemented* = real code path exists; *Tested* = direct
automated test evidence exists; *Partial* = gaps or inconsistent behavior; *Missing* = no code
found; *Not verified* = no execution evidence available.

## 2. Complete module inventory

| Component | Location | Count / contents |
|---|---|---|
| FastAPI core | `rupaywala_backend/app/{__init__,config,database,main}.py` | 4 files; 11 routers registered at `app/main.py:358-368` |
| Models | `app/models/` | 22 files (20+ registered in `app/models/__init__.py:8-28`) |
| Routes | `app/routes/` | 12 files, 11 functional routers, **108 router endpoints + 3 app-level = 111** |
| Schemas | `app/schemas/` | 10 files |
| Services | `app/services/` | 19 files incl. `map_providers/{base,google_maps}.py` |
| Utils | `app/utils/` | 8 files (auth deps, JWT, security, rate limit, OTP, SMS, upload) |
| Alembic migrations | `alembic/versions/` | 9 revisions; single linear head `0008_private_document_storage` |
| Backend tests | `tests/` | 16 files, 399 test functions; pytest collects **416** (parametrization) |
| Flutter client (canonical) | `C:\RUPAAY_WALA\rupaywala_mobile` | 74 `lib/` files, 8 test files (22 tests), 6 platform folders + `web/` |
| Flutter duplicate (stale builds) | `rupaywala_backend\rupaywala_mobile` | byte-identical `lib/`, older build outputs |
| Empty/legacy path | `C:\RUPAAY_WALA\rupaywala_app` | **0 entries** — not a project |
| DB artifacts | `database/`, `database_backups/` | role/bootstrap SQL + plans; 4 dump files (latest is pre-0007) |

Endpoint distribution: `/auth` 16, `/profile` 4, `/policies` 4, `/subscriptions` 13,
`/service` 15, `/payments` + `/admin/payments` 9, `/admin` 30, `/field-member` 10,
`/notifications` 5, `/documents` 3, app-level 3.

## 3. Backend implementation status

**Status: broadly implemented; test coverage strong on security-critical paths, weak on
several CRUD/notification services.**

- All 11 routers are registered (`app/main.py:358-368`) and all 111 endpoints have real
  implementations. No `NotImplementedError` or HTTP 501 stubs found.
- **Implemented/tested:** auth (16 endpoints, 37 tests including token-version regressions),
  service/quote workflow (15 endpoints; `test_fixed_quote_stage5.py` 60,
  `test_stage5_security_remediation.py` 63, `test_request_flow.py` 18, Maps 107),
  payments (9 endpoints; `test_payments.py` 26, `test_stage56g1_*` 10), subscriptions
  (`test_subscription_catalog.py` 11), documents (3 endpoints; `test_stage56j_*` 13),
  admin field members (`test_admin_field_members.py` 4) plus security containment suites.
- **Implemented but untested directly:** `profile_routes.py`, `policy_routes.py`,
  `notification_routes.py`; services `assignment_service.py`, `notification_service.py`,
  `email_service.py`, `google_auth_service.py`, `otp_service.py`, `sms_service.py`,
  `rate_limit.py`, `upload_service.py`.
- **Intentional placeholders:** `POST /subscriptions/subscribe` deliberately returns HTTP 410
  (activation occurs via payment verification) at `app/routes/subscription_routes.py:137-153`;
  `GET /profile/me` is a placeholder at `app/routes/profile_routes.py:102-111`.
- **Dead/unused:** `SubscriptionService.cancel`, `VisitService.usage_summary`,
  `SubscribeRequest`, legacy `MapplsService`/`OlaMapsService`, `upload_service.save_upload`.
- **Defect candidates:** profile update allows `profile=None` then dereferences `profile.id`
  (`profile_routes.py:120-124,157`); `payment.submitted_at` is populated from `verified_at`
  (`payment_routes.py:186,231`); service coordinate direction is inconsistent between
  explicit destination, nearest-branch batch and fallback paths
  (`service_routes.py:376-389,417-437`).
- **Documented gaps:** Redis/shared rate limiting (in-process only), push notifications
  (in-app only), automatic document retention purge, and live external integrations.
- Startup hook (`app/main.py:331-352`) skips work under `TESTING`; calls `create_all()` only
  under `DEBUG`; logs seeding errors without failing startup.

## 4. Mobile application status

**Canonical source:** `C:\RUPAAY_WALA\rupaywala_mobile` (most recent build activity).
`C:\RUPAAY_WALA\rupaywala_backend\rupaywala_mobile` is a byte-identical duplicate snapshot with
older build outputs; `C:\RUPAAY_WALA\rupaywala_app` is **empty** (0 entries). All three are
untracked and the root Git repo has no commits, so Git provides no canonical authority. This
duplication is itself a deployment hazard.

**Status: substantially implemented, partially tested, not release-ready.** Evidence is static
(audit did not run Flutter tooling because it writes build/dart tool caches):
- Real API layer (`lib/core/api/api_client.dart`, 8 repositories in
  `lib/core/api/repositories/`), secure token storage (`lib/core/api/token_store.dart`),
  session restore and role-specific shells (`lib/main.dart`,
  `lib/core/state/session_controller.dart`, `lib/features/shell/role_shell.dart`).
- Customer features: dashboard, policies, profile/account security, subscriptions (plans,
  family members, visits), payments (QR, UPI deep link, UTR submission, status polling),
  service requests (location search, signed quote, create/cancel/extra charge),
  notifications, authenticated document images.
- Field-member features: assignments, start/complete with proof upload, availability, stats.
- Admin features: dashboard, requests, assignment sheet, field team, payments, branches,
  distance rate, plans, maintenance.
- No TODO/FIXME/stub/no-op navigation or fake backend in `lib/`.
- Tests exist (`test/` — 8 files, 22 tests) but cover mainly auth controls, login flows,
  profile/password, payment screen, subscription models and two admin screens. Service
  requests, field tasks, most admin screens, notifications, session restore, API client,
  token store and web are untested. **No persisted `flutter analyze`/`flutter test` result log
  exists**; build cache timestamps suggest recent activity but passage is unverified.

**Defects/blockers:**
- **Release blocker:** `android/app/src/main/AndroidManifest.xml` lacks `INTERNET`
  permission; it exists only in debug/profile manifests, so a release APK cannot call the API.
- **Release blocker:** no production HTTPS configuration. `lib/core/config/app_config.dart:14-35`
  defaults to `http://127.0.0.1:8000` (or `10.0.2.2` on Android emulator); no runtime config
  mechanism beyond `--dart-define`.
- **High:** over-broad 401 handling clears tokens on a failed login password attempt
  (`api_client.dart:201-205`, `session_controller.dart:170-175`); session restore errors are
  stored but never surfaced (`main.dart:83-96`).
- **Medium:** fail-open role mapping defaults unknown roles to `customer`
  (`auth_models.dart:9-17`, `role_shell.dart:97`); unused `provider`/`go_router` dependencies;
  unused config values (`paymentPollInterval`, `qrExpiryMinutes`); no-op `includeInactive`
  flag in `admin_repository.dart:286-290`; iOS missing `LSApplicationQueriesSchemes` for UPI.
- Historical `flutter_01.log` records a web shader-compilation failure; unresolved.

## 5. Web application status

**Status: partial / stale, not deployment-ready.** There is no separate web application —
`web/` is the standard Flutter web shell for the same Dart codebase. The checked-in
`web/flutter_bootstrap.js` is the unexpanded template, `web/index.html` still says
“A new Flutter project”, and the generated `build/web/main.dart.js` is dated 30-10-2026, older
than current `lib/` sources, and still embeds `127.0.0.1:8000`. The generated build does use
local CanvasKit (`"useLocalCanvasKit":true`) to avoid the gstatic CDN, and fonts are aliased to
bundled Inter (`pubspec.yaml:61-74`), but no production base URL, no web-specific routing
(`go_router` is unused), and no verified fresh web build/test exist. Rebuild with
`--dart-define=API_BASE_URL=https://...` is required for any web deployment.

## 6. API integration status

**Status: paths and payloads broadly aligned; release blocked by client config and one auth defect.**

Eight frontend repositories in `rupaywala_mobile/lib/core/api/repositories/` call all 11 backend
routers registered at `app/main.py:358-368` through one `ApiClient`
(`lib/core/api/api_client.dart:37-46,51-103,162-217,249-274`) that injects Bearer tokens,
JSON-encodes bodies, decodes FastAPI `detail`, and handles 429 `Retry-After`. Document bytes are
fetched authenticated via `getBytes` (`api_client.dart:105-132`), matching the backend's
authenticated `/uploads/{path}` handler (`app/main.py:216-250`).

| Area | Integration status | Notes |
|---|---|---|
| Auth/session | **Aligned paths, defective logic** | 15 endpoints match; `/auth/email-login` contains critical OTP bypass (§7); `/check-user` unthrottled. |
| Profile/policies | **Aligned, untested** | `saveProfile` intentionally maps to backend upsert (`profile_routes.py:63`). No dedicated route tests. |
| Subscriptions/visits | **Aligned, tested** | 404 on current subscription handled as null (`subscription_repository.dart:19-26`). |
| Service/quotes/requests | **Mostly aligned** | Maps endpoints fail until key configured; extra-charge response is a reduced shape. |
| Payments | **Aligned, tested** | Low parse mismatch: `/payments/status/{txn_id}` returns `PaymentDetailResponse` without UPI/QR fields (`payment_schema.py:61-83`), parsed as `PaymentIntent` (`payment_repository.dart:55-58`); polling only reads `status`. |
| Admin | **Broadly aligned** | `includeInactive` flag is a no-op (`admin_repository.dart:286-290`). |
| Field member | **Aligned** | Multipart proof upload field split matches `field_member_routes.py:339-395`. |
| Notifications/documents | **Aligned** | Document auth model matches server-side ownership checks. |

**Client configuration blockers:** base URL is compile-time only with HTTP loopback defaults
(`lib/core/config/app_config.dart:15,26-35`); no runtime prod config; web build embeds
`127.0.0.1:8000` and predates current sources; iOS has no ATS configuration; Android release
manifest lacks `INTERNET` permission.

**Integration validation gap:** no evidence of Flutter browser/device E2E login or full
end-to-end payment/document flow against a deployed backend. Static alignment is not proof of
working functionality.

## 7. Security audit findings

**Controls implemented (with evidence):**
- HS256 JWTs with `exp`/`iat`/`jti` (`app/utils/jwt_handler.py:10-20`); every request reloads the
  user from the DB so deletion/suspension/role changes take effect immediately
  (`app/utils/dependencies.py:27-61`).
- `token_version` minted at `app/routes/auth_routes.py:86-92`, checked at
  `app/utils/dependencies.py:53-60`, incremented on logout, password change and OTP reset
  (`auth_routes.py:568,637,689`). bcrypt password policy and salted OTP digests with
  constant-time comparison (`app/utils/security.py:9-59`).
- Role dependencies and field-member approval checks (`app/utils/dependencies.py:64-105`);
  client cannot choose role (`auth_routes.py:333-338,392-402`). Ownership filters on policies,
  requests, payments, notifications, documents and subscriptions.
- Google ID-token verification via RS256/JWKS with audience, issuer and `email_verified`
  checks (`app/services/google_auth_service.py:44-145`).
- CORS allowlist with wildcard+credentials rejection, TrustedHost, HTTPS redirect, HSTS,
  CSP/security headers, docs disabled in production, generic HTTP errors
  (`app/config.py:216,221-265,356-397`; `app/main.py:91-158,253-271`).
- Upload validation (extension allowlist, size cap, magic bytes, random filenames, path
  containment) and authenticated retrieval with ownership/traversal checks
  (`app/utils/upload_service.py:31-86`; `app/services/document_service.py:149-191,219-289`;
  `app/main.py:162-250`).
- No SQL injection, unsafe deserialization, upload traversal, or blanket missing-auth
  dependency on a mutating route was found.

**Tested:** token validation, role separation, role escalation rejection, login/`me`,
username/password change, OTP non-disclosure, token-version logout invalidation, production
docs/CORS/trusted-host/security-header behavior, and document authorization/traversal cases
(`tests/test_auth.py:28-380`; `tests/test_stage56i_security_containment.py:149-342`;
`tests/test_stage56j_private_documents.py:177-482`).

**Critical finding (independently verified during this audit):**
- **C-01 — `/auth/email-login` can issue a token without verifying the submitted OTP.**
  `app/routes/auth_routes.py:269-282` first looks for *any* prior `OTPVerification` row with
  `purpose == email_login` and `verified == True`; if one exists it uses it directly and skips
  `OTPService.verify_email()` entirely. The proof query has no expiry or `is_used` filter, and
  `OTPService.verify_email` sets `verified = True` but never `is_used = True`
  (`app/services/otp_service.py:244-250,279-281`; contrast phone verification at `:232-236`).
  Consequently, once any email-login OTP has been verified, any party knowing the email can
  POST an arbitrary OTP value and receive a full access token
  (`auth_routes.py:283-291`). **Account takeover.** No test covers this path.

**High findings:**
- **H-01 — Rate limiting trusts client-supplied `X-Forwarded-For` unconditionally**
  (`app/utils/rate_limit.py:42-47,58-66`). `TRUST_PROXY_HEADERS`/`TRUSTED_PROXY_IPS`
  (`app/config.py:266-271`) are never consulted. Affects login, OTP, email login,
  password reset and payment routes; headers can be rotated to bypass throttles and create
  unbounded in-memory buckets.
- **H-02 — Email OTP is replayable** because verification never marks it used
  (`app/services/otp_service.py:279-281` vs `:232-236`); repeated verification succeeds until
  expiry. No test covers this.

**Medium findings:**
- **M-01 — HTTPS/HSTS can be influenced by spoofed `X-Forwarded-Proto`** when proxy trust is
  enabled; source IP is never validated (`app/main.py:112-124,140-147`).
- **M-02 — Unauthenticated account enumeration** via `/auth/check-user`, which returns
  `exists`/`has_password` with no rate limit (`app/routes/auth_routes.py:115-132`).
- **M-03 — Registration OTP proof has no expiry/session binding**; phone proof checks
  `verified`/`is_used` but not `expires_at`, email proof checks neither
  (`auth_routes.py:302-318,354-363`). Registration has no rate limit.

**Low findings:** 12-hour access tokens with only global revocation; `/auth/google` has no
rate limit and the JWKS cache has no TTL (`app/services/google_auth_service.py:27,45-58`);
malware scanning defaults off (`app/config.py:311`); internal error details are logged
verbatim (`app/main.py:256-271`).

**Auth coverage gaps (no tests):** email OTP login (contains C-01), Google sign-in, rate
limiting/429 behavior, password-change/reset token invalidation, malformed `tv` claims, OTP
expiry/lockout/purpose separation, HTTPS/HSTS behind a proxy, stale registration proofs,
field-member approval states, and successful authenticated proof upload.

## 8. Payment workflow findings

**Status: mostly implemented and tested.**

- Quote integrity core is implemented and covered: dedicated signing secret with fail-fast
  validation (`app/config.py:80-121`, `app/services/quote_service.py:49-52`), v2 lifecycle HMAC
  over state/pricing/coordinates/request linkage (`:92-217,234-263`), coordinate normalization
  (`:82-89,265-282,396-417`), row-locked expiry/consumption (`:527-744`), two-sided quote/request
  amount binding (`:749-865`), and legacy v1 verification/upgrade (`:187-217`).
  Evidence tests: `tests/test_stage5_security_remediation.py:246-655,1042-1286,1421-1647,1653-2061`
  and `tests/test_fixed_quote_stage5.py:543-1019`. No correctness defect found in this core.
- Payment idempotency is implemented and covered: keyed intent reuse, terminal-key replay,
  key/user/purpose mismatch rejection, cross-user rejection (`app/services/payment_service.py:241-350`;
  `tests/test_stage56g1_payment_idempotency.py:19-182`;
  `tests/test_stage5_security_remediation.py:661-884`). Extra-charge intents/admin approval
  (`:138-232,472-541`), UTR duplicate detection and concurrency (`:356-420`), and admin
  verification/activation (`app/routes/payment_routes.py:239-278`) are covered.
- Database guards: partial unique payment/UTR indexes (`app/models/payment.py:92-121`,
  `alembic/versions/0006_stage5_security_remediation.py:108-147`) and global `IntegrityError` →
  HTTP 409 mapping (`app/main.py:256-262`).
- Subscription catalog seeding/sequencing/concurrency is implemented and tested
  (`app/services/plan_catalog.py:171-293`; `tests/test_subscription_catalog.py:32-73,318-367`).
- QR/UPI payload generation exists (`app/services/payment_service.py:52-64,131-135,235-237`) but
  has only basic coverage (`tests/test_payments.py:38-46`). **Live UPI settlement is not
  implemented/locally verifiable** (`RUPAYWALA_STAGE_5_6G1_PAYMENT_IDEMPOTENCY_REPORT.md:100`).
- Request workflow state graph and transition enforcement
  (`app/services/request_status_service.py:15-48,69-81`), assignment eligibility/locking
  (`app/services/assignment_service.py:34-117`), field completion/proof association
  (`app/routes/field_member_routes.py:371-384`), and visit consumption/refund idempotency
  (`app/services/visit_service.py:145-223`) are implemented but only partially covered
  (`tests/test_request_flow.py:39-298`). Proof-document association has no direct coverage in
  the named tests.

**Findings:**
- **Medium** — a wrong `request_id` can be persisted before extra-charge validation fails.
  The route compares `payment.related_request_id` only after `submit_payment` commits the UTR
  (`app/routes/service_routes.py:788-811`, `app/services/payment_service.py:406-420`). A same-user
  caller can attach a UTR to the wrong request before receiving HTTP 400. Not covered by tests.
- **Medium** — unkeyed concurrent subscription intents can duplicate. The no-key fallback in
  `_reusable_intent` has no row lock and the partial unique index applies only when
  `idempotency_key IS NOT NULL` (`app/services/payment_service.py:77-128,330-350`,
  `app/models/payment.py:99-109`, `0006:127-136`). Not covered by tests.
- **Low** — dead `PaymentCreateRequest.validate_purpose` has no validator decorator
  (`app/schemas/payment_schema.py:18-21`); real validation is at `payment_routes.py:60-67`.
- **Low** — `consume_for_request` docstring disagrees with its expiry-branch commit
  (`app/services/quote_service.py:606-612` vs `:648-653`); behavior is covered by tests.

## 9. Database and migration status

**Reported state (from repository documentation only — no live DB was contacted):**
`rupaywala_ori` is at `0007_user_token_version`, one revision behind head
(`RUPAYWALA_TOKEN_VERSION_MIGRATION_FIX_REPORT.md:76,81,108`). `0008_private_document_storage`
is the single head and is intentionally pending. `rupaywala_dev_stage56k` is reported at
`0008` and was used to validate the corrected enum handling.

**Migration chain (single linear head):**
`0001_initial_schema` → `0002_expand_enums` → `0003_visit_credits_lifecycle` →
`b96aae0ed4c8` → `0004_subscription_entitlements` → `0005_fixed_quotes` →
`0006_stage5_security_remediation` → `0007_user_token_version` →
**`0008_private_document_storage` (head)**.
Note: the `0003` filename contains `_and_lifecycle` while its revision ID is
`0003_visit_credits_lifecycle` (`alembic/versions/0003_visit_credits_and_lifecycle.py:43-44`).

**0008 scope (pending):** creates `document_scan_status` enum, `document_records`,
`document_audit_logs`, 10 indexes, `service_requests.proof_document_id` plus FK
(`0008_private_document_storage.py:19-103`). Additive, no backfill, nullable column.
Its historical `DuplicateObject` enum-creation failure was fixed and validated on the
disposable staging DB; the current file uses `postgresql.ENUM(create_type=False)` with a
catalog pre-check and a single explicit create path (`:19-49`).

**Session/schema ownership:** one engine from `DATABASE_URL` at import
(`app/database.py:6-23`); `get_db()` yields/closes without explicit commit/rollback
(`:28-33`). Alembic `env.py` uses `transaction_per_migration=True` (`:47-59`), no `SET ROLE`;
the documented `rupaywala_owner`/`rupaywala_migrator`/`rupaywala_app` role model was applied
only to disposable staging, not production
(`RUPAYWALA_STAGE_5_6H_DEPLOYMENT_CHECKLIST.md:28`).

**Risks:**
- **High:** application code already expects 0008 objects (document routes/models), so
  those runtime paths would fail on a pre-0008 database — same failure class as the 0007
  `UndefinedColumn` incident.
- **High:** `b96aae0ed4c8` unconditionally drops `activity_logs`
  (`b96aae0ed4c8_add_email_otp_support.py:21`), so a fresh `upgrade head` from empty breaks;
  a disposable bootstrap procedure exists but is not part of normal deployment.
- **Medium:** 0008 downgrade is destructive and untested; offline `--sql` mode is unusable
  because several revisions query the live catalog; enum handling is schema-`public`-specific.
- **Medium:** model/migration drift — `User.token_version` has Python default but no
  `server_default` (`app/models/user.py:59` vs `0007:25`); `SIGNATURE_VERSION = 2` in the model
  vs DB default `1` (`app/models/service_quote.py:46,69-70` vs `0006:96`).
- **Medium:** tests build the schema from ORM metadata, not Alembic revisions
  (`tests/conftest.py:199-206`), so migrations are not validated by pytest. Startup
  `create_all()` under `DEBUG` (`app/main.py:336-343`) can also mask drift.
- **Medium:** no fresh post-0007 verified backup of `rupaywala_ori` exists in
  `database_backups/`; the available dump is pre-0007. A new verified dump is required before
  any further migration.
- **Low:** `document_audit_logs.document_id` has no FK and `document_records.storage_key` is
  not unique (design choices to confirm); stale `.pyc` and legacy raw-SQL scripts remain in the tree.

**No Alembic command, database connection, or schema change was performed in this audit.**

**Safe sequence if 0008 is ever authorized:** explicit written authorization for a named
target → read-only identity/revision gate → fresh verified `pg_dump -Fc` + `pg_restore -l` →
read-only absence pre-checks for 0008 objects → isolated rehearsal on a disposable copy →
`alembic upgrade 0008_private_document_storage` only (not `head`, no `stamp`, no downgrade) →
post-checks for revision, enum labels, objects and unchanged row counts → authenticated
document upload/retrieval smoke test → on failure stop and restore from the verified backup
only with authorization.

## 10. Google Maps integration findings

**Status: implemented and mocked-tested; not live-validated.**
- Google provider implements geocoding, Routes (`computeRoutes`, `computeRouteMatrix`) and
  Places (New) autocomplete/details (`app/services/map_providers/google_maps.py:76-1254`),
  exposed through service routes (`app/routes/service_routes.py:298-335,358-459`).
- TTL caching (4 caches, successful-only, stale eviction), bounded retries for transient
  failures, typed error hierarchy and provider→HTTP translation are implemented
  (`app/services/map_providers/base.py:25-66,157-183`; `google_maps.py:81-84,161-215,288-350`;
  `service_routes.py:64-88`; `quote_service.py:349-393`). Tests `test_google_*` mock all HTTP.
- **High (deployment):** no live Google API validation has been performed; the active stage
  environment is documented as having no `GOOGLE_MAPS_API_KEY`, so `/health` reports
  `configured=false` and map-dependent quote endpoints return 503
  (`RUPAYWALA_STAGE_5_6G4_EXTERNAL_INTEGRATION_REPORT.md:15,26-28`).
- **Medium:** `MAP_PROVIDER` is dead config — loaded at `app/config.py:176`, imported at
  `app/services/map_service.py:26`, never read; `get_map_service()` hardcodes `"google"`
  (`:574`), and a test even asserts that setting `mappls` still selects Google
  (`tests/test_google_maps_stage1.py:84-91`).
- **Medium:** auth/billing/quota errors (`InvalidCredentialsError`, `BillingOrQuotaError`) are
  not `MapProviderUnavailable`, so guards return HTTP 400 with provider-derived text instead
  of 503; `/health` reports configured on key presence alone
  (`base.py:37-55`; `service_routes.py:78-86`; `map_service.py:588-594`).
- **Low:** dead Mappls/Ola provider code and legacy TTL config remain
  (`map_service.py:95-559`; `config.py:185-200`); the 60 s `run_async` future timeout is not
  handled by the route guards (`base.py:150-154`).

## 11. Document storage findings

**Status: largely implemented, partially tested, gated on pending migration and external services.**
- Implemented and tested: extension/size/empty validation, MIME/magic-byte checks, random
  filenames, path containment, authenticated retrieval with ownership/traversal checks,
  local + S3 storage abstraction with signed URLs, audit-log model and events, proof-image
  upload route (`app/services/document_service.py:49-191,219-297,300-491`;
  `app/services/document_storage.py:43-199`; `app/routes/field_member_routes.py:339-395`;
  `tests/test_stage56j_private_documents.py:215-412`).
- **High (deployment blocker):** code already requires 0008 objects (`DocumentRecord`,
  `DocumentAuditLog`, `service_requests.proof_document_id`, `/uploads` handler) while the
  reported production revision is `0007` — see §9. Some older reports still say `0005`; the
  newer token-version fix report is authoritative. Document runtime would fail on a
  pre-0008 database.
- **High:** malware scanning defaults off (`MALWARE_SCAN_ENABLED=false`) and such uploads are
  recorded `CLEAN` with `scan_disabled`, while retrieval gates on `CLEAN`; no real ClamAV test
  exists (`app/config.py:311`; `document_service.py:82-83,359-370`).
- **High:** field-member proof access does not check assignment status — `can_access` and the
  legacy `/uploads` path match any assignment row, including `unassigned`/`cancelled`/`rejected`
  (`document_service.py:307-319`; `app/main.py:200-212`; `app/models/request_assignment.py:20-24`).
- **Medium:** audit rows for rejected uploads/storage failures are flushed but never committed,
  so they roll back (`document_service.py:204-217,231-244`; `app/database.py:28-33`).
- **Medium:** retention is retrieval-time only — `expires_at` is enforced but no purge job
  exists and `DOCUMENT_RETENTION_DAYS=0` disables even metadata expiry
  (`config.py:317-318`; `document_service.py:246-248,291-297,335-346`).
- **Low:** S3 signed URL uses `ResponseContentDisposition: inline` and bypasses the
  `nosniff` header applied to streamed content (`document_storage.py:173-186`); client MIME is
  allowlisted but not cross-checked with extension/signature; dead duplicate
  `app/utils/upload_service.py:31-86` (`save_upload` has no callers).
- Real S3, ClamAV, web Flutter proof rendering and the 0008 PostgreSQL migration path are
  **not verified**; the SQLite document tests use `Base.metadata.create_all`, not Alembic.

## 12. Critical and high-priority defects

### Critical

| ID | Defect | Evidence | Impact |
|---|---|---|---|
| **C-01** | `/auth/email-login` issues a full access token without validating the submitted OTP when any prior verified `email_login` OTP row exists. Query has no expiry/`is_used` filter; `verify_email` sets `verified=True` but never `is_used=True`. **Independently verified by direct code inspection during this audit.** | `app/routes/auth_routes.py:269-291`; `app/services/otp_service.py:244-250,279-281` (contrast phone `:232-236`) | **Account takeover** for any account whose email OTP was ever verified. No test covers it. |
| **C-02** | Android release build has no `INTERNET` permission; it exists only in debug/profile manifests. | `android/app/src/main/AndroidManifest.xml`; `.../debug/AndroidManifest.xml:6`; `.../profile/AndroidManifest.xml:6` | Release APK cannot reach the API. |

### High

| ID | Defect | Evidence |
|---|---|---|
| **H-01** | Rate limiter trusts client-supplied `X-Forwarded-For` and ignores `TRUST_PROXY_HEADERS`/`TRUSTED_PROXY_IPS`; affects login, OTP, email login, password reset and payment routes; unbounded bucket keys. | `app/utils/rate_limit.py:42-47,58-66`; `app/config.py:266-271` |
| **H-02** | Email OTP verification never marks the code used, so it is replayable until expiry. | `app/services/otp_service.py:279-281` vs `:232-236` |
| **H-03** | Production network target undefined: HTTP localhost/emulator defaults, compile-time-only override, stale web bundle with `127.0.0.1:8000`, no iOS ATS config. | `lib/core/config/app_config.dart:15,26-35`; `build/web/main.dart.js`; `ios/Runner/Info.plist` |
| **H-04** | Pending 0008 while code already depends on its tables/column/FK; document endpoints would fail on the reported `0007` DB. | `alembic/versions/0008_...py:19-103`; `app/models/document_record.py`; `app/main.py:227-242`; §9 |
| **H-05** | No production packaging/runtime configuration: no Dockerfile, compose, CI/CD, process manager, nginx config, or release runbook; in-process rate limiter only; local storage defaults. | File enumeration; `requirements.txt`; `app/utils/rate_limit.py:9-20` |
| **H-06** | Malware scanning off by default yet uploads marked `CLEAN`; field-member proof access ignores assignment status. | `app/config.py:311`; `app/services/document_service.py:82-83,307-319,359-370`; `app/main.py:200-212` |
| **H-07** | No live Google Maps validation; active environment lacks a Google API key, so map-dependent quotes return 503. | `RUPAYWALA_STAGE_5_6G4_EXTERNAL_INTEGRATION_REPORT.md:15,26-28`; `app/services/quote_service.py:349-353` |

### Medium (selected)

- **M-01** wrong extra-charge `request_id` can be committed before validation fails
  (`service_routes.py:788-811`; `payment_service.py:406-420`).
- **M-02** unkeyed concurrent subscription intents have no lock/constraint, so duplicates are
  possible (`payment_service.py:77-128,330-350`; `app/models/payment.py:99-109`).
- **M-03** HTTPS redirect/HSTS influenced by spoofed `x-forwarded-proto` when proxy trust is
  enabled (`app/main.py:112-124,140-147`).
- **M-04** `/auth/check-user` enables unthrottled account enumeration (`auth_routes.py:115-132`).
- **M-05** registration OTP proof accepts stale/expired records; registration unthrottled
  (`auth_routes.py:302-318,354-363`).
- **M-06** `MAP_PROVIDER` is dead config; Google is hardcoded (`config.py:176`; `map_service.py:574`).
- **M-07** audit rows for rejected uploads/storage failures are flushed but never committed
  (`document_service.py:204-217,231-244`).
- **M-08** retention is retrieval-time only; no purge job; `DOCUMENT_RETENTION_DAYS=0` default
  (`config.py:317-318`).
- **M-09** profile update allows `profile=None` then dereferences it
  (`profile_routes.py:120-124,157`).
- **M-10** over-broad 401 handling clears tokens on failed login; session restore errors are
  stored but never displayed (`api_client.dart:201-205`; `session_controller.dart:170-175`;
  `main.dart:83-96`).
- **M-11** 0008 downgrade untested/destructive; offline SQL mode unusable; `b96` breaks fresh-chain
  upgrades (§9).

Low-severity items (dead code, doc drift, parse mismatches, scaffold metadata, `.env.example`
key-name mismatch) are noted in §§3, 6, 10, 11.

## 13. Deployment blockers

1. **Security gate:** C-01 must be fixed and regression-tested before any public deployment.
2. **Mobile release:** C-02 (INTERNET permission), H-03 (HTTPS production base URL, fresh web build,
   iOS ATS) and M-10 (401/session handling) must be resolved and artifacts rebuilt.
3. **Database:** explicit authorization for 0008 on a named target, fresh verified backup,
   read-only revision/object pre-checks, isolated rehearsal, then apply only
   `0008_private_document_storage` (§9). Note that some older reports still claim `0005`;
   the newer token-version report is authoritative — verify live revision read-only before acting.
4. **External services:** provision Google Maps API key with Geocoding/Routes/Places enabled and
   billing, ClamAV/clamd with `MALWARE_SCAN_ENABLED=true`, private S3 bucket/credentials, and
   perform real live/smoke validation of each. UPI settlement/reconciliation is not implemented
   locally and remains an external dependency.
5. **Operations:** production deployment package (container/process manager/reverse proxy),
   explicit production env configuration, secret manager, TLS, trusted-proxy settings,
   backup schedule + offsite copy + restore drill, RPO/RTO and rollback runbook.
6. **Validation:** browser/device E2E login and end-to-end payment/document flows;
   `flutter analyze`, `flutter test`, fresh Android/iOS/web builds; security regression suite
   against a deployed staging environment.
7. **Hygiene:** close the unkeyed payment intent race, field-member proof status filter, audit
   commit gap, retention purge, and stale/duplicate Flutter directories before scale-up.
8. **Version control:** root repo has no commits and both backend and mobile trees contain
   modified/untracked files — not release-clean.

## 14. Recommended final execution sequence

1. **Freeze scope and record a release checklist** referencing this report; obtain written
   authorization for each production-impacting step (especially any migration).
2. **Fix and test C-01 and H-02** (email-login OTP verification, expiry, single-use) with new
   negative tests; then H-01/H-03 proxy and rate-limit hardening with 429/trusted-proxy tests.
3. **Fix M-01/M-02/M-04/M-05/M-07/M-09/M-10** and add focused regression tests; keep the
   existing 416-test baseline green.
4. **Prepare the DB:** read-only revision verification → fresh verified backup → 0008 rehearsal
   on an isolated copy → authorized apply of 0008 only → post-checks and document smoke test.
5. **Provision and live-validate external services:** Google Maps, ClamAV, private S3, UPI/UPI
   settlement path; confirm `/health` reports configured and map-dependent quotes succeed.
6. **Client release work:** add Android release INTERNET permission, production HTTPS base URL
   via build configuration, iOS ATS/UPI scheme settings, fresh web build without localhost;
   run `flutter analyze`, `flutter test`, and device/browser E2E login + quote/payment/document flows.
7. **Deployment engineering:** container/process packaging, reverse proxy/TLS, trusted-proxy and
   CORS/trusted-host production values, secret manager, rate-limit strategy for multi-instance
   operation, backup/DR runbook and restore drill.
8. **Final verification gate:** full pytest 416+ passing on the release candidate configuration,
   37 auth tests green, security/payment regression green, no external calls from tests, and
   signed-off staging smoke results. Only then schedule a controlled production rollout with
   monitoring and a tested rollback path.

No step above was executed during this audit.

## 15. Overall production-readiness assessment

**Verdict: NOT PRODUCTION READY — do not ship.**

| Area | Status |
|---|---|
| Backend feature implementation | **Implemented** — 111 endpoints, all registered; no stubs |
| Backend automated verification | **Tested** — 416 passing pytest tests, strong security/payment coverage; notable untested CRUD/notification services |
| Authentication/authorization | **Partially implemented / defective** — solid JWT, roles and token-version controls, but critical email-login OTP bypass and rate-limit/proxy flaws |
| Payment/quote workflows | **Implemented/tested** — idempotency, HMAC, amount binding, concurrency controls; live UPI settlement external/unverified |
| Database/migrations | **Partially deployed** — reported at 0007, 0008 pending; fresh-chain and offline-mode hazards; backup gap |
| Maps integration | **Implemented/mocked-tested, not live-validated** |
| Document storage | **Implemented/partially tested, gated on 0008, malware scan off, access-status gap** |
| Flutter mobile | **Substantially implemented, not release-configured, tests unverified** |
| Flutter web | **Partial/stale — not deployable as built** |
| API integration | **Broadly aligned statically, no E2E proof** |
| Deployment/operations | **Missing** — no packaging, runbook, DR drill, or production env |

The engineering core is strong: the security-critical backend paths have real tests and the
frontend is a substantial, non-placeholder implementation. Release readiness is blocked by one
confirmed critical authentication defect, one release-breaking mobile manifest defect,
undefined production network configuration, a pending migration that code already depends on,
unvalidated external integrations, and absent deployment/DR operations.

**Confidence note:** claims above are based on static inspection plus the pytest baseline that
was actually executed during this audit (§0). No Flutter, live Google, ClamAV, S3, UPI, browser
E2E, migration, or production-database execution was performed, so no claim of runtime
functionality in those areas is made.
