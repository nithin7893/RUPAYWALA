# RUPAYWALA STAGE 5.6H — Security Findings

## Classification
**Overall Security Posture: NOT READY**

Read-only audit. No production changes made. No credentials/secrets exposed.

## Findings Summary

| ID | Severity | Area | Classification | Finding | Evidence | Remediation |
|---|---|---|---:|---|---|---|
| H-SEC-001 | Critical | File storage / access control | **FAIL** | Uploaded files are served publicly via `/uploads` StaticFiles mount with no authentication/authorization. | `app/main.py` mounts `StaticFiles(directory=str(_upload_path))` at `/uploads`; `upload_service.save_upload` stores files under local `UPLOAD_DIR`. | Move uploads to private object storage; serve via authenticated endpoints or short-lived signed URLs; enforce ownership/role checks. |
| H-SEC-002 | Critical | Secrets/config governance | **FAIL** | No `.env.example`; `.gitignore` ignores `.env` but not `.env.*`, `uploads/`, `database_backups/`, key/cert patterns. `.env` and `database_backups/` exist in repo root. | `.gitignore`, root listing. | Add `.env.example` with names only; expand `.gitignore`; move secrets to secret manager; ensure backups/env artifacts never committed. |
| H-SEC-003 | High | CORS | **FAIL** | CORS defaults to wildcard `*`; credentials disabled only as side effect. Production allowlist not enforced by default. | `app/config.py`: `_cors_raw = _get("CORS_ALLOWED_ORIGINS", "*")`, `ALLOW_CREDENTIALS = _cors_raw != "*"`. | Require explicit `CORS_ALLOWED_ORIGINS` in prod; reject wildcard in production startup; document allowed origins per env. |
| H-SEC-004 | High | Network hardening | **FAIL** | No TrustedHost middleware, HTTPS redirect/enforcement, or security headers (HSTS/CSP/XCTO/XFO/Referrer-Policy). | `app/main.py` has CORS only; grep found no TrustedHost/HTTPS/security header middleware. | Add TrustedHostMiddleware, proxy-aware HTTPS/HSTS, security headers; enforce TLS at edge and app config. |
| H-SEC-005 | High | API exposure | **FAIL** | Swagger `/docs` and ReDoc `/redoc` always enabled. | `app/main.py`: `docs_url="/docs", redoc_url="/redoc"`. | Disable docs in production or gate behind admin/VPN/auth; expose only in non-prod. |
| H-SEC-006 | High | Rate limiting | **PARTIAL** | In-process rate limiter only; not shared across instances/workers; uses first `X-Forwarded-For` hop. | `app/utils/rate_limit.py` uses in-memory dict+lock; `_client_key` takes first forwarded IP. | Use Redis/shared limiter at app or edge/WAF; trusted proxy handling; per-user/per-route policies; exhaustive testing. |
| H-SEC-007 | High | PostgreSQL prod hardening | **BLOCKED** | Staging role separation validated (5.6D/5.6E/5.6F) but production roles/TLS/pg_hba/network/firewall/pooling/monitoring not applied/validated. | 5.6D/5.6E/5.6F reports. | Execute approved production hardening runbook: owner/migrator/app roles, TLS, strict pg_hba, private network, pooling, monitoring, backup/restore tests. |
| H-SEC-008 | High | Deployment/infra missing | **FAIL** | No Dockerfile, docker-compose, CI/CD, IaC, or deployment manifests. | Root/glob inspection. | Create hardened container build, CI pipeline with security gates, deployment manifests, environment separation. |
| H-SEC-009 | Medium | DB connection hardening | **PARTIAL** | SQLAlchemy engine uses `pool_pre_ping=True` but no explicit pool size, recycle, timeout, statement timeout, or SSL mode enforcement. | `app/database.py`. | Configure pool sizing/timeouts; enforce `sslmode=require/verify-full` in prod; set statement/lock timeouts as appropriate. |
| H-SEC-010 | Medium | Startup/shutdown lifecycle | **PARTIAL** | Startup seeds reference data on every non-TESTING boot; DEBUG may `create_all`. No explicit shutdown handler. | `app/main.py` startup/shutdown absence. | Move seeding/migrations to controlled job; disable create_all outside dev; add lifespan shutdown for engine/clients; ensure idempotent multi-worker startup. |
| H-SEC-011 | Medium | Logging/observability | **PARTIAL** | Basic logging and generic exception handlers exist; no structured logs, correlation IDs, redaction policy, or central monitoring evidence. | `app/main.py` logging.basicConfig, exception handlers. | Structured JSON logging, request IDs, Sentry/OTel, redact sensitive fields, alerting dashboards. |
| H-SEC-012 | Medium | Health/readiness probes | **PARTIAL** | `/health` checks DB and reports integration config; no liveness/readiness split, no dependency timeout budget, exposes config state. | `app/main.py`. | Add `/live` and `/ready`; keep health minimal/authz-aware; avoid exposing sensitive config details publicly. |
| H-SEC-013 | Medium | Auth token model | **PARTIAL** | JWT HS256 with token_version invalidation is good; no refresh-token rotation/revocation store beyond version; logout invalidation relies on token_version bump behavior. | `app/utils/jwt_handler.py`, `dependencies.py`. | Consider refresh tokens/rotation for production UX/security; ensure logout bumps token_version; add audit logging for auth events. |
| H-SEC-014 | Medium | Input/file validation completeness | **PARTIAL** | Upload service checks extension, size, basic magic bytes, random names. No malware scan, no content-type enforcement beyond basic checks, no retrieval auth. | `app/utils/upload_service.py`. | Add MIME sniffing library, antivirus/malware scanning in pipeline, strict content policies, private storage. |
| H-SEC-015 | Medium | Test suite safety | **BLOCKED** | `tests/conftest.py` is destructive (drops/recreates public schema for `rupaywala_test`); full pytest isolation not proven. | 5.6G4 report, checkpoint. | Refactor tests to transactional/isolated disposable DB fixtures; enforce CI guardrails preventing destructive runs against non-test DB. |
| H-SEC-016 | Medium | Payment idempotency DB constraint | **OPEN** | No full all-status DB unique index for payment idempotency; proposed index incompatible as-is with extra-charge terminal retry semantics. | 5.6G3/5.6G4 reports, `NEW-56G1-001`. | Redesign constraint by semantic scope/retry-aware key; target-data duplicate preflight; safe Alembic migration. |
| H-SEC-017 | Low | Dependency hygiene | **NOT TESTED** | Pinned requirements exist; no vulnerability scan/SBOM/dependency update policy evidenced. | `requirements.txt`. | Add `pip-audit`/Dependabot/Renovate, SBOM, regular patch cadence. |
| H-SEC-018 | Low | Docs/debug endpoints in production | **FAIL** | `/docs` and `/redoc` always on; debug flag exists. | `app/main.py`, `app/config.py`. | Disable docs by env; ensure DEBUG false in prod; startup guard for unsafe prod config. |

## Carried-Forward Stage 5.6G-4 Security/App Blockers

| Blocker | Classification | Notes |
|---|---:|---|
| RB-G4-001 Payment DB idempotency constraint design | **OPEN** | Unresolved. |
| RB-G4-002 Full restricted-role HTTP E2E coverage | **PARTIAL** | Unresolved gaps remain. |
| RB-G4-008 File upload validation/auth/retrieval | **NOT TESTED** | Critical before production. |
| RB-G4-012 Rate limiting / security hardening exhaustive tests | **NOT TESTED** | Unresolved. |
| Payment ownership negative HTTP test | **NOT TESTED** | Unresolved. |
| Concurrent HTTP payment retries / extra-charge HTTP workflows | **NOT TESTED / PARTIAL** | Unresolved. |

## Security Recommendation Order
1. Block public `/uploads` exposure; move to private storage with authz/signed URLs.
2. Fix secrets/config governance: `.env.example`, `.gitignore` hardening, secret manager, startup guards.
3. Harden network/app defaults: CORS allowlist, disable docs in prod, TrustedHost/HTTPS/security headers, shared rate limiting.
4. Complete PostgreSQL production hardening: roles, TLS, pg_hba, network isolation, pooling, monitoring, backup/restore.
5. Resolve payment idempotency DB design with target-data preflight and safe migration.
6. Complete missing HTTP E2E/security/upload/integration/pytest isolation validations.
7. Add CI/CD, containerization, observability, DR runbooks, and restore drills.