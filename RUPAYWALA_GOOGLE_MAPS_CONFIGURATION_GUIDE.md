# RUPAYWALA Google Maps Configuration Guide

## Status

**READ-ONLY investigation. Maps is NOT configured in the current runtime.**  
Do not claim Maps is configured until a real geocoding/distance request succeeds with a valid configured key.

Observed runtime signal (from issue): `/health` reports `integrations.maps.provider=google`, `configured=false`, `key_present=false`, `google_only=true`; `POST /service/geocode` returns `503 Service Unavailable` with detail "Location services are not configured yet. Please contact support."

## 1. Exact Configuration Variable Names

| Variable | Purpose | Default / Required | Where read |
|---|---|---:|---|
| `GOOGLE_MAPS_API_KEY` | **Primary required key**. Server-side Google Maps API key. | Default `""` (empty). Maps considered configured only when non-empty. | `app/config.py:178`, `app/config.py:326-328` |
| `GOOGLE_MAPS_TIMEOUT` | HTTP timeout (seconds) for Google Maps requests. | `10.0` | `app/config.py:179`, `app/services/map_providers/google_maps.py:26,99` |
| `GOOGLE_MAPS_RETRY_LIMIT` | Transient retry count (timeouts/connection/5xx/UNKNOWN_ERROR; not permanent auth/billing/invalid-request failures). | `2` | `app/config.py:180`, `google_maps.py:24,168,267,645` |
| `GOOGLE_MAPS_GEOCODE_CACHE_TTL` | Geocode cache TTL seconds. | `86400` | `app/config.py:181`, `google_maps.py:22,82` |
| `GOOGLE_MAPS_ROUTES_CACHE_TTL` | Routes/distance cache TTL seconds. | `600` | `app/config.py:182`, `google_maps.py:25,81` |
| `GOOGLE_MAPS_PLACES_CACHE_TTL` | Places autocomplete/details cache TTL seconds. | `86400` | `app/config.py:183`, `google_maps.py:23,83-84` |
| `MAP_PROVIDER` | Provider selector; loaded but Google is forced active in code. | `"google"` | `app/config.py:176`; `map_service.py:574` hardcodes `provider="google"` |
| `MAP_GEOCODE_CACHE_TTL_SECONDS` | Legacy/general map geocode TTL fallback. | defaults to `GOOGLE_MAPS_GEOCODE_CACHE_TTL` | `app/config.py:198-200` |
| `MAP_CACHE_TTL_SECONDS` | Legacy/general map cache TTL fallback. | defaults to `GOOGLE_MAPS_ROUTES_CACHE_TTL` | `app/config.py:197` |

**Legacy (not active fallbacks):** `MAPPLS_API_KEY`, `MAPPLS_CLIENT_ID`, `MAPPLS_CLIENT_SECRET`, `MAPPLS_BASE_URL`, `MAPPLS_ROUTING_BASE_URL`, `MAPPLS_TIMEOUT`, `OLA_MAPS_API_KEY`, `OLA_MAPS_BASE_URL`, `OLA_MAPS_TIMEOUT`. `app/config.py:185` states "Legacy provider configuration retained for compatibility; not used as fallbacks."

**.env files (names only):** `.env.example` contains `GOOGLE_MAPS_API_KEY=` and related `GOOGLE_MAPS_*` names. `.env.stage56k` currently has **no `GOOGLE_MAPS_API_KEY` name present** (name-only check); it contains legacy `OPENROUTE_API_KEY/OLA_MAPS_*` names. Do not modify env files as part of this investigation.

## 2. Backend Google Maps APIs Actually Called

All Google calls are made server-side by `app/services/map_providers/google_maps.py` via `httpx.AsyncClient`. The API key is sent as query param for Geocoding and as `X-Goog-Api-Key` header for Places/Routes.

| Feature | Google product / endpoint | Backend method | Used by |
|---|---|---|---|
| Forward geocoding (address -> coordinates) | **Geocoding API**: `GET https://maps.googleapis.com/maps/api/geocode/json?address=...&key=...` | `GoogleMapsService.geocode_address()` | `POST /service/quote` flow through `QuoteService._maps_or_503`/map guard? (quote/service flow uses map service), admin branch create/update when coordinates omitted (`admin_routes.py:646-651,689-751`), direct service `geocode_address` capability |
| Address autocomplete | **Places API (New)**: `POST https://places.googleapis.com/v1/places:autocomplete` with field mask `suggestions.placePrediction.placeId,text,structuredFormat.mainText.text,structuredFormat.secondaryText.text` | `GoogleMapsService.autosuggest()` | `POST /service/geocode` (`service_routes.py:298-315` calls `svc.autosuggest`) |
| Place details (selected place -> validated coordinates/address components) | **Places API (New)**: `GET https://places.googleapis.com/v1/places/{place_id}` with field mask `id,displayName,formattedAddress,location,addressComponents`, optional `sessionToken` | `GoogleMapsService.place_details()` | `POST /service/place-details` (`service_routes.py:318-335`) |
| Driving distance/ETA for one origin-destination pair | **Routes API**: `POST https://routes.googleapis.com/directions/v2:computeRoutes` with field mask `routes.distanceMeters,routes.duration,routes.staticDuration`; travelMode DRIVE, routingPreference TRAFFIC_AWARE, departureTime now UTC | `GoogleMapsService.calculate_distance()` | `POST /service/check-distance`, service request creation distance calc, nearest-branches fallback, quote/service flows (`service_routes.py`, `quote_service.py`) |
| Distance matrix for many origins to one destination | **Routes API**: `POST https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix` with field mask `originIndex,destinationIndex,status,condition,distanceMeters,duration,staticDuration`; batched by 625 elements | `GoogleMapsService.distances_from_origin()` | `POST /service/nearest-branches` (`service_routes.py:402-465`) |

## 3. Flutter Frontend Google Maps APIs Actually Called

**None directly.** Flutter does not call Google Maps/Places/Routes endpoints directly and does not include Google Maps browser SDK keys.

Evidence:
- `rupaywala_app/pubspec.yaml`: no `google_maps_flutter`, no Places SDK package match for map/google/places.
- `rupaywala_app/web/index.html`: no `maps.googleapis.com` script.
- Dart code search: no `maps.googleapis.com`, `google_maps_flutter`, `GoogleMapsPlaces`, or direct Maps API usage.
- Flutter uses backend endpoints through `rupaywala_app/lib/core/api/repositories/service_repository.dart`:
  - `POST /service/geocode` (`searchPlaces`) for autocomplete suggestions.
  - `POST /service/nearest-branches` for branch distance ranking.
  - `POST /service/check-distance` for distance quote.
  - `POST /service/quote` for fixed quote.
  - `POST /service/request` for request creation.
- `service_request_screen.dart` displays location search/branch selection and shows backend errors; backend 503 detail "Location services are not configured yet. Please contact support." surfaces to user.

## 4. APIs/Features Used by Rupaywala

| Capability | API required | Notes |
|---|---|---|
| Address search/autocomplete in customer location step | **Places API (New)** | Backend `/service/geocode` name is legacy-ish but implementation uses Places Autocomplete (New), not Geocoding autocomplete. |
| Selected place coordinates/details | **Places API (New)** | `/service/place-details` calls Places Details (New). |
| Admin branch address geocoding when lat/lng omitted | **Geocoding API** | `admin_routes.py` uses `maps.run_async(service.geocode_address(address))`. |
| Road distance and ETA | **Routes API** | `computeRoutes` for single pair; `computeRouteMatrix` for nearest branches. |
| Branch-distance calculations | **Routes API** | `nearest-branches` and `check-distance` require Routes. Distance is road distance, not straight line (`service_routes.py` doc/rules). |

## 5. Branch-Distance Calculations - Additional APIs?

- **No additional APIs beyond Routes API** for distance/ETA calculation itself. `distances_from_origin` uses Routes Distance Matrix; `calculate_distance` uses Routes Directions.
- **Places API (New)** is needed before branch distance if the customer selects an address via autocomplete/place details.
- **Geocoding API** is needed only where address-to-coordinate geocoding is used (e.g., admin branch geocoding, `geocode_address` capability). Customer flow in current Flutter screen uses place suggestions containing lat/lng from backend response shape; place details endpoint exists for detailed place lookup.

## 6. Required Google Cloud Setup / Restrictions / Billing

> Do not enable paid services or create keys as part of this investigation. These are configuration requirements to review/perform in Google Cloud Console by authorized admins.

### Required APIs to enable (project)

1. **Places API (New)** - required for autocomplete and place details (`places.googleapis.com/v1/...`).
2. **Routes API** - required for `directions/v2:computeRoutes` and `distanceMatrix/v2:computeRouteMatrix`.
3. **Geocoding API** - required for `maps/api/geocode/json` geocode_address/admin branch geocoding.

### Billing

- Google Maps Platform APIs require billing enabled on the Google Cloud project. Missing/disabled billing or quota can produce `BillingOrQuotaError`/403/429 mapped by backend.
- Set quotas/budgets/alerts before production use.

### Key restrictions (recommended)

Because calls are **server-side** (backend), use a **server API key** restricted to:
- **Application restriction:** IP address restriction for backend server egress IP(s) (dev/staging/prod as appropriate). Do not use browser referrer restriction for this backend key.
- **API restriction:** restrict key to only required APIs: Places API (New), Routes API, Geocoding API.
- Do not embed this key in Flutter/web/mobile client. Do not commit key to repo.
- Rotate key if exposed.

### Service account?

Not required by current implementation. Code uses API key (`key=` query param / `X-Goog-Api-Key` header).

## 7. Where API Calls Are Made

| Layer | Makes Google Maps API calls? | Details |
|---|---|---|
| FastAPI backend | **Yes** | `app/services/map_providers/google_maps.py` makes server-side HTTPS requests to Google endpoints. |
| Flutter frontend/browser | **No** | Flutter calls Rupaywala backend endpoints only; no Google Maps JS/SDK/browser key usage found. |
| Database | No | Stores coordinates/distances/pricing snapshots; no external Maps calls. |

## 8. Missing API Key / 503 Behavior

**Correctly produces HTTP 503 when not configured.**

- `app/config.py:326-328`: `maps_configured()` returns `bool(GOOGLE_MAPS_API_KEY)`.
- `app/services/map_service.py:568-583`: `get_map_service()` always selects Google; if not configured raises `GoogleNotConfiguredError("Location services are not configured yet. Please contact support.")`.
- `app/routes/service_routes.py:64-88`: `_maps_or_503()` catches `MapProviderNotConfigured` and raises `HTTPException(status_code=503, detail=str(exc))`; map guard also maps provider unavailable to 503.
- `app/services/quote_service.py:349-390`: similar 503 mapping for quote flow.
- `app/routes/admin_routes.py:646-664`: branch geocode maps not-configured/unavailable to 503.

This matches observed behavior: missing key -> 503.

## 9. Mock/Fallback Behavior

- **No active mock provider.**
- **No active Mappls/Ola/OSRM fallback.** Legacy Mappls/Ola classes remain in `map_service.py` for compatibility but are never selected by `get_map_service()` and not used as fallbacks (explicitly stated in config and code comments).
- **Caches:** in-memory TTL caches for geocode/routes/places/autocomplete; successful normalized responses cached; failures not cached. Caches are not mock data.
- **Error mapping:** backend maps provider errors to typed exceptions and HTTP 400/503/404 as appropriate; does not invent coordinates/routes.

## 10. Affected Backend Endpoints

| Endpoint | Requires Maps config | Behavior when missing key |
|---|---|---|
| `POST /service/geocode` | Yes (Places Autocomplete New) | 503 "Location services are not configured yet. Please contact support." |
| `POST /service/place-details` | Yes (Places Details New) | 503 |
| `POST /service/check-distance` | Yes (Routes computeRoutes) | 503 |
| `POST /service/nearest-branches` | Yes (Routes computeRouteMatrix) | 503 |
| `POST /service/quote` | Yes (map/route resolution as needed) | 503 via quote service guard |
| `POST /service/request` | Depends; distance calculation path requires Routes when visit required | 503 on map provider unavailable/not configured |
| Admin branch create/update with omitted coordinates | Yes (Geocoding API) | 503 |

## 11. Safe Testing Commands (after authorized key configuration)

> Do not claim Maps configured until a real request succeeds. Run against local dev backend only after setting `GOOGLE_MAPS_API_KEY` in the environment used by the backend process (do not print secret). Restart backend after env change.

### Health check

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -Method GET
```

Expected after config: `integrations.maps.configured=true`, `key_present=true`.

### Auth (get bearer token) - use disposable dev test user

```powershell
$login = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/auth/login' -Method POST -ContentType 'application/json' -Body (@{identifier='USERNAME'; password='PASSWORD'} | ConvertTo-Json)
$token = $login.access_token
```

### Geocode/autocomplete smoke

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8000/service/geocode' -Method POST -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body (@{query='MG Road Bangalore'} | ConvertTo-Json)
```

### Place details smoke (use place_id from geocode response)

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8000/service/place-details' -Method POST -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body (@{place_id='PLACE_ID'} | ConvertTo-Json)
```

### Nearest branches smoke (requires active branches with lat/lng)

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8000/service/nearest-branches' -Method POST -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body (@{customer_latitude=12.9716; customer_longitude=77.5946} | ConvertTo-Json)
```

### Negative check (missing key)

Before configuration, same endpoints should return 503 with "Location services are not configured yet. Please contact support." (already observed).

## 12. Investigation Files Reviewed

- `app/config.py`
- `app/services/map_service.py`
- `app/services/map_providers/google_maps.py`
- `app/services/map_providers/base.py`
- `app/routes/service_routes.py`
- `app/routes/admin_routes.py` (branch geocode usage)
- `app/services/quote_service.py` (map 503 guard)
- `rupaywala_app/lib/core/api/repositories/service_repository.dart`
- `rupaywala_app/lib/core/models/service_models.dart`
- `rupaywala_app/lib/features/service/service_request_screen.dart`
- `.env.example` (names only)
- `.env.stage56k` (name presence check only; no values)
- `rupaywala_app/pubspec.yaml`, `rupaywala_app/web/index.html` (no direct Google Maps SDK/key)

## 13. Final Assessment

- **Config gap:** `GOOGLE_MAPS_API_KEY` is not present/configured in the active dev-stage env; backend correctly reports unconfigured and returns 503.
- **Code readiness:** Backend has a Google-only server-side implementation for Geocoding, Places API (New), and Routes API; Flutter correctly uses backend endpoints.
- **Required to enable:** Authorized Google Cloud project setup, billing, enable Places API (New) + Routes API + Geocoding API, create restricted server API key, set `GOOGLE_MAPS_API_KEY` in the runtime env, restart backend, then verify with real geocode/distance requests.
- **Not claimed:** Maps configured/enabled/working in production or current runtime.