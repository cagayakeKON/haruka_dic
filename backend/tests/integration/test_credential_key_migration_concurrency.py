"""Real two-connection deployment encryption versus explicit owner rotation fences."""

import asyncio
from uuid import UUID

import pytest
from cryptography.fernet import Fernet
from pydantic import SecretStr
from sqlalchemy import func, select, text

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthPolicy, AuthSession
from app.models.model_tasks import ExternalCallAttempt, ProviderCredential
from app.schemas.model_settings import CredentialRotate
from app.services.auth_context import verify_scope_in_transaction
from app.services.credential_crypto import CredentialCrypto
from app.services.model_configuration import reencrypt_credential, rotate_credential
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


@pytest.mark.parametrize("maintenance_first", [True, False])
async def test_key_migration_and_owner_rotation_serialize_without_losing_secret(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], maintenance_first: bool
) -> None:
    runtime, maintenance, run_id = identity_runtime
    keyring = {
        "v1": SecretStr(Fernet.generate_key().decode()),
        "v2": SecretStr(Fernet.generate_key().decode()),
    }
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": keyring,
            "credential_encryption_key_version": "v1",
        }
    )
    assert runtime.resources is not None
    sessions = runtime.resources.database.sessions
    async with sessions() as setup, setup.begin():
        policy = await setup.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for client, headers in _owner(
        runtime, maintenance, f"keyrace-{run_id}@haruka.example.test"
    ):
        response = await client.post(
            "/api/v1/provider-credentials",
            json={"provider": "openrouter", "label": "race", "key": "synthetic-before"},
            headers=headers,
        )
        assert response.status_code == 201
        identifier = UUID(response.json()["data"]["id"])
        async with sessions() as setup:
            row = await setup.get(ProviderCredential, identifier)
            assert row is not None and row.encrypted_key is not None
            owner = row.owner_user_id
            archived = row.encrypted_key
            auth = await setup.scalar(
                select(AuthSession).where(
                    AuthSession.user_id == owner, AuthSession.revoked_at.is_(None)
                )
            )
            assert auth is not None
            scope = await verify_scope_in_transaction(
                setup, user_id=owner, session_id=auth.id, audience="client", transport="web"
            )
        old_crypto = CredentialCrypto(runtime.settings)
        runtime.settings = runtime.settings.model_copy(
            update={"credential_encryption_key_version": "v2"}
        )
        async with sessions() as first, sessions() as second:
            async with first.begin():
                pid_first = await first.scalar(text("SELECT pg_backend_pid()"))
                if maintenance_first:
                    await reencrypt_credential(first, runtime, identifier, owner, 1, "v1")
                else:
                    await rotate_credential(
                        first,
                        runtime,
                        scope,
                        identifier,
                        CredentialRotate(expected_revision=1, key=SecretStr("synthetic-after")),
                    )
                await first.flush()
                entered = asyncio.Event()

                async def competing(
                    entered: asyncio.Event, scope: ScopeContext, identifier: UUID, owner: UUID
                ) -> None:
                    async with second.begin():
                        entered.set()
                        if maintenance_first:
                            await rotate_credential(
                                second,
                                runtime,
                                scope,
                                identifier,
                                CredentialRotate(
                                    expected_revision=1, key=SecretStr("synthetic-after")
                                ),
                            )
                        else:
                            await reencrypt_credential(second, runtime, identifier, owner, 1, "v1")

                task = asyncio.create_task(competing(entered, scope, identifier, owner))
                await asyncio.wait_for(entered.wait(), 5)
                async with sessions() as observer:
                    blocked = 0
                    for _ in range(100):
                        blocked = await observer.scalar(
                            text(
                                "SELECT count(*) FROM pg_stat_activity WHERE :pid = ANY(pg_blocking_pids(pid))"
                            ),
                            {"pid": pid_first},
                        )
                        if blocked:
                            break
                        await asyncio.sleep(0.02)
                    assert blocked and not task.done(), (
                        "second physical connection must wait on first row fence"
                    )
            with pytest.raises(AppError) as conflict:
                await asyncio.wait_for(task, 5)
            assert conflict.value.code == ErrorCode.REVISION_CONFLICT
        if maintenance_first:
            changed = await client.patch(
                f"/api/v1/provider-credentials/{identifier}",
                json={"expected_revision": 2, "key": "synthetic-after"},
                headers=headers,
            )
            assert changed.status_code == 200
        async with sessions() as check:
            row = await check.get(ProviderCredential, identifier)
            assert row is not None and row.encrypted_key is not None
            assert row.credential_version == 2 and row.encryption_key_version == "v2"
            assert (
                CredentialCrypto(runtime.settings)
                .decrypt(owner, identifier, 2, "v2", row.encrypted_key)
                .get_secret_value()
                == "synthetic-after"
            )
            assert (
                old_crypto.decrypt(owner, identifier, 1, "v1", archived).get_secret_value()
                == "synthetic-before"
            )
            assert await check.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
