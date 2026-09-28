"""Explicit, bounded avatar cleanup with owner and pointer lock rechecks."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select, union
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.avatar import FileObject, UploadIntent
from app.models.identity import User
from app.models.identity_security import UserExtension


async def collect_avatar_garbage(
    sessions: async_sessionmaker[AsyncSession],
    *,
    now: datetime | None = None,
    owner_limit: int = 100,
    row_limit_per_owner: int = 100,
) -> tuple[int, int]:
    """Remove expired pending intents and released files; never delete an active pointer."""
    if not 1 <= owner_limit <= 100 or not 1 <= row_limit_per_owner <= 100:
        raise ValueError("owner and row limits must be between 1 and 100")
    cutoff = now or datetime.now(UTC)
    async with sessions() as session:
        pending = select(UploadIntent.user_id).where(
            UploadIntent.status == "pending", UploadIntent.expires_at <= cutoff
        )
        released = select(FileObject.user_id).where(
            FileObject.retention_state == "gc_pending",
            FileObject.gc_not_before_at <= cutoff,
        )
        owners = list(
            (
                await session.scalars(
                    select(union(pending, released).subquery().c.user_id)
                    .order_by("user_id")
                    .limit(owner_limit)
                )
            ).all()
        )
    intents_removed = 0
    files_removed = 0
    for user_id in owners:
        removed_intents, removed_files = await _collect_owner(
            sessions, user_id, cutoff, row_limit_per_owner
        )
        intents_removed += removed_intents
        files_removed += removed_files
    return intents_removed, files_removed


async def _collect_owner(
    sessions: async_sessionmaker[AsyncSession],
    user_id: UUID,
    cutoff: datetime,
    row_limit: int,
) -> tuple[int, int]:
    async with sessions() as session, session.begin():
        user = await session.scalar(select(User).where(User.id == user_id).with_for_update())
        if user is None:
            return 0, 0
        extension = await session.scalar(
            select(UserExtension).where(UserExtension.user_id == user_id).with_for_update()
        )
        if extension is None:
            return 0, 0
        pending = list(
            (
                await session.scalars(
                    select(UploadIntent)
                    .where(
                        UploadIntent.user_id == user_id,
                        UploadIntent.status == "pending",
                        UploadIntent.expires_at <= cutoff,
                    )
                    .order_by(UploadIntent.id)
                    .limit(row_limit)
                    .with_for_update()
                )
            ).all()
        )
        for intent in pending:
            await session.delete(intent)
        released_intents = list(
            (
                await session.scalars(
                    select(UploadIntent)
                    .join(FileObject, FileObject.id == UploadIntent.file_object_id)
                    .where(
                        UploadIntent.user_id == user_id,
                        UploadIntent.status == "completed",
                        UploadIntent.file_object_id.is_not(None),
                        FileObject.user_id == user_id,
                        FileObject.retention_state == "gc_pending",
                        FileObject.gc_not_before_at <= cutoff,
                    )
                    .order_by(UploadIntent.id)
                    .limit(row_limit - len(pending))
                    .with_for_update(of=UploadIntent)
                )
            ).all()
        )
        removed_files = 0
        for intent in released_intents:
            if intent.file_object_id == extension.avatar_asset_id:
                continue
            file = await session.scalar(
                select(FileObject)
                .where(
                    FileObject.id == intent.file_object_id,
                    FileObject.user_id == user_id,
                    FileObject.retention_state == "gc_pending",
                    FileObject.gc_not_before_at <= cutoff,
                )
                .with_for_update()
            )
            if file is None:
                continue
            await session.delete(file)
            await session.delete(intent)
            removed_files += 1
        return len(pending) + removed_files, removed_files
