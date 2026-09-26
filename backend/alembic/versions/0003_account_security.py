"""Add Identity identity roots and fixed email policy without rewriting B0 history.

Only the controlled maintenance entrypoint can execute this revision. Registration
and challenge services validate every logical reference while holding parent locks.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0003_account_security"
down_revision = "0002_b0_identity_alignment"
branch_labels = None
depends_on = None


def _timestamps() -> tuple[sa.Column[object], sa.Column[object]]:
    return (
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
            comment="本行最近一次实际更新的时间，UTC",
        ),
    )


def _identity() -> sa.Column[object]:
    return sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识")


def upgrade() -> None:
    op.alter_column(
        "admin_audit_events",
        "action",
        existing_type=sa.String(32),
        type_=sa.String(100),
        existing_nullable=False,
    )
    op.create_table_comment(
        "admin_audit_events",
        "受控维护与身份安全追加审计，不包含密码、邮箱或私有材料",
        existing_comment="受控初始化追加审计，不包含密码、邮箱或私有材料",
    )
    op.drop_constraint(op.f("ck_admin_audit_events_action"), "admin_audit_events", type_="check")
    op.create_check_constraint(
        op.f("ck_admin_audit_events_action"),
        "admin_audit_events",
        "action IN ('seed.applied', 'admin.created', 'auth_policy.updated', "
        "'account.registered', 'email.verified', 'password.recovered', "
        "'password.changed', 'session.created', 'session.revoked', "
        "'refresh.replayed', 'auth.login.denied')",
    )
    for column in (
        sa.Column("actor_user_id", sa.UUID(), comment="已认证动作主体；匿名/维护事件为空"),
        sa.Column("audience", sa.String(10), comment="动作受众"),
        sa.Column("permission_code", sa.String(100), comment="授权操作权限代码"),
        sa.Column("target_type", sa.String(64), comment="受控目标类型"),
        sa.Column("target_id", sa.UUID(), comment="按target_type解释的目标UUID"),
        sa.Column("target_code", sa.String(100), comment="自然键目标代码"),
        sa.Column("operation_id", sa.UUID(), comment="请求操作关联UUID"),
        sa.Column("request_id", sa.UUID(), comment="请求关联UUID"),
        sa.Column("result", sa.String(24), comment="安全结果类别"),
        sa.Column("reason_code", sa.String(64), comment="受控安全原因代码"),
        sa.Column("change_summary", postgresql.JSONB(), comment="仅白名单状态差异"),
    ):
        op.add_column("admin_audit_events", column)
    op.add_column(
        "admin_audit_events",
        sa.Column(
            "payload_schema_version",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("1"),
            comment="安全摘要协议版本",
        ),
    )
    op.create_check_constraint(
        op.f("ck_admin_audit_events_payload_schema_version_positive"),
        "admin_audit_events",
        "payload_schema_version >= 1",
    )
    op.create_check_constraint(
        op.f("ck_admin_audit_events_audience"),
        "admin_audit_events",
        "audience IS NULL OR audience IN ('client', 'admin')",
    )
    op.create_check_constraint(
        op.f("ck_admin_audit_events_result"),
        "admin_audit_events",
        "result IS NULL OR result IN ('accepted', 'committed', 'denied', 'failed')",
    )
    op.create_index(
        "ix_admin_audit_events_created_at_id", "admin_audit_events", ["created_at", "id"]
    )
    op.create_index(
        "ix_admin_audit_events_actor_user_id_created_at_id",
        "admin_audit_events",
        ["actor_user_id", "created_at", "id"],
    )
    op.create_index(
        "ix_admin_audit_events_target_type_target_id_created_at_id",
        "admin_audit_events",
        ["target_type", "target_id", "created_at", "id"],
    )
    op.create_index(
        "ix_admin_audit_events_action_created_at_id",
        "admin_audit_events",
        ["action", "created_at", "id"],
    )
    op.drop_constraint(op.f("ck_outbox_events_event_type"), "outbox_events", type_="check")
    op.create_check_constraint(
        op.f("ck_outbox_events_event_type"),
        "outbox_events",
        "event_type IN ('authorization.changed', 'identity.security')",
    )

    op.add_column(
        "auth_policies",
        sa.Column(
            "require_email_verification",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
            comment="开放注册必须邮箱验证的固定条件",
        ),
    )
    op.add_column(
        "auth_policies",
        sa.Column(
            "recovery_mode",
            sa.String(16),
            nullable=False,
            server_default=sa.text("'email'"),
            comment="已选邮件找回方式；实际可用仍取决于交付配置",
        ),
    )
    op.create_check_constraint(
        op.f("ck_auth_policies_recovery_mode"),
        "auth_policies",
        "recovery_mode IN ('disabled', 'email')",
    )

    op.create_table(
        "user_extensions",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="当前账号归属"),
        sa.Column(
            "profile_revision",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("1"),
            comment="资料字段组版本",
        ),
        sa.Column(
            "study_revision",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("1"),
            comment="学习档案字段组版本",
        ),
        sa.Column(
            "settings_revision",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("1"),
            comment="设置字段组版本",
        ),
        _identity(),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_extensions")),
        sa.UniqueConstraint("user_id", name=op.f("uq_user_extensions_user_id")),
        sa.CheckConstraint(
            "profile_revision >= 1 AND study_revision >= 1 AND settings_revision >= 1",
            name=op.f("ck_user_extensions_group_revisions_positive"),
        ),
        comment="每个账号唯一空资料/学习/设置扩展根；Identity不要求可选资料",
    )

    op.create_table(
        "user_auth_sessions",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="会话所有者"),
        sa.Column("audience", sa.String(10), nullable=False, comment="client或admin受众"),
        sa.Column("transport", sa.String(8), nullable=False, comment="web或native传输"),
        sa.Column("platform", sa.String(16), nullable=False, comment="经入口允许的平台类别"),
        sa.Column(
            "absolute_expires_at",
            sa.DateTime(timezone=True),
            nullable=False,
            comment="不可由续期延长的绝对截止",
        ),
        sa.Column("revoked_at", sa.DateTime(timezone=True), comment="PG撤销提交时间"),
        sa.Column("revoke_reason_code", sa.String(64), comment="安全撤销原因代码"),
        sa.Column(
            "security_epoch", sa.BigInteger(), nullable=False, comment="签发时账号全局安全代次"
        ),
        sa.Column(
            "audience_security_epoch",
            sa.BigInteger(),
            nullable=False,
            comment="签发时受众安全代次",
        ),
        sa.Column("reauthenticated_at", sa.DateTime(timezone=True), comment="最近身份重验时间"),
        sa.Column("device_summary", sa.String(200), comment="受控裁剪设备摘要"),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), comment="有节制记录的最近活动时间"),
        _identity(),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_auth_sessions")),
        sa.CheckConstraint(
            "audience IN ('client', 'admin')", name=op.f("ck_user_auth_sessions_audience")
        ),
        sa.CheckConstraint(
            "transport IN ('web', 'native')", name=op.f("ck_user_auth_sessions_transport")
        ),
        sa.CheckConstraint(
            "platform IN ('web', 'windows', 'android')",
            name=op.f("ck_user_auth_sessions_platform"),
        ),
        sa.CheckConstraint(
            "(audience = 'admin' AND transport = 'web' AND platform = 'web') "
            "OR (audience = 'client' AND "
            "((transport = 'web' AND platform = 'web') OR "
            "(transport = 'native' AND platform IN ('windows', 'android'))))",
            name=op.f("ck_user_auth_sessions_audience_transport_platform"),
        ),
        sa.CheckConstraint(
            "security_epoch >= 0 AND audience_security_epoch >= 0",
            name=op.f("ck_user_auth_sessions_epochs_nonnegative"),
        ),
        sa.CheckConstraint(
            "absolute_expires_at > created_at", name=op.f("ck_user_auth_sessions_absolute_expiry")
        ),
        comment="PG持久会话、绝对期限与撤销事实，Redis只保留临时凭据材料",
    )
    op.create_index(
        "ix_user_auth_sessions_user_id_audience_created_at_id",
        "user_auth_sessions",
        ["user_id", "audience", "created_at", "id"],
    )
    op.create_index(
        "ix_user_auth_sessions_user_id_audience_active",
        "user_auth_sessions",
        ["user_id", "audience", "id"],
        postgresql_where=sa.text("revoked_at IS NULL"),
    )
    op.create_index(
        "ix_user_auth_sessions_absolute_expires_at_id",
        "user_auth_sessions",
        ["absolute_expires_at", "id"],
    )

    op.create_table(
        "user_auth_challenges",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="目标账号"),
        sa.Column("purpose", sa.String(24), nullable=False, comment="挑战用途"),
        sa.Column("audience", sa.String(10), nullable=False, comment="挑战受众"),
        sa.Column(
            "token_digest", sa.LargeBinary(), nullable=False, comment="随机令牌HMAC-SHA256摘要"
        ),
        sa.Column("digest_key_version", sa.String(64), nullable=False, comment="摘要密钥版本"),
        sa.Column("security_epoch", sa.BigInteger(), nullable=False, comment="签发时账号安全代次"),
        sa.Column("password_version", sa.BigInteger(), nullable=False, comment="签发时密码版本"),
        sa.Column("target_email_digest", sa.LargeBinary(), comment="规范化邮箱绑定摘要"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False, comment="挑战截止时间"),
        sa.Column("consumed_at", sa.DateTime(timezone=True), comment="单次消费时间"),
        sa.Column("revoked_at", sa.DateTime(timezone=True), comment="替换/撤销时间"),
        sa.Column(
            "failed_attempts",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
            comment="已验证挑战失败次数",
        ),
        _identity(),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_auth_challenges")),
        sa.UniqueConstraint(
            "digest_key_version",
            "token_digest",
            name=op.f("uq_user_auth_challenges_digest_key_version_token_digest"),
        ),
        sa.CheckConstraint(
            "purpose IN ('email_verify', 'password_recovery', 'reauth')",
            name=op.f("ck_user_auth_challenges_purpose"),
        ),
        sa.CheckConstraint(
            "audience IN ('client', 'admin')", name=op.f("ck_user_auth_challenges_audience")
        ),
        sa.CheckConstraint(
            "octet_length(token_digest) = 32", name=op.f("ck_user_auth_challenges_digest_length")
        ),
        sa.CheckConstraint(
            "security_epoch >= 0 AND password_version >= 1",
            name=op.f("ck_user_auth_challenges_versions"),
        ),
        sa.CheckConstraint("expires_at > created_at", name=op.f("ck_user_auth_challenges_expiry")),
        sa.CheckConstraint(
            "failed_attempts >= 0", name=op.f("ck_user_auth_challenges_failed_attempts_nonnegative")
        ),
        sa.CheckConstraint(
            "consumed_at IS NULL OR revoked_at IS NULL",
            name=op.f("ck_user_auth_challenges_terminal_exclusive"),
        ),
        comment="绑定账号与用途的一次性挑战，仅保存HMAC摘要",
    )
    op.create_index(
        "ix_user_auth_challenges_user_id_purpose_created_at_id",
        "user_auth_challenges",
        ["user_id", "purpose", "created_at", "id"],
    )
    op.create_index(
        "ix_user_auth_challenges_expires_at_id",
        "user_auth_challenges",
        ["expires_at", "id"],
    )

    op.create_table(
        "user_auth_challenge_deliveries",
        sa.Column("user_id", sa.UUID(), nullable=False, comment="交付目标账号"),
        sa.Column("challenge_id", sa.UUID(), nullable=False, comment="待交付挑战"),
        sa.Column("encrypted_payload", sa.LargeBinary(), comment="短期加密收件地址与链接"),
        sa.Column("encryption_key_version", sa.String(64), comment="交付密钥版本"),
        sa.Column(
            "payload_schema_version",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
            comment="加密载荷协议版本",
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False, comment="最迟交付时间"),
        sa.Column("status", sa.String(16), nullable=False, comment="交付受理状态"),
        sa.Column(
            "attempt_count",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
            comment="传输尝试次数",
        ),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), comment="下次有界尝试时间"),
        sa.Column("last_error_code", sa.String(64), comment="安全失败类别"),
        sa.Column(
            "lease_generation",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("0"),
            comment="领取代次；防止过期Worker覆盖新结果",
        ),
        sa.Column("lease_owner", sa.UUID(), comment="当前领取Worker随机标识"),
        sa.Column("lease_until", sa.DateTime(timezone=True), comment="领取失效时间"),
        _identity(),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_auth_challenge_deliveries")),
        sa.UniqueConstraint(
            "user_id",
            "challenge_id",
            name=op.f("uq_user_auth_challenge_deliveries_user_id_challenge_id"),
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'sending', 'sent', 'failed', 'expired')",
            name=op.f("ck_user_auth_challenge_deliveries_status"),
        ),
        sa.CheckConstraint(
            "(encrypted_payload IS NULL) = (encryption_key_version IS NULL)",
            name=op.f("ck_user_auth_challenge_deliveries_envelope_pair"),
        ),
        sa.CheckConstraint(
            "payload_schema_version >= 1",
            name=op.f("ck_user_auth_challenge_deliveries_payload_version_positive"),
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name=op.f("ck_user_auth_challenge_deliveries_attempt_count_nonnegative"),
        ),
        sa.CheckConstraint(
            "lease_generation >= 0",
            name=op.f("ck_user_auth_challenge_deliveries_lease_generation_nonnegative"),
        ),
        sa.CheckConstraint(
            "(status = 'sending') = (lease_owner IS NOT NULL AND lease_until IS NOT NULL)",
            name=op.f("ck_user_auth_challenge_deliveries_lease_state"),
        ),
        sa.CheckConstraint(
            "status <> 'pending' OR encrypted_payload IS NOT NULL",
            name=op.f("ck_user_auth_challenge_deliveries_pending_payload"),
        ),
        comment="短期加密邮件交付材料，受控Worker只按挑战用途读取",
    )
    op.create_index(
        "ix_auth_challenge_deliveries_pending",
        "user_auth_challenge_deliveries",
        ["status", "next_attempt_at", "id"],
        postgresql_where=sa.text("status IN ('pending', 'sending')"),
    )
    op.create_index(
        "ix_auth_challenge_deliveries_expires_at_id",
        "user_auth_challenge_deliveries",
        ["expires_at", "id"],
    )
    # Refresh comments introduced by the immutable identity revisions.
    op.execute("COMMENT ON TABLE menus IS '绑定发布路由键的菜单目录；管理菜单按权限启用'")
    op.execute("COMMENT ON TABLE auth_policies IS '注册策略；默认关闭注册，开放方式由受控策略决定'")
    op.execute("COMMENT ON TABLE outbox_events IS '授权与身份变更的持久通知及受控投递状态'")
    op.execute("COMMENT ON TABLE users IS '独立账号身份；注册与首管理员初始化分别受控'")


def downgrade() -> None:
    raise RuntimeError("Identity identity data requires reviewed forward repair")
