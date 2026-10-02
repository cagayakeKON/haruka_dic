"""Session failure translation with explicit cache/database repository substitutes."""

import json
from base64 import urlsafe_b64encode
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from typing import cast
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.identity import User
from app.services import sessions as service
from app.services.sessions import _revoke_unissued  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


@dataclass
class Context:
    runtime: Runtime
    scope: ScopeContext
    session: AsyncSession
    cache: MagicMock


@pytest.fixture
def context() -> Context:
    runtime = Runtime(
        Settings(
            app_env="test",
            instance_id="haruka-test-session-boundaries",
            public_base_url="http://localhost:8000",
            auth_signing_key=SecretStr(urlsafe_b64encode(b"a" * 32).decode()),
            auth_digest_key=SecretStr(urlsafe_b64encode(b"b" * 32).decode()),
        )
    )
    session = MagicMock(spec=AsyncSession)
    session.begin.return_value.__aenter__ = AsyncMock(return_value=session)
    session.begin.return_value.__aexit__ = AsyncMock(return_value=False)
    database = MagicMock()
    database.sessions.return_value.__aenter__ = AsyncMock(return_value=session)
    database.sessions.return_value.__aexit__ = AsyncMock(return_value=False)
    cache = MagicMock()

    def cache_key(*parts: str) -> str:
        return ":".join(parts)

    cache.key.side_effect = cache_key
    cache.client.eval = AsyncMock(return_value=1)
    cache.client.delete = AsyncMock()
    runtime.resources = Resources(
        database=database, cache=cache, kafka=None, storage=None, consumer=None
    )
    scope = ScopeContext(
        user_id=uuid4(),
        session_id=uuid4(),
        audience="client",
        transport="web",
        user_authz_version=1,
        policy_authz_version=1,
        security_epoch=0,
        absolute_expires_at=datetime.now(UTC) + timedelta(hours=1),
    )
    return Context(runtime, scope, session, cache)


@pytest.mark.parametrize("operation", ["csrf", "renew"])
@pytest.mark.parametrize("failure", ["native", "absent", "invalid", "driver"])
async def test_web_session_cache_operations_fail_closed(
    context: Context,
    operation: str,
    failure: str,
) -> None:
    scope = context.scope
    expected = ErrorCode.SESSION_INVALID
    if failure == "native":
        scope = replace(scope, transport="native")
    elif failure == "absent":
        context.runtime.resources = None
        expected = ErrorCode.SERVICE_UNAVAILABLE
    elif failure == "invalid":
        context.cache.client.eval.return_value = 0
    else:
        context.cache.client.eval.side_effect = RuntimeError("private driver detail")
        expected = ErrorCode.SERVICE_UNAVAILABLE
    with pytest.raises(AppError) as error:
        if operation == "csrf":
            await service.issue_csrf(context.runtime, scope)
        else:
            await service.renew_web(context.runtime, scope, "synthetic cookie")
    assert error.value.code == expected
    assert "private driver detail" not in str(error.value)
    if failure in ("native", "absent"):
        context.cache.client.eval.assert_not_awaited()


async def test_expired_web_session_cannot_extend_idle_deadline(context: Context) -> None:
    scope = replace(context.scope, absolute_expires_at=datetime.now(UTC) - timedelta(seconds=1))
    with pytest.raises(AppError) as error:
        await service.renew_web(context.runtime, scope, "synthetic cookie")
    assert error.value.code == ErrorCode.SESSION_INVALID
    context.cache.client.eval.assert_not_awaited()


@pytest.mark.parametrize(
    "failure",
    [
        "missing_user",
        "wrong_password",
        "driver",
        "safe_error",
        "missing_revision",
        "missing_locked_user",
        "missing_session",
    ],
)
async def test_password_change_never_writes_after_failed_current_identity(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    failure: str,
) -> None:
    original_digest = sha256(b"synthetic repository digest").hexdigest()
    user = User(
        id=context.scope.user_id,
        password_hash=original_digest,
        password_version=2,
        security_epoch=3,
        revision=4,
    )
    observed = AsyncMock(return_value=user)
    verify = AsyncMock(return_value=True)
    hashed = AsyncMock(return_value="replacement hash")
    revision = AsyncMock(return_value=MagicMock(revision=1))
    locked_user = AsyncMock(return_value=user)
    active = AsyncMock(return_value=MagicMock())
    audit = AsyncMock()
    authorized = AsyncMock()
    if failure == "missing_user":
        observed.return_value = None
    elif failure == "wrong_password":
        verify.return_value = False
    elif failure == "driver":
        observed.side_effect = RuntimeError("private database detail")
    elif failure == "safe_error":
        observed.side_effect = AppError(ErrorCode.PERMISSION_DENIED)
    elif failure == "missing_revision":
        revision.return_value = None
    elif failure == "missing_locked_user":
        locked_user.return_value = None
    else:
        active.return_value = None
    for name, value in {
        "current_user": observed,
        "verify_password": verify,
        "hash_password": hashed,
        "global_revision_for_update": revision,
        "current_user_for_update": locked_user,
        "current_session_for_update": active,
        "append_identity_event": audit,
        "verify_scope_in_transaction": authorized,
    }.items():
        monkeypatch.setattr(service, name, value)
    with pytest.raises(AppError) as error:
        await service.change_password(
            context.runtime,
            context.scope,
            current_password=SecretStr("current"),
            new_password=SecretStr("new"),
        )
    expected = {
        "wrong_password": ErrorCode.AUTH_LOGIN_FAILED,
        "driver": ErrorCode.SERVICE_UNAVAILABLE,
        "safe_error": ErrorCode.PERMISSION_DENIED,
    }.get(failure, ErrorCode.SESSION_INVALID)
    assert error.value.code == expected
    assert user.password_hash == original_digest
    assert (user.password_version, user.security_epoch, user.revision) == (2, 3, 4)
    audit.assert_not_awaited()
    authorized.assert_not_awaited()
    context.cache.client.delete.assert_not_awaited()


@pytest.mark.parametrize("fault", ["missing", "foreign", "revoked", "database"])
async def test_unissued_session_cleanup_cannot_revoke_unrelated_session(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    fault: str,
) -> None:
    row = MagicMock(user_id=context.scope.user_id, revoked_at=None, revoke_reason_code=None)
    if fault == "foreign":
        row.user_id = uuid4()
    elif fault == "revoked":
        row.revoked_at = datetime.now(UTC)
    lookup = AsyncMock(return_value=None if fault == "missing" else row)
    if fault == "database":
        lookup.side_effect = RuntimeError("private database detail")
    monkeypatch.setattr(service, "global_revision_for_update", AsyncMock())
    monkeypatch.setattr(service, "user_for_refresh_for_update", AsyncMock())
    monkeypatch.setattr(service, "refresh_session_for_update", lookup)
    previous = row.revoked_at
    await _revoke_unissued(
        context.runtime, user_id=context.scope.user_id, session_id=context.scope.session_id
    )
    assert row.revoked_at == previous
    assert row.revoke_reason_code is None


async def test_unissued_cleanup_with_missing_resources_is_safe(context: Context) -> None:
    context.runtime.resources = None
    await _revoke_unissued(
        context.runtime, user_id=context.scope.user_id, session_id=context.scope.session_id
    )


@pytest.mark.parametrize(
    "codes,match,allowed,expected",
    [
        ([], "any", set[str](), False),
        (["read", "write"], "all", {"read"}, False),
        (["read", "write"], "all", {"read", "write"}, True),
        (["read", "write"], "any", {"read"}, True),
        (["read", "write"], "any", set[str](), False),
    ],
)
async def test_menu_visibility_uses_all_or_any_registered_permissions(
    codes: list[str],
    match: str,
    allowed: set[str],
    expected: bool,
) -> None:
    assert service.menu_visible(codes, match, allowed) is expected


@pytest.mark.parametrize(
    "fault",
    [
        "invalid_email",
        "missing_user",
        "wrong_password",
        "disabled",
        "lookup_driver",
        "lookup_safe",
        "missing_revision",
        "missing_locked_user",
        "locked",
        "password_race",
        "epoch_race",
        "inactive_race",
        "permission_denied",
        "transaction_driver",
    ],
)
async def test_login_never_issues_cache_credentials_after_identity_rejection(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    fault: str,
) -> None:
    context.runtime.schema_compatible = True
    original_digest = sha256(b"synthetic repository digest").hexdigest()
    user = User(
        id=context.scope.user_id,
        password_hash=original_digest,
        password_version=2,
        security_epoch=3,
        status="active",
        locked_until=None,
    )
    locked = User(
        id=user.id,
        password_hash=original_digest,
        password_version=2,
        security_epoch=3,
        status="active",
        locked_until=None,
    )
    lookup = AsyncMock(return_value=user)
    password_check = AsyncMock(return_value=True)
    revision = AsyncMock(return_value=MagicMock(revision=1))
    lock = AsyncMock(return_value=locked)
    permissions = AsyncMock()
    if fault == "missing_user":
        lookup.return_value = None
    elif fault == "wrong_password":
        password_check.return_value = False
    elif fault == "disabled":
        user.status = "disabled"
    elif fault == "lookup_driver":
        lookup.side_effect = RuntimeError("private database detail")
    elif fault == "lookup_safe":
        lookup.side_effect = AppError(ErrorCode.PERMISSION_DENIED)
    elif fault == "missing_revision":
        revision.return_value = None
    elif fault == "missing_locked_user":
        lock.return_value = None
    elif fault == "locked":
        locked.locked_until = datetime.now(UTC) + timedelta(hours=1)
    elif fault == "password_race":
        locked.password_version = 3
    elif fault == "epoch_race":
        locked.security_epoch = 4
    elif fault == "inactive_race":
        locked.status = "disabled"
    elif fault == "permission_denied":
        permissions.side_effect = AppError(ErrorCode.PERMISSION_DENIED)
    elif fault == "transaction_driver":
        lock.side_effect = RuntimeError("private lock detail")
    for name, value in {
        "user_by_email": lookup,
        "verify_password": password_check,
        "global_revision_for_update": revision,
        "user_for_login_for_update": lock,
        "require_permissions": permissions,
    }.items():
        monkeypatch.setattr(service, name, value)
    context.cache.client.set = AsyncMock()
    with pytest.raises(AppError) as error:
        await service.login(
            context.runtime,
            email="malformed" if fault == "invalid_email" else "member@example.com",
            password=SecretStr("synthetic submitted value"),
            audience="client",
            transport="web",
            platform="web",
        )
    expected = {
        "invalid_email": ErrorCode.INPUT_INVALID,
        "lookup_driver": ErrorCode.SERVICE_UNAVAILABLE,
        "transaction_driver": ErrorCode.SERVICE_UNAVAILABLE,
        "lookup_safe": ErrorCode.PERMISSION_DENIED,
    }.get(fault, ErrorCode.AUTH_LOGIN_FAILED)
    assert error.value.code == expected
    assert "private" not in str(error.value)
    cast(MagicMock, context.session.add).assert_not_called()
    context.cache.client.set.assert_not_awaited()
    if fault == "invalid_email":
        lookup.assert_not_awaited()


@pytest.mark.parametrize(
    "fault",
    [
        "missing_revision",
        "missing_user",
        "missing_target",
        "foreign_target",
        "wrong_audience",
        "database",
    ],
)
async def test_session_revoke_checks_target_scope_before_mutating(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    fault: str,
) -> None:
    revision = AsyncMock(return_value=MagicMock(revision=1))
    user = AsyncMock(return_value=MagicMock())
    target = MagicMock(user_id=context.scope.user_id, audience="client", revoked_at=None)
    lookup = AsyncMock(return_value=target)
    if fault == "missing_revision":
        revision.return_value = None
    elif fault == "missing_user":
        user.return_value = None
    elif fault == "missing_target":
        lookup.return_value = None
    elif fault == "foreign_target":
        target.user_id = uuid4()
    elif fault == "wrong_audience":
        target.audience = "admin"
    else:
        lookup.side_effect = RuntimeError("private database detail")
    audit = AsyncMock()
    for name, value in {
        "global_revision_for_update": revision,
        "current_user_for_update": user,
        "account_session_for_update": lookup,
        "verify_scope_in_transaction": AsyncMock(),
        "append_identity_event": audit,
    }.items():
        monkeypatch.setattr(service, name, value)
    with pytest.raises(AppError) as error:
        await service.revoke_session(context.runtime, context.scope, target_id=uuid4())
    expected = (
        ErrorCode.SESSION_INVALID
        if fault.startswith("missing_") and fault != "missing_target"
        else ErrorCode.SERVICE_UNAVAILABLE
        if fault == "database"
        else ErrorCode.RESOURCE_NOT_FOUND
    )
    assert error.value.code == expected
    assert target.revoked_at is None
    audit.assert_not_awaited()
    context.cache.client.delete.assert_not_awaited()


async def test_already_revoked_target_keeps_original_revocation_fact(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    original = datetime.now(UTC) - timedelta(minutes=1)
    target = MagicMock(
        id=uuid4(),
        user_id=context.scope.user_id,
        audience="client",
        revoked_at=original,
        revoke_reason_code="password_changed",
    )
    for name, value in {
        "global_revision_for_update": AsyncMock(return_value=MagicMock(revision=1)),
        "current_user_for_update": AsyncMock(return_value=MagicMock()),
        "verify_scope_in_transaction": AsyncMock(),
        "account_session_for_update": AsyncMock(return_value=target),
        "append_identity_event": AsyncMock(),
    }.items():
        monkeypatch.setattr(service, name, value)
    await service.revoke_session(context.runtime, context.scope, target_id=target.id)
    assert target.revoked_at == original
    assert target.revoke_reason_code == "password_changed"
    context.cache.client.delete.assert_awaited_once()


@pytest.mark.parametrize("row_count", [0, 2])
async def test_password_commit_seals_all_sessions_even_when_cache_delete_fails(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    row_count: int,
) -> None:
    digest = sha256(b"observed digest").hexdigest()
    replacement = sha256(b"replacement digest").hexdigest()
    user = User(
        id=context.scope.user_id,
        password_hash=digest,
        password_version=2,
        security_epoch=3,
        revision=4,
    )
    rows = [MagicMock(id=uuid4(), revoked_at=None) for _ in range(row_count)]
    audit = AsyncMock()
    for name, value in {
        "current_user": AsyncMock(return_value=user),
        "verify_password": AsyncMock(return_value=True),
        "hash_password": AsyncMock(return_value=replacement),
        "global_revision_for_update": AsyncMock(return_value=MagicMock(revision=8)),
        "current_user_for_update": AsyncMock(return_value=user),
        "current_session_for_update": AsyncMock(return_value=MagicMock()),
        "verify_scope_in_transaction": AsyncMock(),
        "active_sessions_for_scope": AsyncMock(return_value=rows),
        "append_identity_event": audit,
    }.items():
        monkeypatch.setattr(service, name, value)
    context.cache.client.delete.side_effect = RuntimeError("private cache detail")
    await service.change_password(
        context.runtime,
        context.scope,
        current_password=SecretStr("current"),
        new_password=SecretStr("new"),
    )
    assert user.password_hash == replacement
    assert (user.password_version, user.security_epoch, user.revision) == (3, 4, 5)
    assert all(
        row.revoked_at is not None and row.revoke_reason_code == "password_changed" for row in rows
    )
    assert context.cache.client.delete.await_count == row_count
    assert audit.await_args is not None
    assert audit.await_args.kwargs["action"] == "password.changed"


@pytest.mark.parametrize("granted", [False, True])
async def test_access_projection_filters_denied_catalog_entries_before_navigation(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    granted: bool,
) -> None:
    from app.models.authorization import PermissionCatalog

    rows = [
        PermissionCatalog(code="client.profile.read", data_scope="owner"),
        PermissionCatalog(code="client.login", data_scope="owner"),
    ]
    result = MagicMock()
    result.all.return_value = rows
    context.session.scalars = AsyncMock(return_value=result)
    current = AsyncMock(return_value=context.scope)
    grants = {("client.login", "owner")} if granted else set[tuple[str, str]]()
    navigation = AsyncMock(return_value=[])
    monkeypatch.setattr(service, "verify_scope_in_transaction", current)
    monkeypatch.setattr(service, "load_graph", AsyncMock())
    monkeypatch.setattr(service, "allowed_pairs", MagicMock(return_value=grants))
    monkeypatch.setattr(service, "project_navigation", navigation)
    access = await service.read_access(context.runtime, context.scope)
    assert [(p.code, p.data_scope) for p in access.permissions] == sorted(grants)
    assert access.user_id == context.scope.user_id
    assert access.session_ref == context.scope.session_id
    navigation.assert_awaited_once_with(
        context.session, audience="client", allowed={code for code, _ in grants}
    )


async def test_account_projection_rejects_disappeared_current_user(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(service, "verify_scope_in_transaction", AsyncMock())
    read = AsyncMock(return_value=None)
    monkeypatch.setattr(service, "current_user", read)
    with pytest.raises(AppError) as error:
        await service.read_account(context.runtime, context.scope)
    assert error.value.code == ErrorCode.SESSION_INVALID
    read.assert_awaited_once_with(context.session, context.scope)


@pytest.mark.parametrize("action", ["list", "revoke", "pending", "keys"])
async def test_missing_session_resources_never_report_success(
    context: Context, action: str
) -> None:
    from app.services.auth_crypto import AuthCrypto
    from app.services.sessions import (
        _pending_continuation,  # pyright: ignore[reportPrivateUsage]
        _session_keys,  # pyright: ignore[reportPrivateUsage]
    )

    context.runtime.resources = None
    with pytest.raises(AppError) as error:
        if action == "list":
            await service.list_sessions(context.runtime, context.scope, limit=20, cursor=None)
        elif action == "revoke":
            await service.revoke_session(
                context.runtime, context.scope, target_id=context.scope.session_id
            )
        elif action == "pending":
            await _pending_continuation(
                context.runtime,
                AuthCrypto.from_settings(context.runtime.settings),
                user_id=context.scope.user_id,
            )
        else:
            _session_keys(context.runtime, context.scope)
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE


@pytest.mark.parametrize(
    "fault",
    [
        "cas_lost",
        "cas_missing_receipt",
        "cas_received",
        "missing_latest",
        "bad_latest",
        "expired",
        "driver",
    ],
)
async def test_native_refresh_compare_swap_and_receipt_recovery_are_explicit(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    fault: str,
) -> None:
    from app.services.auth_crypto import AuthCrypto

    context.runtime.schema_compatible = True
    scope = replace(context.scope, transport="native")
    if fault == "expired":
        scope = replace(scope, absolute_expires_at=datetime.now(UTC) - timedelta(seconds=1))
    monkeypatch.setattr(service, "verify_scope_in_transaction", AsyncMock(return_value=scope))
    crypto = AuthCrypto.from_settings(context.runtime.settings)
    token = SecretStr("synthetic refresh value")
    digest = crypto.digest("native-refresh", token.get_secret_value()).hex()
    state = json.dumps({"digest": digest, "generation": 1}).encode()
    context.cache.client.get = AsyncMock(
        side_effect=[
            f"{scope.user_id}:{scope.session_id}:1".encode(),
            b"1",
            state,
        ]
    )
    recovery_pair: list[bytes] = []

    async def compare_swap(*args: object) -> object:
        if args[1] == 4:
            if fault == "driver":
                raise RuntimeError("private cache detail")
            if fault == "cas_lost":
                return -1
            latest = cast(str, args[8]).encode()
            receipt = cast(bytes, args[12])
            if fault == "cas_missing_receipt":
                receipt = b""
            elif fault == "missing_latest":
                latest = b""
            elif fault == "bad_latest":
                latest = b"{}"
            recovery_pair.extend([latest, receipt])
            return 0
        return recovery_pair

    context.cache.client.eval.side_effect = compare_swap
    if fault == "cas_received":
        recovered = await service.refresh_native(
            context.runtime, refresh_token=token, refresh_request_id=uuid4()
        )
        assert recovered.session_generation == 2
        assert recovered.session_ref == scope.session_id
        assert context.cache.client.eval.await_count == 2
    else:
        with pytest.raises(AppError) as error:
            await service.refresh_native(
                context.runtime, refresh_token=token, refresh_request_id=uuid4()
            )
        expected = (
            ErrorCode.REFRESH_SUPERSEDED
            if fault == "cas_missing_receipt"
            else ErrorCode.SERVICE_UNAVAILABLE
            if fault == "driver"
            else ErrorCode.SESSION_INVALID
        )
        assert error.value.code == expected
    if fault == "expired":
        context.cache.client.eval.assert_not_awaited()
