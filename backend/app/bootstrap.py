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
    kafka: KafkaProducer
    storage: ObjectStorage
    consumer: KafkaConsumer | None

    async def check(self) -> None:
        """Read-only connectivity checks, not schema or business readiness."""
        await self.database.check()
        await self.cache.check()
        await self.kafka.check()
        await self.storage.check()


@dataclass
class Runtime:
    settings: Settings
    resources: Resources | None = None
    active: bool = True

    @property
    def ready(self) -> bool:
        # Schema compatibility, durable auth and migrations remain separate B0 work.
        return False


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
                configuration = settings.infrastructure()
                try:
                    database = Database(configuration)
                    stack.push_async_callback(database.aclose)
                    await database.check()
                    cache = Cache(configuration)
                    stack.push_async_callback(cache.aclose)
                    await cache.check()
                    kafka = KafkaProducer(configuration)
                    stack.push_async_callback(kafka.aclose)
                    await kafka.check()
                    storage = ObjectStorage(configuration)
                    stack.push_async_callback(storage.aclose)
                    await storage.check()
                    consumer = None
                    if role == "worker":
                        consumer = KafkaConsumer(
                            configuration, group=f"{configuration.namespace}.worker"
                        )
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
