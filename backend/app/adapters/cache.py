"""Redis asyncio client with an owned pool and environment-scoped key builder."""

from collections.abc import Awaitable
from typing import Protocol
from urllib.parse import unquote, urlsplit

from redis.asyncio import Redis
from redis.asyncio.retry import Retry
from redis.backoff import NoBackoff

from app.core.settings import InfrastructureSettings


class _RedisPing(Protocol):
    # redis-py 8.1 leaves ping's unused **kwargs untyped. This is the exact
    # no-argument public call used by our probe, without disabling diagnostics.
    def ping(self) -> Awaitable[bool]: ...


async def _ping(client: _RedisPing) -> bool:
    return await client.ping()


class Cache:
    def __init__(self, settings: InfrastructureSettings) -> None:
        self.namespace = settings.namespace
        address = urlsplit(settings.redis_url.get_secret_value())
        self.client = Redis(
            host=address.hostname or "127.0.0.1",
            port=address.port or 6379,
            username=unquote(address.username) if address.username else None,
            password=unquote(address.password or ""),
            db=int(address.path.removeprefix("/")),
            decode_responses=False,
            max_connections=20,
            socket_connect_timeout=3,
            socket_timeout=3,
            health_check_interval=30,
            retry=Retry(NoBackoff(), 0),
        )

    def key(self, *parts: str) -> str:
        """Callers must include authenticated owner scope for all private data."""
        if not parts or any(not part or ":" in part for part in parts):
            raise ValueError("cache key segments must be nonempty and contain no separator")
        return ":".join((self.namespace, *parts))

    async def check(self) -> None:
        if not await _ping(self.client):
            raise RuntimeError("cache probe failed")

    async def aclose(self) -> None:
        await self.client.aclose(close_connection_pool=True)
