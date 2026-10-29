"""
Map provider abstraction.

Rupaywala resolves customer locations, branch coordinates and road distances
through Mappls:

    autosuggest      -> location search suggestions
    place details    -> address + lat/lng for the chosen suggestion
    distance matrix  -> ROAD distance (never straight-line) to the branch

Nothing above this module knows which provider is in use. ``get_map_service()``
returns the configured implementation; ``MAPPLS_API_KEY`` (plus client id and
secret) is read from the environment, never hard-coded.

When no provider is configured the service raises ``MapProviderNotConfigured``,
which routes translate into a friendly 503 rather than a stack trace. That keeps
the whole feature testable and lets the app degrade gracefully.
"""

import asyncio
import base64
import hashlib
import logging
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Protocol

import httpx
from jose import jwt as jose_jwt

from app.config import (
    DEBUG,
    MAP_CACHE_TTL_SECONDS,
    MAP_GEOCODE_CACHE_TTL_SECONDS,
    MAP_PROVIDER,
    MAPPLS_API_KEY,
    MAPPLS_BASE_URL,
    MAPPLS_CLIENT_ID,
    MAPPLS_CLIENT_SECRET,
    MAPPLS_ROUTING_BASE_URL,
    MAPPLS_TIMEOUT,
    OLA_MAPS_API_KEY,
    OLA_MAPS_BASE_URL,
    OLA_MAPS_TIMEOUT,
)

logger = logging.getLogger(__name__)


# ======================================================================
# Errors
# ======================================================================
class MapProviderNotConfigured(Exception):
    """No map provider credentials are available."""


class MapProviderError(Exception):
    """The provider responded with an error."""


class MapProviderUnavailable(Exception):
    """The provider could not be reached."""


# ======================================================================
# Value objects
# ======================================================================
@dataclass(frozen=True)
class DistanceResult:
    distance_km: float
    duration_minutes: float


@dataclass(frozen=True)
class PlaceSuggestion:
    place_id: str
    name: str
    address: str
    latitude: float
    longitude: float


@dataclass(frozen=True)
class PlaceDetails:
    place_id: str
    name: str
    address: str
    latitude: float
    longitude: float
    city: str | None = None
    state: str | None = None
    pincode: str | None = None


class MapService(Protocol):
    async def autosuggest(self, query: str, limit: int = 8) -> list[PlaceSuggestion]: ...
    async def place_details(self, place_id: str) -> PlaceDetails: ...
    async def geocode_address(self, address: str) -> PlaceDetails: ...
    async def calculate_distance(
        self, origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
    ) -> DistanceResult: ...
    async def distances_from_origin(
        self, origins: list[tuple[float, float]], dest_lat: float, dest_lng: float
    ) -> list[DistanceResult]: ...


# ======================================================================
# Shared infrastructure
# ======================================================================
def _start_background_loop() -> asyncio.AbstractEventLoop:
    loop = asyncio.new_event_loop()
    threading.Thread(target=loop.run_forever, daemon=True, name="map-loop").start()
    logger.info("Background event loop started for map provider")
    return loop


_loop: asyncio.AbstractEventLoop | None = None
_loop_lock = threading.Lock()


def _background_loop() -> asyncio.AbstractEventLoop:
    global _loop
    with _loop_lock:
        if _loop is None or _loop.is_closed():
            _loop = _start_background_loop()
        return _loop


def run_async(coro):
    """Run a coroutine from synchronous route code (used by admin routes)."""
    return asyncio.run_coroutine_threadsafe(coro, _background_loop()).result(
        timeout=60
    )


class _TTLCache:
    """Tiny thread-safe TTL cache to avoid hammering the paid map APIs."""

    def __init__(self, ttl: int):
        self.ttl = ttl
        self._data: dict[str, object] = {}
        self._stamps: dict[str, float] = {}
        self._lock = threading.Lock()

    def get(self, key: str):
        with self._lock:
            stamp = self._stamps.get(key)
            if stamp is not None and time.time() - stamp < self.ttl:
                return self._data.get(key)
            self._data.pop(key, None)
            self._stamps.pop(key, None)
        return None

    def set(self, key: str, value) -> None:
        with self._lock:
            self._data[key] = value
            self._stamps[key] = time.time()

    def clear(self) -> None:
        with self._lock:
            self._data.clear()
            self._stamps.clear()


def validate_coordinates(lat: float, lng: float, label: str = "coordinate") -> None:
    if lat is None or lng is None:
        raise ValueError(f"Missing {label}")
    if not (-90 <= float(lat) <= 90):
        raise ValueError(f"Invalid {label} latitude: {lat}")
    if not (-180 <= float(lng) <= 180):
        raise ValueError(f"Invalid {label} longitude: {lng}")


# ======================================================================
# Mappls
# ======================================================================
class MapplsService:
    """Mappls (Atlas) Places + Routes implementation."""

    name = "mappls"

    def __init__(self):
        self._client: httpx.AsyncClient | None = None
        self._distance_cache = _TTLCache(MAP_CACHE_TTL_SECONDS)
        self._place_cache = _TTLCache(MAP_GEOCODE_CACHE_TTL_SECONDS)
        self._token_cache: tuple[str, float] | None = None

    # -- lifecycle -----------------------------------------------------
    async def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(MAPPLS_TIMEOUT, connect=5.0),
                headers={
                    "User-Agent": "RupaywalaApp/1.0",
                    "Accept": "application/json",
                },
                limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
            )
        return self._client

    async def aclose(self) -> None:
        if self._client and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    @staticmethod
    def is_configured() -> bool:
        return bool(MAPPLS_API_KEY and MAPPLS_CLIENT_ID and MAPPLS_CLIENT_SECRET)

    def _require_config(self) -> None:
        if not self.is_configured():
            raise MapProviderNotConfigured(
                "Mappls is not configured. Set MAPPLS_API_KEY, MAPPLS_CLIENT_ID "
                "and MAPPLS_CLIENT_SECRET in the environment."
            )

    # -- request signing ----------------------------------------------
    # Mappls Atlas expects `Authorization: mappls <jwt>`. When a client secret
    # is present the token is a short-lived HS256 JWT; otherwise the plain API
    # key is used. Both forms are supported so the integration keeps working
    # with either kind of Mappls account.
    def _auth_header(self) -> str:
        if MAPPLS_CLIENT_SECRET:
            payload = {
                "aud": "mappls",
                "iat": int(time.time()),
                "exp": int(time.time()) + 3600,
            }
            # python-jose is already a dependency and provides HS256 signing, so
            # no extra JWT library is needed here.
            token = jose_jwt.encode(payload, MAPPLS_CLIENT_SECRET, algorithm="HS256")
            return f"mappls {token}"
        return f"mappls {MAPPLS_API_KEY}"

    def _params(self, extra: dict | None = None) -> dict:
        params = {
            "client_id": MAPPLS_CLIENT_ID,
            "client_secret": MAPPLS_CLIENT_SECRET or "",
            "X-Request-Id": str(uuid.uuid4()),
        }
        params.update(extra or {})
        return params

    async def _get_json(self, url: str, params: dict) -> dict:
        client = await self._http()
        try:
            response = await client.get(url, params=params, headers={"Authorization": self._auth_header()})
        except (httpx.TimeoutException, httpx.ConnectError) as exc:
            raise MapProviderUnavailable(f"Mappls is unreachable: {exc}") from exc
        except httpx.HTTPError as exc:
            raise MapProviderError(f"Mappls request failed: {exc}") from exc

        if response.status_code in (401, 403):
            raise MapProviderError("Mappls rejected the API credentials")
        if response.status_code == 429:
            raise MapProviderUnavailable("Mappls rate limit exceeded")
        if response.status_code >= 500:
            raise MapProviderUnavailable(f"Mappls server error {response.status_code}")
        if response.status_code >= 400:
            raise MapProviderError(f"Mappls returned {response.status_code}")

        try:
            return response.json()
        except ValueError as exc:
            raise MapProviderError("Mappls returned a malformed response") from exc

    # -- places --------------------------------------------------------
    async def autosuggest(self, query: str, limit: int = 8) -> list[PlaceSuggestion]:
        self._require_config()
        query = (query or "").strip()
        if len(query) < 3:
            return []

        cached = self._place_cache.get(f"as:{query.lower()}:{limit}")
        if cached is not None:
            return cached

        data = await self._get_json(
            f"{MAPPLS_BASE_URL}/v1/places/autosuggest",
            self._params({"text": query, "size": limit, "filter": "countryCode:ind"}),
        )
        suggestions = self._parse_suggestions(data)
        self._place_cache.set(f"as:{query.lower()}:{limit}", suggestions)
        return suggestions

    @staticmethod
    def _parse_suggestions(data: dict) -> list[PlaceSuggestion]:
        candidates = (
            data.get("suggestions")
            or data.get("results")
            or (data.get("predictions") or [])
        )
        out: list[PlaceSuggestion] = []
        for item in candidates or []:
            if not isinstance(item, dict):
                continue
            location = item.get("location") or {}
            lat = location.get("lat", item.get("latitude", item.get("lat")))
            lng = location.get("lng", item.get("longitude", item.get("lng")))
            if lat is None or lng is None:
                geometry = (item.get("geometry") or {}).get("location") or {}
                lat = geometry.get("lat", lat)
                lng = geometry.get("lng", lng)
            if lat is None or lng is None:
                continue
            name = item.get("name") or item.get("title") or item.get("description") or ""
            address = (
                item.get("address")
                or item.get("formatted_address")
                or item.get("description")
                or name
            )
            if isinstance(address, dict):
                address = address.get("formatted") or str(address)
            out.append(
                PlaceSuggestion(
                    place_id=str(item.get("place_id") or item.get("id") or ""),
                    name=str(name),
                    address=str(address),
                    latitude=round(float(lat), 7),
                    longitude=round(float(lng), 7),
                )
            )
        return out

    async def place_details(self, place_id: str) -> PlaceDetails:
        self._require_config()
        if not place_id:
            raise MapProviderError("A place id is required")

        cached = self._place_cache.get(f"pd:{place_id}")
        if cached is not None:
            return cached

        data = await self._get_json(
            f"{MAPPLS_BASE_URL}/v1/places/details",
            self._params({"place_id": place_id}),
        )
        result = data.get("result") or data.get("place") or data
        details = self._to_details(place_id, result)
        self._place_cache.set(f"pd:{place_id}", details)
        return details

    async def geocode_address(self, address: str) -> PlaceDetails:
        self._require_config()
        address = (address or "").strip()
        if len(address) < 3:
            raise MapProviderError("Enter a more complete address")

        cached = self._place_cache.get(f"geo:{address.lower()}")
        if cached is not None:
            return cached

        data = await self._get_json(
            f"{MAPPLS_BASE_URL}/v1/geocode",
            self._params({"address": address}),
        )
        candidates = data.get("geocoding_results") or data.get("results") or data.get("candidates") or []
        if not candidates:
            raise MapProviderError("No matching location was found for that address")
        details = self._to_details("", candidates[0], fallback_address=address)
        self._place_cache.set(f"geo:{address.lower()}", details)
        return details

    @staticmethod
    def _to_details(place_id: str, raw: dict, fallback_address: str = "") -> PlaceDetails:
        location = raw.get("location") or {}
        lat = location.get("lat", raw.get("latitude", raw.get("lat")))
        lng = location.get("lng", raw.get("longitude", raw.get("lng")))
        if lat is None or lng is None:
            geometry = (raw.get("geometry") or {}).get("location") or {}
            lat = geometry.get("lat", lat)
            lng = geometry.get("lng", lng)
        if lat is None or lng is None:
            raise MapProviderError("The map provider returned a location without coordinates")

        address = raw.get("address") or raw.get("formatted_address") or fallback_address
        if isinstance(address, dict):
            address = address.get("formatted") or str(address)

        return PlaceDetails(
            place_id=str(raw.get("place_id") or raw.get("id") or place_id or ""),
            name=str(raw.get("name") or raw.get("title") or fallback_address or "Selected location"),
            address=str(address),
            latitude=round(float(lat), 7),
            longitude=round(float(lng), 7),
            city=raw.get("city"),
            state=raw.get("state"),
            pincode=raw.get("pincode") or raw.get("postal_code"),
        )

    # -- routes --------------------------------------------------------
    async def calculate_distance(
        self, origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
    ) -> DistanceResult:
        validate_coordinates(origin_lat, origin_lng, "origin")
        validate_coordinates(dest_lat, dest_lng, "destination")

        key = f"{origin_lat},{origin_lng}->{dest_lat},{dest_lng}"
        cached = self._distance_cache.get(key)
        if cached is not None:
            return cached

        data = await self._get_json(
            f"{MAPPLS_ROUTING_BASE_URL}/distance/v1/driving",
            self._params(
                {
                    "origin": f"{origin_lat},{origin_lng}",
                    "destination": f"{dest_lat},{dest_lng}",
                    "alternatives": "false",
                    "left_hand_traffic": "false",
                }
            ),
        )
        results = self._parse_distances(data)
        if not results:
            raise MapProviderError("No road route could be found between these locations")

        result = results[0]
        self._distance_cache.set(key, result)
        return result

    async def distances_from_origin(
        self, origins: list[tuple[float, float]], dest_lat: float, dest_lng: float
    ) -> list[DistanceResult]:
        """Batched distance matrix - one call for N branches."""
        if not origins:
            return []
        validate_coordinates(dest_lat, dest_lng, "destination")

        origin_str = "|".join(f"{lat},{lng}" for lat, lng in origins)
        data = await self._get_json(
            f"{MAPPLS_ROUTING_BASE_URL}/distance/v1/driving",
            self._params(
                {
                    "origin": origin_str,
                    "destination": f"{dest_lat},{dest_lng}",
                    "alternatives": "false",
                    "left_hand_traffic": "false",
                }
            ),
        )
        return self._parse_distances(data)

    @staticmethod
    def _parse_distances(data: dict) -> list[DistanceResult]:
        routes = data.get("routes") or data.get("distances") or data.get("results") or []
        out: list[DistanceResult] = []
        for route in routes:
            if not isinstance(route, dict):
                continue
            distance = route.get("distance")
            duration = route.get("duration")
            if distance is None:
                continue
            out.append(
                DistanceResult(
                    distance_km=round(float(distance) / 1000.0, 2),
                    duration_minutes=round(float(duration or 0) / 60.0, 1),
                )
            )
        return out


# ======================================================================
# Ola Maps (retained fallback so the existing integration keeps working)
# ======================================================================
class OlaMapsService:
    name = "ola"

    def __init__(self):
        self._client: httpx.AsyncClient | None = None
        self._distance_cache = _TTLCache(MAP_CACHE_TTL_SECONDS)
        self._place_cache = _TTLCache(MAP_GEOCODE_CACHE_TTL_SECONDS)

    @staticmethod
    def is_configured() -> bool:
        return bool(OLA_MAPS_API_KEY)

    def _require_config(self) -> None:
        if not self.is_configured():
            raise MapProviderNotConfigured("OLA_MAPS_API_KEY is not configured")

    async def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(OLA_MAPS_TIMEOUT, connect=5.0),
                headers={"User-Agent": "RupaywalaApp/1.0", "Accept": "application/json"},
            )
        return self._client

    async def aclose(self) -> None:
        if self._client and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    async def _get_json(self, url: str, params: dict) -> dict:
        client = await self._http()
        try:
            response = await client.get(url, params=params)
        except (httpx.TimeoutException, httpx.ConnectError) as exc:
            raise MapProviderUnavailable(f"Ola Maps is unreachable: {exc}") from exc
        if response.status_code in (401, 403):
            raise MapProviderError("Ola Maps rejected the API credentials")
        if response.status_code >= 400:
            raise MapProviderUnavailable(f"Ola Maps returned {response.status_code}")
        try:
            return response.json()
        except ValueError as exc:
            raise MapProviderError("Ola Maps returned a malformed response") from exc

    async def autosuggest(self, query: str, limit: int = 8) -> list[PlaceSuggestion]:
        self._require_config()
        query = (query or "").strip()
        if len(query) < 3:
            return []
        data = await self._get_json(
            f"{OLA_MAPS_BASE_URL}/places/v1/autosuggest",
            {"input": query, "api_key": OLA_MAPS_API_KEY},
        )
        out: list[PlaceSuggestion] = []
        for item in (data.get("predictions") or data.get("results") or [])[:limit]:
            location = item.get("geometry", {}).get("location", {})
            out.append(
                PlaceSuggestion(
                    place_id=str(item.get("place_id") or item.get("id") or ""),
                    name=str(item.get("structured_formatting", {}).get("main_text") or item.get("description") or ""),
                    address=str(item.get("description") or ""),
                    latitude=round(float(location.get("lat", 0)), 7),
                    longitude=round(float(location.get("lng", 0)), 7),
                )
            )
        return out

    async def place_details(self, place_id: str) -> PlaceDetails:
        self._require_config()
        data = await self._get_json(
            f"{OLA_MAPS_BASE_URL}/places/v1/details",
            {"place_id": place_id, "api_key": OLA_MAPS_API_KEY},
        )
        result = data.get("result") or data.get("response", {}).get("result") or data
        location = result.get("geometry", {}).get("location", {})
        return PlaceDetails(
            place_id=str(result.get("place_id") or place_id),
            name=str(result.get("name") or ""),
            address=str(result.get("formatted_address") or ""),
            latitude=round(float(location.get("lat", 0)), 7),
            longitude=round(float(location.get("lng", 0)), 7),
        )

    async def geocode_address(self, address: str) -> PlaceDetails:
        self._require_config()
        address = (address or "").strip()
        if len(address) < 3:
            raise MapProviderError("Enter a more complete address")
        cached = self._place_cache.get(f"geo:{address.lower()}")
        if cached is not None:
            return cached
        data = await self._get_json(
            f"{OLA_MAPS_BASE_URL}/places/v1/geocode",
            {"address": address, "api_key": OLA_MAPS_API_KEY},
        )
        results = data.get("geocodingResults", data.get("results", []))
        if not results:
            raise MapProviderError("No matching location was found for that address")
        first = results[0]
        location = first.get("geometry", {}).get("location", {})
        details = PlaceDetails(
            place_id=str(first.get("place_id") or ""),
            name=str(first.get("name") or first.get("formatted_address") or address),
            address=str(first.get("formatted_address") or address),
            latitude=round(float(location.get("lat", 0)), 7),
            longitude=round(float(location.get("lng", 0)), 7),
        )
        self._place_cache.set(f"geo:{address.lower()}", details)
        return details

    async def calculate_distance(
        self, origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
    ) -> DistanceResult:
        validate_coordinates(origin_lat, origin_lng, "origin")
        validate_coordinates(dest_lat, dest_lng, "destination")
        key = f"{origin_lat},{origin_lng}->{dest_lat},{dest_lng}"
        cached = self._distance_cache.get(key)
        if cached is not None:
            return cached

        data = await self._get_json(
            f"{OLA_MAPS_BASE_URL}/routing/v1/distanceMatrix",
            {
                "origins": f"{origin_lat},{origin_lng}",
                "destinations": f"{dest_lat},{dest_lng}",
                "mode": "driving",
                "api_key": OLA_MAPS_API_KEY,
            },
        )
        results = self._parse(data)
        if not results:
            raise MapProviderError("No road route could be found between these locations")
        self._distance_cache.set(key, results[0])
        return results[0]

    async def distances_from_origin(
        self, origins: list[tuple[float, float]], dest_lat: float, dest_lng: float
    ) -> list[DistanceResult]:
        if not origins:
            return []
        validate_coordinates(dest_lat, dest_lng, "destination")
        data = await self._get_json(
            f"{OLA_MAPS_BASE_URL}/routing/v1/distanceMatrix",
            {
                "origins": "|".join(f"{lat},{lng}" for lat, lng in origins),
                "destinations": f"{dest_lat},{dest_lng}",
                "mode": "driving",
                "api_key": OLA_MAPS_API_KEY,
            },
        )
        return self._parse(data)

    @staticmethod
    def _parse(data: dict) -> list[DistanceResult]:
        out: list[DistanceResult] = []
        for row in data.get("rows", []):
            for element in row.get("elements", []):
                if element.get("status") != "OK":
                    continue
                out.append(
                    DistanceResult(
                        distance_km=round(float(element["distance"]) / 1000.0, 2),
                        duration_minutes=round(float(element["duration"]) / 60.0, 1),
                    )
                )
        return out


# ======================================================================
# Selection
# ======================================================================
_instances: dict[str, object] = {}


def get_map_service() -> MapService:
    """Return the configured map provider.

    Raises MapProviderNotConfigured when no credentials are present so callers
    can respond with an honest 503 instead of silently returning fake distances.
    """
    provider = MAP_PROVIDER

    if provider == "mappls":
        service = _instances.get("mappls") or MapplsService()
        if not service.is_configured():
            raise MapProviderNotConfigured(
                "Location services are not configured yet. Please contact support."
            )
        _instances["mappls"] = service
        return service  # type: ignore[return-value]

    if provider == "ola":
        service = _instances.get("ola") or OlaMapsService()
        if not service.is_configured():
            raise MapProviderNotConfigured(
                "Location services are not configured yet. Please contact support."
            )
        _instances["ola"] = service
        return service  # type: ignore[return-value]

    raise MapProviderNotConfigured(
        "Location services are unavailable. Please contact support."
    )


def map_service_status() -> dict:
    """Diagnostics for /health and the admin settings screen."""
    return {
        "provider": MAP_PROVIDER,
        "configured": MAP_PROVIDER in ("mappls", "ola")
        and (
            MapplsService.is_configured() if MAP_PROVIDER == "mappls" else OlaMapsService.is_configured()
        ),
        "key_present": bool(MAPPLS_API_KEY or OLA_MAPS_API_KEY),
        "debug": DEBUG,
    }
