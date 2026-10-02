"""Integration client that carries the confirmed session through private calls."""

from typing import Any, cast
from urllib.parse import urlsplit

import httpx2 as httpx

_BOUND_SOURCES = {
    ("POST", "/api/v1/auth/login"),
    ("POST", "/api/v1/admin/auth/login"),
    ("POST", "/api/v1/auth/native/login"),
    ("GET", "/api/v1/me/access"),
    ("GET", "/api/v1/admin/me/access"),
}
_BOOTSTRAP = _BOUND_SOURCES | {
    ("GET", "/api/v1/meta"),
    ("GET", "/api/v1/auth/policy"),
    ("GET", "/api/v1/auth/csrf"),
    ("GET", "/api/v1/admin/auth/csrf"),
    ("POST", "/api/v1/auth/refresh"),
    ("POST", "/api/v1/admin/auth/refresh"),
    ("POST", "/api/v1/auth/native/refresh"),
    ("POST", "/api/v1/auth/register"),
    ("POST", "/api/v1/auth/email/resend"),
    ("POST", "/api/v1/auth/email/verify"),
    ("POST", "/api/v1/auth/recovery/request"),
    ("POST", "/api/v1/auth/recovery/complete"),
    ("GET", "/api/v1/auth/activation/status"),
    ("POST", "/api/v1/frontend-logs/anonymous"),
}


class BoundAsyncClient(httpx.AsyncClient):
    """Test transport only; negative missing-header cases use raw AsyncClient."""

    _expected_session: str | None = None

    async def request(self, method: str, url: str | httpx.URL, **kwargs: Any) -> httpx.Response:
        route = (method.upper(), urlsplit(str(url)).path)
        headers = dict(kwargs.pop("headers", {}) or {})
        if route not in _BOOTSTRAP and self._expected_session is not None:
            headers.setdefault("X-Haruka-Expected-Session", self._expected_session)
        response = await super().request(method, url, headers=headers, **kwargs)
        if route in _BOUND_SOURCES and response.status_code == 200:
            data = response.json().get("data")
            if isinstance(data, dict):
                session_ref = cast(dict[str, object], data).get("session_ref")
                if isinstance(session_ref, str):
                    self._expected_session = session_ref
        return response
