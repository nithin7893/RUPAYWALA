-- RUPAYWALA STAGE 5.6E - CORRECTED ROLE SEPARATION / LEAST-PRIVILEGE SCRIPT
-- STATUS: CORRECTED DRAFT FOR DISPOSABLE STAGING VALIDATION. NOT EXECUTED AGAINST PRODUCTION.
-- Target (staging only): rupaywala_role_validation on rupaywala-pg18-validation (PG 18.1)
-- DO NOT RUN against rupaywala_ori or rupaywala_validation.
--
-- Prerequisites:
--   1) Disposable staging DB already created from validated source.
--   2) Roles rupaywala_owner (NOLOGIN), rupaywala_migrator (LOGIN), rupaywala_app (LOGIN) created
--      with secure passwords managed outside this file.
--   3) Run as bootstrap/superuser admin (validation_admin in disposable container).
--   4) Review and adapt DB name/role names before any execution.
--
-- Security notes:
--   - No passwords in this file.
--   - No CREATE/TRUNCATE/TRIGGER/REFERENCES/MAINTAIN/superuser/bypassrls for rupaywala_app.
--   - alembic_version is denied to rupaywala_app.
--   - family_members has no backend runtime path in current codebase; kept denied to app by default.
--   - subscription_plans_id_seq UPDATE is a TEMPORARY exception required by current startup
--     setval() in app/services/plan_catalog.py. Remove after code change.

\set ON_ERROR_STOP on

-- =============================
-- 0. Identity gates
-- =============================
DO $$
BEGIN
  IF current_database() IS DISTINCT FROM 'rupaywala_role_validation' THEN
    RAISE EXCEPTION 'Refusing: current_database=% expected rupaywala_role_validation', current_database();
  END IF;
  IF current_user IS DISTINCT FROM 'validation_admin' THEN
    RAISE EXCEPTION 'Refusing: current_user=% expected validation_admin', current_user;
  END IF;
  IF session_user IS DISTINCT FROM 'validation_admin' THEN
    RAISE EXCEPTION 'Refusing: session_user=% expected validation_admin', session_user;
  END IF;
  IF split_part(current_setting('server_version'), ' ', 1) NOT LIKE '18.%' THEN
    RAISE EXCEPTION 'Unexpected server version: %', current_setting('server_version');
  END IF;
END $$;

SELECT current_database(), current_user, session_user, current_setting('server_version');

-- =============================
-- 1. Role prechecks
-- =============================
DO $$
DECLARE r record; problems text[] := ARRAY[]::text[];
BEGIN
  FOR r IN
    SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls, rolreplication, rolinherit,
           EXISTS (SELECT 1 FROM pg_authid a WHERE a.oid=p.oid AND a.rolpassword IS NOT NULL AND a.rolpassword <> '') AS has_password
    FROM pg_roles p WHERE rolname IN ('rupaywala_owner','rupaywala_migrator','rupaywala_app')
  LOOP
    IF r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolbypassrls OR r.rolreplication THEN
      problems := array_append(problems, format('%s has forbidden privilege attribute', r.rolname));
    END IF;
    IF r.rolname='rupaywala_owner' AND (r.rolcanlogin OR NOT r.rolinherit) THEN
      problems := array_append(problems, 'rupaywala_owner must be NOLOGIN INHERIT');
    END IF;
    IF r.rolname='rupaywala_migrator' AND (NOT r.rolcanlogin OR NOT r.rolinherit OR NOT r.has_password) THEN
      problems := array_append(problems, 'rupaywala_migrator must be LOGIN INHERIT with password');
    END IF;
    IF r.rolname='rupaywala_app' AND (NOT r.rolcanlogin OR r.rolinherit OR NOT r.has_password) THEN
      problems := array_append(problems, 'rupaywala_app must be LOGIN NOINHERIT with password');
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_roles WHERE rolname IN ('rupaywala_owner','rupaywala_migrator','rupaywala_app')) <> 3 THEN
    problems := array_append(problems, 'missing required roles');
  END IF;
  IF array_length(problems,1) > 0 THEN
    RAISE EXCEPTION 'Role precheck failed: %', array_to_string(problems,'; ');
  END IF;
END $$;

-- Required membership for Alembic owner strategy; idempotent.
GRANT rupaywala_owner TO rupaywala_migrator;

-- =============================
-- 2. Database/schema access
-- =============================
GRANT CONNECT ON DATABASE rupaywala_role_validation TO rupaywala_migrator;
GRANT CONNECT ON DATABASE rupaywala_role_validation TO rupaywala_app;
REVOKE CREATE ON DATABASE rupaywala_role_validation FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO rupaywala_migrator;
GRANT USAGE ON SCHEMA public TO rupaywala_app;
ALTER SCHEMA public OWNER TO rupaywala_owner;

-- =============================
-- 3. Ownership transfer (superuser/bootstrap)
-- =============================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname, c.relkind
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f','S')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid='pg_catalog.pg_class'::regclass AND d.objid=c.oid
          AND d.deptype IN ('e','x') AND d.refclassid='pg_catalog.pg_extension'::regclass)
    ORDER BY CASE c.relkind WHEN 'r' THEN 1 WHEN 'p' THEN 2 WHEN 'v' THEN 3 WHEN 'm' THEN 4 WHEN 'f' THEN 5 WHEN 'S' THEN 6 END, c.relname
  LOOP
    BEGIN
      EXECUTE format('ALTER %s public.%I OWNER TO rupaywala_owner',
        CASE r.relkind WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,
        r.relname);
    EXCEPTION WHEN others THEN
      -- Sequences owned by table columns may error; skip if already owned by target.
      IF r.relkind = 'S' THEN
        IF EXISTS (SELECT 1 FROM pg_class c2 JOIN pg_namespace n2 ON n2.oid=c2.relnamespace
                   WHERE n2.nspname='public' AND c2.relname=r.relname AND pg_get_userbyid(c2.relowner)='rupaywala_owner') THEN
          NULL;
        ELSE
          RAISE;
        END IF;
      ELSE
        RAISE;
      END IF;
    END;
  END LOOP;
  FOR r IN
    SELECT t.typname, t.typtype
    FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='public' AND t.typtype IN ('e','d')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid='pg_catalog.pg_type'::regclass AND d.objid=t.oid
          AND d.deptype IN ('e','x') AND d.refclassid='pg_catalog.pg_extension'::regclass)
    ORDER BY t.typname
  LOOP
    EXECUTE format('ALTER %s public.%I OWNER TO rupaywala_owner', CASE WHEN r.typtype='d' THEN 'DOMAIN' ELSE 'TYPE' END, r.typname);
  END LOOP;
END $$;

-- =============================
-- 4. Grants as owner
-- =============================
SET ROLE rupaywala_owner;

DO $$
DECLARE t text; seq text;
  runtime_tables text[] := ARRAY[
    'users','branches','customer_profiles','field_members','notifications','otp_verifications','payments','policies',
    'policy_members','request_assignments','service_quotes','service_requests','service_types','subscription_plans',
    'subscription_family_members','user_subscriptions','visit_ledger','distance_rate_config'
  ];
  select_tables text[] := runtime_tables;
  insert_tables text[] := runtime_tables;
  update_tables text[] := ARRAY[
    'users','branches','customer_profiles','field_members','notifications','otp_verifications','payments',
    'request_assignments','service_quotes','service_requests','service_types','subscription_plans','user_subscriptions'
  ];
  delete_tables text[] := ARRAY['notifications','otp_verifications','policies','policy_members','subscription_family_members'];
BEGIN
  FOREACH t IN ARRAY runtime_tables LOOP
    IF to_regclass(format('public.%I',t)) IS NULL THEN RAISE EXCEPTION 'Missing table %', t; END IF;
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM rupaywala_app', t);
  END LOOP;
  IF to_regclass('public.family_members') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON TABLE public.family_members FROM rupaywala_app';
  END IF;
  IF to_regclass('public.alembic_version') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON TABLE public.alembic_version FROM rupaywala_app';
  END IF;

  FOREACH t IN ARRAY select_tables LOOP EXECUTE format('GRANT SELECT ON TABLE public.%I TO rupaywala_app', t); END LOOP;
  FOREACH t IN ARRAY insert_tables LOOP EXECUTE format('GRANT INSERT ON TABLE public.%I TO rupaywala_app', t); END LOOP;
  FOREACH t IN ARRAY update_tables LOOP EXECUTE format('GRANT UPDATE ON TABLE public.%I TO rupaywala_app', t); END LOOP;
  FOREACH t IN ARRAY delete_tables LOOP EXECUTE format('GRANT DELETE ON TABLE public.%I TO rupaywala_app', t); END LOOP;

  FOREACH t IN ARRAY insert_tables LOOP
    seq := pg_get_serial_sequence(format('public.%I',t), 'id');
    IF seq IS NULL THEN RAISE EXCEPTION 'Missing sequence for %', t; END IF;
    EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM rupaywala_app', seq::regclass);
    EXECUTE format('GRANT USAGE ON SEQUENCE %s TO rupaywala_app', seq::regclass);
  END LOOP;
  -- TEMPORARY EXCEPTION: current runtime startup seeding uses setval() on subscription_plans.id.
  seq := pg_get_serial_sequence('public.subscription_plans','id');
  IF seq IS NOT NULL THEN
    EXECUTE format('GRANT UPDATE ON SEQUENCE %s TO rupaywala_app', seq::regclass);
  END IF;
END $$;

-- Default privileges for objects created by owner.
-- Conservative defaults: SELECT on tables, USAGE on sequences. Explicit grants above are authoritative.
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public REVOKE ALL ON TABLES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public REVOKE ALL ON SEQUENCES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public GRANT SELECT ON TABLES TO rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public GRANT USAGE ON SEQUENCES TO rupaywala_app;

RESET ROLE;

-- Defensive defaults for migrator-created objects (preferred: run Alembic with PGOPTIONS role=rupaywala_owner).
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public REVOKE ALL ON TABLES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public REVOKE ALL ON SEQUENCES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public GRANT SELECT ON TABLES TO rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public GRANT USAGE ON SEQUENCES TO rupaywala_app;

-- =============================
-- 5. Verification queries
-- =============================
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls, rolinherit
FROM pg_roles WHERE rolname IN ('rupaywala_owner','rupaywala_migrator','rupaywala_app') ORDER BY 1;

SELECT n.nspname, pg_get_userbyid(n.nspowner) AS owner FROM pg_namespace n WHERE n.nspname='public';
SELECT c.relname, c.relkind, pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p','S','v','m','f') ORDER BY c.relkind, c.relname;

SELECT has_database_privilege('rupaywala_app','rupaywala_role_validation','CONNECT') AS app_connect,
       has_schema_privilege('rupaywala_app','public','USAGE') AS app_usage,
       has_schema_privilege('rupaywala_app','public','CREATE') AS app_create;

SELECT table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee='rupaywala_app' AND table_schema='public'
ORDER BY table_name, privilege_type;

SELECT object_name, privilege_type
FROM information_schema.role_usage_grants
WHERE grantee='rupaywala_app' AND object_schema='public' AND object_type='SEQUENCE'
ORDER BY object_name, privilege_type;

-- alembic_version must be inaccessible
SELECT has_table_privilege('rupaywala_app','public.alembic_version','SELECT') AS app_alembic_select,
       has_table_privilege('rupaywala_app','public.alembic_version','UPDATE') AS app_alembic_update;

-- =============================
-- 6. Alembic owner strategy (runbook, not executed here)
-- =============================
-- Preferred: run Alembic as rupaywala_migrator with PGOPTIONS startup role so new objects are owned by rupaywala_owner.
-- Example (process env, secrets managed externally):
--   $env:DATABASE_URL='postgresql+psycopg2://rupaywala_migrator:<SECRET>@127.0.0.1:55432/rupaywala_role_validation'
--   $env:PGOPTIONS='-c role=rupaywala_owner'
--   alembic upgrade head
-- Verify identity before migration: SELECT current_user, session_user; => rupaywala_owner, rupaywala_migrator


