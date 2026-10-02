"""Credential safety failures preserve owner, supplier and deployment versions."""

from datetime import UTC, datetime, timedelta
from typing import cast
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from cryptography.fernet import Fernet
from fastapi import Request
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import model_settings as routes
from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import AuthSession, User, UserExtension
from app.models.model_tasks import (
    Job,
    JobStage,
    ModelCatalogEntry,
    ModelLimitPolicy,
    ProviderCredential,
    UserRuntimeLimit,
)
from app.schemas.model_settings import (
    CatalogUpdate,
    CredentialRotate,
    LimitsUpdate,
    ModelBinding,
    ModelBindings,
    ModelLimits,
    ModelSettingsUpdate,
    UserLimitDelete,
    UserLimitUpdate,
)
from app.services import model_configuration as service
from app.services.credential_crypto import CredentialCrypto


def scope() -> ScopeContext:
    return ScopeContext(uuid4(), uuid4(), "client", "web", 1, 1, 1, datetime.now(UTC))


def session_mock() -> tuple[AsyncSession, AsyncMock]:
    mock = AsyncMock(spec=AsyncSession)
    return cast(AsyncSession, mock), mock


@pytest.mark.asyncio
@pytest.mark.parametrize("age", [None, -1, 301])
async def test_sensitive_authorization_rejects_missing_future_or_old_reauthentication(
    age: int | None,
) -> None:
    session, mock = session_mock()
    row = AuthSession(
        reauthenticated_at=None if age is None else datetime.now(UTC) - timedelta(seconds=age)
    )
    mock.scalar.side_effect = [None, row]
    current = scope()
    with (
        patch.object(service, "verify_scope_in_transaction", new_callable=AsyncMock) as verify,
        pytest.raises(AppError) as error,
    ):
        await service.authorize(session, current, ("client.credential.manage",), sensitive=True)
    assert error.value.code == ErrorCode.REAUTHENTICATION_REQUIRED
    assert verify.await_args is not None
    assert verify.await_args.kwargs["user_id"] == current.user_id
    assert verify.await_args.kwargs["lock_user"] is True


@pytest.mark.asyncio
@pytest.mark.parametrize("row", [None, ProviderCredential(status="revoked")])
async def test_absent_or_revoked_credential_never_becomes_active(
    row: ProviderCredential | None,
) -> None:
    session, mock = session_mock()
    owner, identifier = uuid4(), uuid4()
    mock.scalar.return_value = row
    with pytest.raises(AppError) as error:
        await service.credential(session, owner, identifier, lock=True, active=True)
    assert error.value.code == ErrorCode.RESOURCE_NOT_FOUND
    query = mock.scalar.call_args.args[0]
    parameters = query.compile().params
    assert owner in parameters.values() and identifier in parameters.values()
    assert query._for_update_arg is not None


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "enabled,capabilities,adapter,voice",
    [
        (False, ["text"], None, None),
        (True, ["vision"], None, None),
        (True, ["tts"], None, "Kore"),
        (True, ["tts"], "openrouter-gemini-speech-v1", "Other"),
    ],
)
async def test_catalog_rejects_disabled_missing_capability_or_unverified_adapter(
    enabled: bool,
    capabilities: list[str],
    adapter: str | None,
    voice: str | None,
) -> None:
    session, _ = session_mock()
    row = ModelCatalogEntry(
        provider="openrouter",
        model_code="exact",
        enabled=enabled,
        capabilities=capabilities,
        adapter_id=adapter,
    )
    with (
        patch.object(service, "published_catalog", new_callable=AsyncMock, return_value=[row]),
        pytest.raises(AppError) as error,
    ):
        await service.require_model(
            session, "openrouter", "exact", "tts" if voice else "text", voice
        )
    assert error.value.code == ErrorCode.CAPABILITY_UNSUPPORTED


@pytest.mark.asyncio
async def test_settings_provider_mismatch_does_not_delete_existing_bindings() -> None:
    session, mock = session_mock()
    current = scope()
    mock.scalar.side_effect = [
        UserExtension(settings_revision=4),
        ProviderCredential(provider="gemini", status="active"),
    ]
    payload = ModelSettingsUpdate(
        expected_revision=4,
        bindings=ModelBindings(
            text=ModelBinding(
                credential_id=uuid4(), provider="openrouter", model_id=service.TEXT_MODEL
            )
        ),
    )
    with (
        patch.object(service, "authorize", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await service.update_model_settings(session, current, payload)
    assert error.value.code == ErrorCode.INPUT_INVALID
    mock.execute.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "expected_revision,expected_key,encrypted,code",
    [
        (2, "old", b"cipher", ErrorCode.REVISION_CONFLICT),
        (3, "wrong", b"cipher", ErrorCode.STATE_CONFLICT),
        (3, "old", None, ErrorCode.KEY_REQUIRED),
    ],
)
async def test_reencryption_fences_revision_keyring_and_absent_key(
    expected_revision: int,
    expected_key: str,
    encrypted: bytes | None,
    code: ErrorCode,
) -> None:
    session, mock = session_mock()
    owner, identifier = uuid4(), uuid4()
    row = ProviderCredential(
        id=identifier,
        owner_user_id=owner,
        status="active",
        revision=3,
        credential_version=7,
        encryption_key_version="old",
        encrypted_key=encrypted,
    )
    mock.scalar.return_value = row
    runtime = Runtime(
        Settings(
            app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
        )
    )
    with pytest.raises(AppError) as error:
        await service.reencrypt_credential(
            session, runtime, identifier, owner, expected_revision, expected_key
        )
    assert error.value.code == code
    assert row.revision == 3 and row.credential_version == 7
    assert row.encrypted_key == encrypted


@pytest.mark.asyncio
async def test_reencryption_preserves_supplier_version_and_secret() -> None:
    owner, identifier = uuid4(), uuid4()
    old, new = SecretStr(Fernet.generate_key().decode()), SecretStr(Fernet.generate_key().decode())
    settings = Settings(
        app_env="test",
        instance_id="haruka-test-model",
        public_base_url="http://127.0.0.1:8080",
        credential_keyring={"old": old, "new": new},
        credential_encryption_key_version="new",
    )
    crypto = CredentialCrypto(
        settings.model_copy(update={"credential_encryption_key_version": "old"})
    )
    secret = SecretStr("synthetic-secret")
    row = ProviderCredential(
        id=identifier,
        owner_user_id=owner,
        status="active",
        revision=3,
        credential_version=7,
        encryption_key_version="old",
        encrypted_key=crypto.encrypt(owner, identifier, 7, secret),
    )
    session, mock = session_mock()
    mock.scalar.return_value = row
    await service.reencrypt_credential(session, Runtime(settings), identifier, owner, 3, "old")
    assert row.revision == 4 and row.credential_version == 7 and row.encryption_key_version == "new"
    assert row.encrypted_key is not None
    assert (
        CredentialCrypto(settings).decrypt(owner, identifier, 7, "new", row.encrypted_key) == secret
    )


@pytest.mark.asyncio
async def test_rotation_updates_key_version_and_blocks_waiting_old_key_tasks() -> None:
    from app.models.model_tasks import Job

    current = scope()
    session, mock = session_mock()
    now = datetime.now(UTC)
    row = ProviderCredential(
        id=uuid4(),
        owner_user_id=current.user_id,
        provider="openrouter",
        label="original",
        masked_key="masked",
        revision=3,
        credential_version=7,
        status="active",
        encryption_key_version="v1",
        encrypted_key=b"previous",
        created_at=now,
        updated_at=now,
    )
    waiting = Job(state="queued", revision=2, progress_seq=1)
    mock.scalar.return_value = row
    mock.scalars.return_value = [waiting]
    settings = Settings(
        app_env="test",
        instance_id="haruka-test-model",
        public_base_url="http://127.0.0.1:8080",
        credential_keyring={"v1": SecretStr(Fernet.generate_key().decode())},
    )
    payload = CredentialRotate(
        expected_revision=3, key=SecretStr("synthetic-new-secret"), label="replacement"
    )
    with (
        patch.object(service, "authorize", new_callable=AsyncMock),
        patch.object(service, "audit", new_callable=AsyncMock),
    ):
        result = await service.rotate_credential(
            session, Runtime(settings), current, row.id, payload
        )
    assert result.revision == 4 and result.credential_version == 8 and result.label == "replacement"
    assert row.encrypted_key is not None
    assert (
        CredentialCrypto(settings).decrypt(current.user_id, row.id, 8, "v1", row.encrypted_key)
        == payload.key
    )
    assert waiting.state == "blocked" and waiting.error_code == "KEY_REQUIRED"
    assert waiting.revision == 3 and waiting.progress_seq == 2


@pytest.mark.asyncio
async def test_delete_erases_ciphertext_and_unbinds_only_affected_capability() -> None:
    current = scope()
    session, mock = session_mock()
    now = datetime.now(UTC)
    row = ProviderCredential(
        id=uuid4(),
        owner_user_id=current.user_id,
        provider="openrouter",
        label="original",
        masked_key="masked",
        revision=3,
        credential_version=7,
        status="active",
        encryption_key_version="v1",
        encrypted_key=b"previous",
        created_at=now,
        updated_at=now,
    )
    extension = UserExtension(settings_revision=5)
    bindings = ModelBindings(
        text=ModelBinding(credential_id=row.id, provider="openrouter", model_id=service.TEXT_MODEL),
        vision=ModelBinding(
            credential_id=uuid4(), provider="openrouter", model_id=service.TEXT_MODEL
        ),
    )
    mock.scalar.side_effect = [extension, row]
    mock.scalars.return_value = []
    with (
        patch.object(service, "authorize", new_callable=AsyncMock),
        patch.object(service, "audit", new_callable=AsyncMock),
        patch.object(service, "load_bindings", new_callable=AsyncMock, return_value=bindings),
    ):
        result = await service.delete_credential(session, current, row.id, 3)
    assert result.status == "revoked" and result.credential_version == 8 and result.revision == 4
    assert row.encrypted_key is None and row.revoked_at is not None
    assert bindings.text is None and bindings.vision is not None
    assert extension.settings_revision == 6
    mock.execute.assert_awaited_once()


def route_fixture() -> tuple[Request, Runtime, AsyncMock, ScopeContext]:
    session, mock = session_mock()
    mock.__aenter__.return_value = session
    resources = MagicMock(spec=Resources)
    resources.database = MagicMock()
    resources.database.sessions.return_value = session
    runtime = Runtime(
        Settings(
            app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
        ),
        resources=cast(Resources, resources),
    )
    current = scope()
    request = Request({"type": "http", "headers": [], "state": {"request_id": uuid4()}})
    return request, runtime, mock, current


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "provider,exists,expected,code",
    [
        ("gemini", True, 3, ErrorCode.CAPABILITY_UNSUPPORTED),
        ("openrouter", False, 3, ErrorCode.RESOURCE_NOT_FOUND),
        ("openrouter", True, 2, ErrorCode.REVISION_CONFLICT),
    ],
)
async def test_admin_catalog_cannot_enable_unverified_provider_or_overwrite_new_revision(
    provider: str,
    exists: bool,
    expected: int,
    code: ErrorCode,
) -> None:
    request, runtime, mock, current = route_fixture()
    row = ModelCatalogEntry(id=uuid4(), provider=provider, enabled=False, revision=3)
    mock.scalar.return_value = row if exists else None
    with (
        patch.object(
            routes, "context", new_callable=AsyncMock, return_value=(runtime, current)
        ) as context,
        patch.object(routes, "verify_admin_write", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_policy", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await routes.admin_catalog_update(
            request, row.id, CatalogUpdate(expected_revision=expected, enabled=True)
        )
    assert error.value.code == code
    assert row.enabled is False and row.revision == 3
    mock.add.assert_not_called()
    assert context.await_args is not None
    assert context.await_args.kwargs == {"write": True, "admin": True}


@pytest.mark.asyncio
@pytest.mark.parametrize("exists,expected", [(False, 0), (True, 4)])
async def test_admin_user_limit_create_and_update_only_user_override(
    exists: bool, expected: int
) -> None:
    request, runtime, mock, current = route_fixture()
    target = uuid4()
    row = UserRuntimeLimit(id=uuid4(), owner_user_id=target, value_limit=1, revision=4)
    mock.scalar.side_effect = [User(id=target), row if exists else None]
    with (
        patch.object(routes, "context", new_callable=AsyncMock, return_value=(runtime, current)),
        patch.object(routes, "verify_admin_write", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_policy", new_callable=AsyncMock),
        patch.object(routes.config, "audit", new_callable=AsyncMock),
    ):
        result = await routes.user_limit_update(
            request, target, UserLimitUpdate(expected_revision=expected, max_concurrent_jobs=0)
        )
    assert result.data.user_id == target and result.data.max_concurrent_jobs == 0
    assert result.data.scope == "user_override" and result.data.revision == (5 if exists else 1)
    assert mock.add.call_count == (0 if exists else 1)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "exists,expected,code",
    [(False, 4, ErrorCode.RESOURCE_NOT_FOUND), (True, 3, ErrorCode.REVISION_CONFLICT)],
)
async def test_admin_user_limit_delete_missing_or_stale_does_not_remove_override(
    exists: bool,
    expected: int,
    code: ErrorCode,
) -> None:
    request, runtime, mock, current = route_fixture()
    row = UserRuntimeLimit(id=uuid4(), owner_user_id=uuid4(), value_limit=0, revision=4)
    mock.scalar.return_value = row if exists else None
    with (
        patch.object(routes, "context", new_callable=AsyncMock, return_value=(runtime, current)),
        patch.object(routes, "verify_admin_write", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_policy", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await routes.user_limit_delete(
            request, row.owner_user_id, UserLimitDelete(expected_revision=expected)
        )
    assert error.value.code == code
    mock.delete.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("missing,expected", [(True, 4), (False, 3)])
async def test_settings_missing_profile_or_conflicting_revision_keeps_bindings(
    missing: bool,
    expected: int,
) -> None:
    session, mock = session_mock()
    mock.scalar.return_value = None if missing else UserExtension(settings_revision=4)
    with (
        patch.object(service, "authorize", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await service.update_model_settings(
            session,
            scope(),
            ModelSettingsUpdate(expected_revision=expected, bindings=ModelBindings()),
        )
    assert error.value.code == (
        ErrorCode.SERVICE_UNAVAILABLE if missing else ErrorCode.REVISION_CONFLICT
    )
    mock.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_settings_replace_bindings_in_current_owner_scope_with_single_revision() -> None:
    session, mock = session_mock()
    current = scope()
    extension = UserExtension(settings_revision=4)
    credential = ProviderCredential(provider="openrouter", status="active")
    mock.scalar.side_effect = [extension, credential]
    payload = ModelSettingsUpdate(
        expected_revision=4,
        bindings=ModelBindings(
            tts=ModelBinding(
                credential_id=uuid4(),
                provider="openrouter",
                model_id=service.TTS_MODEL,
                voice_id="Kore",
            )
        ),
    )
    with (
        patch.object(service, "authorize", new_callable=AsyncMock),
        patch.object(service, "require_model", new_callable=AsyncMock) as catalog,
    ):
        result = await service.update_model_settings(session, current, payload)
    assert result.revision == 5 and result.bindings == payload.bindings
    assert catalog.await_args is not None and catalog.await_args.args[3:] == ("tts", "Kore")
    added = mock.add.call_args.args[0]
    assert added.user_id == current.user_id and added.capability == "tts"
    assert added.parameters == {"voice_id": "Kore", "language_tag": "ja", "output_format": "mp3"}
    assert current.user_id in mock.execute.call_args.args[0].compile().params.values()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "retry,state,committed",
    [(False, "succeeded", False), (True, "failed", True), (True, "blocked", False)],
)
async def test_admin_job_actions_cannot_restart_supplier_work_or_cancel_terminal_state(
    retry: bool,
    state: str,
    committed: bool,
) -> None:
    request, runtime, mock, current = route_fixture()
    row = Job(id=uuid4(), state=state, revision=4, generation=2)
    stage = JobStage(
        state="committed" if committed else "running", result_refs={"attempt_id": str(uuid4())}
    )
    mock.scalar.side_effect = [row, stage]
    with (
        patch.object(routes, "context", new_callable=AsyncMock, return_value=(runtime, current)),
        patch.object(routes, "verify_admin_write", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_policy", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_job_owner", new_callable=AsyncMock),
        patch.object(routes.tasks, "emit", new_callable=AsyncMock) as emit,
        pytest.raises(AppError) as error,
    ):
        await routes.admin_job_action(request, row.id, 4, retry=retry)
    assert error.value.code == ErrorCode.STATE_CONFLICT
    assert row.state == state and row.revision == 4 and row.generation == 2
    emit.assert_not_awaited()


@pytest.mark.asyncio
async def test_admin_retry_resumes_committed_publication_without_new_generation() -> None:
    request, runtime, mock, current = route_fixture()
    now = datetime.now(UTC)
    row = Job(
        id=uuid4(),
        operation_kind="credential_test",
        state="blocked",
        revision=4,
        generation=2,
        progress_seq=3,
        created_at=now,
        updated_at=now,
    )
    stage = JobStage(state="committed", result_refs={"attempt_id": str(uuid4())})
    mock.scalar.side_effect = [row, stage]
    with (
        patch.object(routes, "context", new_callable=AsyncMock, return_value=(runtime, current)),
        patch.object(routes, "verify_admin_write", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_policy", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_job_owner", new_callable=AsyncMock),
        patch.object(routes.tasks, "emit", new_callable=AsyncMock) as emit,
        patch.object(routes.config, "audit", new_callable=AsyncMock),
    ):
        result = await routes.admin_job_action(request, row.id, 4, retry=True)
    assert result.state == "queued" and result.revision == 5 and result.sequence == 4
    assert row.generation == 2 and stage.state == "committed"
    emit.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("enabled", [True, False])
async def test_admin_limits_update_enforces_reduction_and_disabled_effective_limits(
    enabled: bool,
) -> None:
    request, runtime, mock, current = route_fixture()
    rows = [
        ModelLimitPolicy(
            id=uuid4(), limit_code="max_credentials", value_limit=8, enabled=True, revision=4
        ),
        ModelLimitPolicy(
            id=uuid4(), limit_code="timeout_seconds", value_limit=60, enabled=True, revision=4
        ),
    ]
    mock.scalars.side_effect = [rows, rows, rows]
    payload = LimitsUpdate(
        expected_revision=4,
        limits=ModelLimits(max_credentials=2, timeout_seconds=10, enabled=enabled),
    )
    with (
        patch.object(routes, "context", new_callable=AsyncMock, return_value=(runtime, current)),
        patch.object(routes, "verify_admin_write", new_callable=AsyncMock),
        patch.object(routes.tasks, "lock_policy", new_callable=AsyncMock),
        patch.object(routes.config, "audit", new_callable=AsyncMock) as audit,
    ):
        result = await routes.admin_limits_update(request, payload)
    assert result.data.revision == 5 and result.data.enabled == enabled
    assert result.data.max_credentials == (2 if enabled else 0)
    assert result.data.timeout_seconds == (10 if enabled else 0)
    assert all(row.revision == 5 and row.updated_at is not None for row in rows)
    audit.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "capability", ["text", "vision", "tts", "missing-catalog", "missing-profile"]
)
async def test_read_settings_uses_owned_persisted_binding_and_fails_closed_on_missing_parent(
    capability: str,
) -> None:
    from app.models.model_tasks import UserModelBinding

    session, mock = session_mock()
    current = scope()
    catalog = ModelCatalogEntry(
        id=uuid4(),
        provider="openrouter",
        model_code=service.TTS_MODEL if capability == "tts" else service.TEXT_MODEL,
    )
    binding = UserModelBinding(
        user_id=current.user_id,
        capability=capability if capability in {"text", "vision", "tts"} else "text",
        credential_id=uuid4(),
        model_catalog_entry_id=catalog.id,
        parameters_schema_version=1,
        parameters={"voice_id": "Kore"} if capability == "tts" else {},
    )
    mock.scalar.return_value = (
        None if capability == "missing-profile" else UserExtension(settings_revision=4)
    )
    mock.scalars.return_value = [binding]
    with (
        patch.object(service, "authorize", new_callable=AsyncMock) as authorize,
        patch.object(
            service,
            "published_catalog",
            new_callable=AsyncMock,
            return_value=[] if capability == "missing-catalog" else [catalog],
        ),
    ):
        if capability.startswith("missing"):
            with pytest.raises(AppError) as error:
                await service.read_model_settings(session, current)
            assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
        else:
            result = await service.read_model_settings(session, current)
            selected = cast(ModelBinding, getattr(result.bindings, capability))
            assert result.revision == 4 and selected.credential_id == binding.credential_id
            assert selected.provider == "openrouter" and selected.model_id == catalog.model_code
            assert selected.voice_id == ("Kore" if capability == "tts" else None)
            assert (
                sum(
                    getattr(result.bindings, name) is not None for name in ("text", "vision", "tts")
                )
                == 1
            )
    authorize.assert_awaited_once_with(session, current, ("client.profile.read",))
    assert current.user_id in mock.scalar.await_args.args[0].compile().params.values()
    if capability != "missing-profile":
        assert current.user_id in mock.scalars.await_args.args[0].compile().params.values()
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("has_profile,matching", [(False, False), (True, False), (True, True)])
async def test_credential_delete_preview_counts_only_current_owner_jobs_and_bound_capabilities(
    has_profile: bool, matching: bool
) -> None:
    session, mock = session_mock()
    current = scope()
    target = uuid4()
    credential = ProviderCredential(id=target, revision=3)
    mock.scalar.side_effect = [UserExtension(settings_revision=4) if has_profile else None, 2]
    bindings = ModelBindings(
        text=ModelBinding(
            credential_id=target if matching else uuid4(),
            provider="openrouter",
            model_id=service.TEXT_MODEL,
        ),
        vision=None,
        tts=None,
    )
    with (
        patch.object(service, "authorize", new_callable=AsyncMock),
        patch.object(
            service, "credential", new_callable=AsyncMock, return_value=credential
        ) as owned,
        patch.object(
            service, "load_bindings", new_callable=AsyncMock, return_value=bindings
        ) as load,
    ):
        result = await service.deletion_impact(session, current, target)
    owned.assert_awaited_once_with(session, current.user_id, target)
    assert result.revision == 3 and result.unfinished_job_count == 2
    assert result.bound_capabilities == (["text"] if has_profile and matching else [])
    if has_profile:
        load.assert_awaited_once_with(session, current.user_id)
    else:
        load.assert_not_awaited()
    statement = mock.scalar.await_args.args[0]
    assert (
        current.user_id in statement.compile().params.values()
        and target in statement.compile().params.values()
    )
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("exists", [False, True])
@pytest.mark.parametrize("action", ["credential.created", "model_limits.updated"])
async def test_model_audit_requires_persistent_authorization_revision_and_safe_target(
    exists: bool, action: str
) -> None:
    from app.models import AuthorizationRevision

    session, mock = session_mock()
    current = scope()
    target = uuid4()
    mock.scalar.return_value = AuthorizationRevision(revision=7) if exists else None
    if exists:
        await service.audit(session, current, action, target)
        record = mock.add.call_args.args[0]
        assert record.actor_user_id == current.user_id and record.target_id == target
        assert record.authorization_revision == 7 and record.result == "committed"
        assert record.target_type == (
            "credential" if action.startswith("credential") else "model_policy"
        )
        assert record.audience == current.audience
    else:
        with pytest.raises(AppError) as error:
            await service.audit(session, current, action, target)
        assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
        mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("limit,count", [(0, 0), (10, 10), (10, 0)])
async def test_credential_registration_enforces_current_count_and_publishes_only_owner_encrypted_key(
    limit: int, count: int
) -> None:
    from app.models import AuthorizationRevision
    from app.schemas.model_settings import CredentialCreate

    session, mock = session_mock()
    current = scope()
    runtime = Runtime(
        Settings(
            app_env="test",
            instance_id="haruka-test-model",
            public_base_url="http://127.0.0.1:8080",
            credential_keyring={"v1": SecretStr(Fernet.generate_key().decode())},
        )
    )
    mock.scalar.side_effect = [count, AuthorizationRevision(revision=7)]

    async def flush() -> None:
        for call in mock.add.call_args_list:
            row = call.args[0]
            if isinstance(row, ProviderCredential):
                row.created_at = row.updated_at = datetime.now(UTC)

    mock.flush.side_effect = flush
    payload = CredentialCreate(
        provider="openrouter", label="Personal", key=SecretStr("synthetic-fixture-key-1234")
    )
    with (
        patch.object(service, "authorize", new_callable=AsyncMock) as authorize,
        patch.object(
            service,
            "effective_limits",
            new_callable=AsyncMock,
            return_value=ModelLimits(max_credentials=limit),
        ),
    ):
        if count >= limit:
            with pytest.raises(AppError) as error:
                await service.add_credential(session, runtime, current, payload)
            assert error.value.code == ErrorCode.QUOTA_EXCEEDED
            mock.add.assert_not_called()
            mock.flush.assert_not_awaited()
        else:
            result = await service.add_credential(session, runtime, current, payload)
            row = mock.add.call_args_list[0].args[0]
            assert isinstance(row, ProviderCredential) and row.owner_user_id == current.user_id
            assert row.credential_version == 1 and row.encryption_key_version == "v1"
            assert (
                row.encrypted_key is not None and b"synthetic-fixture-key" not in row.encrypted_key
            )
            assert (
                CredentialCrypto(runtime.settings).decrypt(
                    current.user_id, row.id, 1, "v1", row.encrypted_key
                )
                == payload.key
            )
            assert (
                result.masked_key == "••••1234"
                and "synthetic-fixture-key" not in result.model_dump_json()
            )
            audit = mock.add.call_args_list[1].args[0]
            assert (
                audit.actor_user_id == current.user_id
                and audit.target_id == row.id
                and audit.authorization_revision == 7
            )
    authorize.assert_awaited_once_with(
        session, current, ("client.credential.manage",), sensitive=True
    )
    assert current.user_id in mock.scalar.await_args_list[0].args[0].compile().params.values()
