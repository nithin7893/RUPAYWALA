# RUPAYWALA STAGE 5.6H — Production Infrastructure Security and Deployment Readiness Audit

## Final Classification
**Overall: NOT READY**

No production readiness claim. This is a READ-ONLY audit; no production changes were made.

## Audit Scope / Safety
- Read-only inspection only. No DB/schema/role/permission/config/app changes made. No migrations executed. No deployment/DNS/infra changes. No real SMS/email/financial transactions. No secrets/credentials exposed.
- Preserved DBs not accessed/modified: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`, `rupaywala_g2seed_validation`, `rupaywala_g3pay_validation`.
- Evidence sources: `app/main.py`, `app/config.py`, `app/database.py`, `requirements.txt`, `alembic.ini`, `alembic/env.py`, `.gitignore`, `app/utils/*`, `app/services/*`, Stage 5.6D/5.6E/5.6F/5.6G1-5.6G4 reports, repo root listing.

## 1. Current Architecture (Observed)

| Component | Observed State | Evidence |
|---|---|---|
| Backend framework | FastAPI app, `app.main:app`, version 2.0.0 | `app/main.py` |
| ASGI server | `uvicorn==0.41.0` in requirements; no gunicorn/uvicorn config files | `requirements.txt`, root listing |
| Database | PostgreSQL via SQLAlchemy 2.0 + psycopg2-binary; `DATABASE_URL` required | `app/config.py`, `app/database.py`, `requirements.txt` |
| Migrations | Alembic configured; `alembic/env.py` loads URL from `app.config`; `transaction_per_migration=True` | `alembic.ini`, `alembic/env.py` |
| Auth | JWT HS256 (`python-jose`), bearer auth, token_version invalidation, DB user lookup per request | `app/utils/jwt_handler.py`, `app/utils/dependencies.py`, `app/config.py` |
| Passwords | bcrypt/passlib, min 8 chars, letters+numbers required | `app/utils/security.py` |
| Rate limiting | In-process memory buckets by IP/X-Forwarded-For first hop | `app/utils/rate_limit.py` |
| Uploads | Local filesystem under `UPLOAD_DIR` (default `uploads`), mounted publicly at `/uploads` via StaticFiles | `app/main.py`, `app/utils/upload_service.py`, `app/config.py` |
| External integrations | Google Maps (Google-only active), Fast2SMS, SMTP, Google OAuth, UPI manual verification | `app/config.py`, `app/services/*`, `app/main.py` |
| Health endpoint | `GET /health` checks DB with `SELECT count(users.id)` and reports integration config flags | `app/main.py` |
| Docs | `/docs`, `/redoc` always enabled | `app/main.py` |
| CORS | Configured from env; default `*`; credentials disabled when `*` | `app/config.py`, `app/main.py` |
| Startup | Skips schema create/seed in TESTING; `create_all` only when DEBUG; seeds reference data on startup otherwise | `app/main.py` |
| Shutdown | No explicit shutdown handler observed | `app/main.py` |
| Docker/CI/CD | No Dockerfile, docker-compose, CI workflow, Procfile, deployment manifests found | root/glob inspection |
| .env handling | `.env` loaded by python-dotenv; `.env` in gitignore; no `.env.example` found | `app/config.py`, `.gitignore`, root listing |

## 2. Production Architecture Recommendation (Target)

| Area | Recommendation | Classification |
|---|---|---|
| App runtime | Run FastAPI behind managed reverse proxy/load balancer; use uvicorn workers under gunicorn/uvicorn worker process manager or equivalent; separate web and migration jobs | **NOT READY** |
| Database roles | Use `rupaywala_owner` (NOLOGIN), `rupaywala_migrator` (LOGIN, migration-only), `rupaywala_app` (LOGIN, least privilege) per 5.6D/5.6E | **PARTIALLY COMPLETE** (staging-validated, not production-applied) |
| Migration execution | Run Alembic in controlled release step as migrator/owner role with `PGOPTIONS='-c role=rupaywala_owner'`; never as app runtime | **BLOCKED** (not production-executed) |
| Secrets | External secret manager / platform secrets; no `.env` in image/repo; startup fail-fast for required secrets | **FAIL** |
| File storage | Private object storage (S3/GCS/Azure Blob or equivalent) with signed URLs/authz checks; no public static mount for sensitive uploads | **FAIL** |
| Network | TLS everywhere, WAF/rate limiting at edge, private DB network, restricted pg_hba, no public DB | **NOT TESTED / FAIL** |
| Observability | Centralized structured logs, metrics, tracing, alerting, Sentry/OTel equivalent; health/readiness/liveness probes | **FAIL** |

## 3. Requirement Classification Summary

| # | Requirement | Classification | Evidence / Notes |
|---:|---|---:|---|
| 1 | Backend deployability | **FAIL** | No Dockerfile/compose/CI/deploy manifests; no gunicorn/worker config; no production startup contract documented; docs always on; public uploads. |
| 2 | PostgreSQL production security | **BLOCKED** | 5.6D/5.6E staging evidence exists; production roles/TLS/pg_hba/network/backup/monitoring not applied/validated. |
| 3 | Secrets and environment management | **FAIL** | `.env` present in repo root; no `.env.example`; `.gitignore` incomplete; some required secrets fail-fast, others have unsafe defaults/optional behavior. |
| 4 | Network and application security | **FAIL** | No TrustedHost/HTTPS enforcement/security headers; docs exposed; in-process rate limit only; public upload mount; CORS default `*`. |
| 5 | File storage and uploads | **FAIL** | Local static `/uploads` publicly served; no auth on retrieval; no object storage; backups/retention undefined. |
| 6 | External integrations production readiness | **BLOCKED** | Maps/SMS/SMTP/Google OAuth not configured in validated env; UPI manual only; no live settlement/reconciliation evidence. |
| 7 | Backup and disaster recovery | **FAIL** | No documented/scheduled backup, restore test, encryption, offsite, RPO/RTO, rollback procedure evidence. |
| 8 | Deployment platform assessment | **FAIL** | Missing container/CI/CD/IaC/deployment manifests; no platform evidence. |
| 9 | Existing Stage 5.6G-4 blockers carried forward | **FAIL** | All unresolved G4 blockers remain unresolved. |

## 4. Backend Deployability

| Check | Classification | Evidence | Notes |
|---|---:|---|---|
| App entrypoint | **PASS** | `app/main.py` exposes `app = FastAPI(...)` | Usable with uvicorn `app.main:app`. |
| Required runtime deps | **PARTIAL** | `requirements.txt` pinned | Includes uvicorn, psycopg2-binary, alembic; no gunicorn; includes test deps in same file. |
| Environment variable handling | **PARTIAL** | `app/config.py` | Required: `DATABASE_URL`, `JWT_SECRET_KEY`, `QUOTE_SIGNING_SECRET`, `UPI_ID`. Many integration secrets optional with empty defaults. |
| DB connection requirements | **PARTIAL** | `app/database.py` | `pool_pre_ping=True`; no pool size/overflow/recycle/timeout/SSL mode config. |
| Worker configuration | **FAIL** | No gunicorn/procfile/worker config | Multi-worker startup seeding/rate limiting need review. |
| Startup behavior | **PARTIAL** | `app/main.py` | TESTING skips create_all/seed; DEBUG create_all; non-TESTING seeds reference data. Seed uses advisory lock in plan catalog (good) but startup still does DB work. |
| Shutdown behavior | **FAIL** | No `@app.on_event("shutdown")`/lifespan cleanup observed | DB engine disposal/background resources not explicitly managed. |
| Health endpoint | **PARTIAL** | `/health` in `app/main.py` | Checks DB and integration config flags; no readiness/liveness split; no explicit timeout; exposes config state. |
| Readiness endpoint | **FAIL** | Not found | No `/ready`/liveness/readiness separation. |
| Graceful shutdown | **NOT TESTED** | No config observed | Depends on deployment/process manager. |
| Logging/error handling | **PARTIAL** | `app/main.py`, logging.basicConfig | Generic 500 handler; logs exceptions; no structured JSON logging/central sink/correlation IDs/redaction policy evidence. |
| Background tasks | **PASS** | No scheduler/background worker observed | Reduces complexity; long-running jobs would need separate design. |
| Static/upload serving | **FAIL** | `app.mount("/uploads", StaticFiles(...))` | Public unauthenticated file serving; not production-safe for sensitive docs. |
| Alembic deployability | **PARTIAL** | `alembic.ini`, `alembic/env.py` | URL injected from app config; no production migration runbook/CI gate evidenced. |

## 5. PostgreSQL Production Security (Carry-forward 5.6D/5.6E/5.6F)

| Check | Classification | Evidence | Notes |
|---|---:|---|---|
| Role separation model (`owner/migrator/app`) | **PARTIALLY COMPLETE** | 5.6D/5.6E reports | Validated in disposable staging DB only; not applied to production. |
| Least-privilege runtime | **PARTIALLY COMPLETE** | 5.6E/5.6F reports | 5.6F removed runtime `setval()` and verified app can seed without sequence UPDATE in disposable DB; production role revoke/revalidation pending. |
| Ownership separation | **PARTIALLY COMPLETE** | 5.6E report | Staging transfer passed; production not executed. |
| Migration execution procedure | **PARTIAL** | 5.6E report | PGOPTIONS `-c role=rupaywala_owner` validated in staging; no approved production runbook/window evidence. |
| Default privileges / post-migration audit | **FAIL** | 5.6E B-004 | Conservative defaults set in staging; explicit post-migration grant reconciliation required. |
| TLS requirement | **FAIL** | 5.6D report | Validation container showed `ssl=off`; production TLS not validated. |
| pg_hba hardening | **FAIL** | 5.6D report | Trust rules and broad host rules observed in validation container; production hardening not validated. |
| Network exposure/firewall | **FAIL** | 5.6D report | `listen_addresses=*` in inspected container; production network restrictions not evidenced. |
| Connection pooling | **NOT TESTED** | No PgBouncer/pooler config found | App has SQLAlchemy engine defaults; no external pooler evidence. |
| Backup scheduling/restore | **FAIL** | No backup infra evidence | 5.6D noted backup presence for validation dump only; no production schedule/restore test. |
| DB monitoring | **FAIL** | No monitoring config | No metrics/alerts/slow query/log shipping evidence. |

## 6. Secrets and Environment Management

| Check | Classification | Evidence | Notes |
|---|---:|---|---|
| `.env` excluded from git | **PARTIAL** | `.gitignore` contains `.env` | `.env` file exists in repo root; `.env.*`, `.env.example` patterns and secrets/key files not comprehensively ignored. |
| `.env.example`/secret template | **FAIL** | Root/glob inspection | No `.env.example`/sample found. |
| Secret values in source control | **NOT TESTED / RISK** | `.env` present, `database_backups/` present | Audit did not inspect secret values; presence of env/backup artifacts is a governance risk. |
| Startup rejects missing critical secrets | **PARTIAL** | `app/config.py` | Required: `DATABASE_URL`, `JWT_SECRET_KEY`, `QUOTE_SIGNING_SECRET`, `UPI_ID`. Missing required values raise at import/startup. |
| Unsafe dev defaults | **FAIL** | `app/config.py` | `CORS_ALLOWED_ORIGINS` default `*`; `DEBUG` default False (ok) but no env separation; `UPLOAD_DIR` local default; optional integrations default empty and may degrade silently. |
| Debug settings accidental enablement | **PARTIAL** | `app/config.py`, `main.py` | `DEBUG` defaults False; `OTP_DEBUG_LOG` defaults False; `TESTING` can alter startup behavior and must never be enabled in prod. |
| Secret manager recommendation | **FAIL** | No secret manager integration | Recommend platform secret manager/KMS/Vault; inject env vars at runtime; rotate DB/JWT/quote/SMTP/SMS/OAuth/Maps/UPI secrets. |
| Environment-specific config separation | **FAIL** | Single `.env`/config module | No `prod/staging/dev` config files/manifests. |

## 7. Network and Application Security

| Check | Classification | Evidence | Severity | Notes |
|---|---:|---|---:|---|
| CORS | **FAIL** | `app/main.py`, `app/config.py` | High | Default `CORS_ALLOWED_ORIGINS=*`; wildcard is unsafe for production. Credentials disabled with wildcard but explicit allowlist required. |
| Trusted hosts | **FAIL** | No middleware found | Medium | No `TrustedHostMiddleware` / host allowlist. |
| HTTPS enforcement | **FAIL** | No HTTPSRedirect/security middleware | High | Relies entirely on external infra; no app-level HSTS/redirect policy. |
| Security headers | **FAIL** | No middleware found | Medium | No CSP/HSTS/X-Content-Type-Options/X-Frame-Options/Referrer-Policy. |
| Rate limiting | **PARTIAL** | `app/utils/rate_limit.py` | High | In-process only; not shared across workers/instances; trusts first `X-Forwarded-For` value. |
| Authentication | **PASS (observed)** | `app/utils/dependencies.py`, 5.6G4 | Medium | Bearer token + DB user lookup + token_version invalidation. |
| Token expiry | **PASS (observed)** | `app/config.py`, jwt handler | Low | `ACCESS_TOKEN_EXPIRE_MINUTES` configurable (default 60). |
| Upload authorization | **FAIL** | `app/main.py`, `upload_service.py` | High | `/uploads` static mount is publicly accessible; retrieval auth not enforced. |
| Error response leakage | **PARTIAL** | `app/main.py` exception handlers | Medium | Generic 500/409 handlers present; not exhaustively audited across all routes. |
| API docs exposure | **FAIL** | `app/main.py` | Medium | `/docs` and `/redoc` always enabled. |
| Admin endpoint protection | **PARTIAL** | route deps, 5.6G4 | Medium | Basic authz observed; needs exhaustive negative tests/rate limits/audit logging. |
| Sensitive logging | **PARTIAL** | grep/review | Medium | No obvious secret value logging in reviewed files; logger.exception may include stack traces in logs; formal redaction policy absent. |

## 8. File Storage and Uploads

| Check | Classification | Evidence | Notes |
|---|---:|---|---|
| Storage architecture | **FAIL** | `app/main.py`, `upload_service.py` | Local filesystem only; static mount `/uploads`. |
| File validation | **PARTIAL** | `upload_service.py` | Extension allowlist, random filename, size limit, magic-byte/signature check for jpg/png/webp/pdf. |
| File size restrictions | **PASS** | `config.MAX_UPLOAD_BYTES` default 5MB, enforced | Enforced before write. |
| Magic-byte checks | **PARTIAL** | `upload_service.py` | Basic signatures checked; not a full content scanner/MIME sniffing library. |
| Unauthorized access prevention | **FAIL** | `app/main.py` | Uploaded files served publicly by static mount. |
| Public exposure of uploaded documents | **FAIL** | `/uploads` mount | Any stored file path is retrievable without auth. |
| Backup/retention | **FAIL** | No policy/config | No lifecycle/retention/offsite backup. |
| Production scalability | **FAIL** | Local disk | Not suitable for multi-instance/stateless deployment. |

## 9. External Integrations

| Integration | Classification | Evidence | Production Requirements |
|---|---:|---|---|
| Google Maps | **BLOCKED** | 5.6G4, `/health` reports not configured | API key in secret manager, API restrictions, billing/quota alerts, Places/Routes enablement, timeout/retry/circuit breaker, error monitoring. |
| Fast2SMS | **BLOCKED** | 5.6G4, `sms_service.py` | DLT/template approval, sender ID, credentials in secret manager, delivery/failure webhooks or reconciliation, rate limiting, opt-out/compliance. |
| SMTP | **BLOCKED** | 5.6G4, `email_service.py` | Provider credentials/app password in secret manager, SPF/DKIM/DMARC, TLS, bounce handling, rate limits. |
| Google OAuth | **BLOCKED** | 5.6G4, `google_auth_service.py` | OAuth consent/config, client ID/secret, redirect URIs, token audience validation, key rotation/cache invalidation strategy. |
| UPI/payment verification | **BLOCKED** | 5.6G4, `payment_service.py`, config | Current flow is manual UTR/admin verification; live gateway settlement/reconciliation not tested. Need gateway contract, webhook signature verification, reconciliation, idempotency, dispute/timeout handling. |

## 10. Backup and Disaster Recovery

| Item | Classification | Recommendation |
|---|---:|---|
| PostgreSQL backup schedule | **FAIL** | Daily full + WAL/PITR or managed equivalent; define backup window and ownership. |
| Retention | **FAIL** | Define retention (e.g., 30/90 days) per compliance/business needs. |
| Encryption | **FAIL** | Encrypt backups at rest and in transit; KMS-managed keys. |
| Off-site backup | **FAIL** | Store backups in separate region/account; immutable/object-lock where possible. |
| Restore testing | **FAIL** | Quarterly restore drills into isolated env with documented results. |
| RPO | **FAIL** | Define and approve RPO (business decision); implement PITR if low RPO required. |
| RTO | **FAIL** | Define and approve RTO; test failover/restore runbook. |
| Migration rollback strategy | **FAIL** | Forward-fix preferred; pre-migration backup, Alembic downgrade testing where safe, data migration reversibility notes. |

## 11. Deployment Platform Assessment

| Item | Classification | Evidence | Gap |
|---|---:|---|---|
| FastAPI backend containerization | **FAIL** | No Dockerfile | Need production Dockerfile, non-root user, minimal image, healthcheck. |
| PostgreSQL deployment | **NOT TESTED** | No infra manifests | Managed Postgres recommended; private network, TLS, backups. |
| Flutter web frontend | **NOT APPLICABLE / NOT TESTED** | Not in backend repo | Deployment pipeline/CDN/SSL needed if applicable. |
| Flutter Android app | **NOT APPLICABLE / NOT TESTED** | Not in backend repo | Play release pipeline/signing/secrets needed. |
| Uploaded document storage | **FAIL** | Local static mount | Move to object storage/CDN with signed access. |
| Domain/SSL | **NOT TESTED** | No infra evidence | Need domain, TLS certs, HSTS, redirect policy. |
| Monitoring/logs | **FAIL** | No config | Need APM, logs, metrics, alerts, uptime checks. |
| CI/CD | **FAIL** | No `.github/workflows`, no pipeline files | Need lint/test/build/migrate/deploy gates with secret scanning. |

## 12. Existing Application Blockers (Carried Forward from 5.6G-4)

| Blocker | Classification | Status |
|---|---:|---|
| File upload validation not tested | **NOT TESTED** | Unresolved (RB-G4-008). |
| Payment ownership negative HTTP test not completed | **NOT TESTED** | Unresolved (RB-G4-002/related). |
| Concurrent HTTP payment retries not completed | **NOT TESTED** | Unresolved (RB-G4-002). |
| Payment verification and extra-charge HTTP workflows incomplete | **PARTIAL** | Unresolved (RB-G4-002). |
| Subscription activation and family-member HTTP tests incomplete | **NOT TESTED** | Unresolved (RB-G4-002/RB-G4-011). |
| Field visit start/completion HTTP tests incomplete | **NOT TESTED** | Unresolved (RB-G4-002). |
| Rate limiting not exhaustively tested | **NOT TESTED** | Unresolved (RB-G4-012). |
| Fast2SMS, SMTP, Google OAuth not configured | **BLOCKED** | Unresolved (RB-G4-004/005/006). |
| Google Maps not configured | **BLOCKED** | Unresolved (RB-G4-003). |
| Live UPI settlement not tested | **NOT TESTED** | Unresolved (RB-G4-007). |
| Full pytest suite isolation not established | **BLOCKED** | Unresolved (RB-G4-009); `tests/conftest.py` destructive. |
| Payment idempotency DB-level constraint design unresolved | **OPEN** | RB-G4-001 / NEW-56G1-001; proposed full unique index incompatible as-is with extra-charge terminal retry semantics. |

## 13. Overall Assessment

**Overall: NOT READY**

Rupaywala has meaningful staging validation progress (5.6D-5.6G4), but production infrastructure, security hardening, deployment packaging, secrets management, file storage, DR, and several application/integration validations remain incomplete or blocked. No production readiness claim is made.
