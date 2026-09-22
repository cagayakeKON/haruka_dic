"""Explicit maintenance boundary; no implicit DDL, seed or administrator creation."""

from app.cli.common import check_resources, checked_settings, config_ok, parser_for, unavailable


def main() -> None:
    parser = parser_for("haruka-manage", "Haruka controlled maintenance")
    parser.add_argument(
        "command",
        nargs="?",
        choices=["check-config", "check-infrastructure", "db", "seed", "admin"],
    )
    args = parser.parse_args()
    if args.command is None and not args.check_config:
        parser.error("a maintenance command is required")
    settings = checked_settings(args.config)
    if args.command == "check-config" or args.check_config:
        config_ok()
        return
    if args.command == "check-infrastructure":
        check_resources(settings, "manage")
        return
    unavailable("Database migration / seed / administrator initialization")
