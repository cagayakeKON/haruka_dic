"""Release catalogs and authorization metadata; no business authorization bypasses."""

from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Index,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, IdentityMixin, TimestampMixin, column_info, relation, table_info


class PermissionCatalog(TimestampMixin, Base):
    __tablename__ = "permission_catalog"
    __table_args__ = (
        CheckConstraint("audience IN ('client', 'admin')", name="audience"),
        CheckConstraint("data_scope IN ('self', 'platform_metadata')", name="data_scope"),
        {
            "comment": "发布注册的权限目录；权限存在不代表接口已实现",
            "info": {
                **table_info("system_catalog"),
                "natural_key": "immutable release permission code",
            },
        },
    )
    code: Mapped[str] = mapped_column(
        String(100),
        primary_key=True,
        nullable=False,
        comment="不可由后台任意创建的权限代码",
        info=column_info("release catalog"),
    )
    audience: Mapped[str] = mapped_column(
        String(10), nullable=False, comment="登录受众", info=column_info("release catalog")
    )
    data_scope: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="允许的数据范围", info=column_info("release catalog")
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, comment="权限是否启用", info=column_info("controlled policy")
    )


class Role(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "roles"
    __table_args__ = (
        UniqueConstraint("code"),
        CheckConstraint("revision >= 1", name="revision_positive"),
        {
            "comment": "角色定义；种子只创建缺失角色，不覆盖人工授权",
            "info": table_info("system_catalog"),
        },
    )
    code: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        comment="稳定角色代码",
        info=column_info("seed or controlled admin"),
    )
    name: Mapped[str] = mapped_column(
        String(100), nullable=False, comment="角色显示名", info=column_info("controlled admin")
    )
    description: Mapped[str | None] = mapped_column(
        Text, nullable=True, comment="角色说明", info=column_info("controlled admin")
    )
    protected: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        comment="受保护角色标记",
        info=column_info("controlled security policy"),
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, comment="角色是否启用", info=column_info("controlled policy")
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="角色并发修改版本",
        info=column_info("authorization transaction"),
    )


class RolePermission(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "role_permission_links"
    __table_args__ = (
        UniqueConstraint(
            "role_id",
            "permission_code",
            "effect",
            "data_scope",
            name="uq_role_permission_links_role_id_permission_code_e_5e3b7fafe483",
        ),
        CheckConstraint("effect IN ('allow', 'deny')", name="effect"),
        CheckConstraint("data_scope IN ('self', 'platform_metadata')", name="data_scope"),
        Index(
            "ix_role_permission_links_permission_code_role_id",
            "permission_code",
            "role_id",
            info={"purpose": "permission retirement checks for referencing roles"},
        ),
        {
            "comment": "角色显式允许或拒绝；匹配的拒绝优先",
            "info": table_info(
                "system_catalog",
                relations=(
                    relation("role_id", "roles.id"),
                    relation("permission_code", "permission_catalog.code"),
                ),
            ),
        },
    )
    role_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="锁定并核对的角色标识",
        info=column_info("locked role"),
    )
    permission_code: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        comment="已注册的权限代码",
        info=column_info("locked permission catalog"),
    )
    effect: Mapped[str] = mapped_column(
        String(8), nullable=False, comment="允许或显式拒绝", info=column_info("controlled grant")
    )
    data_scope: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="授权数据范围",
        info=column_info("locked permission catalog"),
    )


class UserRole(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "user_role_links"
    __table_args__ = (
        UniqueConstraint("user_id", "role_id"),
        Index(
            "ix_user_role_links_role_id_user_id",
            "role_id",
            "user_id",
            info={"purpose": "protected role member and last administrator checks"},
        ),
        {
            "comment": "账号角色关联；受控事务内校验身份与受保护角色",
            "info": table_info(
                "user_owned",
                owner="user_id",
                relations=(relation("user_id", "users.id"), relation("role_id", "roles.id")),
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="已锁定账号标识",
        info=column_info("locked user", "personal_reference"),
    )
    role_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="已锁定角色标识",
        info=column_info("locked role"),
    )


class Menu(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "menus"
    __table_args__ = (
        UniqueConstraint("code"),
        CheckConstraint("audience IN ('client', 'admin')", name="audience"),
        CheckConstraint("revision >= 1", name="revision_positive"),
        {
            "comment": "绑定发布路由键的菜单目录；管理菜单按权限启用",
            "info": table_info(
                "system_catalog",
                relations=(relation("permission_code", "permission_catalog.code"),),
            ),
        },
    )
    code: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="菜单代码", info=column_info("release menu catalog")
    )
    route_key: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        comment="前端已注册路由键",
        info=column_info("release route registry"),
    )
    audience: Mapped[str] = mapped_column(
        String(10), nullable=False, comment="菜单受众", info=column_info("release menu catalog")
    )
    permission_code: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        comment="显示所需权限；不代替接口授权",
        info=column_info("locked permission catalog"),
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        comment="菜单是否提供可用入口",
        info=column_info("controlled policy"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="菜单配置版本",
        info=column_info("authorization transaction"),
    )


class AuthPolicy(TimestampMixin, Base):
    __tablename__ = "auth_policies"
    __table_args__ = (
        CheckConstraint("code = 'registration'", name="code"),
        CheckConstraint(
            "registration_mode IN ('closed', 'approval', 'open')", name="registration_mode"
        ),
        CheckConstraint("recovery_mode IN ('disabled', 'email')", name="recovery_mode"),
        CheckConstraint("revision >= 1", name="revision_positive"),
        {
            "comment": "注册策略；默认关闭注册，开放方式由受控策略决定",
            "info": {
                **table_info(
                    "system_catalog", relations=(relation("default_role_id", "roles.id"),)
                ),
                "natural_key": "singleton registration policy",
            },
        },
    )
    code: Mapped[str] = mapped_column(
        String(32),
        primary_key=True,
        nullable=False,
        comment="固定策略代码",
        info=column_info("release seed"),
    )
    registration_mode: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="注册入口策略", info=column_info("controlled policy")
    )
    require_email_verification: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("true"),
        comment="开放注册必须邮箱验证的固定条件",
        info=column_info("controlled policy"),
    )
    recovery_mode: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        server_default=text("'email'"),
        comment="已选邮件找回方式；实际可用仍取决于交付配置",
        info=column_info("controlled policy"),
    )
    default_role_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="普通注册初始角色，不允许受保护角色",
        info=column_info("locked role"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="策略并发修改版本",
        info=column_info("authorization transaction"),
    )


class AuthorizationRevision(TimestampMixin, Base):
    __tablename__ = "authorization_revisions"
    __table_args__ = (
        CheckConstraint("code = 'global'", name="code"),
        CheckConstraint("revision >= 1", name="revision_positive"),
        {
            "comment": "授权目录全局版本与共同父行锁",
            "info": {
                **table_info("system_operation"),
                "natural_key": "singleton global authorization revision",
            },
        },
    )
    code: Mapped[str] = mapped_column(
        String(16),
        primary_key=True,
        nullable=False,
        comment="固定授权锁行标识",
        info=column_info("release seed"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="授权修改单调版本",
        info=column_info("authorization transaction"),
    )


class SeedVersion(TimestampMixin, Base):
    __tablename__ = "seed_versions"
    __table_args__ = (
        CheckConstraint("version >= 1", name="version_positive"),
        CheckConstraint("payload_sha256 ~ '^[a-f0-9]{64}$'", name="digest"),
        {
            "comment": "已应用种子版本与摘要；拒绝同版本内容漂移",
            "info": {**table_info("system_operation"), "natural_key": "reviewed seed release code"},
        },
    )
    code: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
        nullable=False,
        comment="种子发布代码",
        info=column_info("release seed"),
    )
    version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="种子协议版本", info=column_info("release seed")
    )
    payload_sha256: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        comment="权威种子内容摘要",
        info=column_info("release seed sha256"),
    )


class AdminAuditEvent(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "admin_audit_events"
    __table_args__ = (
        CheckConstraint(
            "action IN ('seed.applied', 'admin.created', 'auth_policy.updated', "
            "'account.registered', 'email.verified', 'password.recovered', "
            "'password.changed', 'session.created', 'session.revoked', "
            "'refresh.replayed', 'auth.login.denied')",
            name="action",
        ),
        CheckConstraint("authorization_revision >= 1", name="authorization_revision_positive"),
        CheckConstraint("payload_schema_version >= 1", name="payload_schema_version_positive"),
        CheckConstraint("audience IS NULL OR audience IN ('client', 'admin')", name="audience"),
        CheckConstraint(
            "result IS NULL OR result IN ('accepted', 'committed', 'denied', 'failed')",
            name="result",
        ),
        Index(
            "ix_admin_audit_events_created_at_id",
            "created_at",
            "id",
            info={"purpose": "bounded audit chronology"},
        ),
        Index(
            "ix_admin_audit_events_actor_user_id_created_at_id",
            "actor_user_id",
            "created_at",
            "id",
            info={"purpose": "bounded actor audit query"},
        ),
        Index(
            "ix_admin_audit_events_target_type_target_id_created_at_id",
            "target_type",
            "target_id",
            "created_at",
            "id",
            info={"purpose": "bounded target audit query"},
        ),
        Index(
            "ix_admin_audit_events_action_created_at_id",
            "action",
            "created_at",
            "id",
            info={"purpose": "bounded action audit query"},
        ),
        {
            "comment": "受控维护与身份安全追加审计，不包含密码、邮箱或私有材料",
            "info": table_info(
                "system_operation",
                append_only=True,
                relations=(
                    relation("target_user_id", "users.id", nullable=True, historical=True),
                    relation("actor_user_id", "users.id", nullable=True, historical=True),
                    relation(
                        "permission_code", "permission_catalog.code", nullable=True, historical=True
                    ),
                ),
            ),
        },
    )
    action: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        comment="已注册的维护动作",
        info=column_info("maintenance service"),
    )
    actor: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
        comment="固定受控维护主体",
        info=column_info("validated maintenance scope"),
    )
    target_user_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="目标账号引用；目录种子为空",
        info=column_info("locked user", "personal_reference"),
    )
    authorization_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="同事务提交的授权版本",
        info=column_info("authorization transaction"),
    )
    actor_user_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="已认证动作主体；匿名/维护事件为空",
        info=column_info("authenticated ScopeContext", "personal_reference"),
    )
    audience: Mapped[str | None] = mapped_column(
        String(10),
        nullable=True,
        comment="动作受众",
        info=column_info("route audience"),
    )
    permission_code: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
        comment="授权操作权限代码",
        info=column_info("authorization service"),
    )
    target_type: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        comment="受控目标类型",
        info=column_info("event action registry"),
    )
    target_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="按target_type解释的目标UUID",
        info={**column_info("locked action target"), "non_entity_uuid": "polymorphic_target"},
    )
    target_code: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
        comment="自然键目标代码",
        info=column_info("event action registry"),
    )
    operation_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="请求操作关联UUID",
        info={**column_info("request context"), "non_entity_uuid": "operation_correlation"},
    )
    request_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="请求关联UUID",
        info={**column_info("request context"), "non_entity_uuid": "operation_correlation"},
    )
    result: Mapped[str | None] = mapped_column(
        String(24),
        nullable=True,
        comment="安全结果类别",
        info=column_info("event action registry"),
    )
    reason_code: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        comment="受控安全原因代码",
        info=column_info("event action registry"),
    )
    payload_schema_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="安全摘要协议版本",
        info=column_info("release event schema"),
    )
    change_summary: Mapped[dict[str, object] | None] = mapped_column(
        JSONB,
        nullable=True,
        comment="仅白名单状态差异",
        info=column_info("event action registry"),
    )


class OutboxEvent(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "outbox_events"
    __table_args__ = (
        UniqueConstraint("audit_event_id"),
        CheckConstraint(
            "event_type IN ('authorization.changed', 'identity.security')", name="event_type"
        ),
        CheckConstraint("status IN ('pending', 'published')", name="status"),
        CheckConstraint("authorization_revision >= 1", name="authorization_revision_positive"),
        {
            "comment": "授权与身份变更的持久通知及受控投递状态",
            "info": table_info(
                "system_operation",
                relations=(relation("audit_event_id", "admin_audit_events.id", historical=True),),
            ),
        },
    )
    event_type: Mapped[str] = mapped_column(
        String(48),
        nullable=False,
        comment="已注册事件类型",
        info=column_info("authorization transaction"),
    )
    audit_event_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="同事务追加的审计标识",
        info=column_info("authorization transaction"),
    )
    authorization_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="待通知的授权版本",
        info=column_info("authorization transaction"),
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="投递状态", info=column_info("outbox service")
    )
