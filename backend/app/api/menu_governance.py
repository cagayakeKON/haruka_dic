"""Admin menu catalog, layout, and account preview routes."""

from uuid import UUID

from fastapi import APIRouter, Request

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_session_csrf
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.menu_governance import (
    MenuCatalogRead,
    MenuDelete,
    MenuGroupCreate,
    MenuLayoutUpdate,
    MenuPreviewRead,
    MenuPreviewRequest,
    MenuRead,
    MenuWriteResult,
)
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.services import menu_governance

router = APIRouter(prefix="/api/v1", tags=["menu-governance"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)


async def _admin_write(request: Request) -> tuple[Runtime, ScopeContext]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin")
    await require_session_csrf(request, runtime, scope)
    return runtime, scope


@router.get(
    "/admin/menus",
    operation_id="list_admin_menus",
    response_model=SuccessResponse[list[MenuRead]],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.menu.read"]},
)
async def list_admin_menus(request: Request) -> SuccessResponse[list[MenuRead]]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.menu.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        menus = await menu_governance.list_menus(session, actor_id=scope.user_id)
    return SuccessResponse[list[MenuRead]](
        data=menus, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/menu-catalog",
    operation_id="get_admin_menu_catalog",
    response_model=SuccessResponse[MenuCatalogRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.menu.read"]},
)
async def get_admin_menu_catalog(request: Request) -> SuccessResponse[MenuCatalogRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.menu.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        catalog = await menu_governance.read_catalog(session, actor_id=scope.user_id)
    return SuccessResponse[MenuCatalogRead](
        data=catalog, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/menus",
    operation_id="create_admin_menu_group",
    response_model=SuccessResponse[MenuWriteResult],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.menu.update"]},
)
async def create_admin_menu_group(
    body: MenuGroupCreate, request: Request
) -> SuccessResponse[MenuWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        created = await menu_governance.create_group(session, actor_id=scope.user_id, command=body)
    return SuccessResponse[MenuWriteResult](
        data=created, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/menus/layout",
    operation_id="replace_admin_menu_layout",
    response_model=SuccessResponse[MenuWriteResult],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.menu.update"]},
)
async def replace_admin_menu_layout(
    body: MenuLayoutUpdate, request: Request
) -> SuccessResponse[MenuWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await menu_governance.replace_layout(
            session, actor_id=scope.user_id, items=tuple(body.items)
        )
    return SuccessResponse[MenuWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/menus/preview",
    operation_id="preview_admin_menu_navigation",
    response_model=SuccessResponse[MenuPreviewRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.menu.read", "admin.user.read"]},
)
async def preview_admin_menu_navigation(
    body: MenuPreviewRequest, request: Request
) -> SuccessResponse[MenuPreviewRead]:
    runtime = require_runtime(request)
    scope = await require_scope(
        request, audience="admin", permissions=("admin.menu.read", "admin.user.read")
    )
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        navigation = await menu_governance.preview_navigation(
            session, actor_id=scope.user_id, user_id=body.user_id, audience=body.audience
        )
    return SuccessResponse[MenuPreviewRead](
        data=MenuPreviewRead(navigation=navigation),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.post(
    "/admin/menus/{menu_id}/deletion",
    operation_id="delete_admin_menu_group",
    response_model=SuccessResponse[MenuWriteResult],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.menu.update"]},
)
async def delete_admin_menu_group(
    menu_id: UUID, body: MenuDelete, request: Request
) -> SuccessResponse[MenuWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        deleted = await menu_governance.delete_group(
            session,
            actor_id=scope.user_id,
            menu_id=menu_id,
            expected_revision=body.expected_revision,
        )
    return SuccessResponse[MenuWriteResult](
        data=deleted, meta=ResponseMeta(request_id=get_request_id(request))
    )
