"""Actual source language recovery and owner-serialized capacity boundaries."""

import asyncio
import hashlib
from collections.abc import AsyncIterator
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
import pytest_asyncio
from sqlalchemy import func, select

from app.adapters.storage import ObjectStorage
from app.bootstrap import Runtime
from app.core.settings import load_settings
from app.main import create_app
from app.maintenance.material_source_gc import collect_source_garbage
from app.maintenance.settings import MaintenanceSettings
from app.models import (
    AiRun,
    AuthPolicy,
    ExternalCallAttempt,
    FileObject,
    Job,
    JobStage,
    MaterialImport,
    MaterialRevision,
    OutboxEvent,
    UploadIntent,
    UserStorageReservation,
    UserStorageState,
)
from app.services import material_imports
from app.services.material_jobs import execute_source_job
from tests.integration.test_profile_avatar import (
    _owner,  # pyright: ignore[reportPrivateUsage] -- reuse real registration/login fixture
)
from tests.support.bound_client import BoundAsyncClient


async def test_concurrent_completion_and_late_worker_cannot_revive_deleted_material(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None and runtime.resources.storage is not None
    storage = runtime.resources.storage
    original = storage.get_bounded
    entered, release = asyncio.Event(), asyncio.Event()
    phase = "staging"

    async def paused(key: str, maximum: int) -> bytes:
        raw = await original(key, maximum)
        if f"material/{phase}/" in key:
            entered.set()
            await asyncio.wait_for(release.wait(), 15)
        return raw

    monkeypatch.setattr(storage, "get_bounded", paused)
    async for web, headers in _owner(runtime, maintenance, f"late-{run_id}@haruka.example.test"):
        raw = "これは日本語の小説です。今日はとてもいい天気です。".encode()
        created = await web.post(
            "/api/v1/material-imports",
            json={
                "material_type": "novel",
                "language": "ja",
                "file": {
                    "filename": "source.md",
                    "format": "md",
                    "size_bytes": len(raw),
                    "sha256": hashlib.sha256(raw).hexdigest(),
                },
            },
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert created.status_code == 201
        intent = created.json()["data"]
        upload = intent["upload"]
        app = create_app(runtime.settings)
        app.state.runtime = runtime
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
        ) as temporary:
            assert (
                await temporary.put(upload["url"], content=raw, headers=upload["headers"])
            ).status_code == 204
            url = f"/api/v1/uploads/{upload['id']}/complete"
            complete = asyncio.create_task(
                web.post(
                    url,
                    json={"expected_revision": intent["revision"]},
                    headers={**headers, "Idempotency-Key": upload["id"]},
                )
            )
            try:
                await asyncio.wait_for(entered.wait(), 10)
                assert (
                    await web.post(
                        url,
                        json={"expected_revision": intent["revision"]},
                        headers={**headers, "Idempotency-Key": upload["id"]},
                    )
                ).status_code == 409
                assert (
                    await temporary.put(upload["url"], content=raw, headers=upload["headers"])
                ).status_code == 409
            finally:
                release.set()
            accepted = await complete
        assert accepted.status_code == 202, accepted.text
        value = accepted.json()["data"]
        job_id, material_id = UUID(value["job_id"]), UUID(value["material_id"])
        phase = "final"
        entered.clear()
        release.clear()
        worker = asyncio.create_task(execute_source_job(runtime, job_id, "late-source"))
        try:
            await asyncio.wait_for(entered.wait(), 10)
            metadata = (await web.get(f"/api/v1/materials/{material_id}")).json()["data"]
            assert (
                await web.delete(
                    f"/api/v1/materials/{material_id}?expected_revision={metadata['revision']}",
                    headers=headers,
                )
            ).status_code == 204
        finally:
            release.set()
        await worker
        async with runtime.resources.database.sessions() as session:
            job = await session.get(Job, job_id)
            revision = (
                await session.get(
                    MaterialRevision, UUID(str(job.input_refs["material_revision_id"]))
                )
                if job
                else None
            )
            assert job is not None and job.state == "cancelled"
            assert (
                revision is not None
                and revision.status == "building"
                and revision.published_at is None
            )
            assert await session.scalar(select(func.count()).select_from(FileObject)) == 1
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(OutboxEvent)
                    .where(OutboxEvent.event_type == "material.import.completed")
                )
                == 0
            )


async def test_revoked_session_at_final_commit_does_not_publish_or_accept(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.models import AuthSession, User

    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None and runtime.resources.storage is not None
    storage = runtime.resources.storage
    original = storage.get_bounded
    entered, release = asyncio.Event(), asyncio.Event()

    async def paused(key: str, maximum: int) -> bytes:
        raw = await original(key, maximum)
        if "material/final/" in key:
            entered.set()
            await asyncio.wait_for(release.wait(), 15)
        return raw

    monkeypatch.setattr(storage, "get_bounded", paused)
    email = f"revoked-final-{run_id}@haruka.example.test"
    async for web, headers in _owner(runtime, maintenance, email):
        raw = b"This source must not be accepted after its session is revoked."
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
        assert created.status_code == 201
        intent = created.json()["data"]
        upload = intent["upload"]
        app = create_app(runtime.settings)
        app.state.runtime = runtime
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
        ) as temporary:
            assert (
                await temporary.put(upload["url"], content=raw, headers=upload["headers"])
            ).status_code == 204
            complete = asyncio.create_task(
                web.post(
                    f"/api/v1/uploads/{upload['id']}/complete",
                    json={"expected_revision": intent["revision"]},
                    headers={**headers, "Idempotency-Key": upload["id"]},
                )
            )
            try:
                await asyncio.wait_for(entered.wait(), 10)
                async with runtime.resources.database.sessions() as session, session.begin():
                    row = await session.scalar(
                        select(AuthSession)
                        .join(User, User.id == AuthSession.user_id)
                        .where(User.email == email)
                        .with_for_update()
                    )
                    assert row is not None
                    row.revoked_at = row.updated_at = datetime.now(UTC)
            finally:
                release.set()
            assert (await complete).status_code == 401
            assert (
                await temporary.put(upload["url"], content=raw, headers=upload["headers"])
            ).status_code == 401
        async with runtime.resources.database.sessions() as session:
            row = await session.get(MaterialImport, UUID(intent["id"]))
            assert row is not None and row.status == "verifying" and row.material_id is None
            assert await session.scalar(select(func.count()).select_from(Job)) == 0
            assert await session.scalar(select(func.count()).select_from(FileObject)) == 0
            state = await session.scalar(select(UserStorageState))
            assert state is not None and state.used_bytes == 0 and state.reserved_bytes == len(raw)


@pytest.mark.parametrize("code", ["client.exam.read", "client.exam.edit", "client.exam.import"])
async def test_reused_exam_rechecks_current_permissions_and_cancel_needs_only_cancel(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], code: str
) -> None:
    from app.models import AuthorizationRevision, PermissionCatalog

    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(
        runtime, maintenance, f"exam-reuse-{run_id}@haruka.example.test"
    ):
        material_id, _job = await accepted_source(
            runtime,
            web,
            headers,
            "これは日本語の試験です。今日はとてもいい天気です。".encode(),
            kind="exam",
        )
        target = "exam" if code == "client.exam.import" else "textbook"
        body = {"material_type": target, "language": "ja", "source_material_id": str(material_id)}
        key = str(uuid4())
        accepted = await web.post(
            "/api/v1/material-imports", json=body, headers={**headers, "Idempotency-Key": key}
        )
        assert accepted.status_code == 201, accepted.text
        job_id = UUID(accepted.json()["data"]["job_id"])
        second = await web.post(
            "/api/v1/material-imports",
            json=body,
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert second.status_code == 201
        second_job = UUID(second.json()["data"]["job_id"])
        async with runtime.resources.database.sessions() as session, session.begin():
            revision = await session.get(AuthorizationRevision, "global", with_for_update=True)
            permission = await session.get(PermissionCatalog, code, with_for_update=True)
            assert revision is not None and permission is not None
            permission.enabled = False
            permission.updated_at = revision.updated_at = datetime.now(UTC)
            revision.revision += 1
        assert (
            await web.post(
                "/api/v1/material-imports", json=body, headers={**headers, "Idempotency-Key": key}
            )
        ).status_code == 403
        catalog = await web.get("/api/v1/materials")
        assert catalog.status_code == 200 and len(catalog.json()["data"]) == 3
        assert all(item["readable"] is False for item in catalog.json()["data"])
        await execute_source_job(runtime, second_job, "recheck-reuse-permission")
        async with runtime.resources.database.sessions() as session:
            failed = await session.get(Job, second_job)
            assert (
                failed is not None
                and failed.state == "failed"
                and failed.error_code == "PERMISSION_DENIED"
            )
            retry_revision = failed.revision
        assert (
            await web.post(
                f"/api/v1/jobs/{second_job}/retry",
                json={"expected_revision": retry_revision},
                headers=headers,
            )
        ).status_code == 403
        state = await web.post(
            f"/api/v1/jobs/{job_id}/cancel", json={"expected_revision": 1}, headers=headers
        )
        assert state.status_code == 200 and state.json()["data"]["state"] == "cancelled", state.text
        await execute_source_job(runtime, job_id, "cancel-after-revoke")
        async with runtime.resources.database.sessions() as session:
            row = await session.get(Job, job_id)
            assert row is not None and row.state == "cancelled"


pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
ROOT = Path(__file__).resolve().parents[3]


async def accepted_source(
    runtime: Runtime,
    web: BoundAsyncClient,
    headers: dict[str, str],
    raw: bytes,
    *,
    kind: str = "novel",
    language: str = "ja",
) -> tuple[UUID, UUID]:
    created = await web.post(
        "/api/v1/material-imports",
        json={
            "material_type": kind,
            "language": language,
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
    upload = intent["upload"]
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
    ) as temporary:
        assert (
            await temporary.put(upload["url"], content=raw, headers=upload["headers"])
        ).status_code == 204
    response = await web.post(
        f"/api/v1/uploads/{upload['id']}/complete",
        json={"expected_revision": intent["revision"]},
        headers={**headers, "Idempotency-Key": upload["id"]},
    )
    assert response.status_code == 202, response.text
    return UUID(response.json()["data"]["material_id"]), UUID(response.json()["data"]["job_id"])


@pytest.mark.parametrize("failure", ["digest", "format", "expired"])
async def test_failed_or_expired_completion_does_not_commit_source_capacity(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], failure: str
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(
        runtime, maintenance, f"bad-source-{run_id}@haruka.example.test"
    ):
        raw = b"%PDF-1.7 invalid markdown" if failure == "format" else b"private source text"
        declared_digest = "a" * 64 if failure == "digest" else hashlib.sha256(raw).hexdigest()
        created = await web.post(
            "/api/v1/material-imports",
            json={
                "material_type": "novel",
                "language": "en",
                "file": {
                    "filename": "source.md",
                    "format": "md",
                    "size_bytes": len(raw),
                    "sha256": declared_digest,
                },
            },
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert created.status_code == 201
        intent = created.json()["data"]
        upload = intent["upload"]
        app = create_app(runtime.settings)
        app.state.runtime = runtime
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
        ) as temporary:
            assert (
                await temporary.put(upload["url"], content=raw, headers=upload["headers"])
            ).status_code == 204
            if failure == "expired":
                async with runtime.resources.database.sessions() as session, session.begin():
                    row = await session.get(
                        MaterialImport, UUID(intent["id"]), with_for_update=True
                    )
                    pending = await session.get(
                        UploadIntent, UUID(upload["id"]), with_for_update=True
                    )
                    assert row is not None and pending is not None
                    row.expires_at = pending.expires_at = datetime.now(UTC) - timedelta(seconds=1)
                    row.updated_at = pending.updated_at = datetime.now(UTC)
            response = await web.post(
                f"/api/v1/uploads/{upload['id']}/complete",
                json={"expected_revision": intent["revision"]},
                headers={**headers, "Idempotency-Key": upload["id"]},
            )
            assert (
                response.status_code == {"digest": 422, "format": 415, "expired": 410}[failure]
            ), response.text
            if failure == "expired":
                assert (
                    await temporary.put(upload["url"], content=raw, headers=upload["headers"])
                ).status_code == 410
                assert await collect_source_garbage(runtime) == (1, 0)
        async with runtime.resources.database.sessions() as session:
            row = await session.get(MaterialImport, UUID(intent["id"]))
            assert row is not None and row.status == (
                "expired" if failure == "expired" else "rejected"
            )
            state = await session.scalar(select(UserStorageState))
            assert state is not None and state.used_bytes == 0 and state.reserved_bytes == 0
            assert await session.scalar(select(func.count()).select_from(FileObject)) == 0
            assert await session.scalar(select(func.count()).select_from(Job)) == 0


async def test_deleted_cursor_and_shared_final_reference_retention(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None and runtime.resources.storage is not None
    raw = "これは日本語の小説です。今日はとてもいい天気です。".encode()
    async for web, headers in _owner(runtime, maintenance, f"cursor-{run_id}@haruka.example.test"):
        material_id, job_id = await accepted_source(runtime, web, headers, raw)
        await execute_source_job(runtime, job_id, "cursor-source")
        reused = await web.post(
            "/api/v1/material-imports",
            json={
                "material_type": "textbook",
                "language": "ja",
                "source_material_id": str(material_id),
            },
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert reused.status_code == 201, reused.text
        reused_id = UUID(reused.json()["data"]["material_id"])
        page = (await web.get("/api/v1/materials", params={"limit": 1})).json()
        anchor = page["data"][0]
        assert anchor["id"] == str(reused_id) and page["meta"]["has_more"]
        assert (
            await web.delete(
                f"/api/v1/materials/{reused_id}?expected_revision={anchor['revision']}",
                headers=headers,
            )
        ).status_code == 204
        next_page = await web.get(
            "/api/v1/materials", params={"limit": 1, "cursor": page["meta"]["next_cursor"]}
        )
        assert next_page.status_code == 200, next_page.text
        assert next_page.json()["data"][0]["id"] == str(material_id)
        assert await collect_source_garbage(runtime) == (0, 0)
        primary = next_page.json()["data"][0]
        assert (
            await web.delete(
                f"/api/v1/materials/{material_id}?expected_revision={primary['revision']}",
                headers=headers,
            )
        ).status_code == 204
        assert await collect_source_garbage(runtime) == (0, 1)
        assert await collect_source_garbage(runtime) == (0, 0)
        async with runtime.resources.database.sessions() as session:
            state = await session.scalar(select(UserStorageState))
            assert state is not None and state.used_bytes == 0 and state.reserved_bytes == 0


async def test_actual_source_websocket_owner_reconnect_and_current_revocation(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    import json
    import socket

    import uvicorn
    from websockets.asyncio.client import connect
    from websockets.exceptions import ConnectionClosed
    from websockets.typing import Origin

    from app.models import AuthSession

    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()
    listener.setblocking(False)
    address = f"ws://127.0.0.1:{listener.getsockname()[1]}/api/v1/jobs/events"
    server = uvicorn.Server(
        uvicorn.Config(
            app, log_config=None, access_log=False, lifespan="off", ws="websockets-sansio"
        )
    )
    serving = asyncio.create_task(server.serve(sockets=[listener]))
    try:
        async with asyncio.timeout(10):
            while not server.started:  # noqa: ASYNC110 -- Uvicorn's ready flag
                await asyncio.sleep(0.01)
        async for owner, headers in _owner(
            runtime, maintenance, f"source-ws-{run_id}@haruka.example.test"
        ):
            _material_id, job_id = await accepted_source(
                runtime,
                owner,
                headers,
                "これは日本語の小説です。今日はとてもいい天気です。".encode(),
            )
            cookie = "haruka_client_session=" + owner.cookies["haruka_client_session"]
            subscription = json.dumps(
                {"schema_version": 1, "type": "subscribe", "job_ids": [str(job_id)], "cursors": {}}
            )
            async with connect(
                address,
                origin=Origin("https://localhost:18443"),
                additional_headers={"Cookie": cookie},
            ) as stream:
                await stream.send(subscription)
                frame = json.loads(await asyncio.wait_for(stream.recv(), 5))
                assert (
                    frame["payload"]["operation_kind"] == "material_import"
                    and frame["payload"]["credential_id"] is None
                )
                await execute_source_job(runtime, job_id, "websocket-source")
                updated = json.loads(await asyncio.wait_for(stream.recv(), 5))
                assert updated["type"] == "completed" and updated["payload"]["state"] == "succeeded"
            async for other, _headers in _owner(
                runtime, maintenance, f"source-ws-other-{run_id}@haruka.example.test"
            ):
                async with connect(
                    address,
                    origin=Origin("https://localhost:18443"),
                    additional_headers={
                        "Cookie": "haruka_client_session=" + other.cookies["haruka_client_session"]
                    },
                ) as stream:
                    await stream.send(subscription)
                    with pytest.raises(ConnectionClosed):
                        await asyncio.wait_for(stream.recv(), 5)
            async with connect(
                address,
                origin=Origin("https://localhost:18443"),
                additional_headers={"Cookie": cookie},
            ) as reconnected:
                await reconnected.send(subscription)
                assert (
                    json.loads(await asyncio.wait_for(reconnected.recv(), 5))["payload"]["state"]
                    == "succeeded"
                )
                async with runtime.resources.database.sessions() as session, session.begin():
                    from app.models import Job

                    row = await session.scalar(
                        select(AuthSession)
                        .join(Job, Job.session_id == AuthSession.id)
                        .where(Job.id == job_id, Job.owner_user_id == AuthSession.user_id)
                        .with_for_update()
                    )
                    assert row is not None
                    row.revoked_at = row.updated_at = datetime.now(UTC)
                with pytest.raises(ConnectionClosed):
                    await asyncio.wait_for(reconnected.recv(), 5)
    finally:
        server.should_exit = True
        await asyncio.wait_for(serving, 10)
        listener.close()


@pytest_asyncio.fixture
async def source_runtime(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> AsyncIterator[tuple[Runtime, MaintenanceSettings, str]]:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    storage = ObjectStorage(load_settings(ROOT / "dev/.local/test.env").infrastructure())
    await storage.check()
    runtime.resources = replace(runtime.resources, storage=storage)
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    try:
        yield runtime, maintenance, run_id
    finally:
        async with runtime.resources.database.sessions() as session:
            keys = [
                key
                for row in await session.scalars(
                    select(UploadIntent).where(UploadIntent.purpose == "primary_document")
                )
                for key in (
                    row.staging_object_key,
                    row.candidate_final_object_key,
                    *row.retired_final_candidates,
                )
                if key
            ]
        for key in keys:
            await storage.remove(key)
        await storage.aclose()


async def test_language_confirmation_is_durable_idempotent_and_does_not_publish_reading(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    raw = b"This is an English source whose alphabet alone is not evidence of its language."
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async for web, headers in _owner(
        runtime, maintenance, f"language-{run_id}@haruka.example.test"
    ):
        created = await web.post(
            "/api/v1/material-imports",
            json={
                "material_type": "textbook",
                "language": "en",
                "file": {
                    "filename": "text.md",
                    "format": "md",
                    "size_bytes": len(raw),
                    "sha256": hashlib.sha256(raw).hexdigest(),
                },
            },
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert created.status_code == 201, created.text
        intent = created.json()["data"]
        upload = intent["upload"]
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
        ) as temporary:
            assert (
                await temporary.put(upload["url"], content=raw, headers=upload["headers"])
            ).status_code == 204
        accepted_response = await web.post(
            f"/api/v1/uploads/{upload['id']}/complete",
            json={"expected_revision": intent["revision"]},
            headers={**headers, "Idempotency-Key": upload["id"]},
        )
        assert accepted_response.status_code == 202, accepted_response.text
        accepted = accepted_response.json()["data"]
        identifier = UUID(accepted["job_id"])
        await execute_source_job(runtime, identifier, "language-test")
        blocked_response = await web.get(f"/api/v1/jobs/{identifier}")
        assert blocked_response.status_code == 200, blocked_response.text
        blocked = blocked_response.json()["data"]
        assert blocked["state"] == "blocked" and blocked["language_issue"] is not None
        async with runtime.resources.database.sessions() as session:
            revision = await session.get(MaterialRevision, UUID(blocked["material_revision_id"]))
            assert (
                revision is not None
                and revision.status == "building"
                and revision.published_at is None
            )
            stage = await session.scalar(
                select(JobStage).where(
                    JobStage.job_id == identifier, JobStage.stage_key == "language_assessment"
                )
            )
            assert (
                stage is not None
                and stage.state == "blocked"
                and stage.result_refs
                and stage.result_refs["language"] is None
            )
        confirmation = {
            "expected_revision": blocked["revision"],
            "language_confirmation": {
                "language": "en",
                "input_digest": blocked["language_issue"]["input_digest"],
                "expected_job_generation": blocked["generation"],
                "expected_issue_revision": blocked["language_issue"]["revision"],
            },
        }
        wrong = {
            **confirmation,
            "language_confirmation": {
                **confirmation["language_confirmation"],
                "input_digest": "00" * 32,
            },
        }
        assert (
            await web.post(
                f"/api/v1/jobs/{identifier}/retry",
                json=wrong,
                headers={**headers, "Idempotency-Key": str(uuid4())},
            )
        ).status_code == 409
        key = str(uuid4())
        recovered = await web.post(
            f"/api/v1/jobs/{identifier}/retry",
            json=confirmation,
            headers={**headers, "Idempotency-Key": key},
        )
        assert recovered.status_code == 200, recovered.text
        assert recovered.json()["data"]["state"] == "queued"
        assert (
            await web.post(
                f"/api/v1/jobs/{identifier}/retry",
                json=confirmation,
                headers={**headers, "Idempotency-Key": key},
            )
        ).status_code == 200
        assert (
            await web.post(
                f"/api/v1/jobs/{identifier}/retry",
                json=confirmation,
                headers={**headers, "Idempotency-Key": str(uuid4())},
            )
        ).status_code == 409
        await execute_source_job(runtime, identifier, "language-test-resumed")
        assert (await web.get(f"/api/v1/jobs/{identifier}")).json()["data"]["state"] == "succeeded"
        assert (await web.get(f"/api/v1/materials/{accepted['material_id']}")).json()["data"][
            "readable"
        ] is False
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(AiRun)) == 0
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(JobStage)
                    .where(JobStage.stage_key == "language_resolution")
                )
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(OutboxEvent)
                    .where(OutboxEvent.event_type == "material.import.needs_review")
                )
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(OutboxEvent)
                    .where(OutboxEvent.event_type == "material.import.completed")
                )
                == 1
            )


async def test_capacity_concurrency_cancel_and_expiry(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    monkeypatch.setattr(material_imports, "QUOTA_BYTES", 150)
    async for web, headers in _owner(
        runtime, maintenance, f"capacity-{run_id}@haruka.example.test"
    ):
        payload = {
            "material_type": "novel",
            "language": "en",
            "file": {
                "filename": "source.md",
                "format": "md",
                "size_bytes": 100,
                "sha256": hashlib.sha256(b"x" * 100).hexdigest(),
            },
        }
        first, second = await asyncio.gather(
            *(
                web.post(
                    "/api/v1/material-imports",
                    json=payload,
                    headers={**headers, "Idempotency-Key": str(uuid4())},
                )
                for _ in range(2)
            )
        )
        assert sorted((first.status_code, second.status_code)) == [201, 429]
        intent = (first if first.status_code == 201 else second).json()["data"]
        assert (
            await web.delete(
                f"/api/v1/material-imports/{intent['id']}?expected_revision={intent['revision']}",
                headers=headers,
            )
        ).status_code == 204
        assert (await web.get(f"/api/v1/material-imports/{intent['id']}")).json()["data"][
            "status"
        ] == "cancelled"
        replacement = await web.post(
            "/api/v1/material-imports",
            json=payload,
            headers={**headers, "Idempotency-Key": str(uuid4())},
        )
        assert replacement.status_code == 201
        replacement_intent = replacement.json()["data"]
        async with runtime.resources.database.sessions() as session, session.begin():
            row = await session.get(
                MaterialImport, UUID(replacement_intent["id"]), with_for_update=True
            )
            assert row is not None
            upload = await session.get(
                UploadIntent, row.primary_upload_intent_id, with_for_update=True
            )
            assert upload is not None
            row.expires_at = upload.expires_at = datetime.now(UTC) - timedelta(seconds=1)
            row.updated_at = upload.updated_at = datetime.now(UTC)
        assert await collect_source_garbage(runtime) == (1, 0)
        assert (await web.get(f"/api/v1/material-imports/{replacement_intent['id']}")).json()[
            "data"
        ]["status"] == "expired"
        assert await collect_source_garbage(runtime) == (0, 0)
        async with runtime.resources.database.sessions() as session:
            state = await session.scalar(select(UserStorageState))
            assert state is not None and state.reserved_bytes == 0 and state.used_bytes == 0
            assert set(await session.scalars(select(UserStorageReservation.status))) == {"released"}
