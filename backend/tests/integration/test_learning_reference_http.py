"""Authenticated published-source to collection flow over the real API and test database."""

import logging
import re
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from fastapi import FastAPI
from sqlalchemy import select, text

from app.bootstrap import Runtime
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models.learning_reference import CollectionItem
from tests.integration.test_authentication_flow import (
    _mail_token,  # pyright: ignore[reportPrivateUsage] - shared isolated challenge fixture
)
from tests.support.bound_client import BoundAsyncClient
from tests.support.learning_reference_scenarios import prepare_learning_source

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
ORIGIN = "https://localhost:18443"


class DropCommittedCollectionResponse(httpx.AsyncBaseTransport):
    """Lose one response after the formal ASGI app completes its transaction."""

    def __init__(self, app: FastAPI) -> None:
        self.inner = httpx.ASGITransport(app=app)
        self.drop_count = 0

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        response = await self.inner.handle_async_request(request)
        if (
            self.drop_count == 0
            and request.method == "POST"
            and request.url.path == "/api/v1/collections"
        ):
            await response.aread()
            await response.aclose()
            self.drop_count += 1
            raise httpx.ReadError("synthetic response loss", request=request)
        return response

    async def aclose(self) -> None:
        await self.inner.aclose()


async def test_http_source_resolution_collection_commit_and_lost_response_replay(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    caplog: pytest.LogCaptureFixture,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    assert re.fullmatch(r"[a-f0-9]{32}", run_id)
    schema = f"haruka_migration_test_{run_id}"
    assert maintenance.test_schema == schema
    observer = create_maintenance_engine(maintenance)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.exec_driver_sql(
                f"COMMENT ON SCHEMA {schema} IS 'haruka-b1-run:{run_id}'"
            )
    finally:
        await observer.dispose()

    app = create_app(runtime.settings)
    app.state.runtime = runtime
    transport = DropCommittedCollectionResponse(app)
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    email = f"learner-{run_id}@haruka.example.test"
    password = "synthetic-collection-password-2026"  # noqa: S105 - isolated identity
    async with BoundAsyncClient(transport=transport, base_url=ORIGIN) as admin:
        login = await admin.post(
            "/api/v1/admin/auth/login",
            json={
                "email": f"admin-{run_id}@haruka.example.test",
                "password": "synthetic-admin-password-2026",
            },
            headers=headers,
        )
        assert login.status_code == 200
        csrf = (await admin.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
        policy = (await admin.get("/api/v1/admin/auth-policy")).json()["data"]
        opened = await admin.patch(
            "/api/v1/admin/auth-policy",
            json={"registration_mode": "open", "expected_revision": policy["revision"]},
            headers={
                **headers,
                "X-CSRF-Token": csrf,
                "Idempotency-Key": "policy-learning_reference_http-89",
            },
        )
        assert opened.status_code == 200

    async with BoundAsyncClient(transport=transport, base_url=ORIGIN) as client:
        registered = await client.post(
            "/api/v1/auth/register", json={"email": email, "password": password}, headers=headers
        )
        assert registered.status_code == 202
        token = await _mail_token(maintenance, runtime, email)
        verified = await client.post(
            "/api/v1/auth/email/verify", json={"token": token}, headers=headers
        )
        assert verified.status_code == 204
        authenticated = await client.post(
            "/api/v1/auth/login", json={"email": email, "password": password}, headers=headers
        )
        assert authenticated.status_code == 200
        csrf = (await client.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        scoped_headers = {**headers, "X-CSRF-Token": csrf}

        source = await prepare_learning_source(
            maintenance, owner_email=email, instance_id=runtime.settings.instance_id
        )
        listed = await client.get("/api/v1/materials")
        assert listed.status_code == 200
        assert [item["id"] for item in listed.json()["data"]] == [str(source.material_id)]
        chapter = await client.get(
            f"/api/v1/novels/{source.material_id}/revisions/{source.revision_id}/chapters/{source.chapter_id}"
        )
        assert chapter.status_code == 200
        block = chapter.json()["data"]["blocks"][0]
        content = block["canonical_text"]
        start = content.index("空")
        locator = {
            **block["source_locator"],
            "quote": "空",
            "prefix": content[:start],
            "suffix": content[start + 1 :],
            "spans": [
                {
                    "block_id": block["id"],
                    "start": start,
                    "end": start + 1,
                }
            ],
        }
        resolved = await client.post(
            "/api/v1/explanations/resolve",
            json={
                "targets": [
                    {
                        "source_locator": locator,
                        "target_language": "ja",
                        "explanation_language": "zh-CN",
                    }
                ]
            },
            headers=scoped_headers,
        )
        assert resolved.status_code == 200
        card = resolved.json()["data"]["results"][0]
        assert card["state"] == "found"
        assert card["card"]["card_id"] == str(source.card_id)
        payload: dict[str, object] = {
            "card_id": str(source.card_id),
            "card_revision": 1,
            "notebook_ids": list[str](),
        }
        operation_id = uuid4()
        write_headers = {
            **scoped_headers,
            "Idempotency-Key": "lost-response-replay",
            "X-Operation-ID": str(operation_id),
        }
        with caplog.at_level(logging.INFO, logger="haruka.learning"):
            with pytest.raises(httpx.ReadError):
                await client.post("/api/v1/collections", json=payload, headers=write_headers)
            assert transport.drop_count == 1
            replay = await client.post("/api/v1/collections", json=payload, headers=write_headers)
            assert replay.status_code == 201
            item_id = replay.json()["data"]["id"]
            existing = await client.post(
                "/api/v1/collections",
                json=payload,
                headers={**write_headers, "Idempotency-Key": "another-valid-key"},
            )
            assert existing.status_code == 200
            assert existing.json()["data"]["id"] == item_id
            conflict = await client.post(
                "/api/v1/collections",
                json={**payload, "confirmed_target_language": "ja"},
                headers=write_headers,
            )
            assert conflict.status_code == 409
        collection_events = [
            record for record in caplog.records if record.msg == "collection.saved"
        ]
        assert [getattr(record, "collection_outcome", None) for record in collection_events] == [
            "created",
            "replayed",
            "existing",
        ]
        assert all(
            getattr(record, "operation_id", None) == operation_id for record in collection_events
        )
        assert all(
            isinstance(getattr(record, "request_id", None), UUID) for record in collection_events
        )
        assert all(getattr(record, "audience", None) == "client" for record in collection_events)
        page = await client.get("/api/v1/collections")
        assert page.status_code == 200
        assert [item["id"] for item in page.json()["data"]] == [item_id]
    async with runtime.resources.database.sessions() as session:
        rows = (await session.scalars(select(CollectionItem))).all()
        assert len(rows) == 1 and str(rows[0].id) == item_id
