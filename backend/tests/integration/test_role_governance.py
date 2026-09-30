"""Role creation stays empty, and later grants stay inside the actor ceiling."""

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
from app.models import Role, RolePermission, User, UserRole
from app.schemas.role_governance import GrantBoundaryWrite
from app.services.auth_crypto import hash_password
from app.services.authorization import allows, load_graph
from app.services.initialization import apply_seed, initialize_admin
from app.services.role_governance import (
    create_role,
    delete_role,
    replace_grant_boundaries,
    replace_role_grants,
    replace_role_parents,
    set_role_enabled,
    update_role_metadata,
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
        pytest.fail("role governance tests require haruka_test")
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


async def test_ceiling_blocks_uncapped_grants_and_preserves_last_admin(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="roles-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            created = await create_role(
                session,
                actor_id=admin.user_id,
                code="desk",
                name="Desk",
                description=None,
            )
            stored = await session.get(Role, created.role_id)
            assert stored is not None
            assert stored.protected is False
            assert (
                await session.scalar(
                    select(RolePermission.id).where(RolePermission.role_id == created.role_id)
                )
                is None
            )
            with pytest.raises(AppError) as uncapped:
                await replace_role_grants(
                    session,
                    actor_id=admin.user_id,
                    role_id=created.role_id,
                    expected_revision=created.revision,
                    grants=(("admin.dashboard.view", "allow", "platform_metadata"),),
                )
            assert uncapped.value.code == ErrorCode.PERMISSION_DENIED
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_admin is not None
            bounded = await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.dashboard.view",
                        data_scope="platform_metadata",
                    ),
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.login",
                        data_scope="platform_metadata",
                    ),
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=created.role_id),
                ),
            )
            granted = await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=created.role_id,
                expected_revision=created.revision,
                grants=(
                    ("admin.dashboard.view", "allow", "platform_metadata"),
                    ("admin.dashboard.view", "deny", "platform_metadata"),
                ),
            )
            holder = User(
                email="desk-user@haruka.example.test",
                email_normalized="desk-user@haruka.example.test",
                password_hash=await hash_password(SecretStr(uuid4().hex)),
                status="active",
            )
            session.add(holder)
            await session.flush()
            session.add(UserRole(user_id=holder.id, role_id=created.role_id))
            await session.flush()
            graph = await load_graph(session, holder.id)
            assert not allows(graph, holder.id, "admin.dashboard.view", "platform_metadata")
            renamed = await update_role_metadata(
                session,
                actor_id=admin.user_id,
                role_id=created.role_id,
                expected_revision=granted.revision,
                name="Front desk",
                description=None,
            )
            assert renamed.revision == granted.revision + 1
            assert bounded.audit_id is not None
        with pytest.raises(AppError) as stale:
            async with AsyncSession(engine) as session, session.begin():
                await update_role_metadata(
                    session,
                    actor_id=admin.user_id,
                    role_id=created.role_id,
                    expected_revision=1,
                    name="Stale",
                    description=None,
                )
        assert stale.value.code == ErrorCode.REVISION_CONFLICT
        with pytest.raises(AppError) as public_role:
            async with AsyncSession(engine) as session, session.begin():
                learner = await session.scalar(select(Role).where(Role.code == "learner"))
                assert learner is not None
                await replace_role_grants(
                    session,
                    actor_id=admin.user_id,
                    role_id=learner.id,
                    expected_revision=learner.revision,
                    grants=(("admin.login", "allow", "platform_metadata"),),
                )
        assert public_role.value.code == ErrorCode.STATE_CONFLICT
        with pytest.raises(AppError) as last_admin:
            async with AsyncSession(engine) as session, session.begin():
                super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
                assert super_admin is not None
                await set_role_enabled(
                    session,
                    actor_id=admin.user_id,
                    role_id=super_admin.id,
                    expected_revision=super_admin.revision,
                    enabled=False,
                )
        assert last_admin.value.code == ErrorCode.STATE_CONFLICT
        async with AsyncSession(engine) as session, session.begin():
            login_grants = (
                await session.scalars(
                    select(RolePermission.effect)
                    .join(Role, Role.id == RolePermission.role_id)
                    .where(
                        Role.code == "super_admin",
                        RolePermission.permission_code == "admin.login",
                        RolePermission.effect == "allow",
                    )
                )
            ).all()
            assert login_grants == ["allow"]
            current = await session.get(Role, created.role_id)
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert current is not None and super_admin is not None
            parent = await create_role(
                session, actor_id=admin.user_id, code="desk_parent", name="Parent", description=None
            )
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.dashboard.view",
                        data_scope="platform_metadata",
                    ),
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.login",
                        data_scope="platform_metadata",
                    ),
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=parent.role_id),
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=created.role_id),
                ),
            )
            await replace_role_parents(
                session,
                actor_id=admin.user_id,
                role_id=created.role_id,
                expected_revision=current.revision,
                parent_role_ids=(parent.role_id,),
            )
        with pytest.raises(AppError) as cycle:
            async with AsyncSession(engine) as session, session.begin():
                parent_role = await session.scalar(select(Role).where(Role.code == "desk_parent"))
                desk = await session.scalar(select(Role).where(Role.code == "desk"))
                assert parent_role is not None and desk is not None
                await replace_role_parents(
                    session,
                    actor_id=admin.user_id,
                    role_id=parent_role.id,
                    expected_revision=parent_role.revision,
                    parent_role_ids=(desk.id,),
                )
        assert cycle.value.code == ErrorCode.STATE_CONFLICT
        async with AsyncSession(engine) as session, session.begin():
            desk = await session.scalar(select(Role).where(Role.code == "desk"))
            assert desk is not None
            cleared = await replace_role_parents(
                session,
                actor_id=admin.user_id,
                role_id=desk.id,
                expected_revision=desk.revision,
                parent_role_ids=(),
            )
            await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=desk.id,
                expected_revision=cleared.revision,
                grants=(),
            )
            await session.execute(
                text("DELETE FROM user_role_links WHERE role_id = :id"), {"id": desk.id}
            )
            removed = await delete_role(
                session,
                actor_id=admin.user_id,
                role_id=desk.id,
                expected_revision=cleared.revision + 1,
            )
            assert removed.audit_id is not None
    finally:
        await engine.dispose()


async def test_enabling_and_own_ceiling_stay_inside_the_actor_ceiling(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="ceiling-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_admin is not None
            limited = await create_role(
                session, actor_id=admin.user_id, code="limited", name="Limited", description=None
            )
            wide = await create_role(
                session, actor_id=admin.user_id, code="wide", name="Wide", description=None
            )
            small = await create_role(
                session, actor_id=admin.user_id, code="small", name="Small", description=None
            )
            high = await create_role(
                session, actor_id=admin.user_id, code="high", name="High", description=None
            )
            parent_only = await create_role(
                session,
                actor_id=admin.user_id,
                code="parent_only",
                name="Parent only",
                description=None,
            )
            outside = await create_role(
                session, actor_id=admin.user_id, code="outside", name="Outside", description=None
            )
            permission_ceiling = (
                "admin.role.update",
                "admin.role.permission.assign",
                "admin.grant_boundary.update",
                "admin.login",
                "admin.dashboard.view",
            )
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=tuple(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code=code,
                        data_scope="platform_metadata",
                    )
                    for code in permission_ceiling
                )
                + tuple(
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=role_id)
                    for role_id in (
                        limited.role_id,
                        wide.role_id,
                        small.role_id,
                        high.role_id,
                        parent_only.role_id,
                        outside.role_id,
                    )
                ),
            )
            limited_grants = await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=limited.role_id,
                expected_revision=limited.revision,
                grants=tuple(
                    (code, "allow", "platform_metadata")
                    for code in (
                        "admin.role.update",
                        "admin.role.permission.assign",
                        "admin.grant_boundary.update",
                    )
                ),
            )
            limited_ceiling = await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=limited.role_id,
                expected_revision=limited_grants.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.dashboard.view",
                        data_scope="platform_metadata",
                    ),
                ),
            )
            wide_grants = await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=wide.role_id,
                expected_revision=wide.revision,
                grants=(("admin.login", "allow", "platform_metadata"),),
            )
            wide_disabled = await set_role_enabled(
                session,
                actor_id=admin.user_id,
                role_id=wide.role_id,
                expected_revision=wide_grants.revision,
                enabled=False,
            )
            small_grants = await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=small.role_id,
                expected_revision=small.revision,
                grants=(("admin.dashboard.view", "allow", "platform_metadata"),),
            )
            small_disabled = await set_role_enabled(
                session,
                actor_id=admin.user_id,
                role_id=small.role_id,
                expected_revision=small_grants.revision,
                enabled=False,
            )
            parented = await replace_role_parents(
                session,
                actor_id=admin.user_id,
                role_id=parent_only.role_id,
                expected_revision=parent_only.revision,
                parent_role_ids=(high.role_id,),
            )
            parent_disabled = await set_role_enabled(
                session,
                actor_id=admin.user_id,
                role_id=parent_only.role_id,
                expected_revision=parented.revision,
                enabled=False,
            )
            delegate = User(
                email="limited-admin@haruka.example.test",
                email_normalized="limited-admin@haruka.example.test",
                password_hash=await hash_password(SecretStr(uuid4().hex)),
                status="active",
            )
            session.add(delegate)
            await session.flush()
            session.add(UserRole(user_id=delegate.id, role_id=limited.role_id))
            delegate_id = delegate.id
            limited_id = limited.role_id
            limited_revision = limited_ceiling.revision
            wide_id = wide.role_id
            wide_revision = wide_disabled.revision
            small_id = small.role_id
            small_revision = small_disabled.revision
            parent_id = parent_only.role_id
            parent_revision = parent_disabled.revision
            outside_id = outside.role_id
            outside_revision = outside.revision
        async with AsyncSession(engine) as session, session.begin():
            with pytest.raises(AppError) as blocked_grants:
                await set_role_enabled(
                    session,
                    actor_id=delegate_id,
                    role_id=wide_id,
                    expected_revision=wide_revision,
                    enabled=True,
                )
            assert blocked_grants.value.code == ErrorCode.PERMISSION_DENIED
            with pytest.raises(AppError) as blocked_parent:
                await set_role_enabled(
                    session,
                    actor_id=delegate_id,
                    role_id=parent_id,
                    expected_revision=parent_revision,
                    enabled=True,
                )
            assert blocked_parent.value.code == ErrorCode.PERMISSION_DENIED
            with pytest.raises(AppError) as own_ceiling:
                await replace_grant_boundaries(
                    session,
                    actor_id=delegate_id,
                    role_id=limited_id,
                    expected_revision=limited_revision,
                    boundaries=(
                        GrantBoundaryWrite(
                            boundary_kind="assign_permission",
                            permission_code="admin.login",
                            data_scope="platform_metadata",
                        ),
                    ),
                )
            assert own_ceiling.value.code == ErrorCode.PERMISSION_DENIED
            opened = await set_role_enabled(
                session,
                actor_id=delegate_id,
                role_id=small_id,
                expected_revision=small_revision,
                enabled=True,
            )
            assert opened.revision == small_revision + 1
            delegated = await replace_grant_boundaries(
                session,
                actor_id=delegate_id,
                role_id=outside_id,
                expected_revision=outside_revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.dashboard.view",
                        data_scope="platform_metadata",
                    ),
                ),
            )
            assert delegated.audit_id is not None
        async with AsyncSession(engine) as session, session.begin():
            wide_role = await session.get(Role, wide_id)
            assert wide_role is not None and wide_role.enabled is False
            enabled = await set_role_enabled(
                session,
                actor_id=admin.user_id,
                role_id=wide_id,
                expected_revision=wide_revision,
                enabled=True,
            )
            assert enabled.revision == wide_revision + 1
    finally:
        await engine.dispose()


async def test_disabled_ancestor_cannot_raise_the_actor_ceiling(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="ancestor-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_admin is not None
            limited = await create_role(
                session, actor_id=admin.user_id, code="limited", name="Limited", description=None
            )
            ancestor = await create_role(
                session, actor_id=admin.user_id, code="ancestor", name="Ancestor", description=None
            )
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=tuple(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code=code,
                        data_scope="platform_metadata",
                    )
                    for code in (
                        "admin.role.update",
                        "admin.role.permission.assign",
                        "admin.grant_boundary.update",
                        "admin.login",
                        "admin.dashboard.view",
                    )
                )
                + (
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=limited.role_id),
                    GrantBoundaryWrite(
                        boundary_kind="assign_role", target_role_id=ancestor.role_id
                    ),
                ),
            )
            granted = await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=limited.role_id,
                expected_revision=limited.revision,
                grants=tuple(
                    (code, "allow", "platform_metadata")
                    for code in (
                        "admin.role.update",
                        "admin.role.permission.assign",
                        "admin.grant_boundary.update",
                    )
                ),
            )
            capped = await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=limited.role_id,
                expected_revision=granted.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.dashboard.view",
                        data_scope="platform_metadata",
                    ),
                ),
            )
            await replace_role_parents(
                session,
                actor_id=admin.user_id,
                role_id=limited.role_id,
                expected_revision=capped.revision,
                parent_role_ids=(ancestor.role_id,),
            )
            disabled = await set_role_enabled(
                session,
                actor_id=admin.user_id,
                role_id=ancestor.role_id,
                expected_revision=ancestor.revision,
                enabled=False,
            )
            delegate = User(
                email="ancestor-delegate@haruka.example.test",
                email_normalized="ancestor-delegate@haruka.example.test",
                password_hash=await hash_password(SecretStr(uuid4().hex)),
                status="active",
            )
            session.add(delegate)
            await session.flush()
            session.add(UserRole(user_id=delegate.id, role_id=limited.role_id))
            delegate_id = delegate.id
            ancestor_id = ancestor.role_id
            ancestor_revision = disabled.revision
        async with AsyncSession(engine) as session, session.begin():
            with pytest.raises(AppError) as planted:
                await replace_grant_boundaries(
                    session,
                    actor_id=delegate_id,
                    role_id=ancestor_id,
                    expected_revision=ancestor_revision,
                    boundaries=(
                        GrantBoundaryWrite(
                            boundary_kind="assign_permission",
                            permission_code="admin.login",
                            data_scope="platform_metadata",
                        ),
                    ),
                )
            assert planted.value.code == ErrorCode.PERMISSION_DENIED
            widened = await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=ancestor_id,
                expected_revision=ancestor_revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.login",
                        data_scope="platform_metadata",
                    ),
                ),
            )
            with pytest.raises(AppError) as blocked:
                await set_role_enabled(
                    session,
                    actor_id=delegate_id,
                    role_id=ancestor_id,
                    expected_revision=widened.revision,
                    enabled=True,
                )
            assert blocked.value.code == ErrorCode.PERMISSION_DENIED
        async with AsyncSession(engine) as session, session.begin():
            stored = await session.get(Role, ancestor_id)
            assert stored is not None and stored.enabled is False
            narrowed = await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=ancestor_id,
                expected_revision=stored.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code="admin.dashboard.view",
                        data_scope="platform_metadata",
                    ),
                ),
            )
            opened = await set_role_enabled(
                session,
                actor_id=delegate_id,
                role_id=ancestor_id,
                expected_revision=narrowed.revision,
                enabled=True,
            )
            assert opened.revision == narrowed.revision + 1
    finally:
        await engine.dispose()
