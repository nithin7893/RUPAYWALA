"""Trusted-proxy handling for forwarding headers.

Forwarding headers (``X-Forwarded-For``, ``X-Forwarded-Proto``) are ordinary
HTTP headers and can be set by any client. They are honoured **only** when:

1. ``TRUST_PROXY_HEADERS`` is explicitly enabled, and
2. the immediate TCP peer is a literal IP address listed in
   ``TRUSTED_PROXY_IPS``.

``TRUSTED_PROXY_IPS`` is deployment-specific configuration and must be set by
the operator; this module never guesses or invents a trusted address.
"""

import ipaddress
from typing import Optional

from fastapi import Request

from app import config

# Bound work and the size of derived rate-limit bucket keys. A request with a
# larger/malformed forwarding chain falls back to the verified socket peer.
_MAX_FORWARDED_ENTRIES = 32
_MAX_HEADER_CHARS = 4096
_MAX_PEER_CHARS = 64


def normalize_ip(raw: str) -> Optional[str]:
    """Return a canonical IP string, or ``None`` if *raw* is not an IP literal.

    Names, whitespace-padded garbage and empty values are rejected so that
    attacker-controlled text can never become a rate-limit bucket key. IPv4 and
    IPv6 are both accepted; IPv4-mapped IPv6 addresses are folded to IPv4 so the
    same client cannot obtain two identities by changing address notation.
    """
    if not raw:
        return None
    candidate = raw.strip()
    if not candidate:
        return None
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError:
        # Scoped IPv6 literals (e.g. fe80::1%eth0) are not accepted by
        # ip_address on every supported Python version; retry without the zone.
        if "%" in candidate:
            try:
                address = ipaddress.ip_address(candidate.split("%", 1)[0])
            except ValueError:
                return None
        else:
            return None
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        return str(address.ipv4_mapped)
    return str(address)


def trusted_proxy_ips() -> frozenset[str]:
    """Canonical set of explicitly configured proxy addresses."""
    return frozenset(
        normalized
        for entry in config.TRUSTED_PROXY_IPS
        if (normalized := normalize_ip(entry)) is not None
    )


def peer_ip(request: Request) -> Optional[str]:
    """Canonical IP of the immediate socket peer, if it is an IP literal."""
    host = request.client.host if request.client else None
    return normalize_ip(host) if host else None


def is_trusted_peer(request: Request) -> bool:
    """Whether forwarding headers from this request may be honoured."""
    if not config.TRUST_PROXY_HEADERS:
        return False
    peer = peer_ip(request)
    return peer is not None and peer in trusted_proxy_ips()


def forwarded_client_ip(request: Request) -> Optional[str]:
    """Extract the client IP from ``X-Forwarded-For`` of a trusted request.

    The chain is walked right-to-left (closest hop first). Entries that are
    themselves configured trusted proxies are skipped; the first remaining
    address is the client. This ignores attacker-controlled leftmost entries
    and keeps users behind one proxy in distinct rate-limit buckets.

    Returns ``None`` when the header is absent, oversized, malformed, or lists
    only trusted proxies.
    """
    if not is_trusted_peer(request):
        return None

    header = request.headers.get("x-forwarded-for")
    if not header or len(header) > _MAX_HEADER_CHARS:
        return None

    entries = [entry.strip() for entry in header.split(",")]
    if not entries or len(entries) > _MAX_FORWARDED_ENTRIES:
        return None

    normalized = [normalize_ip(entry) for entry in entries]
    if any(ip is None for ip in normalized):
        # Fail closed: malformed forwarding data must not create a key.
        return None

    trusted = trusted_proxy_ips()
    for ip in reversed(normalized):
        if ip not in trusted:
            return ip
    return None


def client_ip(request: Request) -> str:
    """Return the identity used to key per-client rate limits.

    The verified socket peer is always the default. Forwarding headers are used
    only for an explicitly trusted peer, and only to supply a validated IP.
    """
    peer = peer_ip(request)
    if peer is not None:
        forwarded = forwarded_client_ip(request)
        if forwarded is not None:
            return forwarded
        return peer

    # Non-IP peers (test clients, Unix sockets) are never trusted. Keep their
    # raw value bounded; it came from the transport, not from a request header.
    host = request.client.host if request.client else ""
    return host[:_MAX_PEER_CHARS] if host else "unknown"
