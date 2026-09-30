"""Identity additive identity structure in an owned, disposable PostgreSQL schema."""

import asyncio
import os
from collections.abc import AsyncIterator
from dataclasses import replace
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy import Connection, inspect, text
from sqlalchemy.schema import CreateSchema, DropSchema

from app.maintenance.migrations import (
    _upgrade,  # pyright: ignore[reportPrivateUsage]
    load_migration_resources,
    locked_connection,
    upgrade_database,
)
from app.maintenance.schema import EXPECTED_REVISION, check_schema
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import AuthChallenge, AuthChallengeDelivery, AuthSession, UserExtension

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    selected = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if selected is None:
        pytest.fail("HARUKA_MAINTENANCE_TEST_CONFIG must select the test maintenance file")
    path = await asyncio.to_thread(Path(selected).resolve)
    source = load_maintenance_settings(path)
    if source.app_env != "test":
        pytest.fail("Identity migrations require the dedicated test database")
    schema = f"haruka_migration_test_{uuid4().hex}"
    target = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        yield target
    finally:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


async def test_identity_core_is_additive_and_matches_model(target: MaintenanceSettings) -> None:
    status = await upgrade_database(target, MIGRATIONS)
    assert status.current_revision == EXPECTED_REVISION
    engine = create_maintenance_engine(target)
    try:
        await check_schema(engine, schema=target.database_schema)
        async with engine.connect() as connection:

            def reflected(sync_connection: Connection) -> dict[str, bool]:
                inspector = inspect(sync_connection)
                return {
                    table.__tablename__: bool(
                        inspector.get_foreign_keys(
                            table.__tablename__, schema=target.database_schema
                        )
                    )
                    for table in (
                        UserExtension,
                        AuthSession,
                        AuthChallenge,
                        AuthChallengeDelivery,
                    )
                }

            foreign_keys = await connection.run_sync(reflected)
            assert not any(foreign_keys.values())
            policy = (
                await connection.execute(
                    text(
                        "SELECT registration_mode, require_email_verification, recovery_mode "
                        "FROM auth_policies WHERE code='registration'"
                    )
                )
            ).one_or_none()
            assert policy is None or policy == ("closed", True, "email")
            grants = (
                await connection.execute(
                    text(
                        "SELECT has_schema_privilege(:role, :schema, 'USAGE'), "
                        "has_table_privilege(:role, :learning_table, 'SELECT, INSERT, UPDATE, DELETE'), "
                        "has_table_privilege(:role, :audit_table, 'INSERT'), "
                        "has_table_privilege(:role, :audit_table, 'UPDATE'), "
                        "has_table_privilege(:role, :version_table, 'INSERT')"
                    ),
                    {
                        "role": "haruka_test_runtime",
                        "schema": target.database_schema,
                        "learning_table": f"{target.database_schema}.materials",
                        "audit_table": f"{target.database_schema}.admin_audit_events",
                        "version_table": f"{target.database_schema}.alembic_version",
                    },
                )
            ).one()
            assert grants == (True, True, True, False, False)
    finally:
        await engine.dispose()


async def test_governance_migrations_preserve_existing_client_receipt(
    target: MaintenanceSettings,
) -> None:
    """Constraint-level legacy receipt fixture survives both additive revisions."""
    resources = load_migration_resources(MIGRATIONS)
    receipt_id, owner_id, result_id = uuid4(), uuid4(), uuid4()
    async with locked_connection(target) as (connection, ownership):
        await connection.run_sync(
            _upgrade,
            replace(resources, head="0007_authorization_governance"),
            ownership,
        )
        await connection.execute(
            text("""
            INSERT INTO idempotency_records
            (id, owner_user_id, audience, action_code, key_digest, request_digest, state,
             result_kind, result_id, safe_response, response_schema_version, http_status, expires_at, operation_id)
            VALUES (:id, :owner, 'client', 'collection.create', :digest, :request, 'committed',
                    'collection_item', :result, CAST(:response AS jsonb), 1, 201, now() + interval '7 days', :op)
        """),
            {
                "id": receipt_id,
                "owner": owner_id,
                "digest": b"d" * 32,
                "request": b"r" * 32,
                "result": result_id,
                "response": '{"collection_id":"legacy"}',
                "op": uuid4(),
            },
        )
        await connection.commit()
        await connection.run_sync(_upgrade, resources, ownership)
        row = (
            await connection.execute(
                text("""
            SELECT audience, result_kind, result_id, safe_response, lookup_digest
            FROM idempotency_records WHERE id = :id
        """),
                {"id": receipt_id},
            )
        ).one()
        assert row == ("client", "collection_item", result_id, {"collection_id": "legacy"}, None)
    status = await upgrade_database(target, MIGRATIONS)
    assert status.compatible and status.current_revision == "0009_governance_lookup"
