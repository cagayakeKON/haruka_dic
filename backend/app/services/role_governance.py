"""Role, inheritance, allow/deny, and grant-ceiling writes.

The global authorization row is locked before any role row. PyCasbin is not asked
to store these changes. A missing or exceeded ceiling denies the write.
"""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
from app.domain.errors import AppError
from app.models import (
    AdminAuditEvent,
    AuthorizationRevision,
    AuthPolicy,
    OutboxEvent,
    PermissionCatalog,
    Role,
    RoleGrantBoundary,
    RoleInheritance,
    RolePermission,
    UserRole,
)
from app.schemas.role_governance import (
    AuthorizationWriteResult,
    GrantBoundaryRead,
    GrantBoundaryWrite,
    PermissionCatalogRead,
    RoleGrantRead,
    RoleParentRead,
    RoleRead,
)
from app.services.auth_context import require_permissions
from app.services.authorization import (
    GrantGraph,
    allowed_pairs,
    allows,
    closure,
    count_login_capable_super_admins,
    graph_accepts_authorization,
    load_graph,
    require_super_admin_remains,
    validate_inheritance_graph,
)

_ADMIN_SCOPE = "platform_metadata"


async def list_roles(
    session: AsyncSession, *, actor_id: UUID, limit: int, after_code: str | None
) -> tuple[list[RoleRead], bool]:
    await _require(session, actor_id, "admin.role.read")
    statement = select(Role).order_by(Role.code, Role.id).limit(limit + 1)
    if after_code is not None:
        statement = statement.where(Role.code > after_code)
    roles = (await session.scalars(statement)).all()
    page = roles[:limit]
    return [await _role_read(session, role) for role in page], len(roles) > limit


async def read_role(session: AsyncSession, *, actor_id: UUID, role_id: UUID) -> RoleRead:
    await _require(session, actor_id, "admin.role.read")
    role = await session.get(Role, role_id)
    if role is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return await _role_read(session, role)


async def list_permissions(session: AsyncSession, *, actor_id: UUID) -> list[PermissionCatalogRead]:
    await _require(session, actor_id, "admin.permission.read")
    rows = (await session.scalars(select(PermissionCatalog).order_by(PermissionCatalog.code))).all()
    return [
        PermissionCatalogRead(
            code=row.code,
            audience="admin" if row.audience == "admin" else "client",
            data_scope="self" if row.data_scope == "self" else "platform_metadata",
            enabled=row.enabled,
        )
        for row in rows
    ]


async def read_grant_boundaries(
    session: AsyncSession, *, actor_id: UUID, role_id: UUID
) -> list[GrantBoundaryRead]:
    await _require(session, actor_id, "admin.grant_boundary.read")
    if await session.get(Role, role_id) is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    rows = (
        await session.scalars(
            select(RoleGrantBoundary)
            .where(RoleGrantBoundary.grantor_role_id == role_id)
            .order_by(RoleGrantBoundary.boundary_kind, RoleGrantBoundary.permission_code)
        )
    ).all()
    return [_boundary_read(row) for row in rows]


async def create_role(
    session: AsyncSession,
    *,
    actor_id: UUID,
    code: str,
    name: str,
    description: str | None,
) -> AuthorizationWriteResult:
    """Create one enabled role with no grants and no parents."""
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.role.create")
    if await session.scalar(select(Role.id).where(Role.code == code)) is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    role = Role(
        code=code, name=name, description=description, protected=False, enabled=True, revision=1
    )
    session.add(role)
    await session.flush()
    return await _audit(
        session,
        revision=revision,
        role=role,
        actor_id=actor_id,
        action="role.created",
        permission_code="admin.role.create",
        summary={"code": code},
        affected_count=0,
    )


async def update_role_metadata(
    session: AsyncSession,
    *,
    actor_id: UUID,
    role_id: UUID,
    expected_revision: int,
    name: str,
    description: str | None,
) -> AuthorizationWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.role.update")
    role = await _lock_role(session, role_id)
    _expect(role, expected_revision)
    await _protect(session, actor_id, role)
    if role.name == name and role.description == description:
        return _unchanged(role, revision)
    role.name = name
    role.description = description
    return await _audit(
        session,
        revision=revision,
        role=role,
        action="role.updated",
        permission_code="admin.role.update",
        actor_id=actor_id,
        summary={"metadata": True},
        affected_count=0,
    )


async def set_role_enabled(
    session: AsyncSession,
    *,
    actor_id: UUID,
    role_id: UUID,
    expected_revision: int,
    enabled: bool,
) -> AuthorizationWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.role.update")
    role = await _lock_role(session, role_id)
    _expect(role, expected_revision)
    await _protect(session, actor_id, role)
    if role.enabled == enabled:
        return _unchanged(role, revision)
    if enabled:
        await _assert_enable_within_ceiling(session, actor_id, role.id)
    before_actor = await _actor_pairs(session, actor_id)
    affected = await _affected_users(session, role.id)
    before = await _pairs_for(session, affected)
    had_assign = await _holds(session, actor_id, "admin.role.permission.assign")
    role.enabled = enabled
    await session.flush()
    await _reject_elevation(session, actor_id, before_actor)
    changed = await _effective_change(session, affected, before, had_assign=had_assign)
    await _assert_public_role(session)
    await _assert_last_admin(session)
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        role=role,
        action="role.updated",
        permission_code="admin.role.permission.assign" if changed else "admin.role.update",
        summary={"enabled": enabled},
        affected_count=len(affected),
    )


async def replace_role_grants(
    session: AsyncSession,
    *,
    actor_id: UUID,
    role_id: UUID,
    expected_revision: int,
    grants: tuple[tuple[str, str, str], ...],
) -> AuthorizationWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.role.permission.assign")
    role = await _lock_role(session, role_id)
    _expect(role, expected_revision)
    await _protect(session, actor_id, role)
    await _accept_grants(session, grants)
    ceiling = await _permission_ceiling(session, actor_id)
    if any((code, scope) not in ceiling for code, _effect, scope in grants):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    current = await _grant_key(session, role.id)
    proposed = set(grants)
    if current == proposed:
        return _unchanged(role, revision)
    before_actor = await _actor_pairs(session, actor_id)
    affected = await _affected_users(session, role.id)
    await session.execute(delete(RolePermission).where(RolePermission.role_id == role.id))
    session.add_all(
        [
            RolePermission(role_id=role.id, permission_code=code, effect=effect, data_scope=scope)
            for code, effect, scope in grants
        ]
    )
    await session.flush()
    await _assert_graph(session)
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_public_role(session)
    await _assert_last_admin(session)
    added = sorted(f"{code}:{effect}:{scope}" for code, effect, scope in proposed - current)
    removed = sorted(f"{code}:{effect}:{scope}" for code, effect, scope in current - proposed)
    return await _audit(
        session,
        revision=revision,
        role=role,
        actor_id=actor_id,
        action="role.permission_assigned",
        permission_code="admin.role.permission.assign",
        summary={"added": added, "removed": removed},
        affected_count=len(affected),
    )


async def replace_role_parents(
    session: AsyncSession,
    *,
    actor_id: UUID,
    role_id: UUID,
    expected_revision: int,
    parent_role_ids: tuple[UUID, ...],
) -> AuthorizationWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.role.permission.assign")
    if role_id in parent_role_ids:
        raise AppError(ErrorCode.STATE_CONFLICT)
    ids = {role_id, *parent_role_ids}
    locked = await _lock_roles(session, ids)
    role = locked[role_id]
    _expect(role, expected_revision)
    await _protect(session, actor_id, role)
    ceiling = await _role_ceiling(session, actor_id)
    if any(parent_id not in ceiling for parent_id in parent_role_ids):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    current = set(await _parent_ids(session, role.id))
    proposed = set(parent_role_ids)
    if current == proposed:
        return _unchanged(role, revision)
    before_actor = await _actor_pairs(session, actor_id)
    affected = await _affected_users(session, role.id)
    await session.execute(delete(RoleInheritance).where(RoleInheritance.child_role_id == role.id))
    session.add_all(
        [
            RoleInheritance(child_role_id=role.id, parent_role_id=parent_id)
            for parent_id in parent_role_ids
        ]
    )
    await session.flush()
    await _assert_graph(session)
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_public_role(session)
    await _assert_last_admin(session)
    return await _audit(
        session,
        revision=revision,
        role=role,
        actor_id=actor_id,
        action="role.inheritance_changed",
        permission_code="admin.role.permission.assign",
        summary={
            "added_parent_ids": sorted(str(item) for item in proposed - current),
            "removed_parent_ids": sorted(str(item) for item in current - proposed),
        },
        affected_count=len(affected),
    )


async def delete_role(
    session: AsyncSession, *, actor_id: UUID, role_id: UUID, expected_revision: int
) -> AuthorizationWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.role.delete")
    role = await _lock_role(session, role_id)
    _expect(role, expected_revision)
    await _protect(session, actor_id, role)
    policy = await session.get(AuthPolicy, "registration")
    if policy is not None and policy.default_role_id == role.id:
        raise AppError(ErrorCode.STATE_CONFLICT)
    members = await session.scalar(
        select(func.count()).select_from(UserRole).where(UserRole.role_id == role.id)
    )
    parents = await session.scalar(
        select(func.count())
        .select_from(RoleInheritance)
        .where(RoleInheritance.parent_role_id == role.id)
    )
    if members or parents:
        raise AppError(ErrorCode.STATE_CONFLICT)
    before_actor = await _actor_pairs(session, actor_id)
    await session.execute(delete(RoleInheritance).where(RoleInheritance.child_role_id == role.id))
    await session.execute(delete(RolePermission).where(RolePermission.role_id == role.id))
    await session.execute(
        delete(RoleGrantBoundary).where(
            (RoleGrantBoundary.grantor_role_id == role.id)
            | (RoleGrantBoundary.target_role_id == role.id)
        )
    )
    kept_revision = role.revision
    await session.delete(role)
    await session.flush()
    await _assert_graph(session)
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_public_role(session)
    await _assert_last_admin(session)
    revision.revision += 1
    request_id, operation_id = current_correlation()
    audit = AdminAuditEvent(
        action="role.deleted",
        actor="authenticated-admin",
        actor_user_id=actor_id,
        audience="admin",
        permission_code="admin.role.delete",
        target_type="role",
        target_id=role_id,
        target_code=role.code,
        result="committed",
        payload_schema_version=1,
        change_summary={"deleted": True},
        request_id=request_id,
        operation_id=operation_id,
        authorization_revision=revision.revision,
    )
    session.add(audit)
    await session.flush()
    session.add(
        OutboxEvent(
            event_type="authorization.changed",
            audit_event_id=audit.id,
            authorization_revision=revision.revision,
            status="pending",
        )
    )
    return AuthorizationWriteResult(
        role_id=role_id,
        revision=kept_revision,
        authorization_revision=revision.revision,
        audit_id=audit.id,
        affected_count=0,
    )


async def replace_grant_boundaries(
    session: AsyncSession,
    *,
    actor_id: UUID,
    role_id: UUID,
    expected_revision: int,
    boundaries: tuple[GrantBoundaryWrite, ...],
) -> AuthorizationWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.grant_boundary.update")
    role = await _lock_role(session, role_id)
    _expect(role, expected_revision)
    await _protect(session, actor_id, role)
    await _accept_boundaries(session, boundaries)
    current = await _boundary_key(session, role.id)
    proposed = {
        (item.boundary_kind, item.target_role_id, item.permission_code, item.data_scope)
        for item in boundaries
    }
    if current == proposed:
        return _unchanged(role, revision)
    await _assert_ceiling_not_self_raising(session, actor_id, role.id)
    before_actor = await _actor_pairs(session, actor_id)
    await session.execute(
        delete(RoleGrantBoundary).where(RoleGrantBoundary.grantor_role_id == role.id)
    )
    session.add_all(
        [
            RoleGrantBoundary(
                grantor_role_id=role.id,
                boundary_kind=item.boundary_kind,
                target_role_id=item.target_role_id,
                permission_code=item.permission_code,
                data_scope=item.data_scope,
                revision=1,
            )
            for item in boundaries
        ]
    )
    await session.flush()
    await _reject_elevation(session, actor_id, before_actor)
    await _assert_last_admin(session)
    return await _audit(
        session,
        revision=revision,
        role=role,
        actor_id=actor_id,
        action="grant_boundary.updated",
        permission_code="admin.grant_boundary.update",
        summary={"boundary_count": len(boundaries)},
        affected_count=0,
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


async def _lock_role(session: AsyncSession, role_id: UUID) -> Role:
    role = await session.scalar(select(Role).where(Role.id == role_id).with_for_update())
    if role is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return role


async def _lock_roles(session: AsyncSession, role_ids: set[UUID]) -> dict[UUID, Role]:
    locked: dict[UUID, Role] = {}
    for role_id in sorted(role_ids, key=lambda item: item.bytes):
        locked[role_id] = await _lock_role(session, role_id)
    return locked


def _expect(role: Role, expected_revision: int) -> None:
    if role.revision != expected_revision:
        raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=role.revision)


async def _protect(session: AsyncSession, actor_id: UUID, role: Role) -> None:
    if role.protected:
        await _require(session, actor_id, "admin.protected_role.manage")


async def _holds(session: AsyncSession, actor_id: UUID, code: str) -> bool:
    graph = await load_graph(session, actor_id)
    return allows(graph, actor_id, code, _ADMIN_SCOPE)


async def _actor_pairs(session: AsyncSession, actor_id: UUID) -> set[tuple[str, str]]:
    return allowed_pairs(await load_graph(session, actor_id), actor_id)


async def _reject_elevation(
    session: AsyncSession, actor_id: UUID, before: set[tuple[str, str]]
) -> None:
    if not await _actor_pairs(session, actor_id) <= before:
        raise AppError(ErrorCode.PERMISSION_DENIED)


async def _assert_enable_within_ceiling(
    session: AsyncSession, actor_id: UUID, role_id: UUID
) -> None:
    grants = await _grant_key(session, role_id)
    permission_ceiling = await _permission_ceiling(session, actor_id)
    if any((code, scope) not in permission_ceiling for code, _effect, scope in grants):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    role_ceiling = await _role_ceiling(session, actor_id)
    if any(parent_id not in role_ceiling for parent_id in await _parent_ids(session, role_id)):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    if role_id not in await _actor_bound_role_ids(session, actor_id):
        return
    if await _holds(session, actor_id, "admin.protected_role.manage"):
        return
    owned = await _enabled_boundary_keys(session, actor_id)
    if not await _boundary_key(session, role_id) <= owned:
        raise AppError(ErrorCode.PERMISSION_DENIED)


async def _assert_ceiling_not_self_raising(
    session: AsyncSession, actor_id: UUID, role_id: UUID
) -> None:
    """A ceiling on a held role, including a disabled ancestor, is the actor's own."""
    if role_id not in await _actor_bound_role_ids(session, actor_id):
        return
    if not await _holds(session, actor_id, "admin.protected_role.manage"):
        raise AppError(ErrorCode.PERMISSION_DENIED)


async def _permission_ceiling(session: AsyncSession, actor_id: UUID) -> set[tuple[str, str]]:
    role_ids = await _actor_role_ids(session, actor_id)
    if not role_ids:
        return set()
    rows = (
        await session.execute(
            select(RoleGrantBoundary.permission_code, RoleGrantBoundary.data_scope).where(
                RoleGrantBoundary.grantor_role_id.in_(role_ids),
                RoleGrantBoundary.boundary_kind == "assign_permission",
            )
        )
    ).all()
    return {(code, scope) for code, scope in rows if code is not None and scope is not None}


async def _role_ceiling(session: AsyncSession, actor_id: UUID) -> set[UUID]:
    role_ids = await _actor_role_ids(session, actor_id)
    if not role_ids:
        return set()
    rows = (
        await session.scalars(
            select(RoleGrantBoundary.target_role_id).where(
                RoleGrantBoundary.grantor_role_id.in_(role_ids),
                RoleGrantBoundary.boundary_kind == "assign_role",
                RoleGrantBoundary.target_role_id.is_not(None),
            )
        )
    ).all()
    return {role_id for role_id in rows if role_id is not None}


async def _actor_role_ids(session: AsyncSession, actor_id: UUID) -> list[UUID]:
    graph = await load_graph(session, actor_id)
    return [UUID(role_id) for role_id in closure(graph.direct_role_ids, graph.edges)]


async def _actor_bound_role_ids(session: AsyncSession, actor_id: UUID) -> set[UUID]:
    """Roles the actor holds directly or reaches through parents, enabled or not."""
    direct = set(
        (await session.scalars(select(UserRole.role_id).where(UserRole.user_id == actor_id))).all()
    )
    if not direct:
        return set()
    edges = (
        await session.execute(select(RoleInheritance.child_role_id, RoleInheritance.parent_role_id))
    ).all()
    parents: dict[UUID, list[UUID]] = {}
    for child_id, parent_id in edges:
        parents.setdefault(child_id, []).append(parent_id)
    seen = set(direct)
    pending = list(direct)
    while pending:
        current = pending.pop()
        for parent_id in parents.get(current, ()):
            if parent_id not in seen:
                seen.add(parent_id)
                pending.append(parent_id)
    return seen


async def _enabled_boundary_keys(
    session: AsyncSession, actor_id: UUID
) -> set[tuple[str, UUID | None, str | None, str | None]]:
    role_ids = await _actor_role_ids(session, actor_id)
    if not role_ids:
        return set()
    rows = (
        await session.execute(
            select(
                RoleGrantBoundary.boundary_kind,
                RoleGrantBoundary.target_role_id,
                RoleGrantBoundary.permission_code,
                RoleGrantBoundary.data_scope,
            ).where(RoleGrantBoundary.grantor_role_id.in_(role_ids))
        )
    ).all()
    return {(kind, target_id, code, scope) for kind, target_id, code, scope in rows}


async def _accept_grants(session: AsyncSession, grants: tuple[tuple[str, str, str], ...]) -> None:
    if not grants:
        return
    codes = tuple({code for code, _effect, _scope in grants})
    rows = (
        await session.scalars(select(PermissionCatalog).where(PermissionCatalog.code.in_(codes)))
    ).all()
    catalog = {row.code: row for row in rows}
    for code, _effect, scope in grants:
        row = catalog.get(code)
        if row is None or not row.enabled or row.data_scope != scope:
            raise AppError(ErrorCode.STATE_CONFLICT)


async def _accept_boundaries(
    session: AsyncSession, boundaries: tuple[GrantBoundaryWrite, ...]
) -> None:
    permission_items = [item for item in boundaries if item.boundary_kind == "assign_permission"]
    if permission_items:
        codes = tuple({item.permission_code for item in permission_items if item.permission_code})
        rows = (
            await session.scalars(
                select(PermissionCatalog).where(PermissionCatalog.code.in_(codes))
            )
        ).all()
        catalog = {row.code: row for row in rows}
        for item in permission_items:
            row = catalog.get(item.permission_code or "")
            if row is None or not row.enabled or row.data_scope != item.data_scope:
                raise AppError(ErrorCode.STATE_CONFLICT)
    targets = {item.target_role_id for item in boundaries if item.target_role_id is not None}
    if not targets:
        return
    found = set((await session.scalars(select(Role.id).where(Role.id.in_(targets)))).all())
    if found != targets:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)


async def _assert_graph(session: AsyncSession) -> None:
    edges = await _all_edges(session)
    try:
        validate_inheritance_graph(edges)
    except AppError:
        raise AppError(ErrorCode.STATE_CONFLICT) from None


async def _assert_public_role(session: AsyncSession) -> None:
    policy = await session.get(AuthPolicy, "registration")
    if policy is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    role = await session.get(Role, policy.default_role_id)
    if role is None or not role.enabled or role.protected:
        raise AppError(ErrorCode.STATE_CONFLICT)
    graph = GrantGraph(
        direct_role_ids=(str(role.id),),
        edges=await _all_edges(session),
        grants=await _all_grants(session),
    )
    if not graph_accepts_authorization(graph):
        raise AppError(ErrorCode.STATE_CONFLICT)
    if any(
        code.startswith("admin.") or scope != "self"
        for code, scope in allowed_pairs(graph, role.id)
    ):
        raise AppError(ErrorCode.STATE_CONFLICT)


async def _assert_last_admin(session: AsyncSession) -> None:
    require_super_admin_remains(
        await count_login_capable_super_admins(session, now=datetime.now(UTC))
    )


async def _affected_users(session: AsyncSession, role_id: UUID) -> list[UUID]:
    edges = await _all_edges(session)
    children: dict[str, set[str]] = {}
    for child, parent in edges:
        children.setdefault(parent, set()).add(child)
    seen = {str(role_id)}
    pending = [str(role_id)]
    while pending:
        current = pending.pop()
        for child in children.get(current, ()):
            if child not in seen:
                seen.add(child)
                pending.append(child)
    rows = (
        await session.scalars(
            select(UserRole.user_id).where(UserRole.role_id.in_([UUID(item) for item in seen]))
        )
    ).all()
    return list(dict.fromkeys(rows))


async def _pairs_for(
    session: AsyncSession, user_ids: list[UUID]
) -> dict[UUID, set[tuple[str, str]]]:
    return {user_id: await _actor_pairs(session, user_id) for user_id in user_ids}


async def _effective_change(
    session: AsyncSession,
    user_ids: list[UUID],
    before: dict[UUID, set[tuple[str, str]]],
    *,
    had_assign: bool,
) -> bool:
    after = await _pairs_for(session, user_ids)
    changed = any(after[user_id] != before[user_id] for user_id in user_ids)
    if changed and not had_assign:
        raise AppError(ErrorCode.PERMISSION_DENIED)
    return changed


async def _all_edges(session: AsyncSession) -> tuple[tuple[str, str], ...]:
    rows = (
        await session.execute(select(RoleInheritance.child_role_id, RoleInheritance.parent_role_id))
    ).all()
    return tuple((str(child), str(parent)) for child, parent in rows)


async def _all_grants(session: AsyncSession) -> tuple[tuple[str, str, str, str], ...]:
    rows = (
        await session.execute(
            select(
                RolePermission.role_id,
                RolePermission.permission_code,
                RolePermission.effect,
                RolePermission.data_scope,
            )
        )
    ).all()
    return tuple((str(role_id), code, effect, scope) for role_id, code, effect, scope in rows)


async def _grant_key(session: AsyncSession, role_id: UUID) -> set[tuple[str, str, str]]:
    rows = (
        await session.execute(
            select(
                RolePermission.permission_code, RolePermission.effect, RolePermission.data_scope
            ).where(RolePermission.role_id == role_id)
        )
    ).all()
    return {(code, effect, scope) for code, effect, scope in rows}


async def _parent_ids(session: AsyncSession, role_id: UUID) -> list[UUID]:
    return list(
        (
            await session.scalars(
                select(RoleInheritance.parent_role_id).where(
                    RoleInheritance.child_role_id == role_id
                )
            )
        ).all()
    )


async def _boundary_key(
    session: AsyncSession, role_id: UUID
) -> set[tuple[str, UUID | None, str | None, str | None]]:
    rows = (
        await session.execute(
            select(
                RoleGrantBoundary.boundary_kind,
                RoleGrantBoundary.target_role_id,
                RoleGrantBoundary.permission_code,
                RoleGrantBoundary.data_scope,
            ).where(RoleGrantBoundary.grantor_role_id == role_id)
        )
    ).all()
    return {(kind, target_id, code, scope) for kind, target_id, code, scope in rows}


async def _role_read(session: AsyncSession, role: Role) -> RoleRead:
    grant_rows = (
        await session.execute(
            select(RolePermission.permission_code, RolePermission.effect, RolePermission.data_scope)
            .where(RolePermission.role_id == role.id)
            .order_by(RolePermission.permission_code, RolePermission.effect)
        )
    ).all()
    parent_rows = (
        await session.execute(
            select(Role.id, Role.code, Role.enabled)
            .join(RoleInheritance, RoleInheritance.parent_role_id == Role.id)
            .where(RoleInheritance.child_role_id == role.id)
            .order_by(Role.code)
        )
    ).all()
    member_count = await session.scalar(
        select(func.count()).select_from(UserRole).where(UserRole.role_id == role.id)
    )
    return RoleRead(
        id=role.id,
        code=role.code,
        name=role.name,
        description=role.description,
        protected=role.protected,
        enabled=role.enabled,
        revision=role.revision,
        grants=[
            RoleGrantRead(
                permission_code=code,
                effect="allow" if effect == "allow" else "deny",
                data_scope="self" if scope == "self" else "platform_metadata",
            )
            for code, effect, scope in grant_rows
        ],
        parents=[
            RoleParentRead(role_id=parent_id, code=code, enabled=enabled)
            for parent_id, code, enabled in parent_rows
        ],
        member_count=int(member_count or 0),
    )


def _boundary_read(row: RoleGrantBoundary) -> GrantBoundaryRead:
    scope = row.data_scope
    return GrantBoundaryRead(
        boundary_kind=(
            "assign_role"
            if row.boundary_kind == "assign_role"
            else "assign_permission"
            if row.boundary_kind == "assign_permission"
            else "manage_account_role"
            if row.boundary_kind == "manage_account_role"
            else "manage_unassigned_accounts"
        ),
        target_role_id=row.target_role_id,
        permission_code=row.permission_code,
        data_scope="self" if scope == "self" else "platform_metadata" if scope else None,
        revision=row.revision,
    )


def _unchanged(role: Role, revision: AuthorizationRevision) -> AuthorizationWriteResult:
    return AuthorizationWriteResult(
        role_id=role.id,
        revision=role.revision,
        authorization_revision=revision.revision,
        audit_id=None,
        affected_count=0,
    )


async def _audit(
    session: AsyncSession,
    *,
    actor_id: UUID,
    revision: AuthorizationRevision,
    role: Role,
    action: str,
    permission_code: str,
    summary: dict[str, object],
    affected_count: int,
) -> AuthorizationWriteResult:
    now = datetime.now(UTC)
    role.revision += 1
    role.updated_at = now
    revision.revision += 1
    request_id, operation_id = current_correlation()
    audit = AdminAuditEvent(
        action=action,
        actor="authenticated-admin",
        actor_user_id=actor_id,
        audience="admin",
        permission_code=permission_code,
        target_type="role",
        target_id=role.id,
        target_code=role.code,
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
            event_type="authorization.changed",
            audit_event_id=audit.id,
            authorization_revision=revision.revision,
            status="pending",
        )
    )
    return AuthorizationWriteResult(
        role_id=role.id,
        revision=role.revision,
        authorization_revision=revision.revision,
        audit_id=audit.id,
        affected_count=affected_count,
    )
