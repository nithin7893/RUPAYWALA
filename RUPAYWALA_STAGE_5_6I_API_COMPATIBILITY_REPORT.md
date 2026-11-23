# RUPAYWALA STAGE 5.6I — API Compatibility Report

## Summary
Stage 5.6I preserves most existing route contracts but introduces intentional security behavior changes for document retrieval, documentation exposure, CORS, host validation, and production startup configuration.

## Compatibility Matrix

| Area | Prior Behavior | New Behavior | Classification | Compatibility Impact |
|---|---|---|---:|---|
| `GET /uploads/{file_path:path}` | Public StaticFiles serving, no auth | Authenticated endpoint requiring valid user; owner/admin/assigned field member only; 401 unauthenticated; 404 unauthorized/not-found | **PASS (intentional security change)** | **Breaking for unauthenticated direct file fetches.** Clients must send Bearer token and be authorized. URL path shape preserved. |
| `proof_image_url` in responses | Relative path returned | Same field/path value returned | **PASS** | No schema change; retrieval semantics changed. |
| `/docs`, `/redoc`, `/openapi.json` | Always enabled | Enabled only when `EXPOSE_DOCS=true`; production startup rejects EXPOSE_DOCS true | **PASS (intentional)** | Production/dev tooling behavior changes; API runtime unaffected. |
| CORS | Default wildcard `*` | Explicit allowlist required in prod; dev localhost defaults; wildcard rejected in prod validation | **PASS (intentional)** | Browser clients from non-allowlisted origins will be blocked. Configure real origins. |
| TrustedHost | No host allowlist | TrustedHost middleware enabled; explicit hosts required in prod | **PASS (intentional)** | Requests with unexpected Host header rejected (400). |
| HTTPS redirect/security headers | None | Configurable HTTPS redirect, security headers, conditional HSTS | **PASS (intentional)** | Reverse proxy/TLS config must align; HTTP may redirect 307. |
| Startup config validation | Some required secrets only | Additional prod validation (DEBUG/TESTING/EXPOSE_DOCS/CORS/TRUSTED_HOSTS/unsafe secrets) | **PASS (intentional)** | Misconfigured prod env will fail fast at startup. |
| Existing non-upload API routes | Unchanged | Unchanged | **PASS** | No route contract changes made. |

## Flutter / Client Impact
- **Flutter source scan:** `rupaywala_app/lib/core/models/ops_models.dart` parses `proof_image_url`; no direct `/uploads` string or `proofImageUrl` render/fetch usage found in `lib/`. Built web artifacts contain `proof_image_url` string, consistent with model.
- **Required Flutter change (if proof images displayed/fetched):** fetch protected document URLs with `Authorization: Bearer <token>` (e.g., via authenticated HTTP client and `Image.memory`/blob, or backend-provided signed URL in future stage). Direct `Image.network` to `/uploads/...` without auth will fail with 401.
- **No backend schema change** for `proof_image_url`.

## Tests Not Executed
- Full existing API contract regression suite not run (destructive conftest). 
- Flutter analysis/runtime not run.
- End-to-end browser/mobile document rendering not run.

## Recommendation
Before staging deployment, run isolated API regression tests for service/field/admin request detail endpoints and verify Flutter proof-image rendering uses authenticated requests. 