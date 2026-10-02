"""EXPLAIN of the actual authorized history-list SQL on realistic isolated PG data."""

import asyncio
import json
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import cast
from uuid import UUID

import pytest
from cryptography.fernet import Fernet
from pydantic import SecretStr
from sqlalchemy import Connection, event
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.bootstrap import Runtime
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import AuthPolicy
from app.models.model_tasks import ProviderCredential
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


async def test_actual_credential_list_uses_owner_index_and_bounded_topn(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    database = runtime.resources.database
    async with database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for client, headers in _owner(
        runtime, maintenance, f"plan-a-{run_id}@haruka.example.test"
    ):
        async for other, other_headers in _owner(
            runtime, maintenance, f"plan-b-{run_id}@haruka.example.test"
        ):
            first = await client.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-plan-a"},
                headers=headers,
            )
            second = await other.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-plan-b"},
                headers=other_headers,
            )
            assert first.status_code == second.status_code == 201
            first_id = UUID(first.json()["data"]["id"])
            second_id = UUID(second.json()["data"]["id"])
            async with database.sessions() as session:
                a = await session.get(ProviderCredential, first_id)
                b = await session.get(ProviderCredential, second_id)
                assert a is not None and b is not None
                owner_a, owner_b = a.owner_user_id, b.owner_user_id
            engine = create_maintenance_engine(maintenance)
            try:
                sessions = async_sessionmaker(engine, expire_on_commit=False)
                old = datetime.now(UTC) - timedelta(days=60)
                async with sessions() as session, session.begin():
                    for owner, count in [(owner_a, 1200), (owner_b, 18000)]:
                        session.add_all(
                            [
                                ProviderCredential(
                                    owner_user_id=owner,
                                    provider="openrouter",
                                    label=f"Revoked {index}",
                                    encrypted_key=None,
                                    encryption_key_version="v1",
                                    masked_key="****",
                                    credential_version=2,
                                    revision=2,
                                    status="revoked",
                                    revoked_at=old,
                                    created_at=old + timedelta(seconds=index),
                                    updated_at=old,
                                )
                                for index in range(count)
                            ]
                        )
                async with engine.begin() as connection:
                    await connection.exec_driver_sql("ANALYZE user_provider_credentials")
                captured: list[tuple[str, object]] = []

                def observe(
                    _conn: Connection,
                    _cursor: object,
                    statement: str,
                    parameters: object,
                    _context: object,
                    _many: bool,
                    captured: list[tuple[str, object]] = captured,
                ) -> None:
                    if (
                        statement.startswith("SELECT")
                        and "user_provider_credentials" in statement
                        and "ORDER BY" in statement
                        and "LIMIT" in statement
                    ):
                        captured.append((statement, parameters))

                event.listen(database.engine.sync_engine, "before_cursor_execute", observe)
                try:
                    response = await client.get("/api/v1/provider-credentials")
                finally:
                    event.remove(database.engine.sync_engine, "before_cursor_execute", observe)
                assert response.status_code == 200
                items = response.json()["data"]["items"]
                assert len(items) == 100 and items[0]["id"] == str(first_id)
                assert all(row["id"] != str(second_id) for row in items)
                assert len(captured) == 1
                statement, parameters = captured[0]
                async with database.engine.connect() as connection:
                    plan = await connection.exec_driver_sql(
                        "EXPLAIN (ANALYZE, FORMAT JSON) " + statement,
                        cast(tuple[object, ...], parameters),
                    )
                    document = plan.scalar_one()
                    if isinstance(document, str):
                        document = json.loads(document)
                root = document[0]["Plan"]
                nodes: list[dict[str, object]] = []

                def flatten(node: dict[str, object], nodes: list[dict[str, object]]) -> None:
                    nodes.append(
                        {
                            k: node[k]
                            for k in [
                                "Node Type",
                                "Index Name",
                                "Actual Rows",
                                "Sort Method",
                                "Sort Space Type",
                            ]
                            if k in node
                        }
                    )
                    for child in cast(list[dict[str, object]], node.get("Plans", [])):
                        flatten(child, nodes)

                flatten(root, nodes)
                assert root["Node Type"] == "Limit" and root["Actual Rows"] == 100
                assert any(
                    n.get("Index Name") == "ix_user_provider_credentials_user_state" for n in nodes
                )
                assert any(n.get("Sort Method") == "top-N heapsort" for n in nodes)
                target = os.environ.get("HARUKA_QUERY_PLAN_REPORT")
                if target is not None:
                    await asyncio.to_thread(
                        Path(target).write_text,
                        json.dumps(
                            {
                                "scope": "actual authorized owner query; revoked-history fixtures are not successful business credentials",
                                "run_id": run_id,
                                "own_revoked": 1200,
                                "other_revoked": 18000,
                                "nodes": nodes,
                            },
                            indent=2,
                        )
                        + "\n",
                        encoding="utf-8",
                    )
            finally:
                await engine.dispose()
