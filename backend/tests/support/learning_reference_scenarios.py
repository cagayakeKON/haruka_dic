"""Controlled current slice prerequisites for an already registered synthetic test user.

This factory never creates a collection or supplies a result through HTTP. The
test must perform registration, verification, login, resolve and collection via
the real API/UI. It only publishes one small synthetic novel and complete card.
"""

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models.identity import Library, User
from app.models.learning_reference import (
    Card,
    Material,
    MaterialContentBlock,
    MaterialRevision,
    MaterialSourceUnit,
    NovelChapter,
    NovelChapterBlock,
    SourceResultBinding,
)
from app.schemas.learning_reference import (
    NovelContentLocator,
    SourceSpan,
    WordCardPayload,
    WordExample,
)

_TEXT = "青い空を見上げた。"
_WORD = "空"
_TITLE = "晴空频率测试短篇"
_CHAPTER = "第一章"


@dataclass(frozen=True)
class PreparedLearningSource:
    owner_user_id: UUID
    library_id: UUID
    material_id: UUID
    revision_id: UUID
    chapter_id: UUID
    content_block_id: UUID
    card_id: UUID


async def prepare_learning_source(
    settings: MaintenanceSettings, *, owner_email: str, instance_id: str
) -> PreparedLearningSource:
    """Insert only an authorized synthetic source/card in the caller-owned schema."""
    if (
        settings.app_env != "test"
        or settings.test_schema is None
        or re.fullmatch(r"haruka-test-[a-f0-9]{32}", instance_id) is None
        or settings.test_schema
        != "haruka_migration_test_" + instance_id.removeprefix("haruka-test-")
        or re.fullmatch(r"[a-z0-9._+-]+@haruka\.example\.test", owner_email) is None
    ):
        raise ValueError(
            "current slice source factory requires an owned synthetic test run and recipient"
        )
    run_id = instance_id.removeprefix("haruka-test-")
    engine = create_maintenance_engine(settings)
    try:
        sessions = async_sessionmaker(engine, expire_on_commit=False)
        async with sessions() as session, session.begin():
            identity = (
                await session.execute(text("SELECT current_database(), current_user"))
            ).one()
            marker = await session.scalar(
                text(
                    "SELECT obj_description(oid, 'pg_namespace') FROM pg_namespace WHERE nspname=:schema"
                ),
                {"schema": settings.test_schema},
            )
            if (
                identity != ("haruka_test", "haruka_test_maintenance")
                or marker != f"haruka-b1-run:{run_id}"
            ):
                raise ValueError("current slice source factory schema ownership differs")
            user = await session.scalar(
                select(User).where(User.email_normalized == owner_email.lower()).with_for_update()
            )
            if user is None or user.status != "active" or user.email_verified_at is None:
                raise ValueError("current slice source owner must be a verified active test user")
            library = await session.scalar(
                select(Library).where(Library.owner_user_id == user.id).with_for_update()
            )
            if library is None:
                raise ValueError("current slice source owner has no private library")
            now = datetime.now(UTC)
            material_id, revision_id, source_unit_id, content_block_id = (
                uuid4(),
                uuid4(),
                uuid4(),
                uuid4(),
            )
            chapter_id, chapter_block_id, card_id = uuid4(), uuid4(), uuid4()
            selection_start = _TEXT.index(_WORD)
            selection_end = selection_start + len(_WORD)
            locator = NovelContentLocator(
                instance_id=instance_id,
                library_id=library.id,
                material_id=material_id,
                material_revision_id=revision_id,
                novel_chapter_id=chapter_id,
                chapter_block_id=chapter_block_id,
                quote=_WORD,
                prefix=_TEXT[:selection_start],
                suffix=_TEXT[selection_end:],
                source_title=_TITLE,
                node_title=_CHAPTER,
                spans=[
                    SourceSpan(block_id=content_block_id, start=selection_start, end=selection_end)
                ],
            )
            payload = WordCardPayload(
                term=_WORD,
                reading="そら",
                part_of_speech="名词",
                context_meaning="天空",
                other_meanings=["天气"],
                examples=[
                    WordExample(text="空が青い。", meaning="天空是蓝色的。"),
                    WordExample(text="空を見ます。", meaning="看天空。"),
                ],
            )
            payload_json = payload.model_dump(mode="json")
            locator_json = locator.model_dump(mode="json")
            session.add_all(
                [
                    Material(
                        id=material_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_type="novel",
                        title=_TITLE,
                        language="ja",
                        current_revision_id=revision_id,
                        source_status="published",
                        revision=1,
                        delete_generation=0,
                        deleted_at=None,
                    ),
                    MaterialRevision(
                        id=revision_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_id=material_id,
                        revision_number=1,
                        status="published",
                        text_protocol_version="canonical-text-v1",
                        structure_status="readable",
                        input_delete_generation=0,
                        published_at=now,
                    ),
                    MaterialSourceUnit(
                        id=source_unit_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_id=material_id,
                        material_revision_id=revision_id,
                        unit_kind="spine",
                        ordinal=1,
                    ),
                    MaterialContentBlock(
                        id=content_block_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_id=material_id,
                        material_revision_id=revision_id,
                        source_unit_id=source_unit_id,
                        ordinal=1,
                        block_kind="paragraph",
                        canonical_text=_TEXT,
                        scalar_length=len(_TEXT),
                    ),
                    NovelChapter(
                        id=chapter_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_id=material_id,
                        material_revision_id=revision_id,
                        ordinal=1,
                        title=_CHAPTER,
                    ),
                    NovelChapterBlock(
                        id=chapter_block_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_id=material_id,
                        material_revision_id=revision_id,
                        chapter_id=chapter_id,
                        content_block_id=content_block_id,
                        ordinal=1,
                        start_scalar=0,
                        end_scalar=len(_TEXT),
                        display_role="paragraph",
                    ),
                    Card(
                        id=card_id,
                        owner_user_id=user.id,
                        library_id=library.id,
                        card_kind="word",
                        card_revision=1,
                        schema_version=1,
                        source_schema_version=1,
                        payload=payload_json,
                        serialized_size_bytes=len(
                            json.dumps(payload_json, ensure_ascii=False, sort_keys=True).encode(
                                "utf-8"
                            )
                        ),
                        target_language="ja",
                        explanation_language="zh-CN",
                        source_refs=[locator_json],
                        published_at=now,
                    ),
                    SourceResultBinding(
                        id=uuid4(),
                        owner_user_id=user.id,
                        library_id=library.id,
                        material_id=material_id,
                        material_revision_id=revision_id,
                        novel_chapter_id=chapter_id,
                        chapter_block_id=chapter_block_id,
                        content_block_id=content_block_id,
                        start_scalar=selection_start,
                        end_scalar=selection_end,
                        quote=_WORD,
                        target_language="ja",
                        explanation_language="zh-CN",
                        result_kind="card",
                        result_id=card_id,
                        result_version=1,
                        binding_digest=hashlib.sha256(
                            json.dumps(
                                {
                                    "owner": str(user.id),
                                    "locator": locator_json,
                                    "card": str(card_id),
                                    "version": 1,
                                },
                                ensure_ascii=False,
                                sort_keys=True,
                            ).encode("utf-8")
                        ).digest(),
                        source_kind="material",
                        source_resource_id=material_id,
                        source_version=1,
                        source_locator=locator_json,
                        source_title=_TITLE,
                        source_snapshot={"quote": _WORD},
                        source_schema_version=1,
                        released_at=None,
                    ),
                ]
            )
            await session.flush()
            return PreparedLearningSource(
                user.id, library.id, material_id, revision_id, chapter_id, content_block_id, card_id
            )
    finally:
        await engine.dispose()
