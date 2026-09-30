"""Credential/configuration ownership, CAS, recent identity and catalog limits."""

from datetime import UTC, datetime, timedelta
from typing import cast
from uuid import NAMESPACE_URL, UUID, uuid4, uuid5

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import AdminAuditEvent, AuthorizationRevision, AuthSession, User, UserExtension
from app.models.model_tasks import (
    Job,
    ModelCatalogEntry,
    ModelLimitPolicy,
    ProviderCredential,
    UserModelBinding,
    VoiceCatalogEntry,
)
from app.schemas.model_settings import (
    Capability,
    CredentialCreate,
    CredentialImpact,
    CredentialRead,
    CredentialRotate,
    ModelBinding,
    ModelBindings,
    ModelCapabilities,
    ModelEntry,
    ModelLimits,
    ModelSettingsRead,
    ModelSettingsUpdate,
    Provider,
    VoiceEntry,
)
from app.services.auth_context import verify_scope_in_transaction
from app.services.credential_crypto import CredentialCrypto

TEXT_MODEL = "google/gemini-2.5-flash"
TTS_MODEL = "google/gemini-3.8-flash-lite-tts"
_REGISTRY = (
    ("openrouter", TEXT_MODEL, ["text", "vision"], True, None),
    ("openrouter", TTS_MODEL, ["tts"], True, "openrouter-gemini-speech-v1"),
    ("gemini", "gemini-2.5-flash", ["text", "vision"], False, None),
)


def catalog_id(provider: str, model: str) -> UUID:
    return uuid5(NAMESPACE_URL, f"haruka:model:{provider}:{model}")


async def authorize(
    session: AsyncSession, scope: ScopeContext, codes: tuple[str, ...], *, sensitive: bool = False
) -> None:
    # Same lock order as account security; credential/config locks follow this.
    await session.scalar(select(User).where(User.id == scope.user_id).with_for_update())
    await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience=scope.audience,
        transport=scope.transport,
        permissions=codes,
        lock_user=True,
    )
    if sensitive:
        row = await session.scalar(
            select(AuthSession).where(AuthSession.id == scope.session_id).with_for_update()
        )
        now = datetime.now(UTC)
        if (
            row is None
            or row.reauthenticated_at is None
            or not timedelta(0) <= now - row.reauthenticated_at <= timedelta(minutes=5)
        ):
            raise AppError(ErrorCode.REAUTHENTICATION_REQUIRED)


def require_revision(actual: int, expected: int) -> None:
    if actual != expected:
        raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=actual)


async def credential(
    session: AsyncSession,
    owner: UUID,
    identifier: UUID,
    *,
    lock: bool = False,
    active: bool = False,
) -> ProviderCredential:
    query = select(ProviderCredential).where(
        ProviderCredential.id == identifier, ProviderCredential.owner_user_id == owner
    )
    if lock:
        query = query.with_for_update()
    row = await session.scalar(query)
    if row is None or (active and row.status != "active"):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return row


def credential_read(row: ProviderCredential) -> CredentialRead:
    return CredentialRead.model_validate(
        {name: getattr(row, name) for name in CredentialRead.model_fields}
    )


async def add_credential(
    session: AsyncSession, runtime: Runtime, scope: ScopeContext, payload: CredentialCreate
) -> CredentialRead:
    await authorize(session, scope, ("client.credential.manage",), sensitive=True)
    limits = await effective_limits(session)
    count = await session.scalar(
        select(func.count())
        .select_from(ProviderCredential)
        .where(
            ProviderCredential.owner_user_id == scope.user_id, ProviderCredential.status == "active"
        )
    )
    if (count or 0) >= limits.max_credentials:
        raise AppError(ErrorCode.QUOTA_EXCEEDED)
    identifier = uuid4()
    crypto = CredentialCrypto(runtime.settings)
    row = ProviderCredential(
        id=identifier,
        owner_user_id=scope.user_id,
        provider=payload.provider,
        label=payload.label,
        encrypted_key=crypto.encrypt(scope.user_id, identifier, 1, payload.key),
        encryption_key_version=crypto.version,
        masked_key="••••" + payload.key.get_secret_value()[-4:],
        credential_version=1,
        revision=1,
        status="active",
    )
    session.add(row)
    await session.flush()
    await audit(session, scope, "credential.created", row.id)
    return credential_read(row)


async def rotate_credential(
    session: AsyncSession,
    runtime: Runtime,
    scope: ScopeContext,
    identifier: UUID,
    payload: CredentialRotate,
) -> CredentialRead:
    await authorize(session, scope, ("client.credential.manage",), sensitive=True)
    row = await credential(session, scope.user_id, identifier, lock=True, active=True)
    require_revision(row.revision, payload.expected_revision)
    row.credential_version += 1
    row.revision += 1
    crypto = CredentialCrypto(runtime.settings)
    row.encrypted_key = crypto.encrypt(scope.user_id, row.id, row.credential_version, payload.key)
    row.encryption_key_version = crypto.version
    row.masked_key = "••••" + payload.key.get_secret_value()[-4:]
    if payload.label is not None:
        row.label = payload.label
    row.updated_at = datetime.now(UTC)
    await block_waiting(session, row)
    await audit(session, scope, "credential.rotated", row.id)
    return credential_read(row)


async def deletion_impact(
    session: AsyncSession, scope: ScopeContext, identifier: UUID
) -> CredentialImpact:
    await authorize(session, scope, ("client.credential.read",))
    row = await credential(session, scope.user_id, identifier)
    extension = await session.scalar(
        select(UserExtension).where(UserExtension.user_id == scope.user_id)
    )
    bound = []
    if extension:
        bindings = await load_bindings(session, scope.user_id)
        bound = [
            name
            for name in ("text", "vision", "tts")
            if (binding := getattr(bindings, name)) is not None
            and binding.credential_id == identifier
        ]
    count = await session.scalar(
        select(func.count())
        .select_from(Job)
        .where(
            Job.owner_user_id == scope.user_id,
            Job.credential_id == identifier,
            Job.state.in_(("queued", "running", "retry_wait", "blocked", "cancel_requested")),
        )
    )
    return CredentialImpact(
        credential_id=identifier,
        revision=row.revision,
        bound_capabilities=cast(list[Capability], bound),
        unfinished_job_count=count or 0,
    )


async def delete_credential(
    session: AsyncSession, scope: ScopeContext, identifier: UUID, revision: int
) -> CredentialRead:
    await authorize(session, scope, ("client.credential.manage",), sensitive=True)
    extension = await session.scalar(
        select(UserExtension).where(UserExtension.user_id == scope.user_id).with_for_update()
    )
    row = await credential(session, scope.user_id, identifier, lock=True)
    require_revision(row.revision, revision)
    row.status = "revoked"
    row.revoked_at = datetime.now(UTC)
    row.encrypted_key = None
    row.credential_version += 1
    row.revision += 1
    row.updated_at = datetime.now(UTC)
    if extension:
        bindings = await load_bindings(session, scope.user_id)
        changed = False
        for name in ("text", "vision", "tts"):
            binding = getattr(bindings, name)
            if binding is not None and binding.credential_id == identifier:
                setattr(bindings, name, None)
                changed = True
        if changed:
            await session.execute(
                delete(UserModelBinding).where(
                    UserModelBinding.user_id == scope.user_id,
                    UserModelBinding.credential_id == identifier,
                )
            )
            extension.settings_revision += 1
            extension.updated_at = datetime.now(UTC)
    await block_waiting(session, row)
    await audit(session, scope, "credential.deleted", row.id)
    return credential_read(row)


async def block_waiting(session: AsyncSession, row: ProviderCredential) -> None:
    rows = await session.scalars(
        select(Job)
        .where(
            Job.owner_user_id == row.owner_user_id,
            Job.credential_id == row.id,
            Job.state.in_(("queued", "retry_wait")),
        )
        .order_by(Job.id)
        .with_for_update()
    )
    for job in rows:
        job.state = "blocked"
        job.error_code = "KEY_REQUIRED"
        job.revision += 1
        job.progress_seq += 1
        job.updated_at = datetime.now(UTC)


async def published_catalog(
    session: AsyncSession, *, lock: bool = False
) -> list[ModelCatalogEntry]:
    return list(
        await session.scalars(
            select(ModelCatalogEntry).order_by(ModelCatalogEntry.id).with_for_update()
            if lock
            else select(ModelCatalogEntry).order_by(ModelCatalogEntry.id)
        )
    )


async def require_model(
    session: AsyncSession, provider: str, model_id: str, capability: str, voice: str | None = None
) -> ModelCatalogEntry:
    row = next(
        (
            item
            for item in await published_catalog(session, lock=True)
            if item.provider == provider and item.model_code == model_id
        ),
        None,
    )
    if (
        row is None
        or not row.enabled
        or capability not in row.capabilities
        or (
            capability == "tts"
            and (row.adapter_id != "openrouter-gemini-speech-v1" or voice != "Kore")
        )
    ):
        raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
    return row


async def effective_limits(session: AsyncSession) -> ModelLimits:
    rows = list(await session.scalars(select(ModelLimitPolicy)))
    values = ModelLimits().model_dump()
    for row in rows:
        if row.limit_code in values and isinstance(values[row.limit_code], int):
            values[row.limit_code] = (
                min(values[row.limit_code], row.value_limit) if row.enabled else 0
            )
    values["enabled"] = all(row.enabled for row in rows)
    values["revision"] = max([row.revision for row in rows] or [1])
    return ModelLimits.model_validate(values)


async def capabilities(session: AsyncSession) -> ModelCapabilities:
    rows = await published_catalog(session)
    voices = list(
        await session.scalars(select(VoiceCatalogEntry).where(VoiceCatalogEntry.enabled.is_(True)))
    )
    return ModelCapabilities(
        revision=max([row.revision for row in rows] or [1]),
        models=[
            ModelEntry(
                id=row.id,
                provider=cast(Provider, row.provider),
                model_id=row.model_code,
                display_name=row.display_name,
                capabilities=cast(list[Capability], row.capabilities),
                enabled=row.enabled,
                verified=row.verified_at is not None,
                revision=row.revision,
                adapter_id=row.adapter_id,
            )
            for row in rows
        ],
        voices=[
            VoiceEntry(
                model_id=model.model_code,
                provider=cast(Provider, model.provider),
                voice_id=voice.voice_code,
                language_tags=sorted(
                    {
                        entry.language_tag
                        for entry in voices
                        if entry.model_catalog_entry_id == voice.model_catalog_entry_id
                        and entry.voice_code == voice.voice_code
                    }
                ),
                display_name=voice.display_name,
                output_formats=["mp3"],
                verified=voice.verified_at is not None,
            )
            for voice in voices
            for model in rows
            if model.id == voice.model_catalog_entry_id
            and voice.id
            == min(
                entry.id
                for entry in voices
                if entry.model_catalog_entry_id == voice.model_catalog_entry_id
                and entry.voice_code == voice.voice_code
            )
        ],
        limits=await effective_limits(session),
    )


async def read_model_settings(session: AsyncSession, scope: ScopeContext) -> ModelSettingsRead:
    await authorize(session, scope, ("client.profile.read",))
    row = await session.scalar(select(UserExtension).where(UserExtension.user_id == scope.user_id))
    if row is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return ModelSettingsRead(
        revision=row.settings_revision, bindings=await load_bindings(session, scope.user_id)
    )


async def update_model_settings(
    session: AsyncSession, scope: ScopeContext, payload: ModelSettingsUpdate
) -> ModelSettingsRead:
    await authorize(session, scope, ("client.profile.read", "client.profile.update"))
    row = await session.scalar(
        select(UserExtension).where(UserExtension.user_id == scope.user_id).with_for_update()
    )
    if row is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    require_revision(row.settings_revision, payload.expected_revision)
    for name in ("text", "vision", "tts"):
        binding: ModelBinding | None = getattr(payload.bindings, name)
        if binding:
            secret = await credential(
                session, scope.user_id, binding.credential_id, lock=True, active=True
            )
            if secret.provider != binding.provider:
                raise AppError(ErrorCode.INPUT_INVALID)
            await require_model(session, binding.provider, binding.model_id, name, binding.voice_id)
    await session.execute(delete(UserModelBinding).where(UserModelBinding.user_id == scope.user_id))
    for name in ("text", "vision", "tts"):
        binding = getattr(payload.bindings, name)
        if binding:
            session.add(
                UserModelBinding(
                    user_id=scope.user_id,
                    capability=name,
                    credential_id=binding.credential_id,
                    model_catalog_entry_id=catalog_id(binding.provider, binding.model_id),
                    parameters_schema_version=1,
                    parameters={
                        "voice_id": binding.voice_id,
                        "language_tag": binding.language_tag,
                        "output_format": binding.output_format,
                    },
                )
            )
    row.settings_revision += 1
    row.updated_at = datetime.now(UTC)
    return ModelSettingsRead(revision=row.settings_revision, bindings=payload.bindings)


async def load_bindings(session: AsyncSession, owner: UUID) -> ModelBindings:
    result = ModelBindings()
    catalog = {row.id: row for row in await published_catalog(session)}
    for row in await session.scalars(
        select(UserModelBinding).where(UserModelBinding.user_id == owner)
    ):
        model = catalog.get(row.model_catalog_entry_id)
        if model is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        setattr(
            result,
            row.capability,
            ModelBinding.model_validate(
                {
                    "credential_id": row.credential_id,
                    "provider": model.provider,
                    "model_id": model.model_code,
                    **row.parameters,
                }
            ),
        )
    return result


async def audit(session: AsyncSession, scope: ScopeContext, action: str, target: UUID) -> None:
    global_row = await session.scalar(
        select(AuthorizationRevision).where(AuthorizationRevision.code == "global")
    )
    if global_row is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    session.add(
        AdminAuditEvent(
            action=action,
            actor="authenticated-user",
            actor_user_id=scope.user_id,
            audience=scope.audience,
            target_type="credential" if action.startswith("credential") else "model_policy",
            target_id=target,
            authorization_revision=global_row.revision,
            payload_schema_version=1,
            result="committed",
        )
    )


async def reencrypt_credential(
    session: AsyncSession,
    runtime: Runtime,
    identifier: UUID,
    owner: UUID,
    expected_revision: int,
    expected_encryption_version: str,
) -> None:
    """Controlled maintenance only; preserves supplier version and never calls a model."""
    row = await credential(session, owner, identifier, lock=True, active=True)
    require_revision(row.revision, expected_revision)
    if row.encryption_key_version != expected_encryption_version:
        raise AppError(ErrorCode.STATE_CONFLICT)
    if row.encrypted_key is None:
        raise AppError(ErrorCode.KEY_REQUIRED)
    crypto = CredentialCrypto(runtime.settings)
    key = crypto.decrypt(
        owner, identifier, row.credential_version, row.encryption_key_version, row.encrypted_key
    )
    row.encrypted_key = crypto.encrypt(owner, identifier, row.credential_version, key)
    row.encryption_key_version = crypto.version
    row.revision += 1
    row.updated_at = datetime.now(UTC)
