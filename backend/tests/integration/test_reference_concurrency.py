"""Formal collection create versus controlled maintenance tombstone parent-lock protocol.
This is not an implemented user material-delete/merge/GC workflow.
"""

import asyncio
from collections.abc import AsyncGenerator
from contextlib import aclosing
from datetime import UTC, datetime
from typing import cast
from uuid import UUID

import httpx2 as httpx
import pytest
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.bootstrap import Runtime
from app.domain.scope import ScopeContext
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import AuthPolicy, AuthSession, Library
from app.models.learning_reference import CollectionItem, Material
from app.schemas.learning_reference import CollectionCreate, CollectionRead
from app.services import learning_reference
from app.services.auth_context import verify_scope_in_transaction
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]
from tests.support.bound_client import BoundAsyncClient
from tests.support.learning_reference_scenarios import prepare_learning_source

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


@pytest.mark.parametrize("delete_first", [True, False])
async def test_collection_parent_lock_orders_against_maintenance_tombstone(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    delete_first: bool,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    sessions = runtime.resources.database.sessions
    async with sessions() as setup, setup.begin():
        policy = await setup.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"reference-race-{run_id}@haruka.example.test"
    async with aclosing(
        cast(
            AsyncGenerator[tuple[BoundAsyncClient, dict[str, str]]],
            _owner(runtime, maintenance, email),
        )
    ) as owner_iterator:
        client, headers = await anext(owner_iterator)
        engine = create_maintenance_engine(maintenance)
        try:
            async with engine.begin() as connection:
                assert maintenance.test_schema == f"haruka_migration_test_{run_id}"
                await connection.exec_driver_sql(
                    f"COMMENT ON SCHEMA {maintenance.test_schema} IS 'haruka-b1-run:{run_id}'"
                )
            source = await prepare_learning_source(
                maintenance, owner_email=email, instance_id=runtime.settings.instance_id
            )
            async with sessions() as setup:
                auth = await setup.scalar(
                    select(AuthSession).where(
                        AuthSession.user_id == source.owner_user_id,
                        AuthSession.revoked_at.is_(None),
                    )
                )
                assert auth is not None
                scope = await verify_scope_in_transaction(
                    setup,
                    user_id=source.owner_user_id,
                    session_id=auth.id,
                    audience="client",
                    transport="web",
                )
            assert scope.user_id == source.owner_user_id
            entered = asyncio.Event()
            release = asyncio.Event()
            holder_pid: list[int] = []
            original = learning_reference._create_collection_in_transaction  # pyright: ignore[reportPrivateUsage]

            async def paused(
                session: AsyncSession,
                scope: ScopeContext,
                *,
                instance_id: str,
                payload: CollectionCreate,
                key: str,
                key_digest: bytes,
                operation_id: UUID,
            ) -> tuple[CollectionRead, int, str]:
                result = await original(
                    session,
                    scope,
                    instance_id=instance_id,
                    payload=payload,
                    key=key,
                    key_digest=key_digest,
                    operation_id=operation_id,
                )
                if not delete_first:
                    pid = await session.scalar(text("SELECT pg_backend_pid()"))
                    assert isinstance(pid, int)
                    holder_pid.append(pid)
                    entered.set()
                    await release.wait()
                return result

            monkeypatch.setattr(learning_reference, "_create_collection_in_transaction", paused)

            async def maintenance_delete() -> None:
                factory = async_sessionmaker(engine, expire_on_commit=False)
                async with factory() as session, session.begin():
                    assert (
                        await session.execute(text("SELECT current_database(),current_user"))
                    ).one() == ("haruka_test", "haruka_test_maintenance")
                    library = await session.get(Library, source.library_id, with_for_update=True)
                    material = await session.get(Material, source.material_id, with_for_update=True)
                    assert (
                        library is not None
                        and material is not None
                        and library.owner_user_id == source.owner_user_id
                        and material.library_id == library.id
                    )
                    material.deleted_at = datetime.now(UTC)
                    material.delete_generation += 1
                    material.revision += 1
                    material.updated_at = datetime.now(UTC)
                    await session.flush()
                    if delete_first:
                        pid = await session.scalar(text("SELECT pg_backend_pid()"))
                        assert isinstance(pid, int)
                        holder_pid.append(pid)
                        entered.set()
                        await release.wait()

            async def create_reference() -> httpx.Response:
                return await client.post(
                    "/api/v1/collections",
                    json={"card_id": str(source.card_id), "card_revision": 1, "notebook_ids": []},
                    headers={**headers, "Idempotency-Key": "reference-race-" + run_id},
                )

            first = asyncio.create_task(
                maintenance_delete() if delete_first else create_reference()
            )
            await asyncio.wait_for(entered.wait(), 5)
            second = asyncio.create_task(
                create_reference() if delete_first else maintenance_delete()
            )
            try:
                async with sessions() as observer:
                    blocked = 0
                    for _ in range(100):
                        blocked = await observer.scalar(
                            text(
                                "SELECT count(*) FROM pg_stat_activity WHERE :pid=ANY(pg_blocking_pids(pid))"
                            ),
                            {"pid": holder_pid[0]},
                        )
                        if blocked:
                            break
                        await asyncio.sleep(0.02)
                    assert blocked and not second.done(), (
                        "opposite connection must wait on common parent lock"
                    )
            finally:
                release.set()
            first_result, second_result = await asyncio.wait_for(asyncio.gather(first, second), 5)
            created = second_result if delete_first else first_result
            assert isinstance(created, httpx.Response)
            assert created.status_code == (404 if delete_first else 201)
            async with sessions() as check:
                material = await check.get(Material, source.material_id)
                assert (
                    material is not None
                    and material.deleted_at is not None
                    and material.delete_generation == 1
                )
                assert await check.scalar(
                    select(func.count())
                    .select_from(CollectionItem)
                    .where(CollectionItem.owner_user_id == source.owner_user_id)
                ) == (0 if delete_first else 1)
            if not delete_first:
                retained = await client.get("/api/v1/collections")
                assert retained.status_code == 200
                assert [row["id"] for row in retained.json()["data"]] == [
                    created.json()["data"]["id"]
                ]
            repeated = await create_reference()
            assert repeated.status_code in {404, 409}
        finally:
            await engine.dispose()
