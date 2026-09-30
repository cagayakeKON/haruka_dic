"""Menu visibility can tighten a page floor and cannot publish an empty parent."""

import pytest

from app.contracts.navigation import (
    MenuProjection,
    leaf_visible,
    validate_menu_parents,
    visible_menu_entries,
)

pytestmark = pytest.mark.unit


def _menu(
    menu_id: str,
    *,
    route: str | None,
    parent: str | None = None,
    enabled: bool = True,
    floor: tuple[str, ...] = ("admin.user.read",),
    extras: tuple[str, ...] = (),
    match: str = "all",
    sort_order: int = 0,
) -> MenuProjection:
    return MenuProjection(
        menu_id=menu_id,
        code=menu_id,
        route_key=route,
        title=menu_id,
        parent_id=parent,
        sort_order=sort_order,
        enabled=enabled,
        permission_match=match,
        floor=() if route is None else floor,
        extras=extras,
    )


def test_extras_only_tighten_the_page_floor() -> None:
    allowed = {"admin.user.read"}
    assert leaf_visible(("admin.user.read",), (), "all", allowed)
    assert not leaf_visible((), (), "all", allowed)
    assert not leaf_visible(("admin.user.read",), ("admin.audit.read",), "all", allowed)
    assert leaf_visible(("admin.user.read",), ("admin.audit.read",), "any", set()) is False
    assert leaf_visible(
        ("admin.user.read",), ("admin.audit.read", "admin.user.read"), "any", allowed
    )


def test_disabled_parent_and_empty_group_stay_out_of_navigation() -> None:
    group = _menu("group", route=None)
    child = _menu("users", route="users", parent="group", sort_order=2)
    other = _menu("roles", route="roles", floor=("admin.role.read",), sort_order=1)
    allowed = {"admin.user.read", "admin.role.read"}
    assert visible_menu_entries([group, child, other], allowed) == [
        ("users", "users", "users"),
        ("roles", "roles", "roles"),
    ]
    hidden = _menu("group", route=None, enabled=False)
    assert visible_menu_entries([hidden, child, other], allowed) == [("roles", "roles", "roles")]
    assert visible_menu_entries([group], allowed) == []


def test_parent_cycles_and_deep_chains_are_rejected() -> None:
    with pytest.raises(ValueError):
        validate_menu_parents({"a": "b", "b": "a"})
    with pytest.raises(ValueError):
        validate_menu_parents({"a": "b", "b": "c", "c": "d", "d": "e", "e": "f"})
    validate_menu_parents({"a": "b", "b": "c", "c": "d", "d": "e", "e": None})
