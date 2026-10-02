"""Real source outcomes, private HTTP projections and committed read boundaries."""

import asyncio
import hashlib
import json
import logging
from collections.abc import AsyncIterator
from datetime import datetime
from typing import Any, Protocol, cast
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Runtime
from app.contracts.permissions import CLIENT_CODES
from app.core.logging import SafeJsonFormatter
from app.domain.correlation import current_log_context
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from app.models import AiRun, ExternalCallAttempt, OutboxEvent
from app.models.user_notifications import UserNotification
from app.services import user_notifications
from app.services.material_jobs import execute_source_job
from tests.integration.test_profile_avatar import (
    _owner,  # pyright: ignore[reportPrivateUsage] -- actual register/verify/login fixture
)
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_material_source_boundaries",)
ORIGIN = "https://localhost:18443"


class KeyScanner(Protocol):
    def scan_iter(self, *, match: str) -> AsyncIterator[bytes]: ...


async def accepted_event(
    runtime: Runtime, web: BoundAsyncClient, headers: dict[str, str]
) -> tuple[UUID, dict[str, Any]]:
    """Target source acceptance/worker actions use the actual authorized API."""
    assert runtime.resources is not None
    raw = b"This is an English source. Alphabet alone does not prove its language."
    created = await web.post(
        "/api/v1/material-imports",
        json={
            "material_type": "novel",
            "language": "en",
            "file": {
                "filename": "source.md",
                "format": "md",
                "size_bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
            },
        },
        headers={**headers, "Idempotency-Key": str(uuid4())},
    )
    assert created.status_code == 201, created.text
    intent = created.json()["data"]
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as upload:
        assert (
            await upload.put(
                intent["upload"]["url"], content=raw, headers=intent["upload"]["headers"]
            )
        ).status_code == 204
    accepted = await web.post(
        f"/api/v1/uploads/{intent['upload']['id']}/complete",
        json={"expected_revision": intent["revision"]},
        headers={**headers, "Idempotency-Key": intent["upload"]["id"]},
    )
    assert accepted.status_code == 202, accepted.text
    data = accepted.json()["data"]
    await execute_source_job(runtime, UUID(data["job_id"]), "notification-api-test")
    async with runtime.resources.database.sessions() as session:
        event = await session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.event_type == "material.import.needs_review",
                OutboxEvent.payload["job_id"].astext == data["job_id"],
            )
        )
        assert event is not None
        return event.id, data


async def admin(
    runtime: Runtime, run_id: str
) -> AsyncIterator[tuple[BoundAsyncClient, dict[str, str]]]:
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as client:
        headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
        response = await client.post(
            "/api/v1/admin/auth/login",
            json={
                "email": f"admin-{run_id}@haruka.example.test",
                "password": "synthetic-admin-password-2026",
            },
            headers=headers,
        )
        assert response.status_code == 200
        csrf = (await client.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
        yield client, {**headers, "X-CSRF-Token": csrf}


async def restrict(
    client: BoundAsyncClient, headers: dict[str, str], email: str, excluded: set[str]
) -> None:
    key = str(uuid4())
    created = await client.post(
        "/api/v1/admin/roles",
        json={"code": "notification_scope_" + uuid4().hex[:12], "name": "Notification scope"},
        headers={**headers, "Idempotency-Key": key},
    )
    assert created.status_code == 200, created.text
    role = created.json()["data"]
    found = await client.get("/api/v1/admin/users", params={"query": email})
    assert found.status_code == 200
    account = next(row for row in found.json()["data"] if row["email"] == email)
    roles = (await client.get("/api/v1/admin/roles", params={"limit": 100})).json()["data"]
    administrator_role = next(row for row in roles if row["code"] == "super_admin")
    existing = (
        await client.get(f"/api/v1/admin/roles/{administrator_role['id']}/grant-boundaries")
    ).json()["data"]
    boundaries = [
        {
            key: row[key]
            for key in ("boundary_kind", "target_role_id", "permission_code", "data_scope")
        }
        for row in existing
    ]
    additions = [
        {"boundary_kind": "assign_permission", "permission_code": code, "data_scope": "self"}
        for code in CLIENT_CODES
    ] + [
        {"boundary_kind": "assign_role", "target_role_id": role["role_id"]},
        {"boundary_kind": "manage_account_role", "target_role_id": role["role_id"]},
        *[
            {"boundary_kind": kind, "target_role_id": item["role_id"]}
            for item in account["roles"]
            for kind in ("manage_account_role", "assign_role")
        ],
    ]
    for addition in additions:
        if not any(
            all(row.get(key) == value for key, value in addition.items()) for row in boundaries
        ):
            boundaries.append(addition)
    ceiling = await client.post(
        f"/api/v1/admin/roles/{administrator_role['id']}/grant-boundaries",
        json={"expected_revision": administrator_role["revision"], "boundaries": boundaries},
        headers={**headers, "Idempotency-Key": str(uuid4())},
    )
    assert ceiling.status_code == 200, ceiling.text
    updated = await client.post(
        f"/api/v1/admin/roles/{role['role_id']}/grants",
        json={
            "expected_revision": role["revision"],
            "grants": [
                {"permission_code": code, "effect": "allow", "data_scope": "self"}
                for code in CLIENT_CODES
                if code not in excluded
            ],
        },
        headers={**headers, "Idempotency-Key": str(uuid4())},
    )
    assert updated.status_code == 200, updated.text
    response = await client.post(
        f"/api/v1/admin/users/{account['user_id']}/roles",
        json={"expected_revision": account["revision"], "role_ids": [role["role_id"]]},
        headers={**headers, "Idempotency-Key": str(uuid4())},
    )
    assert response.status_code == 200, response.text


async def test_snapshot_pages_and_old_timestamp_late_commit_remains_unread(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    entered, release = asyncio.Event(), asyncio.Event()
    original_get = AsyncSession.get
    calls = 0
    transaction_time: datetime | None = None
    async for web, headers in _owner(
        runtime, maintenance, f"snapshot-{run_id}@haruka.example.test"
    ):
        operation = uuid4()
        web.headers["X-Operation-ID"] = str(operation)
        caplog.set_level(logging.INFO, logger=user_notifications.logger.name)
        first_event, first_source = await accepted_event(runtime, web, headers)
        assert await user_notifications.consume_event(runtime, first_event)
        second_event, _ = await accepted_event(runtime, web, headers)

        async def paused(session: AsyncSession, entity: Any, ident: Any, **kwargs: Any) -> Any:
            nonlocal calls, transaction_time
            result = await original_get(session, entity, ident, **kwargs)
            task = asyncio.current_task()
            if (
                task is not None
                and task.get_name() == "late-notification"
                and entity is OutboxEvent
            ):
                calls += 1
                if calls == 2:
                    value = await session.scalar(select(func.transaction_timestamp()))
                    assert isinstance(value, datetime)
                    transaction_time = value
                    entered.set()
                    await asyncio.wait_for(release.wait(), 15)
            return result

        monkeypatch.setattr(AsyncSession, "get", paused)
        late = asyncio.create_task(
            user_notifications.consume_event(runtime, second_event), name="late-notification"
        )
        try:
            await asyncio.wait_for(entered.wait(), 10)
            old = await web.get("/api/v1/notifications", params={"limit": 1})
            assert old.status_code == 200, old.text
            boundary = old.json()["meta"]["snapshot_token"]
            assert old.json()["meta"]["unread_count"] == 1
        finally:
            release.set()
        assert await late
        assert (
            await web.post(
                "/api/v1/notifications/read-all", json={"snapshot_token": boundary}, headers=headers
            )
        ).json()["data"] == {"changed_count": 1, "unread_count": 1}
        current = (await web.get("/api/v1/notifications", params={"limit": 1})).json()
        assert current["meta"]["has_more"] and current["meta"]["unread_count"] == 1
        next_page = (
            await web.get(
                "/api/v1/notifications",
                params={"limit": 1, "cursor": current["meta"]["next_cursor"]},
            )
        ).json()
        assert next_page["meta"]["snapshot_token"] == current["meta"]["snapshot_token"]
        assert next_page["meta"]["snapshot_expires_at"] == current["meta"]["snapshot_expires_at"]
        assert current["data"][0]["id"] != next_page["data"][0]["id"]
        assert (
            await web.get(
                "/api/v1/notifications",
                params={"cursor": current["meta"]["next_cursor"], "unread_only": True},
            )
        ).status_code == 422
        newest = current["data"][0]
        assert newest["resource_available"] and newest["resource_version"] == 1
        read = await web.post(
            f"/api/v1/notifications/{newest['id']}/read", json={}, headers=headers
        )
        assert read.status_code == 200
        async with runtime.resources.database.sessions() as session:
            row = await session.get(UserNotification, UUID(newest["id"]))
            assert row is not None and row.created_at == transaction_time
            owner = str(row.owner_user_id)
            original_read, original_updated, revision = row.read_at, row.updated_at, row.revision
        repeated = await web.post(
            f"/api/v1/notifications/{newest['id']}/read", json={}, headers=headers
        )
        assert repeated.json()["data"]["read_at"] == read.json()["data"]["read_at"]
        async with runtime.resources.database.sessions() as session:
            row = await session.get(UserNotification, UUID(newest["id"]))
            assert row is not None and (row.read_at, row.updated_at, row.revision) == (
                original_read,
                original_updated,
                revision,
            )
        assert (
            await web.post(
                "/api/v1/notifications/read-all", json={"snapshot_token": boundary}, headers=headers
            )
        ).json()["data"] == {"changed_count": 0, "unread_count": 0}
        metadata = (await web.get(f"/api/v1/materials/{first_source['material_id']}")).json()[
            "data"
        ]
        assert metadata["source_revision_number"] == 1 and metadata["readable"] is False
        events = {
            "notification.list.loaded",
            "notification.read.updated",
            "notification.read_all.updated",
        }
        formatted = [
            json.loads(SafeJsonFormatter(runtime.settings, "api").format(record))
            for record in caplog.records
            if record.name == user_notifications.logger.name and record.msg in events
        ]
        assert {record["event"] for record in formatted} == events
        assert formatted[0]["request_id"] == old.json()["meta"]["request_id"]
        for record in formatted:
            UUID(record["request_id"])
            assert record["operation_id"] == str(operation)
            assert record["user_id"] == owner and record["audience"] == "client"
            assert "job_id" not in record and "ai_run_id" not in record
            assert (
                not {"snapshot_token", "cursor", "text", "title", "payload", "password"}
                & record.keys()
            )
        assert all(value is None for value in current_log_context().values())


async def test_private_audience_body_scope_and_independent_read_update_permissions(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    email = f"notify-a-{run_id}@haruka.example.test"
    async for a, headers in _owner(runtime, maintenance, email):
        event, source = await accepted_event(runtime, a, headers)
        assert await user_notifications.consume_event(runtime, event)
        page = (await a.get("/api/v1/notifications")).json()
        identifier, snapshot = page["data"][0]["id"], page["meta"]["snapshot_token"]
        renamed = await a.patch(
            f"/api/v1/materials/{source['material_id']}",
            json={"title": "Renamed source", "expected_revision": 1},
            headers=headers,
        )
        assert renamed.status_code == 200 and renamed.json()["data"]["revision"] == 2
        assert renamed.json()["data"]["source_revision_number"] == 1
        assert (await a.get("/api/v1/notifications")).json()["data"][0]["resource_available"]
        async for b, b_headers in _owner(
            runtime, maintenance, f"notify-b-{run_id}@haruka.example.test"
        ):
            assert (
                await b.post(f"/api/v1/notifications/{identifier}/read", json={}, headers=b_headers)
            ).status_code == 404
            assert (
                await b.post(
                    "/api/v1/notifications/read-all",
                    json={"snapshot_token": snapshot},
                    headers=b_headers,
                )
            ).status_code == 422
        assert (
            await a.post(
                f"/api/v1/notifications/{identifier}/read",
                json={"user_id": str(uuid4())},
                headers=headers,
            )
        ).status_code == 422
        app = create_app(runtime.settings)
        app.state.runtime = runtime
        async with BoundAsyncClient(
            transport=httpx.ASGITransport(app=app), base_url=ORIGIN
        ) as native:
            login = await native.post(
                "/api/v1/auth/native/login",
                json={
                    "email": email,
                    "password": "synthetic-profile-password-2026",
                    "platform": "android",
                },
                headers={"Content-Type": "application/json"},
            )
            assert login.status_code == 200
            bearer = {
                "Authorization": "Bearer " + login.json()["data"]["access_token"],
                "Content-Type": "application/json",
            }
            assert (await native.get("/api/v1/notifications", headers=bearer)).status_code == 200
            assert (
                await native.post(
                    f"/api/v1/notifications/{identifier}/read", json={}, headers=bearer
                )
            ).status_code == 200
        async for administrator, admin_headers in admin(runtime, run_id):
            assert (await administrator.get("/api/v1/notifications")).status_code != 200
            await restrict(
                administrator,
                admin_headers,
                email,
                {"client.notification.update", "client.material.read"},
            )
            generic = (await a.get("/api/v1/notifications")).json()["data"][0]
            assert (
                generic["message_code"] == "notification.resource_unavailable"
                and not generic["resource_available"]
            )
            assert all(
                generic[name] is None for name in ("resource_id", "resource_version", "route_key")
            )
            assert generic["job_id"] == source["job_id"] and generic["safe_parameters"] == {}
            assert (
                await a.post(f"/api/v1/notifications/{identifier}/read", json={}, headers=headers)
            ).status_code == 403
            await restrict(administrator, admin_headers, email, {"client.notification.read"})
            assert (await a.get("/api/v1/notifications")).status_code == 403
            assert (
                await a.post(
                    "/api/v1/notifications/read-all",
                    json={"snapshot_token": snapshot},
                    headers=headers,
                )
            ).status_code == 403


async def test_notification_read_facts_survive_owned_redis_loss_and_source_delete(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    email = f"durable-notify-{run_id}@haruka.example.test"
    async for web, headers in _owner(runtime, maintenance, email):
        event, source = await accepted_event(runtime, web, headers)
        assert await user_notifications.consume_event(runtime, event)
        page = (await web.get("/api/v1/notifications")).json()
        row = page["data"][0]
        marked = await web.post(f"/api/v1/notifications/{row['id']}/read", json={}, headers=headers)
        assert marked.status_code == 200
        original_read = marked.json()["data"]["read_at"]
        cache = runtime.resources.cache
        assert cache.namespace == "haruka-test-" + run_id
        scanner = cast(KeyScanner, cache.client)
        keys = [key async for key in scanner.scan_iter(match=cache.namespace + ":*")]
        assert all(
            isinstance(key, bytes) and key.startswith((cache.namespace + ":").encode())
            for key in keys
        )
        if keys:
            await cache.client.delete(*keys)
        assert (await web.get("/api/v1/notifications")).status_code == 401
        assert (
            await web.post(
                "/api/v1/auth/login",
                json={"email": email, "password": "synthetic-profile-password-2026"},
                headers={"Origin": ORIGIN, "Content-Type": "application/json"},
            )
        ).status_code == 200
        recovered = (await web.get("/api/v1/notifications")).json()
        assert (
            recovered["meta"]["unread_count"] == 0
            and recovered["data"][0]["read_at"] == original_read
        )
        csrf = (await web.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        assert (
            await web.delete(
                f"/api/v1/materials/{source['material_id']}?expected_revision=1",
                headers={**headers, "X-CSRF-Token": csrf},
            )
        ).status_code == 204
        unavailable = (await web.get("/api/v1/notifications")).json()["data"][0]
        assert (
            unavailable["message_code"] == "notification.resource_unavailable"
            and unavailable["resource_id"] is None
        )
        assert unavailable["read_at"] == original_read and unavailable["job_id"] == source["job_id"]
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(AiRun)) == 0
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
