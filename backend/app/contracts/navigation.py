"""Published navigation pages. Menu rows can only display these routes.

Page floors stay in this registry. Stored menu permissions are extra display
conditions and cannot replace the floor.
"""

from dataclasses import dataclass
from typing import Literal

_MAX_PARENT_DEPTH = 4


@dataclass(frozen=True, slots=True)
class PublishedPage:
    code: str
    audience: Literal["client", "admin"]
    route_key: str
    component_key: str
    floor: tuple[str, ...]
    icon_key: str
    title: str
    sort_order: int


PUBLISHED_PAGES: tuple[PublishedPage, ...] = (
    PublishedPage(
        "overview",
        "admin",
        "overview",
        "admin.overview",
        ("admin.dashboard.view",),
        "grid",
        "概览",
        10,
    ),
    PublishedPage(
        "users", "admin", "users", "admin.users", ("admin.user.read",), "person", "用户与会话", 20
    ),
    PublishedPage(
        "roles", "admin", "roles", "admin.roles", ("admin.role.read",), "shield", "角色与权限", 30
    ),
    PublishedPage(
        "menus", "admin", "menus", "admin.menus", ("admin.menu.read",), "layers", "菜单", 40
    ),
    PublishedPage(
        "policy",
        "admin",
        "policy",
        "admin.policy",
        ("admin.auth_policy.read",),
        "settings",
        "注册策略",
        50,
    ),
    PublishedPage(
        "jobs", "admin", "jobs", "admin.jobs", ("admin.job.read",), "schedule", "资源任务", 60
    ),
    PublishedPage(
        "audit", "admin", "audit", "admin.audit", ("admin.audit.read",), "book", "审计", 70
    ),
    PublishedPage(
        "usage",
        "admin",
        "usage",
        "admin.usage",
        ("admin.dashboard.view",),
        "spark",
        "用量",
        80,
    ),
    PublishedPage(
        "library",
        "client",
        "/reference/materials",
        "client.library",
        ("client.material.list",),
        "library",
        "书库",
        10,
    ),
    PublishedPage(
        "notebooks",
        "client",
        "/collections",
        "client.notebooks",
        ("client.vocabulary_notebook.read",),
        "notebooks",
        "单词本",
        20,
    ),
    PublishedPage(
        "query", "client", "/query", "client.query", ("client.agent.read",), "query", "查询", 30
    ),
    PublishedPage(
        "exercise",
        "client",
        "/exercise",
        "client.exercise",
        ("client.practice.read",),
        "exercise",
        "习题",
        40,
    ),
    PublishedPage(
        "settings",
        "client",
        "/settings",
        "client.settings",
        ("client.profile.read",),
        "settings",
        "设置",
        50,
    ),
)

PUBLISHED_ICONS = frozenset(
    {
        "grid",
        "person",
        "shield",
        "layers",
        "settings",
        "schedule",
        "book",
        "spark",
        "library",
        "notebooks",
        "query",
        "exercise",
    }
)

_BY_CODE = {page.code: page for page in PUBLISHED_PAGES}
_BY_ROUTE = {(page.audience, page.route_key): page for page in PUBLISHED_PAGES}


def published_page(code: str) -> PublishedPage | None:
    return _BY_CODE.get(code)


def published_route(audience: str, route_key: str) -> PublishedPage | None:
    if audience != "client" and audience != "admin":
        return None
    return _BY_ROUTE.get((audience, route_key))


@dataclass(frozen=True, slots=True)
class MenuProjection:
    menu_id: str
    code: str
    route_key: str | None
    title: str
    parent_id: str | None
    sort_order: int
    enabled: bool
    permission_match: str
    floor: tuple[str, ...]
    extras: tuple[str, ...]


def leaf_visible(
    floor: tuple[str, ...], extras: tuple[str, ...], match: str, allowed: set[str]
) -> bool:
    """A leaf stays hidden until its code floor holds. Extras can only tighten that."""
    if not floor or not set(floor) <= allowed:
        return False
    if not extras:
        return True
    if match == "any":
        return any(code in allowed for code in extras)
    return set(extras) <= allowed


def validate_menu_parents(parents: dict[str, str | None]) -> None:
    """Reject a cycle or a parent chain longer than four edges."""
    for menu_id in parents:
        seen: set[str] = set()
        current = menu_id
        depth = 0
        while True:
            parent = parents.get(current)
            if parent is None:
                break
            if parent not in parents or parent in seen or parent == current:
                raise ValueError("menu parent cycle")
            seen.add(current)
            current = parent
            depth += 1
            if depth > _MAX_PARENT_DEPTH:
                raise ValueError("menu parent depth")


def visible_menu_entries(
    menus: tuple[MenuProjection, ...] | list[MenuProjection], allowed: set[str]
) -> list[tuple[str, str, str]]:
    """Visible leaves in parent/sort order. Empty or disabled parents contribute nothing."""
    by_id = {menu.menu_id: menu for menu in menus}

    def shown(menu: MenuProjection) -> bool:
        if menu.route_key is None or not menu.enabled:
            return False
        current = menu
        seen: set[str] = set()
        while current.parent_id is not None:
            if current.parent_id in seen:
                return False
            seen.add(current.parent_id)
            parent = by_id.get(current.parent_id)
            if parent is None or not parent.enabled:
                return False
            current = parent
        return leaf_visible(menu.floor, menu.extras, menu.permission_match, allowed)

    visible = {menu.menu_id for menu in menus if shown(menu)}
    children: dict[str | None, list[MenuProjection]] = {}
    for menu in menus:
        children.setdefault(menu.parent_id, []).append(menu)
    for group in children.values():
        group.sort(key=lambda item: (item.sort_order, item.menu_id))
    ordered: list[tuple[str, str, str]] = []

    def walk(parent_id: str | None) -> None:
        for menu in children.get(parent_id, []):
            if menu.menu_id in visible and menu.route_key is not None:
                ordered.append((menu.code, menu.route_key, menu.title))
            walk(menu.menu_id)

    walk(None)
    return ordered
