# RUPAYWALA STAGE 5.6I — Remaining Blockers

## Stage Status
**PARTIALLY COMPLETE** — critical containment implemented for targeted scope; not production-ready.

## Blockers / Open Items

| ID | Severity | Classification | Item | Reason / Evidence | Next Action |
|---|---|---:|---|---|---|
| B56I-001 | High | **NOT TESTED** | Full API regression / E2E coverage | Only 14 isolated containment tests + py_compile executed; existing pytest suite destructive. | Build safe isolated regression suite; cover request/service/admin/field endpoints and auth flows. |
| B56I-002 | High | **NOT TESTED** | Flutter proof-document rendering compatibility | Backend now requires auth for `/uploads/*`; Flutter model has `proofImageUrl`, but rendering/fetch path not runtime-verified. | Update Flutter to fetch protected docs with auth headers or backend signed URL; verify on web/mobile. |
| B56I-003 | High | **OPEN** | Local secret/backup hygiene and credential rotation | `.env` and `database_backups/` exist locally (tracked-sensitive check passed; `.gitignore` updated). No rotation performed. | Authorized ops: secret audit/rotation, secure backup storage, ensure no secrets in git history. |
| B56I-004 | Medium | **NOT TESTED** | HTTPS redirect/HSTS behavior behind real proxy | Middleware/config added; no real reverse-proxy deployment test. | Validate in staging with TLS termination, `TRUST_PROXY_HEADERS`, redirect/HSTS behavior. |
| B56I-005 | Medium | **OPEN** | CSP tightening for production Flutter web | Default CSP is compatibility-oriented (`unsafe-inline`, `unsafe-eval`, broad sources). | Validate strict CSP against deployed Flutter web build; tighten incrementally. |
| B56I-006 | Medium | **NOT TESTED** | Authenticated document access for future document types | Current authz covers `ServiceRequest.proof_image_url` only. | Add explicit authz mapping for any new document tables/URLs before exposing. |
| B56I-007 | High | **BLOCKED** | Private object storage / signed URLs | Out of 5.6I scope; local filesystem still used. | Stage 5.6J/Storage: move to private object storage, signed/authenticated retrieval, lifecycle/retention. |
| B56I-008 | High | **BLOCKED** | PostgreSQL production hardening | Out of scope; 5.6D/5.6E/5.6F staging evidence only. | Separate stage: prod roles/TLS/pg_hba/network/pooling/monitoring. |
| B56I-009 | High | **OPEN** | Payment idempotency DB constraint redesign | Carried forward RB-G4-001/NEW-56G1-001. | Target-data preflight + semantic scope redesign + safe migration. |
| B56I-010 | High | **BLOCKED** | External integrations production validation | Maps/SMS/SMTP/OAuth/UPI still blocked/unconfigured per 5.6G4. | Configure and test in staging with authorized credentials. |
| B56I-011 | Medium | **BLOCKED** | Full pytest isolation / CI gates / DR | Destructive conftest; no CI/CD/DR evidence. | Refactor tests, add CI/CD, backup/restore drills. |

## Stage 5.6I Completion Criteria Assessment
- Implemented containment changes have supporting isolated test evidence: **YES (for implemented scope)**.
- All required 5.6I scope items fully production-validated: **NO**.
- Production-ready claim: **NO**.

## Single Most Important Next Stage
**Stage 5.6J — Private Document Storage & Authenticated Delivery Hardening**: move uploads from local static-compatible filesystem to private object storage with authenticated/signed access, complete Flutter/client compatibility, and add malware/MIME/retention controls. This directly closes the highest-risk residual from 5.6I (local file storage + client compatibility) before broader production hardening.