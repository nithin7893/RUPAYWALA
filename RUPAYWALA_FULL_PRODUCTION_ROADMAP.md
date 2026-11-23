# RUPAYWALA FULL PRODUCTION ROADMAP

**Date:** 2026-11-21  
**Stage separation:** Roadmap A is Stage 1 demo readiness; Roadmap B is post-demo full production completion. Do not remove Roadmap B items because they are not needed for demo.

## Roadmap A - Client Demonstration (Stage 1)

### A1. Completed / Improved in This Pass
- Fixed forgot-password OTP brute-force protection gap (OTPService verify with purpose, attempts/expiry/use).
- Hardened Google access-token audience validation and email_verified parsing.
- Added JWT token-version invalidation and `/auth/logout`; invalidates tokens on password change/reset/logout.
- Added Flutter/backend token store sharing fix.
- Integrated fixed-quote backend APIs into Flutter service request flow.
- Added `.webp` upload magic-byte validation.
- Added `/uploads` static mount for completion proof visibility in demo.
- Added Alembic migration `0007_user_token_version.py` for token version column.

### A2. Remaining Demo Blockers
- Run end-to-end demo rehearsal in isolated demo environment.
- Provision separate demo DB with sanitized realistic data.
- Create/confirm role-based demo accounts (customer/admin/field member) through authorized process.
- Verify backend startup, `/health`, DB connectivity, and all demo workflows.
- Verify Flutter analyze/test/build/run on target demo devices.
- Validate external integrations: Google Maps, Fast2SMS, SMTP, Google OAuth, UPI/QR.
- Verify fixed-quote flow end-to-end: quote creation, expiry, request creation, extra-charge, admin verification.
- Verify field-member proof upload and proof display.

### A3. Demo Environment Requirements
- Isolated demo database (never production).
- Environment variables set: `DATABASE_URL`, `JWT_SECRET_KEY`, `QUOTE_SIGNING_SECRET`, `UPI_ID`, `CORS_ALLOWED_ORIGINS`, Google/SMS/SMTP keys as needed.
- Demo user accounts and sample policies/branches/service types/plans.
- Backend reachable from Flutter devices/emulators.
- Stable network for map/SMS/payment demos, or prepared fallback script.

### A4. Recommended Demonstration Sequence
1. Admin login/dashboard overview.
2. Customer registration/login/OTP (or pre-provisioned login).
3. Customer profile/policy/subscription view.
4. Create service request with fixed quote and location.
5. Payment flow (extra charge) and admin payment verification.
6. Admin assignment to field member.
7. Field member start/update/complete request.
8. Customer tracking, history, notifications.

## Roadmap B - Full Production Readiness (Stage 2)

### B1. Security Remediation (Remaining)
- Move from token-version invalidation to robust session/refresh-token model with per-device revocation and audit trail.
- Enforce strict CORS allowlist per environment; remove wildcard defaults in deployment.
- Replace in-process rate limiting with Redis/shared store for multi-instance deployments.
- Add comprehensive audit logging for admin/sensitive actions.
- Harden file storage: authenticated media access, virus/malware scanning, object storage, signed URLs.
- Secret management, key rotation, secure env injection, remove debug defaults.
- Security validation: SAST/DAST/dependency scanning, pen-test remediation.

### B2. Stage 6D PostgreSQL Validation
- Execute Stage 6D security scripts only in authorized disposable/staging DB.
- Capture before/after evidence, role permissions, RLS/policy behavior, and rollback validation.
- Resolve any migration-chain inconsistencies (`b96aae0ed4c8` branch vs 0006 head) before production migration.

### B3. Data & Schema
- Finalize Alembic migration chain and production migration runbook.
- Backup/restore drills and migration rollback strategy.
- Data retention/privacy policies for PII, OTP, payment, and document data.

### B4. Feature Completion
- OCR and document processing pipeline.
- Cloud storage for documents/proofs.
- Payment gateway integration beyond manual UPI UTR verification (if required).
- Push notifications (FCM/APNs) and notification preferences.
- Customer support/ticketing/chat as required by product scope.
- Complete web application requirements (if in scope).
- Full admin reporting/analytics exports.

### B5. Quality & Testing
- Automated backend test suite run in CI against disposable DB.
- Flutter analyze/test/build in CI; add integration/E2E tests for critical flows.
- Performance/load testing for quote, request, payment, and admin workflows.
- UAT and regression test plan.
- Accessibility and localization review.

### B6. DevOps & Operations
- Dockerize backend and supporting services; docker-compose for local/dev.
- CI/CD pipelines with lint, tests, security scans, build artifacts, and gated deploys.
- Environment separation: dev/stage/prod with isolated DBs and secrets.
- Observability: structured logs, metrics, tracing, alerting, error reporting.
- Backup/recovery, disaster recovery, and runbooks.
- Production monitoring and incident response.

### B7. Compliance / Operational Readiness
- Privacy policy, terms, consent, and data handling compliance.
- Payment/audit reconciliation process for manual UPI verification.
- Support SOPs, admin training, and release checklist.
