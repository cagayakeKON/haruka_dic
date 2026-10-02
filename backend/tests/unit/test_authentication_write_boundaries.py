"""Real route transport guards with a substituted authenticated scope/service sink."""

from dataclasses import replace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from fastapi import FastAPI, Request, Response
from pydantic import SecretStr

from app.api import authentication as api
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.schemas.auth import PasswordChangeRequest
from app.services.auth_crypto import AuthCrypto
from tests.unit.test_session_service_boundaries import Context
from tests.unit.test_session_service_boundaries import context as context

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


def request_for(context: Context, headers: dict[str, str]) -> Request:
    app = FastAPI()
    context.runtime.schema_compatible = True
    app.state.runtime = context.runtime
    return Request(
        {
            "state": {"request_id": uuid4()},
            "type": "http",
            "method": "POST",
            "path": "/api/v1/auth/logout",
            "headers": [(k.encode(), v.encode()) for k, v in headers.items()],
            "app": app,
        }
    )


@pytest.mark.parametrize(
    "action", ["client_logout", "admin_logout", "client_refresh", "admin_refresh"]
)
@pytest.mark.parametrize("failure", ["missing_bearer", "cookie", "origin", "fetch", "media"])
async def test_native_write_guard_rejects_browser_metadata_before_mutation(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    action: str,
    failure: str,
) -> None:
    audience = "admin" if action.startswith("admin") else "client"
    scope = replace(context.scope, transport="native", audience=audience)
    authenticated = AsyncMock(return_value=scope)
    mutate = AsyncMock()
    monkeypatch.setattr(api, "require_scope", authenticated)
    monkeypatch.setattr(api, "revoke_session", mutate)
    monkeypatch.setattr(api, "renew_web", mutate)
    headers = {"authorization": "Bearer synthetic", "content-type": "application/json"}
    if failure == "missing_bearer":
        del headers["authorization"]
    elif failure == "media":
        headers["content-type"] = "text/plain"
    else:
        headers[{"cookie": "cookie", "origin": "origin", "fetch": "sec-fetch-site"}[failure]] = (
            "synthetic"
        )
    request = request_for(context, headers)
    with pytest.raises(AppError) as error:
        if action == "client_logout":
            await api.logout_client(request, Response())
        elif action == "admin_logout":
            await api.logout_admin(request)
        elif action == "client_refresh":
            await api.refresh_client_web(request)
        else:
            await api.refresh_admin_web(request)
    assert error.value.code == (
        ErrorCode.MEDIA_TYPE_UNSUPPORTED if failure == "media" else ErrorCode.SESSION_INVALID
    )
    authenticated.assert_awaited_once_with(request, audience=audience)
    mutate.assert_not_awaited()


@pytest.mark.parametrize("action", ["client", "admin"])
async def test_web_refresh_cannot_accept_authenticated_native_scope(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    action: str,
) -> None:
    scope = replace(
        context.scope, transport="native", audience="admin" if action == "admin" else "client"
    )
    monkeypatch.setattr(api, "require_scope", AsyncMock(return_value=scope))
    renew = AsyncMock()
    monkeypatch.setattr(api, "renew_web", renew)
    request = request_for(
        context, {"authorization": "Bearer synthetic", "content-type": "application/json"}
    )
    with pytest.raises(AppError) as error:
        await (
            api.refresh_admin_web(request) if action == "admin" else api.refresh_client_web(request)
        )
    assert error.value.code == ErrorCode.SESSION_INVALID
    renew.assert_not_awaited()


@pytest.mark.parametrize("failure", ["missing_token", "wrong_digest", "cache_outage"])
async def test_web_logout_csrf_failures_do_not_revoke_session(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    failure: str,
) -> None:
    monkeypatch.setattr(api, "require_scope", AsyncMock(return_value=context.scope))
    revoke = AsyncMock()
    monkeypatch.setattr(api, "revoke_session", revoke)
    context.cache.client.get = AsyncMock(return_value=b"not matching digest")
    headers = {
        "origin": context.runtime.settings.public_base_url,
        "content-type": "application/json",
    }
    if failure != "missing_token":
        headers["x-csrf-token"] = "a" * 43
    if failure == "cache_outage":
        context.cache.client.get.side_effect = RuntimeError("private cache detail")
    with pytest.raises(AppError) as error:
        await api.logout_client(request_for(context, headers), Response())
    assert error.value.code == (
        ErrorCode.SERVICE_UNAVAILABLE if failure == "cache_outage" else ErrorCode.CSRF_FAILED
    )
    revoke.assert_not_awaited()


@pytest.mark.parametrize("runtime_state", ["absent", "inactive"])
@pytest.mark.parametrize("endpoint", ["meta", "policy"])
async def test_public_identity_entry_has_no_fabricated_success_when_unwired(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    runtime_state: str,
    endpoint: str,
) -> None:
    request = request_for(context, {})
    if runtime_state == "absent":
        request.app.state.runtime = None
    else:
        context.runtime.active = False
    policy = AsyncMock(side_effect=AppError(ErrorCode.SERVICE_UNAVAILABLE))
    monkeypatch.setattr(api, "read_public_policy", policy)
    with pytest.raises(AppError) as error:
        await (api.public_meta(request) if endpoint == "meta" else api.auth_policy(request))
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    if runtime_state == "absent" or endpoint == "meta":
        policy.assert_not_awaited()


@pytest.mark.parametrize("audience", ["client", "admin"])
@pytest.mark.parametrize("operation", ["target", "all", "password"])
async def test_authenticated_web_actions_preserve_audience_target_and_empty_response(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    audience: str,
    operation: str,
) -> None:
    scope = replace(context.scope, audience="admin" if audience == "admin" else "client")
    authenticated = AsyncMock(return_value=scope)
    mutate = AsyncMock()
    monkeypatch.setattr(api, "require_scope", authenticated)
    monkeypatch.setattr(api, "revoke_session", mutate)
    monkeypatch.setattr(api, "change_password", mutate)
    token = "a" * 43
    context.cache.client.get = AsyncMock(
        return_value=AuthCrypto.from_settings(context.runtime.settings).digest("csrf", token)
    )
    request = request_for(
        context,
        {
            "origin": context.runtime.settings.public_base_url,
            "content-type": "application/json",
            "x-csrf-token": token,
        },
    )
    target = uuid4()
    if operation == "target":
        response = await (
            api.revoke_admin_session(request, target)
            if audience == "admin"
            else api.revoke_client_session(request, target)
        )
        mutate.assert_awaited_once_with(context.runtime, scope, target_id=target)
    elif operation == "all":
        response = await (
            api.revoke_all_admin_sessions(request)
            if audience == "admin"
            else api.revoke_all_client_sessions(request)
        )
        mutate.assert_awaited_once_with(
            context.runtime, scope, target_id=scope.session_id, all_audience=True
        )
    else:
        payload = PasswordChangeRequest(
            current_password=SecretStr("synthetic current"),
            new_password=SecretStr("synthetic replacement"),
        )
        response = await (
            api.change_admin_password(request, payload)
            if audience == "admin"
            else api.change_client_password(request, payload)
        )
        mutate.assert_awaited_once_with(
            context.runtime,
            scope,
            current_password=payload.current_password,
            new_password=payload.new_password,
        )
    assert response.status_code == 204
    assert response.body == b""
    authenticated.assert_awaited_once_with(request, audience=audience)


@pytest.mark.parametrize("next_cursor", [None, "owner-bound-next-cursor"])
async def test_admin_session_page_preserves_pagination_and_admin_scope(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    next_cursor: str | None,
) -> None:
    scope = replace(context.scope, audience="admin")
    authenticated = AsyncMock(return_value=scope)
    page = AsyncMock(return_value=([], next_cursor))
    monkeypatch.setattr(api, "require_scope", authenticated)
    monkeypatch.setattr(api, "list_sessions", page)
    request = request_for(context, {})
    result = await api.admin_sessions(request, limit=17, cursor="prior-owner-cursor")
    assert result.data == []
    assert result.meta.next_cursor == next_cursor
    assert result.meta.has_more == (next_cursor is not None)
    authenticated.assert_awaited_once_with(request, audience="admin")
    page.assert_awaited_once_with(context.runtime, scope, limit=17, cursor="prior-owner-cursor")
