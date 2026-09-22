"""Serialize synchronous SDK work without blocking the application's event loop."""

import asyncio
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from functools import partial


class BlockingClient:
    """One process-local SDK lane, including orderly close after in-flight calls.

    SDK calls must have their own network deadlines. Cancelling an asyncio wait
    cannot kill a Python thread, so shutdown queues behind the bounded SDK call.
    """

    def __init__(self, name: str) -> None:
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix=f"haruka-{name}")
        self._closed = False
        self._closing: asyncio.Task[None] | None = None

    async def call[T](self, operation: Callable[[], T]) -> T:
        if self._closed:
            raise RuntimeError("infrastructure client is closed")
        return await asyncio.get_running_loop().run_in_executor(self._executor, operation)

    async def close(self, cleanup: Callable[[], object]) -> None:
        if self._closing is None:
            self._closed = True
            self._closing = asyncio.create_task(self._finish_close(cleanup))
        cancelled = False
        while True:
            try:
                await asyncio.shield(self._closing)
                break
            except asyncio.CancelledError:
                if self._closing.cancelled():
                    raise
                # Cancellation belongs to the waiter, not the queued SDK close.
                # Drain the bounded call and cleanup, then propagate cancellation.
                cancelled = True
        if cancelled:
            raise asyncio.CancelledError

    async def _finish_close(self, cleanup: Callable[[], object]) -> None:
        loop = asyncio.get_running_loop()
        try:
            await loop.run_in_executor(self._executor, cleanup)
        finally:
            await asyncio.to_thread(
                partial(self._executor.shutdown, wait=True, cancel_futures=False)
            )
