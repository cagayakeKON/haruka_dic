"""current slice read-only published novel/WordCard subset and persisted collection DTOs."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.schemas.responses import ApiModel


class SourceSpan(ApiModel):
    block_id: UUID
    start: int = Field(ge=0)
    end: int = Field(gt=0)


class NovelContentLocator(ApiModel):
    locator_schema_version: Literal[1] = 1
    instance_id: str
    library_id: UUID
    target_kind: Literal["material_content"] = "material_content"
    text_protocol_version: Literal["canonical-text-v1"] = "canonical-text-v1"
    material_id: UUID
    material_revision_id: UUID
    novel_chapter_id: UUID
    chapter_block_id: UUID
    quote: str = Field(min_length=1, max_length=500)
    prefix: str = Field(max_length=100)
    suffix: str = Field(max_length=100)
    source_title: str | None = Field(default=None, max_length=200)
    node_title: str | None = Field(default=None, max_length=200)
    spans: list[SourceSpan] = Field(min_length=1, max_length=1)


class MaterialSummary(ApiModel):
    id: UUID
    library_id: UUID
    revision_id: UUID
    first_chapter_id: UUID
    material_type: Literal["novel"] = "novel"
    title: str
    language: Literal["ja", "en"]
    created_at: datetime


class NovelBlockRead(ApiModel):
    id: UUID
    chapter_block_id: UUID
    canonical_text: str
    ordinal: int = Field(ge=0)
    source_locator: NovelContentLocator


class NovelChapterRead(ApiModel):
    material_id: UUID
    library_id: UUID
    revision_id: UUID
    node_id: UUID
    title: str
    blocks: list[NovelBlockRead]


class ResolveTarget(ApiModel):
    source_locator: NovelContentLocator
    target_language: Literal["ja", "en"]
    explanation_language: str = Field(min_length=2, max_length=35)


class ExplanationResolveRequest(ApiModel):
    targets: list[ResolveTarget] = Field(min_length=1, max_length=10)


class WordExample(ApiModel):
    text: str = Field(min_length=1, max_length=500)
    meaning: str = Field(min_length=1, max_length=500)


class WordCardPayload(ApiModel):
    lexical_kind: Literal["word"] = "word"
    term: str = Field(min_length=1, max_length=200)
    reading: str | None = Field(default=None, max_length=200)
    part_of_speech: str = Field(min_length=1, max_length=100)
    context_meaning: str = Field(min_length=1, max_length=1000)
    other_meanings: list[str] = Field(max_length=10)
    examples: list[WordExample] = Field(min_length=2, max_length=2)


class WordCardRead(ApiModel):
    card_id: UUID
    card_revision: int = Field(ge=1)
    type: Literal["word"] = "word"
    schema_version: Literal[1] = 1
    target_language: Literal["ja", "en"]
    explanation_language: str
    payload: WordCardPayload
    source_refs: list[NovelContentLocator] = Field(min_length=1)
    provenance: Literal["material"] = "material"
    created_at: datetime


class ResolvedCard(ApiModel):
    state: Literal["found"] = "found"
    card: WordCardRead


class MissingCard(ApiModel):
    state: Literal["missing"] = "missing"
    card: None = None


class ExplanationResolveRead(ApiModel):
    results: list[ResolvedCard | MissingCard]


class CollectionCreate(ApiModel):
    card_id: UUID
    card_revision: int = Field(ge=1)
    confirmed_target_language: Literal["ja", "en"] | None = None
    notebook_ids: list[UUID] = Field(default_factory=lambda: list[UUID](), max_length=20)


class CollectionRead(ApiModel):
    id: UUID
    revision: int = Field(ge=1)
    kind: Literal["word"] = "word"
    card_id: UUID
    card_revision: int = Field(ge=1)
    display_text: str
    target_language: Literal["ja", "en"]
    payload: WordCardPayload
    source_refs: list[NovelContentLocator]
    created_at: datetime
