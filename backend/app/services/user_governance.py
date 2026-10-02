"""Account creation, status, role membership, and target-session revocation.

The global authorization row is locked before the user row. A missing account
ceiling denies the write. Creating an account never returns or stores a chosen
password.
"""

from datetime import UTC, datetime, timedelta
from secrets import token_urlsafe
from typing import Literal
from uuid import UUID

from pydantic import SecretStr
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
from app.domain.errors import AppError
from app.models import (
    AdminAuditEvent,
    AuthChallenge,
    AuthorizationRevision,
    AuthSession,
    Library,
    OutboxEvent,
    Role,
    RoleGrantBoundary,
    RoleInheritance,
    User,
    UserExtension,
    UserRole,
)
from app.repositories.identity import challenge_by_id_for_update
from app.schemas.user_governance import (
    AccountCeilingsRead,
    AccountRead,
    AccountRoleRead,
    AccountSessionRead,
    AccountWriteResult,
    ManualRecoveryDecisionResult,
    ManualRecoveryRead,
)
from app.services.auth_context import require_permissions
from app.services.auth_crypto import AuthCrypto, hash_password, new_opaque_token
from app.services.authorization import (
    allowed_pairs,
    allows,
    closure,
    count_login_capable_super_admins,
    load_graph,
    require_super_admin_remains,
)
from app.services.governance_security import revoke_lost_login
from app.services.registration import email_identity

_ADMIN_SCOPE = "platform_metadata"


async def authorize_account_receipt(
    session: AsyncSession, *, actor_id: UUID, user_id: UUID
) -> None:
    _reject_self(actor_id, user_id)
    user = await session.get(User, user_id)
    if user is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user_id)))


_CLIENT_LOGIN = ("client.login", "self")
_ADMIN_LOGIN = ("admin.login", "platform_metadata")


async def list_accounts(
    session: AsyncSession,
    *,
    actor_id: UUID,
    limit: int,
    after_email: str | None,
    query: str | None,
) -> tuple[list[AccountRead], str | None]:
    await _require(session, actor_id, "admin.user.read")
    statement = (
        select(User)
        .outerjoin(UserExtension, UserExtension.user_id == User.id)
        .order_by(User.email_normalized, User.id)
        .limit(limit + 1)
    )
    if after_email is not None:
        statement = statement.where(User.email_normalized > after_email)
    if query is not None and query.strip():
        needle = query.strip().lower()
        statement = statement.where(
            or_(
                User.email_normalized.contains(needle),
                func.lower(UserExtension.display_name).contains(needle),
            )
        )
    users = (await session.scalars(statement)).all()
    page = users[:limit]
    cursor = page[-1].email_normalized if len(users) > limit and page else None
    return [await _account_read(session, user) for user in page], cursor


async def read_account(session: AsyncSession, *, actor_id: UUID, user_id: UUID) -> AccountRead:
    await _require(session, actor_id, "admin.user.read")
    user = await session.get(User, user_id)
    if user is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return await _account_read(session, user)


async def read_account_ceilings(session: AsyncSession, *, actor_id: UUID) -> AccountCeilingsRead:
    await _require(session, actor_id, "admin.user.read")
    assign_roles = await _boundary_targets(session, actor_id, "assign_role")
    managed_roles = await _boundary_targets(session, actor_id, "manage_account_role")
    return AccountCeilingsRead(
        assign_role_ids=sorted(assign_roles, key=lambda item: item.bytes),
        manage_account_role_ids=sorted(managed_roles, key=lambda item: item.bytes),
        manage_unassigned_accounts=await _can_manage_unassigned(session, actor_id),
    )


async def create_account(
    session: AsyncSession,
    *,
    actor_id: UUID,
    email: str,
    display_name: str | None,
    role_ids: tuple[UUID, ...],
) -> AccountWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.user.create")
    display, normalized = email_identity(email)
    roles = set(role_ids)
    if roles:
        await _require(session, actor_id, "admin.user.role.assign")
        await _lock_roles(session, roles)
        await _assert_assignable(session, actor_id, roles)
        await _assert_manageable(session, actor_id, roles)
    existing = await session.scalar(select(User.id).where(User.email_normalized == normalized))
    if existing is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    user = User(
        email=display,
        email_normalized=normalized,
        password_hash=await hash_password(SecretStr(token_urlsafe(48))),
        status="pending",
        authz_version=1,
        password_version=1,
        security_epoch=0,
        revision=1,
        email_verified_at=None,
        locked_until=None,
        approval_status="not_required",
        client_security_epoch=0,
        admin_security_epoch=0,
    )
    session.add(user)
    await session.flush()
    session.add(Library(owner_user_id=user.id))
    session.add(UserExtension(user_id=user.id, display_name=display_name))
    for role_id in sorted(roles, key=lambda item: item.bytes):
        session.add(UserRole(user_id=user.id, role_id=role_id))
    await session.flush()
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action="user.created",
        permission_code="admin.user.role.assign" if roles else "admin.user.create",
        summary={"role_count": len(roles), "status": "pending"},
        affected_count=1,
        event_type="authorization.changed",
    )


async def set_account_status(
    session: AsyncSession,
    *,
    actor_id: UUID,
    user_id: UUID,
    expected_revision: int,
    status: Literal["active", "disabled"],
) -> AccountWriteResult:
    revision = await _lock_global(session)
    permission = "admin.user.enable" if status == "active" else "admin.user.disable"
    await _require(session, actor_id, permission)
    user = await _lock_user(session, user_id)
    _reject_self(actor_id, user.id)
    _expect(user, expected_revision)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user.id)))
    if status == "active" and user.approval_status in {"pending", "rejected"}:
        raise AppError(ErrorCode.STATE_CONFLICT)
    if user.status == status:
        return _unchanged(user, revision)
    before_actor = await _actor_pairs(session, actor_id)
    user.status = status
    user.authz_version += 1
    affected = 0
    if status == "disabled":
        now = datetime.now(UTC)
        user.security_epoch += 1
        user.client_security_epoch += 1
        user.admin_security_epoch += 1
        affected = await _revoke_live(
            session, user.id, audience=None, now=now, reason="account_disabled"
        )
    await session.flush()
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_last_admin(session)
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action="user.enabled" if status == "active" else "user.disabled",
        permission_code=permission,
        summary={"status": status},
        affected_count=affected,
        event_type="authorization.changed",
    )


async def decide_account_approval(
    session: AsyncSession,
    *,
    actor_id: UUID,
    user_id: UUID,
    expected_revision: int,
    decision: Literal["approve", "reject"],
) -> AccountWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.user.approve")
    user = await _lock_user(session, user_id)
    _reject_self(actor_id, user.id)
    _expect(user, expected_revision)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user.id)))
    if user.approval_status == "not_required":
        raise AppError(ErrorCode.STATE_CONFLICT)
    if (
        decision == "approve"
        and user.approval_status == "approved"
        and (user.email_verified_at is None or user.status != "pending")
    ):
        return _unchanged(user, revision)
    if decision == "reject" and user.approval_status == "rejected":
        return _unchanged(user, revision)
    before_actor = await _actor_pairs(session, actor_id)
    affected = 0
    if decision == "approve":
        user.approval_status = "approved"
        if user.status == "pending" and user.email_verified_at is not None:
            user.status = "active"
            user.authz_version += 1
        action = "user.approved"
    else:
        user.approval_status = "rejected"
        if user.status == "active":
            now = datetime.now(UTC)
            user.status = "pending"
            user.authz_version += 1
            user.security_epoch += 1
            user.client_security_epoch += 1
            user.admin_security_epoch += 1
            affected = await _revoke_live(
                session, user.id, audience=None, now=now, reason="approval_rejected"
            )
        action = "user.rejected"
    await session.flush()
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_last_admin(session)
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action=action,
        permission_code="admin.user.approve",
        summary={"decision": decision, "status": user.status},
        affected_count=affected,
        event_type="authorization.changed",
    )


def _recovery_status(
    challenge: AuthChallenge, *, issued: bool, now: datetime
) -> Literal["requested", "issued", "rejected", "consumed", "expired"]:
    if challenge.revoked_at is not None:
        return "rejected"
    if challenge.consumed_at is not None:
        return "consumed"
    if challenge.expires_at <= now:
        return "expired"
    if issued:
        return "issued"
    return "requested"


async def _issued_challenge_ids(session: AsyncSession, challenge_ids: list[UUID]) -> set[UUID]:
    if not challenge_ids:
        return set()
    found = await session.scalars(
        select(AdminAuditEvent.target_id).where(
            AdminAuditEvent.action == "recovery.challenge_issued",
            AdminAuditEvent.target_id.in_(challenge_ids),
        )
    )
    return {item for item in found.all() if item is not None}


async def list_manual_recoveries(
    session: AsyncSession, *, actor_id: UUID, user_id: UUID
) -> list[ManualRecoveryRead]:
    await _require(session, actor_id, "admin.user.read")
    user = await session.get(User, user_id)
    if user is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    _reject_self(actor_id, user.id)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user.id)))
    rows = (
        await session.scalars(
            select(AuthChallenge)
            .where(AuthChallenge.user_id == user.id, AuthChallenge.purpose == "manual_recovery")
            .order_by(AuthChallenge.created_at.desc(), AuthChallenge.id.desc())
            .limit(20)
        )
    ).all()
    issued = await _issued_challenge_ids(session, [row.id for row in rows])
    now = datetime.now(UTC)
    return [
        ManualRecoveryRead(
            challenge_id=row.id,
            status=_recovery_status(row, issued=row.id in issued, now=now),
            created_at=row.created_at,
            expires_at=row.expires_at,
        )
        for row in rows
    ]


async def decide_manual_recovery(
    session: AsyncSession,
    *,
    actor_id: UUID,
    user_id: UUID,
    challenge_id: UUID,
    expected_revision: int,
    decision: Literal["issue", "reject"],
    verification_method: Literal["in_person", "known_channel"] | None,
    crypto: AuthCrypto,
) -> ManualRecoveryDecisionResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.user.update")
    user = await _lock_user(session, user_id)
    _reject_self(actor_id, user.id)
    _expect(user, expected_revision)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user.id)))
    challenge = await challenge_by_id_for_update(session, challenge_id)
    if challenge is None or challenge.user_id != user.id or challenge.purpose != "manual_recovery":
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    now = datetime.now(UTC)
    issued = challenge.id in await _issued_challenge_ids(session, [challenge.id])
    if decision == "reject":
        if challenge.revoked_at is not None:
            return ManualRecoveryDecisionResult(
                challenge_id=challenge.id,
                status="rejected",
                revision=user.revision,
                authorization_revision=revision.revision,
                expires_at=challenge.expires_at,
            )
        if challenge.consumed_at is not None:
            raise AppError(ErrorCode.STATE_CONFLICT)
        challenge.revoked_at = now
        written = await _audit(
            session,
            actor_id=actor_id,
            revision=revision,
            user=user,
            action="recovery.rejected",
            permission_code="admin.user.update",
            summary={"challenge_id": str(challenge.id)},
            affected_count=0,
            event_type="identity.security",
            target_type="challenge",
            target_id=challenge.id,
        )
        return ManualRecoveryDecisionResult(
            challenge_id=challenge.id,
            status="rejected",
            revision=written.revision,
            authorization_revision=written.authorization_revision,
            expires_at=challenge.expires_at,
        )
    if (
        user.status != "active"
        or challenge.consumed_at is not None
        or challenge.revoked_at is not None
    ):
        raise AppError(ErrorCode.STATE_CONFLICT)
    if challenge.expires_at <= now:
        raise AppError(ErrorCode.RESOURCE_EXPIRED)
    if issued or verification_method is None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    token = new_opaque_token()
    challenge.token_digest = crypto.digest("challenge-manual_recovery", token)
    challenge.digest_key_version = crypto.digest_key_version
    challenge.security_epoch = user.security_epoch
    challenge.password_version = user.password_version
    challenge.target_email_digest = crypto.digest("email-target", user.email_normalized)
    challenge.expires_at = now + timedelta(minutes=30)
    await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action="recovery.verified",
        permission_code="admin.user.update",
        summary={"challenge_id": str(challenge.id), "verification_method": verification_method},
        affected_count=0,
        event_type="identity.security",
        target_type="challenge",
        target_id=challenge.id,
    )
    issued_write = await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action="recovery.challenge_issued",
        permission_code="admin.user.update",
        summary={"challenge_id": str(challenge.id)},
        affected_count=0,
        event_type="identity.security",
        target_type="challenge",
        target_id=challenge.id,
    )
    return ManualRecoveryDecisionResult(
        challenge_id=challenge.id,
        status="issued",
        revision=issued_write.revision,
        authorization_revision=issued_write.authorization_revision,
        expires_at=challenge.expires_at,
        token=token,
    )


async def replace_account_roles(
    session: AsyncSession,
    *,
    actor_id: UUID,
    user_id: UUID,
    expected_revision: int,
    role_ids: tuple[UUID, ...],
) -> AccountWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.user.role.assign")
    user = await _lock_user(session, user_id)
    _reject_self(actor_id, user.id)
    _expect(user, expected_revision)
    current = set(await _direct_role_ids(session, user.id))
    proposed = set(role_ids)
    await _assert_manageable(session, actor_id, current)
    if proposed == current:
        return _unchanged(user, revision)
    await _lock_roles(session, proposed)
    await _assert_assignable(session, actor_id, proposed | current)
    await _assert_manageable(session, actor_id, proposed)
    before_actor = await _actor_pairs(session, actor_id)
    before_target = await _actor_pairs(session, user.id)
    if proposed:
        await session.execute(
            delete(UserRole).where(UserRole.user_id == user.id, UserRole.role_id.not_in(proposed))
        )
    else:
        await session.execute(delete(UserRole).where(UserRole.user_id == user.id))
    for role_id in sorted(proposed - current, key=lambda item: item.bytes):
        session.add(UserRole(user_id=user.id, role_id=role_id))
    user.authz_version += 1
    await session.flush()
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_last_admin(session)
    await revoke_lost_login(
        session,
        before={user.id: before_target},
        after={user.id: await _actor_pairs(session, user.id)},
    )
    added = sorted(str(role_id) for role_id in proposed - current)
    removed = sorted(str(role_id) for role_id in current - proposed)
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action="user.role_assigned" if added else "user.role_removed",
        permission_code="admin.user.role.assign",
        summary={"added": added, "removed": removed},
        affected_count=1,
        event_type="authorization.changed",
    )


async def list_account_sessions(
    session: AsyncSession, *, actor_id: UUID, user_id: UUID
) -> list[AccountSessionRead]:
    await _require(session, actor_id, "admin.session.read")
    user = await session.get(User, user_id)
    if user is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    _reject_self(actor_id, user.id)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user.id)))
    rows = (
        await session.scalars(
            select(AuthSession)
            .where(AuthSession.user_id == user.id)
            .order_by(AuthSession.created_at.desc(), AuthSession.id.desc())
            .limit(100)
        )
    ).all()
    return [_session_read(row) for row in rows]


async def revoke_account_sessions(
    session: AsyncSession,
    *,
    actor_id: UUID,
    user_id: UUID,
    expected_revision: int,
    session_id: UUID | None,
    audience: Literal["client", "admin"] | None,
    all_sessions: bool,
) -> AccountWriteResult:
    selected = sum((session_id is not None, audience is not None, all_sessions))
    if selected != 1:
        raise AppError(ErrorCode.INPUT_INVALID)
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.session.revoke")
    user = await _lock_user(session, user_id)
    _reject_self(actor_id, user.id)
    _expect(user, expected_revision)
    await _assert_manageable(session, actor_id, set(await _direct_role_ids(session, user.id)))
    now = datetime.now(UTC)
    if session_id is not None:
        target = await session.scalar(
            select(AuthSession).where(AuthSession.id == session_id).with_for_update()
        )
        if target is None or target.user_id != user.id:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        if target.revoked_at is not None:
            return _unchanged(user, revision)
        target.revoked_at = now
        target.revoke_reason_code = "admin_revoked"
        affected = 1
        summary: dict[str, object] = {"session_id": str(session_id)}
    else:
        affected = await _revoke_live(
            session,
            user.id,
            audience=None if all_sessions else audience,
            now=now,
            reason="admin_revoked",
        )
        if all_sessions:
            user.security_epoch += 1
            user.client_security_epoch += 1
            user.admin_security_epoch += 1
        elif audience == "client":
            user.client_security_epoch += 1
        else:
            user.admin_security_epoch += 1
        summary = {"audience": "all" if all_sessions else audience, "session_count": affected}
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        user=user,
        action="session.revoked",
        permission_code="admin.session.revoke",
        summary=summary,
        affected_count=affected,
        event_type="identity.security",
    )


async def _account_read(session: AsyncSession, user: User) -> AccountRead:
    extension = await session.scalar(select(UserExtension).where(UserExtension.user_id == user.id))
    roles = (
        await session.execute(
            select(Role.id, Role.code, Role.name, Role.enabled, Role.protected)
            .join(UserRole, UserRole.role_id == Role.id)
            .where(UserRole.user_id == user.id)
            .order_by(Role.code, Role.id)
        )
    ).all()
    now = datetime.now(UTC)
    live = await session.scalar(
        select(func.count())
        .select_from(AuthSession)
        .where(
            AuthSession.user_id == user.id,
            AuthSession.revoked_at.is_(None),
            AuthSession.absolute_expires_at > now,
        )
    )
    graph = await load_graph(session, user.id)
    audiences: list[Literal["client", "admin"]] = []
    if allows(graph, user.id, *_CLIENT_LOGIN):
        audiences.append("client")
    if allows(graph, user.id, *_ADMIN_LOGIN):
        audiences.append("admin")
    status: Literal["pending", "active", "disabled"] = (
        "pending"
        if user.status == "pending"
        else "disabled"
        if user.status == "disabled"
        else "active"
    )
    approval: Literal["not_required", "pending", "approved", "rejected"] = (
        "pending"
        if user.approval_status == "pending"
        else "approved"
        if user.approval_status == "approved"
        else "rejected"
        if user.approval_status == "rejected"
        else "not_required"
    )
    return AccountRead(
        user_id=user.id,
        email=user.email,
        display_name=None if extension is None else extension.display_name,
        status=status,
        email_verified=user.email_verified_at is not None,
        locked=user.locked_until is not None and user.locked_until > now,
        approval_status=approval,
        audiences=audiences,
        roles=[
            AccountRoleRead(
                role_id=role_id,
                code=code,
                name=name,
                enabled=enabled,
                protected=protected,
            )
            for role_id, code, name, enabled, protected in roles
        ],
        live_session_count=int(live or 0),
        revision=user.revision,
    )


def _session_read(row: AuthSession) -> AccountSessionRead:
    audience: Literal["client", "admin"] = "admin" if row.audience == "admin" else "client"
    transport: Literal["web", "native"] = "web" if row.transport == "web" else "native"
    return AccountSessionRead(
        session_id=row.id,
        audience=audience,
        transport=transport,
        platform=row.platform,
        device_summary=row.device_summary,
        created_at=row.created_at,
        last_seen_at=row.last_seen_at,
        absolute_expires_at=row.absolute_expires_at,
        revoked_at=row.revoked_at,
    )


async def _require(session: AsyncSession, actor_id: UUID, code: str) -> None:
    await require_permissions(session, user_id=actor_id, audience="admin", codes=(code,))


async def _lock_global(session: AsyncSession) -> AuthorizationRevision:
    revision = await session.scalar(
        select(AuthorizationRevision)
        .where(AuthorizationRevision.code == "global")
        .with_for_update()
    )
    if revision is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return revision


async def _lock_user(session: AsyncSession, user_id: UUID) -> User:
    user = await session.scalar(select(User).where(User.id == user_id).with_for_update())
    if user is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return user


async def _lock_roles(session: AsyncSession, role_ids: set[UUID]) -> None:
    found: set[UUID] = set()
    for role_id in sorted(role_ids, key=lambda item: item.bytes):
        locked = await session.scalar(select(Role.id).where(Role.id == role_id).with_for_update())
        if locked is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        found.add(locked)
    if found != role_ids:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)


def _expect(user: User, expected_revision: int) -> None:
    if user.revision != expected_revision:
        raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=user.revision)


def _reject_self(actor_id: UUID, user_id: UUID) -> None:
    if actor_id == user_id:
        raise AppError(ErrorCode.PERMISSION_DENIED)


async def _enabled_role_ids(session: AsyncSession, actor_id: UUID) -> list[UUID]:
    graph = await load_graph(session, actor_id)
    return [UUID(role_id) for role_id in closure(graph.direct_role_ids, graph.edges)]


async def _boundary_targets(session: AsyncSession, actor_id: UUID, kind: str) -> set[UUID]:
    role_ids = await _enabled_role_ids(session, actor_id)
    if not role_ids:
        return set()
    rows = (
        await session.scalars(
            select(RoleGrantBoundary.target_role_id).where(
                RoleGrantBoundary.grantor_role_id.in_(role_ids),
                RoleGrantBoundary.boundary_kind == kind,
                RoleGrantBoundary.target_role_id.is_not(None),
            )
        )
    ).all()
    return {role_id for role_id in rows if role_id is not None}


async def _can_manage_unassigned(session: AsyncSession, actor_id: UUID) -> bool:
    role_ids = await _enabled_role_ids(session, actor_id)
    if not role_ids:
        return False
    found = await session.scalar(
        select(RoleGrantBoundary.id).where(
            RoleGrantBoundary.grantor_role_id.in_(role_ids),
            RoleGrantBoundary.boundary_kind == "manage_unassigned_accounts",
        )
    )
    return found is not None


async def _direct_role_ids(session: AsyncSession, user_id: UUID) -> list[UUID]:
    return list(
        (await session.scalars(select(UserRole.role_id).where(UserRole.user_id == user_id))).all()
    )


async def _with_ancestors(session: AsyncSession, role_ids: set[UUID]) -> set[UUID]:
    if not role_ids:
        return set()
    edges = (
        await session.execute(select(RoleInheritance.child_role_id, RoleInheritance.parent_role_id))
    ).all()
    parents: dict[UUID, list[UUID]] = {}
    for child_id, parent_id in edges:
        parents.setdefault(child_id, []).append(parent_id)
    seen = set(role_ids)
    pending = list(role_ids)
    while pending:
        current = pending.pop()
        for parent_id in parents.get(current, ()):
            if parent_id not in seen:
                seen.add(parent_id)
                pending.append(parent_id)
    return seen


async def _assert_assignable(session: AsyncSession, actor_id: UUID, role_ids: set[UUID]) -> None:
    if not role_ids:
        return
    covered = await _with_ancestors(session, role_ids)
    if not covered <= await _boundary_targets(session, actor_id, "assign_role"):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    await _assert_protected(session, actor_id, covered)


async def _assert_manageable(session: AsyncSession, actor_id: UUID, role_ids: set[UUID]) -> None:
    if not role_ids:
        if not await _can_manage_unassigned(session, actor_id):
            raise AppError(ErrorCode.PERMISSION_DENIED)
        return
    covered = await _with_ancestors(session, role_ids)
    if not covered <= await _boundary_targets(session, actor_id, "manage_account_role"):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    await _assert_protected(session, actor_id, covered)


async def _assert_protected(session: AsyncSession, actor_id: UUID, role_ids: set[UUID]) -> None:
    protected = await session.scalar(
        select(Role.id).where(Role.id.in_(role_ids), Role.protected.is_(True))
    )
    if protected is not None:
        await _require(session, actor_id, "admin.protected_role.manage")


async def _actor_pairs(session: AsyncSession, actor_id: UUID) -> set[tuple[str, str]]:
    return allowed_pairs(await load_graph(session, actor_id), actor_id)


async def _reject_elevation(
    session: AsyncSession, actor_id: UUID, before: set[tuple[str, str]]
) -> None:
    if not await _actor_pairs(session, actor_id) <= before:
        raise AppError(ErrorCode.PERMISSION_DENIED)


async def _assert_last_admin(session: AsyncSession) -> None:
    require_super_admin_remains(
        await count_login_capable_super_admins(session, now=datetime.now(UTC))
    )


async def _revoke_live(
    session: AsyncSession,
    user_id: UUID,
    *,
    audience: str | None,
    now: datetime,
    reason: str,
) -> int:
    statement = select(AuthSession).where(
        AuthSession.user_id == user_id,
        AuthSession.revoked_at.is_(None),
        AuthSession.absolute_expires_at > now,
    )
    if audience is not None:
        statement = statement.where(AuthSession.audience == audience)
    rows = (await session.scalars(statement.with_for_update())).all()
    for row in rows:
        row.revoked_at = now
        row.revoke_reason_code = reason
    return len(rows)


def _unchanged(user: User, revision: AuthorizationRevision) -> AccountWriteResult:
    return AccountWriteResult(
        user_id=user.id,
        revision=user.revision,
        authorization_revision=revision.revision,
        audit_id=None,
        affected_count=0,
    )


async def _audit(
    session: AsyncSession,
    *,
    actor_id: UUID,
    revision: AuthorizationRevision,
    user: User,
    action: str,
    permission_code: str,
    summary: dict[str, object],
    affected_count: int,
    event_type: Literal["authorization.changed", "identity.security"],
    target_type: str | None = None,
    target_id: UUID | None = None,
) -> AccountWriteResult:
    now = datetime.now(UTC)
    user.revision += 1
    user.updated_at = now
    revision.revision += 1
    request_id, operation_id = current_correlation()
    audit = AdminAuditEvent(
        action=action,
        actor="authenticated-admin",
        actor_user_id=actor_id,
        audience="admin",
        permission_code=permission_code,
        target_type=target_type or ("session" if action == "session.revoked" else "user"),
        target_id=target_id or user.id,
        target_user_id=user.id,
        result="committed",
        payload_schema_version=1,
        change_summary=summary,
        request_id=request_id,
        operation_id=operation_id,
        authorization_revision=revision.revision,
    )
    session.add(audit)
    await session.flush()
    session.add(
        OutboxEvent(
            event_type=event_type,
            audit_event_id=audit.id,
            authorization_revision=revision.revision,
            status="pending",
        )
    )
    return AccountWriteResult(
        user_id=user.id,
        revision=user.revision,
        authorization_revision=revision.revision,
        audit_id=audit.id,
        affected_count=affected_count,
    )
