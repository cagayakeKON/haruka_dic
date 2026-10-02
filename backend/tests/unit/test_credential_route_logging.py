"""Credential business events occur only after route transaction completion."""

import logging
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import cast
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from pydantic import SecretStr
from starlette.requests import Request

from app.api import model_settings
from app.bootstrap import Resources, Runtime
from app.core.logging import SafeJsonFormatter
from app.core.settings import Settings
from app.domain.scope import ScopeContext
from app.schemas.model_settings import (
    CredentialCreate,
    CredentialDelete,
    CredentialRead,
    CredentialRotate,
)


@pytest.mark.asyncio
@pytest.mark.parametrize("action", ["create", "rotate", "delete"])
@pytest.mark.parametrize("failure", ["none", "service", "commit"])
async def test_credential_route_logs_only_after_commit(
    action: str, failure: str, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    session = MagicMock()
    session.__aenter__ = AsyncMock(return_value=session)
    session.__aexit__ = AsyncMock(return_value=False)
    transaction = MagicMock()
    transaction.__aenter__ = AsyncMock()
    committed = False

    async def finish(*_args: object) -> None:
        nonlocal committed
        if failure == "commit":
            raise RuntimeError("injected commit uncertainty")
        committed = failure != "service"

    transaction.__aexit__ = AsyncMock(side_effect=finish)
    session.begin.return_value = transaction
    resources = cast(Resources, SimpleNamespace(database=SimpleNamespace(sessions=lambda: session)))
    runtime = cast(Runtime, object())
    scope = cast(ScopeContext, object())
    monkeypatch.setattr(model_settings, "context", AsyncMock(return_value=(runtime, scope)))

    def selected_resources(_runtime: Runtime) -> Resources:
        return resources

    monkeypatch.setattr(model_settings, "resources", selected_resources)
    identifier = uuid4()
    now = datetime.now(UTC)
    result = CredentialRead(
        id=identifier,
        provider="openrouter",
        label="private label",
        masked_key="***",
        revision=1,
        credential_version=1,
        status="active",
        created_at=now,
        updated_at=now,
    )
    service = AsyncMock(return_value=result)
    if failure == "service":
        service.side_effect = RuntimeError("injected service rollback")
    name = {
        "create": "add_credential",
        "rotate": "rotate_credential",
        "delete": "delete_credential",
    }[action]
    monkeypatch.setattr(model_settings.config, name, service)
    request = Request({"type": "http", "headers": []})
    request.state.request_id = uuid4()
    sentinel = "synthetic-credential-log-sentinel"
    caplog.set_level(logging.INFO, logger=model_settings.logger.name)
    observed_commit_states: list[bool] = []
    original_info = model_settings.logger.info

    def observe_log(message: str, *, extra: dict[str, object]) -> None:
        observed_commit_states.append(committed)
        original_info(message, extra=extra)

    monkeypatch.setattr(model_settings.logger, "info", observe_log)

    async def invoke() -> None:
        if action == "create":
            await model_settings.create_credential(
                request, CredentialCreate(provider="openrouter", key=SecretStr(sentinel))
            )
        elif action == "rotate":
            await model_settings.rotate(
                request, identifier, CredentialRotate(expected_revision=1, key=SecretStr(sentinel))
            )
        else:
            await model_settings.revoke(request, identifier, CredentialDelete(expected_revision=1))

    if failure == "none":
        await invoke()
    else:
        with pytest.raises(RuntimeError):
            await invoke()
    events = [
        record
        for record in caplog.records
        if record.name == model_settings.logger.name
        and record.msg in {"credential.created", "credential.rotated", "credential.deleted"}
    ]
    if failure != "none":
        assert events == [] and observed_commit_states == []
        return
    assert committed and len(events) == 1 and observed_commit_states == [True]
    assert (
        events[0].msg
        == {
            "create": "credential.created",
            "rotate": "credential.rotated",
            "delete": "credential.deleted",
        }[action]
    )
    # Real production formatter never receives credentials, label or payload.
    formatter = SafeJsonFormatter(
        Settings.model_construct(app_env="test", instance_id="safe-instance"), "api"
    )
    rendered = formatter.format(events[0])
    assert sentinel not in rendered and "private label" not in rendered
    assert not any(
        key in events[0].__dict__ for key in ("key", "label", "payload", "encrypted_key")
    )
