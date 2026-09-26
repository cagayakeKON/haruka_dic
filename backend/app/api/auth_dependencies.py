"""HTTP credential parsing and current authenticated-scope dependency."""

from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID

from fastapi import Request

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import audience_context, user_id_context
from app.domain.errors import AppError
from app.domain.scope import Audience, ScopeContext
from app.services.auth_context import verify_scope_in_transaction
from app.services.auth_crypto import AuthCrypto

_WEB_COOKIES = {"client": "haruka_client_session", "admin": "haruka_admin_session"}


def require_runtime(request: Request) -> Runtime:
    runtime: object = getattr(request.app.state, "runtime", None)
    if not isinstance(runtime, Runtime) or not runtime.ready or runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return runtime


def _credentials(
    request: Request, audience: Audience, crypto: AuthCrypto
) -> tuple[UUID, UUID, str, int | None]:
    bearer = request.headers.get("authorization")
    any_cookie = any(name in request.cookies for name in _WEB_COOKIES.values())
    if bearer and any_cookie:
        raise AppError(ErrorCode.SESSION_INVALID)
    if bearer:
        if audience != "client" or not bearer.startswith("Bearer "):
            raise AppError(ErrorCode.SESSION_INVALID)
        user_id, session_id, generation = crypto.decode_access(bearer.removeprefix("Bearer "))
        return user_id, session_id, "native", generation
    value = request.cookies.get(_WEB_COOKIES[audience])
    if not value:
        raise AppError(ErrorCode.AUTH_REQUIRED)
    # The opaque cookie is resolved by a digest index in Redis, never a client sid.
    if len(value) != 43:
        raise AppError(ErrorCode.SESSION_INVALID)
    try:
        digest = crypto.digest("web-session", value).hex()
    except UnicodeEncodeError:
        raise AppError(ErrorCode.SESSION_INVALID) from None
    return UUID(int=0), UUID(int=0), digest, None


async def require_scope(
    request: Request, *, audience: Audience, permissions: tuple[str, ...] = ()
) -> ScopeContext:
    runtime = require_runtime(request)
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    user_id, session_id, transport_or_digest, _token_generation = _credentials(
        request, audience, crypto
    )
    cache = resources.cache
    try:
        if transport_or_digest not in {"native", "web"}:
            lookup = cache.key("auth", "web", audience, transport_or_digest)
            binding = await cache.client.get(lookup)
            if not isinstance(binding, bytes):
                raise AppError(ErrorCode.SESSION_INVALID)
            parts = binding.decode("ascii").split(":")
            if len(parts) != 2:
                raise AppError(ErrorCode.SESSION_INVALID)
            user_id, session_id = UUID(parts[0]), UUID(parts[1])
            transport: Literal["web", "native"] = "web"
        else:
            transport = "native"
        alive = await cache.client.get(cache.key("auth", str(user_id), str(session_id), "alive"))
        if alive != b"1":
            raise AppError(ErrorCode.SESSION_INVALID)
        if transport == "native":
            raw = await cache.client.get(
                cache.key("auth", str(user_id), str(session_id), "refresh")
            )
            if not isinstance(raw, bytes):
                raise AppError(ErrorCode.SESSION_INVALID)
        async with resources.database.sessions() as session:
            scope = await verify_scope_in_transaction(
                session,
                user_id=user_id,
                session_id=session_id,
                audience=audience,
                transport=transport,
                permissions=permissions,
            )
        if transport == "web":
            idle = timedelta(minutes=30) if audience == "admin" else timedelta(hours=24)
            ttl = min(
                int(idle.total_seconds()),
                int((scope.absolute_expires_at - datetime.now(UTC)).total_seconds()),
            )
            if ttl <= 0:
                raise AppError(ErrorCode.SESSION_INVALID)
            renewed = await cache.client.eval(
                "if redis.call('GET', KEYS[1]) ~= '1' or not redis.call('EXISTS', KEYS[2]) "
                "then return 0 end; redis.call('EXPIRE', KEYS[1], ARGV[1]); "
                "redis.call('EXPIRE', KEYS[2], ARGV[1]); "
                "if redis.call('EXISTS', KEYS[3]) == 1 then redis.call('EXPIRE', KEYS[3], ARGV[1]) end; "
                "return 1",
                3,
                cache.key("auth", str(user_id), str(session_id), "alive"),
                cache.key("auth", "web", audience, transport_or_digest),
                cache.key("auth", str(user_id), str(session_id), "csrf"),
                ttl,
            )
            if renewed != 1:
                raise AppError(ErrorCode.SESSION_INVALID)
        request.state.user_id = scope.user_id
        request.state.audience = scope.audience
        user_id_context.set(scope.user_id)
        audience_context.set(scope.audience)
        return scope
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
