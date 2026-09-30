"""Worker packaging boundary for future persistent task execution."""

import asyncio
import sys
from pathlib import Path

from app.bootstrap import InfrastructureUnavailable, bootstrap
from app.cli.common import check_resources, checked_settings, config_ok, parser_for
from app.cli.lifecycle import run_lifecycle, watch_shutdown_file
from app.core.logging import configure_logging
from app.services.model_worker import run_worker


def main() -> None:
    parser = parser_for("haruka-worker", "Haruka worker lifecycle")
    parser.add_argument("--check-startup", action="store_true")
    parser.add_argument(
        "--lifecycle-only", action="store_true", help="hold resources; no business handlers"
    )
    parser.add_argument("--shutdown-file", type=Path)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    settings = checked_settings(args.config)
    if args.check_config:
        config_ok()
        return
    if args.check_startup:
        check_resources(settings, "worker")
        return
    if args.lifecycle_only:
        configure_logging(settings, "worker")
        try:
            asyncio.run(run_lifecycle(settings, "worker", args.shutdown_file))
        except (ValueError, InfrastructureUnavailable):
            sys.stderr.write(
                "Worker lifecycle failed; verify profile, dependencies and stop marker.\n"
            )
            raise SystemExit(2) from None
        return
    configure_logging(settings, "worker")

    async def execute() -> None:
        stop = asyncio.Event()
        async with bootstrap(settings, role="worker") as runtime:
            watcher = (
                asyncio.create_task(watch_shutdown_file(args.shutdown_file, stop))
                if args.shutdown_file
                else None
            )
            try:
                await run_worker(runtime, stop, once=args.once)
            finally:
                if watcher:
                    watcher.cancel()

    try:
        asyncio.run(execute())
    except Exception:
        sys.stderr.write("Model worker unavailable; inspect safe service logs.\n")
        raise SystemExit(2) from None
