"""SCF-B0-03: acquisition failure, cancellation and cleanup failure never leak earlier resources."""

import asyncio
from functools import partial

import pytest

import app.bootstrap as assembly
from app.core.settings import InfrastructureSettings, Settings

pytestmark = pytest.mark.unit


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", ["database", "cache", "kafka", "storage", "body", "cancel", "close", "none"]
)
async def test_cleanup_in_reverse_order(
    infrastructure_settings: Settings, monkeypatch: pytest.MonkeyPatch, failure: str
) -> None:
    acquired: list[str] = []
    closed: list[str] = []

    class Resource:
        def __init__(self, name: str, _settings: InfrastructureSettings) -> None:
            self.name = name
            acquired.append(name)

        async def check(self) -> None:
            if failure == self.name:
                raise OSError("private-connection-sentinel")

        async def aclose(self) -> None:
            closed.append(self.name)
            if failure == "close" and self.name == "storage":
                raise OSError("private-close-sentinel")

    for symbol, name in (
        ("Database", "database"),
        ("Cache", "cache"),
        ("KafkaProducer", "kafka"),
        ("ObjectStorage", "storage"),
    ):
        monkeypatch.setattr(assembly, symbol, partial(Resource, name))

    async def exercise() -> None:
        async with assembly.bootstrap(infrastructure_settings) as runtime:
            assert runtime.resources is not None
            assert not runtime.ready
            if failure == "body":
                raise ValueError("body failure")
            if failure == "cancel":
                raise asyncio.CancelledError
        assert not runtime.active

    if failure == "none":
        await exercise()
    elif failure == "body":
        with pytest.raises(ValueError, match="body failure"):
            await exercise()
    elif failure == "cancel":
        with pytest.raises(asyncio.CancelledError):
            await exercise()
    else:
        with pytest.raises(assembly.InfrastructureUnavailable) as caught:
            await exercise()
        assert "sentinel" not in str(caught.value)
        assert caught.value.__suppress_context__
    assert acquired
    assert closed == list(reversed(acquired))


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("database_url", "postgresql+asyncpg://user:fake@127.0.0.1:15432/haruka_dev"),
        ("database_url", "postgresql+asyncpg://user:fake@remote.example:5432/haruka_test"),
        ("database_url", "postgresql+asyncpg://user:fake@localhost:15432/haruka_test?host=remote"),
        ("redis_url", "redis://:fake@127.0.0.1:16379/0"),
        ("s3_endpoint", "http://remote.example:9000"),
        ("s3_bucket", "haruka-local-dev"),
        ("resource_namespace", "haruka-local-dev"),
        ("kafka_bootstrap_servers", "127.0.0.1:19092,remote.example:9092"),
        ("s3_secret_key", ""),
        ("database_url", None),
    ],
)
def test_infrastructure_targets_fail_closed(
    infrastructure_settings: Settings, field: str, value: object
) -> None:
    from pydantic import ValidationError

    values = infrastructure_settings.model_dump()
    values[field] = value
    with pytest.raises(ValidationError):
        Settings.model_validate(values)


@pytest.mark.asyncio
async def test_cancel_during_resource_shutdown_completes_every_close(
    infrastructure_settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    entered = asyncio.Event()
    release = asyncio.Event()
    closed: list[str] = []

    class Resource:
        def __init__(self, name: str, _settings: InfrastructureSettings) -> None:
            self.name = name

        async def check(self) -> None:
            pass

        async def aclose(self) -> None:
            if self.name == "storage":
                entered.set()
                await release.wait()
            closed.append(self.name)

    for symbol, name in (
        ("Database", "database"),
        ("Cache", "cache"),
        ("KafkaProducer", "kafka"),
        ("ObjectStorage", "storage"),
    ):
        monkeypatch.setattr(assembly, symbol, partial(Resource, name))

    async def run() -> None:
        async with assembly.bootstrap(infrastructure_settings):
            pass

    process = asyncio.create_task(run())
    async with asyncio.timeout(3):
        await entered.wait()
        process.cancel()
        release.set()
        with pytest.raises(asyncio.CancelledError):
            await process
    assert closed == ["storage", "kafka", "cache", "database"]
