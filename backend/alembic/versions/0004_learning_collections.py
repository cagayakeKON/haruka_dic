"""current slice published novel source and own collection tables; no physical foreign keys.

Static DDL reviewed from the release model. Run only through controlled maintenance.
"""

import re

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0004_learning_collections"
down_revision = "0003_account_security"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "materials",
        sa.Column(
            "material_type", sa.String(length=16), nullable=False, comment="current slice仅开放小说来源"
        ),
        sa.Column("title", sa.String(length=200), nullable=False, comment="已发布材料显示标题"),
        sa.Column("language", sa.String(length=35), nullable=False, comment="来源目标语言"),
        sa.Column("current_revision_id", sa.UUID(), nullable=True, comment="当前已发布来源版本"),
        sa.Column(
            "source_status", sa.String(length=24), nullable=False, comment="来源发布或封存状态"
        ),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="材料根并发版本",
        ),
        sa.Column(
            "delete_generation",
            sa.BigInteger(),
            server_default=sa.text("0"),
            nullable=False,
            comment="删除阻止迟到引用的代次",
        ),
        sa.Column(
            "deleted_at", sa.DateTime(timezone=True), nullable=True, comment="材料删除墓碑时间"
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint("language IN ('ja', 'en')", name=op.f("ck_materials_learning_language")),
        sa.CheckConstraint(
            "material_type IN ('novel')", name=op.f("ck_materials_learning_material_type")
        ),
        sa.CheckConstraint(
            "source_status IN ('published', 'sealed')", name=op.f("ck_materials_learning_source_status")
        ),
        sa.CheckConstraint(
            "revision >= 1 AND delete_generation >= 0", name=op.f("ck_materials_learning_revisions")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_materials")),
        comment="current slice已发布的本人小说来源根；受控场景准备，正式上传在后续材料切片",
    )
    op.create_index(
        "ix_materials_learning_owner_type_created_id",
        "materials",
        ["owner_user_id", "material_type", "created_at", "id"],
        unique=False,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_table(
        "material_revisions",
        sa.Column("material_id", sa.UUID(), nullable=False, comment="所属材料根"),
        sa.Column(
            "revision_number", sa.BigInteger(), nullable=False, comment="材料内不可变版本序号"
        ),
        sa.Column("status", sa.String(length=24), nullable=False, comment="来源版本发布状态"),
        sa.Column(
            "text_protocol_version",
            sa.String(length=40),
            nullable=False,
            comment="规范文字偏移协议",
        ),
        sa.Column(
            "structure_status", sa.String(length=24), nullable=False, comment="小说结构可读状态"
        ),
        sa.Column(
            "input_delete_generation", sa.BigInteger(), nullable=False, comment="发布时材料删除代次"
        ),
        sa.Column(
            "published_at",
            sa.DateTime(timezone=True),
            nullable=False,
            comment="来源与结构实际发布时间",
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint(
            "status IN ('published', 'sealed')", name=op.f("ck_material_revisions_learning_status")
        ),
        sa.CheckConstraint(
            "structure_status IN ('readable', 'degraded')",
            name=op.f("ck_material_revisions_learning_structure_status"),
        ),
        sa.CheckConstraint(
            "input_delete_generation >= 0", name=op.f("ck_material_revisions_learning_delete_generation")
        ),
        sa.CheckConstraint(
            "revision_number >= 1", name=op.f("ck_material_revisions_learning_revision_number")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_material_revisions")),
        sa.UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_id",
            "revision_number",
            name="uq_learning_material_revision_number",
        ),
        comment="current slice不可变小说文字及已发布结构版本",
    )
    op.create_table(
        "material_source_units",
        sa.Column("material_id", sa.UUID(), nullable=False, comment="共同材料根"),
        sa.Column("material_revision_id", sa.UUID(), nullable=False, comment="共同来源版本"),
        sa.Column(
            "unit_kind", sa.String(length=32), nullable=False, comment="current slice固定合成来源容器类别"
        ),
        sa.Column("ordinal", sa.Integer(), nullable=False, comment="版本内来源容器顺序"),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint(
            "unit_kind IN ('spine')", name=op.f("ck_material_source_units_learning_unit_kind")
        ),
        sa.CheckConstraint(
            "ordinal >= 1", name=op.f("ck_material_source_units_learning_ordinal_positive")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_material_source_units")),
        sa.UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_revision_id",
            "ordinal",
            name="uq_learning_source_unit_ordinal",
        ),
        comment="current slice受控合成小说来源容器；正式文件解析来源在后续扩展",
    )
    op.create_table(
        "material_content_blocks",
        sa.Column("material_id", sa.UUID(), nullable=False, comment="共同材料根"),
        sa.Column("material_revision_id", sa.UUID(), nullable=False, comment="共同来源版本"),
        sa.Column("source_unit_id", sa.UUID(), nullable=False, comment="不可变来源容器"),
        sa.Column("ordinal", sa.Integer(), nullable=False, comment="来源容器内块顺序"),
        sa.Column("block_kind", sa.String(length=32), nullable=False, comment="current slice文字块类别"),
        sa.Column(
            "canonical_text", sa.Text(), nullable=False, comment="不可变规范原文；不混入注音"
        ),
        sa.Column("scalar_length", sa.Integer(), nullable=False, comment="Unicode标量数"),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint(
            "block_kind IN ('paragraph')", name=op.f("ck_material_content_blocks_learning_block_kind")
        ),
        sa.CheckConstraint(
            "ordinal >= 1 AND scalar_length > 0",
            name=op.f("ck_material_content_blocks_learning_text_length"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_material_content_blocks")),
        sa.UniqueConstraint(
            "owner_user_id",
            "library_id",
            "source_unit_id",
            "ordinal",
            name="uq_learning_content_block_ordinal",
        ),
        comment="current slice已发布规范文本块，标量长度由发布工厂验证",
    )
    op.create_index(
        "ix_material_content_blocks_learning_revision_id",
        "material_content_blocks",
        ["owner_user_id", "material_revision_id", "id"],
        unique=False,
    )
    op.create_table(
        "novel_chapters",
        sa.Column("material_id", sa.UUID(), nullable=False, comment="共同材料根"),
        sa.Column("material_revision_id", sa.UUID(), nullable=False, comment="共同来源版本"),
        sa.Column("ordinal", sa.Integer(), nullable=False, comment="章节顺序"),
        sa.Column("title", sa.String(length=200), nullable=False, comment="已发布章节标题"),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint("ordinal >= 1", name=op.f("ck_novel_chapters_learning_ordinal_positive")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_novel_chapters")),
        sa.UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_revision_id",
            "ordinal",
            name="uq_learning_novel_chapter_ordinal",
        ),
        comment="current slice小说已发布章节身份与有序标题",
    )
    op.create_table(
        "novel_chapter_blocks",
        sa.Column("material_id", sa.UUID(), nullable=False, comment="共同材料根"),
        sa.Column("material_revision_id", sa.UUID(), nullable=False, comment="共同来源版本"),
        sa.Column("chapter_id", sa.UUID(), nullable=False, comment="目标小说章节"),
        sa.Column("content_block_id", sa.UUID(), nullable=False, comment="原文规范块"),
        sa.Column("ordinal", sa.Integer(), nullable=False, comment="章节内块顺序"),
        sa.Column("start_scalar", sa.Integer(), nullable=False, comment="块内左闭选区起点"),
        sa.Column("end_scalar", sa.Integer(), nullable=False, comment="块内右开选区终点"),
        sa.Column("display_role", sa.String(length=32), nullable=False, comment="章节显示角色"),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint(
            "display_role IN ('paragraph')", name=op.f("ck_novel_chapter_blocks_learning_display_role")
        ),
        sa.CheckConstraint(
            "ordinal >= 1 AND start_scalar >= 0 AND end_scalar > start_scalar",
            name=op.f("ck_novel_chapter_blocks_learning_span"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_novel_chapter_blocks")),
        sa.UniqueConstraint(
            "owner_user_id",
            "library_id",
            "chapter_id",
            "ordinal",
            name="uq_learning_novel_chapter_block_ordinal",
        ),
        comment="current slice章节到规范来源块的确定范围映射",
    )
    op.create_index(
        "ix_novel_chapter_blocks_learning_content_block",
        "novel_chapter_blocks",
        ["owner_user_id", "content_block_id", "id"],
        unique=False,
    )
    op.create_table(
        "cards",
        sa.Column("card_kind", sa.String(length=24), nullable=False, comment="完整卡片子型"),
        sa.Column("card_revision", sa.BigInteger(), nullable=False, comment="不可变卡片版本"),
        sa.Column("schema_version", sa.Integer(), nullable=False, comment="载荷结构版本"),
        sa.Column(
            "source_schema_version", sa.Integer(), nullable=False, comment="来源引用结构版本"
        ),
        sa.Column(
            "payload",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            comment="完整类型化WordCard载荷",
        ),
        sa.Column(
            "serialized_size_bytes", sa.BigInteger(), nullable=False, comment="序列化载荷字节长度"
        ),
        sa.Column(
            "target_language", sa.String(length=35), nullable=False, comment="明确的目标语言"
        ),
        sa.Column("explanation_language", sa.String(length=35), nullable=False, comment="解释语言"),
        sa.Column(
            "source_refs",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            comment="有界且已验证的精确来源引用",
        ),
        sa.Column(
            "published_at",
            sa.DateTime(timezone=True),
            nullable=False,
            comment="完整结果实际提交时间",
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint("card_kind IN ('word')", name=op.f("ck_cards_learning_card_kind")),
        sa.CheckConstraint(
            "target_language IN ('ja', 'en')", name=op.f("ck_cards_learning_target_language")
        ),
        sa.CheckConstraint(
            "card_revision >= 1 AND schema_version >= 1", name=op.f("ck_cards_learning_versions")
        ),
        sa.CheckConstraint("serialized_size_bytes > 0", name=op.f("ck_cards_learning_payload_size")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_cards")),
        comment="current slice完整已提交WordCard；受控合成前置，不代表真实模型调用",
    )
    op.create_table(
        "source_result_bindings",
        sa.Column("material_id", sa.UUID(), nullable=False, comment="源材料根"),
        sa.Column("material_revision_id", sa.UUID(), nullable=False, comment="不可变源版本"),
        sa.Column("novel_chapter_id", sa.UUID(), nullable=False, comment="源小说章节"),
        sa.Column("chapter_block_id", sa.UUID(), nullable=False, comment="章节源映射"),
        sa.Column("content_block_id", sa.UUID(), nullable=False, comment="规范原文块"),
        sa.Column("start_scalar", sa.Integer(), nullable=False, comment="卡片目标左闭选区起点"),
        sa.Column("end_scalar", sa.Integer(), nullable=False, comment="卡片目标右开选区终点"),
        sa.Column(
            "quote", sa.String(length=500), nullable=False, comment="原文选区快照，仅匹配精确来源"
        ),
        sa.Column("target_language", sa.String(length=35), nullable=False, comment="卡片目标语言"),
        sa.Column(
            "explanation_language", sa.String(length=35), nullable=False, comment="卡片解释语言"
        ),
        sa.Column(
            "result_kind", sa.String(length=16), nullable=False, comment="current slice固定card结果类别"
        ),
        sa.Column("result_id", sa.UUID(), nullable=False, comment="完整已提交卡片"),
        sa.Column("result_version", sa.BigInteger(), nullable=False, comment="确切卡片版本"),
        sa.Column(
            "binding_digest", sa.LargeBinary(), nullable=False, comment="精确来源与结果绑定摘要"
        ),
        sa.Column("source_kind", sa.String(length=32), nullable=False, comment="current slice固定材料来源"),
        sa.Column("source_resource_id", sa.UUID(), nullable=False, comment="材料来源资源"),
        sa.Column("source_version", sa.BigInteger(), nullable=False, comment="来源版本号"),
        sa.Column(
            "source_locator",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            comment="版本化精确来源定位",
        ),
        sa.Column(
            "source_title", sa.String(length=200), nullable=False, comment="获权来源标题快照"
        ),
        sa.Column(
            "source_snapshot",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            comment="获权原文选区最小快照",
        ),
        sa.Column(
            "source_schema_version", sa.Integer(), nullable=False, comment="来源引用结构版本"
        ),
        sa.Column(
            "released_at", sa.DateTime(timezone=True), nullable=True, comment="源关系失效时间"
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint(
            "result_kind IN ('card') AND result_version >= 1",
            name=op.f("ck_source_result_bindings_learning_result"),
        ),
        sa.CheckConstraint(
            "source_kind IN ('material') AND source_schema_version >= 1",
            name=op.f("ck_source_result_bindings_learning_source"),
        ),
        sa.CheckConstraint(
            "octet_length(binding_digest) = 32",
            name=op.f("ck_source_result_bindings_learning_binding_digest"),
        ),
        sa.CheckConstraint(
            "start_scalar >= 0 AND end_scalar > start_scalar",
            name=op.f("ck_source_result_bindings_learning_span"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_source_result_bindings")),
        sa.UniqueConstraint(
            "owner_user_id", "library_id", "binding_digest", name="uq_learning_source_result_digest"
        ),
        comment="已提交卡片与本人精确小说选区的持久引用",
    )
    op.create_index(
        "ix_source_result_bindings_learning_exact",
        "source_result_bindings",
        [
            "owner_user_id",
            "material_revision_id",
            "chapter_block_id",
            "start_scalar",
            "end_scalar",
            "target_language",
            "explanation_language",
        ],
        unique=False,
        postgresql_where=sa.text("released_at IS NULL"),
    )
    op.create_table(
        "collection_items",
        sa.Column("kind", sa.String(length=16), nullable=False, comment="current slice单词收藏类别"),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="收藏可变版本",
        ),
        sa.Column("card_id", sa.UUID(), nullable=False, comment="原始完整卡片"),
        sa.Column("card_revision", sa.BigInteger(), nullable=False, comment="冻结卡片版本"),
        sa.Column("display_text", sa.String(length=200), nullable=False, comment="冻结显示词形"),
        sa.Column(
            "normalized_text", sa.String(length=200), nullable=False, comment="确定性规范检索词形"
        ),
        sa.Column(
            "target_language", sa.String(length=35), nullable=False, comment="收藏确认目标语言"
        ),
        sa.Column(
            "payload",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            comment="完整WordCard不可变收藏快照",
        ),
        sa.Column(
            "source_refs",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            comment="获权时冻结的有界精确出处",
        ),
        sa.Column(
            "deleted_at", sa.DateTime(timezone=True), nullable=True, comment="收藏删除墓碑时间"
        ),
        sa.Column(
            "delete_generation",
            sa.BigInteger(),
            server_default=sa.text("0"),
            nullable=False,
            comment="迟到创建阻止代次",
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=False, comment="本人资料库归属"),
        sa.CheckConstraint("kind IN ('word')", name=op.f("ck_collection_items_learning_kind")),
        sa.CheckConstraint(
            "target_language IN ('ja', 'en')", name=op.f("ck_collection_items_learning_target_language")
        ),
        sa.CheckConstraint(
            "revision >= 1 AND card_revision >= 1 AND delete_generation >= 0",
            name=op.f("ck_collection_items_learning_versions"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_collection_items")),
        sa.UniqueConstraint(
            "owner_user_id", "library_id", "card_id", "card_revision", name="uq_learning_collection_card"
        ),
        comment="current slice本人WordCard完整快照收藏；卡片版本业务唯一包含墓碑",
    )
    op.create_index(
        "ix_collection_items_learning_owner_created_id",
        "collection_items",
        ["owner_user_id", "library_id", "created_at", "id"],
        unique=False,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_table(
        "idempotency_records",
        sa.Column("owner_user_id", sa.UUID(), nullable=False, comment="本人账号归属"),
        sa.Column("library_id", sa.UUID(), nullable=True, comment="可选本人资料库作用域"),
        sa.Column("audience", sa.String(length=16), nullable=False, comment="固定client受众"),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="记录并发版本",
        ),
        sa.Column("action_code", sa.String(length=128), nullable=False, comment="服务动作固定码"),
        sa.Column(
            "key_digest", sa.LargeBinary(), nullable=False, comment="客户端键的服务端HMAC摘要"
        ),
        sa.Column(
            "request_digest", sa.LargeBinary(), nullable=False, comment="规范请求SHA-256摘要"
        ),
        sa.Column("state", sa.String(length=16), nullable=False, comment="受理状态"),
        sa.Column("result_kind", sa.String(length=64), nullable=True, comment="领域结果类别"),
        sa.Column("result_id", sa.UUID(), nullable=True, comment="领域结果引用"),
        sa.Column(
            "response_schema_version", sa.Integer(), nullable=False, comment="安全响应结构版本"
        ),
        sa.Column(
            "safe_response",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
            comment="仅含结果引用的安全响应",
        ),
        sa.Column("http_status", sa.Integer(), nullable=True, comment="首次确认的HTTP状态"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False, comment="重放窗口到期"),
        sa.Column("operation_id", sa.UUID(), nullable=False, comment="首次请求操作身份"),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.CheckConstraint(
            "audience IN ('client') AND state IN ('committed')",
            name=op.f("ck_idempotency_records_learning_action_state"),
        ),
        sa.CheckConstraint(
            "result_kind = 'collection_item' AND result_id IS NOT NULL AND safe_response IS NOT NULL",
            name=op.f("ck_idempotency_records_learning_committed_result"),
        ),
        sa.CheckConstraint(
            "(result_kind IS NULL AND result_id IS NULL) OR (result_kind IS NOT NULL AND result_id IS NOT NULL)",
            name=op.f("ck_idempotency_records_learning_result_pair"),
        ),
        sa.CheckConstraint(
            "http_status IN (200, 201)", name=op.f("ck_idempotency_records_learning_http_status")
        ),
        sa.CheckConstraint(
            "octet_length(key_digest) = 32 AND octet_length(request_digest) = 32",
            name=op.f("ck_idempotency_records_learning_digest_lengths"),
        ),
        sa.CheckConstraint(
            "revision >= 1 AND response_schema_version >= 1",
            name=op.f("ck_idempotency_records_learning_versions"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_idempotency_records")),
        sa.UniqueConstraint(
            "owner_user_id",
            "audience",
            "action_code",
            "key_digest",
            name="uq_learning_idempotency_action_key",
        ),
        comment="本人业务幂等受理；current slice写入收藏动作子集",
    )
    op.create_index(
        "ix_idempotency_records_learning_expires",
        "idempotency_records",
        ["expires_at", "id"],
        unique=False,
    )

    bind = op.get_bind()
    database = bind.scalar(sa.text("SELECT current_database()"))
    schema = bind.scalar(sa.text("SELECT current_schema()"))
    if (
        database not in {"haruka_test", "haruka_dev"}
        or not isinstance(schema, str)
        or (schema != "public" and not re.fullmatch(r"haruka_migration_test_[a-f0-9]{32}", schema))
    ):
        raise RuntimeError("migration target is not an isolated Haruka schema")
    role = f"{database}_runtime"
    quoted_schema = bind.dialect.identifier_preparer.quote_schema(schema)
    op.execute(f"GRANT USAGE ON SCHEMA {quoted_schema} TO {role}")
    op.execute(
        f"GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {quoted_schema} TO {role}"
    )
    op.execute(f"REVOKE UPDATE, DELETE ON {quoted_schema}.admin_audit_events FROM {role}")
    op.execute(f"REVOKE INSERT, UPDATE, DELETE ON {quoted_schema}.alembic_version FROM {role}")


def downgrade() -> None:
    raise RuntimeError("current slice learning data requires reviewed forward repair")
