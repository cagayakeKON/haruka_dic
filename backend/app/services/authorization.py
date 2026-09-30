"""Authorization decisions projected from PostgreSQL. Casbin does not store grants.

Each protected request reads the current transaction. Redis is not a second policy
ledger and is not consulted here, so a grant written in the same transaction is visible.
"""

import json
from dataclasses import dataclass
from datetime import datetime
from typing import cast
from uuid import UUID

import casbin
from casbin.model import Model
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.models import Role, User, UserRole

MAX_INHERITANCE_DEPTH = 4
_MODEL = """
[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act, eft

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow)) && !some(where (p.eft == deny))

[matchers]
m = g(r.sub, p.sub) && r.obj == p.obj && r.act == p.act
"""


@dataclass(frozen=True)
class GrantGraph:
    direct_role_ids: tuple[str, ...]
    edges: tuple[tuple[str, str], ...]
    grants: tuple[tuple[str, str, str, str], ...]


def validate_inheritance_graph(edges: tuple[tuple[str, str], ...]) -> None:
    """Reject self-links, cycles, and paths deeper than the published limit."""
    parents: dict[str, set[str]] = {}
    nodes: set[str] = set()
    for child, parent in edges:
        if child == parent:
            raise AppError(ErrorCode.STATE_CONFLICT)
        parents.setdefault(child, set()).add(parent)
        nodes.add(child)
        nodes.add(parent)
    visiting: set[str] = set()
    longest: dict[str, int] = {}

    def height(node: str) -> int:
        if node in visiting:
            raise AppError(ErrorCode.STATE_CONFLICT)
        cached = longest.get(node)
        if cached is not None:
            return cached
        visiting.add(node)
        distance = 0
        for parent in parents.get(node, ()):
            distance = max(distance, 1 + height(parent))
        visiting.remove(node)
        if distance > MAX_INHERITANCE_DEPTH:
            raise AppError(ErrorCode.STATE_CONFLICT)
        longest[node] = distance
        return distance

    for node in nodes:
        height(node)


def closure(direct_role_ids: tuple[str, ...], edges: tuple[tuple[str, str], ...]) -> set[str]:
    """Enabled-only ancestor set. A shorter path can still expand a node seen more deeply."""
    parents: dict[str, set[str]] = {}
    for child, parent in edges:
        parents.setdefault(child, set()).add(parent)
    best_depth: dict[str, int] = {}
    pending = [(role_id, 0) for role_id in direct_role_ids]
    while pending:
        role_id, depth = pending.pop()
        if depth > MAX_INHERITANCE_DEPTH:
            continue
        previous = best_depth.get(role_id)
        if previous is not None and previous <= depth:
            continue
        best_depth[role_id] = depth
        pending.extend((parent, depth + 1) for parent in parents.get(role_id, ()))
    return set(best_depth)


def graph_accepts_authorization(graph: GrantGraph) -> bool:
    """Illegal inheritance does not participate in a decision."""
    try:
        validate_inheritance_graph(graph.edges)
    except AppError:
        return False
    return True


def _enforcer(graph: GrantGraph, user_key: str) -> casbin.Enforcer:
    model = Model()
    model.load_model_from_text(_MODEL)
    enforcer = casbin.Enforcer(model)
    roles = closure(graph.direct_role_ids, graph.edges)
    for role_id in graph.direct_role_ids:
        enforcer.add_grouping_policy(user_key, f"role::{role_id}")
    for child, parent in graph.edges:
        if child in roles and parent in roles:
            enforcer.add_grouping_policy(f"role::{child}", f"role::{parent}")
    for role_id, code, effect, scope in graph.grants:
        if role_id in roles:
            enforcer.add_policy(f"role::{role_id}", code, scope, effect)
    enforcer.build_role_links()
    return enforcer


def allows(graph: GrantGraph, user_id: UUID, code: str, scope: str) -> bool:
    if not graph.direct_role_ids or not graph_accepts_authorization(graph):
        return False
    enforcer = _enforcer(graph, f"user::{user_id}")
    return bool(enforcer.enforce(f"user::{user_id}", code, scope))


def allowed_pairs(graph: GrantGraph, user_id: UUID) -> set[tuple[str, str]]:
    """Permission code and data scope pairs the user may use."""
    if not graph.direct_role_ids or not graph_accepts_authorization(graph):
        return set()
    enforcer = _enforcer(graph, f"user::{user_id}")
    user_key = f"user::{user_id}"
    pairs = {(code, scope) for _role, code, _effect, scope in graph.grants}
    return {pair for pair in pairs if bool(enforcer.enforce(user_key, pair[0], pair[1]))}


def login_capable_super_admin(
    *,
    status: str,
    role_enabled: bool,
    locked_until: datetime | None,
    has_admin_login: bool,
    now: datetime,
) -> bool:
    return (
        status == "active"
        and role_enabled
        and has_admin_login
        and (locked_until is None or locked_until <= now)
    )


def require_super_admin_remains(count: int) -> None:
    if count < 1:
        raise AppError(ErrorCode.STATE_CONFLICT)


_GRAPH_SQL = text(
    """
    SELECT
      EXISTS (
        SELECT 1 FROM authorization_revisions WHERE code = 'global'
      ) AS present,
      COALESCE((
        SELECT jsonb_agg(roles.id::text ORDER BY roles.id)
        FROM user_role_links
        JOIN roles ON roles.id = user_role_links.role_id
        WHERE user_role_links.user_id = :user_id AND roles.enabled
      ), '[]'::jsonb) AS direct_roles,
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_array(links.child_role_id::text, links.parent_role_id::text)
          ORDER BY links.child_role_id, links.parent_role_id
        )
        FROM role_inheritance_links AS links
        JOIN roles AS child ON child.id = links.child_role_id
        JOIN roles AS parent ON parent.id = links.parent_role_id
        WHERE child.enabled AND parent.enabled
      ), '[]'::jsonb) AS edges,
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_array(
            grants.role_id::text, grants.permission_code, grants.effect, grants.data_scope
          )
          ORDER BY grants.role_id, grants.permission_code, grants.effect, grants.data_scope
        )
        FROM role_permission_links AS grants
        JOIN roles ON roles.id = grants.role_id
        WHERE roles.enabled
      ), '[]'::jsonb) AS grants
    """
)


def _json_rows(value: object) -> list[object]:
    parsed: object = json.loads(value) if isinstance(value, str) else value
    if not isinstance(parsed, list):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return cast("list[object]", parsed)


def _as_list(value: object) -> list[object] | None:
    if isinstance(value, list):
        return cast("list[object]", value)
    return None


def _tuples(value: object, width: int) -> list[tuple[str, ...]]:
    rows: list[tuple[str, ...]] = []
    for item in _json_rows(value):
        parts = _as_list(item)
        if parts is None or len(parts) != width:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        rows.append(tuple(str(part) for part in parts))
    return rows


async def load_graph(session: AsyncSession, user_id: UUID) -> GrantGraph:
    """Read roles, inheritance, and grants in one statement.

    READ COMMITTED takes the snapshot at the start of that statement, so one grant
    commit cannot appear between the three sets. The read takes no lock: some
    callers already hold the user row, and writers lock the global revision first.
    A missing global revision returns an empty graph.
    """
    row = (await session.execute(_GRAPH_SQL, {"user_id": user_id})).one()
    if not row.present:
        return GrantGraph(direct_role_ids=(), edges=(), grants=())
    return GrantGraph(
        direct_role_ids=tuple(str(role_id) for role_id in _json_rows(row.direct_roles)),
        edges=tuple((edge[0], edge[1]) for edge in _tuples(row.edges, 2)),
        grants=tuple((grant[0], grant[1], grant[2], grant[3]) for grant in _tuples(row.grants, 4)),
    )


async def require_effective_permissions(
    session: AsyncSession,
    *,
    user_id: UUID,
    requirements: tuple[tuple[str, str], ...],
) -> None:
    graph = await load_graph(session, user_id)
    if any(not allows(graph, user_id, code, scope) for code, scope in requirements):
        raise AppError(ErrorCode.PERMISSION_DENIED)


async def count_login_capable_super_admins(session: AsyncSession, *, now: datetime) -> int:
    """Users who can still sign in through the enabled super_admin role."""
    rows = (
        await session.execute(
            select(User.id, User.status, User.locked_until, Role.enabled)
            .join(UserRole, UserRole.user_id == User.id)
            .join(Role, Role.id == UserRole.role_id)
            .where(Role.code == "super_admin")
        )
    ).all()
    capable = 0
    for user_id, status, locked_until, role_enabled in rows:
        graph = await load_graph(session, user_id)
        has_login = allows(graph, user_id, "admin.login", "platform_metadata")
        if login_capable_super_admin(
            status=status,
            role_enabled=role_enabled,
            locked_until=locked_until,
            has_admin_login=has_login,
            now=now,
        ):
            capable += 1
    return capable
