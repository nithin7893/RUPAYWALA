"""Stage 1: Google Maps provider foundation tests.

All external HTTP calls are mocked; no paid Google APIs are invoked.
"""

import importlib

import pytest

import app.config as config
from app.services import map_service
import app.services.map_providers.base as base
import app.services.map_providers.google_maps as google_maps


class _Resp:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload or {}

    def json(self):
        return self._payload


def _set_google_env(monkeypatch, **overrides):
    values = {
        "MAP_PROVIDER": "google",
        "GOOGLE_MAPS_API_KEY": "test-google-key",
        "GOOGLE_MAPS_TIMEOUT": "7.5",
        "GOOGLE_MAPS_RETRY_LIMIT": "3",
        "GOOGLE_MAPS_GEOCODE_CACHE_TTL": "111",
        "GOOGLE_MAPS_ROUTES_CACHE_TTL": "222",
        "GOOGLE_MAPS_PLACES_CACHE_TTL": "333",
    }
    values.update(overrides)
    for key, value in values.items():
        if value is None:
            monkeypatch.delenv(key, raising=False)
        else:
            monkeypatch.setenv(key, str(value))
    import app.services.map_providers.base as base
    import app.services.map_providers.google_maps as google_maps

    importlib.reload(config)
    importlib.reload(base)
    importlib.reload(google_maps)
    importlib.reload(map_service)
    # reset cached instances
    map_service._instances.clear()
    return config


def test_configuration_loading(monkeypatch):
    cfg = _set_google_env(
        monkeypatch,
        GOOGLE_MAPS_TIMEOUT="12.0",
        GOOGLE_MAPS_RETRY_LIMIT="4",
        GOOGLE_MAPS_GEOCODE_CACHE_TTL="900",
        GOOGLE_MAPS_ROUTES_CACHE_TTL="120",
        GOOGLE_MAPS_PLACES_CACHE_TTL="450",
    )
    assert cfg.MAP_PROVIDER == "google"
    assert cfg.GOOGLE_MAPS_API_KEY == "test-google-key"
    assert cfg.GOOGLE_MAPS_TIMEOUT == 12.0
    assert cfg.GOOGLE_MAPS_RETRY_LIMIT == 4
    assert cfg.GOOGLE_MAPS_GEOCODE_CACHE_TTL == 900
    assert cfg.GOOGLE_MAPS_ROUTES_CACHE_TTL == 120
    assert cfg.GOOGLE_MAPS_PLACES_CACHE_TTL == 450
    assert cfg.maps_configured() is True


def test_missing_api_key_selection_and_status(monkeypatch):
    _set_google_env(monkeypatch, GOOGLE_MAPS_API_KEY="")
    assert config.maps_configured() is False
    with pytest.raises(base.GoogleNotConfiguredError):
        map_service.get_map_service()
    status = map_service.map_service_status()
    assert status["provider"] == "google"
    assert status["configured"] is False
    assert status["key_present"] is False
    assert status.get("google_only") is True


def test_google_only_provider_selection(monkeypatch):
    _set_google_env(monkeypatch, MAP_PROVIDER="mappls")
    svc = map_service.get_map_service()
    assert isinstance(svc, google_maps.GoogleMapsService)
    assert map_service.map_service_status()["provider"] == "google"
    # No Mappls/Ola fallback objects are selected.
    assert "mappls" not in map_service._instances
    assert "ola" not in map_service._instances


def test_typed_exception_mapping_http_status(monkeypatch):
    _set_google_env(monkeypatch)
    svc = google_maps.GoogleMapsService()
    with pytest.raises(base.InvalidCredentialsError):
        svc._raise_for_status(_Resp(401))
    with pytest.raises(base.ProviderRateLimitedError):
        svc._raise_for_status(_Resp(429))
    with pytest.raises(base.MapProviderUnavailable):
        svc._raise_for_status(_Resp(503))
    with pytest.raises(base.MapProviderError):
        svc._raise_for_status(_Resp(400))


def test_typed_exception_mapping_google_status(monkeypatch):
    _set_google_env(monkeypatch)
    svc = google_maps.GoogleMapsService()
    with pytest.raises(base.InvalidCredentialsError):
        svc._raise_google_api_status("REQUEST_DENIED", "bad key")
    with pytest.raises(base.BillingOrQuotaError):
        svc._raise_google_api_status("REQUEST_DENIED", "billing disabled")
    with pytest.raises(base.ProviderRateLimitedError):
        svc._raise_google_api_status("OVER_QUERY_LIMIT", "rate")
    with pytest.raises(base.BillingOrQuotaError):
        svc._raise_google_api_status("OVER_QUERY_LIMIT", "quota exceeded")
    with pytest.raises(base.NoRouteFoundError):
        svc._raise_google_api_status("ZERO_RESULTS")
    with pytest.raises(base.MalformedProviderResponseError):
        svc._raise_google_api_status("SOMETHING_NEW")


def test_coordinate_validation(monkeypatch):
    _set_google_env(monkeypatch)
    with pytest.raises(base.InvalidCoordinateError):
        map_service.validate_coordinates(None, 10.0, "origin")
    with pytest.raises(base.InvalidCoordinateError):
        map_service.validate_coordinates(91.0, 10.0, "origin")
    with pytest.raises(base.InvalidCoordinateError):
        map_service.validate_coordinates(10.0, 181.0, "destination")
    # valid coordinates should not raise
    map_service.validate_coordinates(28.6139, 77.2090, "origin")
