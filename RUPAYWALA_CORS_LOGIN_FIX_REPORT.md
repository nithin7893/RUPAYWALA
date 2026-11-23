# RUPAYWALA CORS Login Fix Report

## Scope

- Project: `C:\RUPAAY_WALA\rupaywala_backend`
- Issue: Flutter web (`http://localhost:60292`) CORS preflight failures calling FastAPI (`http://127.0.0.1:8000`) for `POST /auth/login` and `POST /auth/send-email-otp`.
- Confirmed symptom from report: browser blocked preflight with missing `Access-Control-Allow-Origin`; backend log showed `OPTIONS /auth/login HTTP/1.1 400 Bad Request`.
- No authentication, password verification, OTP logic, database schemas, or user data was modified. `rupaywala_ori` was not accessed.

## Root Cause

1. **Development CORS allowlist did not include Flutter web dev ports.** `app/config.py` defaulted `CORS_ALLOWED_ORIGINS` in development to fixed ports (`3000`, `5173`, `8080`) only. `http://localhost:60292` was not allowed.
2. **No development origin regex was configured.** `CORSMiddleware` was registered with `allow_origins` only; there was no `allow_origin_regex` for narrowly scoped localhost/127.0.0.1 numeric-port development origins.
3. **Starlette CORSMiddleware returns 400 for disallowed preflight origins.** For an `OPTIONS` preflight where the `Origin` is not allowed, Starlette responds `400 Bad Request` with body "Disallowed CORS origin" and no `Access-Control-Allow-Origin` header. This matches the observed backend log (`OPTIONS /auth/login HTTP/1.1 400 Bad Request`) and browser CORS error.

The auth routes themselves were not the cause: `/auth/login` exists at `app/routes/auth_routes.py:418` and `/auth/send-email-otp` exists at `app/routes/auth_routes.py:201`; both are normal POST routes. The failure occurred at CORS preflight before route handling.

## Changes

### 1) `app/config.py`

- Added `CORS_ALLOWED_ORIGIN_REGEX` configuration.
- Development default (when `CORS_ALLOWED_ORIGIN_REGEX` env var is not set and environment is not production):  
  `^https?://(localhost|127\.0\.0\.1)(:\d+)?$`  
  This narrowly allows `localhost` and `127.0.0.1` with any numeric port, covering Flutter web random dev ports such as `60292`.
- Production default: `None` (no regex). Production requires explicit `CORS_ALLOWED_ORIGINS`.
- Added production validation: `CORS_ALLOWED_ORIGIN_REGEX` is rejected in production with message "CORS_ALLOWED_ORIGIN_REGEX is not allowed in production; use explicit CORS_ALLOWED_ORIGINS".
- Preserved existing security rules:
  - Wildcard `*` in `CORS_ALLOWED_ORIGINS` is rejected with other origins.
  - Wildcard CORS cannot be used when credentials are enabled.
  - Production startup validation still requires explicit `CORS_ALLOWED_ORIGINS`, rejects wildcard CORS, and rejects unsafe production config.

### 2) `app/main.py`

- Imported `CORS_ALLOWED_ORIGIN_REGEX` from `app.config`.
- Registered `CORSMiddleware` with `allow_origin_regex=CORS_ALLOWED_ORIGIN_REGEX`.
- Preserved existing CORS settings:
  - `allow_origins=CORS_ALLOWED_ORIGINS`
  - `allow_credentials=ALLOW_CREDENTIALS`
  - `allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]`
  - `allow_headers=["Authorization", "Content-Type", "Accept"]`

## Verification

### A. Automated regression test (existing security containment)

Command:

```powershell
.\venv\Scripts\python.exe -m pytest tests/test_stage56i_security_containment.py -q
```

Result:

```text
..............                                                           [100%]
14 passed
```

This confirms CORS allowlist behavior, wildcard production rejection, trusted host, security headers, and production config validation remain intact.

### B. TestClient preflight verification (code-level, definitive)

Executed with development defaults (`ENVIRONMENT=development`, `TESTING=1`) using FastAPI `TestClient` against the updated app.

Preflight: `OPTIONS /auth/login`, Origin `http://localhost:60292`

- Status: `200 OK`
- `access-control-allow-origin`: `http://localhost:60292`
- `access-control-allow-methods`: `GET, POST, PUT, PATCH, DELETE, OPTIONS`
- `access-control-allow-headers`: includes `Authorization` and `Content-Type` (also includes `Accept`, `Accept-Language`, `Content-Language` from Starlette/CORS handling)
- `access-control-allow-credentials`: `true`

Preflight: `OPTIONS /auth/send-email-otp`, Origin `http://localhost:60292`

- Status: `200 OK`
- `access-control-allow-origin`: `http://localhost:60292`
- `access-control-allow-methods`: `GET, POST, PUT, PATCH, DELETE, OPTIONS`
- `access-control-allow-headers`: includes `Authorization` and `Content-Type`
- `access-control-allow-credentials`: `true`

Disallowed origin preflight: `OPTIONS /auth/login`, Origin `https://evil.example.com`

- Status: `400 Bad Request`
- `access-control-allow-origin`: absent

This confirms the fix for the reported Flutter dev origin and confirms unapproved origins are rejected.

### C. Requested PowerShell live-server preflight

Requested command:

```powershell
$headers = @{
    Origin = "http://localhost:60292"
    "Access-Control-Request-Method" = "POST"
    "Access-Control-Request-Headers" = "content-type,authorization"
}

Invoke-WebRequest `
    -Uri "http://127.0.0.1:8000/auth/login" `
    -Method OPTIONS `
    -Headers $headers
```

Result in this workspace session: **not executed against live backend** because `http://127.0.0.1:8000` was not reachable (`Unable to connect to the remote server`). The backend process was not running at verification time.

**Action required:** restart/reload the running FastAPI server so it loads the updated code, then rerun the PowerShell command above. Expected result after restart:

- HTTP `200`
- `Access-Control-Allow-Origin: http://localhost:60292`
- `Access-Control-Allow-Methods` includes `POST`
- `Access-Control-Allow-Headers` includes `content-type` and `authorization`

Also repeat for:

```powershell
Invoke-WebRequest `
    -Uri "http://127.0.0.1:8000/auth/send-email-otp" `
    -Method OPTIONS `
    -Headers $headers
```

And verify an unapproved origin is rejected (no `Access-Control-Allow-Origin`, preflight rejected):

```powershell
$bad = @{
    Origin = "https://evil.example.com"
    "Access-Control-Request-Method" = "POST"
    "Access-Control-Request-Headers" = "content-type,authorization"
}
Invoke-WebRequest -Uri "http://127.0.0.1:8000/auth/login" -Method OPTIONS -Headers $bad
```

## Production Safety

- No wildcard production CORS added.
- Production still requires explicit `CORS_ALLOWED_ORIGINS`.
- `CORS_ALLOWED_ORIGIN_REGEX` is rejected in production by runtime validation.
- Wildcard `*` remains rejected in production and cannot be combined with credentials.
- Development regex is narrowly scoped to `localhost`/`127.0.0.1` with numeric ports only.

## Remaining Issues / Notes

1. **Live server restart required.** The fix is in code; any already-running FastAPI process on `127.0.0.1:8000` must be restarted to pick up changes.
2. **Live PowerShell preflight not executed against running backend** because port 8000 was not reachable during this session. TestClient verification passed.
3. **Flutter end-to-end login not verified.** Per instruction, no successful login is reported until the Flutter application actually logs in successfully. This fix addresses the CORS/preflight blocker; Flutter login still depends on runtime backend availability, correct credentials/test user, and the rest of the auth flow.
4. **CORS allow headers are explicit and include required headers.** Starlette may include additional safe headers in preflight responses; `Content-Type` and `Authorization` are allowed as required.
5. **If a deployed environment sets `CORS_ALLOWED_ORIGIN_REGEX` in production**, startup will now fail fast with a clear validation error. This is intentional for safety; configure explicit production origins instead.
