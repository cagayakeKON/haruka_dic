"""Optional, nonunique display names through authenticated owner HTTP operations."""

from collections.abc import AsyncIterator
from urllib.parse import urlsplit

import httpx2 as httpx
import pytest
from sqlalchemy import select

from app.bootstrap import Runtime
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import AuthChallengeDelivery, AuthPolicy, User
from app.models.identity_security import UserExtension
from app.models.model_tasks import ExternalCallAttempt
from app.services.auth_crypto import AuthCrypto
from tests.integration.test_authentication_flow import ORIGIN
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


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


async def test_two_authenticated_owners_can_share_and_independently_clear_display_name(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email_a = f"display-a-{run_id}@haruka.example.test"
    email_b = f"display-b-{run_id}@haruka.example.test"
    # The local helper registers/verifies/logs in with email/password, without profile fields.
    async for owner_a, headers_a in _owner(runtime, maintenance, email_a):
        async for owner_b, headers_b in _owner(runtime, maintenance, email_b):
            initial_a = await owner_a.get("/api/v1/users/me/profile")
            initial_b = await owner_b.get("/api/v1/users/me/profile")
            assert initial_a.status_code == initial_b.status_code == 200
            assert initial_a.json()["data"]["display_name"] is None
            assert initial_b.json()["data"]["display_name"] is None
            shared_name = "Shared learner"
            for owner, headers, initial in (
                (owner_a, headers_a, initial_a),
                (owner_b, headers_b, initial_b),
            ):
                changed = await owner.patch(
                    "/api/v1/users/me/profile",
                    json={
                        "expected_revision": initial.json()["data"]["revision"],
                        "fields": {"display_name": shared_name},
                    },
                    headers=headers,
                )
                assert changed.status_code == 200
                assert changed.json()["data"]["display_name"] == shared_name
            saved_a = (await owner_a.get("/api/v1/users/me/profile")).json()["data"]
            saved_b = (await owner_b.get("/api/v1/users/me/profile")).json()["data"]
            assert saved_a["display_name"] == saved_b["display_name"] == shared_name
            assert saved_a["revision"] == saved_b["revision"] == 2
            cleared = await owner_a.patch(
                "/api/v1/users/me/profile",
                json={"expected_revision": saved_a["revision"], "fields": {"display_name": None}},
                headers=headers_a,
            )
            assert cleared.status_code == 200
            assert (await owner_a.get("/api/v1/users/me/profile")).json()["data"][
                "display_name"
            ] is None
            assert (await owner_b.get("/api/v1/users/me/profile")).json()["data"] == saved_b
            async with runtime.resources.database.sessions() as session, session.begin():
                users = list(
                    await session.scalars(
                        select(User).where(User.email_normalized.in_((email_a, email_b)))
                    )
                )
                assert len(users) == 2 and users[0].id != users[1].id
                by_email = {user.email_normalized: user for user in users}
                extension_a = await session.scalar(
                    select(UserExtension).where(UserExtension.user_id == by_email[email_a].id)
                )
                extension_b = await session.scalar(
                    select(UserExtension).where(UserExtension.user_id == by_email[email_b].id)
                )
                assert extension_a is not None and extension_b is not None
                assert extension_a.display_name is None
                assert extension_b.display_name == shared_name
                assert list(await session.scalars(select(ExternalCallAttempt.id))) == []
