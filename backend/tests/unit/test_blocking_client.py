"""Cancellation cannot discard SDK cleanup queued behind an in-flight call."""

import asyncio
import threading

import pytest

from app.adapters.blocking import BlockingClient

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


async def test_cancelled_close_still_drains_and_cleans_up() -> None:
    lane = BlockingClient("test-cancellation")
    started = threading.Event()
    release = threading.Event()
    cleaned = threading.Event()

    def blocking_operation() -> None:
        started.set()
        if not release.wait(3):
            raise TimeoutError("synthetic SDK timeout")

    operation = asyncio.create_task(lane.call(blocking_operation))
    assert await asyncio.to_thread(started.wait, 2)
    closing = asyncio.create_task(lane.close(cleaned.set))
    await asyncio.sleep(0)
    closing.cancel()
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await closing
    await operation
    assert cleaned.is_set()
    assert not [t for t in threading.enumerate() if t.name.startswith("haruka-test-cancellation")]
    await lane.close(cleaned.set)
