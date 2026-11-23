# RUPAYWALA — C-01 email OTP authentication vulnerability: remediation report

Date: 2026-11-23
Scope: `POST /auth/email-login` and the email OTP verification service only.
Status: **fixed and regression-tested**. No migration or production-database change was made.

## 1. Root cause

Two defects combined to create an authentication bypass:

1. `app/routes/auth_routes.py` (`email_login`) first queried *any* `OTPVerification` row with
   `purpose == email_login` and `verified == True` for the submitted email. If such a row
   existed, the submitted OTP was **never compared** to the stored hash — the endpoint used
   that old row as proof and issued a JWT. The proof query had no `expires_at` or `is_used`
   condition.
2. `app/services/otp_service.py` (`verify_email`) set `verified = True` on success but, unlike
   phone verification (`verify`, which sets both `verified` and `is_used`), never set
   `is_used = True`. The record therefore remained active (`is_used == False`) and verified
   indefinitely, and verification queries kept selecting it.

Result: after any single successful email-login OTP verification for an address, any caller
who knew that email could submit an arbitrary 4–10 character OTP and receive a full access
token for the account (`AuthResponse` with JWT). This is account takeover.

Contributing observations:
- OTP identity is the normalized email string tied to the record (`email` column); the model
  has no `user_id` column, so purpose plus normalized email are the available identity checks.
- `VerifyEmailOTPRequest.otp` only constrains length (4–10), not value, so an arbitrary value
  was accepted by schema validation.
- `/auth/email-login` already had a 10/60 in-process rate limit, but that did not prevent the
  bypass because the first successful login did not require knowing the code at all.

## 2. Files modified

| File | Change |
|---|---|
| `app/routes/auth_routes.py` | Removed the prior-`verified`-record proof branch from `email_login`. The endpoint now always calls `OTPService.verify_email(..., purpose=OTPPurpose.email_login)` with the submitted code, and translates all OTP failures into generic authentication errors (400, or 429 for attempt lockout). |
| `app/services/otp_service.py` | `verify_email` now uses `SELECT ... FOR UPDATE` on the candidate record, checks `is_used` defensively after the lock, and consumes the OTP with a conditional `UPDATE ... WHERE is_used = False` setting both `verified = True` and `is_used = True`. A non-matching update is rolled back and rejected. Expired/locked/wrong-code branches keep their existing behaviour (mark used or increment attempts). |
| `tests/test_c01_email_otp_security.py` | New focused regression suite (12 tests) covering all mandatory C-01 scenarios. |

No other authentication flow, schema, migration, configuration, frontend file, or production
data was changed. No Alembic command was executed.

## 3. Vulnerable behaviour before remediation

- Submit any OTP (e.g. `000000`) for an email whose account had previously completed
  `/auth/verify-email-otp` with purpose `email_login`:
  - the `proof` query found the old `verified=True` row;
  - `OTPService.verify_email()` was skipped entirely;
  - the user was marked `email_verified`/`is_verified`, `auth_provider` set to `email_otp`,
    `last_login_at` updated, and a JWT issued — all without validating the submitted code.
- The same OTP record could be verified repeatedly until expiry, because `is_used` was never
  set on email verification.
- The proof query had no expiry condition, so an old record was usable long after its
  `expires_at`.

## 4. Corrected behaviour

- `/auth/email-login` **always** validates the submitted code against the newest unused OTP
  record for that exact normalized email and purpose `email_login`. Existence of a prior
  verified record is never proof.
- `verify_email` enforces: correct email identity, correct purpose, `is_used == False`,
  unexpired code, attempt limit, and constant-time hash comparison (`verify_otp`).
- On success the record is atomically consumed (`verified=True`, `is_used=True`) via a locked
  read plus conditional update; only one concurrent request can win. Expired and
  attempt-locked records are also marked used. Wrong codes increment `attempts`.
- Generic errors: all code-validation failures from `/auth/email-login` return
  `400 {"detail": "Invalid or expired verification code"}` (or a generic 429 on attempt
  lockout). The endpoint does not reveal which check failed or whether the email exists.
- Account verification semantics are preserved: `/auth/verify-email-otp` still works for
  signup and login purposes, `/auth/register/email` still accepts the email-signup proof,
  and successful email verification is now single-use like phone verification.
- JWT semantics are unchanged: `_build_auth_response` still issues HS256 tokens with
  `user_id`, `role`, `tv` from `user.token_version`, `exp`, `iat` and `jti`; token-version
  invalidation still applies.

## 5. Tests added

`tests/test_c01_email_otp_security.py` (12 tests):

| # | Test | Assertion |
|---|---|---|
| 1 | `test_correct_otp_succeeds_and_is_consumed` | 200 + JWT with matching `user_id`/`tv`, `/auth/me` succeeds, record `verified`/`is_used`, user verification fields updated. |
| 2 | `test_incorrect_otp_fails_without_authenticating` | 400 generic detail, no token, `attempts` incremented, record still usable. |
| 3 | `test_arbitrary_otp_fails_even_with_prior_verified_record` | Exact C-01 path: legacy `verified=True, is_used=False` record + arbitrary OTP → 400, no token. |
| 4 | `test_expired_otp_fails` | Past `expires_at` + correct OTP → 400, record marked used. |
| 5 | `test_previously_consumed_otp_fails` | `is_used=True` record → 400, no token. |
| 6 | `test_otp_from_another_account_fails` | Another account's OTP rejected for this email; this account's own OTP still succeeds. |
| 7 | `test_otp_from_another_purpose_fails` | `email_signup` OTP cannot authenticate `/email-login`. |
| 8 | `test_repeated_submission_fails` | First submission 200, immediate repeat 400. |
| 9 | `test_concurrent_reuse_cannot_authenticate_twice` | Two parallel requests with the same OTP → exactly one 200 and one 400; stored record consumed. Uses per-request DB sessions. |
| 10 | `test_missing_otp_is_rejected_by_schema` | Missing `otp` → 422, no token. |
| 11 | `test_existing_email_verification_and_registration_still_work` | `/verify-email-otp` → replay rejected → `/register/email` → `/email-login` all succeed with correct purpose-specific OTPs. |
| 12 | `test_email_login_token_obeys_token_version_invalidation` | Email-login JWT carries current `tv`; incrementing `token_version` makes the old token 401. |

Test-only controls: an autouse fixture resets the in-process rate limiter before and after
each test. No security assertion was skipped or weakened, and no OTP value is logged by the
application or the tests.

## 6. Test results

Commands executed from `C:\RUPAAY_WALA\rupaywala_backend` using `.\\venv\\Scripts\\python.exe`:

| Suite | Result |
|---|---|
| `pytest tests/test_c01_email_otp_security.py -v --tb=short` | **12 passed in 9.17s** |
| `pytest tests/test_auth.py tests/test_c01_email_otp_security.py --tb=short -ra` | **49 passed in 34.22s** (37 existing auth + 12 new) |
| `pytest tests/test_stage5_security_remediation.py tests/test_stage56g1_payment_idempotency.py tests/test_stage56i_security_containment.py tests/test_stage56j_private_documents.py tests/test_payments.py tests/test_fixed_quote_stage5.py --tb=short -ra` | **186 passed in 169.84s** |
| `pytest --tb=no -ra` (full suite) | **428 passed in 274.95s** (baseline was 416; +12 new tests) |

Raw output was captured under `C:\Users\NITHIN\AppData\Local\Temp\opencode\` as
`c01_focused.txt`, `c01_auth_regression.txt`, `c01_security_payment_regression.txt` and
`c01_full_suite.txt`.

## 7. Security regression results

- The account-takeover path is closed: arbitrary OTP with a prior verified record returns 400
  and issues no token (test 3).
- Expired, consumed, cross-account, cross-purpose, repeated and missing OTP cases all fail
  closed without a token (tests 4–8, 10).
- Concurrent reuse yields exactly one successful authentication (test 9), confirming the
  locked read plus conditional update prevents double consumption.
- Email verification/registration still function and are now single-use (test 11).
- JWT claim contents, `/auth/me` acceptance and token-version invalidation are unchanged
  (tests 1 and 12); the existing 37 auth/JWT tests and the 186 security/payment tests remain
  green.
- No OTP values or credentials are logged by the changed code. No test was skipped, xfailed,
  or weakened. No production database, Alembic revision, or unrelated auth flow was touched.

## 8. Remaining concerns

1. **Scope:** this fix covers C-01 only. C-02 (missing Android release `INTERNET` permission)
   and the other findings in `RUPAYWALA_FINAL_APPLICATION_AUDIT_REPORT.md` remain open and were
   not addressed.
2. **Rate-limiter trust (`X-Forwarded-For`)** and proxy-header handling remain as documented
   in the final audit; they are separate findings and were deliberately not changed here.
3. **OTP identity binding:** the `otp_verifications` table stores a normalized email, not a
   user ID. Identity validation is therefore "purpose + exact normalized email", enforced in
   `verify_email` and by the user lookup before it. A schema change to bind OTPs to a user ID
   would need an authorized migration and was out of scope.
4. **Delivery semantics:** like the rest of the OTP system, a code can still be issued when
   SMTP is unavailable and delivery failure is reported generically; this is unchanged.
5. **Concurrency guarantee is database-backed:** `SELECT ... FOR UPDATE` relies on row locking
   (PostgreSQL in tests/production). On engines without row locks the conditional update still
   prevents double consumption, but full serialization is not guaranteed. The in-process rate
   limiter also remains single-instance, as previously documented.
6. **Legacy records:** previously verified email OTP rows may still exist with
   `verified=True, is_used=False`. They are no longer usable for authentication — the
   endpoint always requires a submitted, currently active code — but they are not purged by
   this change.
7. **Migration 0008** remains pending by design; this fix does not depend on it.
