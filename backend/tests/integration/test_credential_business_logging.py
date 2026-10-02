"""Real isolated HTTP/PG credential commits produce safe business events."""

import json
import logging
from uuid import UUID, uuid4

import pytest
from cryptography.fernet import Fernet
from pydantic import SecretStr
from sqlalchemy import func, select

from app.bootstrap import Runtime
from app.core.logging import SafeJsonFormatter
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthPolicy
from app.models.model_tasks import ExternalCallAttempt, ProviderCredential
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


async def test_http_credential_commit_events_and_rejected_revision_are_safe(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], caplog: pytest.LogCaptureFixture
) -> None:
    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    events = {"credential.created", "credential.rotated", "credential.deleted"}
    caplog.set_level(logging.INFO, logger="app.api.model_settings")
    async for client, headers in _owner(
        runtime, maintenance, f"credential-log-{run_id}@haruka.example.test"
    ):
        caplog.clear()
        operation_ids = [str(uuid4()) for _ in range(5)]
        action_headers = [{**headers, "X-Operation-ID": value} for value in operation_ids]
        created = await client.post(
            "/api/v1/provider-credentials",
            headers=action_headers[0],
            json={
                "provider": "openrouter",
                "label": "private label must not log",
                "key": "synthetic-logging-key-one",
            },
        )
        assert created.status_code == 201
        credential = created.json()["data"]
        identifier = credential["id"]
        changed = await client.patch(
            f"/api/v1/provider-credentials/{identifier}",
            headers=action_headers[1],
            json={"expected_revision": credential["revision"], "key": "synthetic-logging-key-two"},
        )
        assert changed.status_code == 200
        rotated = changed.json()["data"]
        denied = await client.patch(
            f"/api/v1/provider-credentials/{identifier}",
            headers=action_headers[2],
            json={"expected_revision": credential["revision"], "key": "synthetic-rejected-key"},
        )
        assert denied.status_code == 409
        refused = await client.request(
            "DELETE",
            f"/api/v1/provider-credentials/{identifier}",
            headers=action_headers[3],
            json={"expected_revision": credential["revision"]},
        )
        assert refused.status_code == 409
        revoked = await client.request(
            "DELETE",
            f"/api/v1/provider-credentials/{identifier}",
            headers=action_headers[4],
            json={"expected_revision": rotated["revision"]},
        )
        assert revoked.status_code == 200
        records = [
            record
            for record in caplog.records
            if record.name == "app.api.model_settings" and record.msg in events
        ]
        assert [record.msg for record in records] == [
            "credential.created",
            "credential.rotated",
            "credential.deleted",
        ]
        formatter = SafeJsonFormatter(runtime.settings, "api")
        formatted = [formatter.format(record) for record in records]
        assert [json.loads(text)["operation_id"] for text in formatted] == [
            operation_ids[0],
            operation_ids[1],
            operation_ids[4],
        ]
        for text in formatted:
            row = json.loads(text)
            assert row["level"] == "info" and row["event"] in events
            assert UUID(row["request_id"]) and UUID(row["operation_id"]) and UUID(row["user_id"])
            assert "synthetic-" not in text and "private label" not in text
            assert "encrypted_key" not in text
        async with runtime.resources.database.sessions() as session:
            stored = await session.get(ProviderCredential, UUID(identifier))
            assert (
                stored is not None and stored.status == "revoked" and stored.encrypted_key is None
            )
            assert stored.revision == revoked.json()["data"]["revision"]
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
