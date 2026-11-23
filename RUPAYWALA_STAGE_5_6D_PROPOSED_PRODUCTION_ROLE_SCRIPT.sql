-- RUPAYWALA STAGE 5.6D - PROPOSED PRODUCTION ROLE/PRIVILEGE SCRIPT
-- STATUS: PROPOSED ONLY - NOT EXECUTED - DO NOT RUN WITHOUT REVIEW
-- Date drafted: 2026-11-21
-- Source of truth for permissions: read-only inspection of app models/routes/services,
-- alembic migrations, and live validation DB object inventory. No production DB was touched.
--
-- IMPORTANT
-- 1. Do NOT execute this script against rupaywala_ori or any production DB without:
--    - approved change window
--    - verified backup/snapshot/restore point
--    - exact target DB/host/port/user confirmation
--    - review against the deployed application revision
-- 2. This script assumes PostgreSQL 18.x, schema public, and the current 20-table inventory.
-- 3. Adjust role names/password management to your secrets manager / DBA process.
--    Passwords/placeholders below must be replaced securely; never commit real secrets.
-- 4. The runtime app currently calls seed_subscription_plans() at startup, which executes
--    setval(pg_get_serial_sequence('subscription_plans','id'), ...). That requires UPDATE on
--    subscription_plans_id_seq. Preferred remediation: remove runtime setval() and grant only
--    USAGE,SELECT on sequences. Until removed, the temporary exception is included and marked.
-- 5. Alembic/env.py uses DATABASE_URL directly and does not SET ROLE; migration ownership behavior
--    must be validated in disposable staging before production use.

\echo 'PROPOSED SCRIPT ONLY - NOT EXECUTED'

-- =============================
-- Roles (create outside transaction if your workflow requires)
-- =============================
-- CREATE ROLE rupaywala_owner NOLOGIN;
-- CREATE ROLE rupaywala_migrator LOGIN PASSWORD '<STRONG_RANDOM_SECRET>' INHERIT;
-- CREATE ROLE rupaywala_app LOGIN PASSWORD '<STRONG_RANDOM_SECRET>' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;

-- GRANT rupaywala_owner TO rupaywala_migrator;

-- =============================
-- Database/schema baseline
-- =============================
-- REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- REVOKE ALL ON DATABASE rupaywala_production FROM PUBLIC;
-- GRANT CONNECT ON DATABASE rupaywala_production TO rupaywala_migrator, rupaywala_app;
-- GRANT USAGE ON SCHEMA public TO rupaywala_migrator, rupaywala_app;

-- Migration role needs broad DDL on schema; prefer owner/migrator model reviewed by DBA.
-- GRANT CREATE ON SCHEMA public TO rupaywala_migrator; -- only if migrations run as migrator without ownership transfer

-- =============================
-- Application runtime table privileges
-- =============================
-- App tables observed (19): all public tables except alembic_version.
-- Runtime uses SQLAlchemy ORM CRUD; no DDL/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN required.
-- Principle of least privilege: grant only required DML. Read-only/reference tables can be tightened after query audit.

-- GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
--   public.branches,
--   public.customer_profiles,
--   public.distance_rate_config,
--   public.family_members,
--   public.field_members,
--   public.notifications,
--   public.otp_verifications,
--   public.payments,
--   public.policies,
--   public.policy_members,
--   public.request_assignments,
--   public.service_quotes,
--   public.service_requests,
--   public.service_types,
--   public.subscription_family_members,
--   public.subscription_plans,
--   public.user_subscriptions,
--   public.users,
--   public.visit_ledger
-- TO rupaywala_app;

-- Optional tightening candidate (requires code/query confirmation):
-- service_types, subscription_plans, branches, distance_rate_config may be read-mostly at runtime;
-- keep writes only where startup/admin flows require them.

-- alembic_version: no app runtime access.
-- REVOKE ALL ON TABLE public.alembic_version FROM rupaywala_app;

-- =============================
-- Sequence privileges
-- =============================
-- Serial/bigserial IDs require USAGE; SELECT useful for diagnostics. UPDATE not normally required.
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rupaywala_app;

-- TEMPORARY EXCEPTION - current runtime setval() in seed_subscription_plans():
-- GRANT UPDATE ON SEQUENCE public.subscription_plans_id_seq TO rupaywala_app;
-- Remove after code change and validate startup seeding.

-- =============================
-- Default privileges for future objects created by migrator/owner
-- =============================
-- ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public
--   GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rupaywala_app;
-- ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public
--   GRANT USAGE, SELECT ON SEQUENCES TO rupaywala_app;

-- =============================
-- Verification queries (run read-only after approved execution)
-- =============================
-- SELECT grantee, table_name, privilege_type FROM information_schema.role_table_grants
-- WHERE table_schema='public' AND grantee='rupaywala_app' ORDER BY table_name, privilege_type;
-- SELECT grantee, object_name, privilege_type FROM information_schema.role_usage_grants
-- WHERE object_schema='public' AND object_type='SEQUENCE' AND grantee='rupaywala_app' ORDER BY object_name, privilege_type;
-- SELECT has_table_privilege('rupaywala_app','public.alembic_version','SELECT'); -- should be false
-- SELECT has_schema_privilege('rupaywala_app','public','CREATE'); -- should be false

-- END PROPOSED SCRIPT - NOT EXECUTED