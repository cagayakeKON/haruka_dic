"""Real PG optional strings and revoked-cookie telemetry rejection."""

import json
import logging
from datetime import UTC, datetime
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from sqlalchemy import select, update
from sqlalchemy.exc import DBAPIError

from app.bootstrap import Runtime
from app.core.logging import SafeJsonFormatter
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthPolicy, AuthSession, User, UserExtension
from tests.integration.test_authentication_flow import ORIGIN
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


async def test_pg_optional_string_preserves_null_empty_and_rejects_oversize(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    database = runtime.resources.database
    async with database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"string-{run_id}@haruka.example.test"
    async for _client, _headers in _owner(runtime, maintenance, email):
        async with database.sessions() as session:
            owner = await session.scalar(select(User.id).where(User.email_normalized == email))
            assert owner is not None
        for value in (None, "", "x" * 100):
            async with database.sessions() as session, session.begin():
                await session.execute(
                    update(UserExtension)
                    .where(UserExtension.user_id == owner)
                    .values(display_name=value, updated_at=datetime.now(UTC))
                )
            async with database.sessions() as session:
                stored = await session.scalar(
                    select(UserExtension.display_name).where(UserExtension.user_id == owner)
                )
                assert stored == value
                assert (stored is None) is (value is None)
        with pytest.raises(DBAPIError) as rejected:
            async with database.sessions() as session, session.begin():
                await session.execute(
                    update(UserExtension)
                    .where(UserExtension.user_id == owner)
                    .values(display_name="x" * 101, updated_at=datetime.now(UTC))
                )
        assert getattr(rejected.value.orig, "sqlstate", None) == "22001"
        async with database.sessions() as session:
            stored = await session.scalar(
                select(UserExtension.display_name).where(UserExtension.user_id == owner)
            )
            assert stored == "x" * 100


@pytest.mark.parametrize("audience", ["client", "admin"])
async def test_revoked_original_web_cookie_cannot_ingest_private_telemetry(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    audience: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    prefix = "/api/v1" + ("/admin" if audience == "admin" else "")
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    if audience == "client":
        async with runtime.resources.database.sessions() as session, session.begin():
            policy = await session.get(AuthPolicy, "registration", with_for_update=True)
            assert policy is not None
            policy.registration_mode = "open"
        # Prepare the account through real registration, email verification and login.
        async for _owner_client, _owner_headers in _owner(
            runtime, maintenance, f"receiver-{run_id}@haruka.example.test"
        ):
            pass
        email, password = (
            f"receiver-{run_id}@haruka.example.test",
            "synthetic-profile-password-2026",
        )
    else:
        email, password = f"admin-{run_id}@haruka.example.test", "synthetic-admin-password-2026"
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as client:
        logged = await client.post(
            prefix + "/auth/login", json={"email": email, "password": password}, headers=headers
        )
        assert logged.status_code == 200
        session_id = UUID(logged.json()["data"]["session_ref"])
        csrf = (await client.get(prefix + "/auth/csrf")).json()["data"]["csrf_token"]
        original_cookie = client.build_request("POST", prefix + "/frontend-logs").headers["cookie"]
        write_headers = {**headers, "X-CSRF-Token": csrf}
        revoked = await client.post(
            prefix + f"/auth/sessions/{session_id}/revoke", headers=write_headers
        )
        assert revoked.status_code == 204
        async with runtime.resources.database.sessions() as session:
            row = await session.get(AuthSession, session_id)
            assert row is not None and row.revoked_at is not None and row.audience == audience
            owner_id = row.user_id
        event_id = uuid4()
        caplog.set_level(logging.INFO)
        caplog.clear()
        rejected = await client.post(
            prefix + "/frontend-logs",
            json={
                "client_session_id": str(uuid4()),
                "events": [
                    {
                        "event_id": str(event_id),
                        "record_type": "analytics",
                        "event": "collection.saved",
                        "level": "info",
                        "occurred_at": datetime.now(UTC).isoformat(),
                        "client_platform": "web",
                        "attributes": {"card_type": "word", "result": "success"},
                    }
                ],
            },
            headers={**write_headers, "Cookie": original_cookie},
        )
        assert rejected.status_code == 401
        assert rejected.json()["error"]["code"] == "SESSION_INVALID"
        assert rejected.headers["x-request-id"]
        assert not any(record.msg == "frontend.received" for record in caplog.records)
        cache = runtime.resources.cache
        assert (
            await cache.client.get(
                cache.key("telemetry", "seen", audience, str(owner_id), str(event_id))
            )
            is None
        )
        safe = "\n".join(
            SafeJsonFormatter(runtime.settings, "api").format(record) for record in caplog.records
        )
        assert original_cookie not in safe and password not in safe
        assert str(event_id) not in safe
        # JSON response exposes trusted rejection metadata, never the submitted event.
        assert str(event_id) not in json.dumps(rejected.json())
