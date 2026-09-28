"""Avatar upload intents and the published private avatar object.

This slice accepts avatar only. It does not open material upload, presigned
staging, or the storage reservation ledger. The published JPEG bytes live on
the file row so the API can read them without the jobs object-storage profile.
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
    UniqueConstraint,
)
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
    """A short-lived owner declaration for one avatar upload."""

    __tablename__ = "upload_intents"
    __table_args__ = (
        CheckConstraint("purpose = 'avatar'", name="purpose"),
        CheckConstraint("target_kind = 'user_extension'", name="target_kind"),
        CheckConstraint("target_resource_id = user_id", name="target_owner"),
        CheckConstraint("declared_format IN ('jpeg', 'png', 'webp')", name="declared_format"),
        CheckConstraint("expected_size_bytes BETWEEN 1 AND 5242880", name="expected_size"),
        CheckConstraint("octet_length(expected_sha256) = 32", name="expected_sha256"),
        CheckConstraint("status IN ('pending', 'completed', 'failed')", name="status"),
        CheckConstraint(
            "(status = 'completed' AND file_object_id IS NOT NULL AND failure_code IS NULL) OR "
            "(status IN ('pending', 'failed') AND file_object_id IS NULL)",
            name="completion",
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
                    business_relation(
                        "target_resource_id",
                        "user_extensions.user_id",
                        parent_lock=_LOCK,
                        service="app.services.avatar",
                        tests=_TESTS,
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


class FileObject(IdentityMixin, TimestampMixin, Base):
    """The immutable avatar published for one completed upload intent."""

    __tablename__ = "file_objects"
    __table_args__ = (
        UniqueConstraint("upload_intent_id"),
        CheckConstraint("purpose = 'avatar'", name="purpose"),
        CheckConstraint("media_type = 'image/jpeg'", name="media_type"),
        CheckConstraint("format_code = 'jpeg'", name="format_code"),
        CheckConstraint(
            "pixel_width = pixel_height AND pixel_width BETWEEN 1 AND 512",
            name="square_pixels",
        ),
        CheckConstraint(
            "octet_length(sha256) = 32 AND octet_length(content) = size_bytes "
            "AND size_bytes BETWEEN 1 AND 1048576",
            name="content_digest",
        ),
        CheckConstraint(
            "validation_profile = 'avatar-image-v1' "
            "AND processor_version = 'avatar-jpeg-square-v1'",
            name="processor",
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
    pixel_width: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="成品正方形边长",
        info=column_info("avatar image processor"),
    )
    pixel_height: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
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
    content: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="去元数据后的正方形JPEG，不记录原始文件",
        info=column_info("avatar image processor", "personal"),
    )
