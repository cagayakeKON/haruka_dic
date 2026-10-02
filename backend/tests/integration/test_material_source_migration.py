"""Real locked legacy upgrade and row invariants in a disposable PostgreSQL schema."""

import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from alembic import command
from sqlalchemy import Connection, insert, inspect, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.schema import CreateSchema, DropSchema

from app.maintenance.migrations import load_migration_resources, locked_connection, upgrade_database
from app.maintenance.schema import check_schema_connection
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import (
    Library,
    Material,
    MaterialRevision,
    User,
)
from app.models.avatar import FileObject, UploadIntent
from app.models.material_imports import MaterialImport, UserStorageState
from app.models.model_tasks import Job

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "backend/alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    if os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG") != "dev/.local/test-maintenance.env":
        pytest.fail("explicit isolated test maintenance configuration is required")
    source = load_maintenance_settings(ROOT / "dev/.local/test-maintenance.env")
    assert source.app_env == "test"
    schema = "haruka_migration_test_" + uuid4().hex
    settings = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        yield settings
    finally:
        async with observer.begin() as connection:
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


async def test_locked_source_upgrade_preserves_legacy_rows_and_rejects_invalid_jobs(
    target: MaintenanceSettings,
) -> None:
    owner, library, material, upload, asset = (uuid4() for _ in range(5))
    legacy_revision = uuid4()
    now = datetime.now(UTC)
    resources = load_migration_resources(MIGRATIONS)
    async with locked_connection(target) as (connection, ownership):

        def legacy(conn: Connection) -> None:
            cfg = resources.config()
            cfg.attributes.update(connection=conn, lock_ownership=ownership)
            command.upgrade(cfg, "0013_outbox_delivery_lease")

        await connection.run_sync(legacy)
        await connection.execute(
            insert(User).values(
                id=owner,
                email="source-upgrade@haruka.example.test",
                email_normalized="source-upgrade@haruka.example.test",
                password_hash="synthetic-test-hash",  # noqa: S106 - inert legacy row, never authenticates.
                status="active",
            )
        )
        await connection.execute(insert(Library).values(id=library, owner_user_id=owner))
        await connection.execute(
            insert(Material).values(
                id=material,
                owner_user_id=owner,
                library_id=library,
                material_type="novel",
                language="ja",
                title="Legacy source",
                source_status="published",
            )
        )
        await connection.execute(
            insert(UploadIntent).values(
                id=upload,
                user_id=owner,
                purpose="avatar",
                target_kind="user_extension",
                target_resource_id=owner,
                declared_format="jpeg",
                expected_size_bytes=3,
                expected_sha256=b"a" * 32,
                status="completed",
                file_object_id=asset,
                expires_at=now + timedelta(minutes=5),
            )
        )
        await connection.execute(
            insert(FileObject).values(
                id=asset,
                user_id=owner,
                upload_intent_id=upload,
                purpose="avatar",
                media_type="image/jpeg",
                format_code="jpeg",
                size_bytes=3,
                sha256=b"b" * 32,
                validation_profile="avatar-image-v1",
                processor_version="avatar-jpeg-square-v1",
                validated_at=now,
                pixel_width=1,
                pixel_height=1,
                retention_state="referenced",
                content=b"abc",
            )
        )
        await connection.execute(
            insert(MaterialRevision).values(
                id=legacy_revision,
                owner_user_id=owner,
                library_id=library,
                material_id=material,
                revision_number=1,
                status="published",
                text_protocol_version="canonical-text-v1",
                structure_status="readable",
                input_delete_generation=0,
                published_at=now,
            )
        )
        await connection.execute(
            update(Material)
            .where(Material.id == material)
            .values(current_revision_id=legacy_revision)
        )
        await connection.commit()
    result = await upgrade_database(target, MIGRATIONS)
    assert result.compatible and result.current_revision == "0014_material_sources"
    async with locked_connection(target) as (connection, _ownership):
        await connection.run_sync(check_schema_connection, target.database_schema)
        for table_name in (
            "material_imports",
            "material_source_assets",
            "material_import_issues",
            "user_storage_states",
            "user_storage_reservations",
            "user_notifications",
        ):
            for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE"):
                assert (
                    await connection.scalar(
                        text(
                            "SELECT has_table_privilege('haruka_test_runtime', :table, :privilege)"
                        ),
                        {"table": f"{target.database_schema}.{table_name}", "privilege": privilege},
                    )
                    is True
                )
        assert (
            await connection.scalar(
                text(
                    "SELECT has_table_privilege('haruka_test_runtime', :table, 'SELECT,INSERT,UPDATE,DELETE')"
                ),
                {"table": f"{target.database_schema}.{table_name}"},
            )
            is True
        )
        assert (
            await connection.scalar(
                text("SELECT has_table_privilege('haruka_test_runtime', :table, 'UPDATE')"),
                {"table": f"{target.database_schema}.admin_audit_events"},
            )
            is False
        )
        assert (
            await connection.scalar(
                text("SELECT has_table_privilege('haruka_test_runtime', :table, 'INSERT')"),
                {"table": f"{target.database_schema}.alembic_version"},
            )
            is False
        )

        def physical(conn: Connection) -> tuple[int, bool]:
            reflection = inspect(conn)
            return len(reflection.get_table_names()), all(
                not reflection.get_foreign_keys(name) for name in reflection.get_table_names()
            )

        assert await connection.run_sync(physical) == (51, True)
        assert (
            await connection.scalar(select(FileObject.content).where(FileObject.id == asset))
            == b"abc"
        )
        row = (
            await connection.execute(
                select(
                    Material.title,
                    Material.current_revision_id,
                    Material.primary_file_object_id,
                    Material.source_status,
                ).where(Material.id == material)
            )
        ).one()
        assert tuple(row) == ("Legacy source", legacy_revision, None, "published")
        assert (
            await connection.scalar(
                select(Library.notification_sequence).where(Library.id == library)
            )
            == 0
        )
        await connection.commit()
        job_values: dict[str, object] = {
            "id": uuid4(),
            "owner_user_id": owner,
            "actor_user_id": owner,
            "session_id": uuid4(),
            "transport": "native",
            "audience": "client",
            "operation_id": uuid4(),
            "request_id": uuid4(),
            "input_refs": {},
            "input_digest": b"j" * 32,
            "idempotency_digest": b"i" * 32,
            "operation_kind": "material_import",
            "credential_id": None,
            "run_id": None,
        }
        await connection.execute(insert(Job).values(**job_values))
        await connection.commit()
        assert (
            await connection.scalar(
                select(MaterialRevision.published_at).where(MaterialRevision.id == legacy_revision)
            )
            == now
        )
        building_id = uuid4()
        await connection.execute(
            insert(MaterialRevision).values(
                id=building_id,
                owner_user_id=owner,
                library_id=library,
                material_id=material,
                revision_number=2,
                status="building",
                material_type="novel",
                origin_job_id=job_values["id"],
                processor_version="material-source-v1",
                text_protocol_version="canonical-text-v1",
                structure_status="building",
                input_delete_generation=0,
                published_at=None,
            )
        )
        assert (
            await connection.scalar(
                select(MaterialRevision.published_at).where(MaterialRevision.id == building_id)
            )
            is None
        )
        assert (
            await connection.scalar(
                select(Material.current_revision_id).where(Material.id == material)
            )
            == legacy_revision
        )
        await connection.commit()
        for patch in (
            {"operation_kind": "credential_test"},
            {"operation_kind": "unknown"},
            {"credential_id": uuid4()},
            {"run_id": uuid4()},
        ):
            with pytest.raises(IntegrityError):
                async with connection.begin_nested():
                    await connection.execute(
                        insert(Job).values(
                            **(
                                job_values
                                | patch
                                | {"id": uuid4(), "idempotency_digest": uuid4().bytes}
                            )
                        )
                    )
        await connection.commit()
        intent_values = {
            "id": uuid4(),
            "owner_user_id": owner,
            "library_id": library,
            "material_type": "exam",
            "target_language": "en",
            "schema_version": 1,
            "requested_stages": {"extract": True, "analyze": False},
            "status": "verifying",
            "idempotency_record_id": uuid4(),
            "expires_at": now + timedelta(minutes=5),
            "primary_upload_intent_id": None,
            "reused_material_id": material,
            "reused_file_object_id": asset,
        }
        await connection.execute(insert(MaterialImport).values(**intent_values))
        await connection.commit()
        for patch in (
            {"primary_upload_intent_id": uuid4()},
            {"reused_file_object_id": None},
            {"status": "accepted"},
            {"requested_stages": {"extract": True, "analyze": True}},
        ):
            with pytest.raises(IntegrityError):
                async with connection.begin_nested():
                    await connection.execute(
                        insert(MaterialImport).values(
                            **(
                                intent_values
                                | patch
                                | {"id": uuid4(), "idempotency_record_id": uuid4()}
                            )
                        )
                    )
        await connection.commit()
        with pytest.raises(IntegrityError):
            async with connection.begin_nested():
                await connection.execute(
                    insert(UserStorageState).values(user_id=owner, used_bytes=-1, reserved_bytes=0)
                )
        await connection.rollback()
