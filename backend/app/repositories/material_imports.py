"""Owner-scoped source parents and stable metadata catalog queries."""

from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.identity import Library
from app.models.learning_reference import Material
from app.models.material_imports import MaterialImport


async def library(session: AsyncSession, scope: ScopeContext, *, lock: bool = False) -> Library:
    query = select(Library).where(Library.owner_user_id == scope.user_id)
    result = await session.scalar(query.with_for_update() if lock else query)
    if result is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return result


async def owned[T: Material | MaterialImport](
    session: AsyncSession,
    scope: ScopeContext,
    model: type[T],
    identifier: UUID,
    *,
    lock: bool = False,
) -> T:
    query = select(model).where(model.id == identifier, model.owner_user_id == scope.user_id)
    result = await session.scalar(
        query.with_for_update().execution_options(populate_existing=True) if lock else query
    )
    if result is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if isinstance(result, Material) and result.deleted_at is not None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return result


async def material_page(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    limit: int,
    cursor: UUID | None,
    material_type: str | None,
    language: str | None,
    search: str | None,
) -> list[Material]:
    query = (
        select(Material)
        .join(Library, Library.id == Material.library_id)
        .where(
            Material.owner_user_id == scope.user_id,
            Library.owner_user_id == scope.user_id,
            Material.deleted_at.is_(None),
        )
    )
    if material_type is not None:
        query = query.where(Material.material_type == material_type)
    if language is not None:
        query = query.where(Material.language == language)
    if search:
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        query = query.where(Material.title.ilike("%" + escaped + "%", escape="\\"))
    if cursor is not None:
        # A retained tombstone still anchors ordering after a concurrent delete;
        # only the owner's immutable ordering fields participate in pagination.
        anchor = await session.scalar(
            select(Material)
            .join(Library, Library.id == Material.library_id)
            .where(
                Material.id == cursor,
                Material.owner_user_id == scope.user_id,
                Library.owner_user_id == scope.user_id,
            )
        )
        if anchor is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        query = query.where(
            or_(
                Material.created_at < anchor.created_at,
                (Material.created_at == anchor.created_at) & (Material.id < anchor.id),
            )
        )
    return list(
        await session.scalars(
            query.order_by(Material.created_at.desc(), Material.id.desc()).limit(limit + 1)
        )
    )
