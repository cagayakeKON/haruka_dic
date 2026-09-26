"""Identity roots required by controlled first-administrator initialization."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import BigInteger, CheckConstraint, DateTime, Index, String, UniqueConstraint, text
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, IdentityMixin, TimestampMixin, column_info, relation, table_info


class User(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("email_normalized"),
        CheckConstraint("status IN ('pending', 'active', 'disabled')", name="status"),
        CheckConstraint("length(email_normalized) BETWEEN 3 AND 254", name="email_length"),
        CheckConstraint("authz_version >= 1", name="authz_version_positive"),
        CheckConstraint("password_version >= 1", name="password_version_positive"),
        CheckConstraint("security_epoch >= 0", name="security_epoch_nonnegative"),
        CheckConstraint("revision >= 1", name="revision_positive"),
        CheckConstraint(
            "client_security_epoch >= 0 AND admin_security_epoch >= 0",
            name="security_epochs_nonnegative",
        ),
        Index(
            "ix_users_status_created_at_id",
            "status",
            "created_at",
            "id",
            info={"purpose": "bounded administrator account listing"},
        ),
        {"comment": "独立账号身份；B0只支持受控首管理员初始化", "info": table_info("identity")},
    )
    email: Mapped[str] = mapped_column(
        String(254),
        nullable=False,
        comment="账号显示邮箱",
        info=column_info("maintenance input", "personal"),
    )
    email_normalized: Mapped[str] = mapped_column(
        String(254),
        nullable=False,
        comment="按账号规则规范化的唯一邮箱",
        info=column_info("validated email", "personal"),
    )
    password_hash: Mapped[str] = mapped_column(
        String(512),
        nullable=False,
        comment="Argon2id密码哈希，不存明文",
        info=column_info("argon2id", "secret_hash"),
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, comment="账号状态", info=column_info("identity service")
    )
    authz_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="账号授权版本",
        info=column_info("authorization transaction"),
    )
    password_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="密码哈希版本",
        info=column_info("identity service"),
    )
    security_epoch: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="全局持久撤销代次",
        info=column_info("identity service"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="账号资料并发修改版本",
        info=column_info("identity service"),
    )
    email_verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="邮箱实际验证时间",
        info=column_info("identity service"),
    )
    locked_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="账号限时锁定截止",
        info=column_info("identity service"),
    )
    client_security_epoch: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="用户端持久撤销代次",
        info=column_info("identity service"),
    )
    admin_security_epoch: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
        comment="管理端持久撤销代次",
        info=column_info("identity service"),
    )


class Library(IdentityMixin, TimestampMixin, Base):
    __tablename__ = "libraries"
    __table_args__ = (
        UniqueConstraint("owner_user_id"),
        {
            "comment": "每个账号唯一的私有资料库根",
            "info": table_info(
                "library_root",
                owner="owner_user_id",
                relations=(relation("owner_user_id", "users.id"),),
            ),
        },
    )
    owner_user_id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        nullable=False,
        comment="服务根据已验证账号派生的库所有者",
        info=column_info("locked user", "personal_reference"),
    )
