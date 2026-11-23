# RUPAYWALA Routes API 400 - Fix Report

## Status
**Fixed in code and verified with real Google Routes API responses.**

## Confirmed Defect Fixed
Google Routes API rejected TRAFFIC_AWARE route requests because `departureTime` was set to current UTC time, which can be evaluated as past by Google. Error: `INVALID_ARGUMENT - Timestamp must be set to a future time.`

## Changes Made

### 1) Future-safe departureTime buffer (root cause fix)
**File:** `app/services/map_providers/google_maps.py`

- Added `timedelta` import.
- `_build_route_request()` (computeRoutes / `calculate_distance`): changed `departureTime` from `datetime.now(utc)` to `datetime.now(utc) + timedelta(minutes=1)`.
- `_build_route_matrix_request()` (computeRouteMatrix / `distances_from_origin`): same +1 minute future buffer.

Rationale: 1 minute is safely in the future, avoids clock-skew/same-second INVALID_ARGUMENT, and preserves TRAFFIC_AWARE routing intent.

### 2) Routes error extraction for matrix list responses (diagnosability/correctness)
**File:** `app/services/map_providers/google_maps.py`

- Added `_extract_routes_error()` to extract google.rpc.Status-like errors from dict or list payloads. This handles computeRouteMatrix responses where a request-level error is returned as a list element containing `error`.
- Updated `_raise_routes_http_error()` to use the extractor. Prevents masking real Google error as generic "Google Maps could not process the route request" when payload is a list.

### 3) Element-level error handling in distance matrix parsing
**File:** `app/services/map_providers/google_maps.py`

- `distances_from_origin()` now captures request-level error elements (elements with `error`/`status` but no mappable `originIndex`).
- If an origin result is missing and a request-level error element exists, the real error is raised via `_raise_routes_http_error`.
- Per-element handling now checks both `element.error` and truthy `element.status`.

## What Was Not Changed
- No Mappls/other provider fallback added.
- No Google-only architecture changes.
- No nearest-branch sorting/response shape changes in `service_routes.py`.
- No production config changes.
- No `.env`/`.env.stage56k` changes.
- No `rupaywala_ori` changes.
- No auth/payment functionality changes.
- No API keys or sensitive request data logged/returned.

## Security / Exposure Notes
- Probe/test output redacted API key; only sanitized request/response bodies used.
- Existing error mapping still avoids passing raw provider error bodies to callers except controlled mapped messages; added extraction is internal for classification.

## Files Changed
- `app/services/map_providers/google_maps.py`

## Verification Summary
- Real `computeRouteMatrix` call: **200 OK** after fix (previously 400 INVALID_ARGUMENT).
- Real `computeRoutes` call: **200 OK** after fix.
- `POST /service/nearest-branches` via TestClient against dev DB (`rupaywala_dev_stage56k`) with Google-only provider: **200 OK**, returned branch distance from real Routes response.
- Required case matrix: PASS (see `RUPAYWALA_ROUTES_API_TEST_RESULTS.md`).

## Residual Risk / Notes
- Endpoint-level test was run via FastAPI TestClient with dependency override for customer auth and process-loaded env; it exercised the real route, DB, and real Google Routes API. It is not a browser Flutter flow.
- The background dev backend started during validation was not used for the final endpoint proof because its process reported maps not configured; it was stopped.
- `departureTime` is now +1 minute from request time. This is intentional for TRAFFIC_AWARE reliability; traffic ETA remains near-real-time.
