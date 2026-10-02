"""Current durable authority, correctable language and generation-owned source copies."""

import asyncio
import hashlib
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from minio.error import S3Error
from sqlalchemy import select

from app.bootstrap import Runtime
from app.domain.correlation import current_log_context
from app.main import create_app
from app.maintenance.material_source_gc import collect_source_garbage
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthSession, Job, Material, MaterialRevision, UploadIntent, UserStorageState
from app.services.material_jobs import execute_source_job
from tests.integration.test_material_source_boundaries import accepted_source, source_runtime
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
assert source_runtime


async def test_committed_source_job_survives_logout_expiry_and_restores_log_context(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None and runtime.resources.storage is not None
    storage = runtime.resources.storage
    original = storage.get_bounded
    before = current_log_context()
    observed: list[dict[str, object]] = []
    entered, release = asyncio.Event(), asyncio.Event()
    pause = False

    async def read(key: str, maximum: int) -> bytes:
        if "material/final/" in key:
            observed.append(current_log_context())
            if pause:
                entered.set()
                await asyncio.wait_for(release.wait(), 15)
        return await original(key, maximum)

    monkeypatch.setattr(storage, "get_bounded", read)
    for during in (False, True):
        async for web, headers in _owner(
            runtime, maintenance, f"durable-{during}-{run_id}@haruka.example.test"
        ):
            _material, identifier = await accepted_source(
                runtime, web, headers, "これは日本語の小説です。今日はとてもいい天気です。".encode()
            )
            pause = during
            observed.clear()
            worker = (
                asyncio.create_task(execute_source_job(runtime, identifier, "durable-source"))
                if during
                else None
            )
            if during:
                await asyncio.wait_for(entered.wait(), 10)
            logout = await web.post("/api/v1/auth/logout", headers=headers)
            assert logout.status_code == 204, logout.text
            async with runtime.resources.database.sessions() as session, session.begin():
                job = await session.get(Job, identifier)
                assert job is not None
                auth = await session.get(AuthSession, job.session_id, with_for_update=True)
                assert auth is not None and auth.revoked_at is not None
                auth.absolute_expires_at = datetime.now(UTC) - timedelta(seconds=1)
                auth.updated_at = datetime.now(UTC)
                request_id, operation_id = job.request_id, job.operation_id
            if worker:
                release.set()
                await worker
            else:
                await execute_source_job(runtime, identifier, "durable-source")
            assert observed and observed[-1]["job_id"] == identifier
            assert (
                observed[-1]["request_id"] == request_id
                and observed[-1]["operation_id"] == operation_id
            )
            assert observed[-1]["ai_run_id"] is None and current_log_context() == before
            async with runtime.resources.database.sessions() as session:
                job = await session.get(Job, identifier)
                assert job is not None and job.state == "succeeded"


@pytest.mark.parametrize(
    "raw",
    ["これは日本語の小説です。今日はとてもいい天気です。", "日本経済新聞東京本社国際市場報告"],
)
async def test_input_checkpoint_can_correct_declared_english_to_japanese(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], raw: str
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(
        runtime, maintenance, f"correct-language-{run_id}@haruka.example.test"
    ):
        material_id, identifier = await accepted_source(
            runtime, web, headers, raw.encode(), language="en"
        )
        await execute_source_job(runtime, identifier, "language-assessment")
        blocked = (await web.get(f"/api/v1/jobs/{identifier}")).json()["data"]
        assert blocked["state"] == "blocked" and blocked["language_issue"] is not None
        body = {
            "expected_revision": blocked["revision"],
            "language_confirmation": {
                "language": "ja",
                "input_digest": blocked["language_issue"]["input_digest"],
                "expected_job_generation": blocked["generation"],
                "expected_issue_revision": blocked["language_issue"]["revision"],
            },
        }
        key = str(uuid4())
        confirmed = await web.post(
            f"/api/v1/jobs/{identifier}/retry",
            json=body,
            headers={**headers, "Idempotency-Key": key},
        )
        assert confirmed.status_code == 200, confirmed.text
        assert (
            await web.post(
                f"/api/v1/jobs/{identifier}/retry",
                json=body,
                headers={**headers, "Idempotency-Key": key},
            )
        ).status_code == 200
        await execute_source_job(runtime, identifier, "corrected-language")
        metadata = (await web.get(f"/api/v1/materials/{material_id}")).json()["data"]
        assert metadata["language"] == "ja" and metadata["readable"] is False
        assert (await web.get(f"/api/v1/jobs/{identifier}")).json()["data"]["state"] == "succeeded"


@pytest.mark.parametrize("boundary", ["takeover", "cancel"])
async def test_generation_owned_candidates_survive_late_put_and_repeated_gc(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    boundary: str,
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None and runtime.resources.storage is not None
    storage = runtime.resources.storage
    put = storage.put
    entered, release = asyncio.Event(), asyncio.Event()
    old_key: str | None = None

    async def paused(key: str, raw: bytes) -> None:
        nonlocal old_key
        if "material/final/" in key and old_key is None:
            old_key = key
            entered.set()
            await asyncio.wait_for(release.wait(), 20)
        await put(key, raw)

    monkeypatch.setattr(storage, "put", paused)
    async for web, headers in _owner(
        runtime, maintenance, f"candidate-{run_id}@haruka.example.test"
    ):
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
        old = asyncio.create_task(
            web.post(
                url,
                json={"expected_revision": intent["revision"]},
                headers={**headers, "Idempotency-Key": upload["id"]},
            )
        )
        try:
            await asyncio.wait_for(entered.wait(), 10)
            assert old_key is not None
            async with runtime.resources.database.sessions() as session, session.begin():
                row = await session.get(UploadIntent, UUID(upload["id"]), with_for_update=True)
                assert row is not None
                row.completion_lease_until_at = datetime.now(UTC) - timedelta(seconds=1)
                row.updated_at = datetime.now(UTC)
            verifying = (await web.get(f"/api/v1/material-imports/{intent['id']}")).json()["data"]
            assert verifying["status"] == "verifying"
            if boundary == "takeover":
                accepted = await web.post(
                    url,
                    json={"expected_revision": verifying["revision"]},
                    headers={**headers, "Idempotency-Key": upload["id"]},
                )
                assert accepted.status_code == 202, accepted.text
                async with runtime.resources.database.sessions() as session:
                    row = await session.get(UploadIntent, UUID(upload["id"]))
                    assert row is not None and row.candidate_final_object_key != old_key
                    current_key = row.candidate_final_object_key
                assert (
                    current_key is not None
                    and await storage.get_bounded(current_key, len(raw)) == raw
                )
            else:
                assert (
                    await web.delete(
                        f"/api/v1/material-imports/{intent['id']}?expected_revision={verifying['revision']}",
                        headers=headers,
                    )
                ).status_code == 204
            await collect_source_garbage(runtime)
        finally:
            release.set()
        late = await old
        assert late.status_code == (202 if boundary == "takeover" else 409), late.text
        assert old_key is not None and await storage.get_bounded(old_key, len(raw)) == raw
        async with runtime.resources.database.sessions() as session, session.begin():
            row = await session.get(UploadIntent, UUID(upload["id"]), with_for_update=True)
            assert row is not None and old_key in row.retired_final_candidates
            row.candidate_cleanup_due_at = datetime.now(UTC) - timedelta(seconds=1)
            row.updated_at = datetime.now(UTC)
        await collect_source_garbage(runtime)
        with pytest.raises(S3Error) as removed:
            await storage.get_bounded(old_key, len(raw))
        assert removed.value.code == "NoSuchKey"
        async with runtime.resources.database.sessions() as session:
            state = await session.scalar(select(UserStorageState))
            assert state is not None and state.reserved_bytes == 0
            assert state.used_bytes == (len(raw) if boundary == "takeover" else 0)
            if boundary == "cancel":
                assert not list(await session.scalars(select(Job)))
                assert not list(await session.scalars(select(Material)))
                assert not list(await session.scalars(select(MaterialRevision)))
