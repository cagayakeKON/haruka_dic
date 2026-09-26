"""Owner-scoped published source and collection SQL with shared parent locks."""

from typing import cast
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.identity import Library
from app.models.learning_reference import (
    Card,
    CollectionItem,
    IdempotencyRecord,
    Material,
    MaterialContentBlock,
    MaterialRevision,
    MaterialSourceUnit,
    NovelChapter,
    NovelChapterBlock,
    SourceResultBinding,
)
from app.schemas.learning_reference import NovelContentLocator


async def owned[
    T: Library
    | Material
    | MaterialRevision
    | MaterialSourceUnit
    | MaterialContentBlock
    | NovelChapter
    | NovelChapterBlock
    | Card
    | CollectionItem
](session: AsyncSession, scope: ScopeContext, model: type[T], entity_id: UUID, *, lock: bool) -> T:
    statement = select(model).where(model.id == entity_id, model.owner_user_id == scope.user_id)
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    entity = await session.scalar(statement)
    if entity is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return entity


async def material_page(
    session: AsyncSession, scope: ScopeContext, *, limit: int, anchor_id: UUID | None
) -> list[tuple[Material, MaterialRevision, NovelChapter]]:
    statement = (
        select(Material, MaterialRevision, NovelChapter)
        .join(
            Library, and_(Library.id == Material.library_id, Library.owner_user_id == scope.user_id)
        )
        .join(
            MaterialRevision,
            and_(
                MaterialRevision.id == Material.current_revision_id,
                MaterialRevision.owner_user_id == scope.user_id,
                MaterialRevision.library_id == Material.library_id,
                MaterialRevision.material_id == Material.id,
                MaterialRevision.input_delete_generation == Material.delete_generation,
            ),
        )
        .join(
            NovelChapter,
            and_(
                NovelChapter.material_revision_id == MaterialRevision.id,
                NovelChapter.owner_user_id == scope.user_id,
                NovelChapter.library_id == Material.library_id,
                NovelChapter.material_id == Material.id,
                NovelChapter.ordinal == 1,
            ),
        )
        .where(
            Material.owner_user_id == scope.user_id,
            Material.material_type == "novel",
            Material.deleted_at.is_(None),
            Material.source_status == "published",
            MaterialRevision.status == "published",
            MaterialRevision.structure_status == "readable",
        )
    )
    if anchor_id is not None:
        anchor = await owned(session, scope, Material, anchor_id, lock=False)
        statement = statement.where(
            or_(
                Material.created_at < anchor.created_at,
                and_(Material.created_at == anchor.created_at, Material.id < anchor.id),
            )
        )
    rows = (
        await session.execute(
            statement.order_by(Material.created_at.desc(), Material.id.desc()).limit(limit + 1)
        )
    ).all()
    return [cast("tuple[Material, MaterialRevision, NovelChapter]", tuple(row)) for row in rows]


async def chapter_mappings(
    session: AsyncSession, scope: ScopeContext, *, library_id: UUID, chapter_id: UUID
) -> list[NovelChapterBlock]:
    return list(
        (
            await session.scalars(
                select(NovelChapterBlock)
                .where(
                    NovelChapterBlock.owner_user_id == scope.user_id,
                    NovelChapterBlock.library_id == library_id,
                    NovelChapterBlock.chapter_id == chapter_id,
                )
                .order_by(NovelChapterBlock.ordinal)
                .limit(101)
            )
        ).all()
    )


async def binding_for_card_reference(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    locator: NovelContentLocator,
    library: Library,
    material: Material,
    revision: MaterialRevision,
    chapter: NovelChapter,
    block: MaterialContentBlock,
    mapping: NovelChapterBlock,
    card: Card,
    lock: bool,
) -> SourceResultBinding | None:
    statement = select(SourceResultBinding).where(
        SourceResultBinding.owner_user_id == scope.user_id,
        SourceResultBinding.library_id == library.id,
        SourceResultBinding.material_id == material.id,
        SourceResultBinding.material_revision_id == revision.id,
        SourceResultBinding.novel_chapter_id == chapter.id,
        SourceResultBinding.chapter_block_id == mapping.id,
        SourceResultBinding.content_block_id == block.id,
        SourceResultBinding.start_scalar == locator.spans[0].start,
        SourceResultBinding.end_scalar == locator.spans[0].end,
        SourceResultBinding.quote == locator.quote,
        SourceResultBinding.result_kind == "card",
        SourceResultBinding.result_id == card.id,
        SourceResultBinding.result_version == card.card_revision,
        SourceResultBinding.target_language == card.target_language,
        SourceResultBinding.explanation_language == card.explanation_language,
        SourceResultBinding.released_at.is_(None),
    )
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    return await session.scalar(statement)


async def latest_resolved_binding(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    locator: NovelContentLocator,
    material: Material,
    revision: MaterialRevision,
    chapter: NovelChapter,
    block: MaterialContentBlock,
    mapping: NovelChapterBlock,
    target_language: str,
    explanation_language: str,
) -> SourceResultBinding | None:
    return await session.scalar(
        select(SourceResultBinding)
        .where(
            SourceResultBinding.owner_user_id == scope.user_id,
            SourceResultBinding.library_id == material.library_id,
            SourceResultBinding.material_id == material.id,
            SourceResultBinding.material_revision_id == revision.id,
            SourceResultBinding.novel_chapter_id == chapter.id,
            SourceResultBinding.chapter_block_id == mapping.id,
            SourceResultBinding.content_block_id == block.id,
            SourceResultBinding.start_scalar == locator.spans[0].start,
            SourceResultBinding.end_scalar == locator.spans[0].end,
            SourceResultBinding.quote == locator.quote,
            SourceResultBinding.target_language == target_language,
            SourceResultBinding.explanation_language == explanation_language,
            SourceResultBinding.released_at.is_(None),
        )
        .order_by(SourceResultBinding.created_at.desc(), SourceResultBinding.id.desc())
        .limit(1)
    )


async def replay_receipt(
    session: AsyncSession, scope: ScopeContext, *, key_digest: bytes
) -> IdempotencyRecord | None:
    return await session.scalar(
        select(IdempotencyRecord)
        .where(
            IdempotencyRecord.owner_user_id == scope.user_id,
            IdempotencyRecord.audience == "client",
            IdempotencyRecord.action_code == "client.collection.create",
            IdempotencyRecord.key_digest == key_digest,
        )
        .with_for_update()
        .execution_options(populate_existing=True)
    )


async def existing_collection(
    session: AsyncSession, scope: ScopeContext, *, library_id: UUID, card: Card
) -> CollectionItem | None:
    return await session.scalar(
        select(CollectionItem)
        .where(
            CollectionItem.owner_user_id == scope.user_id,
            CollectionItem.library_id == library_id,
            CollectionItem.card_id == card.id,
            CollectionItem.card_revision == card.card_revision,
        )
        .with_for_update()
        .execution_options(populate_existing=True)
    )


async def collection_page(
    session: AsyncSession, scope: ScopeContext, *, limit: int, anchor_id: UUID | None
) -> list[CollectionItem]:
    statement = (
        select(CollectionItem)
        .join(
            Library,
            and_(Library.id == CollectionItem.library_id, Library.owner_user_id == scope.user_id),
        )
        .where(CollectionItem.owner_user_id == scope.user_id, CollectionItem.deleted_at.is_(None))
    )
    if anchor_id is not None:
        anchor = await owned(session, scope, CollectionItem, anchor_id, lock=False)
        statement = statement.where(
            or_(
                CollectionItem.created_at < anchor.created_at,
                and_(CollectionItem.created_at == anchor.created_at, CollectionItem.id < anchor.id),
            )
        )
    return list(
        (
            await session.scalars(
                statement.order_by(
                    CollectionItem.created_at.desc(), CollectionItem.id.desc()
                ).limit(limit + 1)
            )
        ).all()
    )


async def retire_receipt(
    session: AsyncSession, scope: ScopeContext, record: IdempotencyRecord
) -> None:
    if record.owner_user_id != scope.user_id or record.audience != scope.audience:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    await session.delete(record)
    await session.flush()


async def persist_collection_result(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    item: CollectionItem | None,
    receipt: IdempotencyRecord,
) -> None:
    if (
        scope.audience != "client"
        or receipt.owner_user_id != scope.user_id
        or receipt.audience != scope.audience
        or (
            item is not None
            and (item.owner_user_id != scope.user_id or item.library_id != receipt.library_id)
        )
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if item is not None:
        session.add(item)
    session.add(receipt)
    await session.flush()
