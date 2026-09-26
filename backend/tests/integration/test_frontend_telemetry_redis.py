"""Real namespaced Redis proves replay and owner separation for current slice telemetry."""

import asyncio
import json
import os
import secrets
from base64 import urlsafe_b64encode
from collections.abc import AsyncIterator
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol, cast
from unittest.mock import patch
from uuid import uuid4

import pytest
from fastapi import FastAPI
from pydantic import SecretStr
from starlette.types import Message, Scope

from app.adapters.cache import Cache
from app.adapters.database import Database
from app.bootstrap import Resources, Runtime
from app.core.logging import SafeJsonFormatter
from app.core.settings import Settings, load_settings
from app.domain.scope import ScopeContext
from app.main import create_app
from app.schemas.frontend_telemetry import TelemetryBatchRequest
from app.services.auth_crypto import AuthCrypto
from app.services.frontend_telemetry import receive

ROOT = Path(__file__).resolve().parents[3]


class _ScopedScanner(Protocol):
    def scan_iter(self, *, match: str) -> AsyncIterator[bytes]: ...


async def _asgi_post(
    app: FastAPI, body: bytes | list[bytes]
) -> tuple[int, dict[str, str], dict[str, object]]:
    messages: list[Message] = []
    chunks = body if isinstance(body, list) else [body]
    next_chunk = 0

    async def read() -> Message:
        nonlocal next_chunk
        if next_chunk < len(chunks):
            chunk = chunks[next_chunk]
            next_chunk += 1
            return {"type": "http.request", "body": chunk, "more_body": next_chunk < len(chunks)}
        return {"type": "http.disconnect"}

    async def write(message: Message) -> None:
        messages.append(message)

    scope: Scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "https",
        "path": "/api/v1/frontend-logs/anonymous",
        "raw_path": b"/api/v1/frontend-logs/anonymous",
        "query_string": b"",
        "root_path": "",
        "headers": [
            (b"origin", b"https://localhost:18443"),
            (b"content-type", b"application/json"),
        ],
        "client": ("127.0.0.1", 12345),
        "server": ("localhost", 18443),
    }
    await app(scope, read, write)
    start = next(message for message in messages if message["type"] == "http.response.start")
    status = cast(int, start["status"])
    raw_headers = cast("list[tuple[bytes, bytes]]", start["headers"])
    headers = {key.decode(): value.decode() for key, value in raw_headers}
    raw_body = b"".join(
        cast(bytes, message.get("body", b""))
        for message in messages
        if message["type"] == "http.response.body"
    )
    result = cast("dict[str, object]", json.loads(raw_body))
    return status, headers, result


@pytest.mark.asyncio
async def test_redis_replay_is_atomic_and_identity_scoped(caplog: pytest.LogCaptureFixture) -> None:
    if os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG") != "dev/.local/test-maintenance.env":
        pytest.fail("explicit isolated test configuration is required")
    template = load_settings(ROOT / "dev/.local/test.env")
    assert template.database_url is not None and template.redis_url is not None
    run_id = uuid4().hex
    settings = Settings(
        app_env="test",
        instance_id=f"haruka-test-{run_id}",
        public_base_url="https://localhost:18443",
        infrastructure_enabled=True,
        resource_profile="core",
        database_url=template.database_url,
        redis_url=template.redis_url,
        resource_namespace=f"haruka-test-{run_id}",
        auth_signing_key=SecretStr(urlsafe_b64encode(secrets.token_bytes(32)).decode()),
        auth_digest_key=SecretStr(urlsafe_b64encode(secrets.token_bytes(32)).decode()),
    )
    configuration = settings.core_infrastructure()
    cache = Cache(configuration)
    database = Database(configuration)
    runtime = Runtime(
        settings=settings,
        resources=Resources(
            database=database, cache=cache, kafka=None, storage=None, consumer=None
        ),
        schema_compatible=True,
    )
    try:
        await cache.check()
        owner = uuid4()
        now = datetime.now(UTC)
        scope = ScopeContext(
            user_id=owner,
            session_id=uuid4(),
            audience="client",
            transport="native",
            user_authz_version=1,
            policy_authz_version=1,
            security_epoch=1,
            absolute_expires_at=now + timedelta(days=1),
        )
        event_id = uuid4()
        business_request_id = uuid4()
        batch = TelemetryBatchRequest.model_validate(
            {
                "client_session_id": str(uuid4()),
                "events": [
                    {
                        "event_id": str(event_id),
                        "record_type": "analytics",
                        "event": "collection.saved",
                        "level": "info",
                        "occurred_at": now.isoformat(),
                        "client_platform": "windows",
                        "operation_id": str(uuid4()),
                        "request_id": str(business_request_id),
                        "attributes": {"card_type": "word", "result": "success"},
                    },
                    {
                        "event_id": str(uuid4()),
                        "record_type": "analytics",
                        "event": "collection.saved",
                        "level": "info",
                        "occurred_at": now.isoformat(),
                        "client_platform": "windows",
                        "user_id": "private-token-sentinel",
                    },
                ],
            }
        )
        caplog.set_level("INFO", logger="app.services.frontend_telemetry")
        first, second = await asyncio.gather(
            receive(
                runtime,
                batch,
                scope=scope,
                anonymous=False,
                web_transport=False,
                address="127.0.0.1",
                ingest_request_id=uuid4(),
            ),
            receive(
                runtime,
                batch,
                scope=scope,
                anonymous=False,
                web_transport=False,
                address="127.0.0.1",
                ingest_request_id=uuid4(),
            ),
        )
        assert sorted([first.results[0].status, second.results[0].status]) == [
            "accepted",
            "duplicate",
        ]
        assert first.results[1].status == second.results[1].status == "rejected"
        assert first.results[1].reason == second.results[1].reason == "invalid_record"
        other_user = replace(scope, user_id=uuid4())
        admin = replace(scope, audience="admin")
        for separate_scope in (other_user, admin):
            separate = await receive(
                runtime,
                batch,
                scope=separate_scope,
                anonymous=False,
                web_transport=False,
                address="127.0.0.1",
                ingest_request_id=uuid4(),
            )
            assert separate.results[0].status == "accepted"
        key = cache.key("telemetry", "seen", "client", str(owner), str(event_id))
        assert await cache.client.ttl(key) >= 24 * 60 * 60
        accepted = [record for record in caplog.records if record.msg == "frontend.received"]
        assert len(accepted) == 3
        emitted = json.loads(SafeJsonFormatter(settings, "api").format(accepted[0]))
        assert emitted["event"] == "collection.saved"
        assert emitted["origin"] == "client"
        assert emitted["user_id"] == str(owner)
        assert emitted["request_id"] == str(business_request_id)
        assert emitted["ingest_request_id"] != str(business_request_id)
        assert "private-token-sentinel" not in json.dumps(emitted)

        app = create_app(settings)
        app.state.runtime = runtime
        anonymous_event = {
            "event_id": str(uuid4()),
            "record_type": "analytics",
            "event": "app.started",
            "level": "info",
            "occurred_at": datetime.now(UTC).isoformat(),
            "client_platform": "web",
        }
        status, headers, response = await _asgi_post(
            app,
            json.dumps({"client_session_id": str(uuid4()), "events": [anonymous_event]}).encode(),
        )
        assert status == 200
        response_data = cast("dict[str, object]", response["data"])
        results = cast("list[dict[str, object]]", response_data["results"])
        assert results[0]["status"] == "accepted"
        assert "x-request-id" in headers
        oversized, _, _ = await _asgi_post(app, [b"{" + b"x" * 8192, b"x" * 8193])
        assert oversized == 413
        six = [{**anonymous_event, "event_id": str(uuid4())} for _ in range(6)]
        too_many, _, _ = await _asgi_post(
            app, json.dumps({"client_session_id": str(uuid4()), "events": six}).encode()
        )
        assert too_many == 422

        fresh = {**anonymous_event, "event_id": str(uuid4())}
        with patch.object(cache.client, "set", side_effect=RuntimeError("secret sentinel")):
            unavailable, _, response = await _asgi_post(
                app,
                json.dumps({"client_session_id": str(uuid4()), "events": [fresh]}).encode(),
            )
        assert unavailable == 503
        assert "secret sentinel" not in json.dumps(response)

        digest = AuthCrypto.from_settings(settings).digest("telemetry-ip", "127.0.0.1").hex()
        rate_key = cache.key("telemetry", "rate", "ip", digest)
        await cache.client.set(rate_key, b"120", ex=60)
        limited, _, _ = await _asgi_post(
            app,
            json.dumps({"client_session_id": str(uuid4()), "events": [fresh]}).encode(),
        )
        assert limited == 429
        assert await cache.client.ttl(rate_key) > 0
    finally:
        scanner = cast(_ScopedScanner, cache.client)
        keys = [key async for key in scanner.scan_iter(match=f"haruka-test-{run_id}:*")]
        if keys:
            await cache.client.delete(*keys)
        await cache.aclose()
        await database.aclose()
