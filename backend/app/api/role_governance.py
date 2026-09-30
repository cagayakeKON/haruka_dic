"""Admin role, permission catalog, and grant-ceiling routes."""

import re
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.governance_writes import GOVERNANCE_WRITE_HEADERS, governance_write
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_session_csrf
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.responses import PageMeta, PageResponse, ResponseMeta, SuccessResponse
from app.schemas.role_governance import (
    AuthorizationWriteResult,
    GrantBoundariesUpdate,
    GrantBoundaryRead,
    PermissionCatalogRead,
    RoleCreate,
    RoleDelete,
    RoleEnabledUpdate,
    RoleGrantsUpdate,
    RoleInheritanceUpdate,
    RoleMetadataUpdate,
    RoleRead,
)
from app.services import role_governance

router = APIRouter(prefix="/api/v1", tags=["role-governance"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)
_CODE = re.compile(r"[a-z][a-z0-9_]{0,63}")


async def _admin_write(request: Request) -> tuple[Runtime, ScopeContext]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin")
    await require_session_csrf(request, runtime, scope)
    return runtime, scope


@router.get(
    "/admin/roles",
    operation_id="list_admin_roles",
    response_model=PageResponse[RoleRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.role.read"]},
)
async def list_admin_roles(
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    cursor: str | None = None,
) -> PageResponse[RoleRead]:
    if cursor is not None and _CODE.fullmatch(cursor) is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.role.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        roles, has_more = await role_governance.list_roles(
            session, actor_id=scope.user_id, limit=limit, after_code=cursor
        )
    next_cursor = roles[-1].code if has_more and roles else None
    return PageResponse[RoleRead](
        data=roles,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )


@router.post(
    "/admin/roles",
    operation_id="create_admin_role",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.role.create"]},
)
async def create_admin_role(
    request: Request, payload: RoleCreate
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        created = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.create_role(
                session,
                actor_id=scope.user_id,
                code=payload.code,
                name=payload.name,
                description=payload.description,
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=created, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/roles/{role_id}",
    operation_id="get_admin_role",
    response_model=SuccessResponse[RoleRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.role.read"]},
)
async def get_admin_role(request: Request, role_id: UUID) -> SuccessResponse[RoleRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.role.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        role = await role_governance.read_role(session, actor_id=scope.user_id, role_id=role_id)
    return SuccessResponse[RoleRead](
        data=role, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.patch(
    "/admin/roles/{role_id}",
    operation_id="update_admin_role",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.role.update"]},
)
async def update_admin_role(
    request: Request, role_id: UUID, payload: RoleMetadataUpdate
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.update_role_metadata(
                session,
                actor_id=scope.user_id,
                role_id=role_id,
                expected_revision=payload.expected_revision,
                name=payload.name,
                description=payload.description,
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/roles/{role_id}/enabled",
    operation_id="set_admin_role_enabled",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.role.update"]},
)
async def set_admin_role_enabled(
    request: Request, role_id: UUID, payload: RoleEnabledUpdate
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.set_role_enabled(
                session,
                actor_id=scope.user_id,
                role_id=role_id,
                expected_revision=payload.expected_revision,
                enabled=payload.enabled,
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/roles/{role_id}/grants",
    operation_id="replace_admin_role_grants",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={
        **GOVERNANCE_WRITE_HEADERS,
        "x-haruka-permissions": ["admin.role.permission.assign"],
    },
)
async def replace_admin_role_grants(
    request: Request, role_id: UUID, payload: RoleGrantsUpdate
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.replace_role_grants(
                session,
                actor_id=scope.user_id,
                role_id=role_id,
                expected_revision=payload.expected_revision,
                grants=tuple(
                    (item.permission_code, item.effect, item.data_scope) for item in payload.grants
                ),
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/roles/{role_id}/inheritance",
    operation_id="replace_admin_role_inheritance",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={
        **GOVERNANCE_WRITE_HEADERS,
        "x-haruka-permissions": ["admin.role.permission.assign"],
    },
)
async def replace_admin_role_inheritance(
    request: Request, role_id: UUID, payload: RoleInheritanceUpdate
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.replace_role_parents(
                session,
                actor_id=scope.user_id,
                role_id=role_id,
                expected_revision=payload.expected_revision,
                parent_role_ids=tuple(payload.parent_role_ids),
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/roles/{role_id}/deletion",
    operation_id="delete_admin_role",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.role.delete"]},
)
async def delete_admin_role(
    request: Request, role_id: UUID, payload: RoleDelete
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        deleted = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.delete_role(
                session,
                actor_id=scope.user_id,
                role_id=role_id,
                expected_revision=payload.expected_revision,
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=deleted, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/permissions",
    operation_id="list_admin_permissions",
    response_model=SuccessResponse[list[PermissionCatalogRead]],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.permission.read"]},
)
async def list_admin_permissions(
    request: Request,
) -> SuccessResponse[list[PermissionCatalogRead]]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.permission.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        permissions = await role_governance.list_permissions(session, actor_id=scope.user_id)
    return SuccessResponse[list[PermissionCatalogRead]](
        data=permissions, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/roles/{role_id}/grant-boundaries",
    operation_id="list_admin_grant_boundaries",
    response_model=SuccessResponse[list[GrantBoundaryRead]],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.grant_boundary.read"]},
)
async def list_admin_grant_boundaries(
    request: Request, role_id: UUID
) -> SuccessResponse[list[GrantBoundaryRead]]:
    runtime = require_runtime(request)
    scope = await require_scope(
        request, audience="admin", permissions=("admin.grant_boundary.read",)
    )
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        boundaries = await role_governance.read_grant_boundaries(
            session, actor_id=scope.user_id, role_id=role_id
        )
    return SuccessResponse[list[GrantBoundaryRead]](
        data=boundaries, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/roles/{role_id}/grant-boundaries",
    operation_id="replace_admin_grant_boundaries",
    response_model=SuccessResponse[AuthorizationWriteResult],
    responses=COMMON,
    openapi_extra={
        **GOVERNANCE_WRITE_HEADERS,
        "x-haruka-permissions": ["admin.grant_boundary.update"],
    },
)
async def replace_admin_grant_boundaries(
    request: Request, role_id: UUID, payload: GrantBoundariesUpdate
) -> SuccessResponse[AuthorizationWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AuthorizationWriteResult,
            lambda: role_governance.replace_grant_boundaries(
                session,
                actor_id=scope.user_id,
                role_id=role_id,
                expected_revision=payload.expected_revision,
                boundaries=tuple(payload.boundaries),
            ),
        )
    return SuccessResponse[AuthorizationWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )
