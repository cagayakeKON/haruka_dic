"""B0 identity and controlled authorization initialization.

Revision: empty -> 0001_b0_identity; no prior released revision exists.
Twelve empty metadata tables; transactional DDL, no foreign keys or user-data backfill.
The maintenance connection holds the database-wide advisory lock throughout.
Runtime audit mutation and migration-version mutation are explicitly revoked.
Downgrade is intentionally unavailable: preserve identity/audit data and recover or forward-fix.
"""

import sqlalchemy as sa
from alembic import op

revision = "0001_b0_identity"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "admin_audit_events",
        sa.Column("action", sa.String(length=32), nullable=False, comment="已注册的维护动作"),
        sa.Column("actor", sa.String(length=64), nullable=False, comment="固定受控维护主体"),
        sa.Column("target_user_id", sa.UUID(), nullable=True, comment="目标账号引用；目录种子为空"),
        sa.Column(
            "authorization_revision",
            sa.BigInteger(),
            nullable=False,
            comment="同事务提交的授权版本",
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
        sa.CheckConstraint(
            "action IN ('seed.applied', 'admin.created')", name=op.f("ck_admin_audit_events_action")
        ),
        sa.CheckConstraint(
            "authorization_revision >= 1",
            name=op.f("ck_admin_audit_events_authorization_revision_positive"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_admin_audit_events")),
        comment="受控初始化追加审计，不包含密码、邮箱或私有材料",
    )
    op.create_table(
        "auth_policies",
        sa.Column("code", sa.String(length=32), nullable=False, comment="固定策略代码"),
        sa.Column(
            "registration_mode", sa.String(length=16), nullable=False, comment="注册入口策略"
        ),
        sa.Column(
            "default_role_id",
            sa.UUID(),
            nullable=False,
            comment="普通注册初始角色，不允许受保护角色",
        ),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="策略并发修改版本",
        ),
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
        sa.CheckConstraint("code = 'registration'", name=op.f("ck_auth_policies_code")),
        sa.CheckConstraint(
            "registration_mode IN ('closed', 'approval', 'open')",
            name=op.f("ck_auth_policies_registration_mode"),
        ),
        sa.CheckConstraint("revision >= 1", name=op.f("ck_auth_policies_revision_positive")),
        sa.PrimaryKeyConstraint("code", name=op.f("pk_auth_policies")),
        comment="注册策略；B0默认关闭注册，不决定后续开放方式",
    )
    op.create_table(
        "authorization_revisions",
        sa.Column("code", sa.String(length=16), nullable=False, comment="固定授权锁行标识"),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="授权修改单调版本",
        ),
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
        sa.CheckConstraint("code = 'global'", name=op.f("ck_authorization_revisions_code")),
        sa.CheckConstraint(
            "revision >= 1", name=op.f("ck_authorization_revisions_revision_positive")
        ),
        sa.PrimaryKeyConstraint("code", name=op.f("pk_authorization_revisions")),
        comment="授权目录全局版本与共同父行锁",
    )
    op.create_table(
        "libraries",
        sa.Column(
            "owner_user_id", sa.UUID(), nullable=False, comment="服务根据已验证账号派生的库所有者"
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_libraries")),
        sa.UniqueConstraint("owner_user_id", name=op.f("uq_libraries_owner_user_id")),
        comment="每个账号唯一的私有资料库根",
    )
    op.create_table(
        "menus",
        sa.Column("code", sa.String(length=64), nullable=False, comment="菜单代码"),
        sa.Column("route_key", sa.String(length=64), nullable=False, comment="前端已注册路由键"),
        sa.Column("audience", sa.String(length=10), nullable=False, comment="菜单受众"),
        sa.Column(
            "permission_code",
            sa.String(length=100),
            nullable=False,
            comment="显示所需权限；不代替接口授权",
        ),
        sa.Column("enabled", sa.Boolean(), nullable=False, comment="菜单是否提供可用入口"),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="菜单配置版本",
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
        sa.CheckConstraint("audience IN ('client', 'admin')", name=op.f("ck_menus_audience")),
        sa.CheckConstraint("revision >= 1", name=op.f("ck_menus_revision_positive")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_menus")),
        sa.UniqueConstraint("code", name=op.f("uq_menus_code")),
        comment="绑定发布路由键的菜单目录；B0管理菜单不可用",
    )
    op.create_table(
        "outbox_events",
        sa.Column("event_type", sa.String(length=48), nullable=False, comment="已注册事件类型"),
        sa.Column("audit_event_id", sa.UUID(), nullable=False, comment="同事务追加的审计标识"),
        sa.Column(
            "authorization_revision", sa.BigInteger(), nullable=False, comment="待通知的授权版本"
        ),
        sa.Column("status", sa.String(length=16), nullable=False, comment="投递状态"),
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
            "event_type = 'authorization.changed'", name=op.f("ck_outbox_events_event_type")
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'published')", name=op.f("ck_outbox_events_status")
        ),
        sa.CheckConstraint(
            "authorization_revision >= 1",
            name=op.f("ck_outbox_events_authorization_revision_positive"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_outbox_events")),
        sa.UniqueConstraint("audit_event_id", name=op.f("uq_outbox_events_audit_event_id")),
        comment="授权变更持久通知；B0只提交，B2实现投递",
    )
    op.create_table(
        "permission_catalog",
        sa.Column(
            "code", sa.String(length=100), nullable=False, comment="不可由后台任意创建的权限代码"
        ),
        sa.Column("audience", sa.String(length=10), nullable=False, comment="登录受众"),
        sa.Column("data_scope", sa.String(length=24), nullable=False, comment="允许的数据范围"),
        sa.Column("enabled", sa.Boolean(), nullable=False, comment="权限是否启用"),
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
            "audience IN ('client', 'admin')", name=op.f("ck_permission_catalog_audience")
        ),
        sa.CheckConstraint(
            "data_scope IN ('self', 'platform_metadata')",
            name=op.f("ck_permission_catalog_data_scope"),
        ),
        sa.PrimaryKeyConstraint("code", name=op.f("pk_permission_catalog")),
        comment="发布注册的权限目录；权限存在不代表接口已实现",
    )
    op.create_table(
        "role_permissions",
        sa.Column("role_id", sa.UUID(), nullable=False, comment="锁定并核对的角色标识"),
        sa.Column(
            "permission_code", sa.String(length=100), nullable=False, comment="已注册的权限代码"
        ),
        sa.Column("effect", sa.String(length=8), nullable=False, comment="允许或显式拒绝"),
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
        sa.CheckConstraint("effect IN ('allow', 'deny')", name=op.f("ck_role_permissions_effect")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_role_permissions")),
        sa.UniqueConstraint(
            "role_id",
            "permission_code",
            "effect",
            name=op.f("uq_role_permissions_role_id_permission_code_effect"),
        ),
        comment="角色显式允许或拒绝；匹配的拒绝优先",
    )
    op.create_index(
        "ix_role_permissions_permission_code_role_id",
        "role_permissions",
        ["permission_code", "role_id"],
        unique=False,
    )
    op.create_table(
        "roles",
        sa.Column("code", sa.String(length=64), nullable=False, comment="稳定角色代码"),
        sa.Column("protected", sa.Boolean(), nullable=False, comment="受保护角色标记"),
        sa.Column("enabled", sa.Boolean(), nullable=False, comment="角色是否启用"),
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="角色并发修改版本",
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
        sa.CheckConstraint("revision >= 1", name=op.f("ck_roles_revision_positive")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_roles")),
        sa.UniqueConstraint("code", name=op.f("uq_roles_code")),
        comment="角色定义；种子只创建缺失角色，不覆盖人工授权",
    )
    op.create_table(
        "seed_versions",
        sa.Column("code", sa.String(length=64), nullable=False, comment="种子发布代码"),
        sa.Column("version", sa.BigInteger(), nullable=False, comment="种子协议版本"),
        sa.Column(
            "payload_sha256", sa.String(length=64), nullable=False, comment="权威种子内容摘要"
        ),
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
            "payload_sha256 ~ '^[a-f0-9]{64}$'", name=op.f("ck_seed_versions_digest")
        ),
        sa.CheckConstraint("version >= 1", name=op.f("ck_seed_versions_version_positive")),
        sa.PrimaryKeyConstraint("code", name=op.f("pk_seed_versions")),
        comment="已应用种子版本与摘要；拒绝同版本内容漂移",
    )
    op.create_table(
        "user_roles",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="已锁定账号标识"),
        sa.Column("role_id", sa.UUID(), nullable=False, comment="已锁定角色标识"),
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_roles")),
        sa.UniqueConstraint("user_id", "role_id", name=op.f("uq_user_roles_user_id_role_id")),
        comment="账号角色关联；受控事务内校验身份与受保护角色",
    )
    op.create_index(
        "ix_user_roles_role_id_user_id", "user_roles", ["role_id", "user_id"], unique=False
    )
    op.create_table(
        "users",
        sa.Column("email", sa.String(length=254), nullable=False, comment="账号显示邮箱"),
        sa.Column(
            "email_normalized",
            sa.String(length=254),
            nullable=False,
            comment="按账号规则规范化的唯一邮箱",
        ),
        sa.Column(
            "password_hash",
            sa.String(length=512),
            nullable=False,
            comment="Argon2id密码哈希，不存明文",
        ),
        sa.Column("status", sa.String(length=16), nullable=False, comment="账号状态"),
        sa.Column(
            "authz_version",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="账号授权版本",
        ),
        sa.Column(
            "client_security_epoch",
            sa.BigInteger(),
            server_default=sa.text("0"),
            nullable=False,
            comment="用户端持久撤销代次",
        ),
        sa.Column(
            "admin_security_epoch",
            sa.BigInteger(),
            server_default=sa.text("0"),
            nullable=False,
            comment="管理端持久撤销代次",
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
        sa.CheckConstraint(
            "status IN ('pending', 'active', 'disabled')", name=op.f("ck_users_status")
        ),
        sa.CheckConstraint("authz_version >= 1", name=op.f("ck_users_authz_version_positive")),
        sa.CheckConstraint(
            "client_security_epoch >= 0 AND admin_security_epoch >= 0",
            name=op.f("ck_users_security_epochs_nonnegative"),
        ),
        sa.CheckConstraint(
            "length(email_normalized) BETWEEN 3 AND 254", name=op.f("ck_users_email_length")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
        sa.UniqueConstraint("email_normalized", name=op.f("uq_users_email_normalized")),
        comment="独立账号身份；B0只支持受控首管理员初始化",
    )
    database = op.get_bind().scalar(sa.text("SELECT current_database()"))
    if database == "haruka_test":
        op.execute("REVOKE UPDATE, DELETE ON admin_audit_events FROM haruka_test_runtime")
        op.execute("REVOKE INSERT, UPDATE, DELETE ON alembic_version FROM haruka_test_runtime")
    elif database == "haruka_dev":
        op.execute("REVOKE UPDATE, DELETE ON admin_audit_events FROM haruka_dev_runtime")
        op.execute("REVOKE INSERT, UPDATE, DELETE ON alembic_version FROM haruka_dev_runtime")
    else:
        raise RuntimeError("migration target is not an isolated Haruka database")


def downgrade() -> None:
    raise RuntimeError(
        "identity and audit schema cannot be destructively downgraded; use reviewed recovery or forward repair"
    )
