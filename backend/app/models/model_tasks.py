"""Owner scoped provider secrets and fenced persistent model execution."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
    LargeBinary,
    String,
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
    identifier,
)


def info(scope: str = "user_owned") -> dict[str, object]:
    return business_table_info(
        scope,
        owner="owner_user_id" if scope == "user_owned" else None,
        module="model_tasks",
        entrances=("authorized provider configuration", "fenced model worker"),
        deletion="retain task history; revoke and erase credential ciphertext",
    )


class ProviderCredential(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "user_provider_credentials"
    __table_args__ = (
        CheckConstraint("provider IN ('openrouter','gemini')", name="provider"),
        CheckConstraint("revision >= 1 AND credential_version >= 1", name="versions"),
        CheckConstraint(
            "state IN ('active','revoked') AND ((state='active' AND encrypted_secret IS NOT NULL AND revoked_at IS NULL) OR (state='revoked' AND encrypted_secret IS NULL AND revoked_at IS NOT NULL))",
            name="state",
        ),
        Index("ix_user_provider_credentials_user_state", "user_id", "state", "created_at", "id"),
        {"comment": "本人供应商凭据密文与独立代次", "info": info() | {"owner_column": "user_id"}},
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        "user_id",
        PgUUID,
        nullable=False,
        comment="认证绑定本人",
        info=column_info("authenticated scope"),
    )
    provider: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="供应商", info=column_info("allowed provider")
    )
    label: Mapped[str] = mapped_column(
        "display_label",
        String(100),
        nullable=False,
        comment="本人标签",
        info=column_info("validated input"),
    )
    encrypted_key: Mapped[bytes | None] = mapped_column(
        "encrypted_secret",
        LargeBinary,
        nullable=True,
        comment="独立部署密钥封装",
        info=column_info("credential crypto", "secret"),
    )
    encryption_key_version: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="部署加密版本", info=column_info("keyring")
    )
    masked_key: Mapped[str] = mapped_column(
        "masked_hint",
        String(32),
        nullable=False,
        comment="安全掩码",
        info=column_info("credential crypto"),
    )
    credential_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="供应商秘密代次",
        info=column_info("credential service"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="行CAS版本",
        info=column_info("credential service"),
    )
    status: Mapped[str] = mapped_column(
        "state",
        String(16),
        nullable=False,
        server_default=text("'active'"),
        comment="使用状态",
        info=column_info("credential service"),
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="撤销提交时间",
        info=column_info("credential service"),
    )


class ModelCatalogEntry(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "model_catalog_entries"
    __table_args__ = (
        CheckConstraint(
            'jsonb_typeof(capabilities)=\'array\' AND capabilities <@ \'["text","vision","tts"]\'::jsonb',
            name="capabilities",
        ),
        UniqueConstraint("provider", "model_code"),
        CheckConstraint("revision >= 1", name="revision"),
        {"comment": "发布注册精确模型能力", "info": info("system_catalog")},
    )
    provider: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="发布供应商", info=column_info("release registry")
    )
    model_code: Mapped[str] = mapped_column(
        String(256), nullable=False, comment="精确模型", info=column_info("release registry")
    )
    display_name: Mapped[str] = mapped_column(
        String(100), nullable=False, comment="显示名", info=column_info("release registry")
    )
    capabilities: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, comment="已支持能力", info=column_info("release registry")
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("false"),
        comment="新调用启停",
        info=column_info("catalog service"),
    )
    verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="真实协议验证时间",
        info=column_info("authorized protocol verification"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="目录版本",
        info=column_info("catalog service"),
    )
    adapter_id: Mapped[str | None] = mapped_column(
        "adapter_code",
        String(128),
        nullable=True,
        comment="精确TTS适配器",
        info=column_info("release registry"),
    )


class ModelLimitPolicy(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "runtime_limit_policies"
    __table_args__ = (
        UniqueConstraint("subject_kind", "limit_code"),
        CheckConstraint("value_limit >= 0 AND revision >= 1", name="limits"),
        {"comment": "受控模型技术上限", "info": info("system_catalog")},
    )
    subject_kind: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="user_default或instance",
        info=column_info("release registry"),
    )
    limit_code: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="注册限制维度", info=column_info("release registry")
    )
    value_limit: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="0禁止新动作", info=column_info("limit service")
    )
    window_seconds: Mapped[int | None] = mapped_column(
        Integer, nullable=True, comment="窗口秒数", info=column_info("release registry")
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("true"),
        comment="策略启停",
        info=column_info("limit service"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="策略CAS",
        info=column_info("limit service"),
    )


class UserRuntimeLimit(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "user_runtime_limits"
    __table_args__ = (
        UniqueConstraint("user_id", "limit_code"),
        CheckConstraint("value_limit >= 0 AND revision >= 1", name="limits"),
        {"comment": "本人技术保护覆盖；管理元数据", "info": info() | {"owner_column": "user_id"}},
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        "user_id",
        PgUUID,
        nullable=False,
        comment="目标账号",
        info=column_info("authorized admin target"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="覆盖CAS",
        info=column_info("limit service"),
    )
    limit_code: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="注册维度", info=column_info("limit service")
    )
    value_limit: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="个人限制；0拒新动作", info=column_info("limit service")
    )
    window_seconds: Mapped[int | None] = mapped_column(
        Integer, nullable=True, comment="窗口秒数", info=column_info("release registry")
    )


class UserModelBinding(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "user_model_bindings"
    __table_args__ = (
        UniqueConstraint("user_id", "capability"),
        Index("ix_user_model_bindings_user_credential", "user_id", "credential_id"),
        {
            "comment": "本人模型选择；settings_revision保护",
            "info": info() | {"owner_column": "user_id"},
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人", info=column_info("locked extension")
    )
    capability: Mapped[str] = mapped_column(
        String(12), nullable=False, comment="能力", info=column_info("configuration service")
    )
    credential_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人凭据", info=column_info("locked credential")
    )
    model_catalog_entry_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="发布模型", info=column_info("locked catalog")
    )
    parameters_schema_version: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        server_default=text("1"),
        comment="参数schema",
        info=column_info("release registry"),
    )
    parameters: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text("'{}'::jsonb"),
        comment="有界合成参数",
        info=column_info("configuration service"),
    )


class VoiceCatalogEntry(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "voice_catalog_entries"
    __table_args__ = (
        UniqueConstraint("model_catalog_entry_id", "voice_code", "language_tag"),
        {"comment": "发布准确声音目录", "info": info("system_catalog")},
    )
    model_catalog_entry_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="模型根", info=column_info("release registry")
    )
    voice_code: Mapped[str] = mapped_column(
        String(128), nullable=False, comment="声音标识", info=column_info("release registry")
    )
    language_tag: Mapped[str] = mapped_column(
        String(35), nullable=False, comment="语言", info=column_info("release registry")
    )
    display_name: Mapped[str] = mapped_column(
        String(100), nullable=False, comment="声音显示名", info=column_info("release registry")
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("false"),
        comment="允许新合成",
        info=column_info("catalog service"),
    )
    verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="真实协议证据",
        info=column_info("authorized verification"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="目录版本",
        info=column_info("catalog service"),
    )


class Job(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "jobs"
    __table_args__ = (
        CheckConstraint(
            "generation >= 1 AND revision >= 1 AND fence >= 0 AND progress_seq >= 0",
            name="versions",
        ),
        CheckConstraint(
            "state IN ('queued','running','retry_wait','blocked','succeeded','failed','cancel_requested','cancelled')",
            name="state",
        ),
        CheckConstraint(
            "(operation_kind = 'credential_test' AND credential_id IS NOT NULL AND run_id IS NOT NULL) OR "
            "(operation_kind = 'material_import' AND credential_id IS NULL AND run_id IS NULL)",
            name="operation_references",
        ),
        UniqueConstraint("owner_user_id", "idempotency_digest"),
        Index("ix_jobs_owner_state", "owner_user_id", "state", "created_at", "id"),
        Index("ix_jobs_lease", "state", "lease_expires_at"),
        {"comment": "本人持久模型任务及租约栅栏", "info": info()},
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人归属", info=column_info("authenticated scope")
    )
    actor_user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="发起人", info=column_info("authenticated scope")
    )
    session_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="受理会话", info=column_info("authenticated scope")
    )
    transport: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="受理传输", info=column_info("authenticated scope")
    )
    audience: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="受理受众", info=column_info("authenticated scope")
    )
    credential_id: Mapped[UUID | None] = mapped_column(
        PgUUID,
        nullable=True,
        comment="模型任务本人凭据；确定性材料任务为空",
        info=column_info("locked credential"),
    )
    run_id: Mapped[UUID | None] = mapped_column(
        PgUUID,
        nullable=True,
        comment="模型运行引用；确定性材料任务为空",
        info=column_info("job transaction"),
    )
    operation_kind: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="受控动作", info=column_info("job transaction")
    )
    operation_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="操作关联", info=column_info("request context")
    )
    request_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="请求关联", info=column_info("request context")
    )
    input_refs: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        comment="安全固定样本及配置版本引用",
        info=column_info("job transaction"),
    )
    input_digest: Mapped[bytes] = mapped_column(
        LargeBinary, nullable=False, comment="输入摘要", info=column_info("job transaction")
    )
    idempotency_digest: Mapped[bytes] = mapped_column(
        LargeBinary, nullable=False, comment="本人意图摘要", info=column_info("job transaction")
    )
    state: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        server_default=text("'queued'"),
        comment="任务状态",
        info=column_info("job service"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="任务CAS",
        info=column_info("job service"),
    )
    generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="执行代次",
        info=column_info("job service"),
    )
    progress_seq: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="持久进度序号",
        info=column_info("job service"),
    )
    fence: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="领取栅栏",
        info=column_info("job service"),
    )
    lease_owner: Mapped[str | None] = mapped_column(
        String(128), nullable=True, comment="Worker标识", info=column_info("worker")
    )
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="租约期限", info=column_info("worker")
    )
    heartbeat_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="心跳", info=column_info("worker")
    )
    error_code: Mapped[str | None] = mapped_column(
        String(96), nullable=True, comment="受控错误", info=column_info("worker")
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="任务终态时间", info=column_info("worker")
    )


class JobStage(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "job_stages"
    __table_args__ = (
        UniqueConstraint("job_id", "job_generation", "stage_key"),
        {"comment": "已提交安全阶段恢复点", "info": info()},
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人", info=column_info("job scope")
    )
    job_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="父任务", info=column_info("locked job")
    )
    job_generation: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="任务代次", info=column_info("locked job")
    )
    stage_key: Mapped[str] = mapped_column(
        String(96), nullable=False, comment="注册阶段", info=column_info("worker registry")
    )
    state: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="阶段状态", info=column_info("worker")
    )
    fence: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="领取栅栏",
        info=column_info("worker"),
    )
    result_refs: Mapped[dict[str, object] | None] = mapped_column(
        JSONB, nullable=True, comment="安全恢复成品", info=column_info("worker")
    )


class AiRun(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "ai_runs"
    __table_args__ = (
        Index(
            "ix_ai_runs_owner_credential_test",
            "owner_user_id",
            "credential_id",
            "credential_version",
            "model_id",
            "capability",
            "finished_at",
        ),
        {"comment": "本人模型测试运行安全事实", "info": info()},
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人", info=column_info("job scope")
    )
    job_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="任务", info=column_info("locked job")
    )
    credential_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="凭据身份", info=column_info("locked credential")
    )
    credential_version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="秘密代次", info=column_info("locked credential")
    )
    provider: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="供应商", info=column_info("frozen config")
    )
    model_id: Mapped[str] = mapped_column(
        String(256), nullable=False, comment="精确模型", info=column_info("frozen config")
    )
    model_revision: Mapped[str | None] = mapped_column(
        String(128),
        nullable=True,
        comment="已观测修订未知NULL",
        info=column_info("provider response"),
    )
    capability: Mapped[str] = mapped_column(
        String(12), nullable=False, comment="单能力", info=column_info("frozen config")
    )
    state: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="运行状态", info=column_info("worker")
    )
    generation: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="运行代次", info=column_info("job scope")
    )
    generation_config: Mapped[dict[str, object]] = mapped_column(
        JSONB, nullable=False, comment="冻结模型及调用上限", info=column_info("job transaction")
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="测试时间", info=column_info("worker")
    )
    error_code: Mapped[str | None] = mapped_column(
        String(96), nullable=True, comment="安全错误", info=column_info("worker")
    )


class ExternalCallAttempt(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "external_call_attempts"
    __table_args__ = (
        UniqueConstraint("owner_user_id", "ai_run_id", "attempt_no"),
        CheckConstraint("status IN ('started','succeeded','failed','unknown')", name="status"),
        CheckConstraint(
            "usage_status IN ('complete','partial','unavailable')", name="usage_status"
        ),
        Index("ix_external_call_attempts_owner_started", "owner_user_id", "started_at", "id"),
        {"comment": "实际attempt与用量唯一权威事实", "info": info()},
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人", info=column_info("job scope")
    )
    job_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="任务", info=column_info("locked job")
    )
    ai_run_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="运行", info=column_info("locked run")
    )
    credential_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="凭据", info=column_info("locked credential")
    )
    credential_version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="实际秘密代次", info=column_info("locked credential")
    )
    provider: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="供应商", info=column_info("frozen config")
    )
    model_id: Mapped[str] = mapped_column(
        String(256), nullable=False, comment="精确模型", info=column_info("frozen config")
    )
    capability: Mapped[str] = mapped_column(
        String(12), nullable=False, comment="能力", info=column_info("frozen config")
    )
    operation_kind: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="动作", info=column_info("frozen config")
    )
    attempt_no: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="真实调用序号", info=column_info("worker")
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="外部执行事实", info=column_info("worker")
    )
    usage_status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        server_default=text("'unavailable'"),
        comment="用量完整性",
        info=column_info("provider response"),
    )
    usage: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text("'{}'::jsonb"),
        comment="白名单数字及未知NULL",
        info=column_info("provider response"),
    )
    provider_usage_schema: Mapped[str | None] = mapped_column(
        String(64), nullable=True, comment="用量口径版本", info=column_info("adapter")
    )
    simulated: Mapped[bool] = mapped_column(
        Boolean, nullable=False, comment="受控模拟事实", info=column_info("runtime assembly")
    )
    aggregation_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="补全版本",
        info=column_info("worker"),
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, comment="调用前落盘", info=column_info("worker")
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="外部结束", info=column_info("worker")
    )
    error_code: Mapped[str | None] = mapped_column(
        String(96), nullable=True, comment="受控错误", info=column_info("adapter")
    )
    input_tokens: Mapped[int | None] = mapped_column(
        BigInteger, nullable=True, comment="输入Token；未知NULL", info=column_info("provider usage")
    )
    output_tokens: Mapped[int | None] = mapped_column(
        BigInteger, nullable=True, comment="输出Token；未知NULL", info=column_info("provider usage")
    )
    total_tokens: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="供应商总Token；未知NULL",
        info=column_info("provider usage"),
    )
    cache_read_tokens: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="缓存读取Token；未知NULL",
        info=column_info("provider usage"),
    )
    cache_write_tokens: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="缓存写入Token；未知NULL",
        info=column_info("provider usage"),
    )
    reasoning_tokens: Mapped[int | None] = mapped_column(
        BigInteger, nullable=True, comment="推理Token；未知NULL", info=column_info("provider usage")
    )
    input_audio_tokens: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="输入音频Token；未知NULL",
        info=column_info("provider usage"),
    )
    output_audio_tokens: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="输出音频Token；未知NULL",
        info=column_info("provider usage"),
    )
    input_images: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="输入图片数；未知NULL",
        info=column_info("provider usage"),
    )
    input_characters: Mapped[int | None] = mapped_column(
        BigInteger,
        nullable=True,
        comment="输入字符数；未知NULL",
        info=column_info("provider usage"),
    )


class InboxEvent(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "inbox_events"
    __table_args__ = (
        UniqueConstraint("consumer_name", "event_id"),
        {"comment": "业务提交后消费去重事实", "info": info("system_operation")},
    )
    consumer_name: Mapped[str] = mapped_column(
        String(96), nullable=False, comment="固定消费者", info=column_info("worker")
    )
    event_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="发布事件", info=column_info("outbox")
    )
    payload_digest: Mapped[bytes] = mapped_column(
        LargeBinary, nullable=False, comment="事件安全摘要", info=column_info("worker")
    )
    processed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, comment="提交时点", info=column_info("worker")
    )


# Explicit logical-reference registry, consumed by the normal dictionary gate.
_REFERENCES = {
    "user_provider_credentials": {"user_id": "users.id"},
    "user_runtime_limits": {"user_id": "users.id"},
    "user_model_bindings": {
        "user_id": "users.id",
        "credential_id": "user_provider_credentials.id",
        "model_catalog_entry_id": "model_catalog_entries.id",
    },
    "voice_catalog_entries": {"model_catalog_entry_id": "model_catalog_entries.id"},
    "jobs": {
        "owner_user_id": "users.id",
        "actor_user_id": "users.id",
        "session_id": "user_auth_sessions.id",
        "credential_id": "user_provider_credentials.id",
        "run_id": "ai_runs.id",
    },
    "job_stages": {"owner_user_id": "users.id", "job_id": "jobs.id"},
    "ai_runs": {
        "owner_user_id": "users.id",
        "job_id": "jobs.id",
        "credential_id": "user_provider_credentials.id",
    },
    "external_call_attempts": {
        "owner_user_id": "users.id",
        "job_id": "jobs.id",
        "ai_run_id": "ai_runs.id",
        "credential_id": "user_provider_credentials.id",
    },
    "inbox_events": {"event_id": "outbox_events.id"},
}
for _table_name, _refs in _REFERENCES.items():
    _table = Base.metadata.tables[_table_name]
    _table.info["logical_relations"] = [
        business_relation(
            _column,
            _target,
            nullable=bool(_table.c[_column].nullable),
            historical=True,
            parent_lock="runtime policy → user → user extension → credential → job → stage/run → attempt",
            service="app.services.model_configuration; app.services.model_tasks",
            tests="backend/tests/integration/test_model_credentials.py",
        )
        for _column, _target in _refs.items()
    ]
for _table_name in ("jobs",):
    for _column in ("operation_id", "request_id"):
        Base.metadata.tables[_table_name].c[_column].info["non_entity_uuid"] = (
            "operation_correlation"
        )
for _table_name in _REFERENCES:
    for _constraint in Base.metadata.tables[_table_name].constraints:
        if _constraint.name:
            _constraint.name = identifier(str(_constraint.name))
    for _index in Base.metadata.tables[_table_name].indexes:
        _index.info["purpose"] = "bounded owner/state/recovery lookup"
