"""Owned import intents and transactionally accounted private source capacity."""

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
from app.models.learning_reference import LibraryScopeMixin

_LOCK = "current identity, users, user_storage_states, reservation, library, import, material, upload intent; same-kind parents by UUID"
_SERVICE = "app.services.material_imports"
_TESTS = "tests/integration/test_material_imports.py"


def _info(
    owner: str, relations: tuple[tuple[str, str, bool], ...], *, library: bool = False
) -> dict[str, object]:
    return business_table_info(
        "library_owned" if library else "user_owned",
        owner=owner,
        relations=tuple(
            business_relation(
                column, target, nullable=nullable, parent_lock=_LOCK, service=_SERVICE, tests=_TESTS
            )
            for column, target, nullable in relations
        ),
        module="material_imports",
        entrances=("authorized material import", "fenced source worker"),
        deletion="release uncommitted reservation only after fencing publication; preserve accepted source references",
    )


class UserStorageState(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "user_storage_states"
    __table_args__ = (
        UniqueConstraint("user_id"),
        CheckConstraint("used_bytes >= 0 AND reserved_bytes >= 0 AND revision >= 1", name="counts"),
        {
            "comment": "本人已发布字节及在途容量的锁根",
            "info": _info("user_id", (("user_id", "users.id", False),)),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="当前账号", info=column_info("locked user")
    )
    used_bytes: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="保留的已发布实际字节",
        info=column_info("capacity settlement"),
    )
    reserved_bytes: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="尚未结算的承诺字节",
        info=column_info("capacity reservation"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="容量计数版本",
        info=column_info("capacity transaction"),
    )


class UserStorageReservation(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "user_storage_reservations"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "target_kind",
            "target_resource_id",
            name="uq_storage_reservation_owner_target",
        ),
        CheckConstraint("target_kind = 'upload_intent'", name="target_kind"),
        CheckConstraint(
            "reserved_bytes > 0 AND committed_bytes >= 0 AND revision >= 1", name="counts"
        ),
        CheckConstraint("status IN ('reserved','committed','released')", name="status"),
        CheckConstraint(
            "(status = 'committed' AND committed_bytes > 0) OR (status != 'committed' AND committed_bytes = 0)",
            name="settlement",
        ),
        Index(
            "ix_user_storage_reservations_owner_status",
            "user_id",
            "status",
            "expires_at",
            "id",
            info={"purpose": "bounded owner capacity reconciliation"},
        ),
        {
            "comment": "一次上传意图的本人幂等容量预留",
            "info": _info(
                "user_id",
                (
                    ("user_id", "users.id", False),
                    ("target_resource_id", "upload_intents.id", False),
                ),
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="当前账号", info=column_info("locked user")
    )
    target_kind: Mapped[str] = mapped_column(
        String(40), nullable=False, comment="上传意图目标", info=column_info("import transaction")
    )
    target_resource_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人上传意图", info=column_info("import transaction")
    )
    reserved_bytes: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="承诺字节", info=column_info("capacity reservation")
    )
    committed_bytes: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="发布后结算字节",
        info=column_info("verified immutable file"),
    )
    status: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="reserved committed released",
        info=column_info("capacity transaction"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="预留版本",
        info=column_info("capacity transaction"),
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="预留截止UTC",
        info=column_info("upload policy"),
    )


class MaterialImport(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "material_imports"
    __table_args__ = (
        UniqueConstraint("owner_user_id", "idempotency_record_id"),
        CheckConstraint(
            "material_type IN ('novel','textbook','exam') AND target_language IN ('ja','en')",
            name="type_language",
        ),
        CheckConstraint("revision >= 1 AND schema_version = 1", name="versions"),
        CheckConstraint(
            "(primary_upload_intent_id IS NOT NULL AND reused_material_id IS NULL AND reused_file_object_id IS NULL) OR (primary_upload_intent_id IS NULL AND reused_material_id IS NOT NULL AND reused_file_object_id IS NOT NULL)",
            name="source_choice",
        ),
        CheckConstraint(
            "status IN ('awaiting_upload','verifying','accepted','expired','cancelled','rejected')",
            name="status",
        ),
        CheckConstraint(
            "(material_id IS NULL AND initial_job_id IS NULL AND status != 'accepted') OR (material_id IS NOT NULL AND initial_job_id IS NOT NULL AND status = 'accepted')",
            name="accepted_results",
        ),
        CheckConstraint(
            'requested_stages = \'{"extract": true, "analyze": false}\'::jsonb',
            name="requested_stages",
        ),
        Index(
            "ix_material_imports_owner_status",
            "owner_user_id",
            "library_id",
            "status",
            "created_at",
            "id",
            info={"purpose": "owner pending source imports"},
        ),
        {
            "comment": "三类材料的显式无模型源导入意图",
            "info": _info(
                "owner_user_id",
                (
                    ("owner_user_id", "users.id", False),
                    ("library_id", "libraries.id", False),
                    ("primary_upload_intent_id", "upload_intents.id", True),
                    ("reused_material_id", "materials.id", True),
                    ("reused_file_object_id", "file_objects.id", True),
                    ("idempotency_record_id", "idempotency_records.id", False),
                    ("material_id", "materials.id", True),
                    ("initial_job_id", "jobs.id", True),
                ),
                library=True,
            ),
        },
    )
    material_type: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        comment="固定材料类型",
        info=column_info("validated import request"),
    )
    target_language: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="声明日语或英语；发布前重验",
        info=column_info("validated import request"),
    )
    requested_title: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="用户显式标题",
        info=column_info("validated import request", "personal"),
    )
    reused_material_id: Mapped[UUID | None] = mapped_column(
        PgUUID,
        nullable=True,
        comment="本人被复用的来源材料根",
        info=column_info("locked owned source"),
    )
    reused_file_object_id: Mapped[UUID | None] = mapped_column(
        PgUUID,
        nullable=True,
        comment="源根锁内验证的不可变原件",
        info=column_info("locked owned source"),
    )
    primary_upload_intent_id: Mapped[UUID | None] = mapped_column(
        PgUUID, nullable=True, comment="本次原件上传意图", info=column_info("import transaction")
    )
    schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="载荷版本1", info=column_info("import contract")
    )
    requested_stages: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="明确仅确定性提取，无模型分析",
        info=column_info("validated import request"),
    )
    status: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="导入意图状态", info=column_info("import transaction")
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="导入并发版本",
        info=column_info("import transaction"),
    )
    idempotency_record_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人动作幂等回执", info=column_info("import transaction")
    )
    material_id: Mapped[UUID | None] = mapped_column(
        PgUUID, nullable=True, comment="原件验证后材料根", info=column_info("source acceptance")
    )
    initial_job_id: Mapped[UUID | None] = mapped_column(
        PgUUID, nullable=True, comment="无模型来源Job", info=column_info("source acceptance")
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="待上传截止UTC",
        info=column_info("upload policy"),
    )


class MaterialSourceAsset(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    """An owned immutable primary file bound to a precise candidate source version."""

    __tablename__ = "material_source_assets"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "library_id",
            "material_revision_id",
            "ordinal",
            name="uq_material_source_asset_version_ordinal",
        ),
        CheckConstraint("ordinal > 0 AND purpose = 'primary_document'", name="source_role"),
        CheckConstraint(
            "(pixel_width IS NULL AND pixel_height IS NULL) OR (pixel_width IS NOT NULL AND pixel_height IS NOT NULL AND pixel_width > 0 AND pixel_height > 0)",
            name="pixels",
        ),
        CheckConstraint("duration_ms IS NULL OR duration_ms >= 0", name="duration"),
        Index(
            "ix_material_source_assets_owner_file",
            "owner_user_id",
            "library_id",
            "file_object_id",
            "id",
            info={"purpose": "same-owner immutable file retention references"},
        ),
        {
            "comment": "确切源版本的本人不可变主文档资产",
            "info": _info(
                "owner_user_id",
                (
                    ("owner_user_id", "users.id", False),
                    ("library_id", "libraries.id", False),
                    ("material_id", "materials.id", False),
                    ("material_revision_id", "material_revisions.id", False),
                    ("file_object_id", "file_objects.id", False),
                ),
                library=True,
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="共同材料父根", info=column_info("locked material")
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID,
        nullable=False,
        comment="确切候选或发布源版本",
        info=column_info("locked source revision"),
    )
    file_object_id: Mapped[UUID] = mapped_column(
        PgUUID,
        nullable=False,
        comment="本人的不可变已验证原件",
        info=column_info("verified source file"),
    )
    purpose: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        comment="当前主文档资产角色",
        info=column_info("source acceptance"),
    )
    ordinal: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="版本内资产正序号", info=column_info("source acceptance")
    )
    source_locator: Mapped[dict[str, object] | None] = mapped_column(
        JSONB, nullable=True, comment="仅验证过的原件位置", info=column_info("source validator")
    )
    pixel_width: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="实际图像宽；文字源为空",
        info=column_info("source validator"),
    )
    pixel_height: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="实际图像高；文字源为空",
        info=column_info("source validator"),
    )
    duration_ms: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="实际媒体时长；主文档为空",
        info=column_info("source validator"),
    )


class MaterialImportIssue(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    """A mutable language gate linked to unpublished input and committed job checkpoint."""

    __tablename__ = "material_import_issues"
    __table_args__ = (
        CheckConstraint(
            "revision >= 1 AND schema_version = 1 AND job_generation >= 1 AND input_delete_generation >= 0 AND octet_length(input_digest) = 32",
            name="versions",
        ),
        CheckConstraint(
            "kind = 'language_confirmation_required' AND stage_code = 'language_assessment' AND severity = 'blocking'",
            name="language_gate",
        ),
        CheckConstraint(
            "(status = 'open' AND resolution_code IS NULL AND resolved_by_user_id IS NULL AND resolved_at IS NULL) OR (status IN ('resolved','accepted') AND resolution_code IS NOT NULL AND resolved_at IS NOT NULL)",
            name="resolution",
        ),
        Index(
            "ix_material_import_issues_owner_version_status",
            "owner_user_id",
            "library_id",
            "material_revision_id",
            "status",
            "severity",
            "id",
            info={"purpose": "bounded source-language confirmation issues"},
        ),
        {
            "comment": "未发布源版本的语言确认Issue与实际输入检查点",
            "info": _info(
                "owner_user_id",
                (
                    ("owner_user_id", "users.id", False),
                    ("library_id", "libraries.id", False),
                    ("material_id", "materials.id", False),
                    ("material_revision_id", "material_revisions.id", False),
                    ("file_object_id", "file_objects.id", False),
                    ("job_id", "jobs.id", False),
                    ("resolved_by_user_id", "users.id", True),
                ),
                library=True,
            ),
        },
    )
    material_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="共同材料父根", info=column_info("locked material")
    )
    material_revision_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="待发布源版本", info=column_info("locked source revision")
    )
    file_object_id: Mapped[UUID] = mapped_column(
        PgUUID,
        nullable=False,
        comment="确切不可变原件",
        info=column_info("committed language checkpoint"),
    )
    job_id: Mapped[UUID] = mapped_column(
        PgUUID,
        nullable=False,
        comment="已受理无模型Job",
        info=column_info("committed language checkpoint"),
    )
    job_generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="判断阶段代次",
        info=column_info("committed language checkpoint"),
    )
    input_delete_generation: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="输入材料删除代次", info=column_info("locked material")
    )
    input_digest: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="确切判断输入摘要",
        info=column_info("committed language checkpoint"),
    )
    stage_code: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        comment="注册语言判断阶段",
        info=column_info("job stage registry"),
    )
    kind: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        comment="语言确认原因种类",
        info=column_info("language assessment"),
    )
    severity: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        comment="当前仅blocking",
        info=column_info("language assessment"),
    )
    status: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="open resolved accepted",
        info=column_info("source confirmation"),
    )
    source_refs: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="有界出处与已保存提取结果引用，不含原文",
        info=column_info("committed language checkpoint"),
    )
    schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="Issue载荷版本1", info=column_info("source contract")
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="确认CAS版本",
        info=column_info("source confirmation"),
    )
    resolution_code: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        comment="明确确认或确定修订代码",
        info=column_info("source confirmation"),
    )
    resolved_by_user_id: Mapped[UUID | None] = mapped_column(
        PgUUID,
        nullable=True,
        comment="实际本人确认者，确定性修复可为空",
        info=column_info("authenticated scope"),
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="关闭提交UTC",
        info=column_info("source confirmation"),
    )
