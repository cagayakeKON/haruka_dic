"""Worker packaging boundary; persistent task execution arrives in B2."""

from app.cli.common import checked_settings, config_ok, parser_for, unavailable


def main() -> None:
    args = parser_for("haruka-worker", "Haruka task worker (not yet available)").parse_args()
    checked_settings(args.config)
    if args.check_config:
        config_ok()
        return
    unavailable("Worker execution")
