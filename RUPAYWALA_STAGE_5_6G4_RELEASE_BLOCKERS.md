# RUPAYWALA STAGE 5.6G-4 — Release Blockers

## Final Classification
**PARTIALLY COMPLETE**

No production readiness claim.

## Release Blockers / Open Items

| ID | Area | Status | Detail |
|---|---|---:|---|
| RB-G4-001 | Payment idempotency DB-level constraint | **OPEN** | Proposed full unique index `(user_id,payment_type,idempotency_key)` WHERE key IS NOT NULL is incompatible as-is with current extra-charge terminal retry semantics (5.6G-3). No index added. Target-data duplicate preflight not authorized/executed. |
| RB-G4-002 | Full restricted-role HTTP E2E coverage | **OPEN/PARTIAL** | Key flows passed (auth/profile/logout, quote/request basics, payment idempotency/conflict, admin/field basic authz). Missing/partial: registration OTP HTTP, quote expiry/signature tamper HTTP, payment verify clean retest, concurrent HTTP retries, extra-charge HTTP retry, subscription activation/balance/family limits HTTP, admin branch assignment, field visit start/complete/status transitions. |
| RB-G4-003 | Google Maps live configuration | **BLOCKED** | Not configured in env; no live places/route/distance validation. |
| RB-G4-004 | Fast2SMS OTP delivery | **BLOCKED** | Not configured; no live SMS sent/tested. |
| RB-G4-005 | SMTP configuration | **BLOCKED** | Not configured; no live email sent/tested. |
| RB-G4-006 | Google OAuth | **BLOCKED** | Not configured; no live token validation. |
| RB-G4-007 | UPI/payment integration live settlement | **BLOCKED/NOT TESTED** | Manual UPI intent/UTR/admin verify flow partially exercised; no live gateway settlement/reconciliation. |
| RB-G4-008 | File upload validation | **NOT TESTED** | Allowed formats, MIME, magic-byte, size, unauthorized upload/retrieval authorization not tested. |
| RB-G4-009 | Full pytest isolation/suite | **BLOCKED** | `tests/conftest.py` destructive; full suite not run. |
| RB-G4-010 | Quote integrity/ownership edge cases | **PARTIAL** | Ownership and invalid ID checks passed; expiry and explicit signature tamper HTTP cases not executed. |
| RB-G4-011 | Family-member subscription workflows HTTP E2E | **NOT TESTED** | Prior service-level/catalog tests exist; HTTP E2E not executed. |
| RB-G4-012 | Rate limiting / security hardening | **NOT TESTED** | No rate-limit, exhaustive input validation, or error leakage audit. |

## Preserved Databases
Not modified/deleted: `rupaywala_ori`, `rupaywala_validation`, `rupaywala_role_validation`, `rupaywala_e2e_validation`, `rupaywala_idem_validation`, `rupaywala_g2seed_validation`, `rupaywala_g3pay_validation`. `rupaywala_g4api_validation` created as disposable validation DB.

## Recommendation
Do **not** claim production readiness. Resolve blockers with authorized environment/config access, target-data preflight for payment index redesign, and complete restricted-role HTTP E2E + security/upload/integration validation.