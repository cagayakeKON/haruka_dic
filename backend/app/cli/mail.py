"""Core-profile durable mail outbox worker; no broker or object store required."""

import asyncio
import json
import logging
import signal
import sys
from contextlib import suppress
from pathlib import Path
from types import FrameType

from app.bootstrap import InfrastructureUnavailable, bootstrap
from app.cli.common import checked_settings, config_ok, parser_for
from app.cli.lifecycle import validate_shutdown_file, watch_shutdown_file
from app.core.logging import configure_logging
from app.core.settings import Settings
from app.domain.errors import AppError
from app.services.auth_policy import mail_ready
from app.services.notifications import deliver_one

logger = logging.getLogger(__name__)


async def run_mail(settings: Settings, *, shutdown_file: Path | None, once: bool) -> None:
    if not settings.infrastructure_enabled or settings.resource_profile != "core":
        raise InfrastructureUnavailable("mail delivery requires the core resource profile")
    validate_shutdown_file(shutdown_file)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()

    def terminate(_number: int, _frame: FrameType | None) -> None:
        loop.call_soon_threadsafe(stop.set)

    previous = signal.signal(signal.SIGTERM, terminate)
    watcher: asyncio.Task[None] | None = None
    try:
        async with bootstrap(settings, role="mail") as runtime:
            if not mail_ready(runtime):
                raise InfrastructureUnavailable("mail delivery configuration is incomplete")
            sys.stdout.write(json.dumps({"mail_worker_ready": True}) + "\n")
            sys.stdout.flush()
            if shutdown_file is not None:
                watcher = asyncio.create_task(watch_shutdown_file(shutdown_file, stop))
            failures = 0
            while not stop.is_set():
                try:
                    handled = await deliver_one(runtime)
                    failures = 0
                except AppError:
                    failures += 1
                    logger.warning("mail.worker.unavailable")
                    if failures >= 5:
                        raise InfrastructureUnavailable(
                            "mail worker dependency unavailable"
                        ) from None
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
    parser = parser_for("haruka-mail-worker", "Durable notification delivery")
    parser.add_argument("--shutdown-file", type=Path)
    parser.add_argument(
        "--once", action="store_true", help="claim and deliver at most one due message"
    )
    args = parser.parse_args()
    settings = checked_settings(args.config)
    if args.check_config:
        config_ok()
        return
    configure_logging(settings, "mail")
    try:
        asyncio.run(run_mail(settings, shutdown_file=args.shutdown_file, once=args.once))
    except Exception:
        sys.stderr.write(
            "Mail worker unavailable; check isolated configuration and dependencies.\n"
        )
        raise SystemExit(2) from None


if __name__ == "__main__":
    main()
