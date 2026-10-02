"""Real PG mail leases preserve fence, retry facts and encrypted payload cleanup."""

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx2 as httpx
import pytest
from sqlalchemy import select

from app.bootstrap import Runtime
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthChallengeDelivery
from app.services.notifications import claim_due_mail, deliver_one, finish_mail
from tests.integration.test_authentication_flow import (
    ORIGIN,
)
from tests.integration.test_authentication_flow import (
    identity_runtime as identity_runtime,
)
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]


@pytest.mark.parametrize("outcome", ["sent", "retry", "attempt_limit", "expired"])
async def test_delivery_commit_fence_and_failure_sealing(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], outcome: str
) -> None:
    runtime, _, run_id = identity_runtime
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as client:
        accepted = await client.post(
            "/api/v1/auth/recovery/request",
            json={"email": f"admin-{run_id}@haruka.example.test"},
            headers={"Origin": ORIGIN, "Content-Type": "application/json"},
        )
        assert accepted.status_code == 202
    lease = await claim_due_mail(runtime, uuid4())
    assert lease is not None
    assert not await finish_mail(
        runtime, replace(lease, generation=lease.generation - 1), sent=True
    )
    assert not await finish_mail(runtime, replace(lease, owner=uuid4()), sent=True)
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        row = await session.scalar(
            select(AuthChallengeDelivery)
            .where(AuthChallengeDelivery.id == lease.delivery_id)
            .with_for_update()
        )
        assert row is not None and row.status == "sending" and row.lease_owner == lease.owner
        if outcome == "attempt_limit":
            row.attempt_count = 5
        if outcome == "expired":
            row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    assert await finish_mail(runtime, lease, sent=outcome == "sent")
    assert not await finish_mail(runtime, lease, sent=True)
    async with runtime.resources.database.sessions() as session:
        row = await session.get(AuthChallengeDelivery, lease.delivery_id)
        assert row is not None
        assert row.lease_owner is None and row.lease_until is None
        if outcome == "sent":
            assert row.status == "sent" and row.last_error_code is None
        elif outcome == "retry":
            assert row.status == "pending" and row.next_attempt_at is not None
            assert row.next_attempt_at > datetime.now(UTC)
            assert row.encrypted_payload is not None and row.encryption_key_version is not None
        else:
            assert row.status == "failed"
        if outcome != "retry":
            assert row.encrypted_payload is None and row.encryption_key_version is None
            assert row.next_attempt_at is None
        if outcome != "sent":
            assert row.last_error_code == "smtp_result_unknown"
    assert await claim_due_mail(runtime, uuid4()) is None


@pytest.mark.parametrize("fault", ["key_unavailable", "corrupt_payload", "smtp_unknown", "sent"])
async def test_mail_dispatch_never_leaks_or_replays_in_one_attempt(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    fault: str,
) -> None:
    runtime, _, run_id = identity_runtime
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as client:
        accepted = await client.post(
            "/api/v1/auth/recovery/request",
            json={"email": f"admin-{run_id}@haruka.example.test"},
            headers={"Origin": ORIGIN, "Content-Type": "application/json"},
        )
        assert accepted.status_code == 202
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        row = await session.scalar(select(AuthChallengeDelivery).with_for_update())
        assert row is not None
        row_id = row.id
        if fault == "key_unavailable":
            row.encryption_key_version = "unavailable-key-version"
        elif fault == "corrupt_payload":
            row.encrypted_payload = b"invalid-encrypted-payload"
    calls: list[str] = []

    def smtp(_settings: object, email: str, link: str, purpose: str) -> None:
        calls.append(purpose)
        assert email == f"admin-{run_id}@haruka.example.test"
        assert link.startswith(ORIGIN)
        if fault == "smtp_unknown":
            raise OSError("synthetic SMTP result unknown")

    monkeypatch.setattr("app.services.notifications.send_smtp_message", smtp)
    assert await deliver_one(runtime)
    assert calls == (["password_recovery"] if fault in {"smtp_unknown", "sent"} else [])
    assert not await deliver_one(runtime)
    async with runtime.resources.database.sessions() as session:
        row = await session.get(AuthChallengeDelivery, row_id)
        assert row is not None and row.attempt_count == 1
        assert row.lease_owner is None and row.lease_until is None
        assert row.status == ("sent" if fault == "sent" else "pending")
        assert row.last_error_code == (None if fault == "sent" else "smtp_result_unknown")
