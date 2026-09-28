"""Owner profile, study-language and settings columns. No physical foreign keys.

Static DDL reviewed from the release model. Run only through controlled maintenance.
"""

import re

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0005_profile_settings"
down_revision = "0004_learning_collections"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_extensions",
        sa.Column(
            "display_name", sa.String(100), nullable=True, comment="本人称呼；非唯一，不从邮箱推导"
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "birth_year", sa.SmallInteger(), nullable=True, comment="可选出生年份；不保存整数年龄"
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column("gender_code", sa.String(24), nullable=True, comment="可选性别代码，可清除"),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "gender_self_description",
            sa.String(200),
            nullable=True,
            comment="仅self_described可填写的说明，不进入AI",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "use_optional_demographics_for_ai",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
            comment="是否允许具体功能使用最小派生人口资料",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "explanation_language",
            sa.String(35),
            nullable=True,
            comment="解释语言，和界面语言、母语分开",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "active_target_language",
            sa.String(35),
            nullable=True,
            comment="当前目标语，必须存在本人target语言行",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "ui_locale",
            sa.String(35),
            nullable=False,
            server_default=sa.text("'zh-Hans'"),
            comment="P0界面语言，固定为简体中文",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "timezone",
            sa.String(64),
            nullable=True,
            comment="用户确认的IANA时区；空表示未选择",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "theme_mode",
            sa.String(8),
            nullable=False,
            server_default=sa.text("'system'"),
            comment="system、light或dark",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "reduce_motion",
            sa.String(8),
            nullable=False,
            server_default=sa.text("'system'"),
            comment="system或on",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "reading_font_family",
            sa.String(16),
            nullable=True,
            comment="已发布阅读字体类别；空为应用默认",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column("reading_font_size", sa.Numeric(5, 2), nullable=True, comment="阅读逻辑字号"),
    )
    op.add_column(
        "user_extensions",
        sa.Column("reading_line_height", sa.Numeric(4, 2), nullable=True, comment="阅读行高倍率"),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "reading_theme",
            sa.String(8),
            nullable=True,
            comment="阅读浅色、深色或sepia",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "playback_speed",
            sa.Numeric(3, 2),
            nullable=False,
            server_default=sa.text("1.00"),
            comment="播放倍速，不改变合成键",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "query_context_budget_tokens",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("10000"),
            comment="本人查询补充前后文预算",
        ),
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_birth_year"),
        "user_extensions",
        "birth_year IS NULL OR birth_year >= 1900",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_gender_code"),
        "user_extensions",
        "gender_code IS NULL OR gender_code IN "
        "('unspecified', 'female', 'male', 'non_binary', 'self_described', 'prefer_not_to_say')",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_gender_description"),
        "user_extensions",
        "gender_self_description IS NULL OR gender_code = 'self_described'",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_ui_locale"), "user_extensions", "ui_locale = 'zh-Hans'"
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_theme_mode"),
        "user_extensions",
        "theme_mode IN ('system', 'light', 'dark')",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_reduce_motion"),
        "user_extensions",
        "reduce_motion IN ('system', 'on')",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_reading_font_family"),
        "user_extensions",
        "reading_font_family IS NULL OR reading_font_family IN ('serif', 'sans')",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_reading_measures_positive"),
        "user_extensions",
        "(reading_font_size IS NULL OR reading_font_size > 0) "
        "AND (reading_line_height IS NULL OR reading_line_height > 0)",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_reading_theme"),
        "user_extensions",
        "reading_theme IS NULL OR reading_theme IN ('light', 'dark', 'sepia')",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_playback_speed"),
        "user_extensions",
        "playback_speed >= 0.70 AND playback_speed <= 1.50",
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_query_budget"),
        "user_extensions",
        "query_context_budget_tokens BETWEEN 1000 AND 64000",
    )
    op.execute(
        "COMMENT ON TABLE user_extensions IS "
        "'每个账号唯一的资料、学习档案和设置；可选字段缺失不阻止登录'"
    )
    op.create_table(
        "user_languages",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="当前账号归属"),
        sa.Column("language_kind", sa.String(8), nullable=False, comment="native或target"),
        sa.Column(
            "language_tag",
            sa.String(35),
            nullable=False,
            comment="已发布语言能力目录中的BCP-47标签",
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, comment="同一类语言的有序位置"),
        sa.Column(
            "self_assessed_level",
            sa.String(16),
            nullable=True,
            comment="目标语自评水平；母语必须为空",
        ),
        sa.Column(
            "learning_goals",
            postgresql.ARRAY(sa.String(24)),
            nullable=False,
            server_default=sa.text("'{}'"),
            comment="目标语受控学习目标；母语必须为空数组",
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_languages")),
        sa.UniqueConstraint(
            "user_id",
            "language_kind",
            "language_tag",
            name=op.f("uq_user_languages_user_id_language_kind_language_tag"),
        ),
        sa.UniqueConstraint(
            "user_id",
            "language_kind",
            "sort_order",
            name=op.f("uq_user_languages_user_id_language_kind_sort_order"),
        ),
        sa.CheckConstraint(
            "language_kind IN ('native', 'target')",
            name=op.f("ck_user_languages_language_kind"),
        ),
        sa.CheckConstraint("sort_order >= 0", name=op.f("ck_user_languages_sort_order")),
        sa.CheckConstraint(
            "cardinality(learning_goals) <= 8", name=op.f("ck_user_languages_goal_count")
        ),
        sa.CheckConstraint(
            "learning_goals <@ ARRAY['reading', 'textbook', 'exam', 'listening', "
            "'speaking', 'writing', 'vocabulary', 'grammar']::varchar[]",
            name=op.f("ck_user_languages_learning_goals"),
        ),
        sa.CheckConstraint(
            "(language_kind = 'native' AND self_assessed_level IS NULL "
            "AND cardinality(learning_goals) = 0) OR "
            "(language_kind = 'target' AND self_assessed_level IN "
            "('unknown', 'beginner', 'elementary', 'intermediate', 'advanced'))",
            name=op.f("ck_user_languages_kind_level"),
        ),
        comment="本人母语与目标语选择；删除偏好不删除学习历史",
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
    raise RuntimeError("profile settings require reviewed forward repair")
