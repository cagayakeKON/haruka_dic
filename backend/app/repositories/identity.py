"""Narrow SQL queries for authenticated identity and RBAC decisions."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.scope import ScopeContext
from app.models import (
    AuthChallenge,
    AuthorizationRevision,
    AuthPolicy,
    AuthSession,
    PermissionCatalog,
    User,
)


async def global_revision_for_update(session: AsyncSession) -> AuthorizationRevision | None:
    return await session.scalar(
        select(AuthorizationRevision)
        .where(AuthorizationRevision.code == "global")
        .with_for_update()
    )


async def user_by_email(
    session: AsyncSession, normalized_email: str, *, for_update: bool = False
) -> User | None:
    statement = select(User).where(User.email_normalized == normalized_email)
    if for_update:
        statement = statement.with_for_update()
    return await session.scalar(statement)


async def current_user_for_update(session: AsyncSession, scope: ScopeContext) -> User | None:
    return await session.scalar(select(User).where(User.id == scope.user_id).with_for_update())


async def current_user(session: AsyncSession, scope: ScopeContext) -> User | None:
    return await session.get(User, scope.user_id)


async def user_for_challenge_for_update(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.scalar(select(User).where(User.id == user_id).with_for_update())


async def user_for_login_for_update(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.scalar(select(User).where(User.id == user_id).with_for_update())


async def user_for_refresh_for_update(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.scalar(select(User).where(User.id == user_id).with_for_update())


async def user_for_continuation(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.get(User, user_id)


async def account_session_for_update(
    session: AsyncSession, scope: ScopeContext, session_id: UUID
) -> AuthSession | None:
    return await session.scalar(
        select(AuthSession)
        .where(
            AuthSession.id == session_id,
            AuthSession.user_id == scope.user_id,
            AuthSession.audience == scope.audience,
        )
        .with_for_update()
    )


async def current_session_for_update(
    session: AsyncSession, scope: ScopeContext
) -> AuthSession | None:
    return await account_session_for_update(session, scope, scope.session_id)


async def refresh_session_for_update(
    session: AsyncSession, *, user_id: UUID, session_id: UUID
) -> AuthSession | None:
    return await session.scalar(
        select(AuthSession)
        .where(AuthSession.id == session_id, AuthSession.user_id == user_id)
        .with_for_update()
    )


async def active_sessions_for_scope(
    session: AsyncSession, scope: ScopeContext, *, across_audiences: bool = False
) -> list[AuthSession]:
    statement = select(AuthSession).where(
        AuthSession.user_id == scope.user_id,
        AuthSession.revoked_at.is_(None),
    )
    if not across_audiences:
        statement = statement.where(AuthSession.audience == scope.audience)
    rows = await session.scalars(statement.order_by(AuthSession.id).with_for_update())
    return list(rows.all())


async def active_sessions_for_recovery(
    session: AsyncSession, *, user_id: UUID
) -> list[AuthSession]:
    rows = await session.scalars(
        select(AuthSession)
        .where(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
        .order_by(AuthSession.id)
        .with_for_update()
    )
    return list(rows.all())


async def account_session_page(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    limit: int,
    after: tuple[datetime, UUID] | None,
) -> list[AuthSession]:
    statement = select(AuthSession).where(
        AuthSession.user_id == scope.user_id,
        AuthSession.audience == scope.audience,
    )
    if after is not None:
        statement = statement.where(tuple_(AuthSession.created_at, AuthSession.id) < after)
    rows = await session.scalars(
        statement.order_by(AuthSession.created_at.desc(), AuthSession.id.desc()).limit(limit + 1)
    )
    return list(rows.all())


async def registration_policy(
    session: AsyncSession, *, for_update: bool = False
) -> AuthPolicy | None:
    statement = select(AuthPolicy).where(AuthPolicy.code == "registration")
    if for_update:
        statement = statement.with_for_update()
    return await session.scalar(statement)


async def latest_challenge_for_update(
    session: AsyncSession, *, user_id: UUID, purpose: str
) -> AuthChallenge | None:
    return await session.scalar(
        select(AuthChallenge)
        .where(AuthChallenge.user_id == user_id, AuthChallenge.purpose == purpose)
        .order_by(AuthChallenge.created_at.desc())
        .limit(1)
        .with_for_update()
    )


async def challenge_by_id_for_update(
    session: AsyncSession, challenge_id: UUID
) -> AuthChallenge | None:
    return await session.scalar(
        select(AuthChallenge).where(AuthChallenge.id == challenge_id).with_for_update()
    )


async def challenge_identity_by_digest(
    session: AsyncSession, *, key_version: str, digest: bytes, purpose: str | None = None
) -> tuple[UUID, UUID, str] | None:
    statement = select(AuthChallenge.id, AuthChallenge.user_id, AuthChallenge.purpose).where(
        AuthChallenge.digest_key_version == key_version,
        AuthChallenge.token_digest == digest,
    )
    if purpose is not None:
        statement = statement.where(AuthChallenge.purpose == purpose)
    row = (await session.execute(statement)).one_or_none()
    if row is None:
        return None
    return row.id, row.user_id, row.purpose


async def scope_roots(
    session: AsyncSession, *, user_id: UUID, session_id: UUID, lock_user: bool
) -> tuple[User | None, AuthSession | None, AuthorizationRevision | None]:
    user_query = select(User).where(User.id == user_id)
    if lock_user:
        user_query = user_query.with_for_update().execution_options(populate_existing=True)
    return (
        await session.scalar(user_query),
        await session.get(AuthSession, session_id, populate_existing=True),
        await session.get(AuthorizationRevision, "global", populate_existing=True),
    )


async def permission_catalog(
    session: AsyncSession, codes: tuple[str, ...]
) -> dict[str, PermissionCatalog]:
    rows = await session.scalars(
        select(PermissionCatalog)
        .where(PermissionCatalog.code.in_(codes))
        .execution_options(populate_existing=True)
    )
    return {row.code: row for row in rows.all()}
