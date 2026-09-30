"""Commit-boundary identity checks and durable login revocation for governance."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import AuthorizationRevision, AuthSession, User
from app.services.auth_context import verify_scope_in_transaction


async def verify_admin_write(session: AsyncSession, scope: ScopeContext) -> None:
    """Lock global -> actor -> session, retaining all locks through commit."""
    if scope.audience != "admin" or scope.transport != "web":
        raise AppError(ErrorCode.SESSION_INVALID)
    revision = await session.scalar(
        select(AuthorizationRevision)
        .where(AuthorizationRevision.code == "global")
        .with_for_update()
    )
    if revision is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    await session.scalar(select(User).where(User.id == scope.user_id).with_for_update())
    current = await session.scalar(
        select(AuthSession)
        .where(AuthSession.id == scope.session_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience="admin",
        transport="web",
        lock_user=True,
    )
    now = datetime.now(UTC)
    if (
        current is None
        or current.reauthenticated_at is None
        or current.reauthenticated_at > now
        or now - current.reauthenticated_at > timedelta(minutes=5)
    ):
        # A fresh password login already creates a new session and revokes no
        # privilege checks. Re-login is the currently implemented reauth path.
        raise AppError(ErrorCode.SESSION_INVALID)


async def revoke_lost_login(
    session: AsyncSession,
    *,
    before: dict[UUID, set[tuple[str, str]]],
    after: dict[UUID, set[tuple[str, str]]],
) -> None:
    """Regaining login permission must never resurrect an old session."""
    now = datetime.now(UTC)
    for user_id in sorted(before, key=lambda item: item.bytes):
        lost = before[user_id] - after[user_id]
        audiences = [
            audience
            for audience, data_scope in (("client", "self"), ("admin", "platform_metadata"))
            if (f"{audience}.login", data_scope) in lost
        ]
        if not audiences:
            continue
        user = await session.scalar(select(User).where(User.id == user_id).with_for_update())
        if user is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        for audience in audiences:
            if audience == "client":
                user.client_security_epoch += 1
            else:
                user.admin_security_epoch += 1
        user.updated_at = now
        rows = await session.scalars(
            select(AuthSession)
            .where(
                AuthSession.user_id == user_id,
                AuthSession.audience.in_(audiences),
                AuthSession.revoked_at.is_(None),
            )
            .order_by(AuthSession.id)
            .with_for_update()
        )
        for row in rows:
            row.revoked_at = now
            row.revoke_reason_code = "login_permission_removed"
            row.updated_at = now
