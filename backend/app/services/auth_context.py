"""Identity and RBAC checks on a caller-owned business transaction."""

from datetime import UTC, datetime
from typing import Literal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import Audience, ScopeContext
from app.repositories.identity import permission_catalog, scope_roots
from app.services.authorization import require_effective_permissions


async def verify_scope_in_transaction(
    session: AsyncSession,
    *,
    user_id: UUID,
    session_id: UUID,
    audience: Audience,
    transport: Literal["web", "native"],
    permissions: tuple[str, ...] = (),
    lock_user: bool = False,
) -> ScopeContext:
    user, auth_session, revision = await scope_roots(
        session, user_id=user_id, session_id=session_id, lock_user=lock_user
    )
    now = datetime.now(UTC)
    if (
        user is None
        or auth_session is None
        or revision is None
        or user.status != "active"
        or (user.locked_until is not None and user.locked_until > now)
        or auth_session.user_id != user.id
        or auth_session.audience != audience
        or auth_session.transport != transport
        or auth_session.revoked_at is not None
        or auth_session.absolute_expires_at <= now
        or auth_session.security_epoch != user.security_epoch
        or auth_session.audience_security_epoch
        != (user.client_security_epoch if audience == "client" else user.admin_security_epoch)
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    required = (*permissions, f"{audience}.login")
    await require_permissions(session, user_id=user.id, audience=audience, codes=required)
    return ScopeContext(
        user_id=user.id,
        session_id=auth_session.id,
        audience=audience,
        transport=transport,
        user_authz_version=user.authz_version,
        policy_authz_version=revision.revision,
        security_epoch=user.security_epoch,
        absolute_expires_at=auth_session.absolute_expires_at,
    )


async def require_permissions(
    session: AsyncSession,
    *,
    user_id: UUID,
    audience: Audience,
    codes: tuple[str, ...],
    owner_user_id: UUID | None = None,
) -> None:
    if owner_user_id is not None and owner_user_id != user_id:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if any(not code.startswith(f"{audience}.") for code in codes):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    catalogs = await permission_catalog(session, codes)
    if any(
        code not in catalogs or not catalogs[code].enabled or catalogs[code].audience != audience
        for code in codes
    ):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    await require_effective_permissions(
        session,
        user_id=user_id,
        requirements=tuple((code, catalogs[code].data_scope) for code in codes),
    )
