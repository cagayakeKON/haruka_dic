"""Inheritance filtering and menu-link migration against an isolated schema."""

import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from alembic import command
from pydantic import SecretStr
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.schema import CreateSchema, DropSchema

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.maintenance.migrations import (
    load_migration_resources,
    locked_connection,
    upgrade_database,
)
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import Role, RoleInheritance, RolePermission, User, UserRole
from app.services.auth_crypto import hash_password
from app.services.authorization import (
    allows,
    count_login_capable_super_admins,
    load_graph,
    require_effective_permissions,
)
from app.services.initialization import apply_seed, initialize_admin

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    configuration = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if configuration is None:
        pytest.fail("HARUKA_MAINTENANCE_TEST_CONFIG must select the test maintenance file")
    source = load_maintenance_settings(Path(configuration))
    if source.app_env != "test":
        pytest.fail("authorization kernel tests require haruka_test")
    schema = f"haruka_migration_test_{uuid4().hex}"
    settings = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        yield settings
    finally:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


async def test_disabled_parent_and_parent_deny_do_not_grant(
    target: MaintenanceSettings,
) -> None:
    await upgrade_database(target, MIGRATIONS)
    await apply_seed(target)
    result = await initialize_admin(
        target,
        email="kernel-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert result.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            menu_permission_column = await session.scalar(
                text(
                    "SELECT COUNT(*) FROM information_schema.columns "
                    "WHERE table_schema = current_schema() AND table_name = 'menus' "
                    "AND column_name = 'permission_code'"
                )
            )
            assert menu_permission_column == 0
            assert await session.scalar(text("SELECT COUNT(*) FROM menus")) == await session.scalar(
                text("SELECT COUNT(*) FROM menu_permission_links")
            )
            parent = Role(
                code="kernel_parent",
                name="kernel parent",
                protected=False,
                enabled=True,
                revision=1,
            )
            child = Role(
                code="kernel_child", name="kernel child", protected=False, enabled=True, revision=1
            )
            user = User(
                email="kernel-user@haruka.example.test",
                email_normalized="kernel-user@haruka.example.test",
                password_hash=await hash_password(SecretStr(uuid4().hex)),
                status="active",
            )
            session.add_all([parent, child, user])
            await session.flush()
            session.add(RoleInheritance(child_role_id=child.id, parent_role_id=parent.id))
            session.add(
                RolePermission(
                    role_id=parent.id,
                    permission_code="admin.user.read",
                    effect="allow",
                    data_scope="platform_metadata",
                )
            )
            session.add(UserRole(user_id=user.id, role_id=child.id))
            await session.flush()
            inherited = await load_graph(session, user.id)
            assert allows(inherited, user.id, "admin.user.read", "platform_metadata")
            await require_effective_permissions(
                session,
                user_id=user.id,
                requirements=(("admin.user.read", "platform_metadata"),),
            )
            parent.enabled = False
            await session.flush()
            disabled = await load_graph(session, user.id)
            assert not allows(disabled, user.id, "admin.user.read", "platform_metadata")
            with pytest.raises(AppError) as rejected:
                await require_effective_permissions(
                    session,
                    user_id=user.id,
                    requirements=(("admin.user.read", "platform_metadata"),),
                )
            assert rejected.value.code == ErrorCode.PERMISSION_DENIED
            parent.enabled = True
            await session.flush()
            session.add(
                RolePermission(
                    role_id=parent.id,
                    permission_code="admin.user.read",
                    effect="deny",
                    data_scope="platform_metadata",
                )
            )
            session.add(
                RolePermission(
                    role_id=child.id,
                    permission_code="admin.user.read",
                    effect="allow",
                    data_scope="platform_metadata",
                )
            )
            await session.flush()
            denied = await load_graph(session, user.id)
            assert not allows(denied, user.id, "admin.user.read", "platform_metadata")
            capable = await count_login_capable_super_admins(session, now=datetime.now(UTC))
            assert capable == 1
            await session.execute(
                text(
                    "UPDATE menu_permission_links SET permission_code = 'admin.user.read' "
                    "WHERE menu_id = (SELECT id FROM menus WHERE code = 'administration')"
                )
            )
        await apply_seed(target)
        async with AsyncSession(engine) as session, session.begin():
            retained = await session.scalar(
                text(
                    "SELECT permission_code FROM menu_permission_links "
                    "WHERE menu_id = (SELECT id FROM menus WHERE code = 'administration')"
                )
            )
            assert retained == "admin.user.read"
    finally:
        await engine.dispose()


async def test_existing_menu_permission_is_copied(target: MaintenanceSettings) -> None:
    resources = load_migration_resources(MIGRATIONS)
    async with locked_connection(target) as (connection, ownership):

        def apply(sync: object) -> None:
            from sqlalchemy import Connection

            assert isinstance(sync, Connection)
            config = resources.config()
            config.attributes["connection"] = sync
            config.attributes["lock_ownership"] = ownership
            command.upgrade(config, "0006_avatar_assets")

        await connection.run_sync(apply)
    menu_id = uuid4()
    engine = create_maintenance_engine(target)
    try:
        async with engine.begin() as connection:
            await connection.execute(
                text(
                    "INSERT INTO menus (id, code, route_key, audience, permission_code, enabled) "
                    "VALUES (:id, 'legacy_admin', '/admin', 'admin', 'admin.user.read', true)"
                ),
                {"id": menu_id},
            )
    finally:
        await engine.dispose()
    await upgrade_database(target, MIGRATIONS)
    engine = create_maintenance_engine(target)
    try:
        async with engine.begin() as connection:
            copied = await connection.scalar(
                text("SELECT permission_code FROM menu_permission_links WHERE menu_id = :id"),
                {"id": menu_id},
            )
            assert copied == "admin.user.read"
            column = await connection.scalar(
                text(
                    "SELECT COUNT(*) FROM information_schema.columns "
                    "WHERE table_schema = current_schema() AND table_name = 'menus' "
                    "AND column_name = 'permission_code'"
                )
            )
            assert column == 0
    finally:
        await engine.dispose()
