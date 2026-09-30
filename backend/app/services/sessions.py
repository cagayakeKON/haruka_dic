"""Shared account login and durable session creation for two transports."""

import hmac
import json
import logging
from base64 import urlsafe_b64decode, urlsafe_b64encode
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal, cast
from uuid import UUID

from pydantic import SecretStr, TypeAdapter, ValidationError
from sqlalchemy import select

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
from app.domain.email_address import normalize_existing_login_email
from app.domain.errors import AppError
from app.models import AuthSession, PermissionCatalog
from app.repositories.identity import (
    account_session_for_update,
    account_session_page,
    active_sessions_for_scope,
    current_session_for_update,
    current_user,
    current_user_for_update,
    global_revision_for_update,
    refresh_session_for_update,
    user_by_email,
    user_for_login_for_update,
    user_for_refresh_for_update,
)
from app.schemas.auth import (
    AccessRead,
    AccountRead,
    ActivationRequired,
    AuthzVersionRead,
    NativeAuthenticated,
    PermissionRead,
    SessionSummary,
    WebAuthenticated,
)
from app.services.auth_context import (
    Audience,
    ScopeContext,
    require_permissions,
    verify_scope_in_transaction,
)
from app.services.auth_crypto import AuthCrypto, hash_password, new_opaque_token, verify_password
from app.services.authorization import allowed_pairs, load_graph
from app.services.menu_governance import project_navigation
from app.services.registration import pending_login_action
from app.services.security_events import append_identity_event

_CLIENT_ABSOLUTE = timedelta(days=7)
_CLIENT_IDLE = timedelta(hours=24)
_ADMIN_ABSOLUTE = timedelta(hours=8)
_ADMIN_IDLE = timedelta(minutes=30)
_ACCESS = timedelta(minutes=15)
_CONTINUATION = timedelta(minutes=5)
_LOGGER = logging.getLogger(__name__)


def _log_login_result(
    outcome: Literal["succeeded", "rejected", "action_required"],
    audience: Audience,
    user_id: UUID | None = None,
) -> None:
    request_id, operation_id = current_correlation()
    extra = {
        "request_id": request_id,
        "operation_id": operation_id,
        "user_id": user_id,
        "audience": audience,
    }
    if outcome == "succeeded":
        _LOGGER.info("auth.login.succeeded", extra=extra)
    elif outcome == "action_required":
        _LOGGER.info("auth.login.action_required", extra=extra)
    else:
        _LOGGER.info("auth.login.rejected", extra=extra)


@dataclass(frozen=True)
class LoginResult:
    response: WebAuthenticated | NativeAuthenticated | ActivationRequired
    web_cookie: str | None = None


def _session_limits(audience: Audience) -> tuple[timedelta, timedelta]:
    if audience == "admin":
        return _ADMIN_ABSOLUTE, _ADMIN_IDLE
    return _CLIENT_ABSOLUTE, _CLIENT_IDLE


def _csrf_token(crypto: AuthCrypto, user_id: UUID, session_id: UUID) -> str:
    return (
        urlsafe_b64encode(crypto.digest("csrf-token", f"{user_id}:{session_id}"))
        .decode("ascii")
        .rstrip("=")
    )


async def _pending_continuation(
    runtime: Runtime,
    crypto: AuthCrypto,
    *,
    user_id: UUID,
    action: Literal["verify_email", "await_approval", "rejected"] = "verify_email",
) -> ActivationRequired:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    token = new_opaque_token()
    deadline = datetime.now(UTC) + _CONTINUATION
    key = resources.cache.key("auth", "continuation", crypto.digest("continuation", token).hex())
    try:
        await resources.cache.client.set(key, str(user_id), ex=int(_CONTINUATION.total_seconds()))
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    return ActivationRequired(
        action_required=action,
        continuation_token=token,
        continuation_expires_at=deadline,
    )


def _session_keys(runtime: Runtime, scope: ScopeContext) -> tuple[str, str]:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    prefix = ("auth", str(scope.user_id), str(scope.session_id))
    return resources.cache.key(*prefix, "alive"), resources.cache.key(*prefix, "csrf")


async def issue_csrf(runtime: Runtime, scope: ScopeContext) -> str:
    if scope.transport != "web":
        raise AppError(ErrorCode.SESSION_INVALID)
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    alive_key, csrf_key = _session_keys(runtime, scope)
    crypto = AuthCrypto.from_settings(runtime.settings)
    token = _csrf_token(crypto, scope.user_id, scope.session_id)
    ttl = max(
        1,
        min(
            int((scope.absolute_expires_at - datetime.now(UTC)).total_seconds()),
            int(_session_limits(scope.audience)[1].total_seconds()),
        ),
    )
    try:
        result = await resources.cache.client.eval(
            "if redis.call('GET', KEYS[1]) ~= '1' then return 0 end; "
            "local current = redis.call('GET', KEYS[2]); "
            "if current and current ~= ARGV[1] then return 0 end; "
            "redis.call('SET', KEYS[2], ARGV[1], 'EX', ARGV[2]); return 1",
            2,
            alive_key,
            csrf_key,
            crypto.digest("csrf", token),
            ttl,
        )
        if result != 1:
            raise AppError(ErrorCode.SESSION_INVALID)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    return token


def menu_visible(codes: list[str], match: str, allowed: set[str]) -> bool:
    if not codes:
        return False
    visible = (code in allowed for code in codes)
    return all(visible) if match == "all" else any(code in allowed for code in codes)


async def read_access(runtime: Runtime, scope: ScopeContext) -> AccessRead:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session:
        current = await verify_scope_in_transaction(
            session,
            user_id=scope.user_id,
            session_id=scope.session_id,
            audience=scope.audience,
            transport=scope.transport,
        )
        graph = await load_graph(session, scope.user_id)
        granted = allowed_pairs(graph, scope.user_id)
        catalogs = (
            await session.scalars(
                select(PermissionCatalog).where(
                    PermissionCatalog.audience == scope.audience,
                    PermissionCatalog.enabled.is_(True),
                )
            )
        ).all()
        permissions = [
            PermissionRead(code=catalog.code, data_scope=catalog.data_scope)
            for catalog in catalogs
            if (catalog.code, catalog.data_scope) in granted
        ]
        permissions.sort(key=lambda item: item.code)
        allowed = {item.code for item in permissions}
        navigation = await project_navigation(session, audience=scope.audience, allowed=allowed)
    return AccessRead(
        user_id=current.user_id,
        instance_id=runtime.settings.instance_id,
        audience=current.audience,
        session_ref=current.session_id,
        authz_version=AuthzVersionRead(
            user=current.user_authz_version,
            policy=current.policy_authz_version,
        ),
        permissions=permissions,
        navigation=navigation,
        feature_flags=[],
    )


async def read_account(runtime: Runtime, scope: ScopeContext) -> AccountRead:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session:
        await verify_scope_in_transaction(
            session,
            user_id=scope.user_id,
            session_id=scope.session_id,
            audience="client",
            transport=scope.transport,
        )
        user = await current_user(session, scope)
        if user is None:
            raise AppError(ErrorCode.SESSION_INVALID)
        return AccountRead(
            email=user.email,
            status="active",
            email_verified_at=user.email_verified_at,
            created_at=user.created_at,
        )


def _encode_session_cursor(
    runtime: Runtime, scope: ScopeContext, created_at: datetime, row_id: UUID
) -> str:
    payload = json.dumps([created_at.isoformat(), str(row_id)], separators=(",", ":"))
    encoded = urlsafe_b64encode(payload.encode("ascii")).decode("ascii").rstrip("=")
    signature = AuthCrypto.from_settings(runtime.settings).digest(
        "session-cursor", f"{scope.user_id}:{scope.audience}:{encoded}"
    )
    return f"{encoded}.{urlsafe_b64encode(signature).decode('ascii').rstrip('=')}"


def _decode_session_cursor(
    runtime: Runtime, scope: ScopeContext, cursor: str
) -> tuple[datetime, UUID]:
    try:
        encoded, signature = cursor.split(".")
        if len(cursor) > 256 or not encoded or not signature:
            raise ValueError
        crypto = AuthCrypto.from_settings(runtime.settings)
        expected = crypto.digest("session-cursor", f"{scope.user_id}:{scope.audience}:{encoded}")
        supplied = urlsafe_b64decode(signature + "=" * (-len(signature) % 4))
        if not hmac.compare_digest(supplied, expected):
            raise ValueError
        first, second = TypeAdapter(tuple[str, str]).validate_json(
            urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        )
        created_at, row_id = datetime.fromisoformat(first), UUID(second)
        if created_at.tzinfo is None:
            raise ValueError
        return created_at, row_id
    except (ValueError, TypeError, UnicodeError, ValidationError):
        raise AppError(ErrorCode.INPUT_INVALID) from None


async def list_sessions(
    runtime: Runtime, scope: ScopeContext, *, limit: int, cursor: str | None
) -> tuple[list[SessionSummary], str | None]:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session:
        await verify_scope_in_transaction(
            session,
            user_id=scope.user_id,
            session_id=scope.session_id,
            audience=scope.audience,
            transport=scope.transport,
        )
        after = _decode_session_cursor(runtime, scope, cursor) if cursor is not None else None
        rows = await account_session_page(session, scope, limit=limit, after=after)
    has_more = len(rows) > limit
    page = rows[:limit]
    next_cursor = (
        _encode_session_cursor(runtime, scope, page[-1].created_at, page[-1].id)
        if has_more
        else None
    )
    return [
        SessionSummary(
            id=row.id,
            audience=scope.audience,
            transport=cast(Literal["web", "native"], row.transport),
            platform=cast(Literal["web", "windows", "android"], row.platform),
            device_summary=row.device_summary,
            created_at=row.created_at,
            last_seen_at=row.last_seen_at,
            absolute_expires_at=row.absolute_expires_at,
            revoked_at=row.revoked_at,
            is_current=row.id == scope.session_id,
        )
        for row in page
    ], next_cursor


async def revoke_session(
    runtime: Runtime, scope: ScopeContext, *, target_id: UUID, all_audience: bool = False
) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    now = datetime.now(UTC)
    try:
        async with resources.database.sessions() as session, session.begin():
            revision = await global_revision_for_update(session)
            user = await current_user_for_update(session, scope)
            if revision is None or user is None:
                raise AppError(ErrorCode.SESSION_INVALID)
            await verify_scope_in_transaction(
                session,
                user_id=scope.user_id,
                session_id=scope.session_id,
                audience=scope.audience,
                transport=scope.transport,
            )
            if all_audience:
                if scope.audience == "client":
                    user.client_security_epoch += 1
                else:
                    user.admin_security_epoch += 1
                rows = await active_sessions_for_scope(session, scope)
            else:
                target = await account_session_for_update(session, scope, target_id)
                if (
                    target is None
                    or target.user_id != scope.user_id
                    or target.audience != scope.audience
                ):
                    raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
                rows = [target]
            for row in rows:
                if row.revoked_at is None:
                    row.revoked_at = now
                    row.revoke_reason_code = "user_requested"
            await append_identity_event(
                session,
                action="session.revoked",
                authorization_revision=revision.revision,
                actor="authenticated-user",
                actor_user_id=scope.user_id,
                audience=scope.audience,
                target_type="user" if all_audience else "session",
                target_id=scope.user_id if all_audience else target_id,
                result="committed",
                reason_code="user_requested",
            )
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    # PG revocation is authoritative. Redis deletion is only best effort.
    request_id, operation_id = current_correlation()
    _LOGGER.info(
        "auth.session.revoked",
        extra={
            "request_id": request_id,
            "operation_id": operation_id,
            "user_id": scope.user_id,
            "audience": scope.audience,
        },
    )
    for row in rows:
        try:
            await resources.cache.client.delete(
                resources.cache.key("auth", str(scope.user_id), str(row.id), "alive")
            )
        except Exception:
            _LOGGER.warning("auth.cache_invalidation.deferred", extra={"audience": scope.audience})


async def renew_web(runtime: Runtime, scope: ScopeContext, cookie: str) -> WebAuthenticated:
    if scope.transport != "web":
        raise AppError(ErrorCode.SESSION_INVALID)
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    now = datetime.now(UTC)
    ttl = min(
        int((scope.absolute_expires_at - now).total_seconds()),
        int(_session_limits(scope.audience)[1].total_seconds()),
    )
    if ttl <= 0:
        raise AppError(ErrorCode.SESSION_INVALID)
    crypto = AuthCrypto.from_settings(runtime.settings)
    alive, csrf = _session_keys(runtime, scope)
    lookup = resources.cache.key(
        "auth", "web", scope.audience, crypto.digest("web-session", cookie).hex()
    )
    try:
        renewed = await resources.cache.client.eval(
            "if redis.call('GET', KEYS[1]) ~= '1' or not redis.call('EXISTS', KEYS[2]) "
            "then return 0 end; redis.call('EXPIRE', KEYS[1], ARGV[1]); "
            "redis.call('EXPIRE', KEYS[2], ARGV[1]); "
            "if redis.call('EXISTS', KEYS[3]) == 1 then redis.call('EXPIRE', KEYS[3], ARGV[1]) end; "
            "return 1",
            3,
            alive,
            lookup,
            csrf,
            ttl,
        )
        if renewed != 1:
            raise AppError(ErrorCode.SESSION_INVALID)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    return WebAuthenticated(
        session_ref=scope.session_id,
        audience=scope.audience,
        absolute_expires_at=scope.absolute_expires_at,
        idle_expires_at=now + timedelta(seconds=ttl),
        server_time=now,
    )


async def _revoke_replayed_refresh(runtime: Runtime, user_id: UUID, session_id: UUID) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        async with resources.database.sessions() as session, session.begin():
            revision = await global_revision_for_update(session)
            user = await user_for_refresh_for_update(session, user_id)
            row = await refresh_session_for_update(session, user_id=user_id, session_id=session_id)
            if (
                user is not None
                and row is not None
                and row.user_id == user.id
                and row.revoked_at is None
            ):
                row.revoked_at = datetime.now(UTC)
                row.revoke_reason_code = "refresh_replay"
                if revision is None:
                    raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
                await append_identity_event(
                    session,
                    action="refresh.replayed",
                    authorization_revision=revision.revision,
                    actor="identity-service",
                    actor_user_id=user.id,
                    audience="client",
                    target_type="session",
                    target_id=session_id,
                    result="committed",
                    reason_code="refresh_replay",
                )
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    try:
        await resources.cache.client.delete(
            resources.cache.key("auth", str(user_id), str(session_id), "alive")
        )
    except Exception:
        _LOGGER.warning("auth.cache_invalidation.deferred", extra={"audience": "client"})


async def refresh_native(
    runtime: Runtime, *, refresh_token: SecretStr, refresh_request_id: UUID
) -> NativeAuthenticated:
    resources = runtime.resources
    if resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    supplied = refresh_token.get_secret_value()
    digest = crypto.digest("native-refresh", supplied).hex()
    index_key = resources.cache.key("auth", "refresh", "index", digest)
    receipt_key = resources.cache.key("auth", "refresh", "receipt", digest)
    try:
        binding = await resources.cache.client.get(index_key)
        if not isinstance(binding, bytes):
            raise AppError(ErrorCode.SESSION_INVALID)
        parts = binding.decode("ascii").split(":")
        if len(parts) != 3:
            raise AppError(ErrorCode.SESSION_INVALID)
        user_id, session_id, indexed_generation = UUID(parts[0]), UUID(parts[1]), int(parts[2])
        if indexed_generation < 1:
            raise AppError(ErrorCode.SESSION_INVALID)
        alive_key = resources.cache.key("auth", str(user_id), str(session_id), "alive")
        state_key = resources.cache.key("auth", str(user_id), str(session_id), "refresh")
        if await resources.cache.client.get(alive_key) != b"1":
            raise AppError(ErrorCode.SESSION_INVALID)
        async with resources.database.sessions() as session:
            scope = await verify_scope_in_transaction(
                session,
                user_id=user_id,
                session_id=session_id,
                audience="client",
                transport="native",
            )
        raw_state = await resources.cache.client.get(state_key)
        if not isinstance(raw_state, bytes):
            raise AppError(ErrorCode.SESSION_INVALID)
        state = TypeAdapter(dict[str, object]).validate_json(raw_state)
        current_digest = state.get("digest")
        current_generation = state.get("generation")
        if not isinstance(current_digest, str) or not isinstance(current_generation, int):
            raise AppError(ErrorCode.SESSION_INVALID)

        async def previous_receipt() -> NativeAuthenticated | None:
            pair: object = await resources.cache.client.eval(
                "return {redis.call('GET', KEYS[1]) or '', redis.call('GET', KEYS[2]) or ''}",
                2,
                state_key,
                receipt_key,
            )
            latest_state, encrypted = TypeAdapter(tuple[bytes, bytes]).validate_python(pair)
            if not latest_state:
                raise AppError(ErrorCode.SESSION_INVALID)
            if not encrypted:
                return None
            latest = TypeAdapter(dict[str, object]).validate_json(latest_state)
            latest_generation = latest.get("generation")
            latest_digest = latest.get("digest")
            if not isinstance(latest_generation, int) or not isinstance(latest_digest, str):
                raise AppError(ErrorCode.SESSION_INVALID)
            decoded = TypeAdapter(dict[str, object]).validate_json(
                crypto.decrypt_refresh_receipt(encrypted)
            )
            if decoded.get("request_id") != str(refresh_request_id):
                raise AppError(ErrorCode.REFRESH_SUPERSEDED)
            if decoded.get("generation") != latest_generation:
                raise AppError(ErrorCode.REFRESH_SUPERSEDED)
            value = decoded.get("response")
            response = NativeAuthenticated.model_validate(value)
            if (
                response.session_generation != latest_generation
                or crypto.digest("native-refresh", response.refresh_token).hex() != latest_digest
            ):
                raise AppError(ErrorCode.REFRESH_SUPERSEDED)
            return response

        if current_digest != digest:
            receipt = await previous_receipt()
            if receipt is not None:
                return receipt
            await _revoke_replayed_refresh(runtime, user_id, session_id)
            raise AppError(ErrorCode.SESSION_REVOKED)
        if current_generation != indexed_generation:
            raise AppError(ErrorCode.SESSION_INVALID)
        now = datetime.now(UTC)
        remaining = int((scope.absolute_expires_at - now).total_seconds())
        if remaining <= 0:
            raise AppError(ErrorCode.SESSION_INVALID)
        idle_seconds = min(int(_CLIENT_IDLE.total_seconds()), remaining)
        new_token = new_opaque_token()
        new_digest = crypto.digest("native-refresh", new_token).hex()
        generation = current_generation + 1
        access_expires = now + min(_ACCESS, timedelta(seconds=remaining))
        response = NativeAuthenticated(
            session_ref=session_id,
            access_token=crypto.access_jwt(
                user_id=user_id,
                session_id=session_id,
                generation=generation,
                expires_at=access_expires,
            ),
            access_expires_at=access_expires,
            refresh_token=new_token,
            refresh_expires_at=now + timedelta(seconds=idle_seconds),
            session_generation=generation,
            absolute_expires_at=scope.absolute_expires_at,
            server_time=now,
        )
        new_index = resources.cache.key("auth", "refresh", "index", new_digest)
        new_state = json.dumps(
            {"digest": new_digest, "generation": generation}, separators=(",", ":")
        )
        receipt_payload = json.dumps(
            {
                "request_id": str(refresh_request_id),
                "generation": generation,
                "response": response.model_dump(mode="json"),
            },
            separators=(",", ":"),
        ).encode("utf-8")
        changed = await resources.cache.client.eval(
            "if redis.call('GET', KEYS[1]) ~= '1' then return -1 end; "
            "local raw = redis.call('GET', KEYS[2]); if not raw then return -1 end; "
            "local old = cjson.decode(raw); "
            "if old.digest ~= ARGV[1] or old.generation ~= tonumber(ARGV[2]) then return 0 end; "
            "redis.call('SET', KEYS[2], ARGV[3], 'EX', ARGV[4]); "
            "redis.call('SET', KEYS[3], ARGV[5], 'EX', ARGV[6]); "
            "redis.call('SET', KEYS[4], ARGV[7], 'EX', 10); "
            "redis.call('EXPIRE', KEYS[1], ARGV[4]); return 1",
            4,
            alive_key,
            state_key,
            new_index,
            receipt_key,
            digest,
            current_generation,
            new_state,
            idle_seconds,
            f"{user_id}:{session_id}:{generation}",
            remaining,
            crypto.encrypt_refresh_receipt(receipt_payload),
        )
        if changed == 1:
            return response
        if changed == 0:
            receipt = await previous_receipt()
            if receipt is not None:
                return receipt
            raise AppError(ErrorCode.REFRESH_SUPERSEDED)
        raise AppError(ErrorCode.SESSION_INVALID)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def change_password(
    runtime: Runtime,
    scope: ScopeContext,
    *,
    current_password: SecretStr,
    new_password: SecretStr,
) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        async with resources.database.sessions() as session:
            user = await current_user(session, scope)
            if user is None:
                raise AppError(ErrorCode.SESSION_INVALID)
            previous_hash = user.password_hash
            password_version = user.password_version
            security_epoch = user.security_epoch
        if not await verify_password(previous_hash, current_password):
            raise AppError(ErrorCode.AUTH_LOGIN_FAILED)
        replacement = await hash_password(new_password)
        async with resources.database.sessions() as session, session.begin():
            revision = await global_revision_for_update(session)
            user = await current_user_for_update(session, scope)
            active = await current_session_for_update(session, scope)
            if revision is None or user is None or active is None:
                raise AppError(ErrorCode.SESSION_INVALID)
            if user.password_version != password_version or user.security_epoch != security_epoch:
                raise AppError(ErrorCode.REVISION_CONFLICT)
            await verify_scope_in_transaction(
                session,
                user_id=scope.user_id,
                session_id=scope.session_id,
                audience=scope.audience,
                transport=scope.transport,
            )
            now = datetime.now(UTC)
            rows = await active_sessions_for_scope(session, scope, across_audiences=True)
            user.password_hash = replacement
            user.password_version += 1
            user.security_epoch += 1
            user.revision += 1
            for row in rows:
                row.revoked_at = now
                row.revoke_reason_code = "password_changed"
            await append_identity_event(
                session,
                action="password.changed",
                authorization_revision=revision.revision,
                actor="authenticated-user",
                actor_user_id=user.id,
                audience=scope.audience,
                target_type="user",
                target_id=user.id,
                result="committed",
            )
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    # A committed PG security epoch is the source of truth even if cache deletion fails.
    request_id, operation_id = current_correlation()
    _LOGGER.info(
        "auth.password.changed",
        extra={
            "request_id": request_id,
            "operation_id": operation_id,
            "user_id": scope.user_id,
            "audience": scope.audience,
        },
    )
    for row in rows:
        try:
            await resources.cache.client.delete(
                resources.cache.key("auth", str(scope.user_id), str(row.id), "alive")
            )
        except Exception:
            _LOGGER.warning("auth.cache_invalidation.deferred", extra={"audience": scope.audience})


async def _revoke_unissued(runtime: Runtime, *, user_id: UUID, session_id: UUID) -> None:
    resources = runtime.resources
    if resources is None:
        return
    try:
        async with resources.database.sessions() as session, session.begin():
            await global_revision_for_update(session)
            await user_for_refresh_for_update(session, user_id)
            row = await refresh_session_for_update(session, user_id=user_id, session_id=session_id)
            if row is not None and row.user_id == user_id and row.revoked_at is None:
                row.revoked_at = datetime.now(UTC)
                row.revoke_reason_code = "issuance_failed"
    except Exception:
        # No credentials were returned, and missing Redis material fails closed.
        return


async def login(
    runtime: Runtime,
    *,
    email: str,
    password: SecretStr,
    audience: Audience,
    transport: Literal["web", "native"],
    platform: Literal["web", "windows", "android"],
    device_summary: str | None = None,
) -> LoginResult:
    resources = runtime.resources
    if resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        _, normalized = normalize_existing_login_email(email)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    crypto = AuthCrypto.from_settings(runtime.settings)
    try:
        async with resources.database.sessions() as session:
            observed = await user_by_email(session, normalized)
            stored_hash = observed.password_hash if observed is not None else None
            observed_password_version = observed.password_version if observed is not None else None
            observed_security_epoch = observed.security_epoch if observed is not None else None
        correct = await verify_password(stored_hash, password)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    if not correct or observed is None:
        _log_login_result("rejected", audience)
        raise AppError(ErrorCode.AUTH_LOGIN_FAILED)
    if observed.status == "pending" and audience == "client":
        continuation = await _pending_continuation(
            runtime, crypto, user_id=observed.id, action=pending_login_action(observed)
        )
        _log_login_result("action_required", audience, observed.id)
        return LoginResult(response=continuation)
    if observed.status != "active":
        _log_login_result("rejected", audience)
        raise AppError(ErrorCode.AUTH_LOGIN_FAILED)
    now = datetime.now(UTC)
    absolute, idle = _session_limits(audience)
    expires = now + absolute
    try:
        async with resources.database.sessions() as session, session.begin():
            revision = await global_revision_for_update(session)
            user = await user_for_login_for_update(session, observed.id)
            if (
                revision is None
                or user is None
                or user.status != "active"
                or user.password_version != observed_password_version
                or user.security_epoch != observed_security_epoch
                or (user.locked_until is not None and user.locked_until > now)
            ):
                raise AppError(ErrorCode.AUTH_LOGIN_FAILED)
            await require_permissions(
                session,
                user_id=user.id,
                audience=audience,
                codes=(f"{audience}.login",),
            )
            auth_session = AuthSession(
                user_id=user.id,
                audience=audience,
                transport=transport,
                platform=platform,
                absolute_expires_at=expires,
                revoked_at=None,
                security_epoch=user.security_epoch,
                audience_security_epoch=(
                    user.client_security_epoch
                    if audience == "client"
                    else user.admin_security_epoch
                ),
                reauthenticated_at=now,
                device_summary=(device_summary.strip()[:200] if device_summary else None),
                last_seen_at=now,
            )
            session.add(auth_session)
            await session.flush()
            await append_identity_event(
                session,
                action="session.created",
                authorization_revision=revision.revision,
                actor="authenticated-user",
                actor_user_id=user.id,
                audience=audience,
                target_type="session",
                target_id=auth_session.id,
                result="committed",
            )
            session_id, user_id = auth_session.id, user.id
    except AppError as exc:
        if exc.code == ErrorCode.PERMISSION_DENIED:
            _log_login_result("rejected", audience)
            raise AppError(ErrorCode.AUTH_LOGIN_FAILED) from None
        if exc.code == ErrorCode.AUTH_LOGIN_FAILED:
            _log_login_result("rejected", audience)
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    ttl = max(1, int(min(idle, absolute).total_seconds()))
    alive_key = resources.cache.key("auth", str(user_id), str(session_id), "alive")
    try:
        if transport == "web":
            web_cookie = new_opaque_token()
            csrf_token = _csrf_token(crypto, user_id, session_id)
            lookup_key = resources.cache.key(
                "auth", "web", audience, crypto.digest("web-session", web_cookie).hex()
            )
            csrf_key = resources.cache.key("auth", str(user_id), str(session_id), "csrf")
            await resources.cache.client.set(alive_key, b"1", ex=ttl)
            await resources.cache.client.set(lookup_key, f"{user_id}:{session_id}", ex=ttl)
            await resources.cache.client.set(csrf_key, crypto.digest("csrf", csrf_token), ex=ttl)
            result = LoginResult(
                response=WebAuthenticated(
                    session_ref=session_id,
                    audience=audience,
                    absolute_expires_at=expires,
                    idle_expires_at=now + idle,
                    server_time=now,
                ),
                web_cookie=web_cookie,
            )
            _log_login_result("succeeded", audience, user_id)
            return result
        refresh_token = new_opaque_token()
        refresh_key = resources.cache.key("auth", str(user_id), str(session_id), "refresh")
        refresh_payload = json.dumps(
            {"digest": crypto.digest("native-refresh", refresh_token).hex(), "generation": 1},
            separators=(",", ":"),
        )
        await resources.cache.client.set(alive_key, b"1", ex=ttl)
        await resources.cache.client.set(refresh_key, refresh_payload, ex=ttl)
        refresh_index = resources.cache.key(
            "auth", "refresh", "index", crypto.digest("native-refresh", refresh_token).hex()
        )
        await resources.cache.client.set(
            refresh_index, f"{user_id}:{session_id}:1", ex=max(1, int(absolute.total_seconds()))
        )
        access_expires = now + min(_ACCESS, absolute)
        result = LoginResult(
            response=NativeAuthenticated(
                session_ref=session_id,
                access_token=crypto.access_jwt(
                    user_id=user_id,
                    session_id=session_id,
                    generation=1,
                    expires_at=access_expires,
                ),
                access_expires_at=access_expires,
                refresh_token=refresh_token,
                refresh_expires_at=now + idle,
                session_generation=1,
                absolute_expires_at=expires,
                server_time=now,
            )
        )
        _log_login_result("succeeded", audience, user_id)
        return result
    except Exception:
        await _revoke_unissued(runtime, user_id=user_id, session_id=session_id)
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
