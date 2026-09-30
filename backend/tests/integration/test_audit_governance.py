"""Audit reads stay append-only and omit secrets. Counts are identity metadata only."""

import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from pydantic import SecretStr
from sqlalchemy import text
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
from app.models import AdminAuditEvent
from app.services.audit_governance import list_audit_events, read_governance_summary
from app.services.initialization import apply_seed, initialize_admin
from app.services.user_governance import create_account

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    configuration = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if configuration is None:
        pytest.fail("HARUKA_MAINTENANCE_TEST_CONFIG must select the test maintenance file")
    source = load_maintenance_settings(Path(configuration))
    if source.app_env != "test":
        pytest.fail("audit governance tests require haruka_test")
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


async def test_audit_page_hides_secrets_and_summary_counts_identity(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="audit-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    moment = datetime.now(UTC)
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            created = await create_account(
                session,
                actor_id=admin.user_id,
                email="Desk.User@haruka.example.test",
                display_name="服务台",
                role_ids=(),
            )
            session.add_all(
                [
                    AdminAuditEvent(
                        action="user.updated",
                        actor="admin",
                        actor_user_id=admin.user_id,
                        audience="admin",
                        target_type="user",
                        target_code="desk",
                        result="committed",
                        reason_code="status",
                        authorization_revision=1,
                        change_summary={
                            "status": "disabled",
                            "token": "secret-token",
                            "password": "hidden-password",
                        },
                        created_at=moment,
                    ),
                    AdminAuditEvent(
                        action="user.updated",
                        actor="admin",
                        actor_user_id=admin.user_id,
                        audience="admin",
                        target_type="user",
                        target_code="older",
                        result="committed",
                        reason_code="status",
                        authorization_revision=1,
                        change_summary={"status": "active"},
                        created_at=moment - timedelta(minutes=5),
                    ),
                ]
            )
            learner_id = created.user_id
        with pytest.raises(AppError) as denied:
            async with AsyncSession(engine) as session, session.begin():
                await list_audit_events(
                    session,
                    actor_id=learner_id,
                    limit=10,
                    cursor=None,
                    action=None,
                    result=None,
                    actor_user_id=None,
                    target_type=None,
                )
        assert denied.value.code == ErrorCode.PERMISSION_DENIED
        async with AsyncSession(engine) as session, session.begin():
            page, cursor = await list_audit_events(
                session,
                actor_id=admin.user_id,
                limit=1,
                cursor=None,
                action="user.updated",
                result="committed",
                actor_user_id=admin.user_id,
                target_type="user",
            )
            assert cursor is not None
            assert len(page) == 1
            assert page[0].change_summary == {"status": "disabled"}
            rendered = page[0].model_dump_json()
            assert "secret-token" not in rendered
            assert "hidden-password" not in rendered
            assert "Desk.User" not in rendered
            following, done = await list_audit_events(
                session,
                actor_id=admin.user_id,
                limit=10,
                cursor=cursor,
                action="user.updated",
                result="committed",
                actor_user_id=admin.user_id,
                target_type="user",
            )
            assert done is None
            assert [item.target_code for item in following] == ["older"]
            with pytest.raises(AppError) as invalid:
                await list_audit_events(
                    session,
                    actor_id=admin.user_id,
                    limit=10,
                    cursor="not-a-cursor",
                    action=None,
                    result=None,
                    actor_user_id=None,
                    target_type=None,
                )
            assert invalid.value.code == ErrorCode.INPUT_INVALID
            summary = await read_governance_summary(session, actor_id=admin.user_id)
            assert summary.accounts_active >= 1
            assert summary.accounts_pending >= 1
            assert summary.roles_enabled >= 1
            assert summary.authorization_revision >= 1
            assert summary.open_manual_recoveries == 0
            assert "email" not in summary.model_dump()
        with pytest.raises(AppError) as denied_summary:
            async with AsyncSession(engine) as session, session.begin():
                await read_governance_summary(session, actor_id=learner_id)
        assert denied_summary.value.code == ErrorCode.PERMISSION_DENIED
    finally:
        await engine.dispose()
