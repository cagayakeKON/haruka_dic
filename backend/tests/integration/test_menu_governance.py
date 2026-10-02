"""Menu layout hides navigation without revoking the page permission."""

import os
from collections.abc import AsyncIterator
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from pydantic import SecretStr
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.schema import CreateSchema, DropSchema

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import Menu, Role, RolePermission, User, UserRole
from app.schemas.menu_governance import MenuGroupCreate, MenuLayoutItem, MenuRead
from app.services.auth_crypto import hash_password
from app.services.authorization import allowed_pairs, allows, load_graph
from app.services.initialization import apply_seed, initialize_admin
from app.services.menu_governance import (
    create_group,
    delete_group,
    list_menus,
    preview_navigation,
    project_navigation,
    replace_layout,
)

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    configuration = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if configuration is None:
        pytest.fail("HARUKA_MAINTENANCE_TEST_CONFIG must select the test maintenance file")
    source = load_maintenance_settings(Path(configuration))
    if source.app_env != "test":
        pytest.fail("menu governance tests require haruka_test")
    schema = f"haruka_migration_test_{uuid4().hex}"
    settings = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        await upgrade_database(settings, MIGRATIONS)
        yield settings
    finally:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


def _item(menu: MenuRead, **changes: object) -> MenuLayoutItem:
    payload: dict[str, object] = {
        "menu_id": menu.id,
        "expected_revision": menu.revision,
        "title": menu.title,
        "parent_menu_id": menu.parent_menu_id,
        "sort_order": menu.sort_order,
        "icon_key": menu.icon_key,
        "enabled": menu.enabled,
        "permission_match": menu.permission_match,
        "permission_codes": list(menu.permission_codes),
    }
    payload.update(changes)
    return MenuLayoutItem.model_validate(payload)


async def test_existing_seed_inserts_only_missing_published_menus(
    target: MaintenanceSettings,
) -> None:
    first = await apply_seed(target)
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            users = await session.scalar(select(Menu).where(Menu.code == "users"))
            library = await session.scalar(select(Menu).where(Menu.code == "library"))
            assert users is not None and library is not None
            users.title = "账号"
            users.enabled = False
            await session.delete(library)
        restored = await apply_seed(target)
        assert restored.changed is True
        assert restored.authorization_revision == first.authorization_revision + 1
        async with AsyncSession(engine) as session, session.begin():
            users = await session.scalar(select(Menu).where(Menu.code == "users"))
            library = await session.scalar(select(Menu).where(Menu.code == "library"))
            legacy = await session.scalar(select(Menu).where(Menu.code == "administration"))
            assert users is not None and users.title == "账号" and users.enabled is False
            assert library is not None and library.enabled is True
            assert legacy is not None and legacy.enabled is False
        repeat = await apply_seed(target)
        assert repeat.changed is False
        assert repeat.authorization_revision == restored.authorization_revision
    finally:
        await engine.dispose()


async def test_hiding_a_menu_keeps_the_page_permission(target: MaintenanceSettings) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="menus-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            menus = await list_menus(session, actor_id=admin.user_id)
            users = next(menu for menu in menus if menu.code == "users")
            legacy = next(menu for menu in menus if menu.code == "administration")
            assert users.enabled is True
            assert users.floor == ["admin.user.read"]
            assert legacy.enabled is False
            with pytest.raises(AppError) as unknown:
                await replace_layout(
                    session,
                    actor_id=admin.user_id,
                    items=(_item(legacy, enabled=True),),
                )
            assert unknown.value.code == ErrorCode.INPUT_INVALID
            with pytest.raises(AppError) as foreign:
                await replace_layout(
                    session,
                    actor_id=admin.user_id,
                    items=(_item(users, permission_codes=["client.material.list"]),),
                )
            assert foreign.value.code == ErrorCode.INPUT_INVALID
            hidden = await replace_layout(
                session,
                actor_id=admin.user_id,
                items=(_item(users, enabled=False, title="账号"),),
            )
            assert hidden.audit_id is not None
            graph = await load_graph(session, admin.user_id)
            assert allows(graph, admin.user_id, "admin.user.read", "platform_metadata")
            allowed = {code for code, _scope in allowed_pairs(graph, admin.user_id)}
            navigation = await project_navigation(session, audience="admin", allowed=allowed)
            assert all(item.route_key != "users" for item in navigation)
            shown = next(menu for menu in hidden.menus if menu.code == "users")
            again = await replace_layout(session, actor_id=admin.user_id, items=(_item(shown),))
            assert again.audit_id is None
            assert again.authorization_revision == hidden.authorization_revision
            role = Role(
                code="menu_limited", name="menu_limited", protected=False, enabled=True, revision=1
            )
            session.add(role)
            await session.flush()
            session.add(
                RolePermission(
                    role_id=role.id,
                    permission_code="admin.user.read",
                    effect="allow",
                    data_scope="platform_metadata",
                )
            )
            account = User(
                email="menu-limited@haruka.example.test",
                email_normalized="menu-limited@haruka.example.test",
                password_hash=await hash_password(SecretStr("synthetic-menu-password-2026")),
                status="active",
                authz_version=1,
                password_version=1,
                security_epoch=0,
                revision=1,
                email_verified_at=None,
                locked_until=None,
                approval_status="not_required",
                client_security_epoch=0,
                admin_security_epoch=0,
            )
            session.add(account)
            await session.flush()
            session.add(UserRole(user_id=account.id, role_id=role.id))
            await session.flush()
            opened = next(menu for menu in again.menus if menu.code == "users")
            tightened = await replace_layout(
                session,
                actor_id=admin.user_id,
                items=(_item(opened, enabled=True, permission_codes=["admin.audit.read"]),),
            )
            preview = await preview_navigation(
                session, actor_id=admin.user_id, user_id=account.id, audience="admin"
            )
            assert all(item.route_key != "users" for item in preview)
            assert all(not hasattr(item, "email") for item in preview)
            limited = await load_graph(session, account.id)
            assert allows(limited, account.id, "admin.user.read", "platform_metadata")
            current = next(menu for menu in tightened.menus if menu.code == "users")
            await replace_layout(
                session,
                actor_id=admin.user_id,
                items=(_item(current, permission_codes=[]),),
            )
            restored = await preview_navigation(
                session, actor_id=admin.user_id, user_id=account.id, audience="admin"
            )
            assert any(item.route_key == "users" for item in restored)
            group = await create_group(
                session,
                actor_id=admin.user_id,
                command=MenuGroupCreate(code="desk_group", audience="admin", title="分组"),
            )
            created = next(menu for menu in group.menus if menu.code == "desk_group")
            placed = next(menu for menu in group.menus if menu.code == "users")
            nested = await replace_layout(
                session,
                actor_id=admin.user_id,
                items=(_item(placed, parent_menu_id=created.id), _item(created, enabled=False)),
            )
            nested_nav = await project_navigation(
                session, audience="admin", allowed={"admin.user.read", "admin.login"}
            )
            assert all(item.route_key != "users" for item in nested_nav)
            with pytest.raises(AppError) as conflict:
                await replace_layout(
                    session,
                    actor_id=admin.user_id,
                    items=(_item(placed, title="过期"),),
                )
            assert conflict.value.code == ErrorCode.REVISION_CONFLICT
            live_users = next(menu for menu in nested.menus if menu.code == "users")
            live_group = next(menu for menu in nested.menus if menu.code == "desk_group")
            with pytest.raises(AppError) as kept:
                await delete_group(
                    session,
                    actor_id=admin.user_id,
                    menu_id=live_users.id,
                    expected_revision=live_users.revision,
                )
            assert kept.value.code == ErrorCode.STATE_CONFLICT
            detached = await replace_layout(
                session,
                actor_id=admin.user_id,
                items=(_item(live_users, parent_menu_id=None),),
            )
            live_group = next(menu for menu in detached.menus if menu.code == "desk_group")
            removed = await delete_group(
                session,
                actor_id=admin.user_id,
                menu_id=live_group.id,
                expected_revision=live_group.revision,
            )
            assert all(menu.code != "desk_group" for menu in removed.menus)
            stored = await session.scalar(select(Menu.title).where(Menu.code == "users"))
            assert stored == "账号"
        await apply_seed(target)
        async with AsyncSession(engine) as session, session.begin():
            retained = await session.scalar(select(Menu.title).where(Menu.code == "users"))
            assert retained == "账号"
    finally:
        await engine.dispose()
