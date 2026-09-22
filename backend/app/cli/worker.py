"""Worker packaging boundary; persistent task execution arrives in B2."""

from app.cli.common import check_resources, checked_settings, config_ok, parser_for, unavailable


def main() -> None:
    parser = parser_for("haruka-worker", "Haruka worker lifecycle; business execution awaits B2")
    parser.add_argument("--check-startup", action="store_true")
    args = parser.parse_args()
    settings = checked_settings(args.config)
    if args.check_config:
        config_ok()
        return
    if args.check_startup:
        check_resources(settings, "worker")
        return
    unavailable("Worker execution")
