"""Development API shell with explicit configuration and a bounded shutdown."""

import asyncio
import sys
from contextlib import suppress
from pathlib import Path

import uvicorn

from app.bootstrap import InfrastructureUnavailable
from app.cli.common import checked_settings, config_ok, parser_for
from app.cli.lifecycle import validate_shutdown_file, watch_shutdown_file
from app.core.logging import configure_logging
from app.core.settings import Settings
from app.main import create_app


async def check_startup(settings: Settings) -> None:
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        sys.stdout.write(
            "Process lifecycle started and closed; use readiness for current dependencies.\n"
        )


async def serve(settings: Settings, *, port: int, shutdown_file: Path | None) -> None:
    server = uvicorn.Server(
        uvicorn.Config(
            create_app(settings),
            host="127.0.0.1",
            port=port,
            log_config=None,
            access_log=False,
            timeout_graceful_shutdown=10,
        )
    )
    if shutdown_file is None:
        await server.serve()
        if not server.started:
            raise InfrastructureUnavailable("API did not reach a listening state")
        return
    stop = asyncio.Event()

    async def request_stop() -> None:
        await watch_shutdown_file(shutdown_file, stop)
        server.should_exit = True

    watcher = asyncio.create_task(request_stop())
    try:
        await server.serve()
        if not server.started:
            raise InfrastructureUnavailable("API did not reach a listening state")
    finally:
        watcher.cancel()
        with suppress(asyncio.CancelledError):
            await watcher


def main() -> None:
    parser = parser_for("haruka-api", "Haruka API process")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--shutdown-file",
        type=Path,
        help="absolute future stop marker for an owned development process",
    )
    parser.add_argument(
        "--check-startup", action="store_true", help="start and close the API lifespan"
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    settings = checked_settings(args.config)
    try:
        validate_shutdown_file(args.shutdown_file)
    except ValueError:
        parser.error("shutdown file must be absent, absolute and have an existing parent")
    if args.check_config:
        config_ok()
        return
    configure_logging(settings, "api")
    if args.check_startup:
        try:
            asyncio.run(check_startup(settings))
        except InfrastructureUnavailable:
            sys.stderr.write("Infrastructure startup failed; inspect safe service logs.\n")
            raise SystemExit(2) from None
        return
    try:
        asyncio.run(serve(settings, port=args.port, shutdown_file=args.shutdown_file))
    except InfrastructureUnavailable:
        sys.stderr.write("API startup failed; inspect safe service logs.\n")
        raise SystemExit(2) from None
