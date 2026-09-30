"""Menu layout writes. Hiding a menu does not revoke the page permission."""

from datetime import UTC, datetime
from typing import Literal
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.contracts.navigation import (
    PUBLISHED_ICONS,
    PUBLISHED_PAGES,
    MenuProjection,
    published_page,
    published_route,
    validate_menu_parents,
    visible_menu_entries,
)
from app.domain.correlation import current_correlation
from app.domain.errors import AppError
from app.models import (
    AdminAuditEvent,
    AuthorizationRevision,
    Menu,
    MenuPermission,
    OutboxEvent,
    PermissionCatalog,
    User,
)
from app.schemas.auth import NavigationRead
from app.schemas.menu_governance import (
    MenuCatalogPage,
    MenuCatalogRead,
    MenuGroupCreate,
    MenuLayoutItem,
    MenuPermissionChoice,
    MenuRead,
    MenuWriteResult,
)
from app.services.auth_context import require_permissions
from app.services.authorization import allowed_pairs, load_graph

_MAX_MENUS = 64


async def list_menus(session: AsyncSession, *, actor_id: UUID) -> list[MenuRead]:
    await _require(session, actor_id, "admin.menu.read")
    return await _reads(session)


async def read_catalog(session: AsyncSession, *, actor_id: UUID) -> MenuCatalogRead:
    await _require(session, actor_id, "admin.menu.read")
    codes = (
        await session.execute(
            select(PermissionCatalog.code, PermissionCatalog.audience)
            .where(PermissionCatalog.enabled.is_(True))
            .order_by(PermissionCatalog.code)
        )
    ).all()
    return MenuCatalogRead(
        pages=[
            MenuCatalogPage(
                code=page.code,
                audience=page.audience,
                route_key=page.route_key,
                component_key=page.component_key,
                floor=list(page.floor),
                icon_key=page.icon_key,
                title=page.title,
                sort_order=page.sort_order,
            )
            for page in PUBLISHED_PAGES
        ],
        icons=sorted(PUBLISHED_ICONS),
        permission_codes=[
            MenuPermissionChoice(code=code, audience="admin" if audience == "admin" else "client")
            for code, audience in codes
            if audience in {"client", "admin"}
        ],
    )


async def create_group(
    session: AsyncSession, *, actor_id: UUID, command: MenuGroupCreate
) -> MenuWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.menu.update")
    if published_page(command.code) is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    existing = await session.scalar(select(Menu.id).where(Menu.code == command.code))
    if existing is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    audience_count = len(
        (await session.scalars(select(Menu.id).where(Menu.audience == command.audience))).all()
    )
    if audience_count >= _MAX_MENUS:
        raise AppError(ErrorCode.STATE_CONFLICT)
    parents = await _parent_map(session)
    parent_id = _parent_text(command.parent_menu_id)
    if command.parent_menu_id is not None:
        parent = await session.get(Menu, command.parent_menu_id)
        if parent is None or parent.audience != command.audience:
            raise AppError(ErrorCode.INPUT_INVALID)
    try:
        validate_menu_parents({**parents, "new": parent_id})
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    menu = Menu(
        code=command.code,
        route_key=None,
        component_key=None,
        audience=command.audience,
        parent_menu_id=command.parent_menu_id,
        title=command.title,
        icon_key=None,
        sort_order=command.sort_order,
        permission_match="all",
        enabled=True,
        revision=1,
    )
    session.add(menu)
    await session.flush()
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        target_id=menu.id,
        summary={"op": "group_created", "code": command.code},
        affected_count=1,
    )


async def replace_layout(
    session: AsyncSession, *, actor_id: UUID, items: tuple[MenuLayoutItem, ...]
) -> MenuWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.menu.update")
    locked: dict[UUID, Menu] = {}
    for menu_id in sorted({item.menu_id for item in items}, key=lambda value: value.bytes):
        menu = await session.scalar(select(Menu).where(Menu.id == menu_id).with_for_update())
        if menu is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        locked[menu_id] = menu
    for item in items:
        if locked[item.menu_id].revision != item.expected_revision:
            raise AppError(
                ErrorCode.REVISION_CONFLICT, current_revision=locked[item.menu_id].revision
            )
    menus = (await session.scalars(select(Menu))).all()
    by_id = {menu.id: menu for menu in menus}
    parents = {str(menu.id): _parent_text(menu.parent_menu_id) for menu in menus}
    for item in items:
        parents[str(item.menu_id)] = _parent_text(item.parent_menu_id)
        if item.parent_menu_id is not None:
            parent = by_id.get(item.parent_menu_id)
            if parent is None or parent.audience != locked[item.menu_id].audience:
                raise AppError(ErrorCode.INPUT_INVALID)
    try:
        validate_menu_parents(parents)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    for item in items:
        await _validate_item(session, locked[item.menu_id], item)
    changed: list[tuple[Menu, MenuLayoutItem]] = []
    for item in items:
        menu = locked[item.menu_id]
        extras = await _extra_codes(session, menu.id)
        if _unchanged_item(menu, extras, item):
            continue
        changed.append((menu, item))
    if not changed:
        return MenuWriteResult(
            authorization_revision=revision.revision,
            audit_id=None,
            affected_count=0,
            menus=await _reads(session),
        )
    now = datetime.now(UTC)
    for menu, item in changed:
        menu.title = item.title
        menu.parent_menu_id = item.parent_menu_id
        menu.sort_order = item.sort_order
        menu.icon_key = item.icon_key
        menu.enabled = item.enabled
        menu.permission_match = item.permission_match
        menu.revision += 1
        menu.updated_at = now
        await session.execute(delete(MenuPermission).where(MenuPermission.menu_id == menu.id))
        for code in item.permission_codes:
            session.add(MenuPermission(menu_id=menu.id, permission_code=code))
    await session.flush()
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        target_id=changed[0][0].id,
        summary={"op": "layout", "count": len(changed)},
        affected_count=len(changed),
    )


async def delete_group(
    session: AsyncSession, *, actor_id: UUID, menu_id: UUID, expected_revision: int
) -> MenuWriteResult:
    revision = await _lock_global(session)
    await _require(session, actor_id, "admin.menu.update")
    menu = await session.scalar(select(Menu).where(Menu.id == menu_id).with_for_update())
    if menu is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if menu.revision != expected_revision:
        raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=menu.revision)
    if menu.route_key is not None or published_page(menu.code) is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    child = await session.scalar(select(Menu.id).where(Menu.parent_menu_id == menu.id))
    if child is not None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    await session.execute(delete(MenuPermission).where(MenuPermission.menu_id == menu.id))
    await session.delete(menu)
    await session.flush()
    return await _audit(
        session,
        actor_id=actor_id,
        revision=revision,
        target_id=menu_id,
        summary={"op": "group_deleted", "code": menu.code},
        affected_count=1,
    )


async def preview_navigation(
    session: AsyncSession, *, actor_id: UUID, user_id: UUID, audience: Literal["client", "admin"]
) -> list[NavigationRead]:
    await _require(session, actor_id, "admin.menu.read")
    await _require(session, actor_id, "admin.user.read")
    user = await session.get(User, user_id)
    if user is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    graph = await load_graph(session, user.id)
    allowed = {code for code, _scope in allowed_pairs(graph, user.id)}
    return await project_navigation(session, audience=audience, allowed=allowed)


async def project_navigation(
    session: AsyncSession, *, audience: str, allowed: set[str]
) -> list[NavigationRead]:
    menus = (await session.scalars(select(Menu).where(Menu.audience == audience))).all()
    extras: dict[UUID, list[str]] = {}
    if menus:
        rows = (
            await session.execute(
                select(MenuPermission.menu_id, MenuPermission.permission_code).where(
                    MenuPermission.menu_id.in_([menu.id for menu in menus])
                )
            )
        ).all()
        for menu_id, code in rows:
            extras.setdefault(menu_id, []).append(code)
    projections = [
        MenuProjection(
            menu_id=str(menu.id),
            code=menu.code,
            route_key=menu.route_key,
            title=menu.title,
            parent_id=_parent_text(menu.parent_menu_id),
            sort_order=menu.sort_order,
            enabled=menu.enabled,
            permission_match=menu.permission_match,
            floor=_floor(menu),
            extras=tuple(sorted(extras.get(menu.id, []))),
        )
        for menu in menus
    ]
    by_code = {menu.code: menu for menu in menus}
    published = {page.code: page for page in PUBLISHED_PAGES}
    return [
        NavigationRead(
            key=code,
            route_key=route_key,
            title=title,
            icon_key=by_code[code].icon_key,
            title_customized=code not in published or title != published[code].title,
            icon_customized=code not in published
            or by_code[code].icon_key != published[code].icon_key,
        )
        for code, route_key, title in visible_menu_entries(projections, allowed)
    ]


async def _validate_item(session: AsyncSession, menu: Menu, item: MenuLayoutItem) -> None:
    if item.icon_key is not None and item.icon_key not in PUBLISHED_ICONS:
        raise AppError(ErrorCode.INPUT_INVALID)
    if item.enabled and menu.route_key is not None and _floor(menu) == ():
        raise AppError(ErrorCode.INPUT_INVALID)
    if item.permission_codes:
        rows = (
            await session.execute(
                select(PermissionCatalog.code, PermissionCatalog.audience).where(
                    PermissionCatalog.code.in_(item.permission_codes),
                    PermissionCatalog.enabled.is_(True),
                )
            )
        ).all()
        found = {code: audience for code, audience in rows}
        if set(found) != set(item.permission_codes) or any(
            found[code] != menu.audience for code in item.permission_codes
        ):
            raise AppError(ErrorCode.INPUT_INVALID)


def _floor(menu: Menu) -> tuple[str, ...]:
    if menu.route_key is None:
        return ()
    page = published_route(menu.audience, menu.route_key)
    if page is None:
        return ()
    return page.floor


def _unchanged_item(menu: Menu, extras: set[str], item: MenuLayoutItem) -> bool:
    return (
        menu.title == item.title
        and menu.parent_menu_id == item.parent_menu_id
        and menu.sort_order == item.sort_order
        and menu.icon_key == item.icon_key
        and menu.enabled == item.enabled
        and menu.permission_match == item.permission_match
        and extras == set(item.permission_codes)
    )


async def _extra_codes(session: AsyncSession, menu_id: UUID) -> set[str]:
    return set(
        (
            await session.scalars(
                select(MenuPermission.permission_code).where(MenuPermission.menu_id == menu_id)
            )
        ).all()
    )


async def _parent_map(session: AsyncSession) -> dict[str, str | None]:
    rows = (await session.execute(select(Menu.id, Menu.parent_menu_id))).all()
    return {str(menu_id): _parent_text(parent_id) for menu_id, parent_id in rows}


def _parent_text(parent_id: UUID | None) -> str | None:
    return None if parent_id is None else str(parent_id)


async def _reads(session: AsyncSession) -> list[MenuRead]:
    menus = (
        await session.scalars(select(Menu).order_by(Menu.audience, Menu.sort_order, Menu.code))
    ).all()
    return [await _menu_read(session, menu) for menu in menus]


async def _menu_read(session: AsyncSession, menu: Menu) -> MenuRead:
    audience: Literal["client", "admin"] = "admin" if menu.audience == "admin" else "client"
    match: Literal["all", "any"] = "any" if menu.permission_match == "any" else "all"
    return MenuRead(
        id=menu.id,
        code=menu.code,
        audience=audience,
        route_key=menu.route_key,
        component_key=menu.component_key,
        parent_menu_id=menu.parent_menu_id,
        title=menu.title,
        icon_key=menu.icon_key,
        sort_order=menu.sort_order,
        permission_match=match,
        enabled=menu.enabled,
        floor=list(_floor(menu)),
        permission_codes=sorted(await _extra_codes(session, menu.id)),
        revision=menu.revision,
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


async def _audit(
    session: AsyncSession,
    *,
    actor_id: UUID,
    revision: AuthorizationRevision,
    target_id: UUID,
    summary: dict[str, object],
    affected_count: int,
) -> MenuWriteResult:
    revision.revision += 1
    request_id, operation_id = current_correlation()
    audit = AdminAuditEvent(
        action="menu.updated",
        actor="authenticated-admin",
        actor_user_id=actor_id,
        audience="admin",
        permission_code="admin.menu.update",
        target_type="menu",
        target_id=target_id,
        target_user_id=None,
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
    return MenuWriteResult(
        authorization_revision=revision.revision,
        audit_id=audit.id,
        affected_count=affected_count,
        menus=await _reads(session),
    )
