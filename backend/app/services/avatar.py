"""Publish, replace, read and detach the owner's current avatar."""

from datetime import UTC, datetime, timedelta
from hashlib import sha256
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.avatar import FileObject, UploadIntent
from app.models.identity_security import UserExtension
from app.repositories import avatar as avatar_repository
from app.repositories import profile as profile_repository
from app.schemas.avatar import AvatarUploadIntentCreate, AvatarUploadIntentRead
from app.schemas.profile import ProfileRead
from app.services.auth_context import verify_scope_in_transaction
from app.services.avatar_image import (
    MAX_INPUT_BYTES,
    PROCESSOR_VERSION,
    VALIDATION_PROFILE,
    publish_avatar_bounded,
)
from app.services.profile_settings import read_profile

_READ = ("client.profile.read",)
_UPDATE = ("client.profile.read", "client.profile.avatar.update")
_INTENT_TTL = timedelta(minutes=15)
_GC_DELAY = timedelta(days=7)


async def create_intent(
    session: AsyncSession, scope: ScopeContext, payload: AvatarUploadIntentCreate
) -> AvatarUploadIntentRead:
    async with session.begin():
        extension = await _extension(session, scope, _UPDATE, lock=True)
        row = UploadIntent(
            user_id=scope.user_id,
            purpose="avatar",
            target_kind="user_extension",
            target_resource_id=extension.user_id,
            declared_format=payload.declared_format,
            expected_size_bytes=payload.expected_size_bytes,
            expected_sha256=bytes.fromhex(payload.expected_sha256),
            status="pending",
            expires_at=datetime.now(UTC) + _INTENT_TTL,
        )
        session.add(row)
        await session.flush()
        return AvatarUploadIntentRead(
            id=row.id,
            expires_at=row.expires_at,
            max_size_bytes=MAX_INPUT_BYTES,
            accepted_formats=["jpeg", "png", "webp"],
        )


async def complete_intent(
    session: AsyncSession,
    scope: ScopeContext,
    intent_id: UUID,
    expected_revision: int,
    raw: bytes,
) -> ProfileRead:
    digest = sha256(raw).digest()
    async with session.begin():
        intent = await _intent(session, scope, intent_id, lock=False)
        _match_bytes(intent, raw, digest)
        if intent.status == "completed":
            return await read_profile(session, scope)
        _expect_pending(intent)
        current = await profile_repository.extension(session, scope.user_id, lock=False)
        if current is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        if current.profile_revision != expected_revision:
            raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=current.profile_revision)
        declared = intent.declared_format
    published = await publish_avatar_bounded(raw, declared_format=declared)
    async with session.begin():
        extension = await _extension(session, scope, _UPDATE, lock=True)
        intent = await _intent(session, scope, intent_id, lock=True)
        _match_bytes(intent, raw, digest)
        if intent.status == "completed":
            return await read_profile(session, scope)
        _expect_pending(intent)
        if extension.profile_revision != expected_revision:
            raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=extension.profile_revision)
        asset = FileObject(
            user_id=scope.user_id,
            upload_intent_id=intent.id,
            purpose="avatar",
            media_type="image/jpeg",
            format_code="jpeg",
            size_bytes=len(published.content),
            sha256=published.sha256,
            validation_profile=VALIDATION_PROFILE,
            processor_version=PROCESSOR_VERSION,
            validated_at=datetime.now(UTC),
            pixel_width=published.width,
            pixel_height=published.width,
            retention_state="referenced",
            content=published.content,
        )
        session.add(asset)
        await session.flush()
        intent.file_object_id = asset.id
        intent.status = "completed"
        await _release(session, scope.user_id, extension.avatar_asset_id)
        extension.avatar_asset_id = asset.id
        extension.avatar_revision += 1
        extension.profile_revision += 1
        return await read_profile(session, scope)


async def delete_avatar(
    session: AsyncSession, scope: ScopeContext, expected_revision: int
) -> ProfileRead:
    async with session.begin():
        extension = await _extension(session, scope, _UPDATE, lock=True)
        if extension.profile_revision != expected_revision:
            raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=extension.profile_revision)
        if extension.avatar_asset_id is None:
            return await read_profile(session, scope)
        await _release(session, scope.user_id, extension.avatar_asset_id)
        extension.avatar_asset_id = None
        extension.avatar_revision += 1
        extension.profile_revision += 1
        return await read_profile(session, scope)


async def read_avatar(session: AsyncSession, scope: ScopeContext) -> bytes:
    extension = await _extension(session, scope, _READ, lock=False)
    if extension.avatar_asset_id is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    asset = await avatar_repository.file_object(
        session, scope.user_id, extension.avatar_asset_id, lock=False
    )
    if (
        asset is None
        or asset.purpose != "avatar"
        or asset.retention_state != "referenced"
        or asset.id != extension.avatar_asset_id
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return bytes(asset.content)


async def _extension(
    session: AsyncSession, scope: ScopeContext, permissions: tuple[str, ...], *, lock: bool
) -> UserExtension:
    await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience="client",
        transport=scope.transport,
        permissions=permissions,
        lock_user=lock,
    )
    extension = await profile_repository.extension(session, scope.user_id, lock=lock)
    if extension is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return extension


async def _intent(
    session: AsyncSession, scope: ScopeContext, intent_id: UUID, *, lock: bool
) -> UploadIntent:
    if lock:
        found = await avatar_repository.intent(session, scope.user_id, intent_id, lock=True)
    else:
        await verify_scope_in_transaction(
            session,
            user_id=scope.user_id,
            session_id=scope.session_id,
            audience="client",
            transport=scope.transport,
            permissions=_UPDATE,
            lock_user=False,
        )
        found = await avatar_repository.intent(session, scope.user_id, intent_id, lock=False)
    if found is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return found


def _match_bytes(intent: UploadIntent, raw: bytes, digest: bytes) -> None:
    if len(raw) > MAX_INPUT_BYTES or intent.expected_size_bytes > MAX_INPUT_BYTES:
        raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
    if len(raw) != intent.expected_size_bytes or digest != bytes(intent.expected_sha256):
        raise AppError(ErrorCode.INPUT_INVALID)


def _expect_pending(intent: UploadIntent) -> None:
    if intent.status != "pending" or intent.expires_at <= datetime.now(UTC):
        raise AppError(ErrorCode.STATE_CONFLICT)


async def _release(session: AsyncSession, user_id: UUID, file_id: UUID | None) -> None:
    if file_id is None:
        return
    previous = await avatar_repository.file_object(session, user_id, file_id, lock=True)
    if previous is not None and previous.retention_state == "referenced":
        previous.retention_state = "gc_pending"
        previous.gc_not_before_at = datetime.now(UTC) + _GC_DELAY
