# RUPAYWALA — Stage 5.6G Security Test Results

## Status
**PARTIALLY COMPLETE**

Security validation was performed in disposable `rupaywala_e2e_validation` against the actual FastAPI app running as restricted role `rw56g_app` (mirroring `rupaywala_app` grants). Core privilege denials passed. Some application-level security behaviors were partially covered; full adversarial coverage was not completed.

## Test Context
| Item | Value |
|---|---|
| Container | `rupaywala-pg18-validation` (PostgreSQL 18.1) |
| Disposable DB | `rupaywala_e2e_validation` |
| Source DB | `rupaywala_role_validation` (not modified) |
| App runtime role | `rw56g_app` (temporary, E2E DB only) |
| Runtime identity | `rupaywala_e2e_validation | rw56g_app | rw56g_app` |
| App endpoint | `127.0.0.1:18080` |

## Database Privilege / Role Checks
| Check | Expected | Result | Evidence |
|---|---|---|---|
| `rupaywala_app` USAGE on `public.subscription_plans_id_seq` | true | PASS | `has_sequence_privilege(...,'USAGE')=t` |
| `rupaywala_app` UPDATE on `public.subscription_plans_id_seq` | false | PASS | revoked in E2E DB only; `has_sequence_privilege(...,'UPDATE')=f` |
| `rw56g_app` USAGE on `public.subscription_plans_id_seq` | true | PASS | `t` |
| `rw56g_app` UPDATE on `public.subscription_plans_id_seq` | false | PASS | `f` |
| App role cannot `setval()` | denied | PASS | `SET ROLE rupaywala_app; SELECT setval(pg_get_serial_sequence('public.subscription_plans','id'),1,false);` => `permission denied for sequence subscription_plans_id_seq` |
| App role cannot CREATE in public schema | denied | PASS | `SET ROLE rupaywala_app; CREATE TABLE public.zz_stage56g_bad(id int);` => `permission denied for schema public` |
| App role cannot TRUNCATE | denied | PASS | `SET ROLE rupaywala_app; TRUNCATE TABLE public.notifications;` => `permission denied for table notifications` |
| App role cannot access `alembic_version` | denied | PASS | `SET ROLE rupaywala_app; SELECT * FROM public.alembic_version;` => permission denied / no table privilege |
| App role not superuser/createdb/createrole/bypassrls | all false | PASS | `pg_roles` shows `rolsuper=f, rolcreatedb=f, rolcreaterole=f, rolbypassrls=f, rolcanlogin=t, rolinherit=f` for `rupaywala_app` |
| `rw56g_app` role attributes safe | restricted | PASS | same restricted attributes; LOGIN NOINHERIT, no replication |

## Runtime Application Security Checks
| Check | Result | Evidence / Notes |
|---|---|---|
| No permission-denied DB errors during normal workflows | PASS | Scanned uvicorn err log for `permission denied`/insufficient privilege strings after tests; none found |
| No runtime DDL observed | PASS (observed) | no CREATE/ALTER statements in app behavior; DB role denied CREATE |
| No runtime TRUNCATE observed | PASS (observed) | DB role denied TRUNCATE |
| No sequence UPDATE requirement | PASS | startup seeding and plan catalog operations succeeded without sequence UPDATE; 5.6F fix uses nextval/USAGE |
| No application access to Alembic migration tables | PASS | DB role denied SELECT on `alembic_version` |
| No privilege escalation observed | PASS (limited) | no role creation/membership changes attempted by app; role attributes restricted |
| Transaction rollback on failed workflows | PARTIAL | invalid/failed API requests returned 4xx without crashing app; explicit DB rollback inspection not instrumented |
| Ownership/tenant isolation | PARTIAL | mocked flow: other customer request retrieval returned 403/404. Additional object-level checks across all endpoints not exhaustively tested |
| Quote/payment integrity protections | PARTIAL | consumed quote reuse 409; invalid quote 404; payment submit/verify flows enforced. Expiry/signature/tamper cases not fully exercised in this pass |
| Duplicate payment prevention | PARTIAL | same idempotency key produced same behavior in some cases but v3 observed different txn_ids for r1/r2 200; needs focused review. Duplicate submit returned idempotent 200 with unchanged attempts; duplicate verify returned idempotent 200 |

## `plan_catalog` Concurrent Seeding Safety (5.6F follow-up)
| Check | Result | Notes |
|---|---|---|
| Static review | CONCERN / NOT FULLY PROVEN | `_ensure_subscription_plans_sequence()` uses atomic `nextval` (good) and no backward reset. `seed_subscription_plans()` performs read/update/insert/commit sequence; concurrent startup seeding may race on insert/update ordering. Not observed to fail in this single-process startup. |
| Focused concurrent regression test | NOT TESTED | Not added/executed due time/scope and need to avoid unsafe test harness; recommend disposable-DB concurrent test before production claim. |

## Pytest Safety Gate
| Check | Result | Notes |
|---|---|---|
| `tests/conftest.py` inspection | BLOCKED for pytest execution | conftest creates `rupaywala_test`, sets env, drops/creates public schema, truncates tables; destructive by design. No pytest run in Stage 5.6G. |

## Gaps / Not Tested
- SQL injection / fuzzing / adversarial payloads.
- Full object-level authorization matrix across every endpoint.
- Quote expiry enforcement at boundary time.
- Tampered quote signature/integrity negative test through API.
- Concurrent payment verification race.
- File upload path traversal/content-type abuse beyond existing static checks.
- RLS behavior (app role has no BYPASSRLS; no RLS policies assessed here).
- Network/TLS/pg_hba/secret management/backup restore to production-like infra.

## Summary
Core restricted-role DB denials and actual-app startup under `rw56g_app` passed. No permission-denied runtime DB errors were observed in uvicorn logs during tested workflows. Application-level security coverage is partial and requires follow-up before any production readiness claim.