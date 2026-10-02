"""Current-authority list/read actions and snapshot-bounded persistent read facts."""

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain import notification_tokens as tokens
from app.domain.correlation import current_log_context
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.learning_reference import Material
from app.models.user_notifications import UserNotification
from app.repositories import material_imports as materials
from app.repositories import user_notifications as repository
from app.schemas.user_notifications import NotificationsReadAllResult, UserNotificationRead
from app.services.auth_context import require_permissions, verify_scope_in_transaction
from app.services.auth_crypto import AuthCrypto

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class NotificationPage:
    items: list[UserNotificationRead]
    next_cursor: str | None
    unread_count: int
    snapshot_token: str
    snapshot_expires_at: datetime


async def consume_event(
    runtime: Runtime, event_id: UUID, envelope: dict[str, object] | None = None
) -> bool:
    # Broker/recovery uses the same public entry point; fixed system receipt
    # authority is separate from these current-user API actions.
    from app.services.notification_events import consume_event as consume

    return await consume(runtime, event_id, envelope)


async def verify(session: AsyncSession, scope: ScopeContext, *, write: bool) -> ScopeContext:
    return await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience=scope.audience,
        transport=scope.transport,
        permissions=("client.notification.read", "client.notification.update")
        if write
        else ("client.notification.read",),
        lock_user=True,
    )


async def project(
    session: AsyncSession, scope: ScopeContext, row: UserNotification
) -> UserNotificationRead:
    material = await session.scalar(
        select(Material).where(
            Material.id == row.resource_id,
            Material.owner_user_id == scope.user_id,
            Material.library_id == row.library_id,
            Material.deleted_at.is_(None),
        )
    )
    available = False
    if material is not None:
        codes = (
            ("client.material.read", "client.exam.read")
            if material.material_type == "exam"
            else ("client.material.read",)
        )
        try:
            await require_permissions(
                session, user_id=scope.user_id, audience="client", codes=codes
            )
        except AppError as error:
            if error.code != ErrorCode.PERMISSION_DENIED:
                raise
        else:
            source = await materials.source_revision(session, scope, material)
            available = source is not None and source.revision_number == row.resource_version
    return UserNotificationRead.model_validate(
        {
            "id": row.id,
            "notification_kind": row.notification_kind,
            "message_code": row.message_code if available else "notification.resource_unavailable",
            "schema_version": 1,
            "safe_parameters": {},
            "job_id": row.job_id,
            "resource_kind": "material",
            "resource_id": row.resource_id if available else None,
            "resource_version": row.resource_version if available else None,
            "resource_available": available,
            "route_key": "material" if available else None,
            "created_at": row.created_at,
            "read_at": row.read_at,
        }
    )


async def list_notifications(
    runtime: Runtime, scope: ScopeContext, *, unread_only: bool, limit: int, cursor: str | None
) -> NotificationPage:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    async with resources.database.sessions() as session, session.begin():
        current = await verify(session, scope, write=False)
        library = await materials.library(session, current, lock=True)
        now = datetime.now(UTC)
        if cursor is None:
            snapshot = tokens.initial_snapshot(
                instance=runtime.settings.instance_id,
                scope=current,
                library_id=library.id,
                upper=library.notification_sequence,
                now=now,
            )
            anchor_at = anchor_id = None
        else:
            boundary = tokens.decode(
                cursor,
                crypto.signing_key,
                purpose="cursor",
                instance=runtime.settings.instance_id,
                scope=current,
                library_id=library.id,
                now=now,
                unread_only=unread_only,
            )
            if boundary.upper > library.notification_sequence:
                raise AppError(ErrorCode.INPUT_INVALID)
            snapshot = tokens.snapshot_from(boundary)
            anchor_at, anchor_id = boundary.anchor_at, boundary.anchor_id
        rows = await repository.page(
            session,
            current,
            library.id,
            upper=snapshot.upper,
            unread_only=unread_only,
            limit=limit,
            anchor_at=anchor_at,
            anchor_id=anchor_id,
        )
        has_more = len(rows) > limit
        visible = rows[:limit]
        next_cursor = (
            tokens.encode(
                tokens.cursor_for(
                    snapshot,
                    unread_only=unread_only,
                    anchor_at=visible[-1].created_at,
                    anchor_id=visible[-1].id,
                ),
                crypto.signing_key,
            )
            if has_more
            else None
        )
        result = NotificationPage(
            items=[await project(session, current, row) for row in visible],
            next_cursor=next_cursor,
            unread_count=await repository.unread_count(session, current, library.id),
            snapshot_token=tokens.encode(snapshot, crypto.signing_key),
            snapshot_expires_at=snapshot.expiry(),
        )
    logger.info("notification.list.loaded", extra=current_log_context())
    return result


async def mark_read(
    runtime: Runtime, scope: ScopeContext, identifier: UUID
) -> UserNotificationRead:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session, session.begin():
        current = await verify(session, scope, write=True)
        library = await materials.library(session, current, lock=True)
        row = await repository.owned(session, current, library.id, identifier)
        if row is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        if row.read_at is None:
            row.read_at = row.updated_at = datetime.now(UTC)
            row.revision += 1
        result = await project(session, current, row)
    logger.info("notification.read.updated", extra=current_log_context())
    return result


async def mark_all_read(
    runtime: Runtime, scope: ScopeContext, snapshot_token: str
) -> NotificationsReadAllResult:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    async with resources.database.sessions() as session, session.begin():
        current = await verify(session, scope, write=True)
        library = await materials.library(session, current, lock=True)
        now = datetime.now(UTC)
        snapshot = tokens.decode(
            snapshot_token,
            crypto.signing_key,
            purpose="snapshot",
            instance=runtime.settings.instance_id,
            scope=current,
            library_id=library.id,
            now=now,
        )
        if snapshot.upper > library.notification_sequence:
            raise AppError(ErrorCode.INPUT_INVALID)
        changed = await repository.mark_snapshot(
            session, current, library.id, upper=snapshot.upper, now=now
        )
        result = NotificationsReadAllResult(
            changed_count=changed,
            unread_count=await repository.unread_count(session, current, library.id),
        )
    logger.info("notification.read_all.updated", extra=current_log_context())
    return result
