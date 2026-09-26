"""Real PG maintenance locks and disconnect recovery in disposable, owned test schemas."""

import asyncio
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from collections.abc import AsyncIterator
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from alembic import command
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine
from sqlalchemy.schema import CreateSchema, DropSchema

from app.maintenance.migrations import (
    LOCK_NAMESPACE,
    LOCK_RESOURCE,
    MigrationError,
    database_status,
    load_migration_resources,
    locked_connection,
    upgrade_database,
)
from app.maintenance.schema import (
    EXPECTED_REVISION,
    SchemaMismatchError,
    check_revision,
    check_schema,
)
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.services.initialization import apply_seed

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"
CHILD_PROGRAM = """
import asyncio
import json
import sys
from pathlib import Path
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import MaintenanceSettings, load_maintenance_settings

original = load_maintenance_settings(Path(sys.argv[1]))
settings = MaintenanceSettings(database_url=original.database_url, test_schema=sys.argv[2])
try:
    status = asyncio.run(upgrade_database(settings, Path(sys.argv[3]), lock_timeout_seconds=float(sys.argv[4])))
except Exception as error:
    Path(sys.argv[5]).write_text(json.dumps({"error": type(error).__name__}), encoding="utf-8")
    raise SystemExit(2)
Path(sys.argv[5]).write_text(json.dumps({"revision": status.current_revision, "pid": status.backend_pid}), encoding="utf-8")
"""


@dataclass(frozen=True)
class MigrationTarget:
    settings: MaintenanceSettings
    configuration: Path
    observer: AsyncEngine


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MigrationTarget]:
    configuration = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if configuration is None:
        pytest.fail("HARUKA_MAINTENANCE_TEST_CONFIG must explicitly select test-maintenance.env")
    path = await asyncio.to_thread(Path(configuration).resolve)
    original = load_maintenance_settings(path)
    if original.app_env != "test":
        pytest.fail("migration failure tests only run against the dedicated test database")
    schema = f"haruka_migration_test_{uuid4().hex}"
    settings = MaintenanceSettings(database_url=original.database_url, test_schema=schema)
    observer = create_maintenance_engine(original)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        yield MigrationTarget(settings=settings, configuration=path, observer=observer)
    finally:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            # Only the random schema created by this fixture is ever dropped.
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


def fixture_migrations(temporary: Path, *, mode: str) -> Path:
    directory = temporary / "migrations"
    shutil.copytree(MIGRATIONS, directory, ignore=shutil.ignore_patterns("__pycache__"))
    first = directory / "versions/0001_b0_identity.py"
    contents = first.read_text(encoding="utf-8")
    contents = contents.replace("down_revision = None", 'down_revision = "test_checkpoint"')
    first.write_text(contents, encoding="utf-8")
    statements = {
        "lock": 'op.execute("SELECT pg_sleep(5)")',
        "ddl": (
            'op.execute("CREATE TABLE interrupted_ddl AS SELECT 1 AS id FROM (SELECT pg_sleep(8)) AS pause")\n'
            '    op.drop_table("interrupted_ddl")'
        ),
        "partial": 'op.create_table("migration_checkpoint", sa.Column("id", sa.Integer(), primary_key=True))',
    }
    (directory / "versions/test_checkpoint.py").write_text(
        "from alembic import op\nimport sqlalchemy as sa\n"
        'revision = "test_checkpoint"\ndown_revision = None\n'
        f"def upgrade():\n    {statements[mode]}\n",
        encoding="utf-8",
    )
    if mode == "partial":
        # Revision one commits first. Revision two is interrupted, then re-entered on retry.
        first.write_text(
            contents.replace('down_revision = "test_checkpoint"', 'down_revision = "test_wait"'),
            encoding="utf-8",
        )
        (directory / "versions/test_wait.py").write_text(
            "from alembic import op\n"
            'revision = "test_wait"\ndown_revision = "test_checkpoint"\n'
            'def upgrade():\n    op.execute("SELECT pg_sleep(2)")\n'
            '    op.drop_table("migration_checkpoint")\n',
            encoding="utf-8",
        )
    write_fixture_manifest(directory)
    return directory


def write_fixture_manifest(directory: Path) -> None:
    (directory / "manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "head": EXPECTED_REVISION,
                "files": {
                    path.relative_to(directory).as_posix(): hashlib.sha256(
                        path.read_bytes()
                    ).hexdigest()
                    for path in directory.rglob("*.py")
                },
            }
        ),
        encoding="utf-8",
    )


def start_migration(
    target: MigrationTarget, directory: Path, result: Path, *, timeout: float = 10
) -> subprocess.Popen[bytes]:
    return subprocess.Popen(  # noqa: S603 - fixed Python, test program, and explicit owned paths; no shell.
        [
            sys.executable,
            "-c",
            CHILD_PROGRAM,
            str(target.configuration),
            target.settings.database_schema,
            str(directory),
            str(timeout),
            str(result),
        ],
        cwd=result.parent,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env={**os.environ, "PYTHONUTF8": "1"},
    )


async def stop_child(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            await asyncio.to_thread(process.wait, timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            await asyncio.to_thread(process.wait, timeout=5)


async def waiting_backend(target: MigrationTarget, *, query_prefix: str) -> int:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        async with target.observer.connect() as connection:
            pid = await connection.scalar(
                text(
                    "SELECT activity.pid FROM pg_stat_activity AS activity "
                    "JOIN pg_locks AS lock ON lock.pid=activity.pid "
                    "WHERE activity.datname=current_database() AND activity.application_name=:application "
                    "AND activity.wait_event='PgSleep' AND activity.query LIKE :query "
                    "AND lock.locktype='advisory' AND lock.classid=:namespace "
                    "AND lock.objid=:resource AND lock.objsubid=2 AND lock.granted"
                ),
                {
                    "application": target.settings.application_name,
                    "query": query_prefix + "%",
                    "namespace": LOCK_NAMESPACE,
                    "resource": LOCK_RESOURCE,
                },
            )
            if isinstance(pid, int):
                return pid
        await asyncio.sleep(0.025)
    pytest.fail("the migration did not reach the expected locked PostgreSQL statement")


async def terminate_backend(target: MigrationTarget, pid: int) -> None:
    async with target.observer.begin() as connection:
        assert (
            await connection.scalar(text("SELECT pg_terminate_backend(:pid)"), {"pid": pid}) is True
        )


async def test_empty_upgrade_repeat_and_read_only_schema_drift(target: MigrationTarget) -> None:
    before = await database_status(target.settings, MIGRATIONS)
    assert before.current_revision is None and not before.compatible
    result = await upgrade_database(target.settings, MIGRATIONS)
    assert result.current_revision == EXPECTED_REVISION and result.compatible
    assert (await upgrade_database(target.settings, MIGRATIONS)).tables == result.tables
    engine = create_maintenance_engine(target.settings)
    try:
        await check_schema(engine, schema=target.settings.database_schema)
        async with engine.begin() as connection:
            await connection.execute(
                text("ALTER TABLE users DROP CONSTRAINT ck_users_authz_version_positive")
            )
            await connection.execute(
                text(
                    "ALTER TABLE users ADD CONSTRAINT ck_users_authz_version_positive CHECK(authz_version >= 0)"
                )
            )
        with pytest.raises(SchemaMismatchError, match="check constraints"):
            await check_schema(engine, schema=target.settings.database_schema)
        async with engine.begin() as connection:
            await connection.execute(
                text("ALTER TABLE users DROP CONSTRAINT ck_users_authz_version_positive")
            )
            await connection.execute(
                text(
                    "ALTER TABLE users ADD CONSTRAINT ck_users_authz_version_positive CHECK(authz_version >= 1)"
                )
            )
        async with engine.begin() as connection:
            await connection.execute(text("ALTER TABLE users ADD COLUMN unexpected_value TEXT"))
        with pytest.raises(SchemaMismatchError):
            await check_schema(engine, schema=target.settings.database_schema)
        async with engine.connect() as connection:
            assert await connection.scalar(text("SELECT COUNT(*) FROM users")) == 0
    finally:
        await engine.dispose()


@pytest.mark.parametrize("invalid", ["missing", "empty", "multiple", "wrong"])
async def test_light_revision_probe_rejects_bad_head_and_recovers(
    target: MigrationTarget, monkeypatch: pytest.MonkeyPatch, invalid: str
) -> None:
    await upgrade_database(target.settings, MIGRATIONS)
    engine = create_maintenance_engine(target.settings)
    try:

        def unexpected(*_args: object, **_kwargs: object) -> None:
            pytest.fail("readiness reflected application tables")

        with monkeypatch.context() as patch:
            patch.setattr("app.maintenance.schema.inspect", unexpected)
            patch.setattr("app.maintenance.schema.compare_metadata", unexpected)
            await check_revision(engine, schema=target.settings.database_schema)
            await check_revision(engine, schema=target.settings.database_schema)
        async with engine.begin() as connection:
            if invalid == "missing":
                await connection.execute(text("DROP TABLE alembic_version"))
            elif invalid == "empty":
                await connection.execute(text("DELETE FROM alembic_version"))
            elif invalid == "multiple":
                await connection.execute(
                    text("INSERT INTO alembic_version (version_num) VALUES ('unexpected')")
                )
            else:
                await connection.execute(
                    text("UPDATE alembic_version SET version_num='unexpected'")
                )
        with pytest.raises(SchemaMismatchError, match="revision"):
            await check_revision(engine, schema=target.settings.database_schema)
        async with engine.begin() as connection:
            if invalid == "missing":
                await connection.execute(
                    text(
                        "CREATE TABLE alembic_version (version_num varchar(32) NOT NULL PRIMARY KEY)"
                    )
                )
            else:
                await connection.execute(text("DELETE FROM alembic_version"))
            await connection.execute(
                text("INSERT INTO alembic_version (version_num) VALUES (:revision)"),
                {"revision": EXPECTED_REVISION},
            )
        await check_revision(engine, schema=target.settings.database_schema)
    finally:
        await engine.dispose()


async def test_full_schema_check_still_catches_drift_with_valid_head(
    target: MigrationTarget,
) -> None:
    await upgrade_database(target.settings, MIGRATIONS)
    engine = create_maintenance_engine(target.settings)
    try:
        async with engine.begin() as connection:
            await connection.execute(
                text("ALTER TABLE users DROP CONSTRAINT ck_users_revision_positive")
            )
        await check_revision(engine, schema=target.settings.database_schema)
        with pytest.raises(SchemaMismatchError):
            await check_schema(engine, schema=target.settings.database_schema)
    finally:
        await engine.dispose()


async def upgrade_only_0001(target: MigrationTarget) -> None:
    """Prepare a real old revision through the same owned maintenance lock."""
    resources = load_migration_resources(MIGRATIONS)
    async with locked_connection(target.settings) as (connection, ownership):

        def apply(sync: object) -> None:
            from sqlalchemy import Connection

            assert isinstance(sync, Connection)
            config = resources.config()
            config.attributes["connection"] = sync
            config.attributes["lock_ownership"] = ownership
            command.upgrade(config, "0001_b0_identity")

        await connection.run_sync(apply)


@pytest.mark.parametrize(
    "invalid",
    [None, "orphan_permission", "wrong_scope", "wrong_audience", "orphan_role", "orphan_user"],
)
async def test_0001_upgrade_preserves_grants_or_refuses_bad_catalog(
    target: MigrationTarget, invalid: str | None
) -> None:
    await upgrade_only_0001(target)
    role_id, user_id, grant_id, membership_id = (uuid4() for _ in range(4))
    engine = create_maintenance_engine(target.settings)
    try:
        async with engine.begin() as connection:
            await connection.execute(
                text(
                    "INSERT INTO users (id,email,email_normalized,password_hash,status) "
                    "VALUES (:id,'old@example.test','old@example.test','old-hash','active')"
                ),
                {"id": user_id},
            )
            await connection.execute(
                text(
                    "INSERT INTO roles (id,code,protected,enabled) VALUES (:id,'reviewer',false,true)"
                ),
                {"id": role_id},
            )
            if invalid != "orphan_permission":
                await connection.execute(
                    text(
                        "INSERT INTO permission_catalog (code,audience,data_scope,enabled) "
                        "VALUES ('client.material.read',:audience,:scope,true)"
                    ),
                    {
                        "audience": "admin" if invalid == "wrong_audience" else "client",
                        "scope": "platform_metadata"
                        if invalid in {"wrong_scope", "wrong_audience"}
                        else "self",
                    },
                )
            await connection.execute(
                text(
                    "INSERT INTO role_permissions (id,role_id,permission_code,effect) "
                    "VALUES (:id,:role,'client.material.read','deny')"
                ),
                {"id": grant_id, "role": uuid4() if invalid == "orphan_role" else role_id},
            )
            await connection.execute(
                text("INSERT INTO user_roles (id,user_id,role_id) VALUES (:id,:user,:role)"),
                {
                    "id": membership_id,
                    "user": uuid4() if invalid == "orphan_user" else user_id,
                    "role": role_id,
                },
            )
            if invalid is None:
                await connection.execute(
                    text(
                        "INSERT INTO seed_versions (code,version,payload_sha256) "
                        "VALUES ('b0-identity-v2',2,:digest)"
                    ),
                    {"digest": "a" * 64},
                )
        if invalid is not None:
            with pytest.raises(MigrationError, match="identity associations"):
                await upgrade_database(target.settings, MIGRATIONS)
            async with engine.connect() as connection:
                assert (
                    await connection.scalar(text("SELECT version_num FROM alembic_version"))
                    == "0001_b0_identity"
                )
                assert await connection.scalar(text("SELECT count(*) FROM role_permissions")) == 1
            return
        async with engine.connect() as connection:
            old_user = (
                await connection.execute(
                    text("SELECT id,password_hash,created_at FROM users WHERE id=:id"),
                    {"id": user_id},
                )
            ).one()
            old_grant_created = await connection.scalar(
                text("SELECT created_at FROM role_permissions WHERE id=:id"), {"id": grant_id}
            )
            old_membership_created = await connection.scalar(
                text("SELECT created_at FROM user_roles WHERE id=:id"), {"id": membership_id}
            )
        result = await upgrade_database(target.settings, MIGRATIONS)
        assert result.compatible
        async with engine.connect() as connection:
            grant = (
                await connection.execute(
                    text(
                        "SELECT id,role_id,permission_code,effect,data_scope FROM role_permission_links"
                    )
                )
            ).one()
            assert tuple(grant) == (grant_id, role_id, "client.material.read", "deny", "self")
            assert (
                await connection.scalar(
                    text("SELECT created_at FROM role_permission_links WHERE id=:id"),
                    {"id": grant_id},
                )
                == old_grant_created
            )
            membership = (
                await connection.execute(text("SELECT id,user_id,role_id FROM user_role_links"))
            ).one()
            assert tuple(membership) == (membership_id, user_id, role_id)
            assert (
                await connection.scalar(
                    text("SELECT created_at FROM user_role_links WHERE id=:id"),
                    {"id": membership_id},
                )
                == old_membership_created
            )
            role = (
                await connection.execute(
                    text("SELECT name,revision,created_at,updated_at FROM roles")
                )
            ).one()
            assert role.name == "reviewer" and role.revision == 2
            assert role.updated_at >= role.created_at
            account = (
                await connection.execute(
                    text(
                        "SELECT password_version,security_epoch,revision,email_verified_at,locked_until "
                        "FROM users"
                    )
                )
            ).one()
            assert tuple(account) == (1, 0, 1, None, None)
            assert (
                await connection.execute(
                    text("SELECT id,password_hash,created_at FROM users WHERE id=:id"),
                    {"id": user_id},
                )
            ).one() == old_user
            assert (
                await connection.scalar(
                    text(
                        "SELECT count(*) FROM pg_constraint WHERE connamespace=current_schema()::regnamespace "
                        "AND contype='f'"
                    )
                )
                == 0
            )
        with pytest.raises(IntegrityError):
            async with engine.begin() as connection:
                await connection.execute(
                    text(
                        "INSERT INTO role_permission_links "
                        "(id,role_id,permission_code,effect,data_scope) "
                        "VALUES (:id,:role,'client.material.read','allow','arbitrary')"
                    ),
                    {"id": uuid4(), "role": role_id},
                )
        assert (await apply_seed(target.settings)).changed
        async with engine.connect() as connection:
            assert (
                await connection.scalar(
                    text(
                        "SELECT count(*) FROM role_permission_links WHERE id=:id AND effect='deny'"
                    ),
                    {"id": grant_id},
                )
                == 1
            )
            assert (
                await connection.scalar(
                    text("SELECT name FROM roles WHERE id=:id"), {"id": role_id}
                )
                == "reviewer"
            )
            assert (
                await connection.scalar(
                    text("SELECT count(*) FROM seed_versions WHERE code='b0-identity-v2'")
                )
                == 1
            )
    finally:
        await engine.dispose()


async def test_two_processes_cannot_execute_ddl_under_different_locks(
    target: MigrationTarget, tmp_path: Path
) -> None:
    directory = fixture_migrations(tmp_path, mode="lock")
    first = start_migration(target, directory, tmp_path / "first.json")
    second: subprocess.Popen[bytes] | None = None
    try:
        held_pid = await waiting_backend(target, query_prefix="SELECT pg_sleep")
        second = start_migration(target, directory, tmp_path / "second.json", timeout=0.1)
        assert await asyncio.to_thread(second.wait, timeout=15) == 2
        assert '"error": "MigrationError"' in (tmp_path / "second.json").read_text(encoding="utf-8")
        assert await asyncio.to_thread(first.wait, timeout=15) == 0
        status = await database_status(target.settings, directory)
        assert status.compatible
        assert f'"pid": {held_pid}' in (tmp_path / "first.json").read_text(encoding="utf-8")
    finally:
        await stop_child(first)
        if second is not None:
            await stop_child(second)


@pytest.mark.parametrize("mode", ["lock", "ddl", "partial"])
async def test_disconnect_fails_then_reacquires_and_observes_committed_state(
    target: MigrationTarget, tmp_path: Path, mode: str
) -> None:
    directory = fixture_migrations(tmp_path, mode=mode)
    process = start_migration(target, directory, tmp_path / "interrupted.json")
    try:
        prefix = "CREATE TABLE interrupted_ddl" if mode == "ddl" else "SELECT pg_sleep"
        pid = await waiting_backend(target, query_prefix=prefix)
        await terminate_backend(target, pid)
        assert await asyncio.to_thread(process.wait, timeout=10) == 2
        status = await database_status(target.settings, directory)
        assert status.backend_pid != pid
        if mode == "partial":
            assert status.current_revision == "test_checkpoint"
            assert "migration_checkpoint" in status.tables
        else:
            assert status.current_revision is None
            assert "interrupted_ddl" not in status.tables
        recovered = await upgrade_database(target.settings, directory)
        assert recovered.compatible and recovered.backend_pid != pid
        assert recovered.current_revision == EXPECTED_REVISION
    finally:
        await stop_child(process)


async def test_bare_alembic_cannot_create_or_connect_without_maintenance_lock(
    target: MigrationTarget,
) -> None:
    config = load_migration_resources(MIGRATIONS).config()
    with pytest.raises(MigrationError, match="haruka-manage"):
        await asyncio.to_thread(command.upgrade, config, EXPECTED_REVISION)
    assert (await database_status(target.settings, MIGRATIONS)).current_revision is None


async def test_schema_check_rejects_an_engine_pointing_at_another_search_path(
    target: MigrationTarget,
) -> None:
    with pytest.raises(SchemaMismatchError, match="search path"):
        await check_schema(target.observer, schema=target.settings.database_schema)
    with pytest.raises(SchemaMismatchError, match="search path"):
        await check_revision(target.observer, schema=target.settings.database_schema)
    with pytest.raises(ValueError, match="isolated migration test schema"):
        await check_revision(target.observer, schema="unregistered_schema")
