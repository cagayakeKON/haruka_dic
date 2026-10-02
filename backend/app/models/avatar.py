"""Purpose-restricted upload intents and immutable private source/avatar files.

Existing avatar JPEGs keep their inline storage contract. Material sources use
separate staging capabilities and verified private object-store final keys.
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

_LOCK = "lock users.id, then user_extensions, then the avatar upload intent"
_TESTS = "tests/integration/test_profile_avatar.py"


class UploadIntent(IdentityMixin, TimestampMixin, Base):
    """A purpose-restricted owner declaration for one temporary upload."""

    __tablename__ = "upload_intents"
    __table_args__ = (
        CheckConstraint(
            "jsonb_typeof(retired_final_candidates) = 'array' AND jsonb_array_length(retired_final_candidates) <= 16 AND (purpose = 'primary_document' OR (retired_final_candidates = '[]'::jsonb AND candidate_cleanup_due_at IS NULL))",
            name="candidate_retirement",
        ),
        CheckConstraint("purpose IN ('avatar','primary_document')", name="purpose"),
        CheckConstraint(
            "(purpose = 'avatar' AND target_kind = 'user_extension') OR (purpose = 'primary_document' AND target_kind = 'material_import')",
            name="target_kind",
        ),
        CheckConstraint("purpose != 'avatar' OR target_resource_id = user_id", name="target_owner"),
        CheckConstraint(
            "(purpose = 'avatar' AND declared_format IN ('jpeg','png','webp')) OR (purpose = 'primary_document' AND declared_format IN ('md','epub','pdf','png','jpeg','webp'))",
            name="declared_format",
        ),
        CheckConstraint(
            "expected_size_bytes > 0 AND (purpose != 'avatar' OR expected_size_bytes <= 5242880)",
            name="expected_size",
        ),
        CheckConstraint("octet_length(expected_sha256) = 32", name="expected_sha256"),
        CheckConstraint(
            "(purpose = 'avatar' AND status IN ('pending','completed','failed')) OR (purpose = 'primary_document' AND status IN ('awaiting_upload','verifying','completed','failed','cancelled','expired'))",
            name="status",
        ),
        CheckConstraint(
            "(status = 'completed' AND file_object_id IS NOT NULL AND failure_code IS NULL) OR "
            "(status != 'completed' AND file_object_id IS NULL)",
            name="completion",
        ),
        CheckConstraint("revision >= 1 AND completion_generation >= 0", name="versions"),
        CheckConstraint(
            "(purpose = 'avatar' AND material_type IS NULL AND storage_reservation_id IS NULL AND staging_object_key IS NULL) OR (purpose = 'primary_document' AND material_type IS NOT NULL AND material_type IN ('novel','textbook','exam') AND storage_reservation_id IS NOT NULL AND staging_object_key IS NOT NULL AND original_filename IS NOT NULL)",
            name="purpose_source",
        ),
        CheckConstraint(
            "((purpose = 'avatar' OR status != 'verifying') AND completion_lease_token IS NULL AND completion_lease_until_at IS NULL) OR (purpose = 'primary_document' AND status = 'verifying' AND completion_generation > 0 AND completion_lease_token IS NOT NULL AND completion_lease_until_at IS NOT NULL)",
            name="completion_lease",
        ),
        Index(
            "ix_upload_intents_staging_unique",
            "staging_object_key",
            unique=True,
            postgresql_where=text("staging_object_key IS NOT NULL"),
            info={"purpose": "private temporary key belongs to one intent"},
        ),
        Index(
            "ix_upload_intents_final_candidate_unique",
            "candidate_final_object_key",
            unique=True,
            postgresql_where=text("candidate_final_object_key IS NOT NULL"),
            info={"purpose": "fixed input key belongs to one completion generation"},
        ),
        Index(
            "ix_upload_intents_owner_status",
            "user_id",
            "status",
            "expires_at",
            "id",
            info={"purpose": "scan one owner's expiring avatar intents"},
        ),
        {
            "comment": "本人头像的临时上传声明；完成前没有可读取对象",
            "info": business_table_info(
                "user_owned",
                owner="user_id",
                relations=(
                    business_relation(
                        "user_id",
                        "users.id",
                        parent_lock=_LOCK,
                        service="app.services.avatar",
                        tests=_TESTS,
                    ),
                    {
                        **business_relation(
                            "target_resource_id",
                            "user_extensions.user_id",
                            parent_lock=_LOCK,
                            service="app.services.avatar",
                            tests=_TESTS,
                        ),
                        "alternative_targets": {"primary_document": "material_imports.id"},
                        "state_rule": "purpose avatar resolves user_extensions.user_id; primary_document resolves material_imports.id; owner is checked under each parent lock",
                    },
                    business_relation(
                        "storage_reservation_id",
                        "user_storage_reservations.id",
                        nullable=True,
                        parent_lock="lock users, storage state, reservation, library, import then upload",
                        service="app.services.material_imports",
                        tests="tests/integration/test_material_imports.py",
                    ),
                    business_relation(
                        "file_object_id",
                        "file_objects.id",
                        nullable=True,
                        parent_lock=_LOCK,
                        service="app.services.avatar",
                        tests=_TESTS,
                    ),
                ),
                module="account",
                entrances=("avatar service",),
                deletion="expire unused intents; retain a completed intent with its file object",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="当前账号归属",
        info=column_info("avatar service"),
    )
    purpose: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        comment="本切片只接受avatar",
        info=column_info("avatar service"),
    )
    target_kind: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        comment="头像目标固定为本人资料",
        info=column_info("avatar service"),
    )
    target_resource_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="本人user_extensions.user_id",
        info=column_info("avatar service"),
    )
    declared_format: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        comment="客户端声明的jpeg、png或webp，以实际字节为准",
        info=column_info("avatar service"),
    )
    expected_size_bytes: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="原始上传字节的声明大小",
        info=column_info("avatar service"),
    )
    expected_sha256: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="原始上传字节的SHA-256",
        info=column_info("avatar service"),
    )
    status: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="pending、completed或failed",
        info=column_info("avatar service"),
    )
    file_object_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="完成后的本人头像对象；完成前为空",
        info=column_info("avatar service"),
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="意图截止时间，UTC",
        info=column_info("avatar service"),
    )
    failure_code: Mapped[str | None] = mapped_column(
        String(80),
        nullable=True,
        comment="失败时的稳定错误码，不含文件内容",
        info=column_info("avatar service"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="上传意图版本",
        info=column_info("upload transaction"),
    )
    material_type: Mapped[str | None] = mapped_column(
        String(16), nullable=True, comment="仅主文件为三类之一", info=column_info("import contract")
    )
    original_filename: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="仅显示原文件名，不作为对象路径",
        info=column_info("validated import request", "personal"),
    )
    storage_reservation_id: Mapped[UUID | None] = mapped_column(
        PgUUID,
        nullable=True,
        comment="主文件本人容量预留",
        info=column_info("capacity transaction"),
    )
    staging_object_key: Mapped[str | None] = mapped_column(
        Text, nullable=True, comment="本人独占临时键", info=column_info("upload service")
    )
    completion_generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="完成领取代次",
        info=column_info("upload transaction"),
    )
    completion_lease_token: Mapped[UUID | None] = mapped_column(
        PgUUID, nullable=True, comment="完成租约fence", info=column_info("upload transaction")
    )
    completion_lease_until_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="完成租约UTC截止",
        info=column_info("upload transaction"),
    )
    candidate_final_object_key: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="本代次服务端独占固定副本键",
        info=column_info("immutable source validator"),
    )
    retired_final_candidates: Mapped[list[str]] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text("'[]'::jsonb"),
        comment="服务端退休候选键账本，持续可复查，不含已发布副本",
        info=column_info("source completion fence"),
    )
    candidate_cleanup_due_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="退休副本下一次有界复查UTC时间",
        info=column_info("source garbage collection"),
    )


class FileObject(IdentityMixin, TimestampMixin, Base):
    """An immutable private avatar or source published by a completed upload."""

    __tablename__ = "file_objects"
    __table_args__ = (
        UniqueConstraint("upload_intent_id"),
        CheckConstraint("purpose IN ('avatar','primary_document')", name="purpose"),
        CheckConstraint("purpose != 'avatar' OR media_type = 'image/jpeg'", name="media_type"),
        CheckConstraint(
            "(purpose = 'avatar' AND format_code = 'jpeg') OR (purpose = 'primary_document' AND format_code IN ('md','epub','pdf','png','jpeg','webp'))",
            name="format_code",
        ),
        CheckConstraint(
            "purpose != 'avatar' OR (pixel_width IS NOT NULL AND pixel_height IS NOT NULL AND pixel_width = pixel_height AND pixel_width BETWEEN 1 AND 512)",
            name="square_pixels",
        ),
        CheckConstraint(
            "octet_length(sha256) = 32 AND size_bytes > 0 AND "
            "((purpose = 'avatar' AND content IS NOT NULL AND octet_length(content) = size_bytes AND size_bytes <= 1048576 AND bucket_name IS NULL AND object_key IS NULL) OR "
            "(purpose = 'primary_document' AND content IS NULL AND bucket_name IS NOT NULL AND object_key IS NOT NULL))",
            name="content_digest",
        ),
        CheckConstraint(
            "(purpose = 'avatar' AND validation_profile = 'avatar-image-v1' AND processor_version = 'avatar-jpeg-square-v1') OR "
            "(purpose = 'primary_document' AND validation_profile = 'material-source-v1' AND processor_version = 'immutable-source-v1')",
            name="processor",
        ),
        CheckConstraint(
            "(pixel_width IS NULL AND pixel_height IS NULL) OR (pixel_width IS NOT NULL AND pixel_height IS NOT NULL AND pixel_width > 0 AND pixel_height > 0)",
            name="pixel_pair",
        ),
        Index(
            "ix_file_objects_final_key_unique",
            "bucket_name",
            "object_key",
            unique=True,
            postgresql_where=text("object_key IS NOT NULL"),
            info={"purpose": "immutable private source object identity"},
        ),
        CheckConstraint(
            "(retention_state = 'referenced' AND gc_not_before_at IS NULL) OR "
            "(retention_state = 'gc_pending' AND gc_not_before_at IS NOT NULL)",
            name="retention",
        ),
        Index(
            "ix_file_objects_retention_gc",
            "retention_state",
            "gc_not_before_at",
            "id",
            info={"purpose": "find avatar objects whose pointer was released"},
        ),
        {
            "comment": "已验证的本人头像成品；字节保存在本行，供每次鉴权后的私有读取",
            "info": business_table_info(
                "user_owned",
                owner="user_id",
                relations=(
                    business_relation(
                        "user_id",
                        "users.id",
                        parent_lock=_LOCK,
                        service="app.services.avatar",
                        tests=_TESTS,
                    ),
                    business_relation(
                        "upload_intent_id",
                        "upload_intents.id",
                        parent_lock=_LOCK,
                        service="app.services.avatar",
                        tests=_TESTS,
                    ),
                ),
                module="account",
                entrances=("avatar service",),
                deletion="mark gc_pending when the profile pointer moves; bytes stay until GC",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="当前账号归属",
        info=column_info("avatar service", "personal"),
    )
    upload_intent_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="发布此对象的本人上传意图",
        info=column_info("avatar service"),
    )
    purpose: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        comment="固定为avatar",
        info=column_info("avatar service"),
    )
    media_type: Mapped[str] = mapped_column(
        String(127),
        nullable=False,
        comment="重编码后的image/jpeg",
        info=column_info("avatar image processor"),
    )
    format_code: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        comment="重编码后的jpeg",
        info=column_info("avatar image processor"),
    )
    size_bytes: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="重编码成品的字节数",
        info=column_info("avatar image processor"),
    )
    sha256: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="重编码成品的SHA-256",
        info=column_info("avatar image processor"),
    )
    validation_profile: Mapped[str] = mapped_column(
        String(80),
        nullable=False,
        comment="头像解码与重编码规则",
        info=column_info("avatar image processor"),
    )
    processor_version: Mapped[str] = mapped_column(
        String(80),
        nullable=False,
        comment="头像处理器版本",
        info=column_info("avatar image processor"),
    )
    validated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="成品验证完成时间，UTC",
        info=column_info("avatar service"),
    )
    pixel_width: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="成品正方形边长",
        info=column_info("avatar image processor"),
    )
    pixel_height: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="成品正方形边长，与宽度相等",
        info=column_info("avatar image processor"),
    )
    retention_state: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="referenced或gc_pending",
        info=column_info("avatar service"),
    )
    gc_not_before_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="解除引用后的最早回收时间，UTC",
        info=column_info("avatar service"),
    )
    content: Mapped[bytes | None] = mapped_column(
        LargeBinary,
        nullable=True,
        comment="去元数据后的正方形JPEG，不记录原始文件",
        info=column_info("avatar image processor", "personal"),
    )
    bucket_name: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="材料私有bucket，旧头像为空",
        info=column_info("immutable source publication"),
    )
    object_key: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="只有服务端可写的材料final键",
        info=column_info("immutable source publication"),
    )
