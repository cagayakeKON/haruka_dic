"""Avatar upload intents and the private published avatar. No physical foreign keys.

Static DDL reviewed from the release model. Run only through controlled maintenance.
"""

import re

import sqlalchemy as sa
from alembic import op

revision = "0006_avatar_assets"
down_revision = "0005_profile_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "upload_intents",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="当前账号归属"),
        sa.Column("purpose", sa.String(40), nullable=False, comment="本切片只接受avatar"),
        sa.Column("target_kind", sa.String(40), nullable=False, comment="头像目标固定为本人资料"),
        sa.Column(
            "target_resource_id", sa.UUID(), nullable=False, comment="本人user_extensions.user_id"
        ),
        sa.Column(
            "declared_format",
            sa.String(32),
            nullable=False,
            comment="客户端声明的jpeg、png或webp，以实际字节为准",
        ),
        sa.Column(
            "expected_size_bytes",
            sa.BigInteger(),
            nullable=False,
            comment="原始上传字节的声明大小",
        ),
        sa.Column(
            "expected_sha256", sa.LargeBinary(), nullable=False, comment="原始上传字节的SHA-256"
        ),
        sa.Column("status", sa.String(24), nullable=False, comment="pending、completed或failed"),
        sa.Column(
            "file_object_id",
            sa.UUID(),
            nullable=True,
            comment="完成后的本人头像对象；完成前为空",
        ),
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            nullable=False,
            comment="意图截止时间，UTC",
        ),
        sa.Column(
            "failure_code",
            sa.String(80),
            nullable=True,
            comment="失败时的稳定错误码，不含文件内容",
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_upload_intents")),
        sa.CheckConstraint("purpose = 'avatar'", name=op.f("ck_upload_intents_purpose")),
        sa.CheckConstraint(
            "target_kind = 'user_extension'", name=op.f("ck_upload_intents_target_kind")
        ),
        sa.CheckConstraint(
            "target_resource_id = user_id", name=op.f("ck_upload_intents_target_owner")
        ),
        sa.CheckConstraint(
            "declared_format IN ('jpeg', 'png', 'webp')",
            name=op.f("ck_upload_intents_declared_format"),
        ),
        sa.CheckConstraint(
            "expected_size_bytes BETWEEN 1 AND 5242880",
            name=op.f("ck_upload_intents_expected_size"),
        ),
        sa.CheckConstraint(
            "octet_length(expected_sha256) = 32",
            name=op.f("ck_upload_intents_expected_sha256"),
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'completed', 'failed')",
            name=op.f("ck_upload_intents_status"),
        ),
        sa.CheckConstraint(
            "(status = 'completed' AND file_object_id IS NOT NULL AND failure_code IS NULL) OR "
            "(status IN ('pending', 'failed') AND file_object_id IS NULL)",
            name=op.f("ck_upload_intents_completion"),
        ),
        comment="本人头像的临时上传声明；完成前没有可读取对象",
    )
    op.create_index(
        "ix_upload_intents_owner_status",
        "upload_intents",
        ["user_id", "status", "expires_at", "id"],
    )
    op.create_table(
        "file_objects",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="当前账号归属"),
        sa.Column(
            "upload_intent_id", sa.UUID(), nullable=False, comment="发布此对象的本人上传意图"
        ),
        sa.Column("purpose", sa.String(40), nullable=False, comment="固定为avatar"),
        sa.Column("media_type", sa.String(127), nullable=False, comment="重编码后的image/jpeg"),
        sa.Column("format_code", sa.String(32), nullable=False, comment="重编码后的jpeg"),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False, comment="重编码成品的字节数"),
        sa.Column("sha256", sa.LargeBinary(), nullable=False, comment="重编码成品的SHA-256"),
        sa.Column(
            "validation_profile",
            sa.String(80),
            nullable=False,
            comment="头像解码与重编码规则",
        ),
        sa.Column("processor_version", sa.String(80), nullable=False, comment="头像处理器版本"),
        sa.Column(
            "validated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            comment="成品验证完成时间，UTC",
        ),
        sa.Column("pixel_width", sa.Integer(), nullable=False, comment="成品正方形边长"),
        sa.Column(
            "pixel_height", sa.Integer(), nullable=False, comment="成品正方形边长，与宽度相等"
        ),
        sa.Column(
            "retention_state", sa.String(24), nullable=False, comment="referenced或gc_pending"
        ),
        sa.Column(
            "gc_not_before_at",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="解除引用后的最早回收时间，UTC",
        ),
        sa.Column(
            "content",
            sa.LargeBinary(),
            nullable=False,
            comment="去元数据后的正方形JPEG，不记录原始文件",
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_file_objects")),
        sa.UniqueConstraint("upload_intent_id", name=op.f("uq_file_objects_upload_intent_id")),
        sa.CheckConstraint("purpose = 'avatar'", name=op.f("ck_file_objects_purpose")),
        sa.CheckConstraint("media_type = 'image/jpeg'", name=op.f("ck_file_objects_media_type")),
        sa.CheckConstraint("format_code = 'jpeg'", name=op.f("ck_file_objects_format_code")),
        sa.CheckConstraint(
            "pixel_width = pixel_height AND pixel_width BETWEEN 1 AND 512",
            name=op.f("ck_file_objects_square_pixels"),
        ),
        sa.CheckConstraint(
            "octet_length(sha256) = 32 AND octet_length(content) = size_bytes "
            "AND size_bytes BETWEEN 1 AND 1048576",
            name=op.f("ck_file_objects_content_digest"),
        ),
        sa.CheckConstraint(
            "validation_profile = 'avatar-image-v1' "
            "AND processor_version = 'avatar-jpeg-square-v1'",
            name=op.f("ck_file_objects_processor"),
        ),
        sa.CheckConstraint(
            "(retention_state = 'referenced' AND gc_not_before_at IS NULL) OR "
            "(retention_state = 'gc_pending' AND gc_not_before_at IS NOT NULL)",
            name=op.f("ck_file_objects_retention"),
        ),
        comment="已验证的本人头像成品；字节保存在本行，供每次鉴权后的私有读取",
    )
    op.create_index(
        "ix_file_objects_retention_gc",
        "file_objects",
        ["retention_state", "gc_not_before_at", "id"],
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "avatar_asset_id",
            sa.UUID(),
            nullable=True,
            comment="当前已验证头像；空表示无头像",
        ),
    )
    op.add_column(
        "user_extensions",
        sa.Column(
            "avatar_revision",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("0"),
            comment="头像指针版本，从0起",
        ),
    )
    op.create_check_constraint(
        op.f("ck_user_extensions_avatar_revision"),
        "user_extensions",
        "avatar_revision >= 0",
    )
    op.execute(
        "COMMENT ON TABLE user_extensions IS "
        "'每个账号唯一的资料、学习档案、设置和当前头像指针；可选字段缺失不阻止登录'"
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
    raise RuntimeError("avatar assets require reviewed forward repair")
