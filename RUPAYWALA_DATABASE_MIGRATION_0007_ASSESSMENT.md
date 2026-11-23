# RUPAYWALA DATABASE MIGRATION 0007 ASSESSMENT

**Date:** 2026-11-21  
**Mode:** Read-only inspection. No migrations applied. No DB modifications.

## 1. Migration File Inspected

- **File:** `alembic/versions/0007_user_token_version.py`
- **Revision ID:** `0007_user_token_version`
- **Down revision:** `0006_stage5_security_remediation`
- **Branch labels:** None
- **Depends on:** None
- **Alembic head:** `0007_user_token_version` (confirmed by `alembic heads`)

## 2. Upgrade / Downgrade Operations

| Direction | Operation | Safety |
|---|---|---|
| Upgrade | `op.add_column("users", sa.Column("token_version", sa.Integer(), nullable=False, server_default=sa.text("0")))` | Additive, non-destructive. Sets default 0 for existing rows. |
| Downgrade | `op.drop_column("users", "token_version")` | Destructive to column data; should only be used in controlled rollback scenarios. |

## 3. Model / Code Compatibility

| Area | Status | Evidence |
|---|---|---|
| User model | Compatible | `app/models/user.py` defines `token_version = Column(Integer, default=0, nullable=False)`. |
| JWT issuance | Compatible | `app/routes/auth_routes.py` includes `"tv": int(getattr(user, "token_version", 0) or 0)` in access token. |
| JWT enforcement | Compatible | `app/utils/dependencies.py` compares token `tv` with `user.token_version`; mismatch returns unauthenticated. |
| Password change/reset/logout invalidation | Compatible | `auth_routes.py` increments `token_version` on change-password, forgot-password reset, logout. |
| Flutter client | Compatible | Flutter logout calls `/auth/logout`; token clearing handled. No schema dependency on client. |

## 4. Current Database Target (Read-only Inspection)

| Check | Result | Evidence |
|---|---|---|
| Database URL target | localhost:5432, db `rupaywala_ori`, credentials present | Parsed safely from env; no secrets exposed |
| Disposable/test/demo naming | **No** - name `rupaywala_ori` does not suggest disposable | Name inspection |
| Production/demo separation confirmed | **No** | Single `.env`; DB name/role not confirmed as demo |
| PostgreSQL version | PostgreSQL 18.1 on x86_64-windows | Read-only `SELECT version()` |
| Current Alembic revision | `0005_fixed_quotes` | Read-only `SELECT version_num FROM alembic_version` |
| Migration 0006 pending | **Yes** | DB at 0005; head chain includes 0006 |
| Migration 0007 pending | **Yes** | DB at 0005; head is 0007 |
| DB safe to modify for testing/migration now | **No - not authorized/confirmed safe** | Non-disposable name, no explicit authorization |

## 5. Risk Assessment

- **Applying 0007 on `rupaywala_ori` without authorization:** **UNSAFE**. Target DB identity/safety not confirmed as disposable demo.
- **Applying 0007 before 0006:** **Not applicable**; Alembic will follow chain 0005->0006->0007. 0006 must also be reviewed/applied in same authorized window.
- **Runtime behavior if 0007 not applied but code deployed:** **High risk**. Code references `users.token_version`; queries against DB missing column will fail on user auth/profile flows.
- **Migration 0007 itself:** Additive and low-risk on an authorized demo/staging DB after backup.

## 6. Recommendation

- **Do not apply migration 0007 (or 0006) to the currently configured DB** until a separate authorized demo/staging DB is identified, backed up/snapshotted, and explicitly approved.
- For demo readiness, apply 0006 then 0007 to an isolated demo DB only, verify auth flows, and capture evidence.