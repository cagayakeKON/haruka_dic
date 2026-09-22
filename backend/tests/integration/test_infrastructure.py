"""Real isolated PG/Redis/Kafka/MinIO transport and lifetime acceptance; no business seed."""

import asyncio
import os
import threading
from contextlib import AsyncExitStack
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen
from uuid import uuid4

import pytest
from minio.error import S3Error
from pydantic import SecretStr
from sqlalchemy import text
from sqlalchemy.engine import make_url

from app.adapters.database import Database
from app.adapters.queue import KafkaConsumer
from app.adapters.storage import ObjectStorage
from app.bootstrap import InfrastructureUnavailable, bootstrap
from app.core.logging import configure_logging
from app.core.settings import Settings, load_settings

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]


@pytest.fixture
def integration_settings() -> Settings:
    path = os.environ.get("HARUKA_INTEGRATION_CONFIG")
    if path is None:
        pytest.fail("HARUKA_INTEGRATION_CONFIG must explicitly select dev/.local/test.env")
    settings = load_settings(Path(path))
    if settings.app_env != "test" or settings.instance_id != "haruka-test-integration":
        pytest.fail("integration resources do not match the dedicated test environment")
    settings.infrastructure()
    return settings


async def test_real_transports_and_release(integration_settings: Settings) -> None:
    run_id = uuid4().hex
    configure_logging(integration_settings, "integration")
    async with bootstrap(integration_settings) as runtime:
        resources = runtime.resources
        assert resources is not None
        assert runtime.ready
        # Separate sessions and physical connections, no implicit DDL or seed.
        async with resources.database.sessions() as first, resources.database.sessions() as second:
            first_id = await first.scalar(text("SELECT pg_backend_pid()"))
            second_id = await second.scalar(text("SELECT pg_backend_pid()"))
            assert first_id != second_id
            assert await first.scalar(text("SHOW timezone")) == "UTC"
            assert await first.scalar(text("SHOW search_path")) == "public"
            assert await first.scalar(text("SELECT current_database()")) == "haruka_test"
            assert not await first.scalar(
                text("SELECT rolsuper FROM pg_roles WHERE rolname=current_user")
            )
            assert not await first.scalar(
                text("SELECT has_schema_privilege(current_user, 'public', 'CREATE')")
            )
            await first.rollback()
            await second.rollback()

        key = resources.cache.key("integration", run_id)
        payload = f"haruka-smoke-{run_id}".encode()
        try:
            assert await resources.cache.client.set(key, payload, ex=60)
            assert await resources.cache.client.get(key) == payload
        finally:
            await resources.cache.client.delete(key)

        object_key = f"integration/{run_id}/probe.txt"
        try:
            await resources.storage.put(object_key, payload)
            assert await resources.storage.get(object_key) == payload

            def anonymous_read() -> None:
                endpoint = integration_settings.infrastructure().s3_endpoint
                address = f"{endpoint}/{resources.storage.bucket}/{object_key}"
                with (
                    pytest.raises(HTTPError) as failure,
                    urlopen(address, timeout=5),  # noqa: S310 - validated loopback HTTP endpoint and generated path.
                ):
                    pytest.fail("private object was anonymously accessible")
                assert failure.value.code == 403
                failure.value.close()

            await asyncio.to_thread(anonymous_read)
        finally:
            await resources.storage.remove(object_key)

        configuration = integration_settings.infrastructure()
        topic = f"{configuration.namespace}.smoke"
        # Only the integration topic receives synthetic records. Unique group/key
        # isolate each run; broker retention bounds this non-business smoke topic.
        consumer = KafkaConsumer(configuration, group=f"{configuration.namespace}.smoke-{run_id}")
        async with AsyncExitStack() as cleanup:
            cleanup.push_async_callback(consumer.aclose)
            await consumer.subscribe(topic)
            await resources.kafka.publish(topic, key=run_id.encode(), value=payload)
            async with asyncio.timeout(20):
                while True:
                    record = await consumer.read()
                    if record is not None and record.key == run_id.encode():
                        assert record.value == payload
                        break
    assert not runtime.active
    assert not [
        thread.name for thread in threading.enumerate() if thread.name.startswith("haruka-")
    ]


async def test_unreachable_dependency_fails_safely(integration_settings: Settings) -> None:
    configuration = integration_settings.model_dump()
    # Port 1 is not part of the Compose project; this must not fall back to Redis 6379.
    configuration["redis_url"] = "redis://:fake-secret-sentinel@127.0.0.1:1/1"
    broken = Settings.model_validate(configuration)
    with pytest.raises(InfrastructureUnavailable) as caught:
        async with bootstrap(broken):
            pytest.fail("unreachable Redis became ready")
    assert "sentinel" not in str(caught.value)
    assert not [
        thread.name for thread in threading.enumerate() if thread.name.startswith("haruka-")
    ]


async def test_runtime_credentials_cannot_cross_environments(
    integration_settings: Settings,
) -> None:
    configuration = integration_settings.infrastructure()
    other_database = make_url(configuration.database_url.get_secret_value()).set(
        database="haruka_dev"
    )
    database = Database(
        configuration.model_copy(
            update={
                "database_url": SecretStr(other_database.render_as_string(hide_password=False)),
            }
        )
    )
    try:
        with pytest.raises(Exception) as database_failure:
            await database.check()
        error: object = database_failure.value
        code: object = getattr(error, "sqlstate", None)
        if code is None:
            code = getattr(getattr(error, "orig", None), "sqlstate", None)
        assert code == "42501", "expected PostgreSQL insufficient_privilege"
    finally:
        await database.aclose()

    storage = ObjectStorage(configuration.model_copy(update={"s3_bucket": "haruka-local-dev"}))
    try:
        with pytest.raises(S3Error) as storage_failure:
            await storage.check()
        assert storage_failure.value.code == "AccessDenied"
    finally:
        await storage.aclose()
