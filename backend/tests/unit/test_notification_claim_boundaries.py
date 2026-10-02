"""Mail claim rechecks selected candidates; mocked I/O is not PostgreSQL evidence."""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.services import notifications as service
from app.services.auth_crypto import AuthCrypto
from tests.unit.test_session_service_boundaries import Context
from tests.unit.test_session_service_boundaries import context as context

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


@pytest.mark.parametrize(
    "fault",
    [
        "missing_user",
        "missing_challenge",
        "missing_delivery",
        "owner",
        "consumed",
        "revoked",
        "challenge_expired",
        "delivery_expired",
        "epoch",
        "password_version",
        "email",
        "verify_state",
        "recovery_state",
        "unsupported_purpose",
        "pending_future",
        "sending_live",
        "closed",
        "attempt_limit",
        "payload_absent",
        "key_absent",
        "database",
    ],
)
async def test_mail_claim_revalidates_candidate_before_attempt_or_delivery(
    context: Context,
    monkeypatch: pytest.MonkeyPatch,
    fault: str,
) -> None:
    context.runtime.schema_compatible = True
    monkeypatch.setattr(service, "mail_ready", MagicMock(return_value=True))
    now = datetime.now(UTC)
    user = MagicMock(
        id=context.scope.user_id,
        security_epoch=2,
        password_version=3,
        email_normalized="owner@example.com",
        status="pending",
    )
    challenge = MagicMock(
        id=uuid4(),
        user_id=user.id,
        consumed_at=None,
        revoked_at=None,
        expires_at=now + timedelta(hours=1),
        security_epoch=2,
        password_version=3,
        purpose="email_verify",
        target_email_digest=AuthCrypto.from_settings(context.runtime.settings).digest(
            "email-target", user.email_normalized
        ),
    )
    delivery = MagicMock(
        id=uuid4(),
        user_id=user.id,
        challenge_id=challenge.id,
        status="pending",
        expires_at=now + timedelta(hours=1),
        next_attempt_at=now,
        lease_until=None,
        lease_owner=None,
        lease_generation=1,
        attempt_count=0,
        encrypted_payload=b"synthetic encrypted payload",
        encryption_key_version="test",
    )
    if fault == "owner":
        challenge.user_id = uuid4()
    elif fault in ("consumed", "revoked"):
        setattr(challenge, "consumed_at" if fault == "consumed" else "revoked_at", now)
    elif fault == "challenge_expired":
        challenge.expires_at = now - timedelta(seconds=1)
    elif fault == "delivery_expired":
        delivery.expires_at = now - timedelta(seconds=1)
    elif fault == "epoch":
        challenge.security_epoch += 1
    elif fault == "password_version":
        challenge.password_version += 1
    elif fault == "email":
        challenge.target_email_digest = b"mismatch"
    elif fault == "verify_state":
        user.status = "active"
    elif fault == "recovery_state":
        challenge.purpose = "password_recovery"
    elif fault == "unsupported_purpose":
        challenge.purpose = "unregistered"
    elif fault == "pending_future":
        delivery.next_attempt_at = now + timedelta(minutes=1)
    elif fault == "sending_live":
        delivery.status = "sending"
        delivery.lease_until = now + timedelta(minutes=1)
    elif fault == "closed":
        delivery.status = "sent"
    elif fault == "attempt_limit":
        delivery.attempt_count = 5
    elif fault == "payload_absent":
        delivery.encrypted_payload = None
    elif fault == "key_absent":
        delivery.encryption_key_version = None
    result = MagicMock()
    result.first.return_value = MagicMock(
        id=delivery.id, user_id=user.id, challenge_id=challenge.id
    )
    context.session.execute = AsyncMock(return_value=result)
    context.session.scalar = AsyncMock(
        side_effect=[
            None if fault == "missing_user" else user,
            None if fault == "missing_challenge" else challenge,
            None if fault == "missing_delivery" else delivery,
        ]
    )
    if fault == "database":
        context.session.execute.side_effect = RuntimeError("private database detail")
    initial_attempts = delivery.attempt_count
    if fault in {"payload_absent", "key_absent", "database"}:
        with pytest.raises(AppError) as error:
            await service.claim_due_mail(context.runtime, uuid4())
        assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    else:
        assert await service.claim_due_mail(context.runtime, uuid4()) is None
    assert delivery.attempt_count == initial_attempts
    assert delivery.lease_owner is None
    if fault not in {
        "missing_delivery",
        "pending_future",
        "sending_live",
        "closed",
        "payload_absent",
        "key_absent",
        "database",
    }:
        assert delivery.status == ("failed" if fault == "attempt_limit" else "expired")
        assert delivery.encrypted_payload is None
        assert delivery.encryption_key_version is None
