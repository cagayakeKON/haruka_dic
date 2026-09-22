"""Development API shell with explicit configuration and a bounded shutdown."""

import asyncio
import sys

import uvicorn

from app.bootstrap import InfrastructureUnavailable
from app.cli.common import checked_settings, config_ok, parser_for
from app.core.logging import configure_logging
from app.core.settings import Settings
from app.main import create_app


async def check_startup(settings: Settings) -> None:
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        sys.stdout.write("Process lifecycle started; schema readiness remains unavailable.\n")


def main() -> None:
    parser = parser_for("haruka-api", "Haruka API process")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--check-startup", action="store_true", help="start and close the API lifespan"
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    settings = checked_settings(args.config)
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
    uvicorn.run(
        create_app(settings),
        host="127.0.0.1",
        port=args.port,
        log_config=None,
        access_log=False,
        timeout_graceful_shutdown=10,
    )
