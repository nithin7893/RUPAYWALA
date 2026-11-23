# RUPAYWALA — H-01 Trusted Proxy / X-Forwarded-For Security Fix Report

**Date:** 23 November 2026
**Scope:** H-01 only (untrusted `X-Forwarded-For` in rate limiting). C-01 and C-02 fixes are preserved.
**Status:** FIXED and regression-tested. No production deployment or database change was made.

---

## 1. Root cause

`app/utils/rate_limit.py::_client_key` took the client identity directly from the request:

```python
client = request.client.host if request.client else "unknown"
forwarded = request.headers.get("x-forwarded-for")
if forwarded:
    client = forwarded.split(",")[0].strip()
return f"{scope}:{client}"
```

This blindly trusted an arbitrary client-supplied header and used its **leftmost** entry. Any caller
could rotate `X-Forwarded-For` to obtain a fresh rate-limit bucket per request, defeating throttling
on all 10 rate-limited routes. Arbitrary header text also became an in-memory dict key, allowing
unbounded bucket growth.

The project already had the correct policy settings — `TRUST_PROXY_HEADERS` (default `false`) and
`TRUSTED_PROXY_IPS` (default `127.0.0.1`) in `app/config.py:266-271` — but the rate limiter never
consulted them. A repository-wide search confirmed there is no reverse-proxy, Docker, nginx, or
other deployment configuration in the repo, so **no trusted proxy is actually configured**; the
correct default is therefore to trust no forwarding headers at all.

Affected limits (all thresholds unchanged):

| Route | Limit |
|---|---|
| `/auth/send-otp`, `/auth/send-email-otp`, `/auth/forgot-otp` | 5 / 60 s |
| `/auth/verify-otp`, `/auth/verify-email-otp`, `/auth/email-login`, `/auth/login`, `/auth/forgot-reset` | 10 / 60 s |
| `/payments/create`, `/payments/submit` | 20 / 60 s |

---

## 2. Files changed

| File | Change |
|---|---|
| `app/utils/proxy.py` | **New.** Shared trusted-proxy identity module: IP normalisation, trusted-peer check, right-to-left `X-Forwarded-For` parsing, bounded/fail-closed fallback. |
| `app/utils/rate_limit.py` | `_client_key()` now uses `client_ip(request)` instead of reading `X-Forwarded-For`; docstring updated. Limits, scopes, `hit()` and `reset()` are unchanged. |
| `app/main.py` | HTTPS-redirect and HSTS middleware now honour `X-Forwarded-Proto` only via `is_trusted_peer(request)` instead of the bare `TRUST_PROXY_HEADERS` flag; removed the now-unused direct import. |
| `.env.example` | Added explicit explanatory comments for `TRUST_PROXY_HEADERS` / `TRUSTED_PROXY_IPS`. No address invented or changed. |
| `tests/test_h01_trusted_proxy_security.py` | **New.** 13 regression tests covering all required cases. |

No authentication flow, OTP logic, database schema, migration, production data, Flutter screen, or
Android build configuration was modified. No secrets were introduced.

---

## 3. Security behaviour implemented

1. **Default deny.** Forwarding headers are ignored unless `TRUST_PROXY_HEADERS=true`.
2. **Peer allowlist.** Even when enabled, headers are honoured only if the immediate TCP peer is a
   literal IP present in `TRUSTED_PROXY_IPS`. An untrusted client sending a header gains nothing.
3. **Right-to-left chain parsing.** `X-Forwarded-For` is read from the closest hop backwards;
   configured trusted-proxy hops are skipped and the first remaining address becomes the client.
   Attacker-controlled leftmost entries are therefore ignored.
4. **No shared proxy identity.** Different client IPs arriving through the same proxy get separate
   rate-limit buckets. If a chain contains only trusted proxies (no client information), the code
   fails back to the verified socket peer rather than inventing an identity.
5. **IPv4/IPv6 preserved.** Both families are canonicalised with `ipaddress`; IPv4-mapped IPv6 is
   folded to IPv4 so notation changes cannot create multiple identities. Scoped IPv6 is tolerated.
6. **Bounded, validated keys.** Malformed, empty, oversized (>4096 chars) or >32-entry forwarding
   chains fall back to the verified peer. At most one canonical IP (or a 64-char transport peer)
   enters a bucket key, eliminating header-controlled unbounded keys.
7. **No sensitive logging.** The new module logs nothing; no header value, OTP, password or token is
   written to logs. A regression test asserts this.
8. **Related forwarding header hardened.** `X-Forwarded-Proto` now uses the same trusted-peer gate,
   closing the spoofing path in the audit's M-01 without changing behaviour for genuine proxies.
9. **Thresholds unchanged.** All 5/60, 10/60 and 20/60 limits and their scopes remain identical;
   `Retry-After` 429 behaviour is preserved.

Deployment remains explicit: with no reverse proxy in the repository, the safe default (`false`) is
retained. If a proxy is introduced, the operator must set `TRUST_PROXY_HEADERS=true` and list its
real IP(s) in `TRUSTED_PROXY_IPS`; the application never guesses them.

---

## 4. Tests and results

New suite `tests/test_h01_trusted_proxy_security.py` (13 tests):

| Requirement | Covered by |
|---|---|
| Spoofed `X-Forwarded-For` | unit test with trust disabled; unit test with trust enabled but untrusted peer; rotating-header endpoint tests for login and OTP |
| Direct client requests | peer-only identity test; endpoint spoofing tests |
| Trusted proxy requests | single-header trusted-proxy test; proxy peer allowlist assertions |
| Multiple forwarded IPs | chain with spoofed leftmost + two trusted proxy hops |
| IPv4 and IPv6 | canonicalisation test including IPv4-mapped IPv6 and direct IPv6 peer |
| OTP rate limiting | `/auth/send-otp` 6th request returns 429 after 5 allowed (service mocked, no SMS/DB writes) |
| Login rate limiting | `/auth/login` 11th request returns 429 after 10 allowed |
| Multiple users behind a trusted proxy | two distinct identities through one proxy get independent buckets (unit + endpoint) |
| Existing rate-limit behaviour | threshold/`Retry-After` preservation test |
| Fail-closed parsing | malformed, empty, 33-entry and oversized headers |
| No sensitive logging | `caplog` assertion in the OTP test |

Results:

| Check | Result |
|---|---|
| `pytest tests/test_h01_trusted_proxy_security.py` | **13 passed** |
| Full backend regression (`pytest --tb=no -ra`) | **441 passed, 0 failed** (428 prior baseline + 13 new; 250.48 s) |
| C-02 Android `INTERNET` declaration | Still present in `android/app/src/main/AndroidManifest.xml` (verified) |
| C-01 OTP fix | Untouched; included in the passing regression suite |

No tests were skipped. No production database, schema, migration, or external integration was used.
The test suite binds only the dedicated `rupaywala_test` database via the existing safety guards.

---

## 5. Remaining limitations

- The rate limiter is still **in-process**; buckets are not shared across workers or instances. This
  is the pre-existing documented limitation (Redis/edge limiter required for multi-instance
  production) and was out of scope for H-01.
- No reverse-proxy deployment configuration exists in this repository, so trusted proxy addresses
  could not be validated against a real deployment. Only explicit operator configuration can enable
  forwarding-header trust.
- Live proxy/TLS behaviour (termination, header sanitisation, forwarded-proto) was not tested against
  a real load balancer; no deployment has been authorised.
- Other unthrottled endpoints (e.g. `/auth/check-user`, registration, `/auth/google`) remain as
  separately documented audit findings; H-01 did not add or change limits there.

---

## 6. Conclusion

H-01 is remediated: forwarding headers can no longer spoof a client identity outside an explicitly
configured and allowlisted proxy, spoofed headers cannot bypass login or OTP throttles, and all
existing limits and security configuration are preserved. The full regression suite is green at
441 passed. Work is stopped here pending approval.
