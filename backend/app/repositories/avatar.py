"""Avatar intent and file rows. Callers lock the user and extension first."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.avatar import FileObject, UploadIntent


async def intent(
    session: AsyncSession, user_id: UUID, intent_id: UUID, *, lock: bool
) -> UploadIntent | None:
    statement = select(UploadIntent).where(
        UploadIntent.id == intent_id,
        UploadIntent.user_id == user_id,
        UploadIntent.purpose == "avatar",
        UploadIntent.target_kind == "user_extension",
        UploadIntent.target_resource_id == user_id,
    )
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    return await session.scalar(statement)


async def file_object(
    session: AsyncSession, user_id: UUID, file_id: UUID, *, lock: bool
) -> FileObject | None:
    statement = select(FileObject).where(
        FileObject.id == file_id, FileObject.user_id == user_id, FileObject.purpose == "avatar"
    )
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    return await session.scalar(statement)
