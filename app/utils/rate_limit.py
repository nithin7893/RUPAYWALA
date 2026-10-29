"""Rate limiting.

Two layers are used:

* ``hit()`` - the primitive, useful inside a service.
* ``rate_limit()`` - a FastAPI dependency that throttles a route by client IP
  for a fixed window and answers with a proper 429 + ``Retry-After``.

The store is in-process, which is correct for a single-instance deployment.
Swap the ``_buckets`` dict for Redis when running more than one worker.
"""

import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request, status

_lock = threading.Lock()
_buckets: dict[str, deque] = defaultdict(deque)


def hit(key: str, limit: int, window_seconds: int) -> tuple[bool, int]:
    """Record an occurrence.

    Returns (allowed, retry_after_seconds). ``allowed`` is False once ``limit``
    calls have been made inside the window.
    """
    now = time.monotonic()
    cutoff = now - window_seconds
    with _lock:
        bucket = _buckets[key]
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= limit:
            retry_after = int(bucket[0] + window_seconds - now) + 1
            return False, retry_after
        bucket.append(now)
        return True, max(0, limit - len(bucket))


def _client_key(request: Request, scope: str) -> str:
    client = request.client.host if request.client else "unknown"
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        client = forwarded.split(",")[0].strip()
    return f"{scope}:{client}"


def rate_limit(limit: int, window_seconds: int = 60, scope: str | None = None):
    """Throttle a route by client IP.

    Usage::

        @router.post("/send-otp", dependencies=[Depends(rate_limit(5, 60, "send-otp"))])
    """

    def dependency(request: Request) -> None:
        key = _client_key(request, scope or request.url.path)
        allowed, retry_after = hit(key, limit, window_seconds)
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please wait a moment and try again.",
                headers={"Retry-After": str(retry_after)},
            )

    return dependency


def reset(key: str | None = None) -> None:
    with _lock:
        if key is None:
            _buckets.clear()
        else:
            _buckets.pop(key, None)
