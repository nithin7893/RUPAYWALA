"""
Shared map provider primitives.

This module defines the stable provider interface and value objects used by the
application. Provider implementations (Google, legacy Mappls/Ola kept for
compatibility) conform to this surface so routes and services never depend on
vendor-specific payloads.
"""

from __future__ import annotations

import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from typing import Protocol

logger = logging.getLogger(__name__)


# ======================================================================
# Errors
# ======================================================================
class MapProviderError(Exception):
    """Base error for map provider failures."""


class MapProviderNotConfigured(MapProviderError):
    """No map provider credentials are available."""


class GoogleNotConfiguredError(MapProviderNotConfigured):
    """Google Maps is not configured."""


class MapProviderUnavailable(MapProviderError):
    """The provider could not be reached or is temporarily unavailable."""


class ProviderTimeoutError(MapProviderUnavailable):
    """The provider request timed out."""


class ProviderRateLimitedError(MapProviderUnavailable):
    """The provider rate limit was exceeded."""


class InvalidCredentialsError(MapProviderError):
    """The provider rejected the configured credentials."""


class BillingOrQuotaError(MapProviderError):
    """The provider rejected the request due to billing or quota issues."""


class NoRouteFoundError(MapProviderError):
    """No road route could be found between locations."""


class MalformedProviderResponseError(MapProviderError):
    """The provider returned an unexpected or malformed response."""


class InvalidCoordinateError(ValueError):
    """A coordinate value is missing or outside its valid range."""


# ======================================================================
# Value objects
# ======================================================================
@dataclass(frozen=True)
class DistanceResult:
    distance_km: float
    duration_minutes: float
    provider: str = "unknown"
    route_available: bool = True
    calculation_metadata: dict | None = None


@dataclass(frozen=True)
class PlaceSuggestion:
    place_id: str
    name: str
    address: str
    # Google Places Autocomplete (New) does not return coordinates. Keeping
    # these optional avoids inventing a location; Place Details provides them.
    latitude: float | None = None
    longitude: float | None = None


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
    country: str | None = None
    # Normalized Google address components (long_name/short_name/types). Never
    # the raw provider payload; omitted when the provider returns none.
    address_components: list[dict] | None = None


class MapService(Protocol):
    async def autosuggest(
        self, query: str, limit: int = 8, session_token: str | None = None
    ) -> list[PlaceSuggestion]: ...

    async def place_details(
        self, place_id: str, session_token: str | None = None
    ) -> PlaceDetails: ...

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


class TTLCache:
    """Tiny thread-safe TTL cache to avoid hammering paid map APIs."""

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
        raise InvalidCoordinateError(f"Missing {label}")
    if not (-90 <= float(lat) <= 90):
        raise InvalidCoordinateError(f"Invalid {label} latitude: {lat}")
    if not (-180 <= float(lng) <= 180):
        raise InvalidCoordinateError(f"Invalid {label} longitude: {lng}")
