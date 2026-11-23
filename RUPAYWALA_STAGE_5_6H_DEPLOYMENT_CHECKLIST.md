# RUPAYWALA STAGE 5.6H — Deployment Checklist

## Classification
**Overall: NOT READY**

Read-only audit. No production changes made. Use this checklist before any staging/production deployment.

## 1. Backend Deployability

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| Application entrypoint (`app.main:app`) | **PASS** | `app/main.py` | Keep stable; document run command. | Backend |
| Python dependency manifest | **PARTIAL** | `requirements.txt` pinned | Separate runtime/test deps; add lock/hash policy; add gunicorn if used. | Backend/DevOps |
| Container image | **FAIL** | No Dockerfile | Create hardened Dockerfile (non-root, slim base, healthcheck, no secrets). | DevOps |
| Local orchestration | **FAIL** | No docker-compose for prod-like stack | Add dev/staging compose; do not use for prod secrets. | DevOps |
| ASGI/worker config | **FAIL** | No gunicorn/uvicorn worker config | Define workers, timeouts, graceful shutdown, proxy headers. | DevOps |
| Startup command/process manager | **FAIL** | Not documented | Document and test `uvicorn/gunicorn` command, env, migrations, seed job. | DevOps |
| Shutdown/graceful drain | **FAIL** | No shutdown handler | Add lifespan shutdown, DB engine dispose, SIGTERM handling validation. | Backend/DevOps |
| Health/liveness/readiness | **PARTIAL** | `/health` exists only | Add `/live` and `/ready`; probe-compatible; avoid sensitive info. | Backend |
| Migration job | **PARTIAL** | Alembic present | Run Alembic as separate release/migration job with migrator role. | DevOps/DBA |
| Startup seeding | **PARTIAL** | `seed_reference_data` on startup | Move to controlled idempotent job or ensure safe multi-worker behavior; keep advisory lock. | Backend |
| Docs exposure | **FAIL** | `/docs`, `/redoc` always enabled | Disable in production or restrict behind auth/VPN. | Backend |

## 2. PostgreSQL Production Security

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| Owner/migrator/app role separation | **BLOCKED** | 5.6D/5.6E staging only | Apply approved role script in controlled prod window after backup/approval. | DBA |
| Runtime least privilege | **PARTIAL** | 5.6F removed runtime setval need | Deploy code, revoke sequence UPDATE exception, revalidate. | DBA/Backend |
| TLS (`sslmode`, server TLS) | **FAIL** | 5.6D saw `ssl=off` in validation container | Require TLS in transit; enforce `sslmode=verify-full` where possible. | DBA/DevOps |
| pg_hba hardening | **FAIL** | 5.6D trust/broad rules observed | Restrict to required hosts/roles/methods (SCRAM), no trust. | DBA |
| Network isolation/firewall | **FAIL** | No prod evidence | Private DB subnet, security groups, no public DB endpoint. | DevOps |
| Connection pooling | **NOT TESTED** | No pooler config | Evaluate PgBouncer/managed pooler; set app pool limits. | DBA/DevOps |
| DB monitoring/alerts | **FAIL** | No config | CPU, connections, locks, slow queries, replication/backup alerts. | DevOps/DBA |
| Backup/restore drill | **FAIL** | No prod evidence | Schedule automated backups and restore tests. | DBA |

## 3. Secrets and Environment Management

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| `.env` not in repo / secret hygiene | **FAIL** | `.env` present; `.gitignore` incomplete | Remove secrets from repo history if present; expand ignore; rotate secrets. | Security/Backend |
| `.env.example` (names only) | **FAIL** | Missing | Add template with required var names and descriptions only. | Backend |
| Secret manager integration | **FAIL** | No integration | Use platform secret manager/KMS/Vault; runtime injection. | DevOps/Security |
| Required secret startup validation | **PARTIAL** | DATABASE_URL/JWT/QUOTE/UPI required | Add prod guardrails for CORS wildcard, DEBUG/TESTING, docs enabled, missing integration secrets as needed. | Backend |
| Secret rotation procedure | **NOT TESTED** | No docs | Define rotation for JWT/DB/SMTP/SMS/OAuth/Maps/UPI/quote secrets. | Security |
| Environment separation | **FAIL** | Single config style | Separate dev/staging/prod env configs and deployment manifests. | DevOps |

## 4. Network and Application Security

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| CORS allowlist | **FAIL** | Default `*` | Explicit per-env allowlist; no wildcard in prod. | Backend |
| Trusted hosts | **FAIL** | Missing | Add TrustedHostMiddleware / proxy host validation. | Backend |
| HTTPS/HSTS | **FAIL** | Missing | Enforce TLS at edge; HSTS; redirect HTTP->HTTPS. | DevOps/Backend |
| Security headers | **FAIL** | Missing | CSP, XCTO, XFO/DENY or frame-ancestors, Referrer-Policy, Permissions-Policy. | Backend |
| Rate limiting (distributed) | **FAIL** | In-process only | Edge/WAF + Redis/shared limiter; trusted proxy config. | DevOps/Backend |
| AuthZ negative testing | **PARTIAL** | 5.6G4 basic checks passed | Complete payment ownership, admin/field negative matrix, IDOR tests. | QA/Security |
| Error leakage review | **PARTIAL** | Generic handlers present | Audit all routes for stack traces/internal IDs/sensitive data. | Backend/Security |
| Logging redaction | **NOT TESTED** | No formal policy | Redact tokens, OTPs, secrets, PII; structured logs. | Backend/Security |

## 5. File Storage and Uploads

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| Private object storage | **FAIL** | Local `/uploads` static mount | Use S3/GCS/Azure Blob/private volume with signed URLs. | DevOps/Backend |
| Upload authz/retrieval authz | **FAIL** | Public static serving | Authenticated download endpoint; owner/admin/field checks. | Backend |
| MIME/magic-byte/malware scanning | **PARTIAL** | Basic extension/magic-byte checks | Add robust MIME sniffing, AV scan, quarantine. | Backend/Security |
| File size/type limits | **PARTIAL** | 5MB + extension allowlist | Confirm business limits; enforce per endpoint; reject polyglots. | Backend |
| Retention/lifecycle | **FAIL** | No policy | Define retention, deletion, legal hold, backup. | Product/Security/DevOps |

## 6. External Integrations

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| Google Maps | **BLOCKED** | Not configured | Provision key, restrict by API/referrer/IP, enable billing/quotas, test errors/timeouts. | DevOps/Backend |
| Fast2SMS | **BLOCKED** | Not configured | Configure DLT/templates/sender; secret manager; delivery monitoring. | Backend/Ops |
| SMTP | **BLOCKED** | Not configured | Configure provider, SPF/DKIM/DMARC, TLS, bounce handling. | DevOps/Ops |
| Google OAuth | **BLOCKED** | Not configured | Configure client IDs/secrets/redirects; verify audience/email_verified in prod. | Backend/Ops |
| UPI/payment settlement | **BLOCKED** | Manual verification only | Define gateway/manual ops SOP; reconciliation; idempotency; webhook signatures; no live test in audit. | Product/Backend/Ops |

## 7. Backup and Disaster Recovery

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| Automated DB backups | **FAIL** | No evidence | Daily full + PITR/WAL; managed backup preferred. | DBA |
| Offsite/encrypted backups | **FAIL** | No evidence | Encrypt, separate account/region, immutable retention. | DBA/Security |
| Restore drills | **FAIL** | No evidence | Quarterly restore test into isolated env; document RTO achieved. | DBA |
| RPO/RTO defined | **FAIL** | No evidence | Business-approved RPO/RTO; architecture to meet them. | Product/DBA/DevOps |
| Migration rollback plan | **FAIL** | No runbook | Pre-migration backup, downgrade/forward-fix criteria, data rollback notes. | DBA/Backend |

## 8. CI/CD and Observability

| Item | Classification | Evidence | Required Action | Owner |
|---|---:|---|---|---|
| CI pipeline | **FAIL** | No workflows | Lint, type/test, SAST, dependency scan, secret scan, build image. | DevOps |
| CD pipeline | **FAIL** | No manifests | Staged deploy, migration gate, smoke tests, rollback. | DevOps |
| Central logs/metrics/traces | **FAIL** | No config | Structured logs, APM, dashboards, alerts, on-call. | DevOps/SRE |
| Security scanning | **NOT TESTED** | No evidence | Image scan, pip-audit, IaC scan, DAST in staging. | Security |

## 9. Release Gate

| Gate | Classification | Exit Criteria |
|---|---:|---|
| Staging readiness | **NOT READY** | All Critical/High findings remediated or risk-accepted with approval; staging deploy reproducible; migrations/roles/backup tested. |
| Production review | **NOT READY** | External integrations configured/tested, DR tested, security review passed, E2E/regression complete, monitoring active. |
| Production readiness | **NOT READY** | No claim until evidence exists for all critical controls and blockers. |