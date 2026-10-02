"""Identity continuation and cursor boundaries reject cross-scope or malformed facts."""

from base64 import urlsafe_b64encode
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from pydantic import SecretStr
from sqlalchemy.exc import IntegrityError

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.services import registration, sessions
from app.services.auth_crypto import AuthCrypto
from app.services.registration import _same_email_conflict  # pyright: ignore[reportPrivateUsage]
from app.services.sessions import (
    _decode_session_cursor,  # pyright: ignore[reportPrivateUsage]
    _encode_session_cursor,  # pyright: ignore[reportPrivateUsage]
)

pytestmark = pytest.mark.unit


@pytest.fixture
def identity_context() -> tuple[Runtime, ScopeContext]:
    runtime = Runtime(
        Settings(
            app_env="test",
            instance_id="haruka-test-cursor",
            public_base_url="http://localhost:8000",
            auth_signing_key=SecretStr(urlsafe_b64encode(b"a" * 32).decode()),
            auth_digest_key=SecretStr(urlsafe_b64encode(b"b" * 32).decode()),
        )
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
    return runtime, scope


def test_session_cursor_is_owner_and_audience_bound(
    identity_context: tuple[Runtime, ScopeContext],
) -> None:
    runtime, scope = identity_context
    created_at, row_id = datetime.now(UTC), uuid4()
    cursor = _encode_session_cursor(runtime, scope, created_at, row_id)
    assert _decode_session_cursor(runtime, scope, cursor) == (created_at, row_id)
    for other in (replace(scope, user_id=uuid4()), replace(scope, audience="admin")):
        with pytest.raises(AppError) as rejected:
            _decode_session_cursor(runtime, other, cursor)
        assert rejected.value.code == ErrorCode.INPUT_INVALID


@pytest.mark.parametrize(
    "value", ["", "one", ".two", "one.", "one.two.three", "a" * 257 + ".x", "a.x"]
)
def test_session_cursor_rejects_malformed_input(
    identity_context: tuple[Runtime, ScopeContext], value: str
) -> None:
    runtime, scope = identity_context
    with pytest.raises(AppError) as rejected:
        _decode_session_cursor(runtime, scope, value)
    assert rejected.value.code == ErrorCode.INPUT_INVALID
    assert value not in str(rejected.value) or not value


@pytest.mark.parametrize(
    "payload",
    [
        b"not json",
        b"{}",
        b'["2026-10-01", "not-uuid"]',
        b'["2026-10-01", "00000000-0000-0000-0000-000000000001"]',
    ],
)
def test_session_cursor_rejects_invalid_signed_payload(
    identity_context: tuple[Runtime, ScopeContext], payload: bytes
) -> None:
    runtime, scope = identity_context
    encoded = urlsafe_b64encode(payload).decode().rstrip("=")
    signature = AuthCrypto.from_settings(runtime.settings).digest(
        "session-cursor", f"{scope.user_id}:{scope.audience}:{encoded}"
    )
    cursor = f"{encoded}.{urlsafe_b64encode(signature).decode().rstrip('=')}"
    with pytest.raises(AppError) as rejected:
        _decode_session_cursor(runtime, scope, cursor)
    assert rejected.value.code == ErrorCode.INPUT_INVALID


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "operation",
    [
        "csrf",
        "account",
        "access",
        "list",
        "revoke",
        "renew",
        "refresh",
        "password",
        "login",
        "register",
        "activation",
        "challenge",
        "verify",
        "manual",
        "recover",
    ],
)
async def test_identity_operations_fail_closed_without_runtime_resources(
    identity_context: tuple[Runtime, ScopeContext], operation: str
) -> None:
    runtime, scope = identity_context
    with pytest.raises(AppError) as rejected:
        if operation == "csrf":
            await sessions.issue_csrf(runtime, scope)
        elif operation == "account":
            await sessions.read_account(runtime, scope)
        elif operation == "access":
            await sessions.read_access(runtime, scope)
        elif operation == "list":
            await sessions.list_sessions(runtime, scope, limit=10, cursor=None)
        elif operation == "revoke":
            await sessions.revoke_session(runtime, scope, target_id=uuid4())
        elif operation == "renew":
            await sessions.renew_web(runtime, scope, "synthetic-cookie")
        elif operation == "refresh":
            await sessions.refresh_native(
                runtime, refresh_token=SecretStr("synthetic-token"), refresh_request_id=uuid4()
            )
        elif operation == "password":
            await sessions.change_password(
                runtime,
                scope,
                current_password=SecretStr("synthetic-current"),
                new_password=SecretStr("synthetic-new"),
            )
        elif operation == "login":
            await sessions.login(
                runtime,
                email="user@example.test",
                password=SecretStr("synthetic-password"),
                audience="client",
                transport="web",
                platform="web",
            )
        elif operation == "register":
            await registration.register(
                runtime, email="user@example.test", password=SecretStr("synthetic-password")
            )
        elif operation == "activation":
            await registration.activation_status(runtime, continuation="synthetic-continuation")
        elif operation == "challenge":
            await registration.request_challenge(
                runtime, email="user@example.test", purpose="password_recovery"
            )
        elif operation == "verify":
            await registration.verify_email(runtime, token=SecretStr("synthetic-token"))
        elif operation == "manual":
            await registration.request_manual_recovery(runtime, email="user@example.test")
        else:
            await registration.complete_recovery(
                runtime, token=SecretStr("synthetic-token"), new_password=SecretStr("synthetic-new")
            )
    assert rejected.value.code == ErrorCode.SERVICE_UNAVAILABLE


@pytest.mark.asyncio
async def test_native_session_cannot_issue_web_csrf(
    identity_context: tuple[Runtime, ScopeContext],
) -> None:
    runtime, scope = identity_context
    with pytest.raises(AppError) as rejected:
        await sessions.issue_csrf(runtime, replace(scope, transport="native"))
    assert rejected.value.code == ErrorCode.SESSION_INVALID


@pytest.mark.parametrize(
    "sqlstate,constraint,depth,expected",
    [
        ("23505", "uq_users_email_normalized", 0, True),
        ("23505", "uq_users_email_normalized", 3, True),
        ("23505", "uq_users_email_normalized", 4, False),
        ("23505", "unrelated_unique", 0, False),
        ("23514", "uq_users_email_normalized", 0, False),
    ],
)
def test_registration_conflict_mapping_is_exact_and_bounded(
    sqlstate: str, constraint: str, depth: int, expected: bool
) -> None:
    class DriverError(Exception):
        sqlstate: str
        constraint_name: str

    driver = DriverError("synthetic driver failure")
    driver.sqlstate = sqlstate
    driver.constraint_name = constraint
    cause: Exception = driver
    for _ in range(depth):
        wrapper = Exception("synthetic wrapped driver failure")
        wrapper.__cause__ = cause
        cause = wrapper
    assert _same_email_conflict(IntegrityError("", {}, cause)) is expected
