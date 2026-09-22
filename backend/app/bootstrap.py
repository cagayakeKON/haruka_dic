"""The only process resource assembly path, shared by API and installed CLIs."""

import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import AsyncExitStack, asynccontextmanager
from dataclasses import dataclass
from typing import Literal

from app.adapters.cache import Cache
from app.adapters.database import Database
from app.adapters.queue import KafkaConsumer, KafkaProducer
from app.adapters.storage import ObjectStorage
from app.core.settings import Settings
from app.maintenance.schema import check_schema

logger = logging.getLogger(__name__)


class InfrastructureUnavailable(RuntimeError):
    """Safe startup failure; never include a driver exception or a connection string."""


async def _close_resources(stack: AsyncExitStack) -> None:
    """Shutdown cancellation must not interrupt PG/Redis or skip later resources."""
    closing = asyncio.create_task(stack.aclose())
    cancelled = False
    while True:
        try:
            await asyncio.shield(closing)
            break
        except asyncio.CancelledError:
            if closing.cancelled():
                raise
            cancelled = True
    if cancelled:
        raise asyncio.CancelledError


@dataclass(frozen=True)
class Resources:
    database: Database
    cache: Cache
    kafka: KafkaProducer | None
    storage: ObjectStorage | None
    consumer: KafkaConsumer | None

    async def check(self) -> None:
        """Read-only connectivity checks, not schema or business readiness."""
        await self.database.check()
        await self.cache.check()
        if self.kafka is not None:
            await self.kafka.check()
        if self.storage is not None:
            await self.storage.check()


@dataclass
class Runtime:
    settings: Settings
    resources: Resources | None = None
    active: bool = True
    schema_compatible: bool = False

    @property
    def ready(self) -> bool:
        return self.active and self.resources is not None and self.schema_compatible

    async def check_readiness(self) -> bool:
        """Revalidate required dependencies and schema under a single bounded probe."""
        if not self.active or self.resources is None:
            return False
        try:
            async with asyncio.timeout(5), asyncio.TaskGroup() as probes:
                probes.create_task(self.resources.database.check())
                probes.create_task(_check_database_schema(self.resources.database))
                probes.create_task(self.resources.cache.check())
                if self.resources.kafka is not None:
                    probes.create_task(self.resources.kafka.check())
                if self.resources.storage is not None:
                    probes.create_task(self.resources.storage.check())
        except Exception:
            self.schema_compatible = False
            logger.warning("infrastructure.unavailable")
            return False
        self.schema_compatible = True
        return True


async def _check_database_schema(database: Database) -> None:
    await check_schema(database.engine)


@asynccontextmanager
async def bootstrap(
    settings: Settings, *, role: Literal["api", "worker", "outbox", "manage"] = "api"
) -> AsyncGenerator[Runtime]:
    """Register every close immediately and unwind when a later probe fails.

    Disabled infrastructure is the explicit offline process-shell mode. It never
    reports readiness, and maintenance connectivity checks refuse that mode.
    """
    runtime = Runtime(settings=settings)
    async with AsyncExitStack() as stack:
        try:
            if settings.infrastructure_enabled:
                if role in {"worker", "outbox"} and settings.resource_profile != "jobs":
                    raise InfrastructureUnavailable("worker and outbox require the jobs profile")
                configuration = settings.core_infrastructure()
                try:
                    database = Database(configuration)
                    stack.push_async_callback(database.aclose)
                    await database.check()
                    await _check_database_schema(database)
                    runtime.schema_compatible = True
                    cache = Cache(configuration)
                    stack.push_async_callback(cache.aclose)
                    await cache.check()
                    kafka = None
                    storage = None
                    consumer = None
                    if settings.resource_profile == "jobs":
                        jobs = settings.infrastructure()
                        kafka = KafkaProducer(jobs)
                        stack.push_async_callback(kafka.aclose)
                        await kafka.check()
                        storage = ObjectStorage(jobs)
                        stack.push_async_callback(storage.aclose)
                        await storage.check()
                        if role == "worker":
                            consumer = KafkaConsumer(jobs, group=f"{jobs.namespace}.worker")
                            stack.push_async_callback(consumer.aclose)
                    runtime.resources = Resources(database, cache, kafka, storage, consumer)
                except Exception:
                    logger.error("infrastructure.unavailable")
                    raise InfrastructureUnavailable("infrastructure startup failed") from None
                logger.info("infrastructure.connected")
            logger.info("process.started")
            yield runtime
        finally:
            runtime.active = False
            try:
                await _close_resources(stack)
            except Exception:
                logger.error("infrastructure.unavailable")
                raise InfrastructureUnavailable("infrastructure cleanup failed") from None
            logger.info("process.stopped")
