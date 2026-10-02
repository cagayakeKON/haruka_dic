"""A real hung parser process is killed/reaped and cannot publish after timeout."""

import hashlib
import subprocess
import sys
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from sqlalchemy import func, select

from app.adapters import source_validation
from app.bootstrap import Runtime
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from app.models import FileObject, Job, MaterialImport, UserStorageState
from tests.integration.test_material_source_boundaries import source_runtime
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
assert source_runtime


async def test_real_parser_timeout_reaps_child_and_releases_unaccepted_capacity(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(
        runtime, maintenance, f"parser-timeout-{run_id}@haruka.example.test"
    ):
        raw = b"A source whose parser will deliberately exceed its deadline."
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
        actual_start = subprocess.Popen
        children: list[subprocess.Popen[bytes]] = []

        def hang(
            _args: list[str], *, stdin: int, stdout: int, stderr: int
        ) -> subprocess.Popen[bytes]:
            child = actual_start(  # noqa: B023 -- consumed within this owner's monkeypatch lifetime
                [sys.executable, "-c", "import sys,time;sys.stdin.buffer.read();time.sleep(10)"],
                stdin=stdin,
                stdout=stdout,
                stderr=stderr,
            )
            children.append(child)  # noqa: B023 -- consumed within this owner's monkeypatch lifetime
            return child

        monkeypatch.setattr(source_validation.subprocess, "Popen", hang)
        monkeypatch.setattr(source_validation, "PARSER_TIMEOUT_SECONDS", 0.2)
        response = await web.post(
            f"/api/v1/uploads/{upload['id']}/complete",
            json={"expected_revision": intent["revision"]},
            headers={**headers, "Idempotency-Key": upload["id"]},
        )
        assert (
            response.status_code == 504 and response.json()["error"]["code"] == "DEPENDENCY_TIMEOUT"
        )
        assert len(children) == 1 and children[0].poll() is not None
        async with runtime.resources.database.sessions() as session:
            row = await session.get(MaterialImport, UUID(intent["id"]))
            assert row is not None and row.status == "rejected" and row.material_id is None
            state = await session.scalar(select(UserStorageState))
            assert state is not None and state.used_bytes == 0 and state.reserved_bytes == 0
            assert await session.scalar(select(func.count()).select_from(FileObject)) == 0
            assert await session.scalar(select(func.count()).select_from(Job)) == 0
