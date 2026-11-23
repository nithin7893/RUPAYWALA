# RUPAYWALA KNOWN LIMITATIONS

**Date:** 2026-11-21  
**Stage:** 1 - Client Demonstration Readiness

## Demo-Relevant Limitations

| ID | Severity | Limitation | Impact on Demo | Workaround / Control |
|---|---|---|---|---|
| LIM-001 | P1 | End-to-end workflows not runtime-verified in this pass. | Cannot guarantee demo flow will work in target environment. | Run full demo rehearsal in isolated staging/demo environment before client meeting. |
| LIM-002 | P1 | Demo DB/accounts/data not provisioned/verified. | Login/request/payment demos may fail or show empty/unrealistic data. | Prepare separate demo DB with sanitized realistic seed data and role-based demo accounts. Do not use production data. |
| LIM-003 | P1 | External integrations depend on env/credentials/network: Google Maps, Fast2SMS, SMTP, Google OAuth, UPI. | OTP, map search, quote distance, email, Google sign-in, or payment QR may fail. | Validate all keys before demo; have fallback demo path (pre-created accounts, known addresses, admin verification flow). |
| LIM-004 | P1 | Flutter fixed-quote integration changed but not executed. | Service request creation may have UI/runtime issue despite static correctness. | Run Flutter app against demo backend and verify quote-create-submit flow. |
| LIM-005 | P2 | Pytest suite not executed because conftest drops/recreates `rupaywala_test` schema. | Regression risk remains. | Run pytest only against disposable test DB. |
| LIM-006 | P2 | Flutter CLI unavailable in current environment. | No analyze/test/build evidence. | Install Flutter SDK and run `flutter analyze`, `flutter test`, `flutter build apk --debug`. |
| LIM-007 | P2 | JWT invalidation is token-version based; no per-session revocation/refresh token pair. | Logout/password reset invalidates all user sessions; old access token remains valid until expiry unless version bumped. | Acceptable for demo; communicate re-login behavior after password changes. |
| LIM-008 | P2 | CORS default is `*` in code config when env var unset. | Unsafe if deployed as-is. | Set explicit `CORS_ALLOWED_ORIGINS` in demo/prod env. |
| LIM-009 | P2 | In-process rate limiting only. | Limits not shared across workers/instances. | Use single instance for demo; move to Redis for production. |
| LIM-010 | P2 | Uploads served via `/uploads` static mount. | Simple demo solution; not a hardened object-storage/authenticated media design. | Use only for demo proof files; move to cloud storage + access control for production. |
| LIM-011 | P2 | Admin "reports/statistics" are basic dashboard stats, not a full reporting module. | Client may expect richer reports. | Present as dashboard overview, not full analytics/reporting suite. |
| LIM-012 | P2 | `MyTasksScreen` exists but is not wired in field-member shell; field dashboard/detail path is primary. | Minor navigation inconsistency if discovered. | Demo via Field Member Today tab and task detail screen. |
| LIM-013 | P3 | No push notifications; notifications are in-app only. | Users must refresh/open app to see updates. | State clearly during demo. |
| LIM-014 | P3 | No OCR/document processing/cloud document storage. | Document automation features unavailable. | Out of Stage 1 scope. |
| LIM-015 | P3 | No CI/CD, Docker, deployment automation, monitoring, backup/recovery validation. | Operational readiness not production-grade. | Roadmap B. |
