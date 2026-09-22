"""Core/jobs composition and graceful development stop markers are explicit."""

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

import pytest
from pydantic import SecretStr, ValidationError

import app.bootstrap as assembly
import app.cli.lifecycle as lifecycle
from app.core.settings import CoreInfrastructureSettings, Settings

pytestmark = pytest.mark.unit


def core_settings() -> Settings:
    return Settings(
        app_env="test",
        instance_id="haruka-test-core",
        public_base_url="http://localhost:8000",
        infrastructure_enabled=True,
        resource_profile="core",
        resource_namespace="haruka-test-core",
        database_url=SecretStr(
            "postgresql+asyncpg://haruka_test_runtime:fake@127.0.0.1:15432/haruka_test"
        ),
        redis_url=SecretStr("redis://:fake@127.0.0.1:16379/1"),
    )


def test_core_requires_no_job_credentials_and_runtime_rejects_maintenance() -> None:
    settings = core_settings()
    assert settings.core_infrastructure().namespace == settings.instance_id
    with pytest.raises(ValueError, match="not enabled"):
        settings.infrastructure()
    values = settings.model_dump()
    values["resource_profile"] = "jobs"
    with pytest.raises(ValidationError):
        Settings.model_validate(values)
    values = settings.model_dump()
    values["database_url"] = SecretStr(
        "postgresql+asyncpg://haruka_test_maintenance:fake@127.0.0.1:15432/haruka_test"
    )
    with pytest.raises(ValidationError):
        Settings.model_validate(values)


@pytest.mark.asyncio
async def test_core_never_constructs_jobs_and_cleans_up(monkeypatch: pytest.MonkeyPatch) -> None:
    closed: list[str] = []

    class CoreResource:
        def __init__(self, _settings: CoreInfrastructureSettings) -> None:
            pass

        async def check(self) -> None:
            pass

        async def aclose(self) -> None:
            closed.append("closed")

    async def schema_check(_database: object) -> None:
        pass

    def unexpected(*_args: object, **_kwargs: object) -> None:
        pytest.fail("core profile constructed a jobs-only client")

    monkeypatch.setattr(assembly, "Database", CoreResource)
    monkeypatch.setattr(assembly, "Cache", CoreResource)
    monkeypatch.setattr(assembly, "KafkaProducer", unexpected)
    monkeypatch.setattr(assembly, "ObjectStorage", unexpected)
    monkeypatch.setattr(assembly, "_check_database_schema", schema_check)
    async with assembly.bootstrap(core_settings()) as runtime:
        assert runtime.ready and await runtime.check_readiness()
        assert runtime.resources is not None and runtime.resources.kafka is None
        assert runtime.resources.storage is None
    assert len(closed) == 2
    with pytest.raises(assembly.InfrastructureUnavailable, match="jobs profile"):
        async with assembly.bootstrap(core_settings(), role="worker"):
            pytest.fail("worker started in core profile")


@pytest.mark.asyncio
async def test_lifecycle_stop_releases_resources(
    infrastructure_settings: Settings,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    marker = tmp_path / "stop"
    started = asyncio.Event()
    closed = asyncio.Event()

    @asynccontextmanager
    async def bootstrap(
        _settings: Settings, *, role: Literal["worker", "outbox"]
    ) -> AsyncGenerator[None]:
        assert role == "worker"
        started.set()
        try:
            yield
        finally:
            closed.set()

    monkeypatch.setattr(lifecycle, "bootstrap", bootstrap)
    running = asyncio.create_task(
        lifecycle.run_lifecycle(infrastructure_settings, "worker", marker)
    )
    async with asyncio.timeout(3):
        await started.wait()
        await asyncio.to_thread(marker.write_text, "stop", encoding="utf-8")
        await running
    assert closed.is_set()
    assert '"business_handlers": false' in capsys.readouterr().out
    assert marker.read_text(encoding="utf-8") == "stop"


def test_stop_marker_cannot_be_relative_or_preexisting(tmp_path: Path) -> None:
    existing = tmp_path / "owned-by-someone-else"
    existing.write_text("preserve", encoding="utf-8")
    for path in (Path("relative.stop"), existing, tmp_path / "absent-parent" / "stop"):
        with pytest.raises(ValueError):
            lifecycle.validate_shutdown_file(path)
    assert existing.read_text(encoding="utf-8") == "preserve"
