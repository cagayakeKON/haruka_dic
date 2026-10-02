"""Signed boundary attacks, purpose separation and original pagination lifetime."""

import hashlib
import hmac
from base64 import urlsafe_b64encode
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID, uuid4

import pytest

from app.contracts.errors import ErrorCode
from app.domain import notification_tokens as tokens
from app.domain.errors import AppError
from app.domain.scope import ScopeContext

pytestmark = pytest.mark.unit
_SIGNING_MATERIAL = b"synthetic-notification-signing-material-only"


def scope() -> ScopeContext:
    return ScopeContext(
        user_id=uuid4(),
        session_id=uuid4(),
        audience="client",
        transport="web",
        user_authz_version=1,
        policy_authz_version=1,
        security_epoch=1,
        absolute_expires_at=datetime.now(UTC) + timedelta(hours=1),
    )


def test_snapshot_binds_owner_instance_library_audience_purpose_and_expiry() -> None:
    current, library, now = scope(), uuid4(), datetime.now(UTC)
    token = tokens.initial_snapshot(
        instance="owned-test", scope=current, library_id=library, upper=7, now=now
    )
    encoded = tokens.encode(token, _SIGNING_MATERIAL)
    assert (
        tokens.decode(
            encoded,
            _SIGNING_MATERIAL,
            purpose="snapshot",
            instance="owned-test",
            scope=current,
            library_id=library,
            now=now,
        )
        == token
    )
    cases: list[tuple[Literal["snapshot", "cursor"], str, ScopeContext, UUID]] = [
        ("snapshot", "owned-test", replace(current, user_id=uuid4()), library),
        ("snapshot", "other", current, library),
        ("snapshot", "owned-test", current, uuid4()),
        ("snapshot", "owned-test", replace(current, audience="admin"), library),
        ("cursor", "owned-test", current, library),
    ]
    for purpose, instance, actor, library_id in cases:
        with pytest.raises(AppError) as rejected:
            tokens.decode(
                encoded,
                _SIGNING_MATERIAL,
                purpose=purpose,
                instance=instance,
                scope=actor,
                library_id=library_id,
                now=now,
            )
        assert rejected.value.code == ErrorCode.INPUT_INVALID
    with pytest.raises(AppError) as expired:
        tokens.decode(
            encoded,
            _SIGNING_MATERIAL,
            purpose="snapshot",
            instance="owned-test",
            scope=current,
            library_id=library,
            now=now + timedelta(seconds=901),
        )
    assert expired.value.code == ErrorCode.RESOURCE_EXPIRED


def test_cursor_freezes_upper_expiry_filter_and_anchor_across_pages() -> None:
    current, library, now = scope(), uuid4(), datetime.now(UTC)
    first = tokens.initial_snapshot(
        instance="owned-test", scope=current, library_id=library, upper=9, now=now
    )
    cursor = tokens.cursor_for(
        first, unread_only=True, anchor_at=now - timedelta(days=1), anchor_id=uuid4()
    )
    encoded = tokens.encode(cursor, _SIGNING_MATERIAL)
    later = now + timedelta(minutes=10)
    decoded = tokens.decode(
        encoded,
        _SIGNING_MATERIAL,
        purpose="cursor",
        instance="owned-test",
        scope=current,
        library_id=library,
        now=later,
        unread_only=True,
    )
    next_page = tokens.cursor_for(
        tokens.snapshot_from(decoded),
        unread_only=True,
        anchor_at=now - timedelta(days=2),
        anchor_id=uuid4(),
    )
    assert next_page.upper == 9 and next_page.expires_at == first.expires_at
    assert tokens.encode(tokens.snapshot_from(decoded), _SIGNING_MATERIAL) == tokens.encode(
        first, _SIGNING_MATERIAL
    )
    with pytest.raises(AppError):
        tokens.decode(
            encoded,
            _SIGNING_MATERIAL,
            purpose="cursor",
            instance="owned-test",
            scope=current,
            library_id=library,
            now=later,
            unread_only=False,
        )
    with pytest.raises(AppError):
        tokens.decode(
            encoded,
            _SIGNING_MATERIAL,
            purpose="snapshot",
            instance="owned-test",
            scope=current,
            library_id=library,
            now=later,
        )


def test_tampered_overlarge_or_signed_wrong_typed_boundary_rejected() -> None:
    current, library, now = scope(), uuid4(), datetime.now(UTC)
    snapshot = tokens.initial_snapshot(
        instance="owned-test", scope=current, library_id=library, upper=0, now=now
    )
    encoded = tokens.encode(snapshot, _SIGNING_MATERIAL)
    invalid_json = snapshot.model_dump_json().replace('"upper":0', '"upper":true')
    assert '"upper":true' in invalid_json
    body = urlsafe_b64encode(invalid_json.encode()).rstrip(b"=")
    signature = urlsafe_b64encode(
        hmac.new(
            _SIGNING_MATERIAL, b"haruka-notifications-v1\x00snapshot\x00" + body, hashlib.sha256
        ).digest()
    ).rstrip(b"=")
    signed_wrong_type = (body + b"." + signature).decode("ascii")
    for invalid in (
        "x" * 2049,
        encoded[1:] + "x",
        encoded.replace(".", ".."),
        signed_wrong_type,
    ):
        with pytest.raises(AppError) as rejected:
            tokens.decode(
                invalid,
                _SIGNING_MATERIAL,
                purpose="snapshot",
                instance="owned-test",
                scope=current,
                library_id=library,
                now=now,
            )
        assert rejected.value.code == ErrorCode.INPUT_INVALID
