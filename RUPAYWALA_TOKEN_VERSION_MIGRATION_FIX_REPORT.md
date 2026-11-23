# RUPAYWALA — token_version schema mismatch investigation and fix

Date: 2026-11-23
Target database: `rupaywala_ori` (PostgreSQL 18.1, `localhost:5432`, user `postgres`)
Authorization: user approved "Backup + upgrade to 0007" after review of root cause, exact migration and target DB.

## 1. Root cause

The application code is ahead of the database schema. `app/models/user.py:59` declares
`token_version = Column(Integer, default=0, nullable=False)`, and `POST /auth/login`
(`app/routes/auth_routes.py:429`) materializes the full `User` entity via `query.first()`.
The connected database had no `users.token_version` column, so PostgreSQL raised
`psycopg2.errors.UndefinedColumn`.

The migration that adds the column already existed in the repository
(`alembic/versions/0007_user_token_version.py`) but had never been applied to the active
database. It was **not** a missing migration, not an incorrectly recorded revision, and
not an accidental wrong connection: the app deliberately points at `rupaywala_ori`, which
was still at `0005_fixed_quotes` (three revisions behind the repository head `0008_private_document_storage`).

### Model vs. database before the fix
Expected `users` columns (16): `id, phone_number, username, email, password_hash, role,
is_verified, token_version, account_status, auth_provider, google_sub, email_verified,
phone_verified, last_login_at, created_at, updated_at`.

Actual `public.users` had 15 columns — only `token_version` was missing.

## 2. Files inspected

- `app/models/user.py` — User model and expected columns.
- `app/routes/auth_routes.py` — login query (line 429), JWT `tv` claim (line 90), logout/version increments (lines 568, 637, 689).
- `app/utils/dependencies.py` — token-version enforcement (lines 53–60).
- `app/utils/jwt_handler.py` — JWT creation/decoding.
- `app/config.py`, `app/database.py`, `alembic.ini`, `alembic/env.py` — single `DATABASE_URL` source for app and Alembic.
- `alembic/versions/0001…0008_*.py` and `b96aae0ed4c8_add_email_otp_support.py` — complete revision chain.
- `tests/conftest.py`, `tests/test_auth.py`, `tests/factories.py` — test isolation and auth coverage.
- `seed_users.py` — known seeded credentials used only for read-only verification.
- Prior investigation/assessment reports and `database_backups/` inventory.

## 3. Migration identified and applied

Existing migration, not a new one: **`0007_user_token_version`**
(`alembic/versions/0007_user_token_version.py`):

```sql
ALTER TABLE users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;
```

`0007` depends on `0006_stage5_security_remediation`, so the authorized command
`alembic upgrade 0007_user_token_version` also applied `0006`:

```sql
ALTER TABLE service_quotes ADD COLUMN signature_version INTEGER NOT NULL DEFAULT '1';
ALTER TABLE service_requests ADD COLUMN quote_ref VARCHAR(64) NULL;
ALTER TABLE service_requests ADD CONSTRAINT uq_service_requests_quote_ref UNIQUE (quote_ref);
CREATE UNIQUE INDEX uq_payments_user_type_idem_open ON payments (user_id, payment_type, idempotency_key)
  WHERE idempotency_key IS NOT NULL AND status IN ('pending','pending_verification');
CREATE UNIQUE INDEX uq_payments_open_extra_charge_request ON payments (related_request_id)
  WHERE payment_type='extra_charge' AND related_request_id IS NOT NULL
    AND status IN ('pending','pending_verification');
```

Preflight duplicate checks for `0006` both returned `0`. Server-side default `0` preserves
all existing rows and matches `User.token_version` (`default=0`, `nullable=False`).

`alembic stamp` was not used. No downgrade was run. No database was dropped/recreated.
No records were deleted. No authentication/security logic was modified.

## 4. Database changes performed

| Step | Result |
|---|---|
| Identity guard before backup | `current_database()=rupaywala_ori`, revision `0005_fixed_quotes`, 28 users, no `token_version` — PASS |
| Fresh backup | `database_backups/rupaywala_ori_pre_0007_20261123_195104.dump`, 105,241 bytes, `pg_dump -Fc -Z 6` exit 0 |
| Backup verification | `pg_restore -l` exit 0, 272 TOC lines, header `dbname: rupaywala_ori` — PASS |
| `alembic upgrade 0007_user_token_version` | `0005 → 0006 → 0007` applied successfully |
| Data preservation | 28 users before and after; all existing users have `token_version = 0`; no row updates/deletes by migrations |

Post-change read-only verification:

- `alembic current` → `0007_user_token_version`
- `alembic heads` → `0008_private_document_storage` (single head; 0008 intentionally still pending)
- `users.token_version` → `integer`, nullable `NO`, default `0`
- `token_version` distribution: 28 rows with value `0`
- `0006` columns and partial unique indexes present

## 5. Tests executed and results

| Validation | Result |
|---|---|
| Read-only schema/revision verification on `rupaywala_ori` | PASS |
| Live `POST /auth/login` against `rupaywala_ori` via FastAPI TestClient (`TESTING=1` to avoid startup seeding): wrong password → 401; correct password → 200 | PASS |
| JWT from live login: `user_id` correct, `tv = 0`, `role = customer`, no password claims | PASS |
| Live `GET /auth/me` with issued token → 200; same token with forged stale `tv` → 401 | PASS |
| Live login test left `token_version` unchanged (no logout on production-like data) | PASS |
| `pytest tests/test_auth.py` | **37 passed** (includes 3 new regression tests) |
| New regression tests: login JWT carries current `token_version`; logout increments version and invalidates old token; stale-version token rejected | PASS (isolated `rupaywala_test` PostgreSQL DB) |
| `pytest tests/test_auth.py tests/test_stage5_security_remediation.py tests/test_stage56i_security_containment.py` | **113 passed, 1 failed** |
| Full `pytest` | **370 passed, 46 failed** |

### Code added
`tests/test_auth.py` — new `TestTokenVersionInvalidation` class with three tests covering
JWT `tv` issuance, `/auth/logout` increment + invalidation, and rejection of stale versions.
No application code or security logic was changed.

## 6. Remaining issues

1. **`0008_private_document_storage` is still pending** on `rupaywala_ori` by design (minimal fix authorized). The repository head remains `0008`; a separate authorized change is required to apply it.
2. **Unrelated failing tests** (pre-existing, not caused by this migration):
   - `TestPaymentIdempotency::test_existing_duplicate_history_is_never_deleted` — `app/services/payment_service.py` deliberately returns the most recent terminal payment for a reused key; the test expects a new pending intent. Reproduces in isolation.
   - Most full-suite failures call the live Google Maps Routes API and receive HTTP 400 (`Google Maps returned an unexpected status`); these are external-credential/network dependent.
   - `test_seed_subscription_plans_concurrent_startup` uses a SQLite bind with no `subscription_plans` table.
   None of these touch `users.token_version`, login, JWT, or Alembic state.
3. **Model metadata nuance (no runtime impact):** `User.token_version` declares Python-side `default=0` but not `server_default`. The database has server default `0` from migration `0007`. Optional future cleanup could add `server_default=text("0")` to the model so autogenerate comparisons agree; not done here to avoid unrelated model churn.
4. Other local databases (`rupaywala_dev`, `rupaywala_mig_clone`, `rupaywala_schema_tmp`, `rupaywala_test`) were not migrated. `rupaywala_dev_stage56k` was already at `0008` and remains untouched.

## 7. Conclusion

The reported login failure is resolved and validated on the actual PostgreSQL database and
HTTP endpoint. The existing `0007` migration was applied safely through the normal Alembic
chain after a verified backup, with all 28 user records preserved.
