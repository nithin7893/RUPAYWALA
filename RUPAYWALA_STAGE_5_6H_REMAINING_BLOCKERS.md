# RUPAYWALA STAGE 5.6H — Remaining Blockers

## Final Classification
**Overall: NOT READY**

Read-only audit. No production changes made. No production readiness claim.

## Requirement Classification (Stage 5.6H)

| Requirement | Classification | Rationale |
|---|---:|---|
| Backend deployment architecture assessed | **FAIL** | App runnable in dev, but missing production deployment packaging/config (Docker/worker/shutdown/readiness/docs hardening). |
| PostgreSQL production security assessed | **BLOCKED** | 5.6D/5.6E/5.6F provide staging evidence; production role/TLS/pg_hba/network/pooling/backup/monitoring not applied or validated. |
| Secrets and environment management assessed | **FAIL** | Missing `.env.example`, incomplete ignore rules, env/backup artifacts present in repo root, no secret manager, unsafe defaults. |
| Network and application security assessed | **FAIL** | CORS wildcard default, no TrustedHost/HTTPS/security headers, docs exposed, in-process rate limit, public upload mount. |
| File storage and uploads assessed | **FAIL** | Local public static upload serving; no retrieval authz; no object storage/retention/DR. |
| External integrations assessed | **BLOCKED** | Maps/SMS/SMTP/OAuth not configured; UPI manual only; no live settlement/reconciliation evidence. |
| Backup and disaster recovery assessed | **FAIL** | No schedule, encryption, offsite, restore testing, RPO/RTO, rollback runbook evidence. |
| Deployment platform assessed | **FAIL** | No Docker/CI/CD/IaC/deployment manifests/monitoring stack evidence. |
| Existing Stage 5.6G-4 blockers carried forward | **FAIL** | Unresolved blockers remain open/blocking. |

## Critical / High Blockers

| ID | Severity | Classification | Blocker | Evidence | Exit Criteria |
|---|---|---:|---|---|---|
| B56H-001 | Critical | **FAIL** | Public upload exposure: `/uploads` static files served without auth | `app/main.py`, `app/utils/upload_service.py` | Private storage + authenticated/signed retrieval; authz tests pass. |
| B56H-002 | Critical | **FAIL** | Secrets/config governance unsafe for production | `.gitignore`, root contains `.env`, `database_backups/`; no `.env.example` | Secret manager, env template names-only, ignore hardening, secret rotation, repo hygiene. |
| B56H-003 | High | **FAIL** | Missing production deployment packaging and runtime hardening | No Dockerfile/compose/CI/Procfile/gunicorn config | Reproducible container build, worker config, health/readiness/liveness, shutdown, env separation. |
| B56H-004 | High | **BLOCKED** | PostgreSQL production hardening not applied/validated | 5.6D/5.6E/5.6F reports | Approved prod runbook executed: roles, TLS, pg_hba, network isolation, pooling, monitoring. |
| B56H-005 | High | **FAIL** | No backup/DR program evidenced | No backup/restore/RPO/RTO docs or infra | Automated encrypted backups, offsite, restore drills, defined RPO/RTO, rollback runbook. |
| B56H-006 | High | **FAIL** | Network/app security defaults insufficient | CORS default `*`, docs enabled, no TrustedHost/HTTPS/security headers, in-process rate limit | Hardened middleware/config, docs disabled/gated, distributed rate limiting, security tests. |
| B56H-007 | High | **OPEN** | Payment idempotency DB-level constraint unresolved | RB-G4-001 / NEW-56G1-001, 5.6G3 | Semantic-scope redesign preserving extra-charge terminal retries; target-data preflight; safe migration. |
| B56H-008 | High | **BLOCKED** | External integrations not production-validated | RB-G4-003..007, 5.6G4 | Configured credentials/webhooks/templates/restrictions; safe integration tests; UPI reconciliation/settlement process defined. |

## Medium / Operational Blockers

| ID | Severity | Classification | Blocker | Evidence | Exit Criteria |
|---|---|---:|---|---|---|
| B56H-009 | Medium | **PARTIAL** | Restricted-role HTTP E2E coverage incomplete | RB-G4-002 | Complete missing HTTP cases: OTP, quote expiry/signature tamper, payment verify/duplicate clean retest, concurrent retries, extra-charge retry, subscription activation/balance/family limits, admin branch assignment, field visit start/complete/status transitions. |
| B56H-010 | Medium | **NOT TESTED** | File upload validation/security tests incomplete | RB-G4-008 | Allowed formats, MIME, magic-byte, oversize, unauthorized upload/retrieval, path/storage isolation tests pass. |
| B56H-011 | Medium | **NOT TESTED** | Rate limiting and security negative tests incomplete | RB-G4-012 | Exhaustive rate-limit, authz, IDOR/payment ownership, input validation, error leakage tests. |
| B56H-012 | Medium | **BLOCKED** | Full pytest suite isolation unsafe | RB-G4-009, `tests/conftest.py` | Refactor to safe disposable DB/transactional isolation; CI guardrails; full suite green. |
| B56H-013 | Medium | **PARTIAL** | Observability/operational readiness missing | no CI/CD/logging/metrics/alerts | Central logs, metrics, traces, alerts, runbooks, SLOs, incident process. |
| B56H-014 | Medium | **PARTIAL** | DB/app lifecycle hardening incomplete | `database.py`, `main.py` | Pool/timeout/SSL config, startup/shutdown lifecycle, migration job separation. |

## Exact Remediation Order

1. **Containment/Security defaults**: disable public `/uploads`; disable/gate docs in prod; enforce CORS allowlist; add TrustedHost/HTTPS/security headers; move secrets to secret manager; add `.env.example` and `.gitignore` hardening; rotate exposed/at-risk secrets.
2. **Data/storage hardening**: implement private object storage + authenticated retrieval; upload malware/MIME validation; define retention.
3. **PostgreSQL production hardening**: apply approved owner/migrator/app roles in controlled window; enforce TLS, strict pg_hba, private network; configure pooler/timeouts; remove app sequence UPDATE exception after 5.6F deployment validation.
4. **Payment idempotency redesign**: authorized target-data duplicate preflight; redesign extra-charge/subscription idempotency scopes; safe Alembic migration with preflight abort; regression tests.
5. **Integration readiness**: configure Maps/SMS/SMTP/OAuth/UPI in staging with secrets and restrictions; validate failure handling, webhooks/reconciliation as applicable.
6. **E2E/security validation**: complete restricted-role HTTP E2E gaps, file upload security tests, rate-limit/IDOR/payment ownership tests, clean payment verify/duplicate/concurrent/extra-charge tests.
7. **Test/CI/CD readiness**: fix pytest isolation; add CI gates (tests, lint, SAST, dependency/secret/image scans); build reproducible container.
8. **DR/operations**: backups/PITR, offsite encryption, restore drills, RPO/RTO, monitoring/alerting/runbooks, rollback procedure.
9. **Staging release review**: deploy to staging with production-like controls; obtain evidence for all critical/high blockers before any production review.

## Final Statement
**Stage 5.6H Overall: NOT READY.** No production readiness claim.