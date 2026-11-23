"""Google Maps provider.

Implements the shared :class:`~app.services.map_providers.base.MapService`
interface. Stage 2 integrates Google Geocoding API, Stage 3 integrates the
Routes API and Stage 4 integrates the Places API (New) for autocomplete and
place details.
"""

from __future__ import annotations

import logging
import math
import re
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import quote

import httpx

from app.config import (
    GOOGLE_MAPS_API_KEY,
    GOOGLE_MAPS_GEOCODE_CACHE_TTL,
    GOOGLE_MAPS_PLACES_CACHE_TTL,
    GOOGLE_MAPS_RETRY_LIMIT,
    GOOGLE_MAPS_ROUTES_CACHE_TTL,
    GOOGLE_MAPS_TIMEOUT,
)
from app.services.map_providers.base import (
    BillingOrQuotaError,
    DistanceResult,
    GoogleNotConfiguredError,
    InvalidCoordinateError,
    InvalidCredentialsError,
    MalformedProviderResponseError,
    MapProviderError,
    MapProviderUnavailable,
    NoRouteFoundError,
    PlaceDetails,
    PlaceSuggestion,
    ProviderRateLimitedError,
    ProviderTimeoutError,
    TTLCache,
    validate_coordinates,
)

logger = logging.getLogger(__name__)

_GEOCODE_ENDPOINT = "https://maps.googleapis.com/maps/api/geocode/json"
_ROUTES_ENDPOINT = "https://routes.googleapis.com/directions/v2:computeRoutes"
_ROUTE_MATRIX_ENDPOINT = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"
_ROUTES_FIELD_MASK = "routes.distanceMeters,routes.duration,routes.staticDuration"
_ROUTE_MATRIX_FIELD_MASK = (
    "originIndex,destinationIndex,status,condition,distanceMeters,duration,staticDuration"
)
_ROUTE_MATRIX_MAX_ELEMENTS = 625  # documented Routes API element limit per request (origins*destinations)

# Places API (New)
_PLACES_AUTOCOMPLETE_ENDPOINT = "https://places.googleapis.com/v1/places:autocomplete"
_PLACES_DETAILS_ENDPOINT = "https://places.googleapis.com/v1/places/{place_id}"
_PLACES_AUTOCOMPLETE_FIELD_MASK = (
    "suggestions.placePrediction.placeId,"
    "suggestions.placePrediction.text.text,"
    "suggestions.placePrediction.structuredFormat.mainText.text,"
    "suggestions.placePrediction.structuredFormat.secondaryText.text"
)
# Keep this list minimal: display, address, coordinates and components only.
_PLACES_DETAILS_FIELD_MASK = "id,displayName,formattedAddress,location,addressComponents"
_PLACES_LANGUAGE_CODE = "en"
_MAX_AUTOCOMPLETE_QUERY = 200
_MAX_PLACE_ID_LENGTH = 300
_MAX_SESSION_TOKEN_LENGTH = 128
_PLACE_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")
_SESSION_TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9._~-]+$")


class GoogleMapsService:
    name = "google"

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        self._distance_cache = TTLCache(GOOGLE_MAPS_ROUTES_CACHE_TTL)
        self._geocode_cache = TTLCache(GOOGLE_MAPS_GEOCODE_CACHE_TTL)
        self._place_cache = TTLCache(GOOGLE_MAPS_PLACES_CACHE_TTL)
        self._autocomplete_cache = TTLCache(GOOGLE_MAPS_PLACES_CACHE_TTL)

    @staticmethod
    def is_configured() -> bool:
        return bool(GOOGLE_MAPS_API_KEY)

    def _require_config(self) -> None:
        if not self.is_configured():
            raise GoogleNotConfiguredError(
                "Google Maps is not configured. Set GOOGLE_MAPS_API_KEY in the environment."
            )

    async def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(GOOGLE_MAPS_TIMEOUT, connect=5.0),
                headers={"User-Agent": "RupaywalaApp/1.0", "Accept": "application/json"},
            )
        return self._client

    async def aclose(self) -> None:
        if self._client and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    # ------------------------------------------------------------------
    # Error mapping
    # ------------------------------------------------------------------
    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        status = response.status_code
        if status == 400:
            raise MapProviderError("Google Maps could not process the request")
        if status in (401, 403):
            raise InvalidCredentialsError("Google Maps rejected the API credentials")
        if status == 429:
            raise ProviderRateLimitedError("Google Maps rate limit exceeded")
        if status >= 500:
            raise MapProviderUnavailable(f"Google Maps server error {status}")
        if status >= 400:
            raise MapProviderError(f"Google Maps returned {status}")

    @staticmethod
    def _raise_google_api_status(
        status: str | None, message: str | None = None, *, context: str = "location"
    ) -> None:
        """Map Google API status codes to typed exceptions.

        Does not expose raw provider messages to callers.
        """
        normalized = (status or "").upper()
        if normalized in ("", "OK"):
            return
        if normalized in ("REQUEST_DENIED", "PERMISSION_DENIED"):
            text = (message or "").lower()
            if "billing" in text or "quota" in text:
                raise BillingOrQuotaError("Google Maps billing or quota is unavailable")
            raise InvalidCredentialsError("Google Maps rejected the API credentials")
        if normalized in ("OVER_QUERY_LIMIT", "RESOURCE_EXHAUSTED"):
            text = (message or "").lower()
            if "billing" in text or "quota" in text:
                raise BillingOrQuotaError("Google Maps billing or quota is unavailable")
            raise ProviderRateLimitedError("Google Maps rate limit exceeded")
        if normalized == "ZERO_RESULTS":
            if context == "route":
                raise NoRouteFoundError("No road route could be found between these locations")
            raise NoRouteFoundError("No matching location was found for that address")
        if normalized == "NOT_FOUND":
            if context == "route":
                raise NoRouteFoundError("No road route could be found between these locations")
            raise MapProviderError("Google Maps could not process the request")
        if normalized == "INVALID_REQUEST":
            raise MapProviderError("Google Maps could not process the request")
        if normalized in ("UNKNOWN_ERROR",):
            raise MapProviderUnavailable("Google Maps is temporarily unavailable")
        raise MalformedProviderResponseError("Google Maps returned an unexpected status")

    async def _get_json(self, url: str, params: dict[str, Any]) -> dict[str, Any]:
        """Perform a GET request with bounded retries for transient failures.

        Retries are applied only for timeout/connection/5xx/UNKNOWN_ERROR cases.
        API key and full request URL are never logged.
        """
        client = await self._http()
        attempts = max(int(GOOGLE_MAPS_RETRY_LIMIT), 0) + 1
        last_exc: Exception | None = None
        for attempt in range(attempts):
            try:
                response = await client.get(url, params=params)
            except httpx.TimeoutException as exc:
                last_exc = ProviderTimeoutError("Google Maps request timed out")
                if attempt < attempts - 1:
                    continue
                raise last_exc from exc
            except httpx.RequestError as exc:
                last_exc = MapProviderUnavailable("Google Maps is unreachable")
                if attempt < attempts - 1:
                    continue
                raise last_exc from exc

            try:
                self._raise_for_status(response)
            except ProviderRateLimitedError:
                raise
            except MapProviderUnavailable as exc:
                # Retry transient server-side unavailability (e.g. HTTP 5xx).
                last_exc = exc
                if attempt < attempts - 1:
                    continue
                raise

            try:
                payload = response.json()
            except ValueError as exc:
                raise MalformedProviderResponseError(
                    "Google Maps returned a malformed response"
                ) from exc
            if not isinstance(payload, dict):
                raise MalformedProviderResponseError(
                    "Google Maps returned a malformed response"
                )

            api_status = payload.get("status")
            if (api_status or "").upper() == "UNKNOWN_ERROR" and attempt < attempts - 1:
                continue
            # Do not pass raw provider error messages to callers.
            self._raise_google_api_status(api_status, payload.get("error_message"))
            return payload

        if last_exc:
            raise last_exc
        raise MapProviderUnavailable("Google Maps is temporarily unavailable")

    @staticmethod
    def _extract_routes_error(payload: Any) -> dict[str, Any] | None:
        """Extract a google.rpc.Status-like error from Routes API responses.

        computeRouteMatrix may return a JSON array of elements; on request-level
        errors elements can carry an `error` object instead of route fields.
        """
        if isinstance(payload, dict):
            err = payload.get("error")
            if isinstance(err, dict):
                return err
            # Some error bodies are already status-like.
            if payload.get("message") and (payload.get("status") or payload.get("code")):
                return payload
            return None
        if isinstance(payload, list):
            for element in payload:
                if not isinstance(element, dict):
                    continue
                err = element.get("error")
                if isinstance(err, dict):
                    return err
                if element.get("message") and (element.get("status") or element.get("code")):
                    return element
        return None

    def _raise_routes_http_error(self, response: httpx.Response, payload: Any) -> None:
        """Map Routes API HTTP/error-body responses to typed exceptions."""
        status_code = response.status_code
        message = None
        status = None
        err = self._extract_routes_error(payload)
        if isinstance(err, dict):
            message = err.get("message")
            status = err.get("status")
            details = err.get("details") or []
            # Some errors include google.rpc.ErrorInfo reason in details.
            if isinstance(details, list):
                for detail in details:
                    if isinstance(detail, dict) and detail.get("reason"):
                        message = f"{message or ''} {detail.get('reason')}".strip()
        if isinstance(payload, dict):
            # Fallback for non-standard bodies.
            message = message or payload.get("error_message")
            status = status or payload.get("status")

        # Prefer API status mapping when present.
        if status:
            self._raise_google_api_status(status, message, context="route")

        text = (str(message) if message is not None else "").lower()
        if status_code == 400:
            if "origin" in text:
                raise MapProviderError("Invalid origin for route calculation")
            if "destination" in text:
                raise MapProviderError("Invalid destination for route calculation")
            raise MapProviderError("Google Maps could not process the route request")
        if status_code in (401, 403):
            if "billing" in text or "quota" in text:
                raise BillingOrQuotaError("Google Maps billing or quota is unavailable")
            raise InvalidCredentialsError("Google Maps rejected the API credentials")
        if status_code == 429:
            if "billing" in text or "quota" in text:
                raise BillingOrQuotaError("Google Maps billing or quota is unavailable")
            raise ProviderRateLimitedError("Google Maps rate limit exceeded")
        if status_code == 404:
            raise NoRouteFoundError("No road route could be found between these locations")
        if status_code >= 500:
            raise MapProviderUnavailable(f"Google Maps server error {status_code}")
        raise MapProviderError("Google Maps could not process the route request")

    async def _post_json(
        self, url: str, body: dict[str, Any], field_mask: str
    ) -> Any:
        """POST JSON to Routes API with required headers and bounded retries."""
        client = await self._http()
        attempts = max(int(GOOGLE_MAPS_RETRY_LIMIT), 0) + 1
        last_exc: Exception | None = None
        headers = {
            "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
            "X-Goog-FieldMask": field_mask,
            "Content-Type": "application/json",
        }
        for attempt in range(attempts):
            try:
                response = await client.post(url, json=body, headers=headers)
            except httpx.TimeoutException as exc:
                last_exc = ProviderTimeoutError("Google Maps request timed out")
                if attempt < attempts - 1:
                    continue
                raise last_exc from exc
            except httpx.RequestError as exc:
                last_exc = MapProviderUnavailable("Google Maps is unreachable")
                if attempt < attempts - 1:
                    continue
                raise last_exc from exc

            # Parse payload when possible for error mapping; computeRouteMatrix may
            # return a JSON array.
            payload: Any = None
            try:
                payload = response.json()
            except ValueError:
                payload = None

            if response.status_code >= 400:
                # Retry transient 5xx only.
                if response.status_code >= 500 and attempt < attempts - 1:
                    last_exc = MapProviderUnavailable(
                        f"Google Maps server error {response.status_code}"
                    )
                    continue
                if payload is None:
                    if response.status_code >= 500:
                        raise MapProviderUnavailable(
                            f"Google Maps server error {response.status_code}"
                        )
                    self._raise_for_status(response)
                self._raise_routes_http_error(response, payload)

            if payload is None:
                raise MalformedProviderResponseError(
                    "Google Maps returned a malformed response"
                )

            # Handle top-level error bodies with 200-like envelopes defensively.
            if isinstance(payload, dict) and payload.get("error"):
                self._raise_routes_http_error(response, payload)

            return payload

        if last_exc:
            raise last_exc
        raise MapProviderUnavailable("Google Maps is temporarily unavailable")

    # ------------------------------------------------------------------
    # Routes
    # ------------------------------------------------------------------
    @staticmethod
    def _norm_coord(value: float) -> str:
        return f"{float(value):.7f}"

    def _route_cache_key(self, origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float) -> str:
        # Cache key includes all route options affecting the response.
        return (
            f"route:drive:traffic_aware:metric:en-US:"
            f"{self._norm_coord(origin_lat)},{self._norm_coord(origin_lng)}->"
            f"{self._norm_coord(dest_lat)},{self._norm_coord(dest_lng)}"
        )

    @staticmethod
    def _parse_duration_seconds(value: Any) -> float:
        if value is None:
            raise MalformedProviderResponseError("Route duration is missing")
        if isinstance(value, (int, float)):
            seconds = float(value)
        elif isinstance(value, str):
            m = re.fullmatch(r"\s*(\d+(?:\.\d+)?)s\s*", value)
            if not m:
                raise MalformedProviderResponseError("Route duration format is invalid")
            seconds = float(m.group(1))
        elif isinstance(value, dict):
            # Defensive support for google.protobuf.Duration-like JSON objects.
            seconds = float(value.get("seconds", 0)) + float(value.get("nanos", 0)) / 1_000_000_000
        else:
            raise MalformedProviderResponseError("Route duration format is invalid")
        if not math.isfinite(seconds) or seconds < 0:
            raise MalformedProviderResponseError("Route duration is invalid")
        return seconds

    def _normalize_route(
        self,
        distance_meters: Any,
        duration_value: Any,
        static_duration_value: Any = None,
    ) -> DistanceResult:
        if distance_meters is None:
            raise MalformedProviderResponseError("Route distance is missing")
        try:
            meters = float(distance_meters)
        except (TypeError, ValueError) as exc:
            raise MalformedProviderResponseError("Route distance is invalid") from exc
        if not math.isfinite(meters) or meters < 0:
            raise MalformedProviderResponseError("Route distance is invalid")

        # Traffic-aware ETA: prefer `duration` for TRAFFIC_AWARE responses.
        duration_seconds = self._parse_duration_seconds(duration_value)
        static_seconds: float | None = None
        if static_duration_value is not None:
            try:
                static_seconds = self._parse_duration_seconds(static_duration_value)
            except MalformedProviderResponseError:
                static_seconds = None

        metadata: dict[str, Any] = {
            "travel_mode": "DRIVE",
            "routing_preference": "TRAFFIC_AWARE",
            "traffic_aware": True,
        }
        if static_seconds is not None:
            metadata["static_duration_minutes"] = static_seconds / 60.0
            metadata["traffic_duration_minutes"] = duration_seconds / 60.0

        # Preserve precision internally; do not round before pricing.
        return DistanceResult(
            distance_km=meters / 1000.0,
            duration_minutes=duration_seconds / 60.0,
            provider="google",
            route_available=True,
            calculation_metadata=metadata,
        )

    def _build_route_request(
        self, origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
    ) -> dict[str, Any]:
        # TRAFFIC_AWARE driving routes require a future departureTime. A small
        # buffer avoids 400 INVALID_ARGUMENT "Timestamp must be set to a future
        # time." from clock skew or same-second evaluation.
        departure_time = (
            (datetime.now(timezone.utc) + timedelta(minutes=1))
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
        )
        return {
            "origin": {
                "location": {
                    "latLng": {"latitude": float(origin_lat), "longitude": float(origin_lng)}
                }
            },
            "destination": {
                "location": {
                    "latLng": {"latitude": float(dest_lat), "longitude": float(dest_lng)}
                }
            },
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "computeAlternativeRoutes": False,
            "units": "METRIC",
            "languageCode": "en-US",
            "departureTime": departure_time,
        }

    # ------------------------------------------------------------------
    # Geocoding
    # ------------------------------------------------------------------
    @staticmethod
    def _normalize_address(address: str) -> str:
        return re.sub(r"\s+", " ", (address or "").strip()).lower()

    @staticmethod
    def _extract_component(components: list[dict[str, Any]], *types: str) -> str | None:
        wanted = set(types)
        for component in components or []:
            if not isinstance(component, dict):
                continue
            comp_types = set(component.get("types") or [])
            if comp_types & wanted:
                value = component.get("long_name") or component.get("short_name")
                if value:
                    return str(value)
        return None

    def _normalize_geocode_result(self, result: dict[str, Any], fallback_address: str) -> PlaceDetails:
        if not isinstance(result, dict):
            raise MalformedProviderResponseError("Google Maps returned a malformed response")

        geometry = result.get("geometry") or {}
        location = geometry.get("location") or {}
        lat = location.get("lat")
        lng = location.get("lng")
        if lat is None or lng is None:
            raise MalformedProviderResponseError(
                "Google Maps returned a location without coordinates"
            )
        try:
            lat_f = float(lat)
            lng_f = float(lng)
        except (TypeError, ValueError) as exc:
            raise MalformedProviderResponseError(
                "Google Maps returned invalid coordinates"
            ) from exc
        try:
            validate_coordinates(lat_f, lng_f, "geocoded location")
        except InvalidCoordinateError as exc:
            raise MalformedProviderResponseError(str(exc)) from exc

        components = result.get("address_components") or []
        city = self._extract_component(
            components, "locality", "postal_town", "administrative_area_level_2"
        )
        state = self._extract_component(components, "administrative_area_level_1")
        pincode = self._extract_component(components, "postal_code")
        formatted = str(result.get("formatted_address") or fallback_address).strip()
        name = city or formatted or fallback_address
        place_id = str(result.get("place_id") or "").strip()
        provider_place_id = f"google:{place_id}" if place_id else ""

        return PlaceDetails(
            place_id=provider_place_id,
            name=str(name),
            address=formatted,
            latitude=round(lat_f, 7),
            longitude=round(lng_f, 7),
            city=city,
            state=state,
            pincode=pincode,
        )

    # ------------------------------------------------------------------
    # Places (Autocomplete + Details)
    # ------------------------------------------------------------------
    @staticmethod
    def _normalize_session_token(session_token: str | None) -> str | None:
        """Validate an optional client-supplied autocomplete session token."""
        if session_token is None:
            return None
        if not isinstance(session_token, str):
            raise MapProviderError("Invalid autocomplete session token")
        token = session_token.strip()
        if not token:
            return None
        if (
            len(token) > _MAX_SESSION_TOKEN_LENGTH
            or not _SESSION_TOKEN_PATTERN.fullmatch(token)
        ):
            raise MapProviderError("Invalid autocomplete session token")
        return token

    @staticmethod
    def _strip_place_id_prefix(place_id: str) -> str:
        if not isinstance(place_id, str):
            return ""
        value = place_id.strip()
        if value.lower().startswith("google:"):
            value = value[len("google:") :].strip()
        return value

    def _validate_place_id(self, place_id: str) -> str:
        raw = self._strip_place_id_prefix(place_id)
        if not raw:
            raise MapProviderError("A place id is required")
        if len(raw) > _MAX_PLACE_ID_LENGTH or not _PLACE_ID_PATTERN.fullmatch(raw):
            raise MapProviderError("Invalid place id")
        return raw

    def _autocomplete_cache_key(
        self, query: str, limit: int, session_token: str | None
    ) -> str:
        # No geographic bias/restriction is applied yet, so the fixed markers
        # document that absence and keep keys isolated from future options.
        return (
            f"as:lang={_PLACES_LANGUAGE_CODE}:bias=none:region=none:"
            f"limit={limit}:session={session_token or '-'}:"
            f"q={self._normalize_address(query)}"
        )

    @staticmethod
    def _place_details_cache_key(raw_place_id: str) -> str:
        # Session tokens affect billing, not the returned place content, so they
        # are deliberately excluded from the details cache key.
        return f"pd:{raw_place_id}:fields={_PLACES_DETAILS_FIELD_MASK}"

    @staticmethod
    def _places_error_context(payload: Any) -> tuple[str, str, str]:
        """Extract safely-usable error context without exposing raw payloads."""
        message = ""
        api_status = ""
        extra = ""
        if isinstance(payload, dict):
            error = payload.get("error")
            if isinstance(error, dict):
                message = str(error.get("message") or "")
                api_status = str(error.get("status") or "")
                details = error.get("details")
                if isinstance(details, list):
                    bits: list[str] = []
                    for detail in details:
                        if not isinstance(detail, dict):
                            continue
                        if detail.get("reason"):
                            bits.append(str(detail["reason"]))
                        metadata = detail.get("metadata")
                        if isinstance(metadata, dict):
                            bits.extend(
                                str(value)
                                for value in metadata.values()
                                if value is not None
                            )
                    extra = " ".join(bits)
            else:
                message = str(
                    payload.get("error_message") or payload.get("message") or ""
                )
                api_status = str(payload.get("status") or "")
        return message, api_status, extra

    def _raise_places_http_error(self, status_code: int, payload: Any) -> None:
        """Map Places API HTTP errors to the shared typed error hierarchy."""
        message, api_status, extra = self._places_error_context(payload)
        combined = f"{message} {api_status} {extra}".lower()
        quota_like = any(
            key in combined
            for key in (
                "billing",
                "quota",
                "resource_exhausted",
                "daily limit",
            )
        )
        credential_like = any(
            key in combined
            for key in (
                "api key",
                "api_key",
                "credential",
                "permission",
                "unauthenticated",
                "unauthorized",
                "forbidden",
            )
        )
        if status_code == 400:
            if credential_like:
                raise InvalidCredentialsError(
                    "Google Maps rejected the API credentials"
                )
            raise MapProviderError("Google Maps could not process the place request")
        if status_code in (401, 403):
            if quota_like:
                raise BillingOrQuotaError(
                    "Google Maps billing or quota is unavailable"
                )
            raise InvalidCredentialsError("Google Maps rejected the API credentials")
        if status_code == 404:
            raise NoRouteFoundError("No matching place was found")
        if status_code == 429:
            if "billing" in combined:
                raise BillingOrQuotaError(
                    "Google Maps billing or quota is unavailable"
                )
            raise ProviderRateLimitedError("Google Maps rate limit exceeded")
        if status_code >= 500:
            raise MapProviderUnavailable(f"Google Maps server error {status_code}")
        raise MapProviderError("Google Maps could not process the place request")

    async def _places_request(
        self,
        method: str,
        url: str,
        *,
        field_mask: str,
        body: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> Any:
        """Perform a Places API request with bounded retries for transient errors.

        API keys and full request URLs are never logged. Permanent failures
        (auth, billing, invalid request, not found) are never retried.
        """
        client = await self._http()
        attempts = max(int(GOOGLE_MAPS_RETRY_LIMIT), 0) + 1
        last_exc: Exception | None = None
        headers = {
            "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
            "X-Goog-FieldMask": field_mask,
        }
        if method.upper() == "POST":
            headers["Content-Type"] = "application/json"

        for attempt in range(attempts):
            try:
                if method.upper() == "POST":
                    response = await client.post(url, json=body or {}, headers=headers)
                else:
                    response = await client.get(url, params=params or {}, headers=headers)
            except httpx.TimeoutException as exc:
                last_exc = ProviderTimeoutError("Google Maps request timed out")
                if attempt < attempts - 1:
                    continue
                raise last_exc from exc
            except httpx.RequestError as exc:
                last_exc = MapProviderUnavailable("Google Maps is unreachable")
                if attempt < attempts - 1:
                    continue
                raise last_exc from exc

            payload: Any = None
            try:
                payload = response.json()
            except ValueError:
                payload = None

            if response.status_code >= 400:
                if response.status_code >= 500 and attempt < attempts - 1:
                    last_exc = MapProviderUnavailable(
                        f"Google Maps server error {response.status_code}"
                    )
                    continue
                if payload is None:
                    if response.status_code >= 500:
                        raise MapProviderUnavailable(
                            f"Google Maps server error {response.status_code}"
                        )
                    # Fall back to the shared HTTP status mapping (e.g. 429).
                    self._raise_for_status(response)
                self._raise_places_http_error(response.status_code, payload)

            if payload is None:
                raise MalformedProviderResponseError(
                    "Google Maps returned a malformed response"
                )
            # Defensive handling of error envelopes returned with a 2xx status.
            if isinstance(payload, dict) and payload.get("error"):
                error = payload.get("error")
                error_code = error.get("code") if isinstance(error, dict) else None
                status_code = (
                    error_code
                    if isinstance(error_code, int) and error_code >= 400
                    else 400
                )
                self._raise_places_http_error(status_code, payload)
            return payload

        if last_exc:
            raise last_exc
        raise MapProviderUnavailable("Google Maps is temporarily unavailable")

    def _normalize_autocomplete_suggestions(
        self, payload: Any
    ) -> list[PlaceSuggestion]:
        if not isinstance(payload, dict):
            raise MalformedProviderResponseError(
                "Google Maps returned a malformed response"
            )
        raw_suggestions = payload.get("suggestions")
        if raw_suggestions is None:
            return []
        if not isinstance(raw_suggestions, list):
            raise MalformedProviderResponseError(
                "Google Maps returned a malformed response"
            )

        out: list[PlaceSuggestion] = []
        for item in raw_suggestions:
            if not isinstance(item, dict):
                continue
            prediction = item.get("placePrediction")
            # Query predictions are not places and have no place ID.
            if prediction is None:
                continue
            if not isinstance(prediction, dict):
                raise MalformedProviderResponseError(
                    "Google Maps returned a malformed response"
                )

            raw_place_id = prediction.get("placeId")
            if not isinstance(raw_place_id, str) or not raw_place_id.strip():
                raise MalformedProviderResponseError(
                    "Google Maps returned a suggestion without a place id"
                )
            place_id = self._validate_place_id(raw_place_id)

            text_obj = prediction.get("text")
            full_text = (
                str(text_obj.get("text") or "").strip()
                if isinstance(text_obj, dict)
                else ""
            )
            structured = prediction.get("structuredFormat")
            structured = structured if isinstance(structured, dict) else {}
            main_obj = structured.get("mainText")
            secondary_obj = structured.get("secondaryText")
            main_text = (
                str(main_obj.get("text") or "").strip()
                if isinstance(main_obj, dict)
                else ""
            )
            secondary_text = (
                str(secondary_obj.get("text") or "").strip()
                if isinstance(secondary_obj, dict)
                else ""
            )
            fallback = " ".join(
                part for part in (main_text, secondary_text) if part
            ).strip()
            display_text = full_text or fallback
            if not display_text:
                raise MalformedProviderResponseError(
                    "Google Maps returned a suggestion without text"
                )

            out.append(
                PlaceSuggestion(
                    place_id=f"google:{place_id}",
                    name=main_text or display_text,
                    address=display_text,
                    # Autocomplete never supplies coordinates; do not invent them.
                    latitude=None,
                    longitude=None,
                )
            )
        return out

    @staticmethod
    def _normalize_places_components(raw_components: Any) -> list[dict] | None:
        if raw_components is None:
            return None
        if not isinstance(raw_components, list):
            raise MalformedProviderResponseError(
                "Google Maps returned malformed address components"
            )
        normalized: list[dict] = []
        for component in raw_components:
            if not isinstance(component, dict):
                continue
            types = component.get("types")
            if not isinstance(types, list):
                types = []
            normalized.append(
                {
                    "long_name": component.get("longText")
                    or component.get("long_name"),
                    "short_name": component.get("shortText")
                    or component.get("short_name"),
                    "types": [str(value) for value in types],
                }
            )
        return normalized or None

    def _normalize_place_details(self, payload: Any) -> PlaceDetails:
        if not isinstance(payload, dict):
            raise MalformedProviderResponseError(
                "Google Maps returned a malformed response"
            )

        raw_place_id = payload.get("id")
        if not isinstance(raw_place_id, str) or not raw_place_id.strip():
            raise MalformedProviderResponseError(
                "Google Maps returned place details without a place id"
            )
        place_id = self._validate_place_id(raw_place_id)

        location = payload.get("location")
        if not isinstance(location, dict):
            raise MalformedProviderResponseError(
                "Google Maps returned place details without coordinates"
            )
        lat = location.get("latitude")
        lng = location.get("longitude")
        if lat is None or lng is None:
            raise MalformedProviderResponseError(
                "Google Maps returned place details without coordinates"
            )
        try:
            lat_f = float(lat)
            lng_f = float(lng)
        except (TypeError, ValueError) as exc:
            raise MalformedProviderResponseError(
                "Google Maps returned invalid coordinates"
            ) from exc
        try:
            validate_coordinates(lat_f, lng_f, "place")
        except InvalidCoordinateError as exc:
            raise MalformedProviderResponseError(str(exc)) from exc

        display = payload.get("displayName")
        display_text = ""
        if isinstance(display, dict):
            display_text = str(display.get("text") or "").strip()
        formatted_address = str(payload.get("formattedAddress") or "").strip()

        components = self._normalize_places_components(
            payload.get("addressComponents")
        )
        component_list = components or []
        city = self._extract_component(
            component_list,
            "locality",
            "postal_town",
            "administrative_area_level_2",
        )
        state = self._extract_component(
            component_list, "administrative_area_level_1"
        )
        pincode = self._extract_component(component_list, "postal_code")
        country = self._extract_component(component_list, "country")

        name = display_text or city or formatted_address or place_id
        address = formatted_address or name

        return PlaceDetails(
            place_id=f"google:{place_id}",
            name=name,
            address=address,
            latitude=round(lat_f, 7),
            longitude=round(lng_f, 7),
            city=city,
            state=state,
            pincode=pincode,
            country=country,
            address_components=components,
        )

    async def autosuggest(
        self, query: str, limit: int = 8, session_token: str | None = None
    ) -> list[PlaceSuggestion]:
        """Address autocomplete via Google Places API (New).

        Suggestions never carry coordinates: Google Autocomplete does not return
        them and inventing a location would be unsafe. Call ``place_details`` for
        the selected suggestion to obtain validated coordinates.
        """
        self._require_config()
        normalized_query = re.sub(r"\s+", " ", (query or "").strip())
        if not normalized_query:
            raise MapProviderError("Enter a location to search")
        if len(normalized_query) > _MAX_AUTOCOMPLETE_QUERY:
            raise MapProviderError("Search text is too long")
        if len(normalized_query) < 3:
            # Preserve the pre-existing behaviour: short prefixes are not queried.
            return []

        token = self._normalize_session_token(session_token)
        try:
            requested_limit = int(limit)
        except (TypeError, ValueError):
            requested_limit = 8
        requested_limit = max(1, min(requested_limit, 20))

        cache_key = self._autocomplete_cache_key(
            normalized_query, requested_limit, token
        )
        cached = self._autocomplete_cache.get(cache_key)
        if isinstance(cached, list):
            return list(cached)
        if cached is not None:
            # Prevent malformed/stale non-list cache entries from leaking.
            self._autocomplete_cache._data.pop(cache_key, None)
            self._autocomplete_cache._stamps.pop(cache_key, None)

        body: dict[str, Any] = {
            "input": normalized_query,
            "languageCode": _PLACES_LANGUAGE_CODE,
        }
        if token:
            body["sessionToken"] = token

        payload = await self._places_request(
            "POST",
            _PLACES_AUTOCOMPLETE_ENDPOINT,
            field_mask=_PLACES_AUTOCOMPLETE_FIELD_MASK,
            body=body,
        )
        suggestions = self._normalize_autocomplete_suggestions(payload)[
            :requested_limit
        ]
        # Cache successful normalized results. Do not cache empty results so a
        # newly available place is not hidden for the whole TTL.
        if suggestions:
            self._autocomplete_cache.set(cache_key, suggestions)
        return suggestions

    async def place_details(
        self, place_id: str, session_token: str | None = None
    ) -> PlaceDetails:
        """Fetch validated place details via Google Places API (New)."""
        self._require_config()
        raw_place_id = self._validate_place_id(place_id)
        token = self._normalize_session_token(session_token)

        cache_key = self._place_details_cache_key(raw_place_id)
        cached = self._place_cache.get(cache_key)
        if isinstance(cached, PlaceDetails):
            return cached
        if cached is not None:
            # Prevent malformed/stale cache entries from leaking.
            self._place_cache._data.pop(cache_key, None)
            self._place_cache._stamps.pop(cache_key, None)

        url = _PLACES_DETAILS_ENDPOINT.format(place_id=quote(raw_place_id, safe=""))
        params: dict[str, Any] = {}
        if token:
            params["sessionToken"] = token

        payload = await self._places_request(
            "GET",
            url,
            field_mask=_PLACES_DETAILS_FIELD_MASK,
            params=params,
        )
        details = self._normalize_place_details(payload)
        # Cache successful normalized results only.
        self._place_cache.set(cache_key, details)
        return details

    async def geocode_address(self, address: str) -> PlaceDetails:
        """Forward geocode an address using Google Geocoding API.

        Deterministic result-selection policy:
        - ZERO_RESULTS is treated as no match.
        - Multiple results are treated as ambiguous and rejected to avoid selecting
          an arbitrary location that could affect branch placement or routing.
        - A single result is normalized and returned.

        Successful normalized results are cached by normalized address; provider
        failures are not cached.
        """
        self._require_config()
        address = (address or "").strip()
        if not address:
            raise MapProviderError("An address is required")
        if len(address) < 3:
            raise MapProviderError("Enter a more complete address")

        cache_key = self._normalize_address(address)
        cached = self._geocode_cache.get(cache_key)
        if isinstance(cached, PlaceDetails):
            return cached
        if cached is not None:
            # Prevent malformed/stale non-PlaceDetails cache entries from leaking.
            self._geocode_cache._data.pop(cache_key, None)  # best-effort cleanup
            self._geocode_cache._stamps.pop(cache_key, None)

        payload = await self._get_json(
            _GEOCODE_ENDPOINT,
            {"address": address, "key": GOOGLE_MAPS_API_KEY},
        )
        results = payload.get("results")
        if not isinstance(results, list) or not results:
            # ZERO_RESULTS should have been raised by status mapping; guard anyway.
            raise NoRouteFoundError("No matching location was found for that address")
        if len(results) > 1:
            raise MapProviderError(
                "Multiple locations match this address. Please provide a more specific address."
            )

        details = self._normalize_geocode_result(results[0], fallback_address=address)
        self._geocode_cache.set(cache_key, details)
        return details

    async def calculate_distance(
        self, origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
    ) -> DistanceResult:
        self._require_config()
        validate_coordinates(origin_lat, origin_lng, "origin")
        validate_coordinates(dest_lat, dest_lng, "destination")

        cache_key = self._route_cache_key(origin_lat, origin_lng, dest_lat, dest_lng)
        cached = self._distance_cache.get(cache_key)
        if isinstance(cached, DistanceResult):
            return cached
        if cached is not None:
            # Prevent malformed/stale cache entries from leaking.
            self._distance_cache._data.pop(cache_key, None)
            self._distance_cache._stamps.pop(cache_key, None)

        payload = await self._post_json(
            _ROUTES_ENDPOINT,
            self._build_route_request(origin_lat, origin_lng, dest_lat, dest_lng),
            _ROUTES_FIELD_MASK,
        )
        if not isinstance(payload, dict):
            raise MalformedProviderResponseError("Google Maps returned a malformed response")
        routes = payload.get("routes")
        if not isinstance(routes, list) or not routes:
            raise NoRouteFoundError("No road route could be found between these locations")
        route = routes[0] if isinstance(routes[0], dict) else None
        if route is None:
            raise MalformedProviderResponseError("Google Maps returned a malformed response")

        result = self._normalize_route(
            route.get("distanceMeters"),
            route.get("duration"),
            route.get("staticDuration"),
        )
        # Cache successful normalized route results only.
        self._distance_cache.set(cache_key, result)
        return result

    def _build_route_matrix_request(
        self, origins: list[tuple[float, float]], dest_lat: float, dest_lng: float
    ) -> dict[str, Any]:
        # TRAFFIC_AWARE driving routes require a future departureTime. A small
        # buffer avoids 400 INVALID_ARGUMENT "Timestamp must be set to a future
        # time." from clock skew or same-second evaluation.
        departure_time = (
            (datetime.now(timezone.utc) + timedelta(minutes=1))
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
        )
        return {
            "origins": [
                {
                    "waypoint": {
                        "location": {
                            "latLng": {"latitude": float(lat), "longitude": float(lng)}
                        }
                    }
                }
                for lat, lng in origins
            ],
            "destinations": [
                {
                    "waypoint": {
                        "location": {
                            "latLng": {
                                "latitude": float(dest_lat),
                                "longitude": float(dest_lng),
                            }
                        }
                    }
                }
            ],
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "units": "METRIC",
            "languageCode": "en-US",
            "departureTime": departure_time,
        }

    async def distances_from_origin(
        self, origins: list[tuple[float, float]], dest_lat: float, dest_lng: float
    ) -> list[DistanceResult]:
        self._require_config()
        if not origins:
            return []
        validate_coordinates(dest_lat, dest_lng, "destination")
        for lat, lng in origins:
            validate_coordinates(lat, lng, "origin")

        results: list[DistanceResult | None] = [None] * len(origins)
        missing_indices: list[int] = []
        missing_origins: list[tuple[float, float]] = []

        # Serve cached entries first (per origin->destination pair) to avoid duplicates.
        for idx, (olat, olng) in enumerate(origins):
            key = self._route_cache_key(olat, olng, dest_lat, dest_lng)
            cached = self._distance_cache.get(key)
            if isinstance(cached, DistanceResult):
                results[idx] = cached
            else:
                if cached is not None:
                    self._distance_cache._data.pop(key, None)
                    self._distance_cache._stamps.pop(key, None)
                missing_indices.append(idx)
                missing_origins.append((olat, olng))

        if not missing_indices:
            return [r for r in results if r is not None]  # type: ignore[return-value]

        # Batch computeRouteMatrix requests by element limit (origins * 1 destination).
        chunk_size = max(1, min(_ROUTE_MATRIX_MAX_ELEMENTS, 625))
        offset = 0
        while offset < len(missing_origins):
            chunk = missing_origins[offset : offset + chunk_size]
            chunk_indices = missing_indices[offset : offset + chunk_size]
            payload = await self._post_json(
                _ROUTE_MATRIX_ENDPOINT,
                self._build_route_matrix_request(chunk, dest_lat, dest_lng),
                _ROUTE_MATRIX_FIELD_MASK,
            )
            elements = payload
            if isinstance(payload, dict):
                # Some clients/wrappers may envelope; support common shapes.
                elements = payload.get("elements") or payload.get("routeMatrixElements") or []
            if not isinstance(elements, list):
                raise MalformedProviderResponseError(
                    "Google Maps returned a malformed route matrix response"
                )

            # Map results by originIndex within this chunk; destinationIndex must be 0.
            by_origin: dict[int, dict[str, Any]] = {}
            request_error: dict[str, Any] | None = None
            for element in elements:
                if not isinstance(element, dict):
                    continue
                oi = element.get("originIndex")
                di = element.get("destinationIndex", 0)
                if di not in (0, None):
                    continue
                element_error = element.get("error")
                status = element.get("status")
                if isinstance(oi, int):
                    by_origin[oi] = element
                elif isinstance(element_error, dict) or status:
                    # Request-level error element (no origin mapping) - surface it.
                    request_error = element

            for local_i, global_i in enumerate(chunk_indices):
                element = by_origin.get(local_i)
                if element is None:
                    if request_error is not None:
                        err = request_error.get("error") or request_error.get("status") or {}
                        self._raise_routes_http_error(
                            type("_R", (), {"status_code": 400})(),  # type: ignore[arg-type]
                            {"error": err if isinstance(err, dict) else {"status": err}},
                        )
                    raise MalformedProviderResponseError(
                        "Google Maps returned an incomplete route matrix response"
                    )

                condition = element.get("condition")
                status = element.get("status")
                element_error = element.get("error")
                # Element-level error/status handling (do not invent or misassign).
                if isinstance(element_error, dict) or status:
                    err = element_error if isinstance(element_error, dict) else status
                    self._raise_routes_http_error(
                        # synthesize 400 to route through status mapping
                        type("_R", (), {"status_code": 400})(),  # type: ignore[arg-type]
                        {"error": err if isinstance(err, dict) else {"status": err, "message": element.get("error_message")}},
                    )
                if condition and condition != "ROUTE_EXISTS":
                    raise NoRouteFoundError(
                        "No road route could be found between these locations"
                    )

                result = self._normalize_route(
                    element.get("distanceMeters"),
                    element.get("duration"),
                    element.get("staticDuration"),
                )
                results[global_i] = result
                olat, olng = origins[global_i]
                self._distance_cache.set(
                    self._route_cache_key(olat, olng, dest_lat, dest_lng), result
                )

            offset += chunk_size

        # Predictable correspondence: one result per input origin in input order.
        if any(r is None for r in results):
            raise MalformedProviderResponseError(
                "Google Maps returned an incomplete route matrix response"
            )
        return [r for r in results if r is not None]  # type: ignore[return-value]
