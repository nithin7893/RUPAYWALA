/*
RUPAYWALA - STAGE 5.6D
POSTGRESQL 18.1 ROLE AND PERMISSION ARTIFACT - CORRECTED, DISPOSABLE ONLY

Target environment (enforced below):
  container        : rupaywala-pg18-validation
  database         : rupaywala_validation
  login/owner user : validation_admin
  client mapping   : 127.0.0.1:55432 -> container 5432
  server port seen by inet_server_port() : 5432
  server version   : PostgreSQL 18.1

PRODUCTION DATABASE ACCESS IS STRICTLY OUT OF SCOPE. This file contains no
production connection instruction and must never be used against one.

STATUS: PREPARED - NOT EXECUTED. Run only with psql against the disposable
database after the separate bootstrap plan has reached 0005_fixed_quotes.

CLIENT-SIDE CONNECTION VERIFICATION (operator must perform before execution):
  psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=validation_admin" -c '\conninfo'
  Expected evidence: host=127.0.0.1, port=55432, dbname=rupaywala_validation,
  user=validation_admin.

SERVER-SIDE PORT FACT: inet_server_port() reports the PostgreSQL listener port
inside the container, which is 5432. It CANNOT prove the external Docker host
mapping 127.0.0.1:55432. The \conninfo command above verifies the client side.
\conninfo

Execution boundaries:
  * Sections 0-3 and 5-7, 9, 11-12 are DBA/bootstrap-administrator actions.
    validation_admin must be a superuser in the disposable container.
  * Section 4 is an OWNER-role action, entered explicitly with
    SET ROLE rupaywala_owner. Schema ownership alone does not make the DBA a
    member of the owning role; every ALTER ... OWNER TO is done as superuser.
  * Section 10 is the REQUIRED Alembic ownership runbook for a separate
     migrator connection. A psql-only SET ROLE demonstration is insufficient.
  * Section 8 is a LINE-COMMENTED APPLICATION-ROLE EXTRACT. It is never run by
    executing this file as the DBA. Copy/de-comment it into a separate psql
    session authenticated as rupaywala_app only after sections 0-7 pass.
  * Section 11 is the pre-0006 gate. It does not execute migration 0006.

Credential policy:
  * No password literal appears in this file.
  * New login roles use psql's interactive \password. Existing passwords are
    never reset.
  * Existing conflicting role configurations abort explicitly.
*/

\set ON_ERROR_STOP on

-- Normalise sequence rendering while keeping catalog objects qualified.
SET search_path = public, pg_catalog;

-- =====================================================================
-- 0. DBA / BOOTSTRAP: hard identity, version, port and superuser gates
-- =====================================================================

DO $$
DECLARE
    v_super boolean;
BEGIN
    IF current_database() IS DISTINCT FROM 'rupaywala_validation' THEN
        RAISE EXCEPTION
            'Refusing to run: current_database is %, expected rupaywala_validation',
            current_database();
    END IF;

    IF current_user IS DISTINCT FROM 'validation_admin' THEN
        RAISE EXCEPTION
            'Refusing to run: current_user is %, expected validation_admin',
            current_user;
    END IF;

    IF session_user IS DISTINCT FROM 'validation_admin' THEN
        RAISE EXCEPTION
            'Refusing to run: session_user is %, expected validation_admin',
            session_user;
    END IF;

    IF split_part(current_setting('server_version'), ' ', 1) IS DISTINCT FROM '18.1'
       OR current_setting('server_version_num') IS DISTINCT FROM '180001' THEN
        RAISE EXCEPTION
            'Refusing to run: server_version is % (num %), expected exactly PostgreSQL 18.1',
            current_setting('server_version'), current_setting('server_version_num');
    END IF;

    -- Internal container listener port only. External 55432 is verified above.
    IF inet_server_port() IS DISTINCT FROM 5432 THEN
        RAISE EXCEPTION
            'Refusing to run: inet_server_port() is %, expected internal port 5432',
            inet_server_port();
    END IF;

    IF inet_server_addr() IS NULL THEN
        RAISE EXCEPTION
            'Refusing to run: no server IP; connect over TCP through 127.0.0.1:55432';
    END IF;

    SELECT rolsuper INTO v_super FROM pg_catalog.pg_roles
    WHERE rolname = current_user;

    IF v_super IS NOT TRUE THEN
        RAISE EXCEPTION
            'Refusing to run: % is not a superuser; role creation and ALTER OWNER require it',
            current_user;
    END IF;

    RAISE NOTICE
        'Server gates passed: db=%, user=%, session=%, version=%, internal_port=%',
        current_database(), current_user, session_user,
        current_setting('server_version'), inet_server_port();
END $$;

SELECT current_database() AS db,
       current_user,
       session_user,
       current_setting('server_version') AS server_version,
       inet_server_addr()::text AS server_ip,
       inet_server_port() AS internal_server_port;

-- ---------------------------------------------------------------------
-- Record the original database owner BEFORE any operation.
-- psql variables are substituted here, outside any dollar-quoted DO body.
-- The value is copied into a session-level custom setting so DO blocks can
-- read it with current_setting() without :'variable' substitution.
-- ---------------------------------------------------------------------
SELECT COALESCE(
           (SELECT pg_catalog.pg_get_userbyid(datdba)
            FROM pg_catalog.pg_database
            WHERE datname = 'rupaywala_validation'),
           ''
       ) AS db_owner_before
\gset

SELECT pg_catalog.set_config('rupaywala.db_owner_before', :'db_owner_before', false)
       AS db_owner_before_setting;

DO $$
DECLARE
    v_before text := current_setting('rupaywala.db_owner_before', true);
    v_current text;
BEGIN
    IF v_before IS NULL OR v_before = '' THEN
        RAISE EXCEPTION
            'Could not record the owner of rupaywala_validation; aborting';
    END IF;

    SELECT pg_catalog.pg_get_userbyid(datdba) INTO v_current
    FROM pg_catalog.pg_database
    WHERE datname = 'rupaywala_validation';

    IF v_current IS NULL OR v_current IS DISTINCT FROM v_before THEN
        RAISE EXCEPTION
            'Database owner comparison failed: recorded %, observed %',
            v_before, v_current;
    END IF;

    RAISE NOTICE 'Database owner recorded and verified unchanged: %', v_before;
END $$;

-- Baseline inventories (evidence only; no ownership is changed here).
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
       rolbypassrls, rolreplication, rolinherit
FROM pg_catalog.pg_roles
WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')
ORDER BY rolname;

SELECT r.rolname AS member_role,
       m.rolname AS member_of,
       am.admin_option
FROM pg_catalog.pg_auth_members am
JOIN pg_catalog.pg_roles r ON r.oid = am.member
JOIN pg_catalog.pg_roles m ON m.oid = am.roleid
WHERE r.rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')
   OR m.rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')
ORDER BY r.rolname, m.rolname;

SELECT n.nspname,
       pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
       n.nspacl,
       e.extname AS extension_name
FROM pg_catalog.pg_namespace n
LEFT JOIN pg_catalog.pg_depend d
       ON d.classid = 'pg_catalog.pg_namespace'::regclass
      AND d.objid = n.oid
      AND d.deptype IN ('e', 'x')
      AND d.refclassid = 'pg_catalog.pg_extension'::regclass
LEFT JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
WHERE n.nspname = 'public';

SELECT c.oid::regclass AS object_name,
       c.relkind,
       pg_catalog.pg_get_userbyid(c.relowner) AS owner,
       c.relacl
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
ORDER BY c.relkind, c.relname;

SELECT t.oid::regtype AS type_name,
       t.typtype,
       pg_catalog.pg_get_userbyid(t.typowner) AS owner,
       t.typacl
FROM pg_catalog.pg_type t
JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public'
  AND t.typtype IN ('b', 'c', 'd', 'e', 'r', 'm')
ORDER BY t.typtype, t.typname;

SELECT p.oid::regprocedure AS routine_name,
       p.prokind,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner,
       p.proacl
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY p.prokind, routine_name;

SELECT defaclrole::regrole::text AS owner_role, CASE WHEN defaclnamespace=0 THEN 'GLOBAL' ELSE 'public' END AS scope,
       defaclobjtype, defaclacl
FROM pg_catalog.pg_default_acl
WHERE defaclrole::regrole::text IN ('rupaywala_owner','rupaywala_migrator')
  AND defaclnamespace IN (0,'public'::regnamespace::oid)
  AND defaclobjtype IN ('r','S','f','T','n','L')
ORDER BY 1,2,3;

SELECT extname, extversion, pg_catalog.pg_get_userbyid(extowner) AS owner
FROM pg_catalog.pg_extension
ORDER BY extname;

-- Strict revision gate for the SQL artifact itself (NOT the 0006 gate).
SELECT version_num AS revision_before
FROM public.alembic_version;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.alembic_version
        WHERE version_num = '0005_fixed_quotes'
    ) THEN
        RAISE EXCEPTION
            'Refusing to run: revision must be 0005_fixed_quotes before Stage 5.6D grants';
    END IF;
END $$;

-- =====================================================================
-- 1. DBA: validate any EXISTING target roles before proceeding.
--    This guard never changes a role; unsafe state aborts explicitly.
-- =====================================================================

DO $$
DECLARE
    problems text[] := ARRAY[]::text[];
    r record;
BEGIN
    FOR r IN
        SELECT p.rolname, p.rolcanlogin, p.rolsuper, p.rolcreatedb,
               p.rolcreaterole, p.rolbypassrls, p.rolreplication,
               p.rolinherit,
               EXISTS (
                   SELECT 1 FROM pg_catalog.pg_authid a
                   WHERE a.oid = p.oid
                     AND a.rolpassword IS NOT NULL
                     AND a.rolpassword <> ''
               ) AS has_password
        FROM pg_catalog.pg_roles p
        WHERE p.rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')
    LOOP
        IF r.rolsuper OR r.rolcreatedb OR r.rolcreaterole
           OR r.rolbypassrls OR r.rolreplication THEN
            problems := array_append(
                problems,
                format('%s has a forbidden privilege attribute', r.rolname)
            );
        END IF;

        IF r.rolname = 'rupaywala_owner' THEN
            IF r.rolcanlogin THEN
                problems := array_append(problems, 'rupaywala_owner must be NOLOGIN');
            END IF;
            IF NOT r.rolinherit THEN
                problems := array_append(problems,
                    'rupaywala_owner must be INHERIT (documented model)');
            END IF;
        ELSIF r.rolname = 'rupaywala_migrator' THEN
            IF NOT r.rolcanlogin THEN
                problems := array_append(problems, 'rupaywala_migrator must be LOGIN');
            END IF;
            IF NOT r.rolinherit THEN
                problems := array_append(problems, 'rupaywala_migrator must be INHERIT');
            END IF;
            IF NOT r.has_password THEN
                problems := array_append(problems,
                    'rupaywala_migrator exists without a password; provision it out of band');
            END IF;
        ELSIF r.rolname = 'rupaywala_app' THEN
            IF NOT r.rolcanlogin THEN
                problems := array_append(problems, 'rupaywala_app must be LOGIN');
            END IF;
            IF r.rolinherit THEN
                problems := array_append(problems, 'rupaywala_app must be NOINHERIT');
            END IF;
            IF NOT r.has_password THEN
                problems := array_append(problems,
                    'rupaywala_app exists without a password; provision it out of band');
            END IF;
        END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members am
               WHERE am.member = (SELECT oid FROM pg_catalog.pg_roles
                                  WHERE rolname = 'rupaywala_owner')) THEN
        problems := array_append(problems,
            'rupaywala_owner must not be a member of any role');
    END IF;

    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members am
               JOIN pg_catalog.pg_roles m ON m.oid = am.roleid
               WHERE am.member = (SELECT oid FROM pg_catalog.pg_roles
                                  WHERE rolname = 'rupaywala_migrator')
                 AND m.rolname <> 'rupaywala_owner') THEN
        problems := array_append(problems,
            'rupaywala_migrator has a membership other than rupaywala_owner');
    END IF;

    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members am
               WHERE am.member = (SELECT oid FROM pg_catalog.pg_roles
                                  WHERE rolname = 'rupaywala_migrator')
                 AND am.roleid = (SELECT oid FROM pg_catalog.pg_roles
                                  WHERE rolname = 'rupaywala_owner')
                 AND am.admin_option) THEN
        problems := array_append(problems,
            'rupaywala_migrator must not hold ADMIN OPTION on rupaywala_owner');
    END IF;

    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members am
               WHERE am.member = (SELECT oid FROM pg_catalog.pg_roles
                                  WHERE rolname = 'rupaywala_app')) THEN
        problems := array_append(problems,
            'rupaywala_app must not be a member of any role');
    END IF;

    IF array_length(problems, 1) > 0 THEN
        RAISE EXCEPTION
            'Existing role configuration conflicts with the 5.6D model: %',
            array_to_string(problems, '; ');
    END IF;
END $$;

-- =====================================================================
-- 1A. READ-ONLY FAIL-CLOSED PREFLIGHT BEFORE THE FIRST MUTATION
--     This is the pre-change counterpart of sections 7A, 7B and 13. It
--     inspects the disposable catalog only and aborts with exact findings
--     when existing state is unsafe. It never grants, revokes, creates,
--     alters, drops, reassigns, inserts, updates or deletes anything.
--     Missing target roles are allowed because Section 2 creates them.
--     Unexpected memberships, ACL entries, options, grant options, objects
--     and extension-owned objects are NOT repaired here; they require manual
--     investigation. The first mutation in this artifact is CREATE ROLE in
--     Section 2, which is reached only after all three preflight groups pass.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1A.1 H-05 PREFLIGHT: existing target-role memberships and PG18 options.
--      An absent migrator-to-owner row is allowed because Section 2 adds
--      the sole required membership. If that row already exists it must be
--      exactly inherit_option=true, set_option=true, admin_option=false.
--      Every other row touching the three target roles aborts the file.
-- ---------------------------------------------------------------------

SELECT pg_catalog.pg_get_userbyid(am.member) AS member_role,
       pg_catalog.pg_get_userbyid(am.roleid) AS granted_role,
       am.inherit_option,
       am.set_option,
       am.admin_option,
       CASE
           WHEN am.member = (SELECT oid FROM pg_catalog.pg_roles
                             WHERE rolname = 'rupaywala_migrator')
            AND am.roleid = (SELECT oid FROM pg_catalog.pg_roles
                             WHERE rolname = 'rupaywala_owner')
            AND am.inherit_option
            AND am.set_option
            AND NOT am.admin_option
           THEN 'PREFLIGHT_EXPECTED_MIGRATOR_TO_OWNER'
           ELSE 'PREFLIGHT_UNEXPECTED_MEMBERSHIP'
       END AS preflight_assessment
FROM pg_catalog.pg_auth_members am
WHERE am.member IN (SELECT oid FROM pg_catalog.pg_roles
                    WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app'))
   OR am.roleid IN (SELECT oid FROM pg_catalog.pg_roles
                    WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app'))
ORDER BY member_role, granted_role;

DO $$
DECLARE
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    v_migrator oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator');
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_count int;
    v_details text;
BEGIN
    WITH observed AS (
        SELECT am.member,
               am.roleid,
               am.inherit_option,
               am.set_option,
               am.admin_option,
               format('member=%s granted_role=%s inherit_option=%s set_option=%s admin_option=%s',
                      pg_catalog.pg_get_userbyid(am.member),
                      pg_catalog.pg_get_userbyid(am.roleid),
                      am.inherit_option,
                      am.set_option,
                      am.admin_option) AS state
        FROM pg_catalog.pg_auth_members am
        WHERE am.member IN (v_owner, v_migrator, v_app)
           OR am.roleid IN (v_owner, v_migrator, v_app)
    ),
    violations AS (
        SELECT 'PF_H05_UNEXPECTED_MEMBERSHIP'::text AS check_type,
               format('%s; detail=only an existing migrator-to-owner row is permitted; an absent row is allowed because Section 2 adds it; manual investigation required',
                      o.state) AS detail
        FROM observed o
        WHERE NOT (
            v_migrator IS NOT NULL
            AND v_owner IS NOT NULL
            AND o.member = v_migrator
            AND o.roleid = v_owner
        )

        UNION ALL

        SELECT 'PF_H05_INVALID_MIGRATOR_MEMBERSHIP_OPTIONS'::text AS check_type,
               format('%s; detail=expected inherit_option=true, set_option=true, admin_option=false; set_option is required by the Section 10 PGOPTIONS startup-role strategy; manual investigation required',
                      o.state) AS detail
        FROM observed o
        WHERE v_migrator IS NOT NULL
          AND v_owner IS NOT NULL
          AND o.member = v_migrator
          AND o.roleid = v_owner
          AND NOT (o.inherit_option AND o.set_option AND NOT o.admin_option)
    )
    SELECT count(*),
           string_agg(format('%s %s', check_type, detail), E'\n' ORDER BY check_type, detail)
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'PREFLIGHT H-05 failed for % membership finding(s); aborting before the first mutation; no role, membership, ACL, ownership or data was changed; manual investigation required:\n%',
            v_count, v_details;
    END IF;

    IF v_owner IS NOT NULL AND v_migrator IS NOT NULL THEN
        SELECT count(*) INTO v_count
        FROM pg_catalog.pg_auth_members
        WHERE member = v_migrator
          AND roleid = v_owner;

        IF v_count > 1 THEN
            RAISE EXCEPTION 'PREFLIGHT H-05: expected at most one migrator-to-owner membership row, observed %; aborting before mutation',
                v_count;
        END IF;
    END IF;

    RAISE NOTICE 'Preflight H-05 passed: no unexpected existing target-role membership or option was found';
END $$;

-- ---------------------------------------------------------------------
-- 1A.2 H-06 PREFLIGHT: database and public-schema ACL provenance BEFORE
--      grants and before the public-schema owner change. aclexplode() reads
--      direct ACL entries; NULL datacl/nspacl are expanded with acldefault()
--      so PostgreSQL defaults are treated as ACL provenance and are not
--      misreported as missing grants. Required PUBLIC defaults must already
--      exist. Optional target-only CONNECT/USAGE entries are allowed only if
--      non-grantable; their absence is allowed because Section 3 adds them.
--      Effective privilege checks are separate and never used to justify a
--      direct grant. No ACL is revoked or broadened here.
-- ---------------------------------------------------------------------

WITH db_entries AS (
    SELECT 'DATABASE'::text AS object_type,
           d.datname::text AS object_name,
           CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(a.grantee)
           END AS grantee,
           CASE WHEN a.privilege_type IN ('TEMP', 'TEMPORARY') THEN 'TEMPORARY'
                ELSE a.privilege_type
           END AS privilege,
           a.is_grantable AS grant_option,
           CASE WHEN d.datacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
    FROM pg_catalog.pg_database d
    CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
    WHERE d.datname = 'rupaywala_validation'
),
schema_entries AS (
    SELECT 'SCHEMA'::text AS object_type,
           n.nspname::text AS object_name,
           CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(a.grantee)
           END AS grantee,
           a.privilege_type AS privilege,
           a.is_grantable AS grant_option,
           CASE WHEN n.nspacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
    FROM pg_catalog.pg_namespace n
    CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
    WHERE n.nspname = 'public'
),
all_entries AS (
    SELECT * FROM db_entries
    UNION ALL
    SELECT * FROM schema_entries
)
SELECT e.object_type,
       e.object_name,
       e.grantee,
       e.privilege,
       e.grant_option,
       e.acl_source,
       CASE e.object_type
           WHEN 'DATABASE' THEN pg_catalog.has_database_privilege(
               CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
               e.object_name, e.privilege)
           WHEN 'SCHEMA' THEN pg_catalog.has_schema_privilege(
               CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
               e.object_name, e.privilege)
       END AS effective_privilege,
       CASE
           WHEN e.object_type = 'DATABASE' AND e.privilege = 'CREATE' THEN 'PREFLIGHT_DENY_CREATE'
           WHEN e.object_type = 'SCHEMA' AND e.grantee = 'PUBLIC' AND e.privilege = 'CREATE' THEN 'PREFLIGHT_DENY_PUBLIC_CREATE'
           ELSE 'PREFLIGHT_EVIDENCE_ONLY'
       END AS preflight_note
FROM all_entries e
WHERE e.grantee IN ('PUBLIC', 'rupaywala_app', 'rupaywala_owner', 'rupaywala_migrator')
ORDER BY e.object_type, e.object_name, e.grantee, e.privilege;

DO $$
DECLARE
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    v_migrator oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator');
    v_db text := 'rupaywala_validation';
    v_schema text := 'public';
    v_count int;
    v_details text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_database WHERE datname = v_db) THEN
        RAISE EXCEPTION 'PREFLIGHT H-06: disposable database % is missing; aborting before mutation', v_db;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = v_schema) THEN
        RAISE EXCEPTION 'PREFLIGHT H-06: schema % is missing; aborting before mutation', v_schema;
    END IF;

    WITH db_acl AS (
        SELECT 'DATABASE'::text AS object_type,
               d.datname::text AS object_name,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(a.grantee)
               END AS grantee,
               CASE WHEN a.privilege_type IN ('TEMP', 'TEMPORARY') THEN 'TEMPORARY'
                    ELSE a.privilege_type
               END AS privilege,
               a.is_grantable AS grant_option,
               CASE WHEN d.datacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
        FROM pg_catalog.pg_database d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
        WHERE d.datname = v_db
    ),
    schema_acl AS (
        SELECT 'SCHEMA'::text AS object_type,
               n.nspname::text AS object_name,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(a.grantee)
               END AS grantee,
               a.privilege_type AS privilege,
               a.is_grantable AS grant_option,
               CASE WHEN n.nspacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
        FROM pg_catalog.pg_namespace n
        CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
        WHERE n.nspname = v_schema
    ),
    direct_acl AS (
        SELECT * FROM db_acl
        UNION ALL
        SELECT * FROM schema_acl
    ),
    pre_allowed(object_type, grantee, privilege, required, expected_grant_option) AS (
        VALUES
            ('DATABASE'::text, 'PUBLIC'::text, 'CONNECT'::text, true, false),
            ('DATABASE'::text, 'PUBLIC'::text, 'TEMPORARY'::text, true, false),
            ('DATABASE'::text, 'rupaywala_app'::text, 'CONNECT'::text, false, false),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'CONNECT'::text, false, false),
            ('SCHEMA'::text, 'PUBLIC'::text, 'USAGE'::text, true, false),
            ('SCHEMA'::text, 'rupaywala_app'::text, 'USAGE'::text, false, false),
            ('SCHEMA'::text, 'rupaywala_owner'::text, 'CREATE'::text, false, false),
            ('SCHEMA'::text, 'rupaywala_owner'::text, 'USAGE'::text, false, false)
    ),
    unexpected_acl AS (
        SELECT 'PF_H06_UNEXPECTED_DIRECT_ACL'::text AS check_type,
               d.object_type,
               d.object_name,
               d.grantee,
               d.privilege,
               d.grant_option,
               d.acl_source,
               format('acl_source=%s; detail=entry is not in the preflight allowlist or has a grant option; manual investigation required',
                      d.acl_source) AS detail
        FROM direct_acl d
        LEFT JOIN pre_allowed a
          ON a.object_type = d.object_type
         AND a.grantee = d.grantee
         AND a.privilege = d.privilege
        WHERE d.grantee IN ('PUBLIC', 'rupaywala_app', 'rupaywala_owner', 'rupaywala_migrator')
          AND (
              a.object_type IS NULL
              OR d.grant_option IS DISTINCT FROM a.expected_grant_option
          )
    ),
    missing_required AS (
        SELECT 'PF_H06_MISSING_DEFAULT_ACL'::text AS check_type,
               e.object_type,
               CASE e.object_type WHEN 'DATABASE' THEN v_db ELSE v_schema END AS object_name,
               e.grantee,
               e.privilege,
               NULL::boolean AS grant_option,
               NULL::text AS acl_source,
               'detail=required PostgreSQL default ACL provenance is absent; manual investigation required'::text AS detail
        FROM pre_allowed e
        WHERE e.required
          AND NOT EXISTS (
              SELECT 1 FROM direct_acl d
              WHERE d.object_type = e.object_type
                AND d.grantee = e.grantee
                AND d.privilege = e.privilege
          )
    ),
    effective_expected(object_type, grantee, privilege, expected) AS (
        VALUES
            ('DATABASE'::text, 'PUBLIC'::text, 'CONNECT'::text, true),
            ('DATABASE'::text, 'PUBLIC'::text, 'TEMPORARY'::text, true),
            ('DATABASE'::text, 'PUBLIC'::text, 'CREATE'::text, false),
            ('DATABASE'::text, 'rupaywala_app'::text, 'CREATE'::text, false),
            ('DATABASE'::text, 'rupaywala_owner'::text, 'CREATE'::text, false),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'CREATE'::text, false),
            ('SCHEMA'::text, 'PUBLIC'::text, 'USAGE'::text, true),
            ('SCHEMA'::text, 'PUBLIC'::text, 'CREATE'::text, false),
            ('SCHEMA'::text, 'rupaywala_app'::text, 'CREATE'::text, false)
    ),
    effective_mismatch AS (
        SELECT 'PF_H06_EFFECTIVE_PRIVILEGE_MISMATCH'::text AS check_type,
               e.object_type,
               CASE e.object_type WHEN 'DATABASE' THEN v_db ELSE v_schema END AS object_name,
               e.grantee,
               e.privilege,
               NULL::boolean AS grant_option,
               NULL::text AS acl_source,
               format('expected=%s observed=%s; detail=effective privilege is unsafe before grants; manual investigation required',
                      e.expected, o.effective) AS detail
        FROM effective_expected e
        CROSS JOIN LATERAL (
            SELECT CASE e.object_type
                       WHEN 'DATABASE' THEN pg_catalog.has_database_privilege(
                           CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
                           v_db, e.privilege)
                       WHEN 'SCHEMA' THEN pg_catalog.has_schema_privilege(
                           CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
                           v_schema, e.privilege)
                   END AS effective
        ) o
        WHERE (e.grantee = 'PUBLIC'
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = e.grantee))
          AND o.effective IS DISTINCT FROM e.expected
    ),
    violations AS (
        SELECT check_type, object_type, object_name, grantee, privilege, grant_option, acl_source, detail FROM unexpected_acl
        UNION ALL SELECT check_type, object_type, object_name, grantee, privilege, grant_option, acl_source, detail FROM missing_required
        UNION ALL SELECT check_type, object_type, object_name, grantee, privilege, grant_option, acl_source, detail FROM effective_mismatch
    )
    SELECT count(*),
           string_agg(
               format('%s object_type=%s object=%s grantee=%s privilege=%s grant_option=%s acl_source=%s %s',
                      check_type, object_type, object_name, grantee, privilege,
                      COALESCE(grant_option::text, '-'), COALESCE(acl_source, '-'), detail),
               E'\n' ORDER BY check_type, object_type, object_name, grantee, privilege)
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'PREFLIGHT H-06 failed for % database/schema ACL finding(s); aborting before the first mutation; no ACL was revoked or broadened; manual investigation required:\n%',
            v_count, v_details;
    END IF;

    RAISE NOTICE 'Preflight H-06 passed: required PUBLIC defaults exist and no unexpected direct ACL, grant option or unsafe effective CREATE was found';
END $$;

-- ---------------------------------------------------------------------
-- 1A.3 SECTION 13 PREFLIGHT: full public relation/sequence inventory and
--      app/PUBLIC allowlist BEFORE ownership transfer and grants. Every
--      public r/p/v/m/f/S object is classified. Extension-owned objects are
--      detected with the same pg_depend -> pg_extension pattern used by the
--      Section 3 ownership transfer; they are reported explicitly and abort
--      here instead of being silently treated as ordinary application objects
--      or deferred to a post-change assertion. Missing expected objects,
--      unlisted objects, wrong relkinds, unexpected PUBLIC/app object ACLs,
--      app grant options and forbidden pre-existing effective app privileges
--      abort before mutation. Expected app grants may be absent because
--      Section 4 adds them; they are never revoked here.
-- ---------------------------------------------------------------------

SELECT c.oid::regclass AS object_name,
       c.relkind,
       pg_catalog.pg_get_userbyid(c.relowner) AS owner,
       c.relacl,
       x.extension_names,
       CASE WHEN x.extension_names IS NULL
            THEN 'APPLICATION_SCOPE' ELSE 'EXTENSION_OWNED' END AS preflight_scope,
       CASE WHEN c.relkind = 'S'
                 AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app') THEN
           jsonb_build_object(
               'USAGE', pg_catalog.has_sequence_privilege('rupaywala_app', c.oid, 'USAGE'),
               'SELECT', pg_catalog.has_sequence_privilege('rupaywala_app', c.oid, 'SELECT'),
               'UPDATE', pg_catalog.has_sequence_privilege('rupaywala_app', c.oid, 'UPDATE'))
       WHEN c.relkind <> 'S'
                 AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app') THEN
           jsonb_build_object(
               'SELECT', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'SELECT'),
               'INSERT', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'INSERT'),
               'UPDATE', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'UPDATE'),
               'DELETE', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'DELETE'),
               'TRUNCATE', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'TRUNCATE'),
               'TRIGGER', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'TRIGGER'),
               'REFERENCES', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'REFERENCES'),
               'MAINTAIN', pg_catalog.has_table_privilege('rupaywala_app', c.oid, 'MAINTAIN'))
       ELSE NULL::jsonb END AS app_effective_privileges,
       (SELECT jsonb_agg(jsonb_build_object(
                   'grantee', CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee) END,
                   'privilege', a.privilege_type,
                   'grantable', a.is_grantable))
        FROM aclexplode(COALESCE(
                 c.relacl,
                 acldefault((CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END)::"char", c.relowner))) a
        WHERE a.grantee = 0
           OR a.grantee = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app'))
       AS app_public_acl_entries
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN LATERAL (
    SELECT string_agg(DISTINCT e.extname, ', ') AS extension_names
    FROM pg_catalog.pg_depend d
    JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
    WHERE d.classid = 'pg_catalog.pg_class'::regclass
      AND d.objid = c.oid
      AND d.deptype IN ('e', 'x')
      AND d.refclassid = 'pg_catalog.pg_extension'::regclass
) x ON true
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
ORDER BY c.relkind, c.relname;

DO $$
DECLARE
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_count int;
    v_details text;
BEGIN
    WITH expected_rel(relname, sel, ins, upd, del) AS (
        VALUES
            ('users'::text, true, true, true, false),
            ('branches'::text, true, true, true, false),
            ('customer_profiles'::text, true, true, true, false),
            ('field_members'::text, true, true, true, false),
            ('notifications'::text, true, true, true, true),
            ('otp_verifications'::text, true, true, true, true),
            ('payments'::text, true, true, true, false),
            ('policies'::text, true, true, false, true),
            ('policy_members'::text, true, true, false, true),
            ('request_assignments'::text, true, true, true, false),
            ('service_quotes'::text, true, true, true, false),
            ('service_requests'::text, true, true, true, false),
            ('service_types'::text, true, true, true, false),
            ('subscription_plans'::text, true, true, true, false),
            ('subscription_family_members'::text, true, true, false, true),
            ('user_subscriptions'::text, true, true, true, false),
            ('visit_ledger'::text, true, true, false, false),
            ('distance_rate_config'::text, true, true, false, false),
            ('family_members'::text, false, false, false, false),
            ('alembic_version'::text, false, false, false, false)
    ),
    expected_seq(table_name, usage, sel, upd) AS (
        VALUES
            ('users'::text, true, false, false),
            ('branches'::text, true, false, false),
            ('customer_profiles'::text, true, false, false),
            ('field_members'::text, true, false, false),
            ('notifications'::text, true, false, false),
            ('otp_verifications'::text, true, false, false),
            ('payments'::text, true, false, false),
            ('policies'::text, true, false, false),
            ('policy_members'::text, true, false, false),
            ('request_assignments'::text, true, false, false),
            ('service_quotes'::text, true, false, false),
            ('service_requests'::text, true, false, false),
            ('service_types'::text, true, false, false),
            ('subscription_plans'::text, true, false, true),
            ('subscription_family_members'::text, true, false, false),
            ('user_subscriptions'::text, true, false, false),
            ('visit_ledger'::text, true, false, false),
            ('distance_rate_config'::text, true, false, false)
    ),
    expected_seq_oid AS (
        SELECT es.table_name,
               NULLIF(pg_catalog.pg_get_serial_sequence(format('public.%I', es.table_name), 'id'), '')::regclass AS seq_oid,
               es.usage, es.sel, es.upd
        FROM expected_seq es
    ),
    expected_objects AS (
        SELECT c.oid AS obj_oid,
               ARRAY['r', 'p']::text[] AS expected_kinds,
               er.sel, er.ins, er.upd, er.del,
               NULL::boolean AS seq_usage, NULL::boolean AS seq_sel, NULL::boolean AS seq_upd
        FROM expected_rel er
        JOIN pg_catalog.pg_class c ON c.oid = to_regclass(format('public.%I', er.relname))
        UNION ALL
        SELECT c.oid,
               ARRAY['S']::text[],
               NULL::boolean, NULL::boolean, NULL::boolean, NULL::boolean,
               eso.usage, eso.sel, eso.upd
        FROM expected_seq_oid eso
        JOIN pg_catalog.pg_class c ON c.oid = eso.seq_oid
        WHERE eso.seq_oid IS NOT NULL
    ),
    scope AS (
        SELECT c.oid,
               c.relkind,
               c.relname,
               c.relowner,
               COALESCE(c.relacl,
                        acldefault((CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END)::"char", c.relowner)) AS expanded_acl,
               x.extension_names
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN LATERAL (
            SELECT string_agg(DISTINCT e.extname, ', ') AS extension_names
            FROM pg_catalog.pg_depend d
            JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
            WHERE d.classid = 'pg_catalog.pg_class'::regclass
              AND d.objid = c.oid
              AND d.deptype IN ('e', 'x')
              AND d.refclassid = 'pg_catalog.pg_extension'::regclass
        ) x ON true
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
    ),
    missing_rel AS (
        SELECT 'PF_13_MISSING_EXPECTED_RELATION'::text AS check_type,
               format('public.%I', er.relname) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               'detail=expected relation is absent; manual investigation required'::text AS detail
        FROM expected_rel er
        WHERE to_regclass(format('public.%I', er.relname)) IS NULL
    ),
    missing_seq AS (
        SELECT 'PF_13_MISSING_EXPECTED_SEQUENCE'::text AS check_type,
               format('id sequence for public.%I', eso.table_name) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               'detail=pg_get_serial_sequence returned no sequence; manual investigation required'::text AS detail
        FROM expected_seq_oid eso
        WHERE eso.seq_oid IS NULL
    ),
    extension_objects AS (
        SELECT 'PF_13_EXTENSION_OWNED_OBJECT'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               format('relkind=%s extension=%s; detail=extension-owned object is excluded by the Section 3 transfer pattern and is not an ordinary application object; manual investigation required',
                      s.relkind::text, s.extension_names) AS detail
        FROM scope s
        WHERE s.extension_names IS NOT NULL
    ),
    unlisted AS (
        SELECT 'PF_13_UNLISTED_OBJECT'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               format('detail=unexpected non-extension object with relkind=%s in public; manual investigation required',
                      s.relkind::text) AS detail
        FROM scope s
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        WHERE e.obj_oid IS NULL
          AND s.extension_names IS NULL
    ),
    relkind_mismatch AS (
        SELECT 'PF_13_RELKIND_MISMATCH'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               format('expected relkind in [%s], observed %s; manual investigation required',
                      array_to_string(e.expected_kinds, ','), s.relkind::text) AS detail
        FROM scope s
        JOIN expected_objects e ON e.obj_oid = s.oid
        WHERE s.extension_names IS NULL
          AND NOT (s.relkind::text = ANY(e.expected_kinds))
    ),
    direct_acl AS (
        SELECT 'PF_13_UNEXPECTED_DIRECT_ACL'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               a.privilege_type AS privilege,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee) END AS grantee,
               CASE
                   WHEN a.grantee = 0 THEN 'PUBLIC object ACL is not allowed'
                   WHEN a.is_grantable THEN 'WITH GRANT OPTION is not allowed'
                   WHEN v_app IS NULL THEN 'app role absent; direct app ACL cannot be pre-validated'
                   WHEN e.obj_oid IS NULL THEN 'unlisted object has a direct app ACL'
                   ELSE 'privilege is not in the expected app allowlist'
               END AS detail
        FROM scope s
        CROSS JOIN LATERAL aclexplode(s.expanded_acl) a
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        WHERE s.extension_names IS NULL
          AND (
              a.grantee = 0
              OR (v_app IS NOT NULL AND a.grantee = v_app)
          )
          AND (
              a.grantee = 0
              OR a.is_grantable
              OR v_app IS NULL
              OR e.obj_oid IS NULL
              OR CASE
                     WHEN s.relkind = 'S' THEN NOT (
                          (a.privilege_type = 'USAGE' AND COALESCE(e.seq_usage, false))
                       OR (a.privilege_type = 'SELECT' AND COALESCE(e.seq_sel, false))
                       OR (a.privilege_type = 'UPDATE' AND COALESCE(e.seq_upd, false))
                     )
                     ELSE NOT (
                          (a.privilege_type = 'SELECT' AND COALESCE(e.sel, false))
                       OR (a.privilege_type = 'INSERT' AND COALESCE(e.ins, false))
                       OR (a.privilege_type = 'UPDATE' AND COALESCE(e.upd, false))
                       OR (a.privilege_type = 'DELETE' AND COALESCE(e.del, false))
                     )
                 END
          )
    ),
    forbidden_effective_rel AS (
        SELECT 'PF_13_UNEXPECTED_EFFECTIVE_PRIVILEGE'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               p.privilege AS privilege,
               'rupaywala_app'::text AS grantee,
               'detail=app already has a forbidden effective table privilege before grants; manual investigation required'::text AS detail
        FROM scope s
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        CROSS JOIN LATERAL (VALUES
            ('SELECT', COALESCE(e.sel, false)),
            ('INSERT', COALESCE(e.ins, false)),
            ('UPDATE', COALESCE(e.upd, false)),
            ('DELETE', COALESCE(e.del, false)),
            ('TRUNCATE', false),
            ('TRIGGER', false),
            ('REFERENCES', false),
            ('MAINTAIN', false)
        ) p(privilege, expected)
        WHERE v_app IS NOT NULL
          AND s.relkind <> 'S'
          AND s.extension_names IS NULL
          AND NOT p.expected
          AND pg_catalog.has_table_privilege(v_app, s.oid, p.privilege)
    ),
    forbidden_effective_seq AS (
        SELECT 'PF_13_UNEXPECTED_EFFECTIVE_PRIVILEGE'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               p.privilege AS privilege,
               'rupaywala_app'::text AS grantee,
               'detail=app already has a forbidden effective sequence privilege before grants; manual investigation required'::text AS detail
        FROM scope s
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        CROSS JOIN LATERAL (VALUES
            ('USAGE', COALESCE(e.seq_usage, false)),
            ('SELECT', COALESCE(e.seq_sel, false)),
            ('UPDATE', COALESCE(e.seq_upd, false))
        ) p(privilege, expected)
        WHERE v_app IS NOT NULL
          AND s.relkind = 'S'
          AND s.extension_names IS NULL
          AND NOT p.expected
          AND pg_catalog.has_sequence_privilege(v_app, s.oid, p.privilege)
    ),
    violations AS (
        SELECT * FROM missing_rel
        UNION ALL SELECT * FROM missing_seq
        UNION ALL SELECT * FROM extension_objects
        UNION ALL SELECT * FROM unlisted
        UNION ALL SELECT * FROM relkind_mismatch
        UNION ALL SELECT * FROM direct_acl
        UNION ALL SELECT * FROM forbidden_effective_rel
        UNION ALL SELECT * FROM forbidden_effective_seq
    )
    SELECT count(*),
           string_agg(
               format('%s object=%s privilege=%s grantee=%s %s',
                      check_type, object_name, COALESCE(privilege, '-'),
                      COALESCE(grantee, '-'), detail),
               E'\n' ORDER BY check_type, object_name, privilege, grantee)
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'PREFLIGHT section 13 failed for % public object finding(s); aborting before the first mutation; no ownership, grant, ACL or data was changed; manual investigation required:\n%',
            v_count, v_details;
    END IF;

    RAISE NOTICE 'Preflight section 13 passed: public object inventory matches the allowlist and contains no extension-owned object';
END $$;

-- ---------------------------------------------------------------------
-- 1A.4 SECTION 7.10 PREFLIGHT: privilege provenance not normalized by 2-5.
--      Sections 4-5 intentionally reconcile ONLY per-schema r/S default
--      ACLs for rupaywala_owner and rupaywala_migrator (REVOKE ALL FROM
--      rupaywala_app, then GRANT SELECT/USAGE TO rupaywala_app) and existing
--      relation/sequence app grants. Those states may be absent or wrong here
--      because Sections 4-5 safely normalize them before Section 7.10 runs.
--      This preflight never revokes, grants, or repairs anything. It reads the
--      other Section 7.10 states that this script does NOT modify: GLOBAL
--      default ACLs for all six PG18 object classes, global-only n/L rows,
--      built-in PUBLIC USAGE/EXECUTE preservation for T/f defaults, existing
--      custom type and routine ACLs, effective app USAGE/EXECUTE, and
--      app/PUBLIC grant options outside the normalized per-schema r/S set.
--      Every finding reports exact object, grantee, privilege, ACL source and
--      grant-option state, then aborts before CREATE ROLE.
-- ---------------------------------------------------------------------

SELECT pg_catalog.pg_get_userbyid(d.defaclrole) AS default_role,
       CASE WHEN d.defaclnamespace = 0 THEN 'GLOBAL' ELSE 'public' END AS scope,
       d.defaclobjtype::text AS object_class,
       d.defaclacl IS NULL AS defaclacl_is_null,
       a.grantee,
       a.privilege,
       a.grant_option
FROM pg_catalog.pg_default_acl d
LEFT JOIN LATERAL (
    SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(x.grantee)
           END AS grantee,
           x.privilege_type AS privilege,
           x.is_grantable AS grant_option
    FROM aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) x
) a ON true
WHERE pg_catalog.pg_get_userbyid(d.defaclrole) IN ('rupaywala_owner', 'rupaywala_migrator')
  AND d.defaclobjtype::text IN ('r', 'S', 'f', 'T', 'n', 'L')
  AND d.defaclnamespace IN (0, 'public'::regnamespace::oid)
ORDER BY 1, 2, 3, 5, 6;

SELECT format('TYPE public.%I', t.typname) AS object,
       CASE WHEN t.typacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source,
       pg_catalog.has_type_privilege(
           (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app'),
           t.oid, 'USAGE') AS app_effective_usage,
       a.grantee,
       a.privilege,
       a.grant_option
FROM pg_catalog.pg_type t
JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
LEFT JOIN LATERAL (
    SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(x.grantee)
           END AS grantee,
           x.privilege_type AS privilege,
           x.is_grantable AS grant_option
    FROM aclexplode(COALESCE(t.typacl, acldefault('T', t.typowner))) x
) a ON true
WHERE n.nspname = 'public'
  AND (
      t.typtype IN ('e', 'd')
      OR (t.typtype = 'c' AND EXISTS (
          SELECT 1 FROM pg_catalog.pg_class rc
          WHERE rc.oid = t.typrelid AND rc.relkind = 'c'))
  )
  AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_depend d
      WHERE d.classid = 'pg_catalog.pg_type'::regclass
        AND d.objid = t.oid
        AND d.deptype IN ('e', 'x')
        AND d.refclassid = 'pg_catalog.pg_extension'::regclass
  )
ORDER BY 1, 4, 5;

SELECT format('ROUTINE public.%I(%s)',
              p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)) AS object,
       CASE WHEN p.proacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source,
       pg_catalog.has_function_privilege(
           (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app'),
           p.oid, 'EXECUTE') AS app_effective_execute,
       a.grantee,
       a.privilege,
       a.grant_option
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
LEFT JOIN LATERAL (
    SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(x.grantee)
           END AS grantee,
           x.privilege_type AS privilege,
           x.is_grantable AS grant_option
    FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) x
) a ON true
WHERE n.nspname = 'public'
  AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_depend d
      WHERE d.classid = 'pg_catalog.pg_proc'::regclass
        AND d.objid = p.oid
        AND d.deptype IN ('e', 'x')
        AND d.refclassid = 'pg_catalog.pg_extension'::regclass
  )
ORDER BY 1, 4, 5;

DO $$
DECLARE
    v_public oid := 0;
    v_public_schema oid := 'public'::regnamespace::oid;
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    v_migrator oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator');
    v_count int;
    v_details text;
BEGIN
    WITH default_entries AS (
        SELECT
            CASE WHEN d.defaclnamespace = 0 THEN 'GLOBAL' ELSE 'PUBLIC_SCHEMA' END AS scope,
            d.defaclobjtype::text AS objtype,
            pg_catalog.pg_get_userbyid(d.defaclrole) AS default_role,
            CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                 ELSE pg_catalog.pg_get_userbyid(a.grantee)
            END AS grantee,
            a.privilege_type AS privilege,
            a.is_grantable AS grant_option,
            (v_app IS NOT NULL AND a.grantee = v_app) AS is_app,
            (a.grantee = 0) AS is_public,
            format('%s default ACL for role %s objtype %s',
                   CASE WHEN d.defaclnamespace = 0 THEN 'GLOBAL' ELSE 'PUBLIC_SCHEMA' END,
                   pg_catalog.pg_get_userbyid(d.defaclrole),
                   d.defaclobjtype::text) AS object_name,
            CASE WHEN d.defaclnamespace = 0 THEN 'PG_DEFAULT_ACL_GLOBAL'
                 ELSE 'PG_DEFAULT_ACL_PUBLIC_SCHEMA'
            END AS acl_source
        FROM pg_catalog.pg_default_acl d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
        WHERE d.defaclrole IN (v_owner, v_migrator)
          AND d.defaclobjtype::text IN ('r', 'S', 'f', 'T', 'n', 'L')
          AND d.defaclnamespace IN (0, v_public_schema)
    ),
    default_row_violations AS (
        SELECT 'PF_710_PER_SCHEMA_GLOBAL_ONLY_DEFAULT'::text AS check_type,
               format('PUBLIC_SCHEMA default ACL for role %s objtype %s',
                      pg_catalog.pg_get_userbyid(d.defaclrole),
                      d.defaclobjtype::text) AS object_name,
               'ANY'::text AS grantee,
               'ANY'::text AS privilege,
               'PG_DEFAULT_ACL_PUBLIC_SCHEMA'::text AS acl_source,
               '-'::text AS grant_option,
               format('defaclrole=%s defaclnamespace=public objtype=%s; detail=PG18 n/L defaults are global-only and are not modified by Sections 4-5; manual investigation required',
                      pg_catalog.pg_get_userbyid(d.defaclrole),
                      d.defaclobjtype::text) AS detail
        FROM pg_catalog.pg_default_acl d
        WHERE d.defaclrole IN (v_owner, v_migrator)
          AND d.defaclobjtype::text IN ('n', 'L')
          AND d.defaclnamespace = v_public_schema

        UNION ALL

        SELECT 'PF_710_MISSING_GLOBAL_PUBLIC_TYPE_USAGE'::text,
               format('GLOBAL default ACL for role %s objtype T',
                      pg_catalog.pg_get_userbyid(d.defaclrole)),
               'PUBLIC'::text,
               'USAGE'::text,
               'PG_DEFAULT_ACL_GLOBAL'::text,
               '-'::text,
               'detail=built-in PUBLIC USAGE on future types is absent from the GLOBAL default; Sections 4-5 do not modify it; manual investigation required'::text
        FROM pg_catalog.pg_default_acl d
        WHERE d.defaclrole IN (v_owner, v_migrator)
          AND d.defaclnamespace = 0
          AND d.defaclobjtype::text = 'T'
          AND NOT EXISTS (
              SELECT 1
              FROM aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
              WHERE a.grantee = 0
                AND a.privilege_type = 'USAGE'
                AND NOT a.is_grantable
          )

        UNION ALL

        SELECT 'PF_710_MISSING_GLOBAL_PUBLIC_ROUTINE_EXECUTE'::text,
               format('GLOBAL default ACL for role %s objtype f',
                      pg_catalog.pg_get_userbyid(d.defaclrole)),
               'PUBLIC'::text,
               'EXECUTE'::text,
               'PG_DEFAULT_ACL_GLOBAL'::text,
               '-'::text,
               'detail=built-in PUBLIC EXECUTE on future routines is absent from the GLOBAL default; Sections 4-5 do not modify it; manual investigation required'::text
        FROM pg_catalog.pg_default_acl d
        WHERE d.defaclrole IN (v_owner, v_migrator)
          AND d.defaclnamespace = 0
          AND d.defaclobjtype::text = 'f'
          AND NOT EXISTS (
              SELECT 1
              FROM aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
              WHERE a.grantee = 0
                AND a.privilege_type = 'EXECUTE'
                AND NOT a.is_grantable
          )
    ),
    default_entry_violations AS (
        SELECT 'PF_710_UNEXPECTED_DEFAULT_ACL'::text AS check_type,
               e.object_name,
               e.grantee,
               e.privilege,
               e.acl_source,
               e.grant_option::text,
               format('default_role=%s scope=%s objtype=%s; detail=default ACL entry is not normalized by Sections 4-5 and is not allowed by Section 7.10; manual investigation required',
                      e.default_role, e.scope, e.objtype) AS detail
        FROM default_entries e
        WHERE (
            (e.grant_option AND NOT (e.scope = 'PUBLIC_SCHEMA' AND e.objtype IN ('r', 'S') AND e.is_app))
            OR e.objtype IN ('n', 'L')
            OR (e.is_app AND e.scope = 'GLOBAL')
            OR (e.scope = 'GLOBAL' AND e.objtype IN ('r', 'S'))
            OR (e.objtype = 'T' AND NOT (e.is_public AND e.privilege = 'USAGE' AND NOT e.grant_option))
            OR (e.objtype = 'f' AND NOT (e.is_public AND e.privilege = 'EXECUTE' AND NOT e.grant_option))
            OR (e.scope = 'PUBLIC_SCHEMA' AND e.objtype IN ('r', 'S') AND NOT e.is_app)
        )
    ),
    custom_types AS (
        SELECT t.oid,
               t.typname,
               t.typacl,
               t.typowner,
               format('TYPE public.%I', t.typname) AS object_name,
               CASE WHEN t.typacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
        FROM pg_catalog.pg_type t
        JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
        WHERE n.oid = v_public_schema
          AND (
              t.typtype IN ('e', 'd')
              OR (t.typtype = 'c' AND EXISTS (
                  SELECT 1 FROM pg_catalog.pg_class rc
                  WHERE rc.oid = t.typrelid AND rc.relkind = 'c'))
          )
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
    ),
    custom_type_entries AS (
        SELECT ct.object_name,
               ct.acl_source,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(a.grantee)
               END AS grantee,
               a.privilege_type AS privilege,
               a.is_grantable AS grant_option,
               (v_app IS NOT NULL AND a.grantee = v_app) AS is_app,
               (a.grantee = 0) AS is_public
        FROM custom_types ct
        CROSS JOIN LATERAL aclexplode(COALESCE(ct.typacl, acldefault('T', ct.typowner))) a
    ),
    custom_type_violations AS (
        SELECT 'PF_710_TYPE_EFFECTIVE_USAGE'::text AS check_type,
               ct.object_name,
               'rupaywala_app'::text AS grantee,
               'USAGE'::text AS privilege,
               'EFFECTIVE_PRIVILEGE'::text AS acl_source,
               '-'::text AS grant_option,
               format('acl_source=%s expected=true observed=%s; detail=effective app USAGE cannot be proven before mutation; manual investigation required',
                      ct.acl_source,
                      pg_catalog.has_type_privilege(v_app, ct.oid, 'USAGE')::text) AS detail
        FROM custom_types ct
        WHERE v_app IS NOT NULL
          AND NOT pg_catalog.has_type_privilege(v_app, ct.oid, 'USAGE')

        UNION ALL

        SELECT 'PF_710_TYPE_MISSING_PUBLIC_USAGE'::text,
               ct.object_name,
               'PUBLIC'::text,
               'USAGE'::text,
               ct.acl_source,
               '-'::text,
               'detail=built-in PUBLIC USAGE is absent from the object ACL; Sections 4-5 do not modify type ACLs; manual investigation required'::text
        FROM custom_types ct
        WHERE NOT EXISTS (
            SELECT 1
            FROM aclexplode(COALESCE(ct.typacl, acldefault('T', ct.typowner))) a
            WHERE a.grantee = 0
              AND a.privilege_type = 'USAGE'
              AND NOT a.is_grantable
        )

        UNION ALL

        SELECT 'PF_710_TYPE_GRANT_OPTION'::text,
               e.object_name,
               e.grantee,
               e.privilege,
               e.acl_source,
               e.grant_option::text,
               'detail=app/PUBLIC WITH GRANT OPTION on a custom type ACL is not modified by Sections 4-5; manual investigation required'::text
        FROM custom_type_entries e
        WHERE (e.is_public OR e.is_app)
          AND e.grant_option
    ),
    routines AS (
        SELECT p.oid,
               p.proname,
               p.proacl,
               p.proowner,
               format('ROUTINE public.%I(%s)',
                      p.proname,
                      pg_catalog.pg_get_function_identity_arguments(p.oid)) AS object_name,
               CASE WHEN p.proacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.oid = v_public_schema
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_proc'::regclass
                AND d.objid = p.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
    ),
    routine_entries AS (
        SELECT r.object_name,
               r.acl_source,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(a.grantee)
               END AS grantee,
               a.privilege_type AS privilege,
               a.is_grantable AS grant_option,
               (v_app IS NOT NULL AND a.grantee = v_app) AS is_app,
               (a.grantee = 0) AS is_public
        FROM routines r
        CROSS JOIN LATERAL aclexplode(COALESCE(r.proacl, acldefault('f', r.proowner))) a
    ),
    routine_violations AS (
        SELECT 'PF_710_ROUTINE_EFFECTIVE_EXECUTE'::text AS check_type,
               r.object_name,
               'rupaywala_app'::text AS grantee,
               'EXECUTE'::text AS privilege,
               'EFFECTIVE_PRIVILEGE'::text AS acl_source,
               '-'::text AS grant_option,
               format('acl_source=%s expected=true observed=%s; detail=effective app EXECUTE cannot be proven before mutation; manual investigation required',
                      r.acl_source,
                      pg_catalog.has_function_privilege(v_app, r.oid, 'EXECUTE')::text) AS detail
        FROM routines r
        WHERE v_app IS NOT NULL
          AND NOT pg_catalog.has_function_privilege(v_app, r.oid, 'EXECUTE')

        UNION ALL

        SELECT 'PF_710_ROUTINE_MISSING_PUBLIC_EXECUTE'::text,
               r.object_name,
               'PUBLIC'::text,
               'EXECUTE'::text,
               r.acl_source,
               '-'::text,
               'detail=built-in PUBLIC EXECUTE is absent from the object ACL; Sections 4-5 do not modify routine ACLs; manual investigation required'::text
        FROM routines r
        WHERE NOT EXISTS (
            SELECT 1
            FROM aclexplode(COALESCE(r.proacl, acldefault('f', r.proowner))) a
            WHERE a.grantee = 0
              AND a.privilege_type = 'EXECUTE'
              AND NOT a.is_grantable
        )

        UNION ALL

        SELECT 'PF_710_ROUTINE_GRANT_OPTION'::text,
               e.object_name,
               e.grantee,
               e.privilege,
               e.acl_source,
               e.grant_option::text,
               'detail=app/PUBLIC WITH GRANT OPTION on a routine ACL is not modified by Sections 4-5; manual investigation required'::text
        FROM routine_entries e
        WHERE (e.is_public OR e.is_app)
          AND e.grant_option
    ),
    violations AS (
        SELECT * FROM default_row_violations
        UNION ALL SELECT * FROM default_entry_violations
        UNION ALL SELECT * FROM custom_type_violations
        UNION ALL SELECT * FROM routine_violations
    )
    SELECT count(*),
           string_agg(
               format('%s object=%s grantee=%s privilege=%s acl_source=%s grant_option=%s %s',
                      check_type, object_name, grantee, privilege,
                      acl_source, grant_option, detail),
               E'\n' ORDER BY check_type, object_name, grantee, privilege)
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'PREFLIGHT Section 7.10 failed for % provenance finding(s); aborting before the first mutation; no ACL was revoked, granted, or repaired; manual investigation required:\n%',
            v_count, v_details;
    END IF;

    RAISE NOTICE 'Preflight Section 7.10 passed: unnormalized default ACL, custom type, routine, and grant-option provenance matches Section 7.10';
END $$;

-- =====================================================================
-- 2. DBA: idempotent role creation with secure credentials.
--    Existing role attributes and passwords are NEVER changed here. The one
--    configuration mutation in this artifact is the idempotent membership
--    GRANT below, which adds rupaywala_owner to rupaywala_migrator if absent.
-- =====================================================================

SELECT
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner')
         THEN 'false' ELSE 'true' END AS create_owner,
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator')
         THEN 'false' ELSE 'true' END AS create_migrator,
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app')
         THEN 'false' ELSE 'true' END AS create_app
\gset

\if :create_owner
CREATE ROLE rupaywala_owner
  NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;
\endif

\if :create_migrator
CREATE ROLE rupaywala_migrator
  NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;
\password rupaywala_migrator
ALTER ROLE rupaywala_migrator
  LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;
\endif

\if :create_app
CREATE ROLE rupaywala_app
  NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;
\password rupaywala_app
ALTER ROLE rupaywala_app
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOBYPASSRLS NOREPLICATION;
\endif

-- Post-creation guard using exactly the same rules, now for all three roles.
DO $$
DECLARE
    problems text[] := ARRAY[]::text[];
    r record;
BEGIN
    FOR r IN
        SELECT p.rolname, p.rolcanlogin, p.rolsuper, p.rolcreatedb,
               p.rolcreaterole, p.rolbypassrls, p.rolreplication,
               p.rolinherit,
               EXISTS (
                   SELECT 1 FROM pg_catalog.pg_authid a
                   WHERE a.oid = p.oid
                     AND a.rolpassword IS NOT NULL
                     AND a.rolpassword <> ''
               ) AS has_password
        FROM pg_catalog.pg_roles p
        WHERE p.rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')
    LOOP
        IF r.rolsuper OR r.rolcreatedb OR r.rolcreaterole
           OR r.rolbypassrls OR r.rolreplication THEN
            problems := array_append(problems,
                format('%s has a forbidden privilege attribute', r.rolname));
        END IF;

        IF r.rolname = 'rupaywala_owner'
           AND (r.rolcanlogin OR NOT r.rolinherit) THEN
            problems := array_append(problems,
                'rupaywala_owner must be NOLOGIN INHERIT');
        END IF;

        IF r.rolname = 'rupaywala_migrator'
           AND (NOT r.rolcanlogin OR NOT r.rolinherit OR NOT r.has_password) THEN
            problems := array_append(problems,
                'rupaywala_migrator must be LOGIN INHERIT with a password');
        END IF;

        IF r.rolname = 'rupaywala_app'
           AND (NOT r.rolcanlogin OR r.rolinherit OR NOT r.has_password) THEN
            problems := array_append(problems,
                'rupaywala_app must be LOGIN NOINHERIT with a password');
        END IF;
    END LOOP;

    IF (SELECT count(*) FROM pg_catalog.pg_roles
        WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')) <> 3 THEN
        problems := array_append(problems, 'not all three target roles exist');
    END IF;

    IF array_length(problems, 1) > 0 THEN
        RAISE EXCEPTION 'Role model is invalid: %', array_to_string(problems, '; ');
    END IF;
END $$;

-- The only required membership. Idempotent; never WITH ADMIN OPTION.
-- This is a role-configuration mutation: if both roles already exist, their
-- attributes and passwords stay untouched, but this GRANT adds the required
-- membership. rupaywala_app remains a member of no role.
GRANT rupaywala_owner TO rupaywala_migrator;

-- =====================================================================
-- 3. DBA: database/schema access and object ownership transfer.
--    Database ownership is NOT transferred. No database CREATE grant is added.
--    PUBLIC defaults are neither broadened nor revoked; expected PUBLIC state
--    is asserted in section 7.2/7.10: database CONNECT and TEMP true, schema
--    USAGE true, schema CREATE false, and no PUBLIC table/sequence ACLs.
-- =====================================================================

GRANT CONNECT ON DATABASE rupaywala_validation TO rupaywala_migrator;
GRANT CONNECT ON DATABASE rupaywala_validation TO rupaywala_app;

-- Direct USAGE is granted so the app does not depend on PUBLIC schema grants.
-- CREATE is deliberately NOT granted.
GRANT USAGE ON SCHEMA public TO rupaywala_app;

-- The schema itself is owned by the owner role. This is a schema ownership
-- change, not a database ownership change.
ALTER SCHEMA public OWNER TO rupaywala_owner;

-- PUBLIC CREATE on public is asserted false in section 7, never silently revoked.

-- ---------------------------------------------------------------------
-- Object ownership transfer. Executed as superuser. Schema ownership alone
-- does not give an arbitrary executor the right to change every owner.
-- Tables, sequences, views, materialized views, foreign tables, enums,
-- domains and standalone composite types are covered. Extension-owned
-- objects are excluded using pg_depend -> pg_extension dependencies.
-- Indexes, constraints, TOAST objects, arrays and table-associated row types
-- are NOT independently re-owned.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r record;
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
BEGIN
    FOR r IN
        SELECT c.relname, c.relkind
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_class'::regclass
                AND d.objid = c.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY c.relkind, c.relname
    LOOP
        EXECUTE format(
            'ALTER %s public.%I OWNER TO %I',
            CASE r.relkind
                WHEN 'S' THEN 'SEQUENCE'
                WHEN 'v' THEN 'VIEW'
                WHEN 'm' THEN 'MATERIALIZED VIEW'
                WHEN 'f' THEN 'FOREIGN TABLE'
                ELSE 'TABLE'
            END,
            r.relname,
            'rupaywala_owner'
        );
    END LOOP;

    FOR r IN
        SELECT t.typname
        FROM pg_catalog.pg_type t
        JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typtype = 'e'
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY t.typname
    LOOP
        EXECUTE format('ALTER TYPE public.%I OWNER TO %I', r.typname, 'rupaywala_owner');
    END LOOP;

    FOR r IN
        SELECT t.typname
        FROM pg_catalog.pg_type t
        JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typtype = 'd'
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY t.typname
    LOOP
        EXECUTE format('ALTER DOMAIN public.%I OWNER TO %I', r.typname, 'rupaywala_owner');
    END LOOP;

    FOR r IN
        SELECT t.typname
        FROM pg_catalog.pg_type t
        JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
        JOIN pg_catalog.pg_class rc ON rc.oid = t.typrelid
        WHERE n.nspname = 'public'
          AND t.typtype = 'c'
          AND rc.relkind = 'c'
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
        ORDER BY t.typname
    LOOP
        EXECUTE format('ALTER TYPE public.%I OWNER TO %I', r.typname, 'rupaywala_owner');
    END LOOP;

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'rupaywala_owner role disappeared during ownership transfer';
    END IF;
END $$;

-- =====================================================================
-- 4. OWNER-ROLE ACTIONS: explicit SET ROLE rupaywala_owner.
--    Grants are reconciled to the exact source-derived matrix.
-- =====================================================================

SET ROLE rupaywala_owner;

DO $$
DECLARE
    t text;
    missing text[] := ARRAY[]::text[];
    runtime_tables text[] := ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments', 'policies',
        'policy_members', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'subscription_family_members', 'user_subscriptions', 'visit_ledger',
        'distance_rate_config'
    ];
    select_tables text[] := ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments', 'policies',
        'policy_members', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'subscription_family_members', 'user_subscriptions', 'visit_ledger',
        'distance_rate_config'
    ];
    insert_tables text[] := ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments', 'policies',
        'policy_members', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'subscription_family_members', 'user_subscriptions', 'visit_ledger',
        'distance_rate_config'
    ];
    update_tables text[] := ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments',
        'request_assignments', 'service_quotes', 'service_requests',
        'service_types', 'subscription_plans', 'user_subscriptions'
    ];
    delete_tables text[] := ARRAY[
        'notifications', 'otp_verifications', 'policies', 'policy_members',
        'subscription_family_members'
    ];
BEGIN
    FOREACH t IN ARRAY runtime_tables LOOP
        IF to_regclass(format('public.%I', t)) IS NULL THEN
            missing := array_append(missing, format('runtime:%s', t));
        END IF;
    END LOOP;

    IF to_regclass('public.family_members') IS NULL THEN
        missing := array_append(missing, 'deny:family_members');
    END IF;
    IF to_regclass('public.alembic_version') IS NULL THEN
        missing := array_append(missing, 'deny:alembic_version');
    END IF;

    IF array_length(missing, 1) > 0 THEN
        RAISE EXCEPTION
            'Aborting before any grant: expected objects absent: %',
            array_to_string(missing, ', ');
    END IF;

    -- Reconcile exact table privileges for the application role only.
    FOREACH t IN ARRAY runtime_tables LOOP
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', t, 'rupaywala_app');
    END LOOP;
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', 'family_members', 'rupaywala_app');
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', 'alembic_version', 'rupaywala_app');

    FOREACH t IN ARRAY select_tables LOOP
        EXECUTE format('GRANT SELECT ON TABLE public.%I TO %I', t, 'rupaywala_app');
    END LOOP;
    FOREACH t IN ARRAY insert_tables LOOP
        EXECUTE format('GRANT INSERT ON TABLE public.%I TO %I', t, 'rupaywala_app');
    END LOOP;
    FOREACH t IN ARRAY update_tables LOOP
        EXECUTE format('GRANT UPDATE ON TABLE public.%I TO %I', t, 'rupaywala_app');
    END LOOP;
    FOREACH t IN ARRAY delete_tables LOOP
        EXECUTE format('GRANT DELETE ON TABLE public.%I TO %I', t, 'rupaywala_app');
    END LOOP;
END $$;

-- family_members has no backend runtime code path: zero privileges by design.
-- alembic_version must remain inaccessible to the application role.
-- Both are enforced by the REVOKE ALL above and by section 7 assertions.

-- ---------------------------------------------------------------------
-- Sequence grants. USAGE is sufficient for serial nextval(). SELECT/currval
-- is not used by the backend. The temporary UPDATE on the subscription_plans
-- id sequence is required only by app/services/plan_catalog.py:177 setval().
-- ---------------------------------------------------------------------
DO $$
DECLARE
    t text;
    seq text;
    insert_tables text[] := ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments', 'policies',
        'policy_members', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'subscription_family_members', 'user_subscriptions', 'visit_ledger',
        'distance_rate_config'
    ];
BEGIN
    FOREACH t IN ARRAY insert_tables LOOP
        seq := pg_catalog.pg_get_serial_sequence(format('public.%I', t), 'id');
        IF seq IS NULL THEN
            RAISE EXCEPTION 'Missing id sequence for public.%', t;
        END IF;
        EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM %I', seq::regclass, 'rupaywala_app');
        EXECUTE format('GRANT USAGE ON SEQUENCE %s TO %I', seq::regclass, 'rupaywala_app');
    END LOOP;

    seq := pg_catalog.pg_get_serial_sequence('public.subscription_plans', 'id');
    IF seq IS NULL THEN
        RAISE EXCEPTION 'public.subscription_plans.id sequence is absent';
    END IF;

    EXECUTE format('GRANT UPDATE ON SEQUENCE %s TO %I', seq::regclass, 'rupaywala_app');
END $$;

-- ---------------------------------------------------------------------
-- Per-schema defaults: stale public-schema app defaults are removed first.
-- GLOBAL defaults are not altered (they affect every schema); built-in PUBLIC
-- defaults are not touched. Schema (n) and large-object (L) defaults are
-- global-only in PostgreSQL 18 and are therefore not issued here. All six
-- object classes are inventoried and audited in 7.10.
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public
    REVOKE ALL ON TABLES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public
    GRANT SELECT ON TABLES TO rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_owner IN SCHEMA public
    GRANT USAGE ON SEQUENCES TO rupaywala_app;

RESET ROLE;

-- =====================================================================
-- 5. DBA: defensive PER-SCHEMA defaults for migrator-created objects.
--    The REQUIRED owner strategy is the Alembic PGOPTIONS startup role in
--    section 10, so objects should be recorded as owned by rupaywala_owner.
--    No GLOBAL default is changed because it would affect every schema.
--    These public-only defaults are a fallback; they do NOT fix ownership.
-- =====================================================================

ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public
    REVOKE ALL ON TABLES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public
    GRANT SELECT ON TABLES TO rupaywala_app;
ALTER DEFAULT PRIVILEGES FOR ROLE rupaywala_migrator IN SCHEMA public
    GRANT USAGE ON SEQUENCES TO rupaywala_app;

-- =====================================================================
-- 6. DBA: database owner and revision post-checks.
--    current_setting() is used instead of psql substitution inside DO.
-- =====================================================================

DO $$
DECLARE
    v_before text := current_setting('rupaywala.db_owner_before', true);
    v_current text;
BEGIN
    IF v_before IS NULL OR v_before = '' THEN
        RAISE EXCEPTION 'Database owner baseline is missing; comparison cannot be performed';
    END IF;

    SELECT pg_catalog.pg_get_userbyid(datdba) INTO v_current
    FROM pg_catalog.pg_database
    WHERE datname = 'rupaywala_validation';

    IF v_current IS DISTINCT FROM v_before THEN
        RAISE EXCEPTION
            'Database owner changed unexpectedly; expected %, got %',
            v_before, v_current;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.alembic_version
        WHERE version_num = '0005_fixed_quotes'
    ) THEN
        RAISE EXCEPTION 'Revision changed unexpectedly; expected 0005_fixed_quotes';
    END IF;
END $$;

-- =====================================================================
-- 7. DBA: verification queries and strict catalog assertions.
-- =====================================================================

-- 7.1 Role attributes and memberships.
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
       rolbypassrls, rolreplication, rolinherit
FROM pg_catalog.pg_roles
WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app')
ORDER BY rolname;

SELECT r.rolname AS member_role,
       m.rolname AS member_of,
       am.admin_option
FROM pg_catalog.pg_auth_members am
JOIN pg_catalog.pg_roles r ON r.oid = am.member
JOIN pg_catalog.pg_roles m ON m.oid = am.roleid
WHERE r.rolname IN ('rupaywala_migrator', 'rupaywala_app')
ORDER BY r.rolname, m.rolname;

-- 7.2 PUBLIC and role-level namespace/database checks. Expected state is
--     asserted, not merely reported. PUBLIC values are PostgreSQL defaults,
--     not grants added by this artifact.
SELECT has_database_privilege('public', 'rupaywala_validation', 'CONNECT')
       AS public_db_connect,
       has_database_privilege('public', 'rupaywala_validation', 'TEMP')
       AS public_db_temp,
       has_schema_privilege('public', 'public', 'USAGE')
       AS public_schema_usage,
       has_schema_privilege('public', 'public', 'CREATE')
       AS public_schema_create;

SELECT has_database_privilege('rupaywala_app', 'rupaywala_validation', 'CONNECT')
       AS app_connect,
       has_database_privilege('rupaywala_app', 'rupaywala_validation', 'TEMP')
       AS app_db_temp,
       has_database_privilege('rupaywala_app', 'rupaywala_validation', 'CREATE')
       AS app_db_create,
       has_schema_privilege('rupaywala_app', 'public', 'USAGE')
       AS app_schema_usage,
       has_schema_privilege('rupaywala_app', 'public', 'CREATE')
       AS app_schema_create,
       has_database_privilege('rupaywala_owner', 'rupaywala_validation', 'CONNECT')
       AS owner_db_connect,
       has_database_privilege('rupaywala_owner', 'rupaywala_validation', 'TEMP')
       AS owner_db_temp,
       has_database_privilege('rupaywala_owner', 'rupaywala_validation', 'CREATE')
       AS owner_db_create,
       has_schema_privilege('rupaywala_owner', 'public', 'USAGE')
       AS owner_schema_usage,
       has_schema_privilege('rupaywala_owner', 'public', 'CREATE')
       AS owner_schema_create,
       has_database_privilege('rupaywala_migrator', 'rupaywala_validation', 'CONNECT')
       AS migrator_db_connect,
       has_database_privilege('rupaywala_migrator', 'rupaywala_validation', 'TEMP')
       AS migrator_db_temp,
       has_database_privilege('rupaywala_migrator', 'rupaywala_validation', 'CREATE')
       AS migrator_db_create,
       has_schema_privilege('rupaywala_migrator', 'public', 'USAGE')
       AS migrator_schema_usage,
       has_schema_privilege('rupaywala_migrator', 'public', 'CREATE')
       AS migrator_schema_create;

-- Expected:
--   public_db_connect=true, public_db_temp=true, public_schema_usage=true,
--   public_schema_create=false (defaults; not changed here).
--   app_connect=true, app_db_temp=true (PUBLIC-derived), app_schema_usage=true,
--   app_db_create=false, app_schema_create=false.
--   owner_db_create=false, migrator_db_create=false.
--   owner_schema_create=true (ownership), migrator_schema_create=true
--   (INHERIT from rupaywala_owner); neither is a direct CREATE grant to app.

DO $$
BEGIN
    IF NOT has_database_privilege('public', 'rupaywala_validation', 'CONNECT') THEN
        RAISE EXCEPTION 'Default PUBLIC CONNECT on rupaywala_validation is missing';
    END IF;
    IF NOT has_database_privilege('public', 'rupaywala_validation', 'TEMP') THEN
        RAISE EXCEPTION 'Default PUBLIC TEMP on rupaywala_validation is missing';
    END IF;
    IF NOT has_schema_privilege('public', 'public', 'USAGE') THEN
        RAISE EXCEPTION 'Default PUBLIC USAGE on public is missing';
    END IF;
    IF has_schema_privilege('public', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'PUBLIC must not have CREATE on public';
    END IF;

    IF NOT has_database_privilege('rupaywala_app', 'rupaywala_validation', 'CONNECT') THEN
        RAISE EXCEPTION 'rupaywala_app CONNECT is missing';
    END IF;
    IF NOT has_schema_privilege('rupaywala_app', 'public', 'USAGE') THEN
        RAISE EXCEPTION 'rupaywala_app USAGE on public is missing';
    END IF;
    IF has_database_privilege('rupaywala_app', 'rupaywala_validation', 'CREATE') THEN
        RAISE EXCEPTION 'rupaywala_app must not have database CREATE';
    END IF;
    IF has_schema_privilege('rupaywala_app', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'rupaywala_app must not have schema CREATE';
    END IF;

    IF has_database_privilege('rupaywala_owner', 'rupaywala_validation', 'CREATE')
       OR has_database_privilege('rupaywala_migrator', 'rupaywala_validation', 'CREATE') THEN
        RAISE EXCEPTION 'owner/migrator must not have database CREATE';
    END IF;
    IF NOT has_schema_privilege('rupaywala_owner', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'rupaywala_owner must control schema public';
    END IF;
    IF NOT has_schema_privilege('rupaywala_migrator', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'rupaywala_migrator must inherit schema CREATE from rupaywala_owner';
    END IF;
END $$;

-- 7.3 Ownership of every object class touched by section 3, excluding
--     extension-owned objects. Arrays and table row types are deliberately
--     excluded from the transfer and from this assertion.
DO $$
DECLARE
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    bad int := 0;
BEGIN
    IF (SELECT pg_catalog.pg_get_userbyid(nspowner)
        FROM pg_catalog.pg_namespace WHERE nspname = 'public')
       IS DISTINCT FROM 'rupaywala_owner' THEN
        RAISE EXCEPTION 'Ownership assertion failed: schema public is not owned by rupaywala_owner';
    END IF;

    SELECT count(*) INTO bad
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
      AND c.relowner IS DISTINCT FROM v_owner
      AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_depend d
          WHERE d.classid = 'pg_catalog.pg_class'::regclass
            AND d.objid = c.oid
            AND d.deptype IN ('e', 'x')
            AND d.refclassid = 'pg_catalog.pg_extension'::regclass
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Ownership assertion failed: % relation(s) not owned by rupaywala_owner', bad;
    END IF;

    SELECT count(*) INTO bad
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typtype IN ('e', 'd')
      AND t.typowner IS DISTINCT FROM v_owner
      AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_depend d
          WHERE d.classid = 'pg_catalog.pg_type'::regclass
            AND d.objid = t.oid
            AND d.deptype IN ('e', 'x')
            AND d.refclassid = 'pg_catalog.pg_extension'::regclass
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Ownership assertion failed: % enum/domain type(s) not owned by rupaywala_owner', bad;
    END IF;

    SELECT count(*) INTO bad
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    JOIN pg_catalog.pg_class rc ON rc.oid = t.typrelid
    WHERE n.nspname = 'public'
      AND t.typtype = 'c'
      AND rc.relkind = 'c'
      AND t.typowner IS DISTINCT FROM v_owner
      AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_depend d
          WHERE d.classid = 'pg_catalog.pg_type'::regclass
            AND d.objid = t.oid
            AND d.deptype IN ('e', 'x')
            AND d.refclassid = 'pg_catalog.pg_extension'::regclass
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Ownership assertion failed: % standalone composite type(s) not owned by rupaywala_owner', bad;
    END IF;
END $$;

-- 7.4 Application-role ownership denial (pg_class, pg_type and pg_proc).
SELECT (
    (SELECT count(*) FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app'))
  + (SELECT count(*) FROM pg_catalog.pg_type t
      JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'public'
        AND t.typowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app'))
  + (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app'))
) AS objects_owned_by_app;
-- Expected: 0

-- 7.5 Alembic history access (must be all false).
SELECT has_table_privilege('rupaywala_app', 'public.alembic_version', 'SELECT')
       AS history_select,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'INSERT')
       AS history_insert,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'UPDATE')
       AS history_update,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'DELETE')
       AS history_delete,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'TRUNCATE')
       AS history_truncate,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'TRIGGER')
       AS history_trigger,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'REFERENCES')
       AS history_references,
       has_table_privilege('rupaywala_app', 'public.alembic_version', 'MAINTAIN')
       AS history_maintain;

SELECT version_num AS revision_before_0006 FROM public.alembic_version;

-- 7.6 Table privilege summary (includes TRUNCATE and TRIGGER denial checks).
SELECT c.relname,
       has_table_privilege('rupaywala_app', c.oid, 'SELECT') AS sel,
       has_table_privilege('rupaywala_app', c.oid, 'INSERT') AS ins,
       has_table_privilege('rupaywala_app', c.oid, 'UPDATE') AS upd,
       has_table_privilege('rupaywala_app', c.oid, 'DELETE') AS del,
       has_table_privilege('rupaywala_app', c.oid, 'TRUNCATE') AS trunc,
       has_table_privilege('rupaywala_app', c.oid, 'TRIGGER') AS trig,
       has_table_privilege('rupaywala_app', c.oid, 'REFERENCES') AS refs,
       has_table_privilege('rupaywala_app', c.oid, 'MAINTAIN') AS maint
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;

-- 7.7 Sequence privilege summary.
SELECT c.relname AS sequence_name,
       has_sequence_privilege('rupaywala_app', c.oid, 'USAGE') AS usage,
       has_sequence_privilege('rupaywala_app', c.oid, 'SELECT') AS sel,
       has_sequence_privilege('rupaywala_app', c.oid, 'UPDATE') AS upd
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'S'
ORDER BY c.relname;
-- Runtime sequences: usage=true, sel=false, upd=false.
-- public.subscription_plans_id_seq: usage=true, sel=false, upd=true (temporary).

-- 7.8 Owners and default ACLs (evidence).
SELECT c.relname, c.relkind, pg_catalog.pg_get_userbyid(c.relowner) AS owner
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
ORDER BY c.relname;

SELECT t.typname, t.typtype, pg_catalog.pg_get_userbyid(t.typowner) AS owner
FROM pg_catalog.pg_type t
JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public'
  AND t.typtype IN ('e', 'd', 'c')
ORDER BY t.typtype, t.typname;

SELECT defaclrole::regrole::text AS owner_role, CASE WHEN defaclnamespace=0 THEN 'GLOBAL' ELSE 'public' END AS scope,
       defaclobjtype, defaclacl
FROM pg_catalog.pg_default_acl
WHERE defaclrole::regrole::text IN ('rupaywala_owner','rupaywala_migrator')
  AND defaclnamespace IN (0,'public'::regnamespace::oid)
  AND defaclobjtype IN ('r','S','f','T','n','L')
ORDER BY 1,2,3;

-- 7.9 Strict positive and negative catalog assertions.
DO $$
DECLARE
    t text;
    seq text;
    v_role text := 'rupaywala_app';
BEGIN
    IF NOT has_database_privilege(v_role, 'rupaywala_validation', 'CONNECT') THEN
        RAISE EXCEPTION 'rupaywala_app CONNECT is missing';
    END IF;
    IF NOT has_database_privilege(v_role, 'rupaywala_validation', 'TEMP') THEN
        RAISE EXCEPTION 'rupaywala_app TEMP is missing (expected via PUBLIC default)';
    END IF;
    IF NOT has_schema_privilege(v_role, 'public', 'USAGE') THEN
        RAISE EXCEPTION 'rupaywala_app USAGE on public is missing';
    END IF;

    FOREACH t IN ARRAY ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments', 'policies',
        'policy_members', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'subscription_family_members', 'user_subscriptions', 'visit_ledger',
        'distance_rate_config'
    ] LOOP
        IF NOT has_table_privilege(v_role, format('public.%I', t), 'SELECT') THEN
            RAISE EXCEPTION 'Missing required SELECT on public.%', t;
        END IF;
        IF NOT has_table_privilege(v_role, format('public.%I', t), 'INSERT') THEN
            RAISE EXCEPTION 'Missing required INSERT on public.%', t;
        END IF;
        IF has_table_privilege(v_role, format('public.%I', t), 'TRUNCATE') THEN
            RAISE EXCEPTION 'Forbidden TRUNCATE on public.%', t;
        END IF;
        IF has_table_privilege(v_role, format('public.%I', t), 'TRIGGER') THEN
            RAISE EXCEPTION 'Forbidden TRIGGER on public.%', t;
        END IF;
        IF has_table_privilege(v_role, format('public.%I', t), 'REFERENCES') THEN
            RAISE EXCEPTION 'Forbidden REFERENCES on public.%', t;
        END IF;
        IF has_table_privilege(v_role, format('public.%I', t), 'MAINTAIN') THEN
            RAISE EXCEPTION 'Forbidden MAINTAIN on public.%', t;
        END IF;
    END LOOP;

    FOREACH t IN ARRAY ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments',
        'request_assignments', 'service_quotes', 'service_requests',
        'service_types', 'subscription_plans', 'user_subscriptions'
    ] LOOP
        IF NOT has_table_privilege(v_role, format('public.%I', t), 'UPDATE') THEN
            RAISE EXCEPTION 'Missing required UPDATE on public.%', t;
        END IF;
    END LOOP;

    FOREACH t IN ARRAY ARRAY[
        'policies', 'policy_members', 'subscription_family_members',
        'visit_ledger', 'distance_rate_config'
    ] LOOP
        IF has_table_privilege(v_role, format('public.%I', t), 'UPDATE') THEN
            RAISE EXCEPTION 'Unnecessary UPDATE granted on public.%', t;
        END IF;
    END LOOP;

    FOREACH t IN ARRAY ARRAY[
        'notifications', 'otp_verifications', 'policies', 'policy_members',
        'subscription_family_members'
    ] LOOP
        IF NOT has_table_privilege(v_role, format('public.%I', t), 'DELETE') THEN
            RAISE EXCEPTION 'Missing required DELETE on public.%', t;
        END IF;
    END LOOP;

    FOREACH t IN ARRAY ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'payments', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'user_subscriptions', 'visit_ledger', 'distance_rate_config'
    ] LOOP
        IF has_table_privilege(v_role, format('public.%I', t), 'DELETE') THEN
            RAISE EXCEPTION 'Unnecessary DELETE granted on public.%', t;
        END IF;
    END LOOP;

    FOREACH t IN ARRAY ARRAY['family_members', 'alembic_version'] LOOP
        IF has_table_privilege(v_role, format('public.%I', t), 'SELECT')
           OR has_table_privilege(v_role, format('public.%I', t), 'INSERT')
           OR has_table_privilege(v_role, format('public.%I', t), 'UPDATE')
           OR has_table_privilege(v_role, format('public.%I', t), 'DELETE')
           OR has_table_privilege(v_role, format('public.%I', t), 'TRUNCATE')
           OR has_table_privilege(v_role, format('public.%I', t), 'TRIGGER')
           OR has_table_privilege(v_role, format('public.%I', t), 'REFERENCES')
           OR has_table_privilege(v_role, format('public.%I', t), 'MAINTAIN') THEN
            RAISE EXCEPTION 'public.% must have ZERO application privileges', t;
        END IF;
    END LOOP;

    FOREACH t IN ARRAY ARRAY[
        'users', 'branches', 'customer_profiles', 'field_members',
        'notifications', 'otp_verifications', 'payments', 'policies',
        'policy_members', 'request_assignments', 'service_quotes',
        'service_requests', 'service_types', 'subscription_plans',
        'subscription_family_members', 'user_subscriptions', 'visit_ledger',
        'distance_rate_config'
    ] LOOP
        seq := pg_catalog.pg_get_serial_sequence(format('public.%I', t), 'id');
        IF seq IS NULL OR NOT has_sequence_privilege(v_role, seq, 'USAGE') THEN
            RAISE EXCEPTION 'Missing USAGE on id sequence for public.%', t;
        END IF;
        IF has_sequence_privilege(v_role, seq, 'SELECT') THEN
            RAISE EXCEPTION 'Unnecessary SELECT on id sequence for public.%', t;
        END IF;
        IF t <> 'subscription_plans' AND has_sequence_privilege(v_role, seq, 'UPDATE') THEN
            RAISE EXCEPTION 'Unnecessary UPDATE on id sequence for public.%', t;
        END IF;
    END LOOP;

    seq := pg_catalog.pg_get_serial_sequence('public.subscription_plans', 'id');
    IF seq IS NULL OR NOT has_sequence_privilege(v_role, seq, 'UPDATE') THEN
        RAISE EXCEPTION 'Temporary setval() exception missing on subscription_plans id sequence';
    END IF;

    IF has_schema_privilege(v_role, 'public', 'CREATE') THEN
        RAISE EXCEPTION 'rupaywala_app must not have CREATE on schema public';
    END IF;
    IF has_database_privilege(v_role, 'rupaywala_validation', 'CREATE') THEN
        RAISE EXCEPTION 'rupaywala_app must not have CREATE on the database';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members am
               WHERE am.member = (SELECT oid FROM pg_catalog.pg_roles
                                  WHERE rolname = v_role)) THEN
        RAISE EXCEPTION 'rupaywala_app must not be a member of any role';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = v_role)
    ) THEN
        RAISE EXCEPTION 'rupaywala_app owns at least one object in public';
    END IF;
END $$;

-- 7.10 Privilege provenance and PostgreSQL 18 completeness assertions.
--      The has_*_privilege() checks above report EFFECTIVE privileges, which
--      can come from direct grants, INHERIT membership, PUBLIC defaults, or
--      ownership. Object ACLs use acldefault() when NULL; pg_default_acl rows
--      are explicit future-object deltas. All six object classes are checked:
--      r/S/f/T/n/L. PUBLIC (grantee 0) and rupaywala_app are both audited, and
--      aclexplode().is_grantable is inspected for escalation.
SELECT d.datname, d.datacl, n.nspacl
FROM pg_catalog.pg_database d
CROSS JOIN pg_catalog.pg_namespace n
WHERE d.datname = 'rupaywala_validation' AND n.nspname = 'public';

DO $$
DECLARE
    v_public oid := 0;
    v_public_schema oid := 'public'::regnamespace::oid;
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    v_migrator oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator');
    bad int;
BEGIN
    -- Existing object ACLs: no PUBLIC on relations/sequences; NULL ACL uses acldefault().
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.oid = v_public_schema
      AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
      AND EXISTS (
          SELECT 1
          FROM aclexplode(COALESCE(c.relacl, acldefault((CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END)::"char", c.relowner))) a
          WHERE a.grantee = v_public
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Unintended PUBLIC ACL on % relation/sequence(s)', bad;
    END IF;

    -- Existing object ACLs: no WITH GRANT OPTION for app or PUBLIC.
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault((CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END)::"char", c.relowner))) a
    WHERE n.oid = v_public_schema
      AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
      AND a.grantee IN (v_app, v_public)
      AND a.is_grantable;
    IF bad > 0 THEN
        RAISE EXCEPTION 'Unexpected WITH GRANT OPTION on relation/sequence ACL(s): %', bad;
    END IF;

    -- Custom types: effective USAGE via has_type_privilege(); NULL typacl uses acldefault('T', typowner).
    -- Only the built-in PUBLIC USAGE default is accepted; no grant option is allowed.
    WITH custom_types AS (
        SELECT t.oid, t.typacl, t.typowner
        FROM pg_catalog.pg_type t
        JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
        WHERE n.oid = v_public_schema
          AND (
              t.typtype IN ('e', 'd')
              OR (t.typtype = 'c' AND EXISTS (
                  SELECT 1 FROM pg_catalog.pg_class rc
                  WHERE rc.oid = t.typrelid AND rc.relkind = 'c'
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend d
              WHERE d.classid = 'pg_catalog.pg_type'::regclass
                AND d.objid = t.oid
                AND d.deptype IN ('e', 'x')
                AND d.refclassid = 'pg_catalog.pg_extension'::regclass
          )
    )
    SELECT count(*) INTO bad
    FROM custom_types ct
    WHERE NOT has_type_privilege(v_app, ct.oid, 'USAGE')
       OR NOT EXISTS (
           SELECT 1
           FROM aclexplode(COALESCE(ct.typacl, acldefault('T', ct.typowner))) a
           WHERE a.privilege_type = 'USAGE'
             AND a.grantee = v_public
             AND NOT a.is_grantable
       )
       OR EXISTS (
           SELECT 1
           FROM aclexplode(COALESCE(ct.typacl, acldefault('T', ct.typowner))) a
           WHERE a.grantee IN (v_app, v_public)
             AND a.is_grantable
       );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Invalid effective/default USAGE on % custom type(s)', bad;
    END IF;

    -- Routines: effective EXECUTE via has_function_privilege(); NULL proacl uses acldefault('f', proowner).
    -- Only the built-in PUBLIC EXECUTE default is accepted; no grant option is allowed.
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.oid = v_public_schema
      AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_depend d
          WHERE d.classid = 'pg_catalog.pg_proc'::regclass
            AND d.objid = p.oid
            AND d.deptype IN ('e', 'x')
            AND d.refclassid = 'pg_catalog.pg_extension'::regclass
      )
      AND (
          NOT has_function_privilege(v_app, p.oid, 'EXECUTE')
          OR NOT EXISTS (
              SELECT 1
              FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
              WHERE a.privilege_type = 'EXECUTE'
                AND a.grantee = v_public
                AND NOT a.is_grantable
          )
          OR EXISTS (
              SELECT 1
              FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
              WHERE a.grantee IN (v_app, v_public)
                AND a.is_grantable
          )
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Invalid effective/default EXECUTE on % routine(s)', bad;
    END IF;

    -- Intended per-schema future-object privileges must be exact and ordinary (no grant option).
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_default_acl d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
        WHERE d.defaclnamespace = v_public_schema
          AND d.defaclrole = v_owner AND d.defaclobjtype = 'r'
          AND a.grantee = v_app AND a.privilege_type = 'SELECT' AND NOT a.is_grantable
    ) THEN
        RAISE EXCEPTION 'Owner default SELECT on future tables is missing or has grant option';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_default_acl d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
        WHERE d.defaclnamespace = v_public_schema
          AND d.defaclrole = v_owner AND d.defaclobjtype = 'S'
          AND a.grantee = v_app AND a.privilege_type = 'USAGE' AND NOT a.is_grantable
    ) THEN
        RAISE EXCEPTION 'Owner default USAGE on future sequences is missing or has grant option';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_default_acl d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
        WHERE d.defaclnamespace = v_public_schema
          AND d.defaclrole = v_migrator AND d.defaclobjtype = 'r'
          AND a.grantee = v_app AND a.privilege_type = 'SELECT' AND NOT a.is_grantable
    ) THEN
        RAISE EXCEPTION 'Migrator default SELECT on future tables is missing or has grant option';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_default_acl d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
        WHERE d.defaclnamespace = v_public_schema
          AND d.defaclrole = v_migrator AND d.defaclobjtype = 'S'
          AND a.grantee = v_app AND a.privilege_type = 'USAGE' AND NOT a.is_grantable
    ) THEN
        RAISE EXCEPTION 'Migrator default USAGE on future sequences is missing or has grant option';
    END IF;

    -- PostgreSQL 18: schemas (n) and large objects (L) have GLOBAL-only default privileges.
    -- IN SCHEMA is not permitted for these classes; any per-schema row is invalid.
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_default_acl d
    WHERE d.defaclrole IN (v_owner, v_migrator)
      AND d.defaclobjtype IN ('n', 'L')
      AND d.defaclnamespace <> 0;
    IF bad > 0 THEN
        RAISE EXCEPTION 'Invalid per-schema default ACL(s) for global-only classes n/L: %', bad;
    END IF;

    -- A GLOBAL entry overrides hard-wired defaults; if one exists for types or
    -- routines it must still carry the built-in PUBLIC USAGE/EXECUTE default.
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_default_acl d
    WHERE d.defaclrole IN (v_owner, v_migrator)
      AND d.defaclnamespace = 0
      AND d.defaclobjtype = 'T'
      AND NOT EXISTS (
          SELECT 1 FROM aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
          WHERE a.grantee = v_public AND a.privilege_type = 'USAGE' AND NOT a.is_grantable
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Global default ACL removed built-in PUBLIC USAGE on % type default(s)', bad;
    END IF;
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_default_acl d
    WHERE d.defaclrole IN (v_owner, v_migrator)
      AND d.defaclnamespace = 0
      AND d.defaclobjtype = 'f'
      AND NOT EXISTS (
          SELECT 1 FROM aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
          WHERE a.grantee = v_public AND a.privilege_type = 'EXECUTE' AND NOT a.is_grantable
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Global default ACL removed built-in PUBLIC EXECUTE on % routine default(s)', bad;
    END IF;

    -- Strict default-ACL audit across all six PG18 object classes and both
    -- grantees (app and PUBLIC), including WITH GRANT OPTION escalation.
    SELECT count(*) INTO bad
    FROM pg_catalog.pg_default_acl d
    CROSS JOIN LATERAL aclexplode(COALESCE(d.defaclacl, ARRAY[]::aclitem[])) a
    WHERE d.defaclrole IN (v_owner, v_migrator)
      AND d.defaclobjtype IN ('r', 'S', 'f', 'T', 'n', 'L')
      AND d.defaclnamespace IN (0, v_public_schema)
      AND a.grantee IN (v_app, v_public)
      AND (
          a.is_grantable
          OR d.defaclobjtype IN ('n', 'L')
          OR (a.grantee = v_app AND d.defaclnamespace = 0)
          OR (d.defaclnamespace = 0 AND d.defaclobjtype IN ('r', 'S'))
          OR (d.defaclnamespace = 0 AND d.defaclobjtype = 'T'
              AND NOT (a.grantee = v_public AND a.privilege_type = 'USAGE'))
          OR (d.defaclnamespace = 0 AND d.defaclobjtype = 'f'
              AND NOT (a.grantee = v_public AND a.privilege_type = 'EXECUTE'))
          OR (
              d.defaclnamespace = v_public_schema
              AND (
                  (d.defaclobjtype = 'r' AND NOT (a.grantee = v_app AND a.privilege_type = 'SELECT'))
                  OR (d.defaclobjtype = 'S' AND NOT (a.grantee = v_app AND a.privilege_type = 'USAGE'))
                  OR (d.defaclobjtype = 'T' AND NOT (a.grantee = v_public AND a.privilege_type = 'USAGE'))
                  OR (d.defaclobjtype = 'f' AND NOT (a.grantee = v_public AND a.privilege_type = 'EXECUTE'))
              )
          )
      );
    IF bad > 0 THEN
        RAISE EXCEPTION 'Unexpected default grant or grant option for app/PUBLIC: %', bad;
    END IF;
END $$;

-- No ALTER DEFAULT PRIVILEGES ... ON TYPES/ROUTINES/SCHEMAS/LARGE OBJECTS is
-- issued. Built-in PUBLIC USAGE/EXECUTE defaults are represented by acldefault()
-- for NULL object ACLs; global defaults (including n/L) are only inspected,
-- never altered, and WITH GRANT OPTION is rejected for app and PUBLIC.

-- =====================================================================
-- 8. APPLICATION-ROLE EXTRACT - LINE-COMMENTED, NOT EXECUTED BY THIS FILE.
--    Copy these lines to a separate psql session authenticated as
--    rupaywala_app against 127.0.0.1:55432 / rupaywala_validation, remove the
--    leading '-- ' markers, and run only after sections 0-7 pass.
--    DO NOT run as validation_admin. SET ROLE is not a substitute for a real
--    login-role test. Section 8b DML is inside BEGIN/ROLLBACK; section 8a
--    negative DML relies on DO-block exception atomicity.
--
--    8.0 MANUAL PREREQUISITES (operator checks, not executed here):
--      * Copy '\set ON_ERROR_STOP on' from line 49 into the extracted session.
--      * Confirm public.alembic_version is exactly '0005_fixed_quotes'.
--      * Confirm no row already uses id=900001 in the 17 explicit-id targets;
--        service_quotes.id is generated and is not fixed to 900001.
--      * Confirm unique literals are free: user phone '9000000001', usernames
--        'zz_probe_user'/'zz_probe_user2', service_types.code 'zz_probe_type',
--        subscription_plans.code 'zz_probe_plan', service_quotes.quote_ref
--        'zz-probe', payments.txn_id 'zz-probe-txn', and
--        subscription_family_members identity key 'probe|self|'.
--      * Confirm no dependent rows reference policies.id=900001 or
--        subscription_family_members.id=900001 before the DELETE probes.
--      * Confirm enum labels via pg_enum before the DML probes. INSERTs and
--        UPDATEs are statically schema-valid, but runtime enum state is data.
--      * Capture sequence values before and after: the 18 nextval() probes and
--        setval(..., 900001, true) are NOT reversed by ROLLBACK.
-- =====================================================================

-- -- 8a. Negative behavioral tests: each operation must be DENIED.
-- -- A PASS means the expected insufficient_privilege error was raised.
--
-- DO $$
-- BEGIN
--     BEGIN
--         CREATE TABLE public.zz_probe_app_ddl (id integer);
--         DROP TABLE public.zz_probe_app_ddl;
--         RAISE EXCEPTION 'FAIL: app role could CREATE TABLE';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied CREATE TABLE';
--     END;
-- END $$;
--
-- DO $$
-- BEGIN
--     BEGIN
--         ALTER TABLE public.users ADD COLUMN zz_probe integer;
--         RAISE EXCEPTION 'FAIL: app role could ALTER TABLE';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied ALTER TABLE';
--     END;
-- END $$;
--
-- DO $$
-- BEGIN
--     BEGIN
--         DROP TABLE public.users;
--         RAISE EXCEPTION 'FAIL: app role could DROP TABLE';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied DROP TABLE';
--     END;
-- END $$;
--
-- DO $$
-- BEGIN
--     BEGIN
--         TRUNCATE TABLE public.users;
--         RAISE EXCEPTION 'FAIL: app role could TRUNCATE';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied TRUNCATE';
--     END;
-- END $$;
--
-- DO $$
-- BEGIN
--     BEGIN
--         CREATE ROLE zz_probe_app_role;
--         RAISE EXCEPTION 'FAIL: app role could CREATE ROLE';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied CREATE ROLE';
--     END;
-- END $$;
--
-- -- CREATE DATABASE cannot run inside DO or a transaction. Run separately:
-- --   psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=rupaywala_app" -c 'CREATE DATABASE zz_probe_app_db'
-- -- Expected: permission denied for database creation.
--
-- DO $$
-- BEGIN
--     BEGIN
--         SET ROLE rupaywala_owner;
--         RAISE EXCEPTION 'FAIL: app role could SET ROLE rupaywala_owner';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied SET ROLE rupaywala_owner';
--     END;
--     BEGIN
--         SET ROLE rupaywala_migrator;
--         RAISE EXCEPTION 'FAIL: app role could SET ROLE rupaywala_migrator';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied SET ROLE rupaywala_migrator';
--     END;
-- END $$;
--
-- DO $$
-- BEGIN
--     BEGIN
--         PERFORM 1 FROM public.alembic_version;
--         RAISE EXCEPTION 'FAIL: app role could SELECT alembic_version';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied SELECT on alembic_version';
--     END;
--     BEGIN
--         INSERT INTO public.alembic_version (version_num) VALUES ('zz_probe');
--         RAISE EXCEPTION 'FAIL: app role could INSERT alembic_version';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied INSERT on alembic_version';
--     END;
--     BEGIN
--         UPDATE public.alembic_version SET version_num = 'zz_probe';
--         RAISE EXCEPTION 'FAIL: app role could UPDATE alembic_version';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied UPDATE on alembic_version';
--     END;
--     BEGIN
--         DELETE FROM public.alembic_version;
--         RAISE EXCEPTION 'FAIL: app role could DELETE alembic_version';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied DELETE on alembic_version';
--     END;
-- END $$;
--
-- DO $$
-- BEGIN
--     BEGIN
--         PERFORM 1 FROM public.family_members;
--         RAISE EXCEPTION 'FAIL: app role could SELECT family_members';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied SELECT on legacy family_members';
--     END;
--     BEGIN
--         DELETE FROM public.users WHERE id = 900001;
--         RAISE EXCEPTION 'FAIL: app role could DELETE users';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied unnecessary DELETE on users';
--     END;
--     BEGIN
--         UPDATE public.distance_rate_config SET rate_per_km = rate_per_km;
--         RAISE EXCEPTION 'FAIL: app role could UPDATE distance_rate_config';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied unnecessary UPDATE on distance_rate_config';
--     END;
--     BEGIN
--         UPDATE public.visit_ledger SET quantity = quantity;
--         RAISE EXCEPTION 'FAIL: app role could UPDATE visit_ledger';
--     EXCEPTION WHEN insufficient_privilege THEN
--         RAISE NOTICE 'PASS: app role denied unnecessary UPDATE on visit_ledger';
--     END;
-- END $$;
--
-- -- 8b. Positive smoke test: only operations the backend actually performs.
-- --     nextval() and setval() are non-transactional and are NOT reversed by
-- --     the ROLLBACK below.
-- BEGIN;
--
-- INSERT INTO public.users
--   (id, phone_number, username, role, is_verified, account_status,
--    auth_provider, email_verified, phone_verified)
-- VALUES
--   (900001, '9000000001', 'zz_probe_user', 'customer', false, 'active',
--    'phone_otp', false, false);
--
-- INSERT INTO public.service_types (id, code, name, is_active, sort_order)
-- VALUES (900001, 'zz_probe_type', 'Probe', true, 900001);
--
-- INSERT INTO public.branches
--   (id, name, address, latitude, longitude, is_active)
-- VALUES (900001, 'Probe', 'Addr', 0, 0, true);
--
-- INSERT INTO public.distance_rate_config
--   (id, threshold_km, rate_per_km, tax_percent, round_trip_factor, updated_by)
-- VALUES (900001, 10, 20, 18, 2, 900001);
--
-- INSERT INTO public.customer_profiles
--   (id, user_id, full_name, profile_completed)
-- VALUES (900001, 900001, 'Probe', false);
--
-- INSERT INTO public.otp_verifications
--   (id, phone_number, otp_hash, purpose, verified, is_used, attempts, expires_at)
-- VALUES
--   (900001, '9000000001', 'zz_probe_hash', 'login', false, false, 0,
--    now() + interval '5 min');
--
-- INSERT INTO public.subscription_plans
--   (id, code, plan_name, price, validity_days, visits_included, is_active, sort_order)
-- VALUES (900001, 'zz_probe_plan', 'Probe', 1, 30, 1, true, 900001);
--
-- INSERT INTO public.user_subscriptions
--   (id, user_id, plan_id, status, total_visits, used_visits)
-- VALUES (900001, 900001, 900001, 'active', 2, 0);
--
-- INSERT INTO public.subscription_family_members
--   (id, subscription_id, member_name, relationship, member_type, identity_key)
-- VALUES (900001, 900001, 'Probe', 'self', 'adult', 'probe|self|');
--
-- INSERT INTO public.policies
--   (id, user_id, policy_type, policy_category, provider_name, policy_number, is_active)
-- VALUES (900001, 900001, 'health', 'individual', 'Probe', 'ZZ1', true);
--
-- INSERT INTO public.policy_members (id, policy_id, member_name)
-- VALUES (900001, 900001, 'Probe');
--
-- INSERT INTO public.field_members
--   (id, user_id, approval_status, is_available)
-- VALUES (900001, 900001, 'approved', true);
--
-- INSERT INTO public.service_requests
--   (id, user_id, request_type, charge_paid, status, visit_required)
-- VALUES (900001, 900001, 'probe', false, 'requested', true);
--
-- INSERT INTO public.request_assignments
--   (id, request_id, field_member_id, status)
-- VALUES (900001, 900001, 900001, 'active');
--
-- -- service_quotes.id is generated by its sequence; unlike the other 17
-- -- INSERTs, this probe does not use fixed id=900001 and consumes one id.
-- INSERT INTO public.service_quotes
--   (quote_ref, signature, user_id, request_type, status, expires_at)
-- VALUES ('zz-probe', 'zz_probe_signature', 900001, 'probe', 'active',
--         now() + interval '15 min');
--
-- INSERT INTO public.payments
--   (id, txn_id, user_id, payment_type, amount, currency, status, expires_at)
-- VALUES (900001, 'zz-probe-txn', 900001, 'subscription', 1, 'INR', 'pending',
--         now() + interval '10 min');
--
-- INSERT INTO public.visit_ledger
--   (id, subscription_id, user_id, entry_type, quantity)
-- VALUES (900001, 900001, 900001, 'allocated', 1);
--
-- INSERT INTO public.notifications
--   (id, user_id, title, message, category)
-- VALUES (900001, 900001, 'Probe', 'Probe', 'account');
--
-- -- Positive SELECT probes for the full runtime matrix.
-- SELECT (SELECT count(*) FROM public.users)
--      + (SELECT count(*) FROM public.branches)
--      + (SELECT count(*) FROM public.customer_profiles)
--      + (SELECT count(*) FROM public.field_members)
--      + (SELECT count(*) FROM public.notifications)
--      + (SELECT count(*) FROM public.otp_verifications)
--      + (SELECT count(*) FROM public.payments)
--      + (SELECT count(*) FROM public.policies)
--      + (SELECT count(*) FROM public.policy_members)
--      + (SELECT count(*) FROM public.request_assignments)
--      + (SELECT count(*) FROM public.service_quotes)
--      + (SELECT count(*) FROM public.service_requests)
--      + (SELECT count(*) FROM public.service_types)
--      + (SELECT count(*) FROM public.subscription_plans)
--      + (SELECT count(*) FROM public.subscription_family_members)
--      + (SELECT count(*) FROM public.user_subscriptions)
--      + (SELECT count(*) FROM public.visit_ledger)
--      + (SELECT count(*) FROM public.distance_rate_config) AS select_probe;
--
-- -- Exercise nextval() on every runtime id sequence (values are consumed).
-- DO $$
-- DECLARE
--     t text;
--     s text;
-- BEGIN
--     FOREACH t IN ARRAY ARRAY[
--         'users', 'branches', 'customer_profiles', 'field_members',
--         'notifications', 'otp_verifications', 'payments', 'policies',
--         'policy_members', 'request_assignments', 'service_quotes',
--         'service_requests', 'service_types', 'subscription_plans',
--         'subscription_family_members', 'user_subscriptions', 'visit_ledger',
--         'distance_rate_config'
--     ] LOOP
--         s := pg_catalog.pg_get_serial_sequence(format('public.%I', t), 'id');
--         IF s IS NULL THEN
--             RAISE EXCEPTION 'Missing id sequence for public.%', t;
--         END IF;
--         PERFORM nextval(s);
--     END LOOP;
-- END $$;
--
-- -- Required UPDATE probes.
-- UPDATE public.users SET username = 'zz_probe_user2' WHERE id = 900001;
-- UPDATE public.otp_verifications SET is_used = true WHERE id = 900001;
-- UPDATE public.customer_profiles SET full_name = 'Probe 2' WHERE id = 900001;
-- UPDATE public.service_requests SET status = 'in_progress' WHERE id = 900001;
-- UPDATE public.request_assignments SET status = 'unassigned' WHERE id = 900001;
-- UPDATE public.service_quotes SET status = 'consumed' WHERE quote_ref = 'zz-probe';
-- UPDATE public.payments SET status = 'success' WHERE txn_id = 'zz-probe-txn';
-- UPDATE public.subscription_plans SET plan_name = 'Probe 2' WHERE id = 900001;
-- UPDATE public.notifications SET is_read = true WHERE id = 900001;
--
-- -- Temporary setval() exception proof (requires UPDATE on the sequence).
-- -- The third argument true makes the next generated id 900002. This sequence
-- -- change persists after ROLLBACK and must be restored manually if needed.
-- SELECT setval(pg_catalog.pg_get_serial_sequence('public.subscription_plans', 'id'),
--               900001, true);
--
-- -- Required DELETE probes.
-- DELETE FROM public.otp_verifications WHERE id = 900001;
-- DELETE FROM public.subscription_family_members WHERE id = 900001;
-- DELETE FROM public.policy_members WHERE id = 900001;
-- DELETE FROM public.policies WHERE id = 900001;
-- DELETE FROM public.notifications WHERE id = 900001;
--
-- ROLLBACK;

-- =====================================================================
-- 9. DBA: temporary exception closure (NOT executed here).
-- =====================================================================

/*
Once app.services.plan_catalog.seed_subscription_plans() no longer calls
setval(), revoke the sequence UPDATE as a separately approved change:

    REVOKE UPDATE ON SEQUENCE public.subscription_plans_id_seq
      FROM rupaywala_app;

Confirm the physical sequence name first with:

    SELECT pg_get_serial_sequence('public.subscription_plans', 'id');

Then re-run section 7.7, the sequence assertion in 7.9, and the negative
setval() probe in the report. Until the runtime call is removed, this UPDATE
remains an explicitly accepted temporary exception.
*/

-- =====================================================================
-- 10. REQUIRED ALEMBIC OWNERSHIP RUNBOOK (future, separate process).
-- =====================================================================

/*
SOURCE VERIFIED: alembic/env.py:13,77 creates the engine directly from
DATABASE_URL with NullPool and never issues SET ROLE; alembic.ini:5-7 leaves
sqlalchemy.url empty. A plain login as rupaywala_migrator therefore gives
session_user=rupaywala_migrator and current_user=rupaywala_migrator.
INHERIT membership allows DDL against owner-owned objects, but the recorded
owner of NEW objects is current_user (the migrator) unless the startup role is
changed. A psql-only SET ROLE demonstration is NOT sufficient.

CHOSEN MECHANISM: libpq PGOPTIONS startup role on the actual Alembic process.
psycopg2/libpq reads PGOPTIONS for every connection made by the env.py:77
engine, so no runtime-code or migration edit is required. URL ?options=... is
a narrower alternative but needs careful percent-encoding. connect_args is
REJECTED because it would require editing alembic/env.py.

DSN separation:
  * validation_admin  = bootstrap/DBA SQL only; never application runtime.
  * rupaywala_migrator = Alembic process only, with PGOPTIONS owner startup.
  * rupaywala_app      = application runtime only.
  * The repository .env DSN is non-disposable; process-level DATABASE_URL
    override is mandatory. No password is shown or stored in this artifact.

PowerShell process-scope example (use a protected pgpass/secret store; do NOT
type a password into shell history):

    $env:DATABASE_URL = 'postgresql+psycopg2://rupaywala_migrator@127.0.0.1:55432/rupaywala_validation'
    $env:PGOPTIONS = '-c role=rupaywala_owner'
    psql "host=127.0.0.1 port=55432 dbname=rupaywala_validation user=rupaywala_migrator" -c "SELECT current_user, session_user;"
    # expected: current_user=rupaywala_owner; session_user=rupaywala_migrator
    alembic upgrade 0006_stage5_security_remediation
    Remove-Item Env:PGOPTIONS

Validate the identity with the IDENTICAL environment before Alembic runs.
Offline mode (`--sql`) cannot validate identity because env.py:60-70 opens no
connection. Runtime success remains UNVERIFIED until a future approved stage.

POST-0006 CATALOG VERIFICATION (run after migration; expect 0 bad rows unless
noted). These are static verification requirements, not executed here:

-- Identity under the same PGOPTIONS environment:
SELECT current_user, session_user;
-- expect rupaywala_owner | rupaywala_migrator

SELECT version_num FROM public.alembic_version;
-- expect 0006_stage5_security_remediation

SELECT pg_get_userbyid(nspowner) AS public_owner
FROM pg_namespace WHERE nspname = 'public';
-- expect rupaywala_owner

SELECT c.oid::regclass, c.relkind, pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r','p','S','v','m','f')
  AND c.relowner IS DISTINCT FROM (SELECT oid FROM pg_roles WHERE rolname='rupaywala_owner')
  AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid='pg_catalog.pg_class'::regclass AND d.objid=c.oid
        AND d.deptype IN ('e','x')
        AND d.refclassid='pg_catalog.pg_extension'::regclass
  );
-- expect 0 rows (existing AND newly created relations)

SELECT c.relname, pg_get_userbyid(c.relowner) AS owner,
       i.indrelid::regclass AS on_table, i.indisunique,
       i.indpred IS NOT NULL AS is_partial
FROM pg_class c JOIN pg_index i ON i.indexrelid=c.oid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('uq_service_requests_quote_ref',
                    'uq_payments_user_type_idem_open',
                    'uq_payments_open_extra_charge_request')
ORDER BY c.relname;
-- expect 3 rows, all owner=rupaywala_owner; two partial, one not partial

SELECT k.conname, k.contype, k.conrelid::regclass AS on_table,
       pg_get_userbyid(t.relowner) AS table_owner
FROM pg_constraint k JOIN pg_class t ON t.oid=k.conrelid
WHERE k.connamespace='public'::regnamespace
  AND k.conname='uq_service_requests_quote_ref';
-- expect 1 row, contype='u', table_owner=rupaywala_owner

SELECT a.attrelid::regclass AS table_name, a.attname,
       format_type(a.atttypid,a.atttypmod) AS type, a.attnotnull,
       pg_get_expr(ad.adbin,ad.adrelid) AS default_expr,
       pg_get_userbyid(c.relowner) AS table_owner
FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
WHERE n.nspname='public' AND NOT a.attisdropped
  AND ((c.relname='service_quotes' AND a.attname='signature_version')
    OR (c.relname='service_requests' AND a.attname='quote_ref'));
-- expect signature_version integer NOT NULL DEFAULT '1' and
-- quote_ref varchar(64) NULL; both table_owner=rupaywala_owner

SELECT pg_get_userbyid(c.relowner) AS owner, c.relkind, count(*)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
GROUP BY 1,2 ORDER BY 1,2;
-- FAIL if any owner is rupaywala_migrator or rupaywala_app

SELECT defaclrole::regrole::text, CASE WHEN defaclnamespace=0 THEN 'GLOBAL' ELSE 'public' END AS scope, defaclobjtype, defaclacl
FROM pg_catalog.pg_default_acl
WHERE defaclrole::regrole::text IN ('rupaywala_owner','rupaywala_migrator')
  AND defaclnamespace IN (0,'public'::regnamespace::oid)
  AND defaclobjtype IN ('r','S','f','T','n','L')
ORDER BY 1,2,3;
-- must still match section 7.10 expectations; scope GLOBAL affects every schema
*/

-- =====================================================================
-- 11. PRE-0006 GATE: revision and duplicate-data checks (DBA connection).
--     Human attestations required before this gate is considered complete:
--       * verified backup exists and restore test succeeded;
--       * maintenance window approved and application/migration sessions stopped;
--       * table-lock impact of building two partial unique indexes accepted;
--       * PGOPTIONS owner-startup strategy from section 10 approved and its
--         current_user/session_user probe validated with the same environment.
--     This section does not execute Alembic and does not modify data.
-- =====================================================================

DO $$
DECLARE
    v text;
    dup_idem bigint;
    dup_extra bigint;
BEGIN
    SELECT version_num INTO v FROM public.alembic_version;
    IF v IS DISTINCT FROM '0005_fixed_quotes' THEN
        RAISE EXCEPTION
            'Refusing 0006: revision is %, expected 0005_fixed_quotes', v;
    END IF;

    SELECT count(*) INTO dup_idem
    FROM (
        SELECT user_id, payment_type, idempotency_key, count(*) AS duplicates
        FROM public.payments
        WHERE idempotency_key IS NOT NULL
          AND status IN ('pending', 'pending_verification')
        GROUP BY user_id, payment_type, idempotency_key
        HAVING count(*) > 1
    ) d;

    SELECT count(*) INTO dup_extra
    FROM (
        SELECT related_request_id, count(*) AS duplicates
        FROM public.payments
        WHERE payment_type = 'extra_charge'
          AND related_request_id IS NOT NULL
          AND status IN ('pending', 'pending_verification')
        GROUP BY related_request_id
        HAVING count(*) > 1
    ) d;

    IF dup_idem > 0 OR dup_extra > 0 THEN
        RAISE EXCEPTION
            'Refusing 0006: duplicate open payments detected (idem=%, extra=%)',
            dup_idem, dup_extra;
    END IF;

    RAISE NOTICE
        'PASS: revision=0005_fixed_quotes; 0006 duplicate preflight checks returned zero rows';
END $$;

-- After a separately approved Alembic upgrade, verify the NEW revision:
/*
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.alembic_version
        WHERE version_num = '0006_stage5_security_remediation'
    ) THEN
        RAISE EXCEPTION
            'Post-upgrade revision check failed: expected 0006_stage5_security_remediation';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'service_quotes'
          AND column_name = 'signature_version'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'service_requests'
          AND column_name = 'quote_ref'
    ) THEN
        RAISE EXCEPTION 'Post-upgrade 0006 column check failed';
    END IF;
END $$;
*/

-- Expected 0006 objects (verified after execution, not created here):
--   public.service_quotes.signature_version (integer NOT NULL DEFAULT '1')
--   public.service_requests.quote_ref (varchar(64) NULL)
--   public.uq_service_requests_quote_ref (unique constraint)
--   public.uq_payments_user_type_idem_open (partial unique index)
--   public.uq_payments_open_extra_charge_request (partial unique index)
-- Downgrade consequence: all five objects above are removed; historical rows
-- are not updated or backfilled in either direction.

-- =====================================================================
-- 12. ROLLBACK / RECOVERY NOTE - documentation only, no destructive command.
-- =====================================================================

/*
Capture before execution:
  - database owner and datacl;
  - public schema owner and nspacl;
  - relation, type and routine owners and ACLs;
  - default ACLs;
  - role attributes and memberships, including ADMIN OPTION;
  - PUBLIC grants;
  - extension inventory;
  - alembic revision;
  - backup identifier and restore verification result.

Rollback principles (no destructive shortcut):
  1. Maintenance mode; stop application and migration sessions.
  2. Restore recorded owners explicitly.
  3. Restore recorded ACLs with explicit GRANT/REVOKE statements.
  4. Remove added default privileges.
  5. Revoke owner membership from the migrator only after ownership is restored.
  6. Drop roles only after no objects remain owned by them.
  7. Never use an ownership-bulk-removal shortcut on the disposable database.
  8. Validate revision, owners, ACLs, negative tests and application startup.

*/

-- =====================================================================
-- 7A. H-05: ROLE MEMBERSHIP COMPLETENESS (read-only catalog assertions)
--     PostgreSQL 18 pg_auth_members exposes member, roleid, inherit_option,
--     set_option and admin_option. The only permitted row touching the three
--     Stage 5.6D roles is:
--       member=rupaywala_migrator, roleid=rupaywala_owner,
--       inherit_option=true, set_option=true, admin_option=false.
--     This is the catalog representation of the Section 2 GRANT and is the
--     prerequisite for both inherited schema CREATE and the Section 10
--     PGOPTIONS='-c role=rupaywala_owner' startup-role strategy. INHERIT
--     alone is NOT accepted as proof that SET ROLE/startup role works;
--     set_option=true is required. Every other membership row touching these
--     roles, and every unexpected option combination, is reported with the
--     exact member, granted role and options. No membership is revoked here.
-- =====================================================================

SELECT pg_catalog.pg_get_userbyid(am.member) AS member_role,
       pg_catalog.pg_get_userbyid(am.roleid) AS granted_role,
       am.inherit_option,
       am.set_option,
       am.admin_option,
       CASE
           WHEN am.member = (SELECT oid FROM pg_catalog.pg_roles
                             WHERE rolname = 'rupaywala_migrator')
            AND am.roleid = (SELECT oid FROM pg_catalog.pg_roles
                             WHERE rolname = 'rupaywala_owner')
            AND am.inherit_option
            AND am.set_option
            AND NOT am.admin_option
           THEN 'EXPECTED_MIGRATOR_TO_OWNER'
           ELSE 'UNEXPECTED_MEMBERSHIP'
       END AS membership_assessment
FROM pg_catalog.pg_auth_members am
WHERE am.member IN (SELECT oid FROM pg_catalog.pg_roles
                    WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app'))
   OR am.roleid IN (SELECT oid FROM pg_catalog.pg_roles
                    WHERE rolname IN ('rupaywala_owner', 'rupaywala_migrator', 'rupaywala_app'))
ORDER BY member_role, granted_role;

DO $$
DECLARE
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    v_migrator oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator');
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_count int;
    v_details text;
BEGIN
    IF v_owner IS NULL OR v_migrator IS NULL OR v_app IS NULL THEN
        RAISE EXCEPTION 'H-05: required Stage 5.6D role(s) are missing; manual investigation required';
    END IF;

    SELECT string_agg(
               format('role=%s rolcanlogin=%s expected=%s rolinherit=%s expected=%s forbidden_attributes=%s',
                      r.rolname, r.rolcanlogin, e.canlogin, r.rolinherit, e.inherit,
                      (r.rolsuper OR r.rolcreatedb OR r.rolcreaterole
                       OR r.rolbypassrls OR r.rolreplication)::text),
               E'\n' ORDER BY r.rolname)
    INTO v_details
    FROM (VALUES
        ('rupaywala_owner'::text, false, true),
        ('rupaywala_migrator'::text, true, true),
        ('rupaywala_app'::text, true, false)
    ) e(rolname, canlogin, inherit)
    JOIN pg_catalog.pg_roles r ON r.rolname::text = e.rolname
    WHERE r.rolcanlogin <> e.canlogin
       OR r.rolinherit <> e.inherit
       OR r.rolsuper
       OR r.rolcreatedb
       OR r.rolcreaterole
       OR r.rolbypassrls
       OR r.rolreplication;

    IF v_details IS NOT NULL THEN
        RAISE EXCEPTION E'H-05: invalid role attributes; manual investigation required, no membership changed:\n%',
            v_details;
    END IF;

    WITH observed AS (
        SELECT am.member,
               am.roleid,
               am.inherit_option,
               am.set_option,
               am.admin_option,
               format('member=%s granted_role=%s inherit_option=%s set_option=%s admin_option=%s',
                      pg_catalog.pg_get_userbyid(am.member),
                      pg_catalog.pg_get_userbyid(am.roleid),
                      am.inherit_option,
                      am.set_option,
                      am.admin_option) AS state
        FROM pg_catalog.pg_auth_members am
        WHERE am.member IN (v_owner, v_migrator, v_app)
           OR am.roleid IN (v_owner, v_migrator, v_app)
    ),
    violations AS (
        SELECT 'UNEXPECTED_MEMBERSHIP'::text AS check_type,
               format('%s; detail=only migrator-to-owner membership touching these roles is permitted; manual investigation required',
                      o.state) AS detail
        FROM observed o
        WHERE NOT (o.member = v_migrator AND o.roleid = v_owner)

        UNION ALL

        SELECT 'INVALID_MIGRATOR_MEMBERSHIP_OPTIONS'::text AS check_type,
               format('%s; detail=expected inherit_option=true, set_option=true, admin_option=false; set_option is required by the PGOPTIONS startup-role strategy',
                      o.state) AS detail
        FROM observed o
        WHERE o.member = v_migrator
          AND o.roleid = v_owner
          AND NOT (o.inherit_option AND o.set_option AND NOT o.admin_option)
    )
    SELECT count(*), string_agg(format('%s %s', check_type, detail), E'\n' ORDER BY check_type, detail)
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'H-05: role membership completeness audit failed for % finding(s); no membership was revoked:\n%',
            v_count, v_details;
    END IF;

    SELECT count(*) INTO v_count
    FROM pg_catalog.pg_auth_members
    WHERE member = v_migrator
      AND roleid = v_owner;

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'H-05: expected exactly one migrator-to-owner membership row, observed %; manual investigation required',
            v_count;
    END IF;
END $$;

-- =====================================================================
-- 7B. H-06: DATABASE AND SCHEMA ACL COMPLETENESS (read-only assertions)
--     Direct/ACL-level provenance is read from pg_database.datacl and
--     pg_namespace.nspacl. NULL ACLs are expanded with acldefault('d',
--     datdba) and acldefault('n', nspowner) so PostgreSQL built-in defaults
--     are not misreported as missing grants. aclexplode() exposes grantee,
--     privilege_type and is_grantable; grantee 0 is PUBLIC. Effective checks
--     with has_database_privilege()/has_schema_privilege() are separate:
--     app TEMP is allowed only via the documented PUBLIC default, and
--     migrator schema CREATE must be inherited through the audited owner
--     membership, never a direct migrator ACL entry. Unexpected ACLs are
--     reported with exact object, grantee, privilege and grant-option state
--     and are NEVER revoked here.
-- =====================================================================

WITH db_entries AS (
    SELECT 'DATABASE'::text AS object_type,
           d.datname::text AS object_name,
           CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(a.grantee)
           END AS grantee,
           CASE WHEN a.privilege_type IN ('TEMP', 'TEMPORARY') THEN 'TEMPORARY'
                ELSE a.privilege_type
           END AS privilege,
           a.is_grantable AS grant_option,
           CASE WHEN d.datacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
    FROM pg_catalog.pg_database d
    CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
    WHERE d.datname = 'rupaywala_validation'
),
schema_entries AS (
    SELECT 'SCHEMA'::text AS object_type,
           n.nspname::text AS object_name,
           CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(a.grantee)
           END AS grantee,
           a.privilege_type AS privilege,
           a.is_grantable AS grant_option,
           CASE WHEN n.nspacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
    FROM pg_catalog.pg_namespace n
    CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
    WHERE n.nspname = 'public'
),
all_entries AS (
    SELECT * FROM db_entries
    UNION ALL
    SELECT * FROM schema_entries
)
SELECT e.object_type,
       e.object_name,
       e.grantee,
       e.privilege,
       e.grant_option,
       e.acl_source,
       CASE e.object_type
           WHEN 'DATABASE' THEN pg_catalog.has_database_privilege(
               CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
               e.object_name, e.privilege)
           WHEN 'SCHEMA' THEN pg_catalog.has_schema_privilege(
               CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
               e.object_name, e.privilege)
       END AS effective_privilege
FROM all_entries e
WHERE e.grantee IN ('PUBLIC', 'rupaywala_app', 'rupaywala_owner', 'rupaywala_migrator')
ORDER BY e.object_type, e.object_name, e.grantee, e.privilege;

DO $$
DECLARE
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_owner');
    v_migrator oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_migrator');
    v_db text := 'rupaywala_validation';
    v_schema text := 'public';
    v_count int;
    v_details text;
BEGIN
    IF v_app IS NULL OR v_owner IS NULL OR v_migrator IS NULL THEN
        RAISE EXCEPTION 'H-06: required Stage 5.6D role(s) are missing; manual investigation required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_database WHERE datname = v_db) THEN
        RAISE EXCEPTION 'H-06: disposable database % is missing', v_db;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = v_schema) THEN
        RAISE EXCEPTION 'H-06: schema % is missing', v_schema;
    END IF;

    WITH db_acl AS (
        SELECT 'DATABASE'::text AS object_type,
               d.datname::text AS object_name,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(a.grantee)
               END AS grantee,
               CASE WHEN a.privilege_type IN ('TEMP', 'TEMPORARY') THEN 'TEMPORARY'
                    ELSE a.privilege_type
               END AS privilege,
               a.is_grantable AS grant_option,
               CASE WHEN d.datacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
        FROM pg_catalog.pg_database d
        CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
        WHERE d.datname = v_db
    ),
    schema_acl AS (
        SELECT 'SCHEMA'::text AS object_type,
               n.nspname::text AS object_name,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(a.grantee)
               END AS grantee,
               a.privilege_type AS privilege,
               a.is_grantable AS grant_option,
               CASE WHEN n.nspacl IS NULL THEN 'ACL_DEFAULT' ELSE 'DIRECT_ACL' END AS acl_source
        FROM pg_catalog.pg_namespace n
        CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
        WHERE n.nspname = v_schema
    ),
    direct_acl AS (
        SELECT * FROM db_acl
        UNION ALL
        SELECT * FROM schema_acl
    ),
    allowed_acl(object_type, grantee, privilege, expected_grant_option) AS (
        VALUES
            ('DATABASE'::text, 'PUBLIC'::text, 'CONNECT'::text, false),
            ('DATABASE'::text, 'PUBLIC'::text, 'TEMPORARY'::text, false),
            ('DATABASE'::text, 'rupaywala_app'::text, 'CONNECT'::text, false),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'CONNECT'::text, false),
            ('SCHEMA'::text, 'PUBLIC'::text, 'USAGE'::text, false),
            ('SCHEMA'::text, 'rupaywala_app'::text, 'USAGE'::text, false),
            ('SCHEMA'::text, 'rupaywala_owner'::text, 'CREATE'::text, NULL::boolean),
            ('SCHEMA'::text, 'rupaywala_owner'::text, 'USAGE'::text, NULL::boolean)
    ),
    unexpected_acl AS (
        SELECT 'UNEXPECTED_DIRECT_ACL'::text AS check_type,
               d.object_type,
               d.object_name,
               d.grantee,
               d.privilege,
               d.grant_option,
               format('acl_source=%s; detail=unexpected direct ACL entry for audited grantee; manual investigation required',
                      d.acl_source) AS detail
        FROM direct_acl d
        LEFT JOIN allowed_acl a
          ON a.object_type = d.object_type
         AND a.grantee = d.grantee
         AND a.privilege = d.privilege
        WHERE d.grantee IN ('PUBLIC', 'rupaywala_app', 'rupaywala_owner', 'rupaywala_migrator')
          AND (
              a.object_type IS NULL
              OR (
                  a.expected_grant_option IS NOT NULL
                  AND d.grant_option IS DISTINCT FROM a.expected_grant_option
              )
          )
    ),
    expected_direct(object_type, grantee, privilege) AS (
        VALUES
            ('DATABASE'::text, 'PUBLIC'::text, 'CONNECT'::text),
            ('DATABASE'::text, 'PUBLIC'::text, 'TEMPORARY'::text),
            ('DATABASE'::text, 'rupaywala_app'::text, 'CONNECT'::text),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'CONNECT'::text),
            ('SCHEMA'::text, 'PUBLIC'::text, 'USAGE'::text),
            ('SCHEMA'::text, 'rupaywala_app'::text, 'USAGE'::text)
    ),
    missing_direct AS (
        SELECT 'MISSING_DIRECT_ACL'::text AS check_type,
               e.object_type,
               CASE e.object_type WHEN 'DATABASE' THEN v_db ELSE v_schema END AS object_name,
               e.grantee,
               e.privilege,
               NULL::boolean AS grant_option,
               'detail=expected direct ACL entry; acldefault() expansion of a NULL ACL counts as ACL provenance'::text AS detail
        FROM expected_direct e
        WHERE NOT EXISTS (
            SELECT 1
            FROM direct_acl d
            WHERE d.object_type = e.object_type
              AND d.grantee = e.grantee
              AND d.privilege = e.privilege
        )
    ),
    expected_effective(object_type, grantee, privilege, expected) AS (
        VALUES
            ('DATABASE'::text, 'PUBLIC'::text, 'CONNECT'::text, true),
            ('DATABASE'::text, 'PUBLIC'::text, 'TEMPORARY'::text, true),
            ('DATABASE'::text, 'PUBLIC'::text, 'CREATE'::text, false),
            ('DATABASE'::text, 'rupaywala_app'::text, 'CONNECT'::text, true),
            ('DATABASE'::text, 'rupaywala_app'::text, 'TEMPORARY'::text, true),
            ('DATABASE'::text, 'rupaywala_app'::text, 'CREATE'::text, false),
            ('DATABASE'::text, 'rupaywala_owner'::text, 'CONNECT'::text, true),
            ('DATABASE'::text, 'rupaywala_owner'::text, 'TEMPORARY'::text, true),
            ('DATABASE'::text, 'rupaywala_owner'::text, 'CREATE'::text, false),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'CONNECT'::text, true),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'TEMPORARY'::text, true),
            ('DATABASE'::text, 'rupaywala_migrator'::text, 'CREATE'::text, false),
            ('SCHEMA'::text, 'PUBLIC'::text, 'USAGE'::text, true),
            ('SCHEMA'::text, 'PUBLIC'::text, 'CREATE'::text, false),
            ('SCHEMA'::text, 'rupaywala_app'::text, 'USAGE'::text, true),
            ('SCHEMA'::text, 'rupaywala_app'::text, 'CREATE'::text, false),
            ('SCHEMA'::text, 'rupaywala_owner'::text, 'USAGE'::text, true),
            ('SCHEMA'::text, 'rupaywala_owner'::text, 'CREATE'::text, true),
            ('SCHEMA'::text, 'rupaywala_migrator'::text, 'USAGE'::text, true),
            ('SCHEMA'::text, 'rupaywala_migrator'::text, 'CREATE'::text, true)
    ),
    effective_mismatch AS (
        SELECT 'EFFECTIVE_PRIVILEGE_MISMATCH'::text AS check_type,
               e.object_type,
               CASE e.object_type WHEN 'DATABASE' THEN v_db ELSE v_schema END AS object_name,
               e.grantee,
               e.privilege,
               NULL::boolean AS grant_option,
               format('expected=%s observed=%s; detail=effective privilege differs from the intended model',
                      e.expected, o.effective) AS detail
        FROM expected_effective e
        CROSS JOIN LATERAL (
            SELECT CASE e.object_type
                       WHEN 'DATABASE' THEN pg_catalog.has_database_privilege(
                           CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
                           v_db, e.privilege)
                       WHEN 'SCHEMA' THEN pg_catalog.has_schema_privilege(
                           CASE WHEN e.grantee = 'PUBLIC' THEN 'public' ELSE e.grantee END,
                           v_schema, e.privilege)
                   END AS effective
        ) o
        WHERE o.effective IS DISTINCT FROM e.expected
    ),
    violations AS (
        SELECT * FROM unexpected_acl
        UNION ALL SELECT * FROM missing_direct
        UNION ALL SELECT * FROM effective_mismatch
    )
    SELECT count(*),
           string_agg(
               format('%s object_type=%s object=%s grantee=%s privilege=%s grant_option=%s %s',
                      check_type, object_type, object_name, grantee, privilege,
                      COALESCE(grant_option::text, '-'), detail),
               E'\n' ORDER BY check_type, object_type, object_name, grantee, privilege)
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'H-06: database/schema ACL completeness audit failed for % finding(s); no ACL was revoked, manual investigation required:\n%',
            v_count, v_details;
    END IF;
END $$;

-- =====================================================================
-- 13. EXHAUSTIVE PUBLIC RELATION/SEQUENCE PRIVILEGE ALLOWLIST AUDIT
--     Fail-closed supplement to Section 7.9/7.10. This section is READ-ONLY:
--     it inventories every public relation/sequence, compares direct ACL
--     entries and effective app privileges with an explicit source-derived
--     allowlist, reports exact object/privilege/grantee/grant-option
--     violations, and never revokes anything from unknown objects.
-- =====================================================================

-- Evidence: every existing public relation/sequence, its owner, raw ACL,
-- effective rupaywala_app privileges, and expanded app/PUBLIC ACL entries.
-- NULL ACLs are expanded with acldefault(): 's' for sequences, 'r' for all
-- other relation kinds. Inherited/PUBLIC-derived access is visible only in
-- the effective columns; ACL provenance is visible in app_public_acl_entries.
SELECT s.oid::regclass AS object_name,
       s.relkind,
       pg_catalog.pg_get_userbyid(s.relowner) AS owner,
       s.relacl,
       CASE WHEN s.relkind = 'S' THEN
           jsonb_build_object(
               'USAGE', pg_catalog.has_sequence_privilege('rupaywala_app', s.oid, 'USAGE'),
               'SELECT', pg_catalog.has_sequence_privilege('rupaywala_app', s.oid, 'SELECT'),
               'UPDATE', pg_catalog.has_sequence_privilege('rupaywala_app', s.oid, 'UPDATE'))
       ELSE
           jsonb_build_object(
               'SELECT', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'SELECT'),
               'INSERT', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'INSERT'),
               'UPDATE', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'UPDATE'),
               'DELETE', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'DELETE'),
               'TRUNCATE', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'TRUNCATE'),
               'TRIGGER', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'TRIGGER'),
               'REFERENCES', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'REFERENCES'),
               'MAINTAIN', pg_catalog.has_table_privilege('rupaywala_app', s.oid, 'MAINTAIN'))
       END AS app_effective_privileges,
       (SELECT jsonb_agg(jsonb_build_object(
                   'grantee', CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee) END,
                   'privilege', a.privilege_type,
                   'grantable', a.is_grantable))
        FROM aclexplode(COALESCE(
                 s.relacl,
                 acldefault((CASE WHEN s.relkind = 'S' THEN 's' ELSE 'r' END)::"char", s.relowner))) a
        WHERE a.grantee IN (0, (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app')))
       AS app_public_acl_entries
FROM pg_catalog.pg_class s
JOIN pg_catalog.pg_namespace n ON n.oid = s.relnamespace
WHERE n.nspname = 'public'
  AND s.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
ORDER BY s.relkind, s.relname;

-- Strict fail-closed audit. Expected table privileges are the source-derived
-- S/I/U/D matrix from Section 8 of the remediation report. Expected sequences are
-- the 18 id sequences returned by pg_get_serial_sequence() for the insert
-- tables: USAGE only, SELECT false, UPDATE false except subscription_plans.
-- family_members and alembic_version are expected objects with zero rights.
-- Any other public relation/sequence is an UNLISTED_OBJECT violation. A listed
-- name with the wrong relkind is a RELKIND_MISMATCH violation. Every expected
-- app privilege must also be present as a direct ACL entry. PUBLIC object ACLs
-- are never allowed here; PUBLIC database/schema/type/routine defaults are
-- audited separately in Section 7.10. This read-only section cannot weaken
-- owner or migrator privileges; earlier ownership assertions remain in force.
DO $$
DECLARE
    v_app oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rupaywala_app');
    v_public oid := 0;
    v_count int;
    v_details text;
BEGIN
    WITH expected_rel(relname, sel, ins, upd, del) AS (
        VALUES
            ('users', true, true, true, false),
            ('branches', true, true, true, false),
            ('customer_profiles', true, true, true, false),
            ('field_members', true, true, true, false),
            ('notifications', true, true, true, true),
            ('otp_verifications', true, true, true, true),
            ('payments', true, true, true, false),
            ('policies', true, true, false, true),
            ('policy_members', true, true, false, true),
            ('request_assignments', true, true, true, false),
            ('service_quotes', true, true, true, false),
            ('service_requests', true, true, true, false),
            ('service_types', true, true, true, false),
            ('subscription_plans', true, true, true, false),
            ('subscription_family_members', true, true, false, true),
            ('user_subscriptions', true, true, true, false),
            ('visit_ledger', true, true, false, false),
            ('distance_rate_config', true, true, false, false),
            ('family_members', false, false, false, false),
            ('alembic_version', false, false, false, false)
    ),
    expected_seq(table_name, usage, sel, upd) AS (
        VALUES
            ('users', true, false, false),
            ('branches', true, false, false),
            ('customer_profiles', true, false, false),
            ('field_members', true, false, false),
            ('notifications', true, false, false),
            ('otp_verifications', true, false, false),
            ('payments', true, false, false),
            ('policies', true, false, false),
            ('policy_members', true, false, false),
            ('request_assignments', true, false, false),
            ('service_quotes', true, false, false),
            ('service_requests', true, false, false),
            ('service_types', true, false, false),
            ('subscription_plans', true, false, true),
            ('subscription_family_members', true, false, false),
            ('user_subscriptions', true, false, false),
            ('visit_ledger', true, false, false),
            ('distance_rate_config', true, false, false)
    ),
    expected_seq_oid AS (
        SELECT es.table_name,
               pg_catalog.pg_get_serial_sequence(format('public.%I', es.table_name), 'id')::regclass AS seq_oid,
               es.usage, es.sel, es.upd
        FROM expected_seq es
    ),
    expected_objects AS (
        SELECT c.oid AS obj_oid,
               ARRAY['r', 'p']::text[] AS expected_kinds,
               'RELATION'::text AS object_kind,
               er.sel, er.ins, er.upd, er.del,
               NULL::boolean AS seq_usage, NULL::boolean AS seq_sel, NULL::boolean AS seq_upd
        FROM expected_rel er
        JOIN pg_catalog.pg_class c ON c.oid = to_regclass(format('public.%I', er.relname))
        UNION ALL
        SELECT c.oid,
               ARRAY['S']::text[],
               'SEQUENCE'::text,
               NULL::boolean, NULL::boolean, NULL::boolean, NULL::boolean,
               eso.usage, eso.sel, eso.upd
        FROM expected_seq_oid eso
        JOIN pg_catalog.pg_class c ON c.oid = eso.seq_oid
    ),
    scope AS (
        SELECT c.oid, c.relkind, c.relname, c.relowner, c.relacl,
               COALESCE(c.relacl,
                        acldefault((CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END)::"char", c.relowner)) AS expanded_acl
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
    ),
    unlisted AS (
        SELECT 'UNLISTED_OBJECT'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               format('unexpected object with relkind=%s in public', s.relkind::text) AS detail
        FROM scope s
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        WHERE e.obj_oid IS NULL
    ),
    relkind_mismatch AS (
        SELECT 'RELKIND_MISMATCH'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               NULL::text AS privilege,
               NULL::text AS grantee,
               format('expected relkind in [%s], observed %s',
                      array_to_string(e.expected_kinds, ','), s.relkind::text) AS detail
        FROM scope s
        JOIN expected_objects e ON e.obj_oid = s.oid
        WHERE NOT (s.relkind::text = ANY(e.expected_kinds))
    ),
    direct_acl AS (
        SELECT 'DIRECT_ACL'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               a.privilege_type AS privilege,
               CASE WHEN a.grantee = v_public THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee) END AS grantee,
               CASE
                   WHEN a.grantee = v_public AND a.is_grantable THEN 'PUBLIC ACL WITH GRANT OPTION is not allowed'
                   WHEN a.grantee = v_public THEN 'PUBLIC object ACL is not allowed'
                   WHEN a.is_grantable THEN 'WITH GRANT OPTION is not allowed'
                   WHEN e.obj_oid IS NULL THEN 'unlisted object has direct app ACL'
                   ELSE 'unexpected direct privilege for rupaywala_app'
               END AS detail
        FROM scope s
        CROSS JOIN LATERAL aclexplode(s.expanded_acl) a
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        WHERE a.grantee IN (v_app, v_public)
          AND (
              a.grantee = v_public
              OR a.is_grantable
              OR e.obj_oid IS NULL
              OR CASE
                     WHEN s.relkind = 'S' THEN NOT (
                          (a.privilege_type = 'USAGE' AND COALESCE(e.seq_usage, false))
                       OR (a.privilege_type = 'SELECT' AND COALESCE(e.seq_sel, false))
                       OR (a.privilege_type = 'UPDATE' AND COALESCE(e.seq_upd, false))
                     )
                     ELSE NOT (
                          (a.privilege_type = 'SELECT' AND COALESCE(e.sel, false))
                       OR (a.privilege_type = 'INSERT' AND COALESCE(e.ins, false))
                       OR (a.privilege_type = 'UPDATE' AND COALESCE(e.upd, false))
                       OR (a.privilege_type = 'DELETE' AND COALESCE(e.del, false))
                     )
                 END
          )
    ),
    missing_direct AS (
        SELECT 'MISSING_DIRECT_ACL'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               p.privilege AS privilege,
               'rupaywala_app'::text AS grantee,
               format('expected direct %s grant on listed relation', p.privilege) AS detail
        FROM scope s
        JOIN expected_objects e ON e.obj_oid = s.oid
        CROSS JOIN LATERAL (VALUES
            ('SELECT', e.sel),
            ('INSERT', e.ins),
            ('UPDATE', e.upd),
            ('DELETE', e.del)
        ) p(privilege, expected)
        WHERE s.relkind <> 'S'
          AND p.expected
          AND NOT EXISTS (
              SELECT 1
              FROM aclexplode(s.expanded_acl) a
              WHERE a.grantee = v_app
                AND a.privilege_type = p.privilege
          )
        UNION ALL
        SELECT 'MISSING_DIRECT_ACL'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               p.privilege AS privilege,
               'rupaywala_app'::text AS grantee,
               format('expected direct %s grant on listed sequence', p.privilege) AS detail
        FROM scope s
        JOIN expected_objects e ON e.obj_oid = s.oid
        CROSS JOIN LATERAL (VALUES
            ('USAGE', e.seq_usage),
            ('SELECT', e.seq_sel),
            ('UPDATE', e.seq_upd)
        ) p(privilege, expected)
        WHERE s.relkind = 'S'
          AND p.expected
          AND NOT EXISTS (
              SELECT 1
              FROM aclexplode(s.expanded_acl) a
              WHERE a.grantee = v_app
                AND a.privilege_type = p.privilege
          )
    ),
    effective_rel AS (
        SELECT 'EFFECTIVE_TABLE_PRIVILEGE'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               p.privilege AS privilege,
               'rupaywala_app'::text AS grantee,
               format('expected %s, observed %s', p.expected,
                      pg_catalog.has_table_privilege(v_app, s.oid, p.privilege)) AS detail
        FROM scope s
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        CROSS JOIN LATERAL (VALUES
            ('SELECT', COALESCE(e.sel, false)),
            ('INSERT', COALESCE(e.ins, false)),
            ('UPDATE', COALESCE(e.upd, false)),
            ('DELETE', COALESCE(e.del, false)),
            ('TRUNCATE', false),
            ('TRIGGER', false),
            ('REFERENCES', false),
            ('MAINTAIN', false)
        ) p(privilege, expected)
        WHERE s.relkind <> 'S'
          AND pg_catalog.has_table_privilege(v_app, s.oid, p.privilege) <> p.expected
    ),
    effective_seq AS (
        SELECT 'EFFECTIVE_SEQUENCE_PRIVILEGE'::text AS check_type,
               format('public.%I', s.relname) AS object_name,
               p.privilege AS privilege,
               'rupaywala_app'::text AS grantee,
               format('expected %s, observed %s', p.expected,
                      pg_catalog.has_sequence_privilege(v_app, s.oid, p.privilege)) AS detail
        FROM scope s
        LEFT JOIN expected_objects e ON e.obj_oid = s.oid
        CROSS JOIN LATERAL (VALUES
            ('USAGE', COALESCE(e.seq_usage, false)),
            ('SELECT', COALESCE(e.seq_sel, false)),
            ('UPDATE', COALESCE(e.seq_upd, false))
        ) p(privilege, expected)
        WHERE s.relkind = 'S'
          AND pg_catalog.has_sequence_privilege(v_app, s.oid, p.privilege) <> p.expected
    ),
    violations AS (
        SELECT * FROM unlisted
        UNION ALL SELECT * FROM relkind_mismatch
        UNION ALL SELECT * FROM direct_acl
        UNION ALL SELECT * FROM missing_direct
        UNION ALL SELECT * FROM effective_rel
        UNION ALL SELECT * FROM effective_seq
    )
    SELECT count(*),
           string_agg(
               format('%s object=%s privilege=%s grantee=%s detail=%s',
                      check_type, object_name, COALESCE(privilege, '-'),
                      COALESCE(grantee, '-'), detail),
               E'\n' ORDER BY check_type, object_name, privilege, grantee
           )
    INTO v_count, v_details
    FROM violations;

    IF v_count > 0 THEN
        RAISE EXCEPTION E'Exhaustive public relation/sequence privilege audit failed for % finding(s):\n%',
            v_count, v_details;
    END IF;
END $$;

-- END OF STAGE 5.6D CORRECTED SQL ARTIFACT - NOT EXECUTED.