# RUPAYWALA STAGE 5.6J — Private Document Storage & Authenticated Delivery Hardening

## Status
**PARTIALLY COMPLETE (implementation delivered with isolated test evidence; not production-ready).**

Stage 5.6J is an implementation/hardening stage. No production readiness claim is made. Stage 5.6I security controls were preserved.

## 1) Mandatory Initial Repository Audit

### Existing implementation
- **Backend:** FastAPI + SQLAlchemy + Alembic + PostgreSQL. Auth via JWT (`app/utils/dependencies.py`) with DB user reload and role checks.
- **Document upload:** `POST /field-member/complete-request` in `app/routes/field_member_routes.py` accepted optional proof file and saved via `app/utils/upload_service.py` to local `UPLOAD_DIR/proof/user_{id}/...`. Stored relative path in `ServiceRequest.proof_image_url`.
- **Document retrieval:** Stage 5.6I removed public `/uploads` StaticFiles mount and added authenticated `GET /uploads/{file_path:path}` in `app/main.py` with owner/admin/assigned-field-member authorization and path containment.
- **DB metadata:** `service_requests.proof_image_url` only; no document metadata table, checksum, scan status, retention, or audit table.
- **Flutter:** `FieldMemberJob.proofImageUrl` parsed (`rupaywala_app/lib/core/models/ops_models.dart`); `FieldMemberRepository.complete` supported multipart proof upload; no proof display in request/field/admin detail screens; `ApiClient` had no authenticated binary fetch.
- **Config/deployment:** `.env.example` and 5.6I security config present; no object storage/malware/retention config.

### Security weaknesses identified
- Local filesystem storage only; no private object storage abstraction.
- No malware scanning/scanning status gating.
- No document metadata table (checksum, mime, size, scan status, expiry, deletion).
- No short-lived signed URL delivery; only direct authenticated stream from local path.
- No document audit log table for upload/retrieval/unauthorized/deletion events.
- No retention/expiry enforcement.
- No proof rendering in Flutter through authenticated fetch (proofImageUrl existed but not displayed).
- Legacy proof URL was a raw storage-relative path.

### Files requiring modification (planned)
- Backend: `app/config.py`, `app/main.py`, `app/models/__init__.py`, `app/models/service_request.py`, `app/routes/field_member_routes.py`, `app/routes/service_routes.py`, `app/schemas/field_member_schema.py`, `app/schemas/service_request_schema.py`, `alembic/env.py`, `.env.example`, tests.
- New: document model/audit model, storage abstraction, document service, document routes, migration, Flutter secure image widget/model updates.
- Flutter: `api_client.dart`, models, repositories/screens/widgets for authenticated proof display.

### Backward compatibility risks
- Changing `proof_image_url` semantics could break clients; kept field and added `proof_document_id`.
- Legacy local proof files must remain retrievable through authenticated endpoint.
- `/uploads` auth-required behavior from 5.6I must remain.
- DB migration must be additive only.

## 2) Files Created
| File | Purpose |
|---|---|
| `app/models/document_record.py` | Document metadata model (`DocumentRecord`, scan/storage enums). |
| `app/models/document_audit_log.py` | Document audit log model. |
| `app/services/document_storage.py` | Storage abstraction: local backend + S3-compatible private backend, signed URL support, storage errors. |
| `app/services/document_service.py` | Upload validation, checksum, malware scan integration, metadata persistence, authz, retrieval, deletion, audit logging. |
| `app/routes/document_routes.py` | Authenticated document metadata/content/delete endpoints. |
| `alembic/versions/0008_private_document_storage.py` | Additive migration for document metadata/audit tables and `service_requests.proof_document_id`. |
| `rupaywala_app/lib/widgets/secure_document_image.dart` | Authenticated Flutter document image widget with loading/error/retry states. |
| `tests/test_stage56j_private_documents.py` | Isolated Stage 5.6J backend tests. |
| `RUPAYWALA_STAGE_5_6J_IMPLEMENTATION_REPORT.md` | This report. |

## 3) Files Modified
| File | Change |
|---|---|
| `app/config.py` | Added storage/malware/retention/document env config. |
| `app/main.py` | Registered document router; legacy `/uploads` now enforces DocumentRecord scan/authz when metadata exists; legacy local authz path preserved. |
| `app/models/__init__.py` | Registered `DocumentRecord`, `DocumentAuditLog`, enums. |
| `app/models/service_request.py` | Added nullable `proof_document_id` FK to `document_records.id`. |
| `app/routes/field_member_routes.py` | Proof upload now uses `DocumentService.store_document`; sets `proof_document_id` and authenticated `proof_image_url`. |
| `app/routes/service_routes.py` | Includes `proof_document_id` in response. |
| `app/schemas/field_member_schema.py` | Added `proof_document_id` to field job response. |
| `app/schemas/service_request_schema.py` | Added `proof_document_id` to service request response. |
| `alembic/env.py` | Imported new document models for migration metadata. |
| `.env.example` | Added storage, signed URL, malware scan, retention env vars. |
| `requirements.txt` | Added optional `boto3`/`clamd` dependencies for S3 storage and ClamAV scanning. |
| `rupaywala_app/lib/core/api/api_client.dart` | Added authenticated `getBytes` for secure document fetch. |
| `rupaywala_app/lib/core/models/ops_models.dart` | Added `proofDocumentId`. |
| `rupaywala_app/lib/core/models/service_models.dart` | Added `proofImageUrl`, `proofDocumentId`. |
| `rupaywala_app/lib/features/field_member/field_task_detail_screen.dart` | Displays proof via `SecureDocumentImage`. |
| `rupaywala_app/lib/features/service/request_detail_screen.dart` | Displays proof via `SecureDocumentImage`. |
| `rupaywala_app/lib/features/admin/admin_request_detail_screen.dart` | Displays proof via `SecureDocumentImage`. |
| `rupaywala_app/lib/widgets/widgets.dart` | Exported `SecureDocumentImage`. |

## 4) Database Migrations Introduced
- `alembic/versions/0008_private_document_storage.py` (Revises `0007_user_token_version`)
  - Creates `document_scan_status` enum (`PENDING`, `CLEAN`, `INFECTED`, `FAILED`).
  - Creates `document_records` with required metadata fields: `id`, `owner_id`, `document_type`, `storage_provider`, `storage_key`, `bucket`, `original_filename`, `mime_type`, `file_size`, `checksum_sha256`, `scan_status`, `scan_detail`, `uploaded_at`, `updated_at`, `expires_at`, `deleted_at`, `deleted_by_user_id`.
  - Creates `document_audit_logs` for audit events.
  - Adds `service_requests.proof_document_id` nullable FK to `document_records.id` (`ON DELETE SET NULL`).
  - Adds indexes/FKs; additive only; no destructive migration.

## 5) New Environment Variables
| Variable | Purpose | Default/Notes |
|---|---|---|
| `STORAGE_PROVIDER` | `local` or `s3` private object storage | `local` |
| `STORAGE_BUCKET` | S3 bucket/container name | empty |
| `STORAGE_REGION` | S3 region | empty |
| `STORAGE_ENDPOINT_URL` | S3-compatible endpoint | empty |
| `STORAGE_ACCESS_KEY` | Backend-only storage credential | empty; never expose |
| `STORAGE_SECRET_KEY` | Backend-only storage credential | empty; never expose |
| `STORAGE_USE_SSL` | S3 SSL flag | `true` |
| `STORAGE_SIGNED_URL_EXPIRES_SECONDS` | Signed URL TTL | `300` |
| `MALWARE_SCAN_ENABLED` | Enable malware scan before availability | `false` |
| `MALWARE_SCAN_PROVIDER` | Scanner provider | `clamav` |
| `CLAMAV_HOST` | ClamAV host | `127.0.0.1` |
| `CLAMAV_PORT` | ClamAV port | `3310` |
| `CLAMAV_TIMEOUT_SECONDS` | Scan timeout | `30` |
| `DOCUMENT_RETENTION_DAYS` | Retention/expiry days; `0` disables | `0` |

## 6) Storage Architecture Implemented
- **Abstraction:** `StorageBackend` protocol with `put/get/delete/exists/signed_url`.
- **Local backend:** private filesystem under `UPLOAD_DIR`, path containment enforced, used for controlled dev/migration and legacy compatibility. No public static mount.
- **S3 backend:** private S3-compatible object storage via `boto3` lazy import; backend-only credentials; presigned `get_object` URLs with configurable expiry; no bucket/key exposed by API payloads.
- **Metadata:** `DocumentRecord` in PostgreSQL stores owner/type/provider/key/bucket/mime/size/checksum/scan/retention/deletion metadata. Raw document contents are never stored in DB metadata.
- **Delivery:** `GET /documents/{id}` returns authorized delivery metadata; `GET /documents/{id}/content` provides authenticated streaming with `Cache-Control: private, no-store`. For S3, signed URL delivery is supported by service payload; local defaults to authenticated streaming.
- **Legacy compatibility:** existing `ServiceRequest.proof_image_url` local relative paths remain accessible through authenticated `/uploads/{path}` with existing 5.6I authz and path containment; DocumentRecord-backed paths gain scan/authz enforcement.

## 7) Security Improvements
- Private storage abstraction with backend-only credentials.
- Authenticated document retrieval on every request (`JWT` + DB user check via `get_current_user`).
- Object-level authorization: admin, owner, or assigned field member (for service proof) only; unauthorized access returns 404.
- Scan-status gating: `PENDING/INFECTED/FAILED` documents blocked from retrieval; scan failures not treated as clean.
- Upload hardening: extension allowlist, magic-byte/content signature validation, client MIME not trusted, configurable max size, filename sanitization, random UUID object IDs, storage key normalization/path containment.
- No public static document serving; no bucket/key exposure in retrieval payload.
- Document audit logging (DB + logger) for upload, validation failure, malware scan, retrieval, unauthorized access, expired access, deletion; no JWT/signed URLs/credentials/full contents/sensitive customer info logged.
- Deletion controls: owner/admin only, deletes storage object then marks metadata deleted, audit logged, storage failures handled safely.
- Retention: configurable `expires_at`; expired/deleted records cannot be retrieved.

## 8) Tests Executed and Results
| Test | Command | Result |
|---|---|---|
| Python compilation | `.\venv\Scripts\python.exe -m py_compile app/config.py app/main.py app/models/document_record.py app/models/document_audit_log.py app/services/document_storage.py app/services/document_service.py app/routes/document_routes.py app/routes/field_member_routes.py app/routes/service_routes.py alembic/versions/0008_private_document_storage.py tests/test_stage56j_private_documents.py` | **PASS** |
| Isolated 5.6I + 5.6J security tests | `.\venv\Scripts\python.exe -m pytest --noconftest tests/test_stage56i_security_containment.py tests/test_stage56j_private_documents.py -q` | **PASS — 27 passed** |

### 5.6J backend test coverage (isolated)
- Document service store + authorized retrieval (owner/admin) — PASS
- Cross-user document access rejection — PASS
- Invalid extension/MIME/signature rejection — PASS
- Oversized file rejection — PASS
- Path traversal rejection — PASS
- Infected document retrieval blocked — PASS
- Scan failure blocks retrieval — PASS
- Document deletion authorization and post-delete 404 — PASS
- Expired document retrieval rejected — PASS
- Storage failure handling — PASS
- Malware scan failure handling (`MALWARE_SCAN_ENABLED=true`, scanner failure) — PASS
- Legacy `/uploads` authz preserved — PASS

### Not executed / limitations
- **Existing destructive pytest suite (`tests/conftest.py`)** — NOT RUN (isolation unproven).
- **Full backend regression/E2E suite** — NOT RUN.
- **Flutter static analysis / Flutter tests** — NOT RUN (Flutter SDK not available in environment).
- **Real S3 object storage integration** — NOT RUN (no credentials/environment; code path implemented, boto3 lazy dependency).
- **Real ClamAV integration** — NOT RUN (no ClamAV service in environment; scan failure/disabled paths tested).
- **Signed URL expiry rejection by S3 provider** — NOT TESTED (provider-dependent; local mode uses authenticated streaming). Expired document metadata rejection tested.
- **PostgreSQL migration apply on target DB** — NOT RUN (no DB modification performed; migration file compiled and model metadata validated by tests).

## 9) Remaining Issues / Blockers
| ID | Severity | Status | Issue | Notes |
|---|---|---:|---|---|
| B56J-001 | High | NOT TESTED | Flutter runtime verification | Flutter SDK unavailable; authenticated proof widget added but not runtime-tested on web/mobile. |
| B56J-002 | High | NOT TESTED | Real private object storage (S3) | Requires boto3 dependency + staging bucket/credentials and integration tests. |
| B56J-003 | High | NOT TESTED | Real ClamAV scanning | Requires clamd/ClamAV deployment and infected EICAR-style integration test in staging. |
| B56J-004 | Medium | OPEN | Automatic retention purge job not implemented | Expired docs are blocked from retrieval; physical purge/anonymization job should be scheduled only under explicit verified retention policy. |
| B56J-005 | Medium | NOT TESTED | Existing destructive pytest suite / full regression | `tests/conftest.py` remains destructive; full regression isolation unproven. |
| B56J-006 | Medium | OPEN | Legacy proof files have no DocumentRecord metadata | Legacy files remain accessible via authenticated legacy path; optional backfill migration can create metadata records. |
| B56J-007 | High | CARRIED FORWARD | Payment idempotency DB constraint redesign | RB-G4-001 / NEW-56G1-001 unresolved. |
| B56J-008 | High | CARRIED FORWARD | External integration production validation | Maps/SMS/SMTP/OAuth/UPI still blocked/unconfigured/unvalidated. |
| B56J-009 | High | CARRIED FORWARD | PostgreSQL prod hardening / backup-DR / CI-CD | 5.6H infra blockers remain. |

## 10) Production Deployment Steps
1. **Do not claim production readiness.** Deploy only after staging validation.
2. Apply additive migration `0008_private_document_storage` in staging first; back up DB before apply. No destructive migration.
3. Set env vars in `.env`/secret manager (never commit secrets): `STORAGE_PROVIDER=s3`, bucket/region/endpoint/credentials, `STORAGE_SIGNED_URL_EXPIRES_SECONDS`, `MALWARE_SCAN_ENABLED=true`, ClamAV settings, `DOCUMENT_RETENTION_DAYS` per approved policy.
4. Provision private bucket/container: block public access, enforce server-side encryption/policy, backend-only IAM credentials.
5. Deploy ClamAV/clamd in private network; validate scan pass/fail/infected behavior.
6. Keep `UPLOAD_DIR` private and not web-served; retain authenticated `/uploads` legacy endpoint until legacy docs are migrated/backfilled.
7. Validate authenticated document upload/retrieval/deletion with owner/admin/field-member roles; confirm cross-user access denied.
8. Validate Flutter web/mobile proof rendering with Authorization header through `SecureDocumentImage`/authenticated fetch.
9. Run isolated regression suite and staging E2E before any production rollout.
10. Preserve Stage 5.6I controls: HTTPS/HSTS/proxy settings, TrustedHost, CORS allowlist, docs disabled in prod, no secrets in logs.

## 11) Stage 5.6I Controls Preserved
- No public `/uploads` static mount.
- Auth-required legacy `/uploads` endpoint with path containment and object-level authz.
- Docs/OpenAPI exposure controlled by config; prod startup validation intact.
- CORS allowlist, TrustedHost, HTTPS redirect/HSTS/security headers, runtime config validation preserved.
- `.env.example` placeholders only; `.gitignore` hardened. No secret values logged.