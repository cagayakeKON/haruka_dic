"""Shared UTC timestamps and explicit metadata for the no-foreign-key schema."""

import hashlib
from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, MetaData, func
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def identifier(name: str) -> str:
    """Shorten reviewed ASCII identifiers deterministically within PostgreSQL's limit."""
    if not name.isascii():
        raise ValueError("database identifiers must be ASCII")
    if len(name) <= 63:
        return name
    return f"{name[:50]}_{hashlib.sha256(name.encode()).hexdigest()[:12]}"


class Base(DeclarativeBase):
    metadata = MetaData(
        naming_convention={
            "pk": "pk_%(table_name)s",
            "uq": "uq_%(table_name)s_%(column_0_N_name)s",
            "ix": "ix_%(table_name)s_%(column_0_N_name)s",
            "ck": "ck_%(table_name)s_%(constraint_name)s",
        }
    )


def column_info(source: str, sensitivity: str = "internal") -> dict[str, str]:
    return {"source": source, "sensitivity": sensitivity}


def relation(
    column: str, target: str, *, nullable: bool = False, historical: bool = False
) -> dict[str, object]:
    return {
        "column": column,
        "target": target,
        "nullable": nullable,
        "scope_rule": "controlled maintenance metadata only; no private content access",
        "state_rule": "existing active parent at write; immutable ownership",
        "parent_lock": "authorization_revisions.global serializes all changes before locking target parent rows; advisory lock protects an absent global row",
        "deletion": "retain historical reference" if historical else "restrict",
        "service": "app.services.initialization",
        "tests": "tests/integration/test_initialization.py",
    }


def table_info(
    scope: str,
    *,
    owner: str | None = None,
    append_only: bool = False,
    relations: tuple[dict[str, object], ...] = (),
) -> dict[str, object]:
    return {
        "scope_kind": scope,
        "owner_column": owner,
        "lifecycle": "append_only" if append_only else "mutable",
        "allowed_entrances": ["controlled maintenance initialization"],
        "deletion_policy": "retain; no public physical deletion in B0",
        "logical_relations": list(relations),
        "module": "identity_foundation",
    }


class IdentityMixin:
    id: Mapped[UUID] = mapped_column(
        PgUUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
        nullable=False,
        comment="服务端生成的稳定标识",
        info=column_info("server.uuid4"),
    )


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        comment="本行创建时间，UTC",
        info=column_info("database.now"),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
        comment="本行最近一次实际更新的时间，UTC",
        info=column_info("database.now"),
    )
