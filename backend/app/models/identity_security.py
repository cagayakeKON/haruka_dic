"""Identity private identity roots; references are checked by services, never database FKs."""

from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    SmallInteger,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY
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

_USER_LOCK = "lock users.id before writing this account-owned relation"
_IDENTITY_TESTS = "tests/integration/test_authentication_flow.py"


class UserExtension(IdentityMixin, TimestampMixin, Base):
    """Profile, study, settings and the current avatar pointer for one account."""

    __tablename__ = "user_extensions"
    __table_args__ = (
        UniqueConstraint("user_id"),
        CheckConstraint(
            "profile_revision >= 1 AND study_revision >= 1 AND settings_revision >= 1",
            name="group_revisions_positive",
        ),
        CheckConstraint("birth_year IS NULL OR birth_year >= 1900", name="birth_year"),
        CheckConstraint(
            "gender_code IS NULL OR gender_code IN "
            "('unspecified', 'female', 'male', 'non_binary', 'self_described', 'prefer_not_to_say')",
            name="gender_code",
        ),
        CheckConstraint(
            "gender_self_description IS NULL OR gender_code = 'self_described'",
            name="gender_description",
        ),
        CheckConstraint("ui_locale = 'zh-Hans'", name="ui_locale"),
        CheckConstraint("theme_mode IN ('system', 'light', 'dark')", name="theme_mode"),
        CheckConstraint("reduce_motion IN ('system', 'on')", name="reduce_motion"),
        CheckConstraint(
            "reading_font_family IS NULL OR reading_font_family IN ('serif', 'sans')",
            name="reading_font_family",
        ),
        CheckConstraint(
            "(reading_font_size IS NULL OR reading_font_size > 0) "
            "AND (reading_line_height IS NULL OR reading_line_height > 0)",
            name="reading_measures_positive",
        ),
        CheckConstraint(
            "reading_theme IS NULL OR reading_theme IN ('light', 'dark', 'sepia')",
            name="reading_theme",
        ),
        CheckConstraint(
            "playback_speed >= 0.70 AND playback_speed <= 1.50",
            name="playback_speed",
        ),
        CheckConstraint(
            "query_context_budget_tokens BETWEEN 1000 AND 64000",
            name="query_budget",
        ),
        CheckConstraint("avatar_revision >= 0", name="avatar_revision"),
        {
            "comment": "每个账号唯一的资料、学习档案、设置和当前头像指针；可选字段缺失不阻止登录",
            "info": business_table_info(
                "user_owned",
                owner="user_id",
                relations=(
                    business_relation(
                        "user_id",
                        "users.id",
                        parent_lock=_USER_LOCK,
                        service="app.services.registration",
                        tests=_IDENTITY_TESTS,
                    ),
                    business_relation(
                        "avatar_asset_id",
                        "file_objects.id",
                        nullable=True,
                        parent_lock="lock users.id then user_extensions before the avatar pointer",
                        service="app.services.avatar",
                        tests="tests/integration/test_profile_avatar.py",
                    ),
                ),
                module="account",
                entrances=(
                    "registration transaction",
                    "profile settings service",
                    "avatar service",
                ),
                deletion="retain while account exists; no Identity public deletion",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="当前账号归属",
        info=column_info("registration service"),
    )
    profile_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="资料字段组版本",
        info=column_info("profile service"),
    )
    study_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="学习档案字段组版本",
        info=column_info("study service"),
    )
    settings_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="设置字段组版本",
        info=column_info("settings service"),
    )
    display_name: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
        comment="本人称呼；非唯一，不从邮箱推导",
        info=column_info("profile service", "personal"),
    )
    birth_year: Mapped[int | None] = mapped_column(
        SmallInteger,
        nullable=True,
        comment="可选出生年份；不保存整数年龄",
        info=column_info("profile service", "personal"),
    )
    gender_code: Mapped[str | None] = mapped_column(
        String(24),
        nullable=True,
        comment="可选性别代码，可清除",
        info=column_info("profile service", "personal"),
    )
    gender_self_description: Mapped[str | None] = mapped_column(
        String(200),
        nullable=True,
        comment="仅self_described可填写的说明，不进入AI",
        info=column_info("profile service", "personal"),
    )
    use_optional_demographics_for_ai: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("false"),
        comment="是否允许具体功能使用最小派生人口资料",
        info=column_info("profile service", "personal"),
    )
    explanation_language: Mapped[str | None] = mapped_column(
        String(35),
        nullable=True,
        comment="解释语言，和界面语言、母语分开",
        info=column_info("study service"),
    )
    active_target_language: Mapped[str | None] = mapped_column(
        String(35),
        nullable=True,
        comment="当前目标语，必须存在本人target语言行",
        info=column_info("study service"),
    )
    ui_locale: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        server_default=text("'zh-Hans'"),
        comment="P0界面语言，固定为简体中文",
        info=column_info("settings service"),
    )
    timezone: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        comment="用户确认的IANA时区；空表示未选择",
        info=column_info("settings service"),
    )
    theme_mode: Mapped[str] = mapped_column(
        String(8),
        nullable=False,
        server_default=text("'system'"),
        comment="system、light或dark",
        info=column_info("settings service"),
    )
    reduce_motion: Mapped[str] = mapped_column(
        String(8),
        nullable=False,
        server_default=text("'system'"),
        comment="system或on",
        info=column_info("settings service"),
    )
    reading_font_family: Mapped[str | None] = mapped_column(
        String(16),
        nullable=True,
        comment="已发布阅读字体类别；空为应用默认",
        info=column_info("settings service"),
    )
    reading_font_size: Mapped[Decimal | None] = mapped_column(
        Numeric(5, 2),
        nullable=True,
        comment="阅读逻辑字号",
        info=column_info("settings service"),
    )
    reading_line_height: Mapped[Decimal | None] = mapped_column(
        Numeric(4, 2),
        nullable=True,
        comment="阅读行高倍率",
        info=column_info("settings service"),
    )
    reading_theme: Mapped[str | None] = mapped_column(
        String(8),
        nullable=True,
        comment="阅读浅色、深色或sepia",
        info=column_info("settings service"),
    )
    playback_speed: Mapped[Decimal] = mapped_column(
        Numeric(3, 2),
        nullable=False,
        server_default=text("1.00"),
        comment="播放倍速，不改变合成键",
        info=column_info("settings service"),
    )
    query_context_budget_tokens: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        server_default=text("10000"),
        comment="本人查询补充前后文预算",
        info=column_info("settings service"),
    )
    avatar_asset_id: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="当前已验证头像；空表示无头像",
        info=column_info("avatar service", "personal"),
    )
    avatar_revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="头像指针版本，从0起",
        info=column_info("avatar service"),
    )


class UserLanguage(IdentityMixin, TimestampMixin, Base):
    """Native and target language rows protected by the parent study revision."""

    __tablename__ = "user_languages"
    __table_args__ = (
        UniqueConstraint("user_id", "language_kind", "language_tag"),
        UniqueConstraint("user_id", "language_kind", "sort_order"),
        CheckConstraint("language_kind IN ('native', 'target')", name="language_kind"),
        CheckConstraint("sort_order >= 0", name="sort_order"),
        CheckConstraint("cardinality(learning_goals) <= 8", name="goal_count"),
        CheckConstraint(
            "learning_goals <@ ARRAY['reading', 'textbook', 'exam', 'listening', "
            "'speaking', 'writing', 'vocabulary', 'grammar']::varchar[]",
            name="learning_goals",
        ),
        CheckConstraint(
            "(language_kind = 'native' AND self_assessed_level IS NULL "
            "AND cardinality(learning_goals) = 0) OR "
            "(language_kind = 'target' AND self_assessed_level IN "
            "('unknown', 'beginner', 'elementary', 'intermediate', 'advanced'))",
            name="kind_level",
        ),
        {
            "comment": "本人母语与目标语选择；删除偏好不删除学习历史",
            "info": business_table_info(
                "user_owned",
                owner="user_id",
                relations=(
                    business_relation(
                        "user_id",
                        "user_extensions.user_id",
                        parent_lock=_USER_LOCK,
                        service="app.services.profile_settings",
                        tests="tests/integration/test_profile_avatar.py",
                    ),
                ),
                module="account",
                entrances=("profile settings service",),
                deletion="delete preference rows while replacing a language kind",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="当前账号归属",
        info=column_info("profile settings service"),
    )
    language_kind: Mapped[str] = mapped_column(
        String(8),
        nullable=False,
        comment="native或target",
        info=column_info("profile settings service"),
    )
    language_tag: Mapped[str] = mapped_column(
        String(35),
        nullable=False,
        comment="已发布语言能力目录中的BCP-47标签",
        info=column_info("profile settings service"),
    )
    sort_order: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="同一类语言的有序位置",
        info=column_info("profile settings service"),
    )
    self_assessed_level: Mapped[str | None] = mapped_column(
        String(16),
        nullable=True,
        comment="目标语自评水平；母语必须为空",
        info=column_info("profile settings service"),
    )
    learning_goals: Mapped[list[str]] = mapped_column(
        ARRAY(String(24)),
        nullable=False,
        server_default=text("'{}'"),
        comment="目标语受控学习目标；母语必须为空数组",
        info=column_info("profile settings service"),
    )


class AuthSession(IdentityMixin, TimestampMixin, Base):
    """Persistent revocation and absolute lifetime for web and native sessions."""

    __tablename__ = "user_auth_sessions"
    __table_args__ = (
        CheckConstraint("audience IN ('client', 'admin')", name="audience"),
        CheckConstraint("transport IN ('web', 'native')", name="transport"),
        CheckConstraint("platform IN ('web', 'windows', 'android')", name="platform"),
        CheckConstraint(
            "(audience = 'admin' AND transport = 'web' AND platform = 'web') "
            "OR (audience = 'client' AND "
            "((transport = 'web' AND platform = 'web') OR "
            "(transport = 'native' AND platform IN ('windows', 'android'))))",
            name="audience_transport_platform",
        ),
        CheckConstraint(
            "security_epoch >= 0 AND audience_security_epoch >= 0", name="epochs_nonnegative"
        ),
        CheckConstraint("absolute_expires_at > created_at", name="absolute_expiry"),
        Index(
            "ix_user_auth_sessions_user_id_audience_created_at_id",
            "user_id",
            "audience",
            "created_at",
            "id",
            info={"purpose": "bounded own-device listing"},
        ),
        Index(
            "ix_user_auth_sessions_user_id_audience_active",
            "user_id",
            "audience",
            "id",
            postgresql_where=text("revoked_at IS NULL"),
            info={"purpose": "revoke all live sessions of one audience"},
        ),
        Index(
            "ix_user_auth_sessions_absolute_expires_at_id",
            "absolute_expires_at",
            "id",
            info={"purpose": "bounded expired-session cleanup"},
        ),
        {
            "comment": "PG持久会话、绝对期限与撤销事实，Redis只保留临时凭据材料",
            "info": business_table_info(
                "user_owned",
                owner="user_id",
                relations=(
                    business_relation(
                        "user_id",
                        "users.id",
                        parent_lock=_USER_LOCK,
                        service="app.services.sessions",
                        tests=_IDENTITY_TESTS,
                    ),
                ),
                module="authentication",
                entrances=("login", "refresh", "current identity", "own session security"),
                deletion="expire and retain for bounded security history",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="会话所有者",
        info=column_info("login service"),
    )
    audience: Mapped[str] = mapped_column(
        String(10), nullable=False, comment="client或admin受众", info=column_info("fixed route")
    )
    transport: Mapped[str] = mapped_column(
        String(8), nullable=False, comment="web或native传输", info=column_info("fixed route")
    )
    platform: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        comment="经入口允许的平台类别",
        info=column_info("session service"),
    )
    absolute_expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="不可由续期延长的绝对截止",
        info=column_info("session service"),
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="PG撤销提交时间",
        info=column_info("security service"),
    )
    revoke_reason_code: Mapped[str | None] = mapped_column(
        String(64), nullable=True, comment="安全撤销原因代码", info=column_info("security service")
    )
    security_epoch: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="签发时账号全局安全代次",
        info=column_info("login service"),
    )
    audience_security_epoch: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="签发时受众安全代次", info=column_info("login service")
    )
    reauthenticated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="最近身份重验时间",
        info=column_info("security service"),
    )
    device_summary: Mapped[str | None] = mapped_column(
        String(200),
        nullable=True,
        comment="受控裁剪设备摘要",
        info=column_info("login service", "personal"),
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="有节制记录的最近活动时间",
        info=column_info("session service"),
    )


class AuthChallenge(IdentityMixin, TimestampMixin, Base):
    """One-time HMAC digests for email verification, recovery and reauthentication."""

    __tablename__ = "user_auth_challenges"
    __table_args__ = (
        UniqueConstraint("digest_key_version", "token_digest"),
        CheckConstraint(
            "purpose IN ('email_verify', 'password_recovery', 'reauth', 'manual_recovery')",
            name="purpose",
        ),
        CheckConstraint("audience IN ('client', 'admin')", name="audience"),
        CheckConstraint("octet_length(token_digest) = 32", name="digest_length"),
        CheckConstraint("security_epoch >= 0 AND password_version >= 1", name="versions"),
        CheckConstraint("expires_at > created_at", name="expiry"),
        CheckConstraint("failed_attempts >= 0", name="failed_attempts_nonnegative"),
        CheckConstraint("consumed_at IS NULL OR revoked_at IS NULL", name="terminal_exclusive"),
        Index(
            "ix_user_auth_challenges_user_id_purpose_created_at_id",
            "user_id",
            "purpose",
            "created_at",
            "id",
            info={"purpose": "bounded challenge replacement and security review"},
        ),
        Index(
            "ix_user_auth_challenges_expires_at_id",
            "expires_at",
            "id",
            info={"purpose": "bounded challenge expiry cleanup"},
        ),
        {
            "comment": "绑定账号与用途的一次性挑战，仅保存HMAC摘要",
            "info": business_table_info(
                "identity",
                relations=(
                    business_relation(
                        "user_id",
                        "users.id",
                        parent_lock=_USER_LOCK,
                        service="app.services.registration",
                        tests=_IDENTITY_TESTS,
                    ),
                ),
                module="authentication",
                entrances=("email verification", "password recovery", "reauthentication"),
                deletion="expire digest after bounded security retention",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="目标账号",
        info=column_info("challenge service", "personal_reference"),
    )
    purpose: Mapped[str] = mapped_column(
        String(24), nullable=False, comment="挑战用途", info=column_info("challenge service")
    )
    audience: Mapped[str] = mapped_column(
        String(10), nullable=False, comment="挑战受众", info=column_info("fixed route")
    )
    token_digest: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="随机令牌HMAC-SHA256摘要",
        info=column_info("challenge service", "secret_hash"),
    )
    digest_key_version: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="摘要密钥版本", info=column_info("deployment keyring")
    )
    security_epoch: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="签发时账号安全代次",
        info=column_info("challenge service"),
    )
    password_version: Mapped[int] = mapped_column(
        BigInteger, nullable=False, comment="签发时密码版本", info=column_info("challenge service")
    )
    target_email_digest: Mapped[bytes | None] = mapped_column(
        LargeBinary,
        nullable=True,
        comment="规范化邮箱绑定摘要",
        info=column_info("challenge service", "secret_hash"),
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="挑战截止时间",
        info=column_info("challenge service"),
    )
    consumed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="单次消费时间",
        info=column_info("challenge service"),
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="替换/撤销时间",
        info=column_info("challenge service"),
    )
    failed_attempts: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        server_default=text("0"),
        comment="已验证挑战失败次数",
        info=column_info("challenge service"),
    )


class AuthChallengeDelivery(IdentityMixin, TimestampMixin, Base):
    """Short-lived encrypted SMTP payload claimed by the durable outbox worker."""

    __tablename__ = "user_auth_challenge_deliveries"
    __table_args__ = (
        UniqueConstraint("user_id", "challenge_id"),
        CheckConstraint(
            "status IN ('pending', 'sending', 'sent', 'failed', 'expired')", name="status"
        ),
        CheckConstraint(
            "(encrypted_payload IS NULL) = (encryption_key_version IS NULL)", name="envelope_pair"
        ),
        CheckConstraint("payload_schema_version >= 1", name="payload_version_positive"),
        CheckConstraint("attempt_count >= 0", name="attempt_count_nonnegative"),
        CheckConstraint("lease_generation >= 0", name="lease_generation_nonnegative"),
        CheckConstraint(
            "(status = 'sending') = (lease_owner IS NOT NULL AND lease_until IS NOT NULL)",
            name="lease_state",
        ),
        CheckConstraint(
            "status <> 'pending' OR encrypted_payload IS NOT NULL", name="pending_payload"
        ),
        Index(
            "ix_auth_challenge_deliveries_pending",
            "status",
            "next_attempt_at",
            "id",
            postgresql_where=text("status IN ('pending', 'sending')"),
            info={"purpose": "claim due email notifications"},
        ),
        Index(
            "ix_auth_challenge_deliveries_expires_at_id",
            "expires_at",
            "id",
            info={"purpose": "erase expired delivery ciphertext"},
        ),
        {
            "comment": "短期加密邮件交付材料，受控Worker只按挑战用途读取",
            "info": business_table_info(
                "user_owned",
                owner="user_id",
                relations=(
                    business_relation(
                        "user_id",
                        "users.id",
                        parent_lock=_USER_LOCK,
                        service="app.services.notifications",
                        tests=_IDENTITY_TESTS,
                    ),
                    business_relation(
                        "challenge_id",
                        "user_auth_challenges.id",
                        parent_lock="lock users.id then user_auth_challenges.id",
                        service="app.services.notifications",
                        tests=_IDENTITY_TESTS,
                    ),
                ),
                module="authentication",
                entrances=("challenge issue", "notification worker"),
                deletion="erase encrypted payload after send, expiry or bounded failure",
            ),
        },
    )
    user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="交付目标账号",
        info=column_info("challenge service", "personal_reference"),
    )
    challenge_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="待交付挑战",
        info=column_info("challenge service", "personal_reference"),
    )
    encrypted_payload: Mapped[bytes | None] = mapped_column(
        LargeBinary,
        nullable=True,
        comment="短期加密收件地址与链接",
        info=column_info("notification service", "encrypted_secret"),
    )
    encryption_key_version: Mapped[str | None] = mapped_column(
        String(64), nullable=True, comment="交付密钥版本", info=column_info("deployment keyring")
    )
    payload_schema_version: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        server_default=text("1"),
        comment="加密载荷协议版本",
        info=column_info("notification service"),
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="最迟交付时间",
        info=column_info("challenge service"),
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="交付受理状态", info=column_info("notification worker")
    )
    attempt_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        server_default=text("0"),
        comment="传输尝试次数",
        info=column_info("notification worker"),
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="下次有界尝试时间",
        info=column_info("notification worker"),
    )
    last_error_code: Mapped[str | None] = mapped_column(
        String(64), nullable=True, comment="安全失败类别", info=column_info("notification worker")
    )
    lease_generation: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="领取代次；防止过期Worker覆盖新结果",
        info=column_info("notification worker"),
    )
    lease_owner: Mapped[UUID | None] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=True,
        comment="当前领取Worker随机标识",
        info=column_info("notification worker"),
    )
    lease_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="领取失效时间",
        info=column_info("notification worker"),
    )
