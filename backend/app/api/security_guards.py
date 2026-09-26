"""Transport-origin separation and bounded anonymous identity attempts."""

import hmac
import re
from collections.abc import Iterable
from urllib.parse import urlsplit

from fastapi import Request

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.services.auth_crypto import AuthCrypto


def _origin(value: str) -> str | None:
    try:
        parsed = urlsplit(value)
        _ = parsed.port
    except ValueError:
        return None
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        return None
    return f"{parsed.scheme}://{parsed.netloc}"


def require_web_write(request: Request, runtime: Runtime, *, anonymous: bool) -> None:
    origin = request.headers.get("origin")
    allowed: Iterable[str] = (runtime.settings.public_base_url, *runtime.settings.allowed_origins)
    if not origin or _origin(origin) not in {_origin(item) for item in allowed}:
        raise AppError(ErrorCode.CSRF_FAILED)
    media_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)
    if request.headers.get("authorization"):
        raise AppError(ErrorCode.SESSION_INVALID)
    if anonymous and request.headers.get("sec-fetch-site") == "cross-site":
        raise AppError(ErrorCode.CSRF_FAILED)


def require_native_write(request: Request) -> None:
    if (
        request.headers.get("origin")
        or any(name.startswith("sec-fetch-") for name in request.headers)
        or request.headers.get("cookie")
        or request.headers.get("authorization")
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    media_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)


def require_authenticated_native_write(request: Request) -> None:
    if (
        request.headers.get("origin")
        or any(name.startswith("sec-fetch-") for name in request.headers)
        or request.headers.get("cookie")
        or not request.headers.get("authorization", "").startswith("Bearer ")
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    media_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)


def require_public_write(request: Request, runtime: Runtime) -> None:
    """Shared anonymous actions accept trusted browsers and actual non-browser clients."""
    if request.headers.get("authorization"):
        raise AppError(ErrorCode.SESSION_INVALID)
    origin = request.headers.get("origin")
    browser_metadata = any(name.startswith("sec-fetch-") for name in request.headers)
    if origin or browser_metadata:
        require_web_write(request, runtime, anonymous=True)
        return
    if request.headers.get("cookie"):
        raise AppError(ErrorCode.SESSION_INVALID)
    media_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)


async def require_session_csrf(request: Request, runtime: Runtime, scope: ScopeContext) -> None:
    if scope.transport != "web":
        raise AppError(ErrorCode.CSRF_FAILED)
    require_web_write(request, runtime, anonymous=False)
    supplied = request.headers.get("x-csrf-token", "")
    if re.fullmatch(r"[A-Za-z0-9_-]{43}", supplied) is None:
        raise AppError(ErrorCode.CSRF_FAILED)
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    key = resources.cache.key("auth", str(scope.user_id), str(scope.session_id), "csrf")
    try:
        expected: object = await resources.cache.client.get(key)
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    if not isinstance(expected, bytes) or not hmac.compare_digest(
        expected, AuthCrypto.from_settings(runtime.settings).digest("csrf", supplied)
    ):
        raise AppError(ErrorCode.CSRF_FAILED)


async def rate_limit(
    request: Request, runtime: Runtime, *, purpose: str, identity: str | None = None
) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    address = request.client.host if request.client is not None else "unknown"
    subjects = [("ip", address, 60, 60)]
    if identity is not None:
        subjects.append(("account", identity, 10, 900))
    try:
        for kind, value, limit, ttl in subjects:
            digest = crypto.digest(f"rate-{purpose}-{kind}", value).hex()
            key = resources.cache.key("auth", "rate", purpose, kind, digest)
            count: object = await resources.cache.client.eval(
                "local count = redis.call('INCR', KEYS[1]); "
                "if redis.call('PTTL', KEYS[1]) < 0 then "
                "redis.call('PEXPIRE', KEYS[1], ARGV[1]); end; return count",
                1,
                key,
                ttl * 1000,
            )
            if not isinstance(count, int):
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            if count > limit:
                raise AppError(ErrorCode.RATE_LIMITED)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
