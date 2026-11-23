"""Stage 2: Google Geocoding API integration tests.

All external HTTP calls are mocked; no live Google APIs are called.
"""

import time

import httpx
import pytest

from app.models.branch import Branch
import app.services.map_providers.base as map_base
import app.services.map_providers.google_maps as map_google
from app.utils.jwt_handler import create_access_token
from tests.factories import make_admin, make_branch


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

    async def get(self, url, params=None):
        self.calls.append({"url": url, "params": params or {}})
        if not self._responses:
            raise AssertionError("No more mocked responses")
        resp = self._responses.pop(0)
        if isinstance(resp, Exception):
            raise resp
        return resp


@pytest.fixture
def google_key(monkeypatch):
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "test-key")
    # reload config-backed module attributes
    import importlib
    import app.config as config
    import app.services.map_providers.base as base
    import app.services.map_providers.google_maps as gm
    import app.services.map_service as ms

    importlib.reload(config)
    importlib.reload(base)
    importlib.reload(gm)
    importlib.reload(ms)
    ms._instances.clear()
    return gm.GoogleMapsService


def _install_client(svc, responses):
    fake = _FakeClient(responses)
    async def _http():
        return fake
    svc._http = _http  # type: ignore[assignment]
    return fake


def _geocode_payload(results, status="OK", error_message=None):
    p = {"status": status, "results": results}
    if error_message is not None:
        p["error_message"] = error_message
    return p


def _single_result(address="1600 Amphitheatre Parkway, Mountain View, CA, USA", lat=37.4224764, lng=-122.0842499):
    return {
        "place_id": "ChIJ2eUgeAK6j4ARbn5u_wAGqWA",
        "formatted_address": address,
        "address_components": [
            {"long_name": "Mountain View", "short_name": "Mountain View", "types": ["locality", "political"]},
            {"long_name": "California", "short_name": "CA", "types": ["administrative_area_level_1", "political"]},
            {"long_name": "94043", "short_name": "94043", "types": ["postal_code"]},
        ],
        "geometry": {"location": {"lat": lat, "lng": lng}},
    }


def _auth_headers(user):
    token = create_access_token({"user_id": user.id, "role": user.role.value})
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.anyio
async def test_successful_forward_geocoding(google_key):
    svc = google_key()
    fake = _install_client(svc, [_Resp(200, _geocode_payload([_single_result()]))])
    details = await svc.geocode_address("1600 Amphitheatre Parkway")
    assert details.latitude == 37.4224764
    assert details.longitude == -122.0842499
    assert details.address == "1600 Amphitheatre Parkway, Mountain View, CA, USA"
    assert details.city == "Mountain View"
    assert details.state == "California"
    assert details.pincode == "94043"
    assert details.place_id == "google:ChIJ2eUgeAK6j4ARbn5u_wAGqWA"
    assert fake.calls[0]["url"] == "https://maps.googleapis.com/maps/api/geocode/json"
    assert fake.calls[0]["params"]["address"] == "1600 Amphitheatre Parkway"
    assert fake.calls[0]["params"]["key"] == "test-key"


@pytest.mark.anyio
async def test_address_normalization_cache_key(google_key):
    svc = google_key()
    fake = _install_client(svc, [_Resp(200, _geocode_payload([_single_result()]))])
    await svc.geocode_address("  1600   Amphitheatre  Parkway  ")
    await svc.geocode_address("1600 amphitheatre parkway")
    assert len(fake.calls) == 1  # second served from cache by normalized key


@pytest.mark.anyio
async def test_empty_address(google_key):
    svc = google_key()
    with pytest.raises(map_base.MapProviderError):
        await svc.geocode_address("")


@pytest.mark.anyio
async def test_zero_results(google_key):
    svc = google_key()
    _install_client(svc, [_Resp(200, _geocode_payload([], status="ZERO_RESULTS"))])
    with pytest.raises(map_base.NoRouteFoundError):
        await svc.geocode_address("nowhereville 12345")


@pytest.mark.anyio
async def test_multiple_results_rejected_deterministically(google_key):
    svc = google_key()
    r1 = _single_result(address="Addr A")
    r2 = _single_result(address="Addr B")
    _install_client(svc, [_Resp(200, _geocode_payload([r1, r2]))])
    with pytest.raises(map_base.MapProviderError, match="Multiple locations"):
        await svc.geocode_address("Ambiguous Address")


@pytest.mark.anyio
async def test_invalid_coordinates_rejected(google_key):
    svc = google_key()
    bad = _single_result(lat=123.0, lng=10.0)
    _install_client(svc, [_Resp(200, _geocode_payload([bad]))])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.geocode_address("Bad Coords Place")


@pytest.mark.anyio
async def test_missing_geometry(google_key):
    svc = google_key()
    bad = {"formatted_address": "No geom", "address_components": [], "geometry": {}}
    _install_client(svc, [_Resp(200, _geocode_payload([bad]))])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.geocode_address("Missing Geometry Place")


@pytest.mark.anyio
async def test_invalid_api_key(google_key):
    svc = google_key()
    _install_client(svc, [_Resp(200, _geocode_payload([], status="REQUEST_DENIED", error_message="The provided API key is invalid."))])
    with pytest.raises(map_base.InvalidCredentialsError):
        await svc.geocode_address("Some Address")


@pytest.mark.anyio
async def test_billing_quota_error(google_key):
    svc = google_key()
    _install_client(svc, [_Resp(200, _geocode_payload([], status="OVER_QUERY_LIMIT", error_message="You have exceeded your daily request quota for this API."))])
    with pytest.raises(map_base.BillingOrQuotaError):
        await svc.geocode_address("Quota Address")


@pytest.mark.anyio
async def test_http_429(google_key):
    svc = google_key()
    _install_client(svc, [_Resp(429, {})])
    with pytest.raises(map_base.ProviderRateLimitedError):
        await svc.geocode_address("Rate Limited Address")


@pytest.mark.anyio
async def test_http_5xx(google_key):
    svc = google_key()
    _install_client(svc, [_Resp(500, {}), _Resp(500, {}), _Resp(500, {})])
    with pytest.raises(map_base.MapProviderUnavailable):
        await svc.geocode_address("Server Error Address")


@pytest.mark.anyio
async def test_timeout(google_key):
    svc = google_key()
    _install_client(svc, [httpx.TimeoutException("timeout"), httpx.TimeoutException("timeout"), httpx.TimeoutException("timeout")])
    with pytest.raises(map_base.ProviderTimeoutError):
        await svc.geocode_address("Timeout Address")


@pytest.mark.anyio
async def test_connection_error(google_key):
    svc = google_key()
    _install_client(svc, [httpx.ConnectError("boom"), httpx.ConnectError("boom"), httpx.ConnectError("boom")])
    with pytest.raises(map_base.MapProviderUnavailable):
        await svc.geocode_address("Connect Error Address")


@pytest.mark.anyio
async def test_malformed_json(google_key):
    svc = google_key()
    _install_client(svc, [_Resp(200, raise_json=True)])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.geocode_address("Malformed JSON Address")


@pytest.mark.anyio
async def test_cache_hit(google_key):
    svc = google_key()
    fake = _install_client(svc, [_Resp(200, _geocode_payload([_single_result(address="Cached Address")]))])
    d1 = await svc.geocode_address("Cached Address")
    d2 = await svc.geocode_address("Cached Address")
    assert d1.address == d2.address
    assert len(fake.calls) == 1


@pytest.mark.anyio
async def test_cache_expiry(google_key, monkeypatch):
    import app.services.map_providers.google_maps as gm
    monkeypatch.setattr(gm, "GOOGLE_MAPS_GEOCODE_CACHE_TTL", 1)
    svc = gm.GoogleMapsService()
    fake = _install_client(svc, [
        _Resp(200, _geocode_payload([_single_result(address="First")])) ,
        _Resp(200, _geocode_payload([_single_result(address="Second")])) ,
    ])
    await svc.geocode_address("Expiring Address")
    # force expiry
    for k in list(svc._geocode_cache._stamps.keys()):
        svc._geocode_cache._stamps[k] = time.time() - 10
    await svc.geocode_address("Expiring Address")
    assert len(fake.calls) == 2


def test_branch_creation_with_geocoding(client, db, google_key, monkeypatch):
    admin = make_admin(db)
    svc = google_key()
    fake = _install_client(svc, [_Resp(200, _geocode_payload([_single_result(lat=12.9716, lng=77.5946, address="Bangalore, KA, India")]))])
    # make admin route use our service instance
    import app.services.map_service as ms
    ms._instances["google"] = svc
    resp = client.post(
        "/admin/branches/add",
        headers=_auth_headers(admin),
        json={"name": "BLR Branch", "address": "MG Road, Bangalore", "city": "Bangalore", "state": "Karnataka"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert float(body["latitude"]) == 12.9716
    assert float(body["longitude"]) == 77.5946
    assert len(fake.calls) == 1


def test_branch_update_with_changed_address(client, db, google_key):
    admin = make_admin(db)
    branch = make_branch(db, address="Old Address", latitude=10.0, longitude=20.0)
    svc = google_key()
    fake = _install_client(svc, [_Resp(200, _geocode_payload([_single_result(lat=11.1111, lng=22.2222, address="New Geocoded Address")]))])
    import app.services.map_service as ms
    ms._instances["google"] = svc
    resp = client.put(
        f"/admin/branches/{branch.id}",
        headers=_auth_headers(admin),
        json={"address": "New Address Text"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["address"] == "New Address Text"
    assert float(body["latitude"]) == 11.1111
    assert float(body["longitude"]) == 22.2222
    assert len(fake.calls) == 1


def test_branch_update_with_failed_geocoding_preserves_existing(client, db, google_key):
    admin = make_admin(db)
    branch = make_branch(db, address="Old Address", latitude=10.0, longitude=20.0)
    svc = google_key()
    _install_client(svc, [_Resp(200, _geocode_payload([], status="ZERO_RESULTS"))])
    import app.services.map_service as ms
    ms._instances["google"] = svc
    resp = client.put(
        f"/admin/branches/{branch.id}",
        headers=_auth_headers(admin),
        json={"address": "Unknown New Address"},
    )
    assert resp.status_code in (400, 404), resp.text
    db.expire_all()
    refreshed = db.get(Branch, branch.id)
    assert refreshed.address == "Old Address"
    assert float(refreshed.latitude) == 10.0
    assert float(refreshed.longitude) == 20.0


def test_existing_branch_data_preservation_on_unrelated_update(client, db):
    admin = make_admin(db)
    branch = make_branch(db, address="Stable Address", latitude=13.0827, longitude=80.2707, name="Old Name")
    resp = client.put(
        f"/admin/branches/{branch.id}",
        headers=_auth_headers(admin),
        json={"name": "New Name"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["name"] == "New Name"
    assert body["address"] == "Stable Address"
    assert float(body["latitude"]) == 13.0827
    assert float(body["longitude"]) == 80.2707
