"""Stage 4: Google Places API (New) integration tests.

All external HTTP calls are mocked; no live Google APIs are called.
"""

import dataclasses
import importlib
import time

import httpx
import pytest

import app.config as config
import app.services.map_providers.base as map_base
import app.services.map_providers.google_maps as map_google
from app.services import map_service
from app.utils.jwt_handler import create_access_token
from tests.factories import make_user


# ----------------------------------------------------------------------
# Mock HTTP plumbing
# ----------------------------------------------------------------------
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
    """Supports both the autocomplete POST and the place-details GET."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = []

    async def _next(self):
        if not self._responses:
            raise AssertionError("No more mocked responses")
        resp = self._responses.pop(0)
        if isinstance(resp, Exception):
            raise resp
        return resp

    async def post(self, url, json=None, headers=None):
        self.calls.append(
            {"method": "POST", "url": url, "json": json or {}, "headers": headers or {}}
        )
        return await self._next()

    async def get(self, url, params=None, headers=None):
        self.calls.append(
            {
                "method": "GET",
                "url": url,
                "params": params or {},
                "headers": headers or {},
            }
        )
        return await self._next()


@pytest.fixture
def google_places(monkeypatch):
    monkeypatch.setenv("MAP_PROVIDER", "google")
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "test-places-key")
    monkeypatch.setenv("GOOGLE_MAPS_RETRY_LIMIT", "2")
    monkeypatch.setenv("GOOGLE_MAPS_PLACES_CACHE_TTL", "86400")
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


def _suggestion(
    place_id="ChIJabc123",
    main="MG Road",
    secondary="Bengaluru, Karnataka, India",
    text=None,
):
    prediction = {"placeId": place_id}
    prediction["text"] = {"text": text or f"{main}, {secondary}"}
    structured = {}
    if main is not None:
        structured["mainText"] = {"text": main}
    if secondary is not None:
        structured["secondaryText"] = {"text": secondary}
    prediction["structuredFormat"] = structured
    return {"placePrediction": prediction}


def _autocomplete_payload(suggestions):
    return {"suggestions": suggestions}


def _components():
    return [
        {"longText": "MG Road", "shortText": "MG Rd", "types": ["route"]},
        {
            "longText": "Bengaluru",
            "shortText": "Bengaluru",
            "types": ["locality", "political"],
        },
        {
            "longText": "Karnataka",
            "shortText": "KA",
            "types": ["administrative_area_level_1", "political"],
        },
        {"longText": "560001", "shortText": "560001", "types": ["postal_code"]},
        {"longText": "India", "shortText": "IN", "types": ["country", "political"]},
    ]


def _details_payload(
    place_id="ChIJabc123",
    lat=12.9716,
    lng=77.5946,
    formatted="MG Road, Bengaluru, Karnataka 560001, India",
    display="MG Road",
    components=None,
    include_location=True,
):
    payload = {
        "id": place_id,
        "displayName": {"text": display, "languageCode": "en"},
        "formattedAddress": formatted,
    }
    if include_location:
        payload["location"] = {"latitude": lat, "longitude": lng}
    if components is not None:
        payload["addressComponents"] = components
    return payload


def _auth_headers(user):
    token = create_access_token({"user_id": user.id, "role": user.role.value})
    return {"Authorization": f"Bearer {token}"}


# ======================================================================
# A. Autocomplete
# ======================================================================
@pytest.mark.anyio
async def test_successful_autocomplete_response(google_places):
    svc = google_places()
    fake = _install_client(svc, [_Resp(200, _autocomplete_payload([_suggestion()]))])

    results = await svc.autosuggest("MG Road")

    assert len(results) == 1
    suggestion = results[0]
    assert suggestion.place_id == "google:ChIJabc123"
    assert suggestion.name == "MG Road"
    assert suggestion.address == "MG Road, Bengaluru, Karnataka, India"
    # Autocomplete must never invent coordinates.
    assert suggestion.latitude is None
    assert suggestion.longitude is None

    call = fake.calls[0]
    assert call["method"] == "POST"
    assert call["url"] == "https://places.googleapis.com/v1/places:autocomplete"
    assert call["headers"]["X-Goog-Api-Key"] == "test-places-key"
    assert "suggestions.placePrediction.placeId" in call["headers"]["X-Goog-FieldMask"]
    assert "suggestions.placePrediction.text.text" in call["headers"]["X-Goog-FieldMask"]
    assert call["headers"]["Content-Type"] == "application/json"
    assert call["json"]["input"] == "MG Road"
    assert call["json"]["languageCode"] == "en"
    assert "sessionToken" not in call["json"]


@pytest.mark.anyio
async def test_multiple_suggestions_and_limit(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                200,
                _autocomplete_payload(
                    [
                        _suggestion(place_id="ChIJ1", main="First"),
                        _suggestion(place_id="ChIJ2", main="Second"),
                        _suggestion(place_id="ChIJ3", main="Third"),
                    ]
                ),
            )
        ],
    )
    results = await svc.autosuggest("Main", limit=2)
    assert [r.place_id for r in results] == ["google:ChIJ1", "google:ChIJ2"]


@pytest.mark.anyio
async def test_query_prediction_is_not_returned_as_place(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                200,
                _autocomplete_payload(
                    [
                        {"queryPrediction": {"text": {"text": "coffee near me"}}},
                        _suggestion(place_id="ChIJplace"),
                    ]
                ),
            )
        ],
    )
    results = await svc.autosuggest("coffee")
    assert [r.place_id for r in results] == ["google:ChIJplace"]


@pytest.mark.anyio
async def test_empty_query_rejected(google_places):
    svc = google_places()
    fake = _install_client(svc, [])
    with pytest.raises(map_base.MapProviderError):
        await svc.autosuggest("")
    assert fake.calls == []


@pytest.mark.anyio
async def test_whitespace_only_query_rejected(google_places):
    svc = google_places()
    fake = _install_client(svc, [])
    with pytest.raises(map_base.MapProviderError):
        await svc.autosuggest("    ")
    assert fake.calls == []


@pytest.mark.anyio
async def test_short_query_returns_empty_without_http_call(google_places):
    svc = google_places()
    fake = _install_client(svc, [])
    assert await svc.autosuggest("ab") == []
    assert fake.calls == []


@pytest.mark.anyio
async def test_no_results_returns_empty_list(google_places):
    svc = google_places()
    _install_client(svc, [_Resp(200, {"suggestions": []})])
    assert await svc.autosuggest("Nowhere at all") == []


@pytest.mark.anyio
async def test_autocomplete_suggestion_missing_place_id(google_places):
    svc = google_places()
    _install_client(
        svc,
        [_Resp(200, _autocomplete_payload([{"placePrediction": {"text": {"text": "x"}}}]))],
    )
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_malformed_json(google_places):
    svc = google_places()
    _install_client(svc, [_Resp(200, raise_json=True)])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_invalid_request(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                400,
                {"error": {"status": "INVALID_ARGUMENT", "message": "Invalid request"}},
            )
        ],
    )
    with pytest.raises(map_base.MapProviderError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_invalid_credentials(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                401,
                {"error": {"status": "UNAUTHENTICATED", "message": "bad key"}},
            )
        ],
    )
    with pytest.raises(map_base.InvalidCredentialsError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_billing_or_quota_error(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                403,
                {
                    "error": {
                        "status": "PERMISSION_DENIED",
                        "message": "billing is not enabled for this project",
                    }
                },
            )
        ],
    )
    with pytest.raises(map_base.BillingOrQuotaError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_rate_limited(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                429,
                {"error": {"status": "RESOURCE_EXHAUSTED", "message": "Too many requests"}},
            )
        ],
    )
    with pytest.raises(map_base.ProviderRateLimitedError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_timeout(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            httpx.TimeoutException("t"),
            httpx.TimeoutException("t"),
            httpx.TimeoutException("t"),
        ],
    )
    with pytest.raises(map_base.ProviderTimeoutError):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_connection_error(google_places):
    svc = google_places()
    _install_client(
        svc,
        [httpx.ConnectError("c"), httpx.ConnectError("c"), httpx.ConnectError("c")],
    )
    with pytest.raises(map_base.MapProviderUnavailable):
        await svc.autosuggest("Somewhere")


@pytest.mark.anyio
async def test_autocomplete_retries_transient_error_then_succeeds(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [
            _Resp(503, {"error": {"status": "UNAVAILABLE", "message": "try later"}}),
            _Resp(200, _autocomplete_payload([_suggestion()])),
        ],
    )
    results = await svc.autosuggest("MG Road")
    assert len(results) == 1
    assert len(fake.calls) == 2


@pytest.mark.anyio
async def test_autocomplete_does_not_retry_invalid_credentials(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [_Resp(401, {"error": {"status": "UNAUTHENTICATED", "message": "bad key"}})],
    )
    with pytest.raises(map_base.InvalidCredentialsError):
        await svc.autosuggest("Somewhere")
    assert len(fake.calls) == 1


@pytest.mark.anyio
async def test_autocomplete_session_token_propagation(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [
            _Resp(200, _autocomplete_payload([_suggestion()])),
            _Resp(200, _details_payload()),
        ],
    )
    await svc.autosuggest("MG Road", session_token="session-abc.123")
    assert fake.calls[0]["json"]["sessionToken"] == "session-abc.123"

    # The same token is forwarded to Place Details for the selection.
    await svc.place_details("google:ChIJabc123", session_token="session-abc.123")
    assert fake.calls[1]["method"] == "GET"
    assert fake.calls[1]["params"]["sessionToken"] == "session-abc.123"


@pytest.mark.anyio
async def test_autocomplete_invalid_session_token_rejected(google_places):
    svc = google_places()
    fake = _install_client(svc, [])
    with pytest.raises(map_base.MapProviderError):
        await svc.autosuggest("MG Road", session_token="bad token with spaces")
    assert fake.calls == []


@pytest.mark.anyio
async def test_autocomplete_cache_hit(google_places):
    svc = google_places()
    fake = _install_client(svc, [_Resp(200, _autocomplete_payload([_suggestion()]))])
    first = await svc.autosuggest("MG Road")
    second = await svc.autosuggest("MG Road")
    assert first == second
    assert len(fake.calls) == 1


@pytest.mark.anyio
async def test_autocomplete_cache_expiry(google_places, monkeypatch):
    monkeypatch.setattr(map_google, "GOOGLE_MAPS_PLACES_CACHE_TTL", 1)
    svc = map_google.GoogleMapsService()
    fake = _install_client(
        svc,
        [
            _Resp(200, _autocomplete_payload([_suggestion(main="First")])),
            _Resp(200, _autocomplete_payload([_suggestion(main="Second")])),
        ],
    )
    await svc.autosuggest("MG Road")
    for key in list(svc._autocomplete_cache._stamps.keys()):
        svc._autocomplete_cache._stamps[key] = time.time() - 10
    result = await svc.autosuggest("MG Road")
    assert len(fake.calls) == 2
    assert result[0].name == "Second"


@pytest.mark.anyio
async def test_autocomplete_cache_key_isolation(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [
            _Resp(200, _autocomplete_payload([_suggestion(place_id="ChIJ1")])),
            _Resp(200, _autocomplete_payload([_suggestion(place_id="ChIJ2")])),
            _Resp(200, _autocomplete_payload([_suggestion(place_id="ChIJ3")])),
            _Resp(200, _autocomplete_payload([_suggestion(place_id="ChIJ4")])),
        ],
    )
    # Whitespace/case differences share a normalized cache entry.
    await svc.autosuggest("MG Road")
    await svc.autosuggest("  mg   road  ")
    assert len(fake.calls) == 1
    # Different session token => different cache entry.
    await svc.autosuggest("MG Road", session_token="session-1")
    await svc.autosuggest("MG Road", session_token="session-2")
    # Different limit => different cache entry.
    await svc.autosuggest("MG Road", session_token="session-2", limit=5)
    assert len(fake.calls) == 4


@pytest.mark.anyio
async def test_autocomplete_failure_is_not_cached(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [
            _Resp(404, {"error": {"status": "NOT_FOUND", "message": "nope"}}),
            _Resp(200, _autocomplete_payload([_suggestion()])),
        ],
    )
    with pytest.raises(map_base.MapProviderError):
        await svc.autosuggest("MG Road")
    results = await svc.autosuggest("MG Road")
    assert len(results) == 1
    assert len(fake.calls) == 2


# ======================================================================
# B. Place details
# ======================================================================
@pytest.mark.anyio
async def test_successful_place_details_response(google_places):
    svc = google_places()
    fake = _install_client(
        svc, [_Resp(200, _details_payload(components=_components()))]
    )
    details = await svc.place_details("google:ChIJabc123")

    assert details.place_id == "google:ChIJabc123"
    assert details.name == "MG Road"
    assert details.address == "MG Road, Bengaluru, Karnataka 560001, India"
    assert details.latitude == 12.9716
    assert details.longitude == 77.5946
    assert details.city == "Bengaluru"
    assert details.state == "Karnataka"
    assert details.pincode == "560001"
    assert details.country == "India"
    assert details.address_components is not None
    assert any(
        component["types"] == ["postal_code"]
        for component in details.address_components
    )

    call = fake.calls[0]
    assert call["method"] == "GET"
    assert call["url"] == "https://places.googleapis.com/v1/places/ChIJabc123"
    assert call["headers"]["X-Goog-Api-Key"] == "test-places-key"
    assert call["headers"]["X-Goog-FieldMask"] == (
        "id,displayName,formattedAddress,location,addressComponents"
    )
    # Session token is not sent when the caller did not supply one.
    assert "sessionToken" not in call["params"]


@pytest.mark.anyio
async def test_place_details_latitude_longitude_extraction(google_places):
    svc = google_places()
    _install_client(svc, [_Resp(200, _details_payload(lat=13.0826801, lng=80.2707184))])
    details = await svc.place_details("ChIJabc123")
    assert details.latitude == 13.0826801
    assert details.longitude == 80.2707184


@pytest.mark.anyio
async def test_place_details_raw_and_prefixed_ids_are_equivalent(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [
            _Resp(200, _details_payload(components=_components())),
        ],
    )
    first = await svc.place_details("ChIJabc123")
    second = await svc.place_details("google:ChIJabc123")
    assert first == second
    assert len(fake.calls) == 1
    assert fake.calls[0]["url"] == "https://places.googleapis.com/v1/places/ChIJabc123"


@pytest.mark.anyio
async def test_place_details_missing_optional_components(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                200,
                _details_payload(
                    display="Some Place",
                    formatted="Some Address",
                    components=None,
                ),
            )
        ],
    )
    details = await svc.place_details("ChIJabc123")
    assert details.city is None
    assert details.state is None
    assert details.pincode is None
    assert details.country is None
    assert details.address_components is None


@pytest.mark.anyio
async def test_place_details_missing_coordinates(google_places):
    svc = google_places()
    _install_client(
        svc, [_Resp(200, _details_payload(include_location=False))]
    )
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_invalid_coordinates(google_places):
    svc = google_places()
    _install_client(svc, [_Resp(200, _details_payload(lat=123.0, lng=10.0))])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
@pytest.mark.parametrize(
    "place_id",
    ["", "   ", "google:", "bad id", "../etc/passwd", "id/with/slash", "x" * 301],
)
async def test_place_details_invalid_place_id(google_places, place_id):
    svc = google_places()
    fake = _install_client(svc, [])
    with pytest.raises(map_base.MapProviderError):
        await svc.place_details(place_id)
    assert fake.calls == []


@pytest.mark.anyio
async def test_place_details_not_found(google_places):
    svc = google_places()
    _install_client(
        svc,
        [_Resp(404, {"error": {"status": "NOT_FOUND", "message": "place not found"}})],
    )
    with pytest.raises(map_base.NoRouteFoundError):
        await svc.place_details("ChIJmissing")


@pytest.mark.anyio
async def test_place_details_malformed_response(google_places):
    svc = google_places()
    _install_client(svc, [_Resp(200, {})])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_malformed_json(google_places):
    svc = google_places()
    _install_client(svc, [_Resp(200, raise_json=True)])
    with pytest.raises(map_base.MalformedProviderResponseError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_credentials_error(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                403,
                {"error": {"status": "PERMISSION_DENIED", "message": "bad credentials"}},
            )
        ],
    )
    with pytest.raises(map_base.InvalidCredentialsError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_billing_error(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            _Resp(
                403,
                {
                    "error": {
                        "status": "PERMISSION_DENIED",
                        "message": "billing not enabled",
                    }
                },
            )
        ],
    )
    with pytest.raises(map_base.BillingOrQuotaError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_timeout(google_places):
    svc = google_places()
    _install_client(
        svc,
        [
            httpx.TimeoutException("t"),
            httpx.TimeoutException("t"),
            httpx.TimeoutException("t"),
        ],
    )
    with pytest.raises(map_base.ProviderTimeoutError):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_connection_error(google_places):
    svc = google_places()
    _install_client(
        svc,
        [httpx.ConnectError("c"), httpx.ConnectError("c"), httpx.ConnectError("c")],
    )
    with pytest.raises(map_base.MapProviderUnavailable):
        await svc.place_details("ChIJabc123")


@pytest.mark.anyio
async def test_place_details_cache_hit(google_places):
    svc = google_places()
    fake = _install_client(
        svc, [_Resp(200, _details_payload(components=_components()))]
    )
    first = await svc.place_details("ChIJabc123")
    second = await svc.place_details("google:ChIJabc123")
    assert first == second
    assert len(fake.calls) == 1


@pytest.mark.anyio
async def test_place_details_cache_expiry(google_places, monkeypatch):
    monkeypatch.setattr(map_google, "GOOGLE_MAPS_PLACES_CACHE_TTL", 1)
    svc = map_google.GoogleMapsService()
    fake = _install_client(
        svc,
        [
            _Resp(200, _details_payload(display="First")),
            _Resp(200, _details_payload(display="Second")),
        ],
    )
    await svc.place_details("ChIJabc123")
    for key in list(svc._place_cache._stamps.keys()):
        svc._place_cache._stamps[key] = time.time() - 10
    details = await svc.place_details("ChIJabc123")
    assert len(fake.calls) == 2
    assert details.name == "Second"


@pytest.mark.anyio
async def test_place_details_cache_keys_ignore_session_token(google_places):
    svc = google_places()
    fake = _install_client(
        svc, [_Resp(200, _details_payload(components=_components()))]
    )
    await svc.place_details("ChIJabc123", session_token="session-1")
    await svc.place_details("ChIJabc123", session_token="session-2")
    # Session tokens affect billing, not content, so details are reused.
    assert len(fake.calls) == 1


@pytest.mark.anyio
async def test_place_details_only_successful_responses_are_cached(google_places):
    svc = google_places()
    fake = _install_client(
        svc,
        [
            _Resp(404, {"error": {"status": "NOT_FOUND", "message": "missing"}}),
            _Resp(200, _details_payload(components=_components())),
        ],
    )
    with pytest.raises(map_base.NoRouteFoundError):
        await svc.place_details("ChIJabc123")
    details = await svc.place_details("ChIJabc123")
    assert details.place_id == "google:ChIJabc123"
    cached = await svc.place_details("ChIJabc123")
    assert cached == details
    assert len(fake.calls) == 2


@pytest.mark.anyio
async def test_place_details_sends_only_minimal_field_mask(google_places):
    svc = google_places()
    fake = _install_client(svc, [_Resp(200, _details_payload(components=_components()))])
    await svc.place_details("ChIJabc123")
    mask = fake.calls[0]["headers"]["X-Goog-FieldMask"]
    assert mask == "id,displayName,formattedAddress,location,addressComponents"
    # No paid/irrelevant field categories are requested.
    for field in ("reviews", "photos", "openingHours", "priceLevel"):
        assert field not in mask


# ======================================================================
# C. Compatibility / endpoints
# ======================================================================
def test_existing_place_suggestion_contract(google_places):
    names = {field.name for field in dataclasses.fields(map_base.PlaceSuggestion)}
    assert {"place_id", "name", "address", "latitude", "longitude"} <= names


def test_existing_place_details_contract(google_places):
    names = {field.name for field in dataclasses.fields(map_base.PlaceDetails)}
    assert {
        "place_id",
        "name",
        "address",
        "latitude",
        "longitude",
        "city",
        "state",
        "pincode",
    } <= names


def test_google_only_provider_selection(google_places):
    service = map_service.get_map_service()
    assert service.name == "google"
    assert isinstance(service, map_google.GoogleMapsService)


def test_google_only_provider_not_configured(google_places, monkeypatch):
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "")
    importlib.reload(config)
    importlib.reload(map_base)
    importlib.reload(map_google)
    importlib.reload(map_service)
    map_service._instances.clear()
    with pytest.raises(map_base.GoogleNotConfiguredError):
        map_service.get_map_service()


def test_geocode_endpoint_contract_unchanged(client, db, google_places):
    customer = make_user(db)
    svc = google_places()
    fake = _install_client(
        svc, [_Resp(200, _autocomplete_payload([_suggestion()]))]
    )
    map_service._instances["google"] = svc

    resp = client.post(
        "/service/geocode",
        headers=_auth_headers(customer),
        json={"query": "MG Road"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert isinstance(body, list) and len(body) == 1
    assert body[0]["place_id"] == "google:ChIJabc123"
    assert body[0]["name"] == "MG Road"
    assert body[0]["address"] == "MG Road, Bengaluru, Karnataka, India"
    # Existing field names are preserved; coordinates are null (not invented).
    assert body[0]["latitude"] is None
    assert body[0]["longitude"] is None
    assert len(fake.calls) == 1


def test_geocode_endpoint_session_token_forwarded(client, db, google_places):
    customer = make_user(db)
    svc = google_places()
    fake = _install_client(
        svc, [_Resp(200, _autocomplete_payload([_suggestion()]))]
    )
    map_service._instances["google"] = svc

    resp = client.post(
        "/service/geocode",
        headers=_auth_headers(customer),
        json={"query": "MG Road", "session_token": "session-xyz"},
    )
    assert resp.status_code == 200, resp.text
    assert fake.calls[0]["json"]["sessionToken"] == "session-xyz"


def test_place_details_endpoint_contract_unchanged(client, db, google_places):
    customer = make_user(db)
    svc = google_places()
    _install_client(svc, [_Resp(200, _details_payload(components=_components()))])
    map_service._instances["google"] = svc

    resp = client.post(
        "/service/place-details",
        headers=_auth_headers(customer),
        json={"place_id": "google:ChIJabc123"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["place_id"] == "google:ChIJabc123"
    assert body["name"] == "MG Road"
    assert body["address"] == "MG Road, Bengaluru, Karnataka 560001, India"
    assert body["latitude"] == 12.9716
    assert body["longitude"] == 77.5946
    assert body["city"] == "Bengaluru"
    assert body["state"] == "Karnataka"
    assert body["pincode"] == "560001"
    assert body["country"] == "India"


def test_place_details_endpoint_session_token_forwarded(client, db, google_places):
    customer = make_user(db)
    svc = google_places()
    fake = _install_client(svc, [_Resp(200, _details_payload())])
    map_service._instances["google"] = svc

    resp = client.post(
        "/service/place-details",
        headers=_auth_headers(customer),
        json={"place_id": "ChIJabc123", "session_token": "session-xyz"},
    )
    assert resp.status_code == 200, resp.text
    assert fake.calls[0]["params"]["sessionToken"] == "session-xyz"


def test_location_endpoints_require_authentication(client):
    geocode = client.post("/service/geocode", json={"query": "MG Road"})
    details = client.post("/service/place-details", json={"place_id": "ChIJabc123"})
    assert geocode.status_code == 401
    assert details.status_code == 401


def test_location_endpoints_reject_admin_role(client, db, google_places):
    from tests.factories import make_admin

    admin = make_admin(db)
    map_service._instances["google"] = google_places()
    geocode = client.post(
        "/service/geocode", headers=_auth_headers(admin), json={"query": "MG Road"}
    )
    details = client.post(
        "/service/place-details",
        headers=_auth_headers(admin),
        json={"place_id": "ChIJabc123"},
    )
    assert geocode.status_code == 403
    assert details.status_code == 403
