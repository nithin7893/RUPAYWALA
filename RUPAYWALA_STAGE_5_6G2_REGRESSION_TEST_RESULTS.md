# RUPAYWALA STAGE 5.6G-2 — Regression Test Results

## Execution Context
- Date: 2026-11-21
- Project: `C:\RUPAAY_WALA\rupaywala_backend`
- Disposable DB: `rupaywala_g2seed_validation` (Postgres 18.1, container `rupaywala-pg18-validation`, host `127.0.0.1:55432`)
- DB created as clone of `rupaywala_role_validation` after existence check; preserved DBs not modified.
- Default `tests/conftest.py` inspected: destructive (drops/recreates `public` schema on `rupaywala_test`, truncates data). Not used.
- Focused tests run via isolated standalone runners/scripts with `TESTING=1` and disposable DB URL; no existing preserved DB targeted.

## Required Seeding/Concurrency Cases

| # | Case | Result | Evidence |
|---|---|---|---|
| 1 | Three concurrent seed calls | **PASS** | 3 workers, 0 errors, active=7, total=7, dup_codes=false |
| 2 | Five concurrent seed calls | **PASS** | 5 workers, 0 errors, active=7, total=7, dup_codes=false |
| 3 | Ten concurrent seed calls | **PASS** | 10 workers, 0 errors, active=7, total=7, dup_codes=false |
| 4 | Repeated sequential seed calls | **PASS** | 10 sequential calls, 0 errors, count=7, IDs stable |
| 5 | Concurrent calls with initially empty table | **PASS** | 5 workers, 0 errors, count=7, no duplicates |
| 6 | Concurrent calls with existing subscription plans | **PASS** | 5 workers, 0 errors, count=7, no duplicates |
| 7 | Startup seeding under restricted `rupaywala_app` permissions | **PASS** | temp role `rw_g2_app` granted CONNECT, schema USAGE, table SELECT/INSERT/UPDATE/DELETE, sequence USAGE/SELECT; 5 concurrent seeds, 0 errors, count=7 |
| 8 | Sequence-generated inserts without sequence UPDATE permission | **PASS** | `has_sequence_privilege(...,'USAGE')=true`, `has_sequence_privilege(...,'UPDATE')=false`; seeding succeeded |
| 9 | Transaction failure and rollback behavior | **PASS** | forced conflicting insert rolled back; plan count/IDs preserved; subsequent seed succeeded; IDs preserved |
| 10 | Final subscription plan count and IDs | **PASS** | final count=7, all expected present, IDs stable after rerun |

## Focused Subscription Catalog Tests (Isolated)

| Test | Result |
|---|---|
| `test_catalog_is_idempotent_and_archives_non_catalog_plans` | PASS |
| `test_catalog_repairs_a_behind_postgres_id_sequence` | PASS |
| `test_digital_entitlement_does_not_consume_a_home_visit` | PASS |
| `test_digital_service_request_is_allowed_without_home_visits` | PASS |
| `test_distance_plan_override_keeps_round_trip_pricing` | PASS |
| `test_duplicate_family_member_is_rejected` | PASS |
| `test_family_member_limit_counts_primary_subscriber` | PASS |
| `test_plan_entitlements_match_the_catalog` | PASS |
| `test_renewal_preserves_the_previous_period_and_snapshots_new_benefits` | PASS |
| `test_seed_preserves_admin_configured_premium_values_and_activation` | PASS |
| `test_seed_subscription_plans_concurrent_startup` | PASS |

**Summary:** 11 passed, 0 failed, 0 skipped.

## Payment All-Status Idempotency Preflight (Read-Only)

| Check | Result | Notes |
|---|---|---|
| Duplicate preflight on `(user_id,payment_type,idempotency_key)` WHERE key IS NOT NULL | **NOT SUFFICIENT** | Disposable DB query returned 0 total payments, 0 keyed, 0 duplicates; cannot prove absence in preserved/production-like data. |
| Index/schema modification | **NOT EXECUTED** | No index added/modified; no payment schema changes combined with seeding fix. |

## Not Run / Blocked
- Full pytest suite: **BLOCKED** (destructive conftest / isolation risk).
- Live external integrations: **BLOCKED/NOT TESTED**.
- Target-data duplicate preflight for full payment idempotency index: **BLOCKED/NOT EXECUTED** (no authorized read-only access to preserved/production-like datasets in scope).
