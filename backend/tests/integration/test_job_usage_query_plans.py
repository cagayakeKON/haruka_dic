"""Authorized history reads and real PG plans; fixtures never execute a supplier."""

import asyncio
import json
import os
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from pathlib import Path
from typing import cast
from uuid import UUID, uuid4

import pytest
from sqlalchemy import Connection, event, select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.bootstrap import Runtime
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import AuthPolicy, AuthSession, User
from app.models.model_tasks import AiRun, ExternalCallAttempt, Job, ProviderCredential
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


def _safe_plan(document: list[dict[str, object]]) -> dict[str, object]:
    """Exclude expressions and bind values, including owner IDs, from artifacts."""
    keys = (
        "Node Type",
        "Relation Name",
        "Index Name",
        "Actual Rows",
        "Actual Loops",
        "Actual Total Time",
        "Plan Rows",
        "Shared Hit Blocks",
        "Shared Read Blocks",
        "Sort Method",
        "Sort Space Type",
        "Rows Removed by Filter",
    )

    def project(node: dict[str, object]) -> dict[str, object]:
        return {key: node[key] for key in keys if key in node} | {
            "Plans": [
                project(child) for child in cast(list[dict[str, object]], node.get("Plans", []))
            ]
        }

    return {
        "Plan": project(cast(dict[str, object], document[0]["Plan"])),
        "Planning Time": document[0]["Planning Time"],
        "Execution Time": document[0]["Execution Time"],
    }


async def test_authorized_job_and_usage_history_filters_limits_and_pg_plans(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    database = runtime.resources.database
    async with database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email_a = f"history-a-{run_id}@haruka.example.test"
    email_b = f"history-b-{run_id}@haruka.example.test"
    async for client, _headers in _owner(runtime, maintenance, email_a):
        async for other, _other_headers in _owner(runtime, maintenance, email_b):
            engine = create_maintenance_engine(maintenance)
            try:
                sessions = async_sessionmaker(engine, expire_on_commit=False)
                # The after-as_of sample is still genuine historical fixture data.
                as_of = datetime.now(UTC).replace(microsecond=0) - timedelta(days=2)
                expected: list[list[str]] = []
                owners: list[UUID] = []
                async with sessions() as session, session.begin():
                    for email, count in ((email_a, 1200), (email_b, 6000)):
                        user = await session.scalar(
                            select(User).where(User.email_normalized == email)
                        )
                        assert user is not None
                        auth = await session.scalar(
                            select(AuthSession).where(AuthSession.user_id == user.id)
                        )
                        assert auth is not None
                        owners.append(user.id)
                        credential = ProviderCredential(
                            id=uuid4(),
                            owner_user_id=user.id,
                            provider="openrouter",
                            label="Revoked historical fixture",
                            encrypted_key=None,
                            encryption_key_version="fixture",
                            masked_key="****",
                            credential_version=2,
                            revision=2,
                            status="revoked",
                            revoked_at=as_of,
                        )
                        session.add(credential)
                        ids: list[str] = []
                        for index in range(count):
                            job_id, ai_run_id = uuid4(), uuid4()
                            ids.append(str(job_id))
                            created = as_of - timedelta(seconds=count - index)
                            started = as_of + timedelta(days=(-40, -5, -10, 1)[index % 4])
                            model = "historical-text" if index % 4 != 2 else "other-text"
                            session.add_all(
                                [
                                    Job(
                                        id=job_id,
                                        owner_user_id=user.id,
                                        actor_user_id=user.id,
                                        session_id=auth.id,
                                        transport="web",
                                        audience="client",
                                        credential_id=credential.id,
                                        run_id=ai_run_id,
                                        operation_kind="model.test",
                                        operation_id=uuid4(),
                                        request_id=uuid4(),
                                        input_refs={},
                                        input_digest=b"historical",
                                        idempotency_digest=index.to_bytes(8, "big"),
                                        state="failed",
                                        created_at=created,
                                        updated_at=created,
                                        finished_at=created,
                                    ),
                                    AiRun(
                                        id=ai_run_id,
                                        owner_user_id=user.id,
                                        job_id=job_id,
                                        credential_id=credential.id,
                                        credential_version=2,
                                        provider="openrouter",
                                        model_id=model,
                                        capability="text",
                                        state="failed",
                                        generation=1,
                                        generation_config={},
                                        finished_at=created,
                                    ),
                                    ExternalCallAttempt(
                                        owner_user_id=user.id,
                                        job_id=job_id,
                                        ai_run_id=ai_run_id,
                                        credential_id=credential.id,
                                        credential_version=2,
                                        provider="openrouter",
                                        model_id=model,
                                        capability="text",
                                        operation_kind="model.test",
                                        attempt_no=1,
                                        status="failed",
                                        usage_status="partial",
                                        simulated=True,
                                        usage={},
                                        input_tokens=7 if email == email_a else 13,
                                        aggregation_revision=1,
                                        started_at=started,
                                    ),
                                ]
                            )
                        expected.append(list(reversed(ids[-100:])))
                async with engine.begin() as connection:
                    await connection.exec_driver_sql("ANALYZE jobs")
                    await connection.exec_driver_sql("ANALYZE external_call_attempts")
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
                    if statement.startswith("SELECT") and (
                        "FROM jobs" in statement or "FROM external_call_attempts" in statement
                    ):
                        captured.append((statement, parameters))

                event.listen(database.engine.sync_engine, "before_cursor_execute", observe)
                try:
                    jobs_a = await client.get("/api/v1/jobs")
                    jobs_b = await other.get("/api/v1/jobs")
                    default = await client.get(
                        "/api/v1/users/me/model-usage", params={"until": as_of.isoformat()}
                    )
                    filters = {
                        "until": as_of.isoformat(),
                        "provider": "openrouter",
                        "model_id": "historical-text",
                        "capability": "text",
                        "operation_kind": "model.test",
                    }
                    filtered = await client.get("/api/v1/users/me/model-usage", params=filters)
                    foreign = await other.get("/api/v1/users/me/model-usage", params=filters)
                    narrower = await client.get(
                        "/api/v1/users/me/model-usage",
                        params={**filters, "since": (as_of - timedelta(days=3)).isoformat()},
                    )
                finally:
                    event.remove(database.engine.sync_engine, "before_cursor_execute", observe)
                assert all(
                    r.status_code == 200
                    for r in (jobs_a, jobs_b, default, filtered, foreign, narrower)
                )
                assert [item["id"] for item in jobs_a.json()["data"]["items"]] == expected[0]
                assert [item["id"] for item in jobs_b.json()["data"]["items"]] == expected[1]
                assert set(expected[0]).isdisjoint(expected[1])
                assert len(jobs_a.json()["data"]["items"]) == 100
                assert sum(g["attempt_count"] for g in default.json()["data"]["groups"]) == 600
                for response, count, tokens in ((filtered, 300, 7), (foreign, 1500, 13)):
                    data = response.json()["data"]
                    assert data["aggregation_revision"] == count
                    assert len(data["groups"]) == 1
                    group = data["groups"][0]
                    assert group["attempt_count"] == group["failed_count"] == count
                    assert group["succeeded_count"] == 0 and group["simulated"] is True
                    assert group["metrics"]["input_tokens"]["known_sum"] == count * tokens
                    assert group["metrics"]["output_tokens"]["known_sum"] is None
                    assert group["metrics"]["output_tokens"]["unknown_attempt_count"] == count
                assert narrower.json()["data"]["groups"] == []
                assert len(captured) == 6
                plans: list[dict[str, object]] = []
                for index, (statement, parameters) in enumerate(captured):
                    values = cast(tuple[object, ...], parameters)
                    assert owners[1 if index in (1, 4) else 0] in values
                    if index < 2:
                        assert "ORDER BY jobs.created_at DESC" in statement
                        assert "LIMIT" in statement and 100 in values
                    else:
                        assert as_of in values
                        assert (as_of - timedelta(days=3 if index == 5 else 30)) in values
                        assert "GROUP BY" in statement
                        if index >= 3:
                            assert all(
                                v in values
                                for v in ("openrouter", "historical-text", "text", "model.test")
                            )
                    async with database.engine.connect() as connection:
                        result = await connection.exec_driver_sql(
                            "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + statement, values
                        )
                        document = result.scalar_one()
                        if isinstance(document, str):
                            document = json.loads(document)
                    plan = _safe_plan(document)
                    root = cast(dict[str, object], plan["Plan"])
                    assert root["Actual Rows"] == (
                        100 if index < 2 else 2 if index == 2 else 0 if index == 5 else 1
                    )
                    if index < 2:
                        assert root["Node Type"] == "Limit"
                    plans.append(
                        {
                            "query": index,
                            "sql_sha256": sha256(statement.encode()).hexdigest(),
                            **plan,
                        }
                    )
                target = os.environ.get("HARUKA_QUERY_PLAN_REPORT")
                if target:
                    await asyncio.to_thread(
                        Path(target).write_text,
                        json.dumps(
                            {
                                "run_id": run_id,
                                "own_history": 1200,
                                "foreign_history": 6000,
                                "fixture_scope": "failed simulated history only; actual authorized GET targets",
                                "cursor": "not implemented; future contract, no cursor coverage claimed",
                                "queries": [
                                    "jobs_a",
                                    "jobs_b",
                                    "usage_default_30d",
                                    "usage_filtered_a",
                                    "usage_filtered_b",
                                    "usage_explicit_3d",
                                ],
                                "plans": plans,
                            },
                            indent=2,
                        )
                        + "\n",
                        encoding="utf-8",
                    )
            finally:
                await engine.dispose()
