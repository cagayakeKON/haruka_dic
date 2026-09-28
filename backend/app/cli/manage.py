"""Explicit maintenance boundary; ordinary process startup never migrates or seeds."""

import asyncio
import getpass
import json
import logging
import sys
import warnings
from dataclasses import asdict
from pathlib import Path

from pydantic import SecretStr, ValidationError
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.cli.common import check_resources, checked_settings, config_ok, parser_for
from app.core.logging import configure_logging
from app.core.settings import Settings
from app.maintenance.avatar_gc import collect_avatar_garbage
from app.maintenance.migrations import MigrationError, database_status, upgrade_database
from app.maintenance.schema import SchemaMismatchError, check_schema
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.services.initialization import InitializationError, apply_seed, initialize_admin


def read_password() -> SecretStr:
    """Do not fall back to an echoing terminal or accept a command-line password."""
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        try:
            password = getpass.getpass("First administrator password: ")
            confirmation = getpass.getpass("Repeat password: ")
        except (getpass.GetPassWarning, EOFError) as error:
            raise InitializationError(
                "a terminal supporting hidden password input is required"
            ) from error
    if password != confirmation:
        raise InitializationError("password confirmation differs")
    return SecretStr(password)


def main() -> None:
    parser = parser_for("haruka-manage", "Haruka controlled maintenance")
    parser.add_argument(
        "command",
        nargs="?",
        choices=["check-config", "check-infrastructure", "db", "seed", "admin", "avatar-gc"],
    )
    parser.add_argument("action", nargs="?", choices=["status", "upgrade", "apply", "init"])
    parser.add_argument(
        "--maintenance-config", type=Path, help="explicit dedicated maintenance credentials"
    )
    parser.add_argument(
        "--migrations-dir",
        type=Path,
        help="absolute path to the matching manifested migration bundle",
    )
    parser.add_argument("--email", help="first administrator email; password is entered privately")
    args = parser.parse_args()
    if args.command is None and not args.check_config:
        parser.error("a maintenance command is required")
    if args.command == "check-config" or args.check_config:
        checked_settings(args.config)
        config_ok()
        return
    if args.command == "check-infrastructure":
        check_resources(checked_settings(args.config), "manage")
        return
    if args.maintenance_config is None:
        parser.error(
            "--maintenance-config is required for database, seed and administrator actions"
        )
    expected_actions = {
        "db": {"status", "upgrade"},
        "seed": {"apply"},
        "admin": {"init"},
        "avatar-gc": {"apply"},
    }
    if args.action not in expected_actions.get(str(args.command), set()):
        parser.error("db requires status/upgrade, seed requires apply, admin requires init")
    if args.command == "db" and args.migrations_dir is None:
        parser.error("--migrations-dir is required for database commands")
    if args.command == "admin" and not args.email:
        parser.error("--email is required for first administrator initialization")
    try:
        maintenance = load_maintenance_settings(args.maintenance_config)
        logging_settings = Settings(
            app_env=maintenance.app_env,
            instance_id=maintenance.instance_id,
            public_base_url="http://127.0.0.1:8000",
            log_file=args.maintenance_config.resolve().parent
            / "logs"
            / f"{maintenance.app_env}.jsonl",
        )
        configure_logging(logging_settings, "manage")
        logger = logging.getLogger(__name__)
        logger.info("process.started")
        if args.command == "db":
            status = asyncio.run(
                upgrade_database(maintenance, args.migrations_dir)
                if args.action == "upgrade"
                else database_status(maintenance, args.migrations_dir)
            )
            sys.stdout.write(json.dumps(asdict(status)) + "\n")
            if not status.compatible:
                raise SystemExit(2)
        elif args.command == "avatar-gc":
            result = asyncio.run(_collect_avatars(maintenance))
            sys.stdout.write(
                json.dumps({"intents_removed": result[0], "files_removed": result[1]}) + "\n"
            )
        elif args.command == "seed":
            result = asyncio.run(apply_seed(maintenance))
            sys.stdout.write(json.dumps(asdict(result), default=str) + "\n")
        else:
            result = asyncio.run(
                initialize_admin(maintenance, email=args.email, password=read_password())
            )
            sys.stdout.write(json.dumps(asdict(result), default=str) + "\n")
        logger.info("process.stopped")
    except (
        ValidationError,
        ValueError,
        OSError,
        SQLAlchemyError,
        MigrationError,
        SchemaMismatchError,
        InitializationError,
    ):
        logging.getLogger(__name__).error("process.unavailable")
        sys.stderr.write(
            "Maintenance failed; verify the isolated target, schema version and operation prerequisites.\n"
        )
        raise SystemExit(2) from None


async def _collect_avatars(maintenance: MaintenanceSettings) -> tuple[int, int]:
    engine = create_maintenance_engine(maintenance)
    try:
        await check_schema(engine, schema=maintenance.database_schema)
        return await collect_avatar_garbage(async_sessionmaker(engine, expire_on_commit=False))
    finally:
        await engine.dispose()
