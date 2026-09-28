"""Owner settings and avatar operations against isolated PostgreSQL and Redis."""

import asyncio
import base64
import io
import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from urllib.parse import urlsplit
from uuid import UUID

import httpx2 as httpx
import pytest
from PIL import Image
from sqlalchemy import select

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.core.logging import SafeJsonFormatter
from app.domain.errors import AppError
from app.main import create_app
from app.maintenance.avatar_gc import collect_avatar_garbage
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import AuthChallengeDelivery, AuthPolicy, User
from app.models.avatar import FileObject, UploadIntent
from app.services import avatar as avatar_service
from app.services.auth_crypto import AuthCrypto
from app.services.avatar_image import PublishedAvatar
from tests.integration.test_authentication_flow import ORIGIN
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


def _png() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (24, 18), (150, 20, 20)).save(output, format="PNG")
    return output.getvalue()


async def _mail_token(maintenance: MaintenanceSettings, runtime: Runtime, email: str) -> str:
    engine = create_maintenance_engine(maintenance)
    try:
        async with engine.connect() as connection:
            encrypted = await connection.scalar(
                select(AuthChallengeDelivery.encrypted_payload)
                .join(User, User.id == AuthChallengeDelivery.user_id)
                .where(User.email_normalized == email.lower())
                .order_by(AuthChallengeDelivery.created_at.desc())
                .limit(1)
            )
            assert isinstance(encrypted, bytes)
            _address, link, _purpose = AuthCrypto.from_settings(runtime.settings).decrypt_mail(
                encrypted
            )
            return urlsplit(link).fragment.removeprefix("token=")
    finally:
        await engine.dispose()


def _paused_processor(
    entered: asyncio.Event,
    release: asyncio.Event,
    original: Callable[..., Awaitable[PublishedAvatar]],
) -> Callable[..., Awaitable[PublishedAvatar]]:
    async def paused(data: bytes, *, declared_format: str) -> PublishedAvatar:
        entered.set()
        await release.wait()
        return await original(data, declared_format=declared_format)

    return paused


async def _owner(
    runtime: Runtime, maintenance: MaintenanceSettings, email: str
) -> AsyncIterator[tuple[BoundAsyncClient, dict[str, str]]]:
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        assert (
            await web.post(
                "/api/v1/auth/register",
                json={
                    "email": email,
                    "password": "synthetic-profile-password-2026",
                },
                headers=headers,
            )
        ).status_code == 202
        assert (
            await web.post(
                "/api/v1/auth/email/verify",
                json={
                    "token": await _mail_token(maintenance, runtime, email),
                },
                headers=headers,
            )
        ).status_code == 204
        assert (
            await web.post(
                "/api/v1/auth/login",
                json={
                    "email": email,
                    "password": "synthetic-profile-password-2026",
                },
                headers=headers,
            )
        ).status_code == 200
        csrf = (await web.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        yield web, {**headers, "X-CSRF-Token": csrf}


async def test_profile_avatar_isolation_revision_race_and_cleanup(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    profile_operation_id = UUID("018f1234-0000-7000-8000-000000000099")
    caplog.set_level(logging.INFO, logger="app.api.profile")
    caplog.set_level(logging.INFO, logger="app.api.avatar")
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for owner_a, headers_a in _owner(
        runtime, maintenance, f"profile-a-{run_id}@haruka.example.test"
    ):
        async for owner_b, headers_b in _owner(
            runtime, maintenance, f"profile-b-{run_id}@haruka.example.test"
        ):
            profile_a = (await owner_a.get("/api/v1/users/me/profile")).json()["data"]
            assert profile_a["revision"] == 1
            assert (
                await owner_a.patch(
                    "/api/v1/users/me/study-profile",
                    json={
                        "expected_revision": 1,
                        "fields": {"target_languages": [{"language_tag": "ja"}]},
                    },
                    headers=headers_a,
                )
            ).status_code == 200
            assert (
                await owner_a.patch(
                    "/api/v1/users/me/settings",
                    json={
                        "expected_revision": 1,
                        "fields": {"timezone": "Asia/Tokyo"},
                    },
                    headers=headers_a,
                )
            ).status_code == 200
            assert (await owner_a.get("/api/v1/users/me/profile")).json()["data"]["revision"] == 1
            assert (await owner_b.get("/api/v1/language-capabilities")).status_code == 200
            assert (
                await owner_b.post(
                    "/api/v1/me/cache/validate",
                    json={
                        "protocol_version": 1,
                        "items": [],
                    },
                    headers=headers_b,
                )
            ).json()["data"]["items"] == []
            assert (
                await owner_b.post(
                    "/api/v1/me/cache/validate",
                    json={
                        "protocol_version": 1,
                        "items": [{"kind": "material_content"}],
                    },
                    headers=headers_b,
                )
            ).status_code == 422

            raw = _png()
            intent = await owner_a.post(
                "/api/v1/users/me/avatar-upload-intents",
                json={
                    "declared_format": "png",
                    "expected_size_bytes": len(raw),
                    "expected_sha256": sha256(raw).hexdigest(),
                },
                headers=headers_a,
            )
            assert intent.status_code == 200
            intent_id = intent.json()["data"]["id"]
            complete_path = f"/api/v1/users/me/avatar-upload-intents/{intent_id}/complete"
            payload = {"expected_revision": 1, "image_base64": base64.b64encode(raw).decode()}
            assert (
                await owner_b.post(complete_path, json=payload, headers=headers_b)
            ).status_code == 404
            assert (
                await owner_a.post(
                    complete_path, content=b"x" * (8 * 1024 * 1024), headers=headers_a
                )
            ).status_code == 413

            entered = asyncio.Event()
            release = asyncio.Event()
            original = avatar_service.publish_avatar_bounded

            paused = _paused_processor(entered, release, original)
            monkeypatch.setattr(avatar_service, "publish_avatar_bounded", paused)
            pending = asyncio.create_task(
                owner_a.post(complete_path, json=payload, headers=headers_a)
            )
            await asyncio.wait_for(entered.wait(), 5)
            changed = await owner_a.patch(
                "/api/v1/users/me/profile",
                json={
                    "expected_revision": 1,
                    "fields": {"display_name": "new name"},
                },
                headers={**headers_a, "X-Operation-ID": str(profile_operation_id)},
            )
            assert changed.status_code == 200
            release.set()
            conflict = await pending
            assert conflict.status_code == 409
            assert (await owner_a.get("/api/v1/users/me/avatar")).status_code == 404
            monkeypatch.setattr(avatar_service, "publish_avatar_bounded", original)
            payload["expected_revision"] = 2
            completed = await owner_a.post(complete_path, json=payload, headers=headers_a)
            assert completed.status_code == 200
            asset_id = completed.json()["data"]["avatar_asset_id"]
            assert (
                await owner_a.post(complete_path, json=payload, headers=headers_a)
            ).status_code == 200
            avatar_a = await owner_a.get("/api/v1/users/me/avatar")
            assert avatar_a.status_code == 200
            assert avatar_a.headers["cache-control"] == "private, no-store"
            assert avatar_a.content.startswith(b"\xff\xd8\xff")
            assert (await owner_b.get("/api/v1/users/me/avatar")).status_code == 404
            second_intent = await owner_a.post(
                "/api/v1/users/me/avatar-upload-intents",
                json={
                    "declared_format": "png",
                    "expected_size_bytes": len(raw),
                    "expected_sha256": sha256(raw).hexdigest(),
                },
                headers=headers_a,
            )
            assert second_intent.status_code == 200
            second_id = second_intent.json()["data"]["id"]
            second_path = f"/api/v1/users/me/avatar-upload-intents/{second_id}/complete"
            second_payload = {"expected_revision": 3, "image_base64": payload["image_base64"]}
            both = await asyncio.gather(
                owner_a.post(second_path, json=second_payload, headers=headers_a),
                owner_a.post(second_path, json=second_payload, headers=headers_a),
            )
            assert [response.status_code for response in both] == [200, 200]
            assert (
                both[0].json()["data"]["avatar_asset_id"]
                == both[1].json()["data"]["avatar_asset_id"]
            )
            current_asset_id = both[0].json()["data"]["avatar_asset_id"]
            async with runtime.resources.database.sessions() as session:
                files = (
                    await session.scalars(
                        select(FileObject).where(FileObject.upload_intent_id == UUID(second_id))
                    )
                ).all()
                assert len(files) == 1
            invalid_intent = await owner_a.post(
                "/api/v1/users/me/avatar-upload-intents",
                json={
                    "declared_format": "jpeg",
                    "expected_size_bytes": len(raw),
                    "expected_sha256": sha256(raw).hexdigest(),
                },
                headers=headers_a,
            )
            assert invalid_intent.status_code == 200
            invalid_path = (
                "/api/v1/users/me/avatar-upload-intents/"
                f"{invalid_intent.json()['data']['id']}/complete"
            )
            assert (
                await owner_a.post(
                    invalid_path,
                    json={
                        "expected_revision": 4,
                        "image_base64": payload["image_base64"],
                    },
                    headers=headers_a,
                )
            ).status_code == 415
            assert (await owner_a.get("/api/v1/users/me/profile")).json()["data"][
                "avatar_asset_id"
            ] == current_asset_id
            assert (await owner_a.get("/api/v1/users/me/avatar")).content == avatar_a.content

            async def timed_out(_data: bytes, *, declared_format: str) -> PublishedAvatar:
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)

            monkeypatch.setattr(avatar_service, "publish_avatar_bounded", timed_out)
            assert (
                await owner_a.post(
                    invalid_path,
                    json={
                        "expected_revision": 4,
                        "image_base64": payload["image_base64"],
                    },
                    headers=headers_a,
                )
            ).status_code == 503
            monkeypatch.setattr(avatar_service, "publish_avatar_bounded", original)
            assert (await owner_a.get("/api/v1/users/me/profile")).json()["data"][
                "avatar_asset_id"
            ] == current_asset_id
            assert (
                await owner_a.post(second_path, content=b"x" * (8 * 1024 * 1024), headers=headers_a)
            ).status_code == 413
            assert (await owner_a.get("/api/v1/users/me/profile")).json()["data"][
                "avatar_asset_id"
            ] == current_asset_id
            b_intent = await owner_b.post(
                "/api/v1/users/me/avatar-upload-intents",
                json={
                    "declared_format": "png",
                    "expected_size_bytes": len(raw),
                    "expected_sha256": sha256(raw).hexdigest(),
                },
                headers=headers_b,
            )
            assert b_intent.status_code == 200
            b_completed = await owner_b.post(
                f"/api/v1/users/me/avatar-upload-intents/{b_intent.json()['data']['id']}/complete",
                json={"expected_revision": 1, "image_base64": payload["image_base64"]},
                headers=headers_b,
            )
            assert b_completed.status_code == 200
            b_asset_id = b_completed.json()["data"]["avatar_asset_id"]
            deleted = await owner_a.request(
                "DELETE",
                "/api/v1/users/me/avatar",
                json={
                    "expected_revision": 4,
                },
                headers=headers_a,
            )
            assert deleted.status_code == 200
            assert deleted.json()["data"]["avatar_asset_id"] is None
            async with runtime.resources.database.sessions() as session:
                asset = await session.get(FileObject, UUID(asset_id))
                assert asset is not None and asset.retention_state == "gc_pending"
            removed_files = 0
            for _ in range(8):
                removed = await collect_avatar_garbage(
                    runtime.resources.database.sessions,
                    now=datetime.now(UTC) + timedelta(days=8),
                    row_limit_per_owner=1,
                )
                assert sum(removed) <= 2
                removed_files += removed[1]
            assert removed_files == 2
            async with runtime.resources.database.sessions() as session:
                assert await session.get(FileObject, UUID(asset_id)) is None
                assert await session.get(FileObject, UUID(current_asset_id)) is None
                assert await session.get(UploadIntent, UUID(intent_id)) is None
                live_b = await session.get(FileObject, UUID(b_asset_id))
                assert live_b is not None and live_b.retention_state == "referenced"
            assert (await owner_b.get("/api/v1/users/me/avatar")).status_code == 200
            revoke_intent = await owner_a.post(
                "/api/v1/users/me/avatar-upload-intents",
                json={
                    "declared_format": "png",
                    "expected_size_bytes": len(raw),
                    "expected_sha256": sha256(raw).hexdigest(),
                },
                headers=headers_a,
            )
            assert revoke_intent.status_code == 200
            revoke_id = revoke_intent.json()["data"]["id"]
            entered.clear()
            release.clear()
            monkeypatch.setattr(avatar_service, "publish_avatar_bounded", paused)
            late = asyncio.create_task(
                owner_a.post(
                    f"/api/v1/users/me/avatar-upload-intents/{revoke_id}/complete",
                    json={"expected_revision": 5, "image_base64": payload["image_base64"]},
                    headers=headers_a,
                )
            )
            await asyncio.wait_for(entered.wait(), 5)
            assert (await owner_a.post("/api/v1/auth/logout", headers=headers_a)).status_code == 204
            release.set()
            refused = await late
            assert refused.status_code in {401, 403}
            async with runtime.resources.database.sessions() as session:
                untouched = await session.get(UploadIntent, UUID(revoke_id))
                assert untouched is not None and untouched.status == "pending"
                assert (
                    await session.scalars(
                        select(FileObject).where(FileObject.upload_intent_id == UUID(revoke_id))
                    )
                ).all() == []
    events = {record.msg for record in caplog.records if record.name.startswith("app.api.")}
    assert {
        "profile.updated",
        "study_profile.updated",
        "settings.updated",
        "profile.avatar.updated",
        "profile.avatar.deleted",
    } <= events
    correlated = [
        record
        for record in caplog.records
        if record.msg == "profile.updated"
        and getattr(record, "operation_id", None) == profile_operation_id
    ]
    assert len(correlated) == 1
    assert isinstance(getattr(correlated[0], "request_id", None), UUID)
    assert isinstance(getattr(correlated[0], "user_id", None), UUID)
    assert getattr(correlated[0], "audience", None) == "client"
    formatter = SafeJsonFormatter(runtime.settings, "api")
    rendered = "\n".join(
        formatter.format(record) for record in caplog.records if record.name.startswith("app.api.")
    )
    assert "new name" not in rendered
    assert "image_base64" not in rendered
    assert "profile-a-" not in rendered
    assert str(profile_operation_id) in rendered
