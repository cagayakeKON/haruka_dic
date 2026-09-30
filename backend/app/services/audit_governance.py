"""Bounded audit reads and identity counts. Rows stay append-only."""

import re
from datetime import UTC, datetime
from typing import Literal, cast
from uuid import UUID

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.models import AdminAuditEvent, AuthChallenge, AuthorizationRevision, Role, User
from app.schemas.audit_governance import AuditEventRead, GovernanceSummaryRead
from app.services.auth_context import require_permissions

_ACTION = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$")
_RESULTS = {"accepted", "committed", "denied", "failed"}
_HIDDEN_SUMMARY = ("token", "password", "secret", "key")


def public_summary(value: dict[str, object] | None) -> dict[str, str] | None:
    """Keep short scalar differences and drop anything that could carry a secret."""
    if not value:
        return None
    clean: dict[str, str] = {}
    for key, item in value.items():
        if not isinstance(key, str) or re.fullmatch(r"[a-z][a-z0-9_]{0,63}", key) is None:
            continue
        if any(hidden in key for hidden in _HIDDEN_SUMMARY):
            continue
        if isinstance(item, bool):
            text = "true" if item else "false"
        elif isinstance(item, int) and not isinstance(item, bool):
            text = str(item)
        elif isinstance(item, str) and 0 < len(item) <= 200:
            text = item
        else:
            continue
        clean[key] = text
    return clean or None


def _cursor(created_at: datetime, event_id: UUID) -> str:
    return f"{created_at.isoformat()}|{event_id}"


def _decode_cursor(value: str) -> tuple[datetime, UUID]:
    created_raw, separator, identity = value.partition("|")
    if not separator:
        raise AppError(ErrorCode.INPUT_INVALID)
    try:
        created_at = datetime.fromisoformat(created_raw)
        event_id = UUID(identity)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    if created_at.tzinfo is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    return created_at, event_id


def _event_read(row: AdminAuditEvent) -> AuditEventRead:
    audience = row.audience if row.audience in {"client", "admin"} else None
    result = row.result if row.result in _RESULTS else None
    return AuditEventRead(
        event_id=row.id,
        action=row.action,
        actor=row.actor,
        actor_user_id=row.actor_user_id,
        audience=cast(Literal["client", "admin"] | None, audience),
        permission_code=row.permission_code,
        target_type=row.target_type,
        target_id=row.target_id,
        target_code=row.target_code,
        result=cast(Literal["accepted", "committed", "denied", "failed"] | None, result),
        reason_code=row.reason_code,
        authorization_revision=row.authorization_revision,
        request_id=row.request_id,
        operation_id=row.operation_id,
        change_summary=public_summary(row.change_summary),
        created_at=row.created_at,
    )


async def list_audit_events(
    session: AsyncSession,
    *,
    actor_id: UUID,
    limit: int,
    cursor: str | None,
    action: str | None,
    result: str | None,
    actor_user_id: UUID | None,
    target_type: str | None,
) -> tuple[list[AuditEventRead], str | None]:
    await require_permissions(
        session, user_id=actor_id, audience="admin", codes=("admin.audit.read",)
    )
    if action is not None and _ACTION.fullmatch(action) is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    if result is not None and result not in _RESULTS:
        raise AppError(ErrorCode.INPUT_INVALID)
    if target_type is not None and re.fullmatch(r"[a-z][a-z0-9_]{0,63}", target_type) is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    statement = select(AdminAuditEvent).order_by(
        AdminAuditEvent.created_at.desc(), AdminAuditEvent.id.desc()
    )
    if action is not None:
        statement = statement.where(AdminAuditEvent.action == action)
    if result is not None:
        statement = statement.where(AdminAuditEvent.result == result)
    if actor_user_id is not None:
        statement = statement.where(AdminAuditEvent.actor_user_id == actor_user_id)
    if target_type is not None:
        statement = statement.where(AdminAuditEvent.target_type == target_type)
    if cursor is not None:
        created_at, event_id = _decode_cursor(cursor)
        statement = statement.where(
            or_(
                AdminAuditEvent.created_at < created_at,
                and_(AdminAuditEvent.created_at == created_at, AdminAuditEvent.id < event_id),
            )
        )
    rows = (await session.scalars(statement.limit(limit + 1))).all()
    visible = rows[:limit]
    next_cursor = _cursor(visible[-1].created_at, visible[-1].id) if len(rows) > limit else None
    return [_event_read(row) for row in visible], next_cursor


async def read_governance_summary(
    session: AsyncSession, *, actor_id: UUID
) -> GovernanceSummaryRead:
    await require_permissions(
        session, user_id=actor_id, audience="admin", codes=("admin.dashboard.view",)
    )
    revision = await session.scalar(
        select(AuthorizationRevision.revision).where(AuthorizationRevision.code == "global")
    )
    if revision is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    now = datetime.now(UTC)
    accounts_active = int(
        await session.scalar(select(func.count()).select_from(User).where(User.status == "active"))
        or 0
    )
    accounts_pending = int(
        await session.scalar(select(func.count()).select_from(User).where(User.status == "pending"))
        or 0
    )
    accounts_disabled = int(
        await session.scalar(
            select(func.count()).select_from(User).where(User.status == "disabled")
        )
        or 0
    )
    approvals_pending = int(
        await session.scalar(
            select(func.count()).select_from(User).where(User.approval_status == "pending")
        )
        or 0
    )
    roles_enabled = int(
        await session.scalar(select(func.count()).select_from(Role).where(Role.enabled.is_(True)))
        or 0
    )
    open_recoveries = int(
        await session.scalar(
            select(func.count())
            .select_from(AuthChallenge)
            .where(
                AuthChallenge.purpose == "manual_recovery",
                AuthChallenge.consumed_at.is_(None),
                AuthChallenge.revoked_at.is_(None),
                AuthChallenge.expires_at > now,
            )
        )
        or 0
    )
    return GovernanceSummaryRead(
        accounts_active=accounts_active,
        accounts_pending=accounts_pending,
        accounts_disabled=accounts_disabled,
        approvals_pending=approvals_pending,
        roles_enabled=roles_enabled,
        authorization_revision=revision,
        open_manual_recoveries=open_recoveries,
    )
