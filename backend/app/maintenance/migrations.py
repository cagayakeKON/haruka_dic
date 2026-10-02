"""Bounded advisory locks and Alembic DDL always use the same physical PG connection."""

import asyncio
import hashlib
import json
import re
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import TypeGuard

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import Connection, inspect, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncConnection

from app.maintenance.schema import (
    EXPECTED_REVISION,
    check_schema_connection,
    current_revision,
)
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine

LOCK_NAMESPACE = 1212240469
LOCK_RESOURCE = 1262563376


class MigrationError(RuntimeError):
    """Safe maintenance failure; retry is a new connection and a new lock acquisition."""


def bundled_migration_head() -> str:
    """Read the verified bundle inside its resource lifetime, independent of cwd."""
    from importlib.resources import as_file, files

    packaged = files("app.maintenance").joinpath("migration_bundle")
    if packaged.is_dir():
        with as_file(packaged) as directory:
            return load_migration_resources(directory.absolute()).head
    # Editable checkouts retain the original manifested bundle alongside app/.
    # Missing/invalid resources still pass through the same strict loader.
    return load_migration_resources(Path(__file__).resolve().parents[2] / "alembic").head


@dataclass(frozen=True)
class MigrationResources:
    directory: Path
    head: str

    def config(self) -> Config:
        config = Config()
        config.set_main_option("script_location", str(self.directory).replace("%", "%%"))
        return config


@dataclass(frozen=True)
class MigrationStatus:
    current_revision: str | None
    expected_revision: str
    compatible: bool
    schema: str
    tables: tuple[str, ...]
    backend_pid: int


@dataclass(frozen=True)
class LockOwnership:
    backend_pid: int
    schema: str


def _json_object(value: object) -> TypeGuard[dict[str, object]]:
    return isinstance(value, dict)


def load_migration_resources(directory: Path) -> MigrationResources:
    if not directory.is_absolute() or not directory.is_dir() or directory.is_symlink():
        raise MigrationError("an explicit absolute migration directory is required")
    try:
        document: object = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise MigrationError("migration manifest is missing or invalid") from error
    if (
        not _json_object(document)
        or document.get("schema_version") != 1
        or document.get("head") != EXPECTED_REVISION
    ):
        raise MigrationError("migration manifest version does not match this application")
    files = document.get("files")
    if not _json_object(files) or "env.py" not in files:
        raise MigrationError("migration manifest must list every executable migration resource")
    actual = {path.relative_to(directory).as_posix() for path in directory.rglob("*.py")}
    if actual != set(files):
        raise MigrationError("migration manifest has missing or unregistered Python resources")
    for name, expected in files.items():
        if not re.fullmatch(r"(?:env\.py|versions/[a-zA-Z0-9_]+\.py)", name):
            raise MigrationError("migration manifest contains an invalid resource path")
        path = directory / name
        if (
            path.is_symlink()
            or not isinstance(expected, str)
            or not re.fullmatch(r"[a-f0-9]{64}", expected)
        ):
            raise MigrationError("migration resources require regular files and SHA-256 hashes")
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise MigrationError("migration resource hash differs from the reviewed manifest")
    resources = MigrationResources(directory=directory, head=EXPECTED_REVISION)
    if ScriptDirectory.from_config(resources.config()).get_heads() != [EXPECTED_REVISION]:
        raise MigrationError("migration resources must have exactly the expected head")
    return resources


def verify_lock_owner(connection: Connection, ownership: object) -> LockOwnership:
    if not isinstance(ownership, LockOwnership) or connection.closed or connection.invalidated:
        raise MigrationError("Alembic requires a live connection owned by the maintenance lock")
    pid = connection.scalar(text("SELECT pg_backend_pid()"))
    if connection.scalar(text("SELECT current_schema()")) != ownership.schema:
        raise MigrationError("migration connection search path differs from the locked target")
    held = connection.scalar(
        text(
            "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE locktype='advisory' "
            "AND pid=pg_backend_pid() AND classid=:namespace AND objid=:resource "
            "AND objsubid=2 AND granted)"
        ),
        {"namespace": LOCK_NAMESPACE, "resource": LOCK_RESOURCE},
    )
    if pid != ownership.backend_pid or held is not True:
        raise MigrationError("migration lock and DDL must use the same physical connection")
    return ownership


@asynccontextmanager
async def locked_connection(
    settings: MaintenanceSettings, *, timeout_seconds: float = 10
) -> AsyncGenerator[tuple[AsyncConnection, LockOwnership]]:
    if not 0 < timeout_seconds <= 60:
        raise ValueError("migration lock timeout must be in (0, 60] seconds")
    engine = create_maintenance_engine(settings)
    try:
        async with engine.connect() as connection:
            identity = (
                await connection.execute(
                    text("SELECT current_database(), current_user, pg_backend_pid()")
                )
            ).one()
            if (
                identity[0] != settings.database
                or identity[1] != f"{settings.database}_maintenance"
                or not isinstance(identity[2], int)
            ):
                raise MigrationError(
                    "connected database identity differs from the maintenance target"
                )
            schema_exists = await connection.scalar(
                text("SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname=:schema)"),
                {"schema": settings.database_schema},
            )
            if schema_exists is not True:
                raise MigrationError("the explicit migration schema does not exist")
            await connection.commit()
            deadline = time.monotonic() + timeout_seconds
            while True:
                acquired = await connection.scalar(
                    text("SELECT pg_try_advisory_lock(:namespace, :resource)"),
                    {"namespace": LOCK_NAMESPACE, "resource": LOCK_RESOURCE},
                )
                await connection.commit()
                if acquired is True:
                    break
                if time.monotonic() >= deadline:
                    raise MigrationError("timed out waiting for the database migration lock")
                await asyncio.sleep(min(0.05, max(0, deadline - time.monotonic())))
            ownership = LockOwnership(backend_pid=identity[2], schema=settings.database_schema)
            try:
                yield connection, ownership
            finally:
                # Never run another statement after disconnect; that could reconnect without the lock.
                if not connection.closed and not connection.invalidated:
                    await connection.rollback()
                    await connection.execute(
                        text("SELECT pg_advisory_unlock(:namespace, :resource)"),
                        {"namespace": LOCK_NAMESPACE, "resource": LOCK_RESOURCE},
                    )
                    await connection.commit()
    except SQLAlchemyError as error:
        raise MigrationError(
            "database maintenance failed; reacquire the lock and inspect state before retry"
        ) from error
    finally:
        await engine.dispose()


def _status(
    connection: Connection, ownership: LockOwnership, *, check_structure: bool
) -> MigrationStatus:
    verify_lock_owner(connection, ownership)
    revision = current_revision(connection, ownership.schema)
    tables = tuple(sorted(inspect(connection).get_table_names(schema=ownership.schema)))
    compatible = revision == EXPECTED_REVISION
    if compatible and check_structure:
        check_schema_connection(connection, ownership.schema)
    return MigrationStatus(
        revision, EXPECTED_REVISION, compatible, ownership.schema, tables, ownership.backend_pid
    )


async def database_status(settings: MaintenanceSettings, migrations_dir: Path) -> MigrationStatus:
    load_migration_resources(migrations_dir)
    async with locked_connection(settings) as (connection, ownership):
        return await connection.run_sync(_status, ownership, check_structure=True)


def _upgrade(
    connection: Connection, resources: MigrationResources, ownership: LockOwnership
) -> None:
    verify_lock_owner(connection, ownership)
    actual = current_revision(connection, ownership.schema)
    scripts = ScriptDirectory.from_config(resources.config())
    known_revisions = {revision.revision for revision in scripts.walk_revisions()}
    if actual is not None and actual not in known_revisions:
        raise MigrationError("database revision is not in the reviewed migration history")
    # Commit inspection only: the advisory lock remains held for this physical session.
    connection.commit()
    config = resources.config()
    config.attributes["connection"] = connection
    config.attributes["lock_ownership"] = ownership
    command.upgrade(config, resources.head)


async def upgrade_database(
    settings: MaintenanceSettings, migrations_dir: Path, *, lock_timeout_seconds: float = 10
) -> MigrationStatus:
    resources = load_migration_resources(migrations_dir)
    async with locked_connection(settings, timeout_seconds=lock_timeout_seconds) as (
        connection,
        ownership,
    ):
        # Every attempt observes the committed revision and physical schema after taking the lock.
        await connection.run_sync(_status, ownership, check_structure=True)
        await connection.run_sync(_upgrade, resources, ownership)
        return await connection.run_sync(_status, ownership, check_structure=True)
