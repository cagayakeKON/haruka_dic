"""Durable authorization and identity cache-invalidation outbox worker."""

import asyncio
import json
import logging
import signal
import sys
from contextlib import suppress
from pathlib import Path
from types import FrameType

from app.bootstrap import InfrastructureUnavailable, bootstrap
from app.cli.common import check_resources, checked_settings, config_ok, parser_for
from app.cli.lifecycle import run_lifecycle, validate_shutdown_file, watch_shutdown_file
from app.core.logging import configure_logging
from app.core.settings import Settings
from app.domain.errors import AppError
from app.services.outbox_delivery import deliver_outbox_one

logger = logging.getLogger(__name__)


async def run_outbox(settings: Settings, *, shutdown_file: Path | None, once: bool) -> None:
    if not settings.infrastructure_enabled:
        raise InfrastructureUnavailable("outbox requires configured infrastructure")
    validate_shutdown_file(shutdown_file)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()

    def terminate(_number: int, _frame: FrameType | None) -> None:
        loop.call_soon_threadsafe(stop.set)

    previous = signal.signal(signal.SIGTERM, terminate)
    watcher: asyncio.Task[None] | None = None
    try:
        async with bootstrap(settings, role="outbox") as runtime:
            sys.stdout.write(json.dumps({"outbox_worker_ready": True}) + "\n")
            sys.stdout.flush()
            if shutdown_file is not None:
                watcher = asyncio.create_task(watch_shutdown_file(shutdown_file, stop))
            failures = 0
            while not stop.is_set():
                try:
                    handled = await deliver_outbox_one(runtime)
                    failures = 0
                except AppError:
                    failures += 1
                    logger.warning("outbox.worker.unavailable")
                    if failures >= 5:
                        raise InfrastructureUnavailable("outbox dependency unavailable") from None
                    await asyncio.sleep(min(failures, 5))
                    continue
                if once:
                    break
                if not handled:
                    with suppress(TimeoutError):
                        await asyncio.wait_for(stop.wait(), timeout=0.5)
    finally:
        if watcher is not None:
            watcher.cancel()
            with suppress(asyncio.CancelledError):
                await watcher
        signal.signal(signal.SIGTERM, previous)


def main() -> None:
    parser = parser_for("haruka-outbox", "Haruka outbox lifecycle")
    parser.add_argument("--check-startup", action="store_true")
    parser.add_argument("--once", action="store_true", help="deliver at most one pending event")
    parser.add_argument(
        "--lifecycle-only", action="store_true", help="hold resources; no business handlers"
    )
    parser.add_argument("--shutdown-file", type=Path)
    args = parser.parse_args()
    settings = checked_settings(args.config)
    if args.check_config:
        config_ok()
        return
    if args.check_startup:
        check_resources(settings, "outbox")
        return
    if args.lifecycle_only:
        configure_logging(settings, "outbox")
        try:
            asyncio.run(run_lifecycle(settings, "outbox", args.shutdown_file))
        except (ValueError, InfrastructureUnavailable):
            sys.stderr.write(
                "Outbox lifecycle failed; verify profile, dependencies and stop marker.\n"
            )
            raise SystemExit(2) from None
        return
    configure_logging(settings, "outbox")
    try:
        asyncio.run(run_outbox(settings, shutdown_file=args.shutdown_file, once=args.once))
    except Exception:
        sys.stderr.write("Outbox worker unavailable; inspect safe service logs.\n")
        raise SystemExit(2) from None
