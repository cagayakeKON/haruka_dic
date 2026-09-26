"""current slice owner isolation and collection replay against a real isolated PostgreSQL schema."""

import asyncio
import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest
import pytest_asyncio
from pydantic import SecretStr
from sqlalchemy import delete, insert, select, text, update
from sqlalchemy.ext.asyncio import async_sessionmaker
from sqlalchemy.schema import CreateSchema, DropSchema

from app.adapters.database import Database
from app.contracts.errors import ErrorCode
from app.core.settings import CoreInfrastructureSettings, load_settings
from app.domain.errors import AppError
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models.authorization import Role, RolePermission, UserRole
from app.models.identity import Library, User
from app.models.identity_security import AuthSession
from app.models.learning_reference import Card, CollectionItem, IdempotencyRecord, Material
from app.schemas.learning_reference import (
    CollectionCreate,
    ExplanationResolveRequest,
    ResolveTarget,
    SourceSpan,
)
from app.services.auth_context import ScopeContext
from app.services.auth_crypto import hash_password
from app.services.initialization import apply_seed
from app.services.learning_reference import (
    create_collection,
    get_novel_chapter,
    list_collections,
    list_materials,
    resolve_explanations,
)
from tests.support.learning_reference_scenarios import (
    PreparedLearningSource,
    prepare_learning_source,
)

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "backend/alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[tuple[MaintenanceSettings, CoreInfrastructureSettings, str]]:
    if os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG") != "dev/.local/test-maintenance.env":
        pytest.fail("explicit isolated maintenance test configuration is required")
    source = load_maintenance_settings(ROOT / "dev/.local/test-maintenance.env")
    runtime_template = load_settings(ROOT / "dev/.local/test.env")
    assert runtime_template.database_url is not None and runtime_template.redis_url is not None
    run_id = uuid4().hex
    schema = f"haruka_migration_test_{run_id}"
    maintenance = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    runtime = CoreInfrastructureSettings(
        database_url=runtime_template.database_url,
        redis_url=runtime_template.redis_url,
        namespace=f"haruka-test-{run_id}",
        test_schema=schema,
    )
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert (
                await connection.execute(text("SELECT current_database(), current_user"))
            ).one() == ("haruka_test", "haruka_test_maintenance")
            await connection.execute(CreateSchema(schema))
            await connection.execute(
                text(f"COMMENT ON SCHEMA {schema} IS 'haruka-b1-run:{run_id}'")
            )
        await upgrade_database(maintenance, MIGRATIONS)
        await apply_seed(maintenance)
        yield maintenance, runtime, run_id
    finally:
        async with observer.begin() as connection:
            marker = await connection.scalar(
                text(
                    "SELECT obj_description(oid, 'pg_namespace') FROM pg_namespace WHERE nspname=:schema"
                ),
                {"schema": schema},
            )
            if marker != f"haruka-b1-run:{run_id}":
                raise AssertionError("refusing to drop unowned learning test schema")
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


async def _client(settings: MaintenanceSettings, email: str) -> tuple[ScopeContext, UUID]:
    engine = create_maintenance_engine(settings)
    try:
        sessions = async_sessionmaker(engine, expire_on_commit=False)
        async with sessions() as session, session.begin():
            role = await session.scalar(select(Role).where(Role.code == "learner"))
            assert role is not None
            user_id, session_id, library_id = uuid4(), uuid4(), uuid4()
            now = datetime.now(UTC)
            session.add(
                User(
                    id=user_id,
                    email=email,
                    email_normalized=email,
                    password_hash=await hash_password(SecretStr(uuid4().hex)),
                    status="active",
                    authz_version=1,
                    password_version=1,
                    security_epoch=0,
                    revision=1,
                    email_verified_at=now,
                    client_security_epoch=0,
                    admin_security_epoch=0,
                )
            )
            session.add(Library(id=library_id, owner_user_id=user_id))
            session.add(UserRole(id=uuid4(), user_id=user_id, role_id=role.id))
            session.add(
                AuthSession(
                    id=session_id,
                    user_id=user_id,
                    audience="client",
                    transport="native",
                    platform="windows",
                    absolute_expires_at=now + timedelta(days=1),
                    revoked_at=None,
                    revoke_reason_code=None,
                    security_epoch=0,
                    audience_security_epoch=0,
                    reauthenticated_at=now,
                    device_summary=None,
                    last_seen_at=now,
                )
            )
            await session.flush()
        return ScopeContext(
            user_id=user_id,
            session_id=session_id,
            audience="client",
            transport="native",
            user_authz_version=1,
            policy_authz_version=1,
            security_epoch=0,
            absolute_expires_at=now + timedelta(days=1),
        ), library_id
    finally:
        await engine.dispose()


async def test_owned_source_resolve_collection_replay_and_revocation(
    target: tuple[MaintenanceSettings, CoreInfrastructureSettings, str],
) -> None:
    maintenance, runtime_settings, run_id = target
    instance_id = f"haruka-test-{run_id}"
    email_a = f"alice-{run_id}@haruka.example.test"
    email_b = f"bob-{run_id}@haruka.example.test"
    scope_a, library_a = await _client(maintenance, email_a)
    scope_b, _ = await _client(maintenance, email_b)
    source_a: PreparedLearningSource = await prepare_learning_source(
        maintenance, owner_email=email_a, instance_id=instance_id
    )
    source_a2: PreparedLearningSource = await prepare_learning_source(
        maintenance, owner_email=email_a, instance_id=instance_id
    )
    source_b: PreparedLearningSource = await prepare_learning_source(
        maintenance, owner_email=email_b, instance_id=instance_id
    )
    assert source_a.library_id == library_a
    database = Database(runtime_settings)
    try:
        await database.check()
        async with database.sessions() as session:
            assert (
                await session.scalar(
                    select(CollectionItem.id).where(CollectionItem.owner_user_id == scope_a.user_id)
                )
                is None
            )
            materials_a, _ = await list_materials(session, scope_a, limit=20, cursor=None)
            materials_b, _ = await list_materials(session, scope_b, limit=20, cursor=None)
            assert {item.id for item in materials_a} == {
                source_a.material_id,
                source_a2.material_id,
            }
            assert [item.id for item in materials_b] == [source_b.material_id]
            first_page, cursor = await list_materials(session, scope_a, limit=1, cursor=None)
            assert cursor is not None and len(first_page) == 1
            second_page, terminal = await list_materials(session, scope_a, limit=1, cursor=cursor)
            assert terminal is None and {first_page[0].id, second_page[0].id} == {
                source_a.material_id,
                source_a2.material_id,
            }
            with pytest.raises(AppError) as foreign_cursor:
                await list_materials(session, scope_b, limit=1, cursor=cursor)
            assert foreign_cursor.value.code == ErrorCode.RESOURCE_NOT_FOUND
            chapter = await get_novel_chapter(
                session,
                scope_a,
                instance_id=instance_id,
                material_id=source_a.material_id,
                revision_id=source_a.revision_id,
                node_id=source_a.chapter_id,
            )
            assert len(chapter.blocks) == 1
            block = chapter.blocks[0]
            start = block.canonical_text.index("空")
            locator = block.source_locator.model_copy(
                update={
                    "quote": "空",
                    "prefix": block.canonical_text[:start],
                    "suffix": block.canonical_text[start + 1 :],
                    "spans": [SourceSpan(block_id=block.id, start=start, end=start + 1)],
                }
            )
            resolved = await resolve_explanations(
                session,
                scope_a,
                instance_id=instance_id,
                payload=ExplanationResolveRequest(
                    targets=[
                        ResolveTarget(
                            source_locator=locator,
                            target_language="ja",
                            explanation_language="zh-CN",
                        )
                    ]
                ),
            )
            assert resolved.results[0].state == "found"
            shortened = locator.model_copy(
                update={"prefix": "い", "suffix": "を", "source_title": None, "node_title": None}
            )
            shortened_result = await resolve_explanations(
                session,
                scope_a,
                instance_id=instance_id,
                payload=ExplanationResolveRequest(
                    targets=[
                        ResolveTarget(
                            source_locator=shortened,
                            target_language="ja",
                            explanation_language="zh-CN",
                        )
                    ]
                ),
            )
            assert shortened_result.results[0].state == "found"
            for invalid in (
                locator.model_copy(update={"quote": "空空"}),
                locator.model_copy(
                    update={
                        "spans": [SourceSpan(block_id=block.id, start=start + 1, end=start + 2)]
                    }
                ),
            ):
                with pytest.raises(AppError) as invalid_selection:
                    await resolve_explanations(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=ExplanationResolveRequest(
                            targets=[
                                ResolveTarget(
                                    source_locator=invalid,
                                    target_language="ja",
                                    explanation_language="zh-CN",
                                )
                            ]
                        ),
                    )
                assert invalid_selection.value.code == ErrorCode.RESOURCE_NOT_FOUND
            with pytest.raises(AppError) as foreign:
                await get_novel_chapter(
                    session,
                    scope_b,
                    instance_id=instance_id,
                    material_id=source_a.material_id,
                    revision_id=source_a.revision_id,
                    node_id=source_a.chapter_id,
                )
            assert foreign.value.code == ErrorCode.RESOURCE_NOT_FOUND
        payload = CollectionCreate(card_id=source_a.card_id, card_revision=1, notebook_ids=[])
        async with database.sessions() as session:
            item, status = await create_collection(
                session,
                scope_a,
                instance_id=instance_id,
                payload=payload,
                key="first",
                key_digest=b"a" * 32,
                operation_id=uuid4(),
            )
            assert status == 201
            first_id = item.id
        async with database.sessions() as session:
            replay, status = await create_collection(
                session,
                scope_a,
                instance_id=instance_id,
                payload=payload,
                key="first",
                key_digest=b"a" * 32,
                operation_id=uuid4(),
            )
            assert status == 201 and replay.id == first_id
        async with database.sessions() as session:
            existing, status = await create_collection(
                session,
                scope_a,
                instance_id=instance_id,
                payload=payload,
                key="second",
                key_digest=b"b" * 32,
                operation_id=uuid4(),
            )
            assert status == 200 and existing.id == first_id
        parallel_payload = CollectionCreate(
            card_id=source_a2.card_id, card_revision=1, notebook_ids=[]
        )

        async def parallel_create() -> tuple[UUID, int]:
            async with database.sessions() as session:
                created, created_status = await create_collection(
                    session,
                    scope_a,
                    instance_id=instance_id,
                    payload=parallel_payload,
                    key="parallel",
                    key_digest=b"p" * 32,
                    operation_id=uuid4(),
                )
                return created.id, created_status

        parallel_results = await asyncio.gather(parallel_create(), parallel_create())
        assert parallel_results[0] == parallel_results[1]
        assert parallel_results[0][1] == 201
        parallel_id = parallel_results[0][0]
        async with database.sessions() as session:
            total_a = (
                await session.scalars(
                    select(CollectionItem.id).where(CollectionItem.owner_user_id == scope_a.user_id)
                )
            ).all()
            assert set(total_a) == {first_id, parallel_id}
            page, collection_cursor = await list_collections(session, scope_a, limit=1, cursor=None)
            assert len(page) == 1 and collection_cursor is not None
            following, terminal = await list_collections(
                session, scope_a, limit=1, cursor=collection_cursor
            )
            assert terminal is None and {page[0].id, following[0].id} == {first_id, parallel_id}
            with pytest.raises(AppError) as foreign_collection_cursor:
                await list_collections(session, scope_b, limit=1, cursor=collection_cursor)
            assert foreign_collection_cursor.value.code == ErrorCode.RESOURCE_NOT_FOUND
        async with database.sessions() as session:
            with pytest.raises(AppError) as conflict:
                await create_collection(
                    session,
                    scope_a,
                    instance_id=instance_id,
                    payload=CollectionCreate(
                        card_id=source_a.card_id,
                        card_revision=1,
                        confirmed_target_language="ja",
                        notebook_ids=[],
                    ),
                    key="first",
                    key_digest=b"a" * 32,
                    operation_id=uuid4(),
                )
            assert conflict.value.code == ErrorCode.IDEMPOTENCY_CONFLICT
        async with database.sessions() as session:
            with pytest.raises(AppError) as foreign_card:
                await create_collection(
                    session,
                    scope_b,
                    instance_id=instance_id,
                    payload=payload,
                    key="foreign",
                    key_digest=b"c" * 32,
                    operation_id=uuid4(),
                )
            assert foreign_card.value.code == ErrorCode.RESOURCE_NOT_FOUND
        maintenance_engine = create_maintenance_engine(maintenance)
        try:
            async with maintenance_engine.begin() as connection:
                b_refs = await connection.scalar(
                    select(Card.source_refs).where(Card.id == source_b.card_id)
                )
                assert isinstance(b_refs, list)
                await connection.execute(
                    update(Card)
                    .where(Card.id == source_a.card_id)
                    .values(source_refs=[locator.model_dump(mode="json"), *b_refs])
                )
            async with database.sessions() as session:
                with pytest.raises(AppError) as mixed_source:
                    await resolve_explanations(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=ExplanationResolveRequest(
                            targets=[
                                ResolveTarget(
                                    source_locator=locator,
                                    target_language="ja",
                                    explanation_language="zh-CN",
                                )
                            ]
                        ),
                    )
                assert mixed_source.value.code == ErrorCode.RESOURCE_NOT_FOUND
            async with maintenance_engine.begin() as connection:
                await connection.execute(
                    update(Card)
                    .where(Card.id == source_a.card_id)
                    .values(source_refs=[locator.model_dump(mode="json")])
                )
                await connection.execute(
                    update(IdempotencyRecord)
                    .where(
                        IdempotencyRecord.owner_user_id == scope_a.user_id,
                        IdempotencyRecord.key_digest == b"a" * 32,
                    )
                    .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
                )
            async with database.sessions() as session:
                expired_replay, expired_status = await create_collection(
                    session,
                    scope_a,
                    instance_id=instance_id,
                    payload=payload,
                    key="first",
                    key_digest=b"a" * 32,
                    operation_id=uuid4(),
                )
                assert expired_status == 200 and expired_replay.id == first_id
            deny_role_id = uuid4()
            async with maintenance_engine.begin() as connection:
                await connection.execute(
                    insert(Role).values(
                        id=deny_role_id,
                        code=f"deny_{run_id[:12]}",
                        name="test deny",
                        protected=False,
                        enabled=True,
                        revision=1,
                    )
                )
                await connection.execute(
                    insert(RolePermission).values(
                        id=uuid4(),
                        role_id=deny_role_id,
                        permission_code="client.collection.create",
                        effect="deny",
                        data_scope="self",
                    )
                )
                await connection.execute(
                    insert(UserRole).values(
                        id=uuid4(), user_id=scope_a.user_id, role_id=deny_role_id
                    )
                )
            async with database.sessions() as session:
                with pytest.raises(AppError) as explicit_deny:
                    await create_collection(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=payload,
                        key="first",
                        key_digest=b"a" * 32,
                        operation_id=uuid4(),
                    )
                assert explicit_deny.value.code == ErrorCode.PERMISSION_DENIED
            async with maintenance_engine.begin() as connection:
                await connection.execute(
                    delete(UserRole).where(
                        UserRole.user_id == scope_a.user_id, UserRole.role_id == deny_role_id
                    )
                )
                await connection.execute(
                    update(CollectionItem)
                    .where(CollectionItem.id == first_id)
                    .values(deleted_at=datetime.now(UTC), delete_generation=1)
                )
            async with database.sessions() as session:
                with pytest.raises(AppError) as no_revive:
                    await create_collection(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=payload,
                        key="new-after-item-delete",
                        key_digest=b"i" * 32,
                        operation_id=uuid4(),
                    )
                assert no_revive.value.code == ErrorCode.STATE_CONFLICT
            async with database.sessions() as session:
                with pytest.raises(AppError) as no_replay_revive:
                    await create_collection(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=payload,
                        key="first",
                        key_digest=b"a" * 32,
                        operation_id=uuid4(),
                    )
                assert no_replay_revive.value.code == ErrorCode.STATE_CONFLICT
            async with maintenance_engine.begin() as connection:
                await connection.execute(
                    update(Material)
                    .where(Material.id == source_a.material_id)
                    .values(deleted_at=datetime.now(UTC), delete_generation=1)
                )
                await connection.execute(
                    update(Material)
                    .where(Material.id == source_a2.material_id)
                    .values(current_revision_id=uuid4())
                )
            async with database.sessions() as session:
                with pytest.raises(AppError) as tombstone:
                    await create_collection(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=payload,
                        key="after-delete",
                        key_digest=b"d" * 32,
                        operation_id=uuid4(),
                    )
                assert tombstone.value.code == ErrorCode.RESOURCE_NOT_FOUND
            async with database.sessions() as session:
                with pytest.raises(AppError) as changed_version:
                    await create_collection(
                        session,
                        scope_a,
                        instance_id=instance_id,
                        payload=parallel_payload,
                        key="after-version",
                        key_digest=b"v" * 32,
                        operation_id=uuid4(),
                    )
                assert changed_version.value.code == ErrorCode.RESOURCE_NOT_FOUND
            async with database.sessions() as session:
                own_items, _ = await list_collections(session, scope_a, limit=20, cursor=None)
                assert [item.id for item in own_items] == [parallel_id]
            async with maintenance_engine.begin() as connection:
                await connection.execute(
                    delete(UserRole).where(UserRole.user_id == scope_a.user_id)
                )
        finally:
            await maintenance_engine.dispose()
        async with database.sessions() as session:
            with pytest.raises(AppError) as revoked:
                await create_collection(
                    session,
                    scope_a,
                    instance_id=instance_id,
                    payload=payload,
                    key="first",
                    key_digest=b"a" * 32,
                    operation_id=uuid4(),
                )
            assert revoked.value.code == ErrorCode.PERMISSION_DENIED
    finally:
        await database.aclose()
