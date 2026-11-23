# RUPAYWALA Routes API 400 - Test Results

## Status Summary
- **Root cause:** Confirmed (departureTime in past -> Google INVALID_ARGUMENT).
- **Fix:** Applied in `app/services/map_providers/google_maps.py`.
- **Real Google Routes API:** **PASS** (actual 200 responses observed).
- **Nearest-branch endpoint:** **PASS** in controlled TestClient run against `rupaywala_dev_stage56k` with real Routes API call.

## Environment / Safety
- DB used for endpoint test: `rupaywala_dev_stage56k` only (process env loaded from `.env.stage56k`; no `.env` overwrite).
- `rupaywala_ori` not modified.
- No production config modified.
- No Google API keys or sensitive request data included in this report.

## Real Routes API Evidence (Sanitized)

### Before fix (controlled probe)
- Endpoint: `https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix`
- HTTP 400
- Error: `INVALID_ARGUMENT - Timestamp must be set to a future time.` (element-level error in array response)

### After fix (controlled probe)
- Same coordinates/request shape with future departureTime buffer.
- HTTP 200
- Body (sanitized): `originIndex=0, destinationIndex=0, condition=ROUTE_EXISTS, distanceMeters=1169, duration=236s, staticDuration=281s, status={}`

## Required Test Cases

| Case | Method | Result | Evidence (sanitized) |
|---|---|---:|---|
| One valid origin and one branch destination | `GoogleMapsService.distances_from_origin` real API | PASS | 1 result: `distance_km=1.169`, `duration_minutes=3.9`, `provider=google`, `route_available=true` |
| Multiple branch destinations | `GoogleMapsService.distances_from_origin` real API (3 origins) | PASS | 3 results returned: `[1.169km/3.9min, 1.076km/3.55min, 3.898km/11.05min]` |
| Missing origin coordinates | `GoogleMapsService.distances_from_origin` with `(None, lng)` | PASS | Raised `InvalidCoordinateError` as expected |
| Invalid branch coordinates | `GoogleMapsService.distances_from_origin` with `(999.0, lng)` | PASS | Raised `InvalidCoordinateError` as expected |
| No available branches | `GoogleMapsService.distances_from_origin` with empty origins | PASS | Returned empty list `[]` |
| Successful distance and duration parsing | From real successful route result | PASS | `distance_km` float > 0, `duration_minutes` float > 0 parsed from Routes response |

## Endpoint Verification

| Test | Result | Evidence |
|---|---:|---|
| `POST /service/nearest-branches` (TestClient, dev DB, customer dependency override, real Google Routes call) | PASS | HTTP 200; httpx log: `POST https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix "HTTP/1.1 200 OK"`; response included `branch_id=1, name=Bhadratha, distance_km=1.169` |
| `POST /service/geocode` | NOT RETESTED in this fix run | Previously reported 200 OK before fix; unaffected by Routes departureTime fix |

## Additional Checks

| Check | Result | Notes |
|---|---:|---|
| `calculate_distance` (computeRoutes) after same departureTime fix | PASS | Real API: `distance_km=1.169`, `duration_minutes=3.85`, `provider=google` |
| Error extraction for matrix list error payload | PASS (code path exercised by before-fix probe) | Before fix, real 400 payload was list-with-error; parsing improved so real error is extractable; root cause resolved by timestamp fix |

## Not Tested / Blocked
- **Flutter/browser nearest-branch UI flow:** NOT TESTED. No browser/UI verification performed.
- **Live running backend endpoint over HTTP with dev launcher:** NOT TESTED. A temporary backend started with the Stage 5.6M launcher reported maps not configured in `/health`; it was stopped. Endpoint proof was obtained via TestClient with real env/DB/Google API.
- **Multiple active branches from DB:** PARTIAL. Dev DB currently has 1 active branch; multiple-destination case was verified by passing multiple valid origin coordinates to the real Routes matrix API.

## Conclusion
Nearest-branch distance matrix calculation is **working in tested backend/service paths** with real Google Routes API 200 responses after the departureTime fix. Do not claim Flutter/browser end-to-end nearest-branch UX until verified in the actual app flow.