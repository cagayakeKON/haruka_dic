"""Real cookie, CSRF, RBAC and bearer paths for scoped telemetry ingestion."""

from datetime import UTC, datetime
from uuid import uuid4

import httpx2 as httpx
import pytest

from app.bootstrap import Runtime
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from tests.integration.test_authentication_flow import (
    _mail_token,  # pyright: ignore[reportPrivateUsage] - shared isolated mail fixture
)

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
ORIGIN = "https://localhost:18443"


def _batch(event_id: str, *, platform: str = "web", spoof: bool = False) -> dict[str, object]:
    event: dict[str, object] = {
        "event_id": event_id,
        "record_type": "analytics",
        "event": "app.started",
        "level": "info",
        "occurred_at": datetime.now(UTC).isoformat(),
        "client_platform": platform,
    }
    if spoof:
        event["user_id"] = str(uuid4())
    return {"client_session_id": str(uuid4()), "events": [event]}


async def test_authenticated_receiver_binds_owner_audience_and_transport(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    transport = httpx.ASGITransport(app=app)
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    password = "synthetic-client-password-2026"  # noqa: S105 - isolated identity
    shared_event = str(uuid4())

    async with httpx.AsyncClient(transport=transport, base_url=ORIGIN) as admin:
        login = await admin.post(
            "/api/v1/admin/auth/login",
            json={
                "email": f"admin-{run_id}@haruka.example.test",
                "password": "synthetic-admin-password-2026",
            },
            headers=headers,
        )
        assert login.status_code == 200
        admin_csrf = (await admin.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
        admin_headers = {**headers, "X-CSRF-Token": admin_csrf}
        admin_event = await admin.post(
            "/api/v1/admin/frontend-logs", json=_batch(shared_event), headers=admin_headers
        )
        assert admin_event.status_code == 200
        assert admin_event.json()["data"]["results"][0]["status"] == "accepted"
        policy = (await admin.get("/api/v1/admin/auth-policy")).json()["data"]
        opened = await admin.patch(
            "/api/v1/admin/auth-policy",
            json={"registration_mode": "open", "expected_revision": policy["revision"]},
            headers=admin_headers,
        )
        assert opened.status_code == 200

    for label in ("alice", "bob"):
        email = f"{label}-{run_id}@haruka.example.test"
        async with httpx.AsyncClient(transport=transport, base_url=ORIGIN) as visitor:
            registered = await visitor.post(
                "/api/v1/auth/register",
                json={"email": email, "password": password},
                headers=headers,
            )
            assert registered.status_code == 202
            token = await _mail_token(maintenance, runtime, email)
            verified = await visitor.post(
                "/api/v1/auth/email/verify", json={"token": token}, headers=headers
            )
            assert verified.status_code == 204
            login = await visitor.post(
                "/api/v1/auth/login",
                json={"email": email, "password": password},
                headers=headers,
            )
            assert login.status_code == 200
            csrf = (await visitor.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
            client_headers = {**headers, "X-CSRF-Token": csrf}
            accepted = await visitor.post(
                "/api/v1/frontend-logs", json=_batch(shared_event), headers=client_headers
            )
            assert accepted.status_code == 200
            assert accepted.json()["data"]["results"][0]["status"] == "accepted"
            replay = await visitor.post(
                "/api/v1/frontend-logs", json=_batch(shared_event), headers=client_headers
            )
            assert replay.status_code == 200
            assert replay.json()["data"]["results"][0]["status"] == "duplicate"
            spoofed = await visitor.post(
                "/api/v1/frontend-logs",
                json=_batch(str(uuid4()), spoof=True),
                headers=client_headers,
            )
            assert spoofed.status_code == 200
            assert spoofed.json()["data"]["results"][0]["reason"] == "invalid_record"
            assert (
                await visitor.post(
                    "/api/v1/frontend-logs", json=_batch(str(uuid4())), headers=headers
                )
            ).status_code == 403
            assert (
                await visitor.post(
                    "/api/v1/frontend-logs",
                    json=_batch(str(uuid4())),
                    headers={**client_headers, "Origin": "https://example.invalid"},
                )
            ).status_code == 403
            assert (
                await visitor.post(
                    "/api/v1/admin/frontend-logs", json=_batch(str(uuid4())), headers=client_headers
                )
            ).status_code == 401

    async with httpx.AsyncClient(transport=transport, base_url="http://127.0.0.1:18081") as native:
        logged = await native.post(
            "/api/v1/auth/native/login",
            json={
                "email": f"alice-{run_id}@haruka.example.test",
                "password": password,
                "platform": "windows",
            },
        )
        assert logged.status_code == 200
        bearer = {"Authorization": f"Bearer {logged.json()['data']['access_token']}"}
        accepted = await native.post(
            "/api/v1/frontend-logs", json=_batch(str(uuid4()), platform="windows"), headers=bearer
        )
        assert accepted.status_code == 200
        assert accepted.json()["data"]["results"][0]["status"] == "accepted"
        denied = await native.post(
            "/api/v1/admin/frontend-logs",
            json=_batch(str(uuid4()), platform="windows"),
            headers=bearer,
        )
        assert denied.status_code in {401, 403}
