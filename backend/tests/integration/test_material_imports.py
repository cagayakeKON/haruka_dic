"""Real authorized source HTTP with isolated PostgreSQL/Redis and private MinIO."""

import hashlib
from dataclasses import replace
from pathlib import Path
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from sqlalchemy import func, select

from app.adapters.storage import ObjectStorage
from app.bootstrap import Runtime
from app.core.settings import load_settings
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from app.models import (
    FileObject,
    Job,
    Material,
    MaterialImportIssue,
    MaterialRevision,
    OutboxEvent,
    UploadIntent,
    UserStorageState,
)
from app.services.material_jobs import execute_source_job
from tests.integration.test_profile_avatar import (
    _owner,  # pyright: ignore[reportPrivateUsage] -- existing real registration/login fixture, no HTTP bypass
)

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
ROOT = Path(__file__).resolve().parents[3]


async def test_real_upload_immutable_replay_language_checkpoint_metadata_and_isolation(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    template = load_settings(ROOT / "dev/.local/test.env")
    storage = ObjectStorage(template.infrastructure())
    await storage.check()
    runtime.resources = replace(runtime.resources, storage=storage)
    from app.models import AuthPolicy

    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    source = "これは日本語の小説です。今日はとてもいい天気です。".encode()
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    try:
        async for web, headers in _owner(
            runtime, maintenance, f"import-{run_id}@haruka.example.test"
        ):
            key = str(uuid4())
            payload = {
                "material_type": "novel",
                "language": "ja",
                "file": {
                    "filename": "私の原件.md",
                    "format": "md",
                    "size_bytes": len(source),
                    "sha256": hashlib.sha256(source).hexdigest(),
                },
            }
            cap = await web.get("/api/v1/material-import-capabilities")
            assert cap.status_code == 200
            assert (
                cap.json()["data"]["capabilities"][0]["format_max_size_bytes"]["md"] == 20_000_000
            )
            created = await web.post(
                "/api/v1/material-imports",
                json=payload,
                headers={**headers, "Idempotency-Key": key},
            )
            assert created.status_code == 201, created.text
            intent = created.json()["data"]
            replay = await web.post(
                "/api/v1/material-imports",
                json=payload,
                headers={**headers, "Idempotency-Key": key},
            )
            assert replay.json()["data"]["id"] == intent["id"]
            upload = intent["upload"]
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
            ) as temporary:
                assert (
                    await temporary.put(upload["url"], content=source, headers=upload["headers"])
                ).status_code == 204
                assert (
                    await temporary.put(
                        upload["url"],
                        content=source,
                        headers={**upload["headers"], "Authorization": "Bearer invalid"},
                    )
                ).status_code == 401
            finished = await web.post(
                f"/api/v1/uploads/{upload['id']}/complete",
                json={"expected_revision": intent["revision"]},
                headers={**headers, "Idempotency-Key": upload["id"]},
            )
            assert finished.status_code == 202, finished.text
            accepted = finished.json()["data"]
            assert accepted["status"] == "accepted" and accepted["upload"] is None
            again = await web.post(
                f"/api/v1/uploads/{upload['id']}/complete",
                json={"expected_revision": intent["revision"]},
                headers={**headers, "Idempotency-Key": upload["id"]},
            )
            assert again.json()["data"]["material_id"] == accepted["material_id"]
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="https://localhost:18443"
            ) as temporary:
                assert (
                    await temporary.put(upload["url"], content=source, headers=upload["headers"])
                ).status_code == 409
            async with runtime.resources.database.sessions() as session:
                file = await session.scalar(
                    select(FileObject).where(FileObject.upload_intent_id == UUID(upload["id"]))
                )
                assert file is not None and file.object_key and file.content is None
                assert await storage.get_bounded(file.object_key, len(source)) == source
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(Job)
                        .where(Job.id == UUID(accepted["job_id"]))
                    )
                    == 1
                )
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(OutboxEvent)
                        .where(OutboxEvent.event_type == "material.job.accepted")
                    )
                    == 1
                )
            await execute_source_job(runtime, UUID(accepted["job_id"]), "source-test")
            task = await web.get(f"/api/v1/jobs/{accepted['job_id']}")
            assert task.status_code == 200, task.text
            assert task.json()["data"]["state"] == "succeeded"
            assert (
                task.json()["data"]["credential_id"] is None
                and task.json()["data"]["run_id"] is None
            )
            catalog = await web.get(
                "/api/v1/materials",
                params={"search": "原件", "material_type": "novel", "language": "ja"},
            )
            assert catalog.status_code == 200 and len(catalog.json()["data"]) == 1
            metadata = catalog.json()["data"][0]
            assert metadata["readable"] is False and metadata["first_chapter_id"] is None
            assert metadata["source_status"] == "parsing"
            patched = await web.patch(
                f"/api/v1/materials/{metadata['id']}",
                json={"expected_revision": metadata["revision"], "title": "新标题"},
                headers=headers,
            )
            assert patched.status_code == 200, patched.text
            assert (
                await web.patch(
                    f"/api/v1/materials/{metadata['id']}",
                    json={"expected_revision": metadata["revision"], "title": "陈旧写入"},
                    headers=headers,
                )
            ).status_code == 409
            reused = await web.post(
                "/api/v1/material-imports",
                json={
                    "material_type": "textbook",
                    "language": "ja",
                    "source_material_id": metadata["id"],
                },
                headers={**headers, "Idempotency-Key": str(uuid4())},
            )
            assert reused.status_code == 201, reused.text
            assert (
                reused.json()["data"]["status"] == "accepted"
                and reused.json()["data"]["upload"] is None
            )
            async for other, _other_headers in _owner(
                runtime, maintenance, f"other-import-{run_id}@haruka.example.test"
            ):
                assert (await other.get(f"/api/v1/materials/{metadata['id']}")).status_code == 404
                assert (await other.get(f"/api/v1/jobs/{accepted['job_id']}")).status_code == 404
                assert (await other.get("/api/v1/materials")).json()["data"] == []
            latest = patched.json()["data"]
            assert (
                await web.delete(
                    f"/api/v1/materials/{metadata['id']}?expected_revision={latest['revision']}",
                    headers=headers,
                )
            ).status_code == 204
            assert (await web.get(f"/api/v1/materials/{metadata['id']}")).status_code == 404
            async with runtime.resources.database.sessions() as session:
                material = await session.get(Material, UUID(metadata["id"]))
                assert (
                    material is not None and material.delete_generation == 1 and material.deleted_at
                )
                assert await session.scalar(select(func.count()).select_from(MaterialRevision)) == 2
                assert (
                    await session.scalar(select(func.count()).select_from(MaterialImportIssue)) == 0
                )
                state = await session.scalar(
                    select(UserStorageState).where(UserStorageState.used_bytes > 0)
                )
                assert (
                    state is not None
                    and state.used_bytes == len(source)
                    and state.reserved_bytes == 0
                )
    finally:
        async with runtime.resources.database.sessions() as session:
            keys = [
                key
                for row in await session.scalars(
                    select(UploadIntent).where(UploadIntent.purpose == "primary_document")
                )
                for key in (row.staging_object_key, row.candidate_final_object_key)
                if key
            ]
        for key in keys:
            await storage.remove(key)
        await storage.aclose()
