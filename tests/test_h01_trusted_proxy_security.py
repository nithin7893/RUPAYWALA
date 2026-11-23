"""H-01 regression tests for trusted-proxy / X-Forwarded-For handling.

The rate limiter must use the verified socket peer by default and may only use
``X-Forwarded-For`` when proxy trust is explicitly enabled *and* the immediate
peer is an allowlisted proxy. All IPs below are RFC 5737 / RFC 3849 examples.
"""

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app import config
from app.utils import rate_limit
from app.utils.proxy import client_ip, is_trusted_peer, normalize_ip

ATTACKER = "198.51.100.99"
PROXY = "10.0.0.1"
PROXY_2 = "10.0.0.2"
CLIENT_V4 = "203.0.113.10"
CLIENT_V6 = "2001:db8::10"


def _request(peer=None, xff=None, xfp=None, path="/auth/login"):
    """Build a bare ASGI request with a controlled socket peer and headers."""
    headers = []
    if xff is not None:
        headers.append((b"x-forwarded-for", xff.encode()))
    if xfp is not None:
        headers.append((b"x-forwarded-proto", xfp.encode()))
    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": path,
        "raw_path": path.encode(),
        "query_string": b"",
        "headers": headers,
        "client": (peer, 50000) if peer else None,
        "server": ("testserver", 80),
    }
    return Request(scope)


@pytest.fixture(autouse=True)
def _isolated_rate_limits():
    rate_limit.reset()
    yield
    rate_limit.reset()


@pytest.fixture()
def trusted_proxy(monkeypatch):
    """Explicitly trust two example proxies (never inferred from the header)."""
    monkeypatch.setattr(config, "TRUST_PROXY_HEADERS", True)
    monkeypatch.setattr(config, "TRUSTED_PROXY_IPS", [PROXY, PROXY_2])
    return (PROXY, PROXY_2)


@pytest.fixture()
def client_from(db):
    """TestClient factory with a controlled socket peer and the test DB bound."""
    from fastapi.testclient import TestClient

    from app.database import get_db
    from app.main import app

    def override_get_db():
        yield db

    app.dependency_overrides[get_db] = override_get_db
    clients = []

    def make(peer):
        instance = TestClient(app, client=(peer, 50000))
        clients.append(instance)
        return instance

    try:
        yield make
    finally:
        for instance in clients:
            instance.close()
        app.dependency_overrides.pop(get_db, None)


# ---------------------------------------------------------------------------
# Identity extraction
# ---------------------------------------------------------------------------
def test_direct_client_without_forwarding_header_uses_peer():
    assert client_ip(_request(CLIENT_V4)) == CLIENT_V4


def test_spoofed_xff_ignored_when_proxy_trust_disabled(monkeypatch):
    monkeypatch.setattr(config, "TRUST_PROXY_HEADERS", False)
    assert client_ip(_request(CLIENT_V4, xff=ATTACKER)) == CLIENT_V4
    assert not is_trusted_peer(_request(CLIENT_V4, xff=ATTACKER))


def test_spoofed_xff_ignored_for_untrusted_peer_even_when_trust_enabled(trusted_proxy):
    request = _request(CLIENT_V4, xff=ATTACKER)
    assert not is_trusted_peer(request)
    assert client_ip(request) == CLIENT_V4


def test_trusted_proxy_honors_single_forwarded_client(trusted_proxy):
    request = _request(PROXY, xff=CLIENT_V4)
    assert is_trusted_peer(request)
    assert client_ip(request) == CLIENT_V4


def test_multiple_forwarded_addresses_skip_trusted_hops(trusted_proxy):
    # Leftmost entry is attacker-controlled; rightmost hops are real proxies.
    header = f"{ATTACKER}, {CLIENT_V4}, {PROXY_2}, {PROXY}"
    assert client_ip(_request(PROXY, xff=header)) == CLIENT_V4


def test_all_forwarded_hops_trusted_falls_back_to_verified_peer(trusted_proxy):
    assert client_ip(_request(PROXY, xff=f"{PROXY_2}, {PROXY}")) == PROXY


def test_ipv4_and_ipv6_are_normalized(trusted_proxy):
    assert normalize_ip("2001:0db8:0000::10") == CLIENT_V6
    assert normalize_ip("::ffff:203.0.113.10") == CLIENT_V4
    assert client_ip(_request(PROXY, xff=f"{CLIENT_V6}, {PROXY}")) == CLIENT_V6
    assert client_ip(_request(CLIENT_V6)) == CLIENT_V6


def test_malformed_or_oversized_forwarding_chain_falls_back(trusted_proxy):
    assert client_ip(_request(PROXY, xff="not-an-ip")) == PROXY
    assert client_ip(_request(PROXY, xff="")) == PROXY
    long_chain = ", ".join([CLIENT_V4] * 33 + [PROXY])
    assert client_ip(_request(PROXY, xff=long_chain)) == PROXY
    oversized = CLIENT_V4 + ", " + ("A" * 5000)
    assert client_ip(_request(PROXY, xff=oversized)) == PROXY


# ---------------------------------------------------------------------------
# Rate limiter behaviour
# ---------------------------------------------------------------------------
def test_users_behind_one_trusted_proxy_get_separate_buckets(trusted_proxy):
    dependency = rate_limit.rate_limit(1, 60, "h01-proxy-users")
    client_a = _request(PROXY, xff=CLIENT_V4)
    client_b = _request(PROXY, xff=CLIENT_V6)

    dependency(client_a)  # allowed
    dependency(client_b)  # different identity, allowed
    with pytest.raises(HTTPException) as exc:
        dependency(client_a)
    assert exc.value.status_code == 429


def test_existing_rate_limit_threshold_and_retry_after_preserved():
    dependency = rate_limit.rate_limit(2, 60, "h01-existing")
    request = _request(CLIENT_V4)

    dependency(request)
    dependency(request)
    with pytest.raises(HTTPException) as exc:
        dependency(request)
    assert exc.value.status_code == 429
    assert exc.value.headers["Retry-After"].isdigit()


def test_rotating_spoofed_xff_does_not_bypass_login_limit(client_from, monkeypatch):
    monkeypatch.setattr(config, "TRUST_PROXY_HEADERS", False)
    client = client_from(ATTACKER)
    statuses = []
    for index in range(11):
        response = client.post(
            "/auth/login",
            json={"identifier": "no-such-user", "password": "wrong-password"},
            headers={"X-Forwarded-For": f"198.51.100.{100 + index}"},
        )
        statuses.append(response.status_code)
    assert statuses[:10] == [401] * 10
    assert statuses[10] == 429
    assert int(response.headers["Retry-After"]) > 0


def test_rotating_spoofed_xff_does_not_bypass_otp_limit(
    client_from, monkeypatch, caplog
):
    from app.routes import auth_routes

    monkeypatch.setattr(config, "TRUST_PROXY_HEADERS", False)
    monkeypatch.setattr(
        auth_routes.OTPService,
        "issue",
        staticmethod(lambda *args, **kwargs: (object(), "123456", True)),
    )
    client = client_from(ATTACKER)
    statuses = []
    for index in range(6):
        response = client.post(
            "/auth/send-otp",
            json={"phone_number": "9999999999"},
            headers={"X-Forwarded-For": f"203.0.113.{100 + index}"},
        )
        statuses.append(response.status_code)
    assert statuses[:5] == [200] * 5
    assert statuses[5] == 429
    # No forwarding header or OTP value is echoed into application logs.
    assert "x-forwarded-for" not in caplog.text.lower()
    assert "123456" not in caplog.text


def test_trusted_proxy_endpoint_limits_are_per_client(client_from, trusted_proxy):
    proxy_client = client_from(PROXY)
    for index in range(10):
        response = proxy_client.post(
            "/auth/login",
            json={"identifier": "no-such-user", "password": "wrong-password"},
            headers={"X-Forwarded-For": f"203.0.113.{100 + index}"},
        )
        assert response.status_code == 401

    # A different client through the same proxy is not throttled.
    other = proxy_client.post(
        "/auth/login",
        json={"identifier": "no-such-user", "password": "wrong-password"},
        headers={"X-Forwarded-For": "203.0.113.200"},
    )
    assert other.status_code == 401
