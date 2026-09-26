"""Authorized current slice published-source reads and persistent WordCard collections."""

from __future__ import annotations

import hashlib
import json
import logging
import re
from datetime import UTC, datetime, timedelta
from typing import Literal, cast
from uuid import UUID, uuid4

import regex
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
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
)
from app.repositories import learning_reference as repository
from app.schemas.learning_reference import (
    CollectionCreate,
    CollectionRead,
    ExplanationResolveRead,
    ExplanationResolveRequest,
    MaterialSummary,
    MissingCard,
    NovelBlockRead,
    NovelChapterRead,
    NovelContentLocator,
    ResolvedCard,
    SourceSpan,
    WordCardPayload,
    WordCardRead,
)
from app.services.auth_context import require_permissions, verify_scope_in_transaction

_LOG = logging.getLogger("haruka.learning")


async def _owned[
    T: Library
    | Material
    | MaterialRevision
    | MaterialSourceUnit
    | MaterialContentBlock
    | NovelChapter
    | NovelChapterBlock
    | Card
    | CollectionItem
](session: AsyncSession, model: type[T], entity_id: UUID, scope: ScopeContext, *, lock: bool) -> T:
    return await repository.owned(session, scope, model, entity_id, lock=lock)


def _uuid_cursor(value: str | None) -> UUID | None:
    if value is None:
        return None
    try:
        return UUID(value)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None


def _payload(card: Card) -> WordCardPayload:
    try:
        if card.card_kind != "word" or card.schema_version != 1 or card.card_revision < 1:
            raise ValueError("unsupported persisted card")
        return WordCardPayload.model_validate(card.payload)
    except (ValueError, ValidationError):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


def _source_refs(value: object) -> list[NovelContentLocator]:
    try:
        if not isinstance(value, list):
            raise ValueError("invalid source reference count")
        items = cast("list[object]", value)
        if not 1 <= len(items) <= 10:
            raise ValueError("invalid source reference count")
        return [NovelContentLocator.model_validate(item) for item in items]
    except (ValueError, ValidationError):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


def _language(value: str) -> Literal["ja", "en"]:
    if value not in {"ja", "en"}:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return cast("Literal['ja', 'en']", value)


def _valid_grapheme_span(value: str, start: int, end: int) -> bool:
    if not 0 <= start < end <= len(value) or len(value) > 10_000:
        return False
    boundaries = {0, len(value)}
    for cluster in regex.finditer(r"\X", value):
        boundaries.add(cluster.start())
        boundaries.add(cluster.end())
    return start in boundaries and end in boundaries


def _same_selection(left: NovelContentLocator, right: NovelContentLocator) -> bool:
    return (
        left.instance_id == right.instance_id
        and left.library_id == right.library_id
        and left.target_kind == right.target_kind
        and left.text_protocol_version == right.text_protocol_version
        and left.material_id == right.material_id
        and left.material_revision_id == right.material_revision_id
        and left.novel_chapter_id == right.novel_chapter_id
        and left.chapter_block_id == right.chapter_block_id
        and left.spans == right.spans
        and left.quote == right.quote
    )


def _card_read(card: Card) -> WordCardRead:
    return WordCardRead(
        card_id=card.id,
        card_revision=card.card_revision,
        target_language=_language(card.target_language),
        explanation_language=card.explanation_language,
        payload=_payload(card),
        source_refs=_source_refs(card.source_refs),
        created_at=card.created_at,
    )


def _collection_read(item: CollectionItem) -> CollectionRead:
    try:
        payload = WordCardPayload.model_validate(item.payload)
        refs = _source_refs(item.source_refs)
        return CollectionRead(
            id=item.id,
            revision=item.revision,
            card_id=item.card_id,
            card_revision=item.card_revision,
            display_text=item.display_text,
            target_language=_language(item.target_language),
            payload=payload,
            source_refs=refs,
            created_at=item.created_at,
        )
    except ValidationError:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def _source(
    session: AsyncSession,
    scope: ScopeContext,
    locator: NovelContentLocator,
    *,
    instance_id: str,
    lock: bool,
) -> tuple[
    Library, Material, MaterialRevision, NovelChapter, MaterialContentBlock, NovelChapterBlock
]:
    """Check every logical parent under the common root lock order."""
    if locator.instance_id != instance_id or locator.target_kind != "material_content":
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    library = await _owned(session, Library, locator.library_id, scope, lock=lock)
    material = await _owned(session, Material, locator.material_id, scope, lock=lock)
    if (
        material.library_id != library.id
        or material.current_revision_id != locator.material_revision_id
        or material.material_type != "novel"
        or material.source_status != "published"
        or material.deleted_at is not None
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    revision = await _owned(
        session, MaterialRevision, locator.material_revision_id, scope, lock=lock
    )
    if (
        revision.library_id != library.id
        or revision.material_id != material.id
        or revision.status != "published"
        or revision.structure_status != "readable"
        or revision.text_protocol_version != locator.text_protocol_version
        or revision.input_delete_generation != material.delete_generation
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    chapter = await _owned(session, NovelChapter, locator.novel_chapter_id, scope, lock=lock)
    if (
        chapter.library_id != library.id
        or chapter.material_id != material.id
        or chapter.material_revision_id != revision.id
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    # Read immutable IDs first, then acquire write locks in the shared parent order.
    mapping_hint = await _owned(
        session, NovelChapterBlock, locator.chapter_block_id, scope, lock=False
    )
    block_hint = await _owned(
        session, MaterialContentBlock, mapping_hint.content_block_id, scope, lock=False
    )
    source_unit = await _owned(
        session, MaterialSourceUnit, block_hint.source_unit_id, scope, lock=lock
    )
    block = await _owned(session, MaterialContentBlock, block_hint.id, scope, lock=lock)
    chapter_block = await _owned(session, NovelChapterBlock, mapping_hint.id, scope, lock=lock)
    if (
        chapter_block.library_id != library.id
        or chapter_block.material_id != material.id
        or chapter_block.material_revision_id != revision.id
        or chapter_block.chapter_id != chapter.id
        or chapter_block.content_block_id != locator.spans[0].block_id
        or chapter_block.content_block_id != block.id
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if (
        block.library_id != library.id
        or block.material_id != material.id
        or block.material_revision_id != revision.id
        or block.source_unit_id != source_unit.id
        or block.scalar_length != len(block.canonical_text)
        or chapter_block.end_scalar > block.scalar_length
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if (
        source_unit.library_id != library.id
        or source_unit.material_id != material.id
        or source_unit.material_revision_id != revision.id
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    span = locator.spans[0]
    if (
        span.start < chapter_block.start_scalar
        or span.end > chapter_block.end_scalar
        or span.start >= span.end
        or not _valid_grapheme_span(block.canonical_text, span.start, span.end)
        or locator.quote != block.canonical_text[span.start : span.end]
        or locator.prefix
        != block.canonical_text[max(0, span.start - len(locator.prefix)) : span.start]
        or locator.suffix != block.canonical_text[span.end : span.end + len(locator.suffix)]
        or (locator.source_title is not None and locator.source_title != material.title)
        or (locator.node_title is not None and locator.node_title != chapter.title)
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return library, material, revision, chapter, block, chapter_block


async def list_materials(
    session: AsyncSession, scope: ScopeContext, *, limit: int, cursor: str | None
) -> tuple[list[MaterialSummary], str | None]:
    await require_permissions(
        session, user_id=scope.user_id, audience="client", codes=("client.material.list",)
    )
    rows = await repository.material_page(
        session, scope, limit=limit, anchor_id=_uuid_cursor(cursor)
    )
    page = rows[:limit]
    return (
        [
            MaterialSummary(
                id=material.id,
                library_id=material.library_id,
                revision_id=revision.id,
                first_chapter_id=chapter.id,
                title=material.title,
                language=_language(material.language),
                created_at=material.created_at,
            )
            for material, revision, chapter in page
        ],
        str(page[-1][0].id) if len(rows) > limit else None,
    )


async def get_novel_chapter(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    instance_id: str,
    material_id: UUID,
    revision_id: UUID,
    node_id: UUID,
) -> NovelChapterRead:
    await require_permissions(
        session, user_id=scope.user_id, audience="client", codes=("client.material.read",)
    )
    chapter = await _owned(session, NovelChapter, node_id, scope, lock=False)
    material = await _owned(session, Material, material_id, scope, lock=False)
    revision = await _owned(session, MaterialRevision, revision_id, scope, lock=False)
    library = await _owned(session, Library, material.library_id, scope, lock=False)
    if (
        material.current_revision_id != revision.id
        or material.deleted_at is not None
        or material.source_status != "published"
        or material.material_type != "novel"
        or revision.material_id != material.id
        or revision.library_id != library.id
        or revision.status != "published"
        or revision.structure_status != "readable"
        or revision.input_delete_generation != material.delete_generation
        or chapter.material_id != material.id
        or chapter.material_revision_id != revision.id
        or chapter.library_id != library.id
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    rows = await repository.chapter_mappings(
        session, scope, library_id=library.id, chapter_id=chapter.id
    )
    if len(rows) > 100:
        raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
    blocks: list[NovelBlockRead] = []
    for mapping in rows:
        if mapping.material_id != material.id or mapping.material_revision_id != revision.id:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        block = await _owned(
            session, MaterialContentBlock, mapping.content_block_id, scope, lock=False
        )
        if (
            block.material_id != material.id
            or block.material_revision_id != revision.id
            or block.library_id != library.id
            or mapping.end_scalar > len(block.canonical_text)
        ):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        text_value = block.canonical_text[mapping.start_scalar : mapping.end_scalar]
        if len(text_value) > 500:
            raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
        locator = NovelContentLocator(
            instance_id=instance_id,
            library_id=library.id,
            material_id=material.id,
            material_revision_id=revision.id,
            novel_chapter_id=chapter.id,
            chapter_block_id=mapping.id,
            quote=text_value,
            prefix=block.canonical_text[max(0, mapping.start_scalar - 100) : mapping.start_scalar],
            suffix=block.canonical_text[mapping.end_scalar : mapping.end_scalar + 100],
            source_title=material.title,
            node_title=chapter.title,
            spans=[
                SourceSpan(block_id=block.id, start=mapping.start_scalar, end=mapping.end_scalar)
            ],
        )
        blocks.append(
            NovelBlockRead(
                id=block.id,
                chapter_block_id=mapping.id,
                canonical_text=text_value,
                ordinal=mapping.ordinal,
                source_locator=locator,
            )
        )
    return NovelChapterRead(
        material_id=material.id,
        library_id=library.id,
        revision_id=revision.id,
        node_id=chapter.id,
        title=chapter.title,
        blocks=blocks,
    )


async def _verify_card_references(
    session: AsyncSession, scope: ScopeContext, card: Card, *, instance_id: str, lock: bool
) -> list[NovelContentLocator]:
    if card.source_schema_version != 1:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    refs = _source_refs(card.source_refs)
    for locator in sorted(
        refs,
        key=lambda item: (
            str(item.material_id),
            str(item.material_revision_id),
            str(item.chapter_block_id),
        ),
    ):
        library, material, revision, chapter, block, mapping = await _source(
            session, scope, locator, instance_id=instance_id, lock=lock
        )
        if library.id != card.library_id or material.language != card.target_language:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        binding = await repository.binding_for_card_reference(
            session,
            scope,
            locator=locator,
            library=library,
            material=material,
            revision=revision,
            chapter=chapter,
            block=block,
            mapping=mapping,
            card=card,
            lock=lock,
        )
        if (
            binding is None
            or binding.source_kind != "material"
            or binding.source_resource_id != material.id
            or binding.source_version != revision.revision_number
            or binding.source_schema_version != 1
            or binding.source_locator != locator.model_dump(mode="json")
            or binding.source_snapshot.get("quote") != locator.quote
        ):
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return refs


async def resolve_explanations(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    instance_id: str,
    payload: ExplanationResolveRequest,
) -> ExplanationResolveRead:
    await require_permissions(
        session,
        user_id=scope.user_id,
        audience="client",
        codes=("client.ai.explain", "client.material.read"),
    )
    results: list[ResolvedCard | MissingCard] = []
    for target in payload.targets:
        locator = target.source_locator
        _, material, revision, chapter, block, mapping = await _source(
            session, scope, locator, instance_id=instance_id, lock=False
        )
        if target.target_language != material.language:
            raise AppError(ErrorCode.INPUT_INVALID)
        binding = await repository.latest_resolved_binding(
            session,
            scope,
            locator=locator,
            material=material,
            revision=revision,
            chapter=chapter,
            block=block,
            mapping=mapping,
            target_language=target.target_language,
            explanation_language=target.explanation_language,
        )
        if binding is None:
            results.append(MissingCard())
            continue
        card = await _owned(session, Card, binding.result_id, scope, lock=False)
        if (
            binding.result_kind != "card"
            or card.library_id != material.library_id
            or card.card_revision != binding.result_version
            or card.target_language != target.target_language
            or card.explanation_language != target.explanation_language
        ):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        refs = await _verify_card_references(
            session, scope, card, instance_id=instance_id, lock=False
        )
        if not any(_same_selection(locator, reference) for reference in refs):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        results.append(ResolvedCard(card=_card_read(card)))
    return ExplanationResolveRead(results=results)


def _digest(payload: CollectionCreate) -> bytes:
    canonical = json.dumps(
        payload.model_dump(mode="json"), ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    return hashlib.sha256(canonical.encode("utf-8")).digest()


async def create_collection(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    instance_id: str,
    payload: CollectionCreate,
    key: str,
    key_digest: bytes,
    operation_id: UUID,
) -> tuple[CollectionRead, int]:
    """Own the complete authorization, parent-lock and result transaction."""
    async with session.begin():
        result, status, outcome = await _create_collection_in_transaction(
            session,
            scope,
            instance_id=instance_id,
            payload=payload,
            key=key,
            key_digest=key_digest,
            operation_id=operation_id,
        )
    request_id, _ = current_correlation()
    _LOG.info(
        "collection.saved",
        extra={
            "request_id": request_id,
            "operation_id": operation_id,
            "user_id": scope.user_id,
            "audience": scope.audience,
            "collection_outcome": outcome,
        },
    )
    return result, status


async def _create_collection_in_transaction(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    instance_id: str,
    payload: CollectionCreate,
    key: str,
    key_digest: bytes,
    operation_id: UUID,
) -> tuple[CollectionRead, int, str]:
    if not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", key):
        raise AppError(ErrorCode.INPUT_INVALID)
    if payload.notebook_ids:
        raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
    if len(key_digest) != 32:
        raise AppError(ErrorCode.INPUT_INVALID)
    await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience="client",
        transport=scope.transport,
        permissions=("client.collection.create", "client.material.read"),
        lock_user=True,
    )
    card = await _owned(session, Card, payload.card_id, scope, lock=False)
    if card.card_revision != payload.card_revision:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    word = _payload(card)
    if (
        payload.confirmed_target_language is not None
        and payload.confirmed_target_language != card.target_language
    ):
        raise AppError(ErrorCode.INPUT_INVALID)
    library = await _owned(session, Library, card.library_id, scope, lock=True)
    await _verify_card_references(session, scope, card, instance_id=instance_id, lock=True)
    card = await _owned(session, Card, card.id, scope, lock=True)
    if card.library_id != library.id or card.card_revision != payload.card_revision:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    digest = _digest(payload)
    existing_key = await repository.replay_receipt(session, scope, key_digest=key_digest)
    if existing_key is not None and existing_key.expires_at <= datetime.now(UTC):
        # The replay receipt expires; the collection's separate unique key remains.
        await repository.retire_receipt(session, scope, existing_key)
        existing_key = None
    if existing_key is not None:
        if existing_key.request_digest != digest or existing_key.library_id != library.id:
            raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
        if (
            existing_key.result_id is None
            or existing_key.state != "committed"
            or existing_key.http_status is None
        ):
            raise AppError(ErrorCode.STATE_CONFLICT)
        item = await _owned(session, CollectionItem, existing_key.result_id, scope, lock=True)
        if (
            item.deleted_at is not None
            or item.library_id != library.id
            or item.card_id != card.id
            or item.card_revision != card.card_revision
        ):
            raise AppError(ErrorCode.STATE_CONFLICT)
        return _collection_read(item), existing_key.http_status, "replayed"
    item = await repository.existing_collection(session, scope, library_id=library.id, card=card)
    if item is not None and item.deleted_at is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    status = 200 if item is not None else 201
    if item is None:
        item = CollectionItem(
            id=uuid4(),
            owner_user_id=scope.user_id,
            library_id=library.id,
            kind="word",
            revision=1,
            card_id=card.id,
            card_revision=card.card_revision,
            display_text=word.term,
            normalized_text=word.term.casefold(),
            target_language=card.target_language,
            payload=card.payload,
            source_refs=card.source_refs,
            deleted_at=None,
            delete_generation=0,
        )
    record_id = uuid4()
    receipt = IdempotencyRecord(
        id=record_id,
        owner_user_id=scope.user_id,
        library_id=library.id,
        audience="client",
        revision=1,
        action_code="client.collection.create",
        key_digest=key_digest,
        request_digest=digest,
        state="committed",
        result_kind="collection_item",
        result_id=item.id,
        response_schema_version=1,
        safe_response={"collection_id": str(item.id)},
        http_status=status,
        expires_at=datetime.now(UTC) + timedelta(days=30),
        operation_id=operation_id,
    )
    await repository.persist_collection_result(
        session, scope, item=item if status == 201 else None, receipt=receipt
    )
    return _collection_read(item), status, "created" if status == 201 else "existing"


async def list_collections(
    session: AsyncSession, scope: ScopeContext, *, limit: int, cursor: str | None
) -> tuple[list[CollectionRead], str | None]:
    await require_permissions(
        session, user_id=scope.user_id, audience="client", codes=("client.collection.read",)
    )
    rows = await repository.collection_page(
        session, scope, limit=limit, anchor_id=_uuid_cursor(cursor)
    )
    page = rows[:limit]
    return [_collection_read(item) for item in page], str(page[-1].id) if len(
        rows
    ) > limit else None
