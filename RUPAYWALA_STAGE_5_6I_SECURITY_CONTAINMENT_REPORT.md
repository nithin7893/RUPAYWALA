# RUPAYWALA STAGE 5.6I — Critical Security Containment Report

## Stage Status
**PARTIALLY COMPLETE (containment implemented with isolated test evidence; not production-ready)**

This is an implementation stage, not a production deployment. No production readiness claim.

## Scope / Safety
- Inspected existing implementation before changes.
- No PostgreSQL DB/role/schema changes. No `rupaywala_ori` access/modification. No secrets printed/exposed. No credential rotation. No commit/push. No deletion of `.env`, backups, uploads, or user data.
- Existing destructive pytest setup (`tests/conftest.py`) was **not** run.

## Files Changed
| File | Change Summary |
|---|---|
| `app/config.py` | Added explicit runtime env (`ENVIRONMENT`, `IS_PRODUCTION`), docs exposure flag, hardened CORS defaults/validation, trusted host/proxy/HTTPS/HSTS/CSP config, production startup validation. |
| `app/main.py` | Disabled docs/openapi by default via config; added TrustedHost, HTTPS enforcement, security headers middleware; removed public `/uploads` StaticFiles mount; added authenticated/authorized upload retrieval endpoint. |
| `.gitignore` | Added `.env.*`, key/cert patterns, uploads/backups/log/db artifact ignores; kept `.env.example` tracked. |
| `.env.example` | Added names/placeholders-only environment template. |
| `tests/test_stage56i_security_containment.py` | New isolated security containment tests (self-contained env+SQLite temp DB, no conftest dependency). |

## Exact Changes Made

### 1) Public upload containment (PASS)
- **Removed** public `StaticFiles` mount at `/uploads` in `app/main.py`.
- **Added** `GET /uploads/{file_path:path}` authenticated endpoint in `app/main.py`.
- **AuthN:** requires `get_current_user` (401 if unauthenticated).
- **AuthZ:** allows only admin, owning request user, or assigned field member for the `ServiceRequest` whose `proof_image_url` matches stored path; returns 404 for unauthorized/not-found to avoid enumeration.
- **Path safety:** normalizes slashes, strips leading `uploads/`, rejects empty/`.`/`..`/absolute segments, resolves path and enforces containment within `UPLOAD_DIR`.
- **File validation preserved:** `app/utils/upload_service.py` unchanged (extension allowlist, random name, size limit, magic-byte/signature checks, safe subdir).
- **API contract:** `proof_image_url` field still returned in existing responses; retrieval path shape `/uploads/...` preserved but now requires auth.

### 2) API documentation protection (PASS)
- `app/main.py` sets `docs_url`, `redoc_url`, `openapi_url` to `/docs,/redoc,/openapi.json` only when `EXPOSE_DOCS` is true; otherwise `None`.
- `app/config.py`: `EXPOSE_DOCS = _get_bool("EXPOSE_DOCS", not IS_PRODUCTION)`.
- Production startup validation rejects `EXPOSE_DOCS=true` in production.

### 3) CORS hardening (PASS)
- Removed wildcard default. `CORS_ALLOWED_ORIGINS` default: explicit localhost list in dev/test; empty in production (must be configured).
- Parses explicit comma-separated origins. Rejects `*` combined with other origins.
- `ALLOW_CREDENTIALS` false when wildcard; rejects wildcard+credentials.
- Production startup validation rejects missing/wildcard CORS.
- No production domains invented.

### 4) Host, HTTPS, and security headers (PASS with caveats)
- **TrustedHost:** `TrustedHostMiddleware` added with configured `TRUSTED_HOSTS`; dev default allows `localhost,127.0.0.1,testserver` when unset; production validation requires explicit non-wildcard hosts.
- **Forwarded headers:** no `ProxyHeadersMiddleware`; HTTPS logic only inspects `X-Forwarded-Proto` when `TRUST_PROXY_HEADERS=true` (explicit config). Redirect decision still enforces HTTPS scheme.
- **HTTPS enforcement:** configurable `HTTPS_REDIRECT_ENABLED` (default true in production, false otherwise); returns 307 redirect to HTTPS when not HTTPS.
- **Security headers:** `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, `Permissions-Policy`, configurable CSP. HSTS added only when `HSTS_ENABLED` and request is HTTPS (or trusted forwarded proto indicates HTTPS).
- **CSP caveat:** default CSP includes `unsafe-inline`/`unsafe-eval` and broad https/data/blob sources for Flutter web compatibility; operators should tighten per deployment.

### 5) Secrets and environment governance (PASS with operational follow-up)
- Added `.env.example` with variable names and safe placeholders only.
- Updated `.gitignore` for `.env.*` (keeping `.env.example`), key/cert patterns, `uploads/`, `database_backups/`, dumps/log/db artifacts.
- **Git tracking check:** `git ls-files -- .env .env.* *.pem *.key *.p12 *.pfx database_backups/* uploads/*` returned no tracked matches. `.env` exists in repo root but is ignored by `.gitignore`; sensitive values not inspected/printed.
- Production startup validation rejects: DEBUG true, TESTING true, EXPOSE_DOCS true, missing CORS, wildcard CORS, missing/wildcard TRUSTED_HOSTS, unsafe/short JWT_SECRET_KEY or QUOTE_SIGNING_SECRET.
- Validation errors never include secret values.
- Credential rotation not performed (separate authorized operational task).

## Findings Classification

| Finding | Classification | Evidence / Notes |
|---|---:|---|
| Unauthenticated `/uploads` StaticFiles exposure removed | **PASS** | `app/main.py` mount removed; auth endpoint added; isolated tests pass. |
| Authenticated document retrieval with ownership/admin/field assignment authz | **PASS** | `get_uploaded_document` checks owner/admin/assigned field member; tests pass. |
| Cross-user document access denied | **PASS** | Returns 404; isolated test pass. |
| Path traversal/arbitrary FS access prevented | **PASS** | Path normalization + resolve containment; isolated test pass. |
| File validation/size/supported formats preserved | **PASS** | `upload_service.py` unchanged; no regression observed in code path. |
| Docs/OpenAPI disabled by default in production | **PASS** | Config+main; prod test pass. |
| Docs configurable in development | **PASS** | Dev test pass. |
| Wildcard CORS removed as production default | **PASS** | Prod default empty; startup validation rejects; test pass. |
| Explicit CORS allowlist behavior | **PASS** | Isolated CORS test pass. |
| Wildcard CORS rejected in production / unsafe config rejected | **PASS** | Isolated tests pass. |
| TrustedHost protection configurable | **PASS** | Middleware + test pass. |
| HTTPS enforcement/reverse-proxy mechanism documented/configurable | **PASS** | `HTTPS_REDIRECT_ENABLED`, `TRUST_PROXY_HEADERS`; HSTS conditional. |
| Security headers added | **PASS** | Middleware + test pass. |
| `.env.example` added (names/placeholders only) | **PASS** | File created. |
| `.gitignore` updated for secrets/backups/uploads | **PASS** | Updated; `.env.example` kept trackable. |
| Sensitive files tracked by Git check | **PASS** | `git ls-files` returned no matching tracked sensitive files. |
| Production startup validation for essential config | **PASS** | Validation in `app/config.py`; tests pass. |
| Unsafe production defaults rejected | **PASS** | DEBUG/TESTING/EXPOSE_DOCS/wildcard CORS/missing hosts/unsafe secrets rejected. |
| Secret values not logged in validation errors | **PASS** | Test confirms secret not in error message. |
| Public document serving disabled if safe retrieval impossible | **NOT APPLICABLE** | Safe authenticated retrieval implemented for current proof storage model. |
| Flutter upload/document viewing compatibility fully verified | **NOT TESTED** | Flutter SDK not used for runtime test; source scan found proofImageUrl model only. |
| Existing destructive pytest suite | **NOT TESTED** | Intentionally not run; destructive conftest isolation unproven. |
| Full E2E/API regression | **NOT TESTED** | Only isolated containment tests and compile checks run. |

## Remaining Security Risks
- `/uploads` endpoint now requires auth; clients that previously fetched image URLs directly without Authorization header will receive 401. Flutter/mobile/web clients may need authenticated fetch or signed-URL redesign.
- Document authz is based on `ServiceRequest.proof_image_url` lookup; other future document types need explicit authz rules.
- In-process rate limiting, object storage, malware scanning, full audit logging, and DR/backup remain unresolved (out of scope).
- CSP default is compatibility-oriented; should be tightened per deployment after validation.
- Existing `.env` and `database_backups/` exist locally (ignored/untracked check for tracked files passed); operational review/secret rotation remains separate authorized task.

## Manual Deployment / Configuration Steps
1. Set `ENVIRONMENT=production`, `DEBUG=false`, `TESTING=false`, `EXPOSE_DOCS=false`.
2. Provide explicit `CORS_ALLOWED_ORIGINS` (no wildcard) and `TRUSTED_HOSTS`.
3. Provide strong `JWT_SECRET_KEY` and `QUOTE_SIGNING_SECRET` (>=32 chars, non-default). Rotate secrets through authorized ops process.
4. Configure HTTPS at reverse proxy/load balancer; set `HTTPS_REDIRECT_ENABLED` and `HSTS_ENABLED` appropriately; set `TRUST_PROXY_HEADERS=true` only behind trusted proxies.
5. Review/tighten `CONTENT_SECURITY_POLICY` for deployed Flutter web/API clients.
6. Move uploads to private object storage in a later stage; until then ensure `UPLOAD_DIR` is not web-served outside app auth endpoint.
7. Do not enable docs in production. Use isolated staging tests before deployment.