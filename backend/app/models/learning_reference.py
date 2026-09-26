"""current slice published novel source, complete prepared WordCard, and own collection slice.

All references are logical. The service holds the same material root while it
checks version/owner and creates a collection; no database foreign keys exist.
"""

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import (
    Base,
    IdentityMixin,
    TimestampMixin,
    business_relation,
    business_table_info,
    column_info,
)

_TESTS = "tests/integration/test_learning_reference.py"
_SERVICE = "app.services.learning_reference"
_LOCK = "lock library then material root then source version/card before collection write"


def _table_info(
    *relations: tuple[str, str, bool], entrances: tuple[str, ...], deletion: str
) -> dict[str, object]:
    refs = (
        ("owner_user_id", "users.id", False),
        ("library_id", "libraries.id", False),
        *relations,
    )
    return business_table_info(
        "library_owned",
        owner="owner_user_id",
        module="learning_reference",
        entrances=entrances,
        deletion=deletion,
        relations=tuple(
            business_relation(
                column,
                target,
                nullable=nullable,
                parent_lock=_LOCK,
                service=_SERVICE,
                tests=_TESTS,
            )
            for column, target, nullable in refs
        ),
    )


class LibraryScopeMixin:
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="本人账号归属",
        info=column_info("authenticated ScopeContext", "personal_reference"),
    )
    library_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="本人资料库归属",
        info=column_info("locked owned library", "personal_reference"),
    )


class Material(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    """current slice test-prepared immutable novel source root; no user upload path yet."""

    __tablename__ = "materials"
    __table_args__ = (
        CheckConstraint("material_type IN ('novel')", name="learning_material_type"),
        CheckConstraint("language IN ('ja', 'en')", name="learning_language"),
        CheckConstraint("source_status IN ('published', 'sealed')", name="learning_source_status"),
        CheckConstraint("revision >= 1 AND delete_generation >= 0", name="learning_revisions"),
        Index(
            "ix_materials_learning_owner_type_created_id",
            "owner_user_id",
            "material_type",
            "created_at",
            "id",
            postgresql_where=text("deleted_at IS NULL"),
            info={"purpose": "bounded own source listing"},
        ),
        {
            "comment": "current slice已发布的本人小说来源根；受控场景准备，正式上传在后续材料切片",
            "info": _table_info(
                ("current_revision_id", "material_revisions.id", True),
                entrances=("controlled current slice source fixture", "future material import"),
                deletion="tombstone first; preserve referenced snapshots and source versions",
            ),
        },
    )
    material_type: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        comment="current slice仅开放小说来源",
        info=column_info("material pipeline"),
    )
    title: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
        comment="已发布材料显示标题",
        info=column_info("source fixture", "private_content"),
    )
    language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="来源目标语言",
        info=column_info("validated source", "personal"),
    )
    current_revision_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="当前已发布来源版本",
        info=column_info("source publication", "personal_reference"),
    )
    source_status: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="来源发布或封存状态",
        info=column_info("source publication"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="材料根并发版本",
        info=column_info("source transaction"),
    )
    delete_generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="删除阻止迟到引用的代次",
        info=column_info("source transaction"),
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="材料删除墓碑时间",
        info=column_info("source transaction"),
    )


class MaterialRevision(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "material_revisions"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_id",
            "revision_number",
            name="uq_learning_material_revision_number",
        ),
        CheckConstraint("revision_number >= 1", name="learning_revision_number"),
        CheckConstraint("status IN ('published', 'sealed')", name="learning_status"),
        CheckConstraint(
            "structure_status IN ('readable', 'degraded')", name="learning_structure_status"
        ),
        CheckConstraint("input_delete_generation >= 0", name="learning_delete_generation"),
        {
            "comment": "current slice不可变小说文字及已发布结构版本",
            "info": _table_info(
                ("material_id", "materials.id", False),
                entrances=("controlled current slice source fixture", "future source publication"),
                deletion="retain while referenced; material tombstone blocks new references",
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="所属材料根",
        info=column_info("locked material", "personal_reference"),
    )
    revision_number: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="材料内不可变版本序号",
        info=column_info("source publication"),
    )
    status: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="来源版本发布状态",
        info=column_info("source publication"),
    )
    text_protocol_version: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        comment="规范文字偏移协议",
        info=column_info("content locator contract"),
    )
    structure_status: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="小说结构可读状态",
        info=column_info("novel publication"),
    )
    input_delete_generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="发布时材料删除代次",
        info=column_info("locked material"),
    )
    published_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="来源与结构实际发布时间",
        info=column_info("source publication"),
    )


class MaterialSourceUnit(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "material_source_units"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_revision_id",
            "ordinal",
            name="uq_learning_source_unit_ordinal",
        ),
        CheckConstraint("ordinal >= 1", name="learning_ordinal_positive"),
        CheckConstraint("unit_kind IN ('spine')", name="learning_unit_kind"),
        {
            "comment": "current slice受控合成小说来源容器；正式文件解析来源在后续扩展",
            "info": _table_info(
                ("material_id", "materials.id", False),
                ("material_revision_id", "material_revisions.id", False),
                entrances=("controlled current slice source fixture",),
                deletion="retain with published source version",
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同材料根",
        info=column_info("source publication", "personal_reference"),
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同来源版本",
        info=column_info("source publication", "personal_reference"),
    )
    unit_kind: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        comment="current slice固定合成来源容器类别",
        info=column_info("fixture recipe"),
    )
    ordinal: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="版本内来源容器顺序",
        info=column_info("source publication"),
    )


class MaterialContentBlock(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "material_content_blocks"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "source_unit_id",
            "ordinal",
            name="uq_learning_content_block_ordinal",
        ),
        CheckConstraint("ordinal >= 1 AND scalar_length > 0", name="learning_text_length"),
        CheckConstraint("block_kind IN ('paragraph')", name="learning_block_kind"),
        Index(
            "ix_material_content_blocks_learning_revision_id",
            "owner_user_id",
            "material_revision_id",
            "id",
            info={"purpose": "resolve an exact published block in an owned source version"},
        ),
        {
            "comment": "current slice已发布规范文本块，标量长度由发布工厂验证",
            "info": _table_info(
                ("material_id", "materials.id", False),
                ("material_revision_id", "material_revisions.id", False),
                ("source_unit_id", "material_source_units.id", False),
                entrances=("controlled current slice source fixture", "future text extraction"),
                deletion="retain with source version while cards or collections reference it",
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同材料根",
        info=column_info("source publication", "personal_reference"),
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同来源版本",
        info=column_info("source publication", "personal_reference"),
    )
    source_unit_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="不可变来源容器",
        info=column_info("source publication", "personal_reference"),
    )
    ordinal: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="来源容器内块顺序", info=column_info("source publication")
    )
    block_kind: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        comment="current slice文字块类别",
        info=column_info("source publication"),
    )
    canonical_text: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        comment="不可变规范原文；不混入注音",
        info=column_info("source extraction", "private_content"),
    )
    scalar_length: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="Unicode标量数",
        info=column_info("validated canonical text"),
    )


class NovelChapter(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "novel_chapters"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_revision_id",
            "ordinal",
            name="uq_learning_novel_chapter_ordinal",
        ),
        CheckConstraint("ordinal >= 1", name="learning_ordinal_positive"),
        {
            "comment": "current slice小说已发布章节身份与有序标题",
            "info": _table_info(
                ("material_id", "materials.id", False),
                ("material_revision_id", "material_revisions.id", False),
                entrances=("controlled current slice source fixture", "future novel publication"),
                deletion="retain with published source version",
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同材料根",
        info=column_info("novel publication", "personal_reference"),
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同来源版本",
        info=column_info("novel publication", "personal_reference"),
    )
    ordinal: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="章节顺序", info=column_info("novel publication")
    )
    title: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
        comment="已发布章节标题",
        info=column_info("novel publication", "private_content"),
    )


class NovelChapterBlock(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "novel_chapter_blocks"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "chapter_id",
            "ordinal",
            name="uq_learning_novel_chapter_block_ordinal",
        ),
        CheckConstraint(
            "ordinal >= 1 AND start_scalar >= 0 AND end_scalar > start_scalar", name="learning_span"
        ),
        CheckConstraint("display_role IN ('paragraph')", name="learning_display_role"),
        Index(
            "ix_novel_chapter_blocks_learning_content_block",
            "owner_user_id",
            "content_block_id",
            "id",
            info={"purpose": "validate that a selected source block belongs to its chapter"},
        ),
        {
            "comment": "current slice章节到规范来源块的确定范围映射",
            "info": _table_info(
                ("material_id", "materials.id", False),
                ("material_revision_id", "material_revisions.id", False),
                ("chapter_id", "novel_chapters.id", False),
                ("content_block_id", "material_content_blocks.id", False),
                entrances=("controlled current slice source fixture", "future novel publication"),
                deletion="retain with published source version",
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同材料根",
        info=column_info("novel publication", "personal_reference"),
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="共同来源版本",
        info=column_info("novel publication", "personal_reference"),
    )
    chapter_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="目标小说章节",
        info=column_info("novel publication", "personal_reference"),
    )
    content_block_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="原文规范块",
        info=column_info("novel publication", "personal_reference"),
    )
    ordinal: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="章节内块顺序", info=column_info("novel publication")
    )
    start_scalar: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="块内左闭选区起点", info=column_info("novel publication")
    )
    end_scalar: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="块内右开选区终点", info=column_info("novel publication")
    )
    display_role: Mapped[str] = mapped_column(
        String(32), nullable=False, comment="章节显示角色", info=column_info("novel publication")
    )


class Card(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "cards"
    __table_args__ = (
        CheckConstraint("card_kind IN ('word')", name="learning_card_kind"),
        CheckConstraint("card_revision >= 1 AND schema_version >= 1", name="learning_versions"),
        CheckConstraint("target_language IN ('ja', 'en')", name="learning_target_language"),
        CheckConstraint("serialized_size_bytes > 0", name="learning_payload_size"),
        {
            "comment": "current slice完整已提交WordCard；受控合成前置，不代表真实模型调用",
            "info": _table_info(
                entrances=(
                    "controlled current slice card fixture",
                    "future validated AI publication",
                ),
                deletion="retain while referenced by collections",
            ),
        },
    )
    card_kind: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="完整卡片子型",
        info=column_info("validated card publication"),
    )
    card_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="不可变卡片版本",
        info=column_info("validated card publication"),
    )
    schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="载荷结构版本", info=column_info("WordCard contract")
    )
    source_schema_version: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="来源引用结构版本",
        info=column_info("source reference contract"),
    )
    payload: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="完整类型化WordCard载荷",
        info=column_info("validated card publication", "private_content"),
    )
    serialized_size_bytes: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="序列化载荷字节长度",
        info=column_info("validated card publication"),
    )
    target_language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="明确的目标语言",
        info=column_info("validated card publication", "personal"),
    )
    explanation_language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="解释语言",
        info=column_info("validated card publication", "personal"),
    )
    source_refs: Mapped[list[dict[str, object]]] = mapped_column(
        JSONB,
        nullable=False,
        comment="有界且已验证的精确来源引用",
        info=column_info("validated card publication", "private_content"),
    )
    published_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="完整结果实际提交时间",
        info=column_info("validated card publication"),
    )


class SourceResultBinding(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "source_result_bindings"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id", "library_id", "binding_digest", name="uq_learning_source_result_digest"
        ),
        CheckConstraint("start_scalar >= 0 AND end_scalar > start_scalar", name="learning_span"),
        CheckConstraint("result_kind IN ('card') AND result_version >= 1", name="learning_result"),
        CheckConstraint(
            "source_kind IN ('material') AND source_schema_version >= 1", name="learning_source"
        ),
        CheckConstraint("octet_length(binding_digest) = 32", name="learning_binding_digest"),
        Index(
            "ix_source_result_bindings_learning_exact",
            "owner_user_id",
            "material_revision_id",
            "chapter_block_id",
            "start_scalar",
            "end_scalar",
            "target_language",
            "explanation_language",
            postgresql_where=text("released_at IS NULL"),
            info={"purpose": "bounded exact read-only card resolve"},
        ),
        {
            "comment": "已提交卡片与本人精确小说选区的持久引用",
            "info": _table_info(
                ("material_id", "materials.id", False),
                ("material_revision_id", "material_revisions.id", False),
                ("novel_chapter_id", "novel_chapters.id", False),
                ("chapter_block_id", "novel_chapter_blocks.id", False),
                ("content_block_id", "material_content_blocks.id", False),
                ("result_id", "cards.id", False),
                ("source_resource_id", "materials.id", False),
                entrances=(
                    "controlled current slice card fixture",
                    "future validated result publication",
                ),
                deletion="release source binding on owner/source deletion; independent collection snapshot remains",
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="源材料根",
        info=column_info("validated locator", "personal_reference"),
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="不可变源版本",
        info=column_info("validated locator", "personal_reference"),
    )
    novel_chapter_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="源小说章节",
        info=column_info("validated locator", "personal_reference"),
    )
    chapter_block_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="章节源映射",
        info=column_info("validated locator", "personal_reference"),
    )
    content_block_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="规范原文块",
        info=column_info("validated locator", "personal_reference"),
    )
    start_scalar: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="卡片目标左闭选区起点",
        info=column_info("validated locator"),
    )
    end_scalar: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="卡片目标右开选区终点",
        info=column_info("validated locator"),
    )
    quote: Mapped[str] = mapped_column(
        String(500),
        nullable=False,
        comment="原文选区快照，仅匹配精确来源",
        info=column_info("validated locator", "private_content"),
    )
    target_language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="卡片目标语言",
        info=column_info("validated card publication", "personal"),
    )
    explanation_language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="卡片解释语言",
        info=column_info("validated card publication", "personal"),
    )
    result_kind: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        comment="current slice固定card结果类别",
        info=column_info("validated result binding"),
    )
    result_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="完整已提交卡片",
        info=column_info("validated card publication", "personal_reference"),
    )
    result_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="确切卡片版本",
        info=column_info("validated card publication"),
    )
    binding_digest: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="精确来源与结果绑定摘要",
        info=column_info("validated result binding", "secret_hash"),
    )
    source_kind: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        comment="current slice固定材料来源",
        info=column_info("source contract"),
    )
    source_resource_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="材料来源资源",
        info=column_info("validated source", "personal_reference"),
    )
    source_version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="来源版本号", info=column_info("validated source")
    )
    source_locator: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="版本化精确来源定位",
        info=column_info("validated locator", "private_content"),
    )
    source_title: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
        comment="获权来源标题快照",
        info=column_info("validated locator", "private_content"),
    )
    source_snapshot: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="获权原文选区最小快照",
        info=column_info("validated locator", "private_content"),
    )
    source_schema_version: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="来源引用结构版本",
        info=column_info("source reference contract"),
    )
    released_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="源关系失效时间",
        info=column_info("source lifecycle"),
    )


class CollectionItem(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "collection_items"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "card_id",
            "card_revision",
            name="uq_learning_collection_card",
        ),
        CheckConstraint("kind IN ('word')", name="learning_kind"),
        CheckConstraint(
            "revision >= 1 AND card_revision >= 1 AND delete_generation >= 0",
            name="learning_versions",
        ),
        CheckConstraint("target_language IN ('ja', 'en')", name="learning_target_language"),
        Index(
            "ix_collection_items_learning_owner_created_id",
            "owner_user_id",
            "library_id",
            "created_at",
            "id",
            postgresql_where=text("deleted_at IS NULL"),
            info={"purpose": "bounded own collection list"},
        ),
        {
            "comment": "current slice本人WordCard完整快照收藏；卡片版本业务唯一包含墓碑",
            "info": _table_info(
                ("card_id", "cards.id", False),
                entrances=("authorized POST /api/v1/collections",),
                deletion="tombstone; never revive by retry or different idempotency key",
            ),
        },
    )
    kind: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        comment="current slice单词收藏类别",
        info=column_info("validated card"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="收藏可变版本",
        info=column_info("collection service"),
    )
    card_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="原始完整卡片",
        info=column_info("locked card", "personal_reference"),
    )
    card_revision: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="冻结卡片版本", info=column_info("locked card")
    )
    display_text: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
        comment="冻结显示词形",
        info=column_info("validated card", "private_content"),
    )
    normalized_text: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
        comment="确定性规范检索词形",
        info=column_info("collection service", "private_content"),
    )
    target_language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="收藏确认目标语言",
        info=column_info("validated card", "personal"),
    )
    payload: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="完整WordCard不可变收藏快照",
        info=column_info("validated card", "private_content"),
    )
    source_refs: Mapped[list[dict[str, object]]] = mapped_column(
        JSONB,
        nullable=False,
        comment="获权时冻结的有界精确出处",
        info=column_info("validated card", "private_content"),
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="收藏删除墓碑时间",
        info=column_info("collection lifecycle"),
    )
    delete_generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="迟到创建阻止代次",
        info=column_info("collection lifecycle"),
    )


class IdempotencyRecord(IdentityMixin, TimestampMixin, Base):
    """The shared user-owned idempotency contract; current slice writes collection results."""

    __tablename__ = "idempotency_records"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "audience",
            "action_code",
            "key_digest",
            name="uq_learning_idempotency_action_key",
        ),
        CheckConstraint(
            "audience IN ('client') AND state IN ('committed')", name="learning_action_state"
        ),
        CheckConstraint("http_status IN (200, 201)", name="learning_http_status"),
        CheckConstraint("revision >= 1 AND response_schema_version >= 1", name="learning_versions"),
        CheckConstraint(
            "(result_kind IS NULL AND result_id IS NULL) OR (result_kind IS NOT NULL AND result_id IS NOT NULL)",
            name="learning_result_pair",
        ),
        CheckConstraint(
            "result_kind = 'collection_item' AND result_id IS NOT NULL AND safe_response IS NOT NULL",
            name="learning_committed_result",
        ),
        CheckConstraint(
            "octet_length(key_digest) = 32 AND octet_length(request_digest) = 32",
            name="learning_digest_lengths",
        ),
        Index(
            "ix_idempotency_records_learning_expires",
            "expires_at",
            "id",
            info={"purpose": "bounded expiry maintenance"},
        ),
        {
            "comment": "本人业务幂等受理；current slice写入收藏动作子集",
            "info": business_table_info(
                "user_owned",
                owner="owner_user_id",
                module="learning_reference",
                entrances=("authorized POST /api/v1/collections",),
                deletion="expire only after replay window; collection business uniqueness persists",
                relations=(
                    business_relation(
                        "owner_user_id",
                        "users.id",
                        nullable=False,
                        parent_lock=_LOCK,
                        service=_SERVICE,
                        tests=_TESTS,
                    ),
                    business_relation(
                        "library_id",
                        "libraries.id",
                        nullable=True,
                        parent_lock=_LOCK,
                        service=_SERVICE,
                        tests=_TESTS,
                    ),
                    business_relation(
                        "result_id",
                        "collection_items.id",
                        nullable=True,
                        parent_lock=_LOCK,
                        service=_SERVICE,
                        tests=_TESTS,
                    ),
                ),
            ),
        },
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="本人账号归属",
        info=column_info("authenticated ScopeContext", "personal_reference"),
    )
    library_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="可选本人资料库作用域",
        info=column_info("locked library", "personal_reference"),
    )
    audience: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="固定client受众", info=column_info("route boundary")
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="记录并发版本",
        info=column_info("idempotency transaction"),
    )
    action_code: Mapped[str] = mapped_column(
        String(128), nullable=False, comment="服务动作固定码", info=column_info("route boundary")
    )
    key_digest: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="客户端键的服务端HMAC摘要",
        info=column_info("server HMAC", "secret_hash"),
    )
    request_digest: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="规范请求SHA-256摘要",
        info=column_info("collection service", "secret_hash"),
    )
    state: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="受理状态", info=column_info("collection transaction")
    )
    result_kind: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        comment="领域结果类别",
        info=column_info("collection transaction"),
    )
    result_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="领域结果引用",
        info=column_info("collection transaction", "personal_reference"),
    )
    response_schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="安全响应结构版本", info=column_info("response contract")
    )
    safe_response: Mapped[dict[str, object] | None] = mapped_column(
        JSONB,
        nullable=True,
        comment="仅含结果引用的安全响应",
        info=column_info("response contract", "private_metadata"),
    )
    http_status: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="首次确认的HTTP状态",
        info=column_info("collection transaction"),
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="重放窗口到期",
        info=column_info("idempotency policy"),
    )
    operation_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="首次请求操作身份",
        info={
            **column_info("request context", "personal_reference"),
            "non_entity_uuid": "operation_correlation",
        },
    )
