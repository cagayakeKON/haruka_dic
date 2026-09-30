"""Inheritance, explicit deny, and last-administrator protection."""

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.services.authorization import (
    MAX_INHERITANCE_DEPTH,
    GrantGraph,
    allows,
    login_capable_super_admin,
    require_super_admin_remains,
    validate_inheritance_graph,
)
from app.services.sessions import menu_visible

pytestmark = pytest.mark.unit
USER = UUID("00000000-0000-4000-8000-000000000001")


def _graph(
    *,
    direct: tuple[str, ...],
    edges: tuple[tuple[str, str], ...] = (),
    grants: tuple[tuple[str, str, str, str], ...],
) -> GrantGraph:
    return GrantGraph(direct_role_ids=direct, edges=edges, grants=grants)


def test_inherited_allow_is_visible_and_explicit_deny_wins() -> None:
    child, parent = str(uuid4()), str(uuid4())
    inherited = _graph(
        direct=(child,),
        edges=((child, parent),),
        grants=((parent, "admin.login", "allow", "platform_metadata"),),
    )
    assert allows(inherited, USER, "admin.login", "platform_metadata")
    denied = _graph(
        direct=(child,),
        edges=((child, parent),),
        grants=(
            (parent, "admin.login", "allow", "platform_metadata"),
            (child, "admin.login", "deny", "platform_metadata"),
        ),
    )
    assert not allows(denied, USER, "admin.login", "platform_metadata")


def test_parent_deny_beats_child_allow_and_scope_must_match() -> None:
    child, parent = str(uuid4()), str(uuid4())
    denied = _graph(
        direct=(child,),
        edges=((child, parent),),
        grants=(
            (child, "admin.user.read", "allow", "platform_metadata"),
            (parent, "admin.user.read", "deny", "platform_metadata"),
        ),
    )
    assert not allows(denied, USER, "admin.user.read", "platform_metadata")
    wrong_scope = _graph(
        direct=(child,),
        grants=((child, "admin.user.read", "allow", "self"),),
    )
    assert not allows(wrong_scope, USER, "admin.user.read", "platform_metadata")


def test_illegal_inheritance_denies_even_a_direct_allow() -> None:
    child = str(uuid4())
    chain = tuple((str(index), str(index + 1)) for index in range(MAX_INHERITANCE_DEPTH + 1))
    too_deep = _graph(
        direct=(child, "0"),
        edges=chain,
        grants=((child, "admin.login", "allow", "platform_metadata"),),
    )
    assert not allows(too_deep, USER, "admin.login", "platform_metadata")
    cycle = _graph(
        direct=(child,),
        edges=(("a", "b"), ("b", "a")),
        grants=((child, "admin.login", "allow", "platform_metadata"),),
    )
    assert not allows(cycle, USER, "admin.login", "platform_metadata")


def test_inheritance_rejects_cycles_and_excessive_depth() -> None:
    first, second = "a", "b"
    with pytest.raises(AppError) as cycle:
        validate_inheritance_graph(((first, second), (second, first)))
    assert cycle.value.code == ErrorCode.STATE_CONFLICT
    chain = tuple((str(index), str(index + 1)) for index in range(MAX_INHERITANCE_DEPTH + 1))
    with pytest.raises(AppError) as depth:
        validate_inheritance_graph(chain)
    assert depth.value.code == ErrorCode.STATE_CONFLICT
    validate_inheritance_graph(
        tuple((str(index), str(index + 1)) for index in range(MAX_INHERITANCE_DEPTH))
    )


def test_menu_visibility_requires_linked_permissions() -> None:
    allowed = {"admin.login"}
    assert not menu_visible([], "all", allowed)
    assert not menu_visible(["admin.user.read"], "any", allowed)
    assert menu_visible(["admin.login", "admin.user.read"], "any", allowed)
    assert not menu_visible(["admin.login", "admin.user.read"], "all", allowed)
    assert menu_visible(["admin.login"], "all", allowed)


def test_last_super_admin_must_remain_login_capable() -> None:
    now = datetime(2026, 9, 29, tzinfo=UTC)
    assert login_capable_super_admin(
        status="active",
        role_enabled=True,
        locked_until=None,
        has_admin_login=True,
        now=now,
    )
    assert not login_capable_super_admin(
        status="disabled",
        role_enabled=True,
        locked_until=None,
        has_admin_login=True,
        now=now,
    )
    require_super_admin_remains(1)
    with pytest.raises(AppError) as lost:
        require_super_admin_remains(0)
    assert lost.value.code == ErrorCode.STATE_CONFLICT
