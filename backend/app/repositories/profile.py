"""Owner profile rows. Callers lock the user before the extension."""

from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.identity_security import UserExtension, UserLanguage


async def extension(session: AsyncSession, user_id: UUID, *, lock: bool) -> UserExtension | None:
    statement = select(UserExtension).where(UserExtension.user_id == user_id)
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    return await session.scalar(statement)


async def languages(session: AsyncSession, user_id: UUID) -> list[UserLanguage]:
    rows = await session.scalars(
        select(UserLanguage)
        .where(UserLanguage.user_id == user_id)
        .order_by(UserLanguage.language_kind, UserLanguage.sort_order, UserLanguage.id)
    )
    return list(rows)


async def replace_kind(
    session: AsyncSession, user_id: UUID, kind: str, rows: list[UserLanguage]
) -> None:
    await session.execute(
        delete(UserLanguage).where(
            UserLanguage.user_id == user_id, UserLanguage.language_kind == kind
        )
    )
    await session.flush()
    session.add_all(rows)
