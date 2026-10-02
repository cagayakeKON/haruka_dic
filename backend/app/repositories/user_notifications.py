"""Scope-bound private receipt queries; transactions belong to the service."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.scope import ScopeContext
from app.models.user_notifications import UserNotification


async def unread_count(session: AsyncSession, scope: ScopeContext, library_id: UUID) -> int:
    return int(
        await session.scalar(
            select(func.count())
            .select_from(UserNotification)
            .where(
                UserNotification.owner_user_id == scope.user_id,
                UserNotification.library_id == library_id,
                UserNotification.read_at.is_(None),
            )
        )
        or 0
    )


async def page(
    session: AsyncSession,
    scope: ScopeContext,
    library_id: UUID,
    *,
    upper: int,
    unread_only: bool,
    limit: int,
    anchor_at: datetime | None,
    anchor_id: UUID | None,
) -> list[UserNotification]:
    query = select(UserNotification).where(
        UserNotification.owner_user_id == scope.user_id,
        UserNotification.library_id == library_id,
        UserNotification.sequence <= upper,
    )
    if unread_only:
        query = query.where(UserNotification.read_at.is_(None))
    if anchor_at is not None and anchor_id is not None:
        query = query.where(
            or_(
                UserNotification.created_at < anchor_at,
                (UserNotification.created_at == anchor_at) & (UserNotification.id < anchor_id),
            )
        )
    return list(
        await session.scalars(
            query.order_by(UserNotification.created_at.desc(), UserNotification.id.desc()).limit(
                limit + 1
            )
        )
    )


async def owned(
    session: AsyncSession, scope: ScopeContext, library_id: UUID, identifier: UUID
) -> UserNotification | None:
    return await session.scalar(
        select(UserNotification)
        .where(
            UserNotification.id == identifier,
            UserNotification.owner_user_id == scope.user_id,
            UserNotification.library_id == library_id,
        )
        .with_for_update()
        .execution_options(populate_existing=True)
    )


async def mark_snapshot(
    session: AsyncSession, scope: ScopeContext, library_id: UUID, *, upper: int, now: datetime
) -> int:
    changed = await session.scalars(
        update(UserNotification)
        .where(
            UserNotification.owner_user_id == scope.user_id,
            UserNotification.library_id == library_id,
            UserNotification.sequence <= upper,
            UserNotification.read_at.is_(None),
        )
        .values(read_at=now, updated_at=now, revision=UserNotification.revision + 1)
        .returning(UserNotification.id)
    )
    return len(list(changed))
