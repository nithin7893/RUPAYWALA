# RUPAYWALA Routes API 400 - Root Cause Report

## Status
**Root cause confirmed and fixed.** Real Google Routes API responses now succeed for the tested cases.

## Scope
- Investigation target: `POST /service/nearest-branches` returning 400 due to Google Routes `distanceMatrix/v2:computeRouteMatrix` returning 400.
- Constraints respected: no production config changes, no `rupaywala_ori` modifications, no Google API keys/sensitive request data exposed, no Mappls/other provider fallback, no unrelated auth/payment changes.

## Observed Symptom
- `POST /service/geocode` (Places Autocomplete New) returned 200 OK with configured key.
- `POST https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix` returned 400 Bad Request.
- `POST /service/nearest-branches` returned 400 Bad Request.

## Sanitized Reproduction Evidence
Controlled probe (same request shape as `GoogleMapsService._build_route_matrix_request`, API key redacted):

Request (sanitized):
```json
{
  "origins": [{"waypoint": {"location": {"latLng": {"latitude": 16.508254, "longitude": 80.639119}}}}],
  "destinations": [{"waypoint": {"location": {"latLng": {"latitude": 16.5062, "longitude": 80.648}}}}],
  "travelMode": "DRIVE",
  "routingPreference": "TRAFFIC_AWARE",
  "units": "METRIC",
  "languageCode": "en-US",
  "departureTime": "2026-11-22T05:49:03Z"
}
```
Field mask: `originIndex,destinationIndex,status,condition,distanceMeters,duration,staticDuration`

Google response:
- HTTP 400
- Body:
```json
[
  {
    "error": {
      "code": 400,
      "message": "Timestamp must be set to a future time.",
      "status": "INVALID_ARGUMENT"
    }
  }
]
```

## Root Cause
**Primary defect:** `GoogleMapsService` built `departureTime` as `datetime.now(utc)` (current time) for TRAFFIC_AWARE Routes requests. Google Routes API requires `departureTime` to be set to a future time. Same-second evaluation/clock skew caused the timestamp to be treated as past, producing `INVALID_ARGUMENT: Timestamp must be set to a future time.`

Affected builders:
- `app/services/map_providers/google_maps.py` - `_build_route_request()` (computeRoutes) used `datetime.now(utc)`.
- `app/services/map_providers/google_maps.py` - `_build_route_matrix_request()` (computeRouteMatrix) used `datetime.now(utc)`.

**Secondary masking defect:** error parsing did not fully handle computeRouteMatrix error shape. The 400 response was a JSON array containing an element with an `error` object and no `originIndex`. `_raise_routes_http_error` only parsed dict payloads, so it fell back to generic `MapProviderError("Google Maps could not process the route request")`. `distances_from_origin` also only checked `element.status`, not `element.error`, and treated unmapped error elements as "incomplete route matrix response" before the masking made the message generic.

## Why It Surfaced on Nearest Branches
`/service/nearest-branches` uses `GoogleMapsService.distances_from_origin()` -> `computeRouteMatrix`. The departureTime bug caused matrix requests to fail. Geocode worked because it uses Places API, not Routes API.

## Validation of Cause
After setting `departureTime` to now+5 minutes in a controlled probe (same key/project, same coordinates, sanitized), Google returned HTTP 200 with:
```json
[{
  "originIndex": 0,
  "destinationIndex": 0,
  "status": {},
  "distanceMeters": 1169,
  "duration": "236s",
  "staticDuration": "281s",
  "condition": "ROUTE_EXISTS"
}]
```

## Ruled Out / Not Indicated
- Invalid branch coordinates in dev DB: `rupaywala_dev_stage56k.branches` has 1 active branch `Bhadratha (16.5082540, 80.6391190)` - valid.
- Missing origin/destination latLng serialization: request body showed correct latLng objects.
- Field mask format: unchanged and accepted after timestamp fix.
- Routes API not enabled/billing/quota: error was `INVALID_ARGUMENT` timestamp, not permission/billing/quota; successful response after fix confirms API enabled.
- Request size/element limit: 1 origin x 1 destination is well under 625 element limit.

## Files Inspected
- `app/services/map_providers/google_maps.py`
- `app/services/map_providers/base.py`
- `app/services/map_service.py`
- `app/routes/service_routes.py`
- `app/config.py`
- `app/routes/admin_routes.py` (reference)
- Dev DB `rupaywala_dev_stage56k` branch coordinates (read-only)
