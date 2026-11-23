# RUPAYWALA — H-02 Production API Configuration and HTTPS Remediation Report

**Date:** 23 November 2026
**Scope:** H-02 (production API configuration, HTTPS enforcement, fresh Android/web builds).
**Status:** **BLOCKED — production API domain not established.** No production build was generated.

---

## 1. Executive summary

Stage 1 (configuration audit) was completed in full. The audit established that:

- The only API endpoint values in the source tree are **development defaults**
  (`http://127.0.0.1:8000`, `http://10.0.2.2:8000`) and a **documentation-only placeholder**
  (`https://api.rupaywala.invalid`) used in the C-02 validation build report.
- **No real production API domain or HTTPS endpoint exists in repository documentation, `.env`
  files, deployment configuration, or approved configuration.**
- There is no reverse-proxy, Docker, nginx, or other deployment configuration in the repository.

Per the H-02 instruction — *"If the actual production API domain is not established in repository
documentation or approved configuration, stop and request it rather than generating a fake
production build"* — work is stopped here. **No code was modified, no production endpoint was
invented, and no release/web build with a placeholder endpoint was produced.** The required input
is stated in Section 9.

---

## 2. Stage 1 — Configuration audit

### 2.1 Flutter API configuration

| Location | Finding |
|---|---|
| `rupaywala_mobile/lib/core/config/app_config.dart:15` | `API_BASE_URL` read via `String.fromEnvironment`; no validation of scheme, host, or placeholder status. |
| `app_config.dart:27` | Override returned verbatim when non-empty (including `http://`, localhost, or fake domains). |
| `app_config.dart:32` | Android fallback `http://10.0.2.2:8000` (emulator loopback). |
| `app_config.dart:35` | General fallback `http://127.0.0.1:8000`. |
| `app_config.dart:10` | Doc comment example uses `http://192.168.1.10:8000` (LAN development address). |
| `app_config.dart:38-43` | `baseUrlHost` displays host/port in the UI; no secret is exposed. |
| `lib/core/api/api_client.dart:164` | Builds request URIs from `AppConfig.baseUrl` — API contract unchanged. |
| `lib/features/auth/phone_input_screen.dart:228` | Displays `AppConfig.baseUrlHost` to the user. |

**Conclusion:** the client silently falls back to a loopback HTTP endpoint with no build-mode gate.
A release build without an override would embed a development endpoint — exactly the behaviour H-02
must eliminate.

### 2.2 Android release configuration

| Location | Finding |
|---|---|
| `android/app/src/main/AndroidManifest.xml:6` | C-02 `android.permission.INTERNET` present and intact. |
| All Android manifests | No `android:usesCleartextTraffic`, no `android:networkSecurityConfig`, no `network_security_config.xml`. For `targetSdk 36`, cleartext traffic is disabled by default — no unintended cleartext permission is declared. |
| `android/app/build.gradle.kts` | C-02 toolchain alignment intact (Gradle 9.5.0 / AGP 9.3.1 / KGP 2.4.20). No API URL stored here. |
| `android/local.properties` | Contains only SDK/Flutter paths and version values; no endpoint. Not a secret store for API config. |

**Conclusion:** Android networking is not configured to permit cleartext. The only missing piece is
the real HTTPS endpoint at build time.

### 2.3 Flutter web configuration

| Location | Finding |
|---|---|
| `web/index.html` | Unmodified Flutter template: description "A new Flutter project", title `rupaywala_app`, unexpanded `$FLUTTER_BASE_HREF`; no API URL. |
| `web/flutter_bootstrap.js` | Unexpanded template (`{{flutter_js}}`, `{{flutter_build_config}}`); no API URL. |
| `build/web/` | **Does not exist** in the current working tree. The stale web bundle cited in the final audit was removed during C-02 build-cache cleanup, so no stale compiled development endpoint remains in the repository. A fresh production bundle is still required once the endpoint is supplied. |

### 2.4 Backend CORS and HTTPS enforcement

| Location | Finding |
|---|---|
| `app/config.py:221-238` | Production `CORS_ALLOWED_ORIGINS` defaults to empty when unset; development defaults are explicit `http://localhost`/`127.0.0.1` origins. |
| `app/config.py:244-251` | Development-only origin regex is narrowly scoped to localhost/127.0.0.1; disabled in production. |
| `app/config.py:356-397` | Production validation rejects DEBUG/TESTING/EXPOSE_DOCS, wildcard CORS, wildcard TRUSTED_HOSTS, origin regex in production, missing explicit CORS origins/hosts, and unsafe secrets. |
| **Gap** | Production validation does **not** require `CORS_ALLOWED_ORIGINS` entries to use `https://`. A misconfigured `http://` production origin would be accepted. Should be addressed once the approved production web origin is known. |
| `app/main.py:108-125` | HTTPS redirect enabled by default in production (`HTTPS_REDIRECT_ENABLED` defaults to `IS_PRODUCTION`). |
| `app/main.py:128-148` | HSTS applied only when HTTPS (real or trusted forwarded proto). |
| `app/main.py:44,112,141` | H-01 `is_trusted_peer()` gate intact: forwarded proto is honoured only from explicitly allowlisted proxy peers. |

### 2.5 Environment variables and deployment documentation

| Item | Finding |
|---|---|
| `rupaywala_backend/.env` | Not present in the repository (correct — no secrets committed). |
| `.env.example` | Documents `CORS_ALLOWED_ORIGINS=http://localhost:3000,...` for development, `TRUST_PROXY_HEADERS=false`, `TRUSTED_PROXY_IPS=127.0.0.1`, `HTTPS_REDIRECT_ENABLED=false`, `HSTS_ENABLED=false`. No production values. |
| Deployment configuration | No Dockerfile, compose file, nginx config, Procfile, CI/CD definition, or release runbook exists. |
| Prior audit reports | Consistently state: no production base URL, no runtime production config, no production domains invented, and `--dart-define=API_BASE_URL=https://...` is required for any deployment. |

### 2.6 Complete endpoint inventory

| Value | Type | Location |
|---|---|---|
| `http://127.0.0.1:8000` | Development HTTP fallback | `app_config.dart:35` |
| `http://10.0.2.2:8000` | Android emulator HTTP fallback | `app_config.dart:32` |
| `http://192.168.1.10:8000` | Development doc example | `app_config.dart:10` |
| `http://localhost:3000`, `http://127.0.0.1:3000`, `:5173`, `:8080` | Development CORS origins | `config.py`, `.env.example` |
| `^https?://(localhost\|127\.0\.0\.1)(:\d+)?$` | Development-only CORS regex | `config.py:246` |
| `https://api.rupaywala.invalid` | **Placeholder** | C-02 report only (validation build), not application config |
| Real production HTTPS API domain | **NOT FOUND** | — |

No API secret, token, or credential is embedded in the Flutter application.

---

## 3. Files modified

**None.** Work was stopped at the explicit blocker condition before Stage 2 implementation.
C-01, C-02, and H-01 fixes were verified as still present (see Section 7).

---

## 4. Production endpoint source

**No production endpoint source exists.** Exhaustive search across the canonical mobile project,
backend configuration, `.env.example`, all audit/deployment reports, and the stale duplicate mobile
tree found no approved production API domain. The only HTTPS-looking application value is the
`.invalid` placeholder used to validate the C-02 Android build; it is explicitly a non-routable
test domain and must not be shipped.

---

## 5. HTTPS validation (static, no deployment)

| Check | Result |
|---|---|
| Production API communication uses HTTPS | **Not verifiable** — no production endpoint supplied. |
| HTTP downgrade prevented | Backend HTTPS redirect enabled by default in production; HSTS gated on HTTPS. Client-side URL scheme validation is **not implemented yet** (blocked). |
| Android cleartext traffic | **PASS (static)** — no `usesCleartextTraffic` or network security config permitting cleartext; `targetSdk 36` defaults to cleartext disabled. |
| Web deployment HTTPS | **Not verifiable** — no web origin or deployment supplied. |
| CORS explicit production origins | **PARTIAL** — explicit origins required in production, wildcard/regex rejected; HTTPS-only origin enforcement is a remaining gap. |
| H-01 proxy protections | **PASS** — `is_trusted_peer()` still gates all forwarded-proto handling. |

These are static/control checks only. No live backend or deployed endpoint was contacted.

---

## 6. Build results

| Build | Result |
|---|---|
| Android release APK with real production endpoint | **NOT PERFORMED — blocked.** The C-02 validation APK used `https://api.rupaywala.invalid` and is explicitly not a production artifact. |
| Fresh production web bundle | **NOT PERFORMED — blocked.** No endpoint supplied; no placeholder bundle generated. |
| Inspection of compiled configuration | **NOT PERFORMED — blocked.** |
| INTERNET permission in release manifest | Previously verified in C-02 and still present in `android/app/src/main/AndroidManifest.xml`. |

---

## 7. Regression results (current tree, no code changes)

| Check | Result |
|---|---|
| Backend full regression | **441 passed, 0 failed** (282.08 s) |
| Flutter tests | **22 passed** |
| Flutter analysis | 0 errors, 0 warnings; 58 pre-existing info-level deprecations |
| C-01 OTP protection | Untouched; included in passing backend suite |
| C-02 INTERNET permission | Present in main manifest |
| H-01 trusted proxy security | Present in `app/utils/proxy.py`, `rate_limit.py`, `main.py` |

No migrations were executed and no production database was touched.

---

## 8. Proposed configuration strategy (for approval, not implemented)

1. Add a build-mode gate in `app_config.dart`: in **release** builds, `API_BASE_URL` must be supplied
   explicitly; absence raises a clear startup error instead of falling back to loopback.
2. Validate any supplied endpoint: absolute URI, `https` scheme, no userinfo, non-placeholder host,
   and not localhost/loopback/emulator (`localhost`, `127.0.0.0/8`, `::1`, `10.0.2.2`, `*.invalid`,
   `*.test`, `*.example`, `example.com`).
3. Keep the existing development defaults for debug/profile/test builds so local development and
   the 22 Flutter tests continue to work.
4. Add Dart unit tests for the validation and fail-closed behaviour.
5. Add HTTPS-only enforcement for `CORS_ALLOWED_ORIGINS` in backend production validation.
6. Once the endpoint is supplied: build the release APK and a fresh web bundle with the real
   `--dart-define=API_BASE_URL=...`, inspect compiled artifacts for absence of localhost/placeholder
   strings, and re-run the full regression set.
7. API base URL is configuration, not a secret; no credentials will be embedded in Flutter.

---

## 9. Required input to unblock H-02

Please provide the approved production values:

1. **Production HTTPS API base URL** (e.g. `https://<approved-host>`) — exact origin, no path unless
   the API is served under one. This must be the real deployed backend origin; it will not be guessed.
2. **Approved production web origin(s)** for `CORS_ALLOWED_ORIGINS` (e.g. `https://<web-host>`), so
   CORS can be restricted to explicitly approved origins.
3. Confirmation of whether the API and web app share a domain or use separate hosts.

Once these are supplied, Stages 2–5 can be completed and the builds/validation above performed.
Work is stopped pending that input.
