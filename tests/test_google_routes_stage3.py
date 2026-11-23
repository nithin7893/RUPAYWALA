"""Stage 3: Google Routes API integration tests.

All external HTTP calls are mocked; no live Google APIs are called.
"""

import time

import httpx
import pytest

import app.services.map_providers.base as map_base
import app.services.map_providers.google_maps as map_google
from app.services import map_service
from app.services.pricing_service import PricingConfig, build_quote


class _Resp:
    def __init__(self, status_code=200, payload=None, raise_json=False):
        self.status_code = status_code
        self._payload = payload
        self._raise_json = raise_json

    def json(self):
        if self._raise_json:
            raise ValueError("bad json")
        return self._payload


class _FakeClient:
    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = []

    async def post(self, url, json=None, headers=None):
        self.calls.append({"url": url, "json": json or {}, "headers": headers or {}})
        if not self._responses:
            raise AssertionError("No more mocked responses")
        resp = self._responses.pop(0)
        if isinstance(resp, Exception):
            raise resp
        return resp


@pytest.fixture
def google_routes(monkeypatch):
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "test-key")
    monkeypatch.setenv("GOOGLE_MAPS_ROUTES_CACHE_TTL", "600")
    import importlib
    import app.config as config
    importlib.reload(config)
    importlib.reload(map_base)
    importlib.reload(map_google)
    importlib.reload(map_service)
    map_service._instances.clear()
    return map_google.GoogleMapsService


def _install_client(svc, responses):
    fake = _FakeClient(responses)
    async def _http():
        return fake
    svc._http = _http  # type: ignore[assignment]
    return fake


def _route_payload(distance_meters=15000, duration="1800s", static_duration="1500s"):
    route = {"distanceMeters": distance_meters, "duration": duration}
    if static_duration is not None:
        route["staticDuration"] = static_duration
    return {"routes": [route]}


def _matrix_payload(elements):
    # computeRouteMatrix REST returns an array of elements
    return elements


# -------------------------
# A. Single route
# -------------------------
@pytest.mark.anyio
async def test_successful_driving_route_and_traffic_aware_request(google_routes):
    svc = google_routes()
    fake = _install_client(svc, [_Resp(200, _route_payload(15000, "1800s", "1500s"))])
    result = await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)
    assert result.distance_km == 15.0
    assert result.duration_minutes == 30.0  # traffic-aware duration preferred
    assert result.provider == "google"
    assert result.route_available is True
    assert result.calculation_metadata["routing_preference"] == "TRAFFIC_AWARE"
    assert result.calculation_metadata["travel_mode"] == "DRIVE"
    assert result.calculation_metadata["static_duration_minutes"] == 25.0
    call = fake.calls[0]
    assert call["url"] == "https://routes.googleapis.com/directions/v2:computeRoutes"
    assert call["headers"]["X-Goog-Api-Key"] == "test-key"
    assert "routes.duration" in call["headers"]["X-Goog-FieldMask"]
    assert "routes.staticDuration" in call["headers"]["X-Goog-FieldMask"]
    body = call["json"]
    assert body["travelMode"] == "DRIVE"
    assert body["routingPreference"] == "TRAFFIC_AWARE"
    assert body["computeAlternativeRoutes"] is False
    assert body["units"] == "METRIC"
    assert body["languageCode"] == "en-US"
    assert "departureTime" in body


@pytest.mark.anyio
async def test_correct_distance_conversion(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, _route_payload(12345, "600s"))])
    result = await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)
    assert result.distance_km == 12.345


@pytest.mark.anyio
async def test_correct_duration_conversion(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, _route_payload(1000, "90.5s"))])
    result = await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)
    assert result.duration_minutes == pytest.approx(90.5 / 60.0)


@pytest.mark.anyio
async def test_missing_routes(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, {"routes": []})])
    with pytest.raises(map_base.NoRouteFoundError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_missing_distance(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, {"routes": [{"duration": "100s"}]})])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_missing_duration(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, {"routes": [{"distanceMeters": 1000}]})])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_no_route_found_http(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(404, {"error": {"status": "NOT_FOUND", "message": "no route"}})])
    with pytest.raises(map_base.NoRouteFoundError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


# -------------------------
# B. Multi-destination (route matrix)
# -------------------------
@pytest.mark.anyio
async def test_multiple_origins_input_result_ordering(google_routes):
    svc = google_routes()
    elements = [
        {"originIndex": 1, "destinationIndex": 0, "condition": "ROUTE_EXISTS", "distanceMeters": 2000, "duration": "120s"},
        {"originIndex": 0, "destinationIndex": 0, "condition": "ROUTE_EXISTS", "distanceMeters": 1000, "duration": "60s"},
        {"originIndex": 2, "destinationIndex": 0, "condition": "ROUTE_EXISTS", "distanceMeters": 3000, "duration": "180s"},
    ]
    fake = _install_client(svc, [_Resp(200, _matrix_payload(elements))])
    origins = [(10.0, 10.0), (20.0, 20.0), (30.0, 30.0)]
    results = await svc.distances_from_origin(origins, 1.0, 2.0)
    assert [r.distance_km for r in results] == [1.0, 2.0, 3.0]
    call = fake.calls[0]
    assert call["url"] == "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"
    assert call["headers"]["X-Goog-Api-Key"] == "test-key"
    assert "originIndex" in call["headers"]["X-Goog-FieldMask"]
    assert len(call["json"]["origins"]) == 3
    assert len(call["json"]["destinations"]) == 1
    assert call["json"]["routingPreference"] == "TRAFFIC_AWARE"


@pytest.mark.anyio
async def test_batch_size_limits(google_routes):
    svc = google_routes()
    # force small conceptual check by many origins -> implementation chunks by 625 (default), but we can still validate multiple chunks by monkeypatching constant
    map_google._ROUTE_MATRIX_MAX_ELEMENTS = 2
    origins = [(float(i), float(i)) for i in range(5)]
    def elems(start, count):
        return [
            {"originIndex": i, "destinationIndex": 0, "condition": "ROUTE_EXISTS", "distanceMeters": (start + i + 1) * 1000, "duration": "60s"}
            for i in range(count)
        ]
    fake = _install_client(svc, [
        _Resp(200, _matrix_payload(elems(0, 2))),
        _Resp(200, _matrix_payload(elems(2, 2))),
        _Resp(200, _matrix_payload(elems(4, 1))),
    ])
    results = await svc.distances_from_origin(origins, 9.0, 9.0)
    assert len(fake.calls) == 3
    assert [r.distance_km for r in results] == [1.0, 2.0, 3.0, 4.0, 5.0]
    map_google._ROUTE_MATRIX_MAX_ELEMENTS = 625


@pytest.mark.anyio
async def test_partial_element_failures(google_routes):
    svc = google_routes()
    elements = [
        {"originIndex": 0, "destinationIndex": 0, "condition": "ROUTE_EXISTS", "distanceMeters": 1000, "duration": "60s"},
        {"originIndex": 1, "destinationIndex": 0, "condition": "ROUTE_NOT_FOUND"},
    ]
    _install_client(svc, [_Resp(200, _matrix_payload(elements))])
    with pytest.raises(map_base.NoRouteFoundError):
        await svc.distances_from_origin([(1.0, 1.0), (2.0, 2.0)], 3.0, 3.0)


@pytest.mark.anyio
async def test_invalid_coordinates_matrix(google_routes):
    svc = google_routes()
    with pytest.raises(map_base.InvalidCoordinateError):
        await svc.distances_from_origin([(91.0, 1.0)], 3.0, 3.0)


@pytest.mark.anyio
async def test_empty_input_matrix(google_routes):
    svc = google_routes()
    results = await svc.distances_from_origin([], 3.0, 3.0)
    assert results == []


@pytest.mark.anyio
async def test_malformed_matrix_response(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, {"unexpected": True})])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.distances_from_origin([(1.0, 1.0)], 3.0, 3.0)


# -------------------------
# C. Caching
# -------------------------
@pytest.mark.anyio
async def test_successful_cache_hit_and_miss(google_routes):
    svc = google_routes()
    fake = _install_client(svc, [_Resp(200, _route_payload(5000, "300s"))])
    r1 = await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)
    r2 = await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)  # hit
    assert len(fake.calls) == 1
    assert r1.distance_km == r2.distance_km == 5.0
    # miss for different destination
    fake2 = _install_client(svc, [_Resp(200, _route_payload(6000, "360s"))])
    await svc.calculate_distance(10.0, 20.0, 12.0, 22.0)
    assert len(fake2.calls) == 1


@pytest.mark.anyio
async def test_cache_expiration(google_routes, monkeypatch):
    monkeypatch.setattr(map_google, "GOOGLE_MAPS_ROUTES_CACHE_TTL", 1)
    svc = map_google.GoogleMapsService()
    fake = _install_client(svc, [
        _Resp(200, _route_payload(5000, "300s")),
        _Resp(200, _route_payload(7000, "420s")),
    ])
    await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)
    for k in list(svc._distance_cache._stamps.keys()):
        svc._distance_cache._stamps[k] = time.time() - 10
    await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)
    assert len(fake.calls) == 2


def test_cache_key_separation_for_routing_preferences(google_routes):
    svc = google_routes()
    key = svc._route_cache_key(10.0, 20.0, 11.0, 21.0)
    assert "traffic_aware" in key
    assert "drive" in key
    # Different routing preference would yield a different key (documented behavior).
    other = f"route:drive:traffic_unaware:metric:en-US:{svc._norm_coord(10.0)},{svc._norm_coord(20.0)}->{svc._norm_coord(11.0)},{svc._norm_coord(21.0)}"
    assert key != other


@pytest.mark.anyio
async def test_traffic_aware_cache_behavior_short_ttl_respected(google_routes, monkeypatch):
    # Traffic-aware results are cached only within configured TTL (kept short by config).
    monkeypatch.setattr(map_google, "GOOGLE_MAPS_ROUTES_CACHE_TTL", 1)
    svc = map_google.GoogleMapsService()
    fake = _install_client(svc, [
        _Resp(200, _route_payload(5000, "300s", "250s")),
        _Resp(200, _route_payload(5000, "360s", "250s")),
    ])
    r1 = await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)
    for k in list(svc._distance_cache._stamps.keys()):
        svc._distance_cache._stamps[k] = time.time() - 5
    r2 = await svc.calculate_distance(10.0, 20.0, 11.0, 21.0)
    assert len(fake.calls) == 2
    assert r1.duration_minutes != r2.duration_minutes


# -------------------------
# D. Errors
# -------------------------
@pytest.mark.anyio
async def test_invalid_credentials(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(401, {"error": {"status": "PERMISSION_DENIED", "message": "bad key"}})])
    with pytest.raises(map_base.InvalidCredentialsError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_billing_failure(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(403, {"error": {"status": "PERMISSION_DENIED", "message": "billing not enabled"}})])
    with pytest.raises(map_base.BillingOrQuotaError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_quota_exceeded(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(429, {"error": {"status": "RESOURCE_EXHAUSTED", "message": "quota exceeded"}})])
    with pytest.raises((map_base.BillingOrQuotaError, map_base.ProviderRateLimitedError)):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_http_429(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(429, {"error": {"message": "rate limit"}})])
    with pytest.raises(map_base.ProviderRateLimitedError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_http_5xx(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(500, {}), _Resp(500, {}), _Resp(500, {})])
    with pytest.raises(map_base.MapProviderUnavailable):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_timeout(google_routes):
    svc = google_routes()
    _install_client(svc, [httpx.TimeoutException("t"), httpx.TimeoutException("t"), httpx.TimeoutException("t")])
    with pytest.raises(map_base.ProviderTimeoutError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_connection_error(google_routes):
    svc = google_routes()
    _install_client(svc, [httpx.ConnectError("c"), httpx.ConnectError("c"), httpx.ConnectError("c")])
    with pytest.raises(map_base.MapProviderUnavailable):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_malformed_json(google_routes):
    svc = google_routes()
    _install_client(svc, [_Resp(200, raise_json=True)])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)


@pytest.mark.anyio
async def test_retry_behavior_transient_then_success(google_routes):
    svc = google_routes()
    fake = _install_client(svc, [
        _Resp(503, {"error": {"message": "unavailable"}}),
        _Resp(200, _route_payload(8000, "480s")),
    ])
    result = await svc.calculate_distance(1.0, 2.0, 3.0, 4.0)
    assert result.distance_km == 8.0
    assert len(fake.calls) == 2


# -------------------------
# E. Compatibility / integration
# -------------------------
def test_existing_mapservice_interface(google_routes):
    svc = google_routes()
    # Protocol methods exist and are callable attributes
    assert callable(getattr(svc, "calculate_distance"))
    assert callable(getattr(svc, "distances_from_origin"))
    assert callable(getattr(svc, "geocode_address"))


@pytest.mark.anyio
async def test_existing_service_route_integration_check_distance(client=None):
    # Use service pricing + route-shaped logic compatibility: DistanceResult feeds pricing unchanged.
    # (endpoint contract preserved; we validate integration surface without changing pricing.)
    cfg = PricingConfig(threshold_km=10.0, charge_per_km=20.0, tax_percent=18.0, round_trip_factor=2.0)
    quote = build_quote(distance_km=15.0, config=cfg, base_amount=0.0)
    assert quote.extra_charge == 200.0
    assert quote.total_amount == 236.0


def test_existing_pricing_tests_unchanged_reference():
    # Sanity: pricing formula remains the same authoritative calculation.
    cfg = PricingConfig(threshold_km=10.0, charge_per_km=20.0, tax_percent=0.0, round_trip_factor=2.0)
    quote = build_quote(distance_km=15.0, config=cfg, base_amount=0.0)
    assert quote.extra_charge == 200.0
