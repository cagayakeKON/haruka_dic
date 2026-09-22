"""Development-only graceful process control; no queue handlers or implicit jobs."""

import asyncio
import json
import signal
import sys
from pathlib import Path
from types import FrameType
from typing import Literal

from app.bootstrap import bootstrap
from app.core.settings import Settings


def validate_shutdown_file(path: Path | None) -> None:
    """Only inspect an explicit future marker; never create, clear or delete caller files."""
    if path is not None and (
        not path.is_absolute() or not path.parent.is_dir() or path.exists() or path.is_symlink()
    ):
        raise ValueError("shutdown file must be an absent absolute path with an existing parent")


async def watch_shutdown_file(path: Path, stop: asyncio.Event) -> None:
    while not stop.is_set():
        if await asyncio.to_thread(path.is_file):
            stop.set()
            return
        await asyncio.sleep(0.1)


async def run_lifecycle(
    settings: Settings, role: Literal["worker", "outbox"], shutdown_file: Path | None
) -> None:
    """Exercise process resources until explicitly stopped, without subscribing or publishing."""
    if not settings.infrastructure_enabled or settings.resource_profile != "jobs":
        raise ValueError("lifecycle-only processes require the enabled jobs profile")
    validate_shutdown_file(shutdown_file)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()

    def terminate(_number: int, _frame: FrameType | None) -> None:
        loop.call_soon_threadsafe(stop.set)

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        async with bootstrap(settings, role=role):
            sys.stdout.write(
                json.dumps({"lifecycle_ready": True, "role": role, "business_handlers": False})
                + "\n"
            )
            sys.stdout.flush()
            if shutdown_file is None:
                await stop.wait()
            else:
                await watch_shutdown_file(shutdown_file, stop)
    finally:
        signal.signal(signal.SIGTERM, previous)
