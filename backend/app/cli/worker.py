"""Worker packaging boundary for future persistent task execution."""

import asyncio
import sys
from pathlib import Path

from app.bootstrap import InfrastructureUnavailable
from app.cli.common import check_resources, checked_settings, config_ok, parser_for, unavailable
from app.cli.lifecycle import run_lifecycle
from app.core.logging import configure_logging


def main() -> None:
    parser = parser_for("haruka-worker", "Haruka worker lifecycle")
    parser.add_argument("--check-startup", action="store_true")
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
    unavailable("Worker execution")
