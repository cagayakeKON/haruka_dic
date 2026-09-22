"""B0 controlled seed/admin transactions and PostgreSQL constraints/timestamps."""

import asyncio
import os
from collections.abc import AsyncIterator
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from argon2 import PasswordHasher
from pydantic import SecretStr
from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.schema import CreateSchema, DropSchema

import app.services.initialization as initialization
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import (
    AdminAuditEvent,
    AuthorizationRevision,
    AuthPolicy,
    Library,
    OutboxEvent,
    Role,
    RolePermission,
    SeedVersion,
    User,
    UserRole,
)
from app.services.initialization import InitializationError, apply_seed, initialize_admin

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    configuration = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if configuration is None:
        pytest.fail(
            "HARUKA_MAINTENANCE_TEST_CONFIG must explicitly select the isolated test maintenance file"
        )
    original = load_maintenance_settings(Path(configuration))
    if original.app_env != "test":
        pytest.fail("initialization failure tests require haruka_test")
    schema = f"haruka_migration_test_{uuid4().hex}"
    settings = MaintenanceSettings(database_url=original.database_url, test_schema=schema)
    observer = create_maintenance_engine(original)
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


async def test_seed_concurrency_upgrade_preserves_manual_grants(
    target: MaintenanceSettings, monkeypatch: pytest.MonkeyPatch
) -> None:
    first, second = await asyncio.gather(apply_seed(target), apply_seed(target))
    assert sorted([first.changed, second.changed]) == [False, True]
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            role = await session.scalar(
                select(Role).where(Role.code == "learner").with_for_update()
            )
            policy = await session.get(AuthPolicy, "registration", with_for_update=True)
            assert role is not None and policy is not None
            session.add(
                RolePermission(
                    role_id=role.id, permission_code="client.material.import", effect="deny"
                )
            )
            policy.registration_mode = "approval"
            role.enabled = False
            role_id = role.id
        assert not (await apply_seed(target)).changed
        monkeypatch.setattr(initialization, "SEED_CODE", "b0-identity-reviewed-next")
        monkeypatch.setattr(initialization, "SEED_VERSION", 3)
        assert (await apply_seed(target)).changed
        async with AsyncSession(engine) as session:
            role = await session.get(Role, role_id)
            policy = await session.get(AuthPolicy, "registration")
            assert role is not None and not role.enabled
            assert policy is not None and policy.registration_mode == "approval"
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(RolePermission)
                    .where(RolePermission.role_id == role_id, RolePermission.effect == "deny")
                )
                == 1
            )
            assert await session.scalar(select(func.count()).select_from(User)) == 0
            assert await session.scalar(select(func.count()).select_from(AdminAuditEvent)) == 2
            assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 2
    finally:
        await engine.dispose()


async def test_admin_is_atomic_private_hashed_and_idempotent(target: MaintenanceSettings) -> None:
    password = SecretStr("Synthetic-Only-Password-For-Tests")
    with pytest.raises(InitializationError, match="seed"):
        await initialize_admin(target, email="admin@example.test", password=password)
    await apply_seed(target)
    first = await initialize_admin(target, email="Admin@Example.test", password=password)
    assert first.changed and first.user_id is not None
    replay = await initialize_admin(
        target, email="admin@example.test", password=SecretStr("Different-Unused-Password")
    )
    assert not replay.changed and replay.user_id == first.user_id
    with pytest.raises(InitializationError, match="already"):
        await initialize_admin(target, email="second@example.test", password=password)
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session:
            user = await session.get(User, first.user_id)
            assert user is not None
            assert user.password_hash.startswith("$argon2id$")
            assert PasswordHasher().verify(user.password_hash, password.get_secret_value())
            assert (
                user.email == "Admin@Example.test" and user.email_normalized == "admin@example.test"
            )
            assert user.created_at == user.updated_at and user.created_at.utcoffset() is not None
            offset = user.created_at.utcoffset()
            assert offset is not None and offset.total_seconds() == 0
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(Library)
                    .where(Library.owner_user_id == user.id)
                )
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count()).select_from(UserRole).where(UserRole.user_id == user.id)
                )
                == 1
            )
            assert await session.scalar(select(func.count()).select_from(AdminAuditEvent)) == 2
            assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 2
            assert not await session.scalar(
                text("SELECT has_table_privilege('haruka_test_runtime', :table, 'UPDATE')"),
                {"table": f"{target.database_schema}.admin_audit_events"},
            )
            assert not await session.scalar(
                text("SELECT has_table_privilege('haruka_test_runtime', :table, 'DELETE')"),
                {"table": f"{target.database_schema}.admin_audit_events"},
            )
    finally:
        await engine.dispose()


async def test_failed_initialization_rolls_back_and_seed_drift_refuses(
    target: MaintenanceSettings, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fail_audit(
        _session: AsyncSession,
        _revision: AuthorizationRevision,
        _action: str,
        _user_id: object = None,
    ) -> None:
        raise RuntimeError("injected-before-audit-commit")

    with monkeypatch.context() as patch:
        patch.setattr(initialization, "_record_change", fail_audit)
        with pytest.raises(RuntimeError, match="injected"):
            await apply_seed(target)
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session:
            assert await session.scalar(select(func.count()).select_from(Role)) == 0
            assert await session.scalar(select(func.count()).select_from(SeedVersion)) == 0
        await apply_seed(target)
        with monkeypatch.context() as patch:
            patch.setattr(initialization, "_record_change", fail_audit)
            with pytest.raises(RuntimeError, match="injected"):
                await initialize_admin(
                    target,
                    email="admin@example.test",
                    password=SecretStr("Synthetic-Only-Password"),
                )
        async with AsyncSession(engine) as session, session.begin():
            assert await session.scalar(select(func.count()).select_from(User)) == 0
            assert await session.scalar(select(func.count()).select_from(Library)) == 0
            assert await session.scalar(select(func.count()).select_from(UserRole)) == 0
            assert await session.scalar(select(func.count()).select_from(AdminAuditEvent)) == 1
            version = await session.get(SeedVersion, initialization.SEED_CODE)
            assert version is not None
            version.payload_sha256 = "0" * 64
        with pytest.raises(InitializationError, match="payload"):
            await apply_seed(target)
        with pytest.raises(InitializationError, match="payload"):
            await initialize_admin(
                target, email="admin@example.test", password=SecretStr("Synthetic-Only-Password")
            )
    finally:
        await engine.dispose()


async def test_pg_constraints_and_explicit_update_paths(target: MaintenanceSettings) -> None:
    await apply_seed(target)
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            role = await session.scalar(select(Role).where(Role.code == "operator"))
            assert role is not None
            role_id, created, initial = role.id, role.created_at, role.updated_at
            role.enabled = False
        async with AsyncSession(engine) as session:
            changed = await session.get(Role, role_id)
            assert (
                changed is not None
                and changed.created_at == created
                and changed.updated_at > initial
            )
            previous = changed.updated_at
        async with engine.begin() as connection:
            await connection.execute(
                update(Role).where(Role.id == role_id).values(enabled=True, updated_at=func.now())
            )
        async with AsyncSession(engine) as session:
            changed = await session.get(Role, role_id)
            assert (
                changed is not None
                and changed.created_at == created
                and changed.updated_at > previous
            )
            previous = changed.updated_at
        async with engine.begin() as connection:
            await connection.execute(
                text("UPDATE roles SET revision=revision+1, updated_at=now() WHERE id=:id"),
                {"id": role_id},
            )
        async with AsyncSession(engine) as session:
            changed = await session.get(Role, role_id)
            assert (
                changed is not None
                and changed.created_at == created
                and changed.updated_at > previous
            )
            previous = changed.updated_at
        async with engine.begin() as connection:
            statement = insert(Role).values(
                id=uuid4(), code="operator", enabled=False, protected=False, revision=1
            )
            await connection.execute(
                statement.on_conflict_do_update(
                    index_elements=[Role.code], set_={"enabled": False, "updated_at": func.now()}
                )
            )
        async with AsyncSession(engine) as session:
            changed = await session.get(Role, role_id)
            assert (
                changed is not None
                and changed.created_at == created
                and changed.updated_at > previous
            )
            previous = changed.updated_at
        await apply_seed(target)
        async with AsyncSession(engine) as session:
            changed = await session.get(Role, role_id)
            assert changed is not None and changed.updated_at == previous
        for values in (
            {"code": "operator", "revision": 1},
            {"code": "invalid-revision", "revision": 0},
            {"code": None, "revision": 1},
        ):
            with pytest.raises(IntegrityError):
                async with engine.begin() as connection:
                    await connection.execute(
                        insert(Role).values(id=uuid4(), enabled=True, protected=False, **values)
                    )
    finally:
        await engine.dispose()
