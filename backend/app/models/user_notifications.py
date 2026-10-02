"""Persistent private committed-job notifications with a library commit sequence."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
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
)
from app.models.learning_reference import LibraryScopeMixin

_LOCK = "current identity then library root, material root, job; same-kind parents by UUID"


class UserNotification(IdentityMixin, TimestampMixin, LibraryScopeMixin, Base):
    __tablename__ = "user_notifications"
    __table_args__ = (
        UniqueConstraint(
            "owner_user_id",
            "source_event_id",
            "notification_kind",
            name="uq_user_notification_owner_event_kind",
        ),
        UniqueConstraint("owner_user_id", "sequence"),
        CheckConstraint(
            "notification_kind IN ('completed','failed','needs_review') AND resource_kind = 'material'",
            name="kind",
        ),
        CheckConstraint(
            "revision >= 1 AND resource_version >= 1 AND sequence > 0 AND schema_version = 1",
            name="versions",
        ),
        CheckConstraint("safe_parameters = '{}'::jsonb", name="safe_parameters"),
        Index(
            "ix_user_notifications_owner_created",
            "owner_user_id",
            "created_at",
            "id",
            info={"purpose": "private stable notification pagination"},
        ),
        Index(
            "ix_user_notifications_owner_unread",
            "owner_user_id",
            "read_at",
            "sequence",
            postgresql_where=text("read_at IS NULL"),
            info={"purpose": "snapshot-bounded unread count and mark-all"},
        ),
        {
            "comment": "仅已提交本人材料任务的安全提示",
            "info": business_table_info(
                "library_owned",
                owner="owner_user_id",
                module="user_notifications",
                entrances=("committed job event consumer", "authorized private notification API"),
                deletion="retain private safe receipt; never revive unavailable resource",
                relations=tuple(
                    business_relation(
                        column,
                        target,
                        parent_lock=_LOCK,
                        service="app.services.user_notifications",
                        tests="tests/integration/test_user_notifications.py",
                    )
                    for column, target in (
                        ("owner_user_id", "users.id"),
                        ("library_id", "libraries.id"),
                        ("job_id", "jobs.id"),
                        ("resource_id", "materials.id"),
                        ("source_event_id", "outbox_events.id"),
                    )
                ),
            ),
        },
    )
    source_event_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="已提交源事件", info=column_info("committed outbox event")
    )
    job_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人材料任务", info=column_info("committed job")
    )
    notification_kind: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        comment="completed failed needs_review",
        info=column_info("registered event consumer"),
    )
    resource_kind: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        comment="当前仅material",
        info=column_info("registered event consumer"),
    )
    resource_id: Mapped[UUID] = mapped_column(
        PgUUID, nullable=False, comment="本人材料根", info=column_info("committed job input")
    )
    resource_version: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="事件提交时资源版本",
        info=column_info("committed material"),
    )
    message_code: Mapped[str] = mapped_column(
        String(96),
        nullable=False,
        comment="注册的提示文案代码",
        info=column_info("event whitelist"),
    )
    schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, comment="安全载荷版本1", info=column_info("notification contract")
    )
    safe_parameters: Mapped[dict[str, object]] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text("'{}'::jsonb"),
        comment="当前不含正文标题或任意参数",
        info=column_info("event whitelist"),
    )
    sequence: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        comment="同库根锁内分配的提交序号",
        info=column_info("locked library"),
    )
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="首次实际已读提交UTC",
        info=column_info("notification transaction"),
    )
    revision: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        server_default=text("1"),
        comment="消息状态版本",
        info=column_info("notification transaction"),
    )
