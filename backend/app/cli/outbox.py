"""Outbox packaging boundary; durable delivery is not simulated here."""

from app.cli.common import checked_settings, config_ok, parser_for, unavailable


def main() -> None:
    args = parser_for("haruka-outbox", "Haruka outbox dispatcher (not yet available)").parse_args()
    checked_settings(args.config)
    if args.check_config:
        config_ok()
        return
    unavailable("Outbox delivery")
