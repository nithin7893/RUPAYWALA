
/*
RUPAYWALA - STAGE 5.6C
POSTGRESQL ROLE AND PERMISSION VALIDATION

Target PostgreSQL: 18.1

STATUS:
PROPOSED - NOT EXECUTED
FOR DISPOSABLE TEST ENVIRONMENT ONLY.

Never execute against rupaywala_ori during Stage 5.6D.

Replace placeholders only through an approved process.
Never commit real passwords or credentials.
*/


-- ============================================================
-- 1.1 READ-ONLY PREFLIGHT QUERIES
-- ============================================================

-- Identity and server version
SELECT current_database(),
       current_user,
       session_user,
       current_setting('server_version'),
       inet_server_addr()::text AS server_ip,
       inet_server_port() AS server_port;

-- Existing target roles
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
       rolbypassrls, rolreplication, rolinherit
FROM pg_roles
WHERE rolname IN (
    'rupaywala_owner',
    'rupaywala_migrator',
    'rupaywala_app'
)
ORDER BY rolname;

-- Existing memberships
SELECT r.rolname AS member_role,
       m.rolname AS member_of,
       am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles m ON m.oid = am.roleid
WHERE r.rolname IN (
    'rupaywala_owner',
    'rupaywala_migrator',
    'rupaywala_app'
)
OR m.rolname IN (
    'rupaywala_owner',
    'rupaywala_migrator',
    'rupaywala_app'
)
ORDER BY r.rolname, m.rolname;

-- Database owner and ACL
SELECT datname,
       pg_get_userbyid(datdba) AS owner,
       datacl
FROM pg_database
WHERE datname = '<DB_NAME>';

-- Schema owner and ACL, with extension check
SELECT n.nspname,
       pg_get_userbyid(n.nspowner) AS owner,
       n.nspacl,
       e.extname AS extension_name
FROM pg_namespace n
LEFT JOIN pg_depend d
       ON d.classid = 'pg_catalog.pg_namespace'::regclass
      AND d.objid = n.oid
      AND d.deptype IN ('e', 'x')
      AND d.refclassid = 'pg_catalog.pg_extension'::regclass
LEFT JOIN pg_extension e ON e.oid = d.refobjid
WHERE n.nspname = 'public';

-- Class objects
SELECT c.oid::regclass AS object_name,
       c.relkind,
       pg_get_userbyid(c.relowner) AS owner,
       c.relacl,
       e.extname AS extension_name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_depend d
       ON d.classid = 'pg_catalog.pg_class'::regclass
      AND d.objid = c.oid
      AND d.deptype IN ('e', 'x')
      AND d.refclassid = 'pg_catalog.pg_extension'::regclass
LEFT JOIN pg_extension e ON e.oid = d.refobjid
WHERE n.nspname = 'public'
ORDER BY c.relkind, c.relname;

-- Type objects
SELECT t.oid::regtype AS type_name,
       t.typtype,
       pg_get_userbyid(t.typowner) AS owner,
       rc.relkind AS typrel_kind,
       t.typacl,
       e.extname AS extension_name
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
LEFT JOIN pg_class rc ON rc.oid = t.typrelid
LEFT JOIN pg_depend d
       ON d.classid = 'pg_catalog.pg_type'::regclass
      AND d.objid = t.oid
      AND d.deptype IN ('e', 'x')
      AND d.refclassid = 'pg_catalog.pg_extension'::regclass
LEFT JOIN pg_extension e ON e.oid = d.refobjid
WHERE n.nspname = 'public'
  AND t.typtype IN ('b', 'c', 'd', 'e', 'r', 'm')
ORDER BY t.typtype, t.typname;

-- Routines requiring manual review
SELECT p.oid::regprocedure AS routine_name,
       p.prokind,
       pg_get_userbyid(p.proowner) AS owner,
       p.proacl,
       e.extname AS extension_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
LEFT JOIN pg_depend d
       ON d.classid = 'pg_catalog.pg_proc'::regclass
      AND d.objid = p.oid
      AND d.deptype IN ('e', 'x')
      AND d.refclassid = 'pg_catalog.pg_extension'::regclass
LEFT JOIN pg_extension e ON e.oid = d.refobjid
WHERE n.nspname = 'public'
ORDER BY p.prokind, routine_name;

-- Default privileges
SELECT defaclrole::regrole AS owner_role,
       defaclobjtype,
       defaclacl
FROM pg_default_acl
WHERE defaclnamespace = 'public'::regnamespace
ORDER BY owner_role::text, defaclobjtype;

-- Extensions
SELECT extname, extversion, pg_get_userbyid(extowner) AS owner
FROM pg_extension
ORDER BY extname;

-- Current table grants
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
ORDER BY table_name, grantee, privilege_type;


-- ============================================================
-- 1.2 ROLE CREATION
-- ============================================================

-- Do not transfer database ownership.

CREATE ROLE rupaywala_owner NOLOGIN;

ALTER ROLE rupaywala_owner
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;

CREATE ROLE rupaywala_migrator
  LOGIN PASSWORD '<MIGRATOR_PASSWORD>';

ALTER ROLE rupaywala_migrator
  LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;

CREATE ROLE rupaywala_app
  LOGIN PASSWORD '<APP_PASSWORD>';

ALTER ROLE rupaywala_app
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;

-- Migrator inherits owner object privileges.
-- No ADMIN OPTION.
-- No membership for rupaywala_app.


-- ============================================================
-- 1.3 DATABASE AND SCHEMA ACCESS
-- ============================================================

-- Retain existing database ownership.

-- If required and approved, temporarily grant:
-- GRANT CREATE ON DATABASE <DB_NAME> TO rupaywala_owner;

ALTER SCHEMA public OWNER TO rupaywala_owner;

-- Revoke temporary database CREATE after ownership transfer:
-- REVOKE CREATE ON DATABASE <DB_NAME> FROM rupaywala_owner;

GRANT rupaywala_owner TO rupaywala_migrator;

GRANT CONNECT ON DATABASE <DB_NAME> TO rupaywala_migrator;
GRANT CONNECT ON DATABASE <DB_NAME> TO rupaywala_app;

GRANT USAGE, CREATE ON SCHEMA public TO rupaywala_migrator;
GRANT USAGE ON SCHEMA public TO rupaywala_app;

-- Do not grant CREATE on schema public to application role.

-- Only after reviewing existing PUBLIC grants:
-- REVOKE CREATE ON SCHEMA public FROM PUBLIC;


-- ============================================================
-- 1.4 CORRECTED OWNERSHIP TRANSFER
-- ============================================================

DO $$
DECLARE
    r record;
BEGIN

    -- Tables, partitioned tables, sequences, views,
    -- materialized views and foreign tables.

    FOR r IN
        SELECT c.relname, c.relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_catalog.pg_class'::regclass
                AND d.objid = c.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY c.relkind, c.relname
    LOOP
        EXECUTE format(
            'ALTER %s public.%I OWNER TO rupaywala_owner',
            CASE r.relkind
                WHEN 'S' THEN 'SEQUENCE'
                WHEN 'v' THEN 'VIEW'
                WHEN 'm' THEN 'MATERIALIZED VIEW'
                WHEN 'f' THEN 'FOREIGN TABLE'
                ELSE 'TABLE'
            END,
            r.relname
        );
    END LOOP;


    -- ENUM types: ALTER TYPE.

    FOR r IN
        SELECT t.typname
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typtype = 'e'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY t.typname
    LOOP
        EXECUTE format(
            'ALTER TYPE public.%I OWNER TO rupaywala_owner',
            r.typname
        );
    END LOOP;


    -- DOMAIN types: ALTER DOMAIN, NOT ALTER TYPE.

    FOR r IN
        SELECT t.typname
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typtype = 'd'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY t.typname
    LOOP
        EXECUTE format(
            'ALTER DOMAIN public.%I OWNER TO rupaywala_owner',
            r.typname
        );
    END LOOP;


    -- Standalone composite types only.
    -- Table-associated row types are skipped.

    FOR r IN
        SELECT t.typname
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        JOIN pg_class rc ON rc.oid = t.typrelid
        WHERE n.nspname = 'public'
          AND t.typtype = 'c'
          AND rc.relkind = 'c'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY t.typname
    LOOP
        EXECUTE format(
            'ALTER TYPE public.%I OWNER TO rupaywala_owner',
            r.typname
        );
    END LOOP;

    -- No routine ownership loop.
    -- No index, constraint, TOAST, array or table-row-type loop.

END $$;


-- ============================================================
-- 1.5 EXPLICIT RUNTIME TABLE GRANTS
-- ============================================================

DO $$
DECLARE
    t text;

    select_tables text[] := ARRAY[
        'users',
        'branches',
        'customer_profiles',
        'field_members',
        'notifications',
        'otp_verifications',
        'payments',
        'policies',
        'policy_members',
        'request_assignments',
        'service_quotes',
        'service_requests',
        'service_types',
        'subscription_plans',
        'subscription_family_members',
        'user_subscriptions',
        'visit_ledger',
        'distance_rate_config'
    ];

    insert_tables text[] := ARRAY[
        'users',
        'branches',
        'customer_profiles',
        'field_members',
        'notifications',
        'otp_verifications',
        'payments',
        'policies',
        'policy_members',
        'request_assignments',
        'service_quotes',
        'service_requests',
        'service_types',
        'subscription_plans',
        'subscription_family_members',
        'user_subscriptions',
        'visit_ledger',
        'distance_rate_config'
    ];

    update_tables text[] := ARRAY[
        'users',
        'branches',
        'customer_profiles',
        'field_members',
        'notifications',
        'otp_verifications',
        'payments',
        'request_assignments',
        'service_quotes',
        'service_requests',
        'service_types',
        'subscription_plans',
        'user_subscriptions',
        'distance_rate_config'
    ];

    delete_tables text[] := ARRAY[
        'notifications',
        'otp_verifications',
        'policies',
        'policy_members',
        'subscription_family_members'
    ];

BEGIN

    FOREACH t IN ARRAY select_tables LOOP

        IF to_regclass(format('public.%I', t)) IS NULL THEN
            RAISE EXCEPTION
                'Expected runtime table public.% is absent', t;
        END IF;

        EXECUTE format(
            'GRANT SELECT ON TABLE public.%I TO rupaywala_app',
            t
        );

    END LOOP;


    FOREACH t IN ARRAY insert_tables LOOP
        EXECUTE format(
            'GRANT INSERT ON TABLE public.%I TO rupaywala_app',
            t
        );
    END LOOP;


    FOREACH t IN ARRAY update_tables LOOP
        EXECUTE format(
            'GRANT UPDATE ON TABLE public.%I TO rupaywala_app',
            t
        );
    END LOOP;


    FOREACH t IN ARRAY delete_tables LOOP
        EXECUTE format(
            'GRANT DELETE ON TABLE public.%I TO rupaywala_app',
            t
        );
    END LOOP;

END $$;


-- ============================================================
-- 1.6 SEQUENCE GRANTS
-- ============================================================

DO $$
DECLARE
    t text;
    seq text;

    insert_tables text[] := ARRAY[
        'users',
        'branches',
        'customer_profiles',
        'field_members',
        'notifications',
        'otp_verifications',
        'payments',
        'policies',
        'policy_members',
        'request_assignments',
        'service_quotes',
        'service_requests',
        'service_types',
        'subscription_plans',
        'subscription_family_members',
        'user_subscriptions',
        'visit_ledger',
        'distance_rate_config'
    ];

BEGIN

    FOREACH t IN ARRAY insert_tables LOOP

        seq := pg_get_serial_sequence(
            format('public.%I', t),
            'id'
        );

        IF seq IS NOT NULL THEN
            EXECUTE format(
                'GRANT USAGE, SELECT ON SEQUENCE %s TO rupaywala_app',
                seq::regclass
            );
        END IF;

    END LOOP;


    -- Temporary UPDATE required by current runtime setval().

    seq := pg_get_serial_sequence(
        'public.subscription_plans',
        'id'
    );

    IF seq IS NULL THEN
        RAISE EXCEPTION
            'public.subscription_plans.id sequence is absent';
    END IF;

    EXECUTE format(
        'GRANT UPDATE ON SEQUENCE %s TO rupaywala_app',
        seq::regclass
    );

END $$;


-- After runtime setval() is removed, revoke temporary UPDATE:
-- REVOKE UPDATE ON SEQUENCE public.subscription_plans_id_seq
-- FROM rupaywala_app;


-- ============================================================
-- 1.7 CONSERVATIVE DEFAULT PRIVILEGES
-- ============================================================

ALTER DEFAULT PRIVILEGES
  FOR ROLE rupaywala_owner
  IN SCHEMA public
  GRANT SELECT ON TABLES TO rupaywala_app;

ALTER DEFAULT PRIVILEGES
  FOR ROLE rupaywala_owner
  IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO rupaywala_app;

ALTER DEFAULT PRIVILEGES
  FOR ROLE rupaywala_migrator
  IN SCHEMA public
  GRANT SELECT ON TABLES TO rupaywala_app;

ALTER DEFAULT PRIVILEGES
  FOR ROLE rupaywala_migrator
  IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO rupaywala_app;


-- ============================================================
-- 1.8 POST-SETUP VERIFICATION QUERIES
-- ============================================================

-- Role attributes
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
       rolbypassrls, rolreplication, rolinherit
FROM pg_roles
WHERE rolname IN (
    'rupaywala_owner',
    'rupaywala_migrator',
    'rupaywala_app'
)
ORDER BY rolname;


-- Membership
SELECT r.rolname AS member_role,
       m.rolname AS member_of
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles m ON m.oid = am.roleid
WHERE r.rolname IN (
    'rupaywala_migrator',
    'rupaywala_app'
)
ORDER BY r.rolname, m.rolname;


-- Schema access
SELECT
    has_database_privilege(
        'rupaywala_app', '<DB_NAME>', 'CONNECT'
    ) AS app_connect,

    has_schema_privilege(
        'rupaywala_app', 'public', 'USAGE'
    ) AS app_schema_usage,

    has_schema_privilege(
        'rupaywala_app', 'public', 'CREATE'
    ) AS app_schema_create,

    has_database_privilege(
        'rupaywala_owner', '<DB_NAME>', 'CREATE'
    ) AS owner_db_create,

    has_schema_privilege(
        'rupaywala_migrator', 'public', 'CREATE'
    ) AS migrator_schema_create;


-- Alembic history must be inaccessible to app
SELECT
    has_table_privilege(
        'rupaywala_app',
        'public.alembic_version',
        'SELECT'
    ) AS history_select,

    has_table_privilege(
        'rupaywala_app',
        'public.alembic_version',
        'INSERT'
    ) AS history_insert,

    has_table_privilege(
        'rupaywala_app',
        'public.alembic_version',
        'UPDATE'
    ) AS history_update,

    has_table_privilege(
        'rupaywala_app',
        'public.alembic_version',
        'DELETE'
    ) AS history_delete;


-- Table privilege summary
SELECT c.relname,
       has_table_privilege('rupaywala_app', c.oid, 'SELECT') AS sel,
       has_table_privilege('rupaywala_app', c.oid, 'INSERT') AS ins,
       has_table_privilege('rupaywala_app', c.oid, 'UPDATE') AS upd,
       has_table_privilege('rupaywala_app', c.oid, 'DELETE') AS del,
       has_table_privilege('rupaywala_app', c.oid, 'TRUNCATE') AS trunc,
       has_table_privilege('rupaywala_app', c.oid, 'TRIGGER') AS trig
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;


-- Sequence privilege summary
SELECT c.relname AS sequence_name,
       has_sequence_privilege('rupaywala_app', c.oid, 'USAGE') AS usage,
       has_sequence_privilege('rupaywala_app', c.oid, 'SELECT') AS sel,
       has_sequence_privilege('rupaywala_app', c.oid, 'UPDATE') AS upd
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'S'
ORDER BY c.relname;


-- Object owners
SELECT c.relname,
       c.relkind,
       pg_get_userbyid(c.relowner) AS owner
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
ORDER BY c.relname;


-- Type owners
SELECT t.typname,
       t.typtype,
       pg_get_userbyid(t.typowner) AS owner
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public'
  AND t.typtype IN ('e', 'd', 'c')
ORDER BY t.typtype, t.typname;


-- Function EXECUTE privileges
SELECT p.oid::regprocedure AS routine_name,
       has_function_privilege(
           'rupaywala_app', p.oid, 'EXECUTE'
       ) AS can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY routine_name;


-- Custom type USAGE privileges
SELECT t.oid::regtype AS type_name,
       has_type_privilege(
           'rupaywala_app', t.oid, 'USAGE'
       ) AS can_use
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public'
  AND t.typtype IN ('e', 'd', 'c')
ORDER BY type_name;


-- ============================================================
-- 1.9 ROLLBACK / RECOVERY PLAN
-- ============================================================

/*
PROPOSED ONLY - NOT EXECUTED.

Before implementation, record:
- Database owner and datacl
- Public schema owner and nspacl
- Relation owners and ACLs
- Type/domain owners and ACLs
- Default ACLs
- Role attributes and memberships
- PUBLIC grants
- Extension inventory
- Current Alembic revision
- Backup identifier and restore verification result

Rollback principles:

1. Put application into maintenance mode.
2. Stop application and migration sessions.
3. Restore recorded object owners explicitly.
4. Restore recorded ACLs with explicit GRANT/REVOKE.
5. Remove added default privileges.
6. Revoke owner membership from migrator only after
   ownership is safely restored.
7. Drop roles only after no objects remain owned by them.
8. Do not use DROP OWNED BY casually.
9. If corruption is suspected, restore into a new database
   and validate before switching traffic.
10. Validate revision, owners, ACLs, row counts,
    negative permission tests and application startup.

END OF STAGE 5.6C SQL ARTIFACT.
*/
