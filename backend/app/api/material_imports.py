"""Authorized source intent, temporary capability and owned metadata routes."""

import asyncio
from uuid import UUID, uuid4

from fastapi import APIRouter, Header, Query, Request, Response

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_session_csrf
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.material_sources import (
    FORMAT_MAX_BYTES,
    FORMATS,
    MAX_SOURCE_BYTES,
    QUOTA_BYTES,
    UPLOAD_TTL_SECONDS,
)
from app.domain.scope import ScopeContext
from app.models.learning_reference import Material
from app.models.material_imports import MaterialImport
from app.repositories import material_imports as repository
from app.schemas.material_imports import (
    MaterialImportCapabilitiesRead,
    MaterialImportCreate,
    MaterialImportRead,
    MaterialLanguage,
    MaterialMetadataRead,
    MaterialTitlePatch,
    MaterialType,
    UploadComplete,
)
from app.schemas.responses import PageMeta, PageResponse, ResponseMeta, SuccessResponse
from app.services import material_imports as service

router = APIRouter(prefix="/api/v1", tags=["materials"])
COMMON = error_responses(400, 401, 403, 404, 409, 410, 413, 415, 422, 429, 500, 503)


def success[T](request: Request, value: T) -> SuccessResponse[T]:
    return SuccessResponse[T](data=value, meta=ResponseMeta(request_id=get_request_id(request)))


async def context(request: Request, code: str, *, write: bool = False) -> ScopeContext:
    scope = await require_scope(request, audience="client", permissions=(code,))
    if write:
        if scope.transport == "web":
            await require_session_csrf(request, require_runtime(request), scope)
        elif (
            request.headers.get("origin")
            or request.headers.get("cookie")
            or request.headers.get("content-type", "").split(";", 1)[0] != "application/json"
        ):
            raise AppError(ErrorCode.SESSION_INVALID)
    return scope


@router.get(
    "/material-import-capabilities",
    operation_id="get_material_import_capabilities",
    response_model=SuccessResponse[MaterialImportCapabilitiesRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.import"]},
)
async def capabilities(request: Request):
    scope = await context(request, "client.material.import")
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        await service.verify(session, scope, ("client.material.import",), lock=True)
        state = await service.capacity(session, scope)
        value = MaterialImportCapabilitiesRead.model_validate(
            {
                "capabilities": [
                    {
                        "material_type": key,
                        "formats": list(formats),
                        "languages": ["ja", "en"],
                        "max_size_bytes": MAX_SOURCE_BYTES,
                        "format_max_size_bytes": {
                            format: FORMAT_MAX_BYTES[format] for format in formats
                        },
                    }
                    for key, formats in FORMATS.items()
                ],
                "quota_bytes": QUOTA_BYTES,
                "used_bytes": state.used_bytes,
                "reserved_bytes": state.reserved_bytes,
                "upload_ttl_seconds": UPLOAD_TTL_SECONDS,
            }
        )
    return success(request, value)


@router.post(
    "/material-imports",
    operation_id="create_material_import",
    status_code=201,
    response_model=SuccessResponse[MaterialImportRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.import"]},
)
async def create(
    request: Request,
    payload: MaterialImportCreate,
    idempotency_key: str = Header(min_length=1, max_length=128),
):
    scope = await context(request, "client.material.import", write=True)
    value = await service.create_import(
        require_runtime(request),
        scope,
        payload,
        idempotency_key,
        getattr(request.state, "operation_id", None) or uuid4(),
        get_request_id(request),
    )
    return success(request, value)


@router.get(
    "/material-imports/{import_id}",
    operation_id="get_material_import",
    response_model=SuccessResponse[MaterialImportRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.import"]},
)
async def intent(request: Request, import_id: UUID):
    scope = await context(request, "client.material.import")
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        row = await repository.owned(session, scope, MaterialImport, import_id)
        return success(request, await service.read_intent(session, runtime, scope, row))


@router.delete(
    "/material-imports/{import_id}",
    operation_id="cancel_material_import",
    status_code=204,
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.import"]},
)
async def cancel(
    request: Request, import_id: UUID, expected_revision: int = Query(ge=1)
) -> Response:
    scope = await context(request, "client.material.import", write=True)
    await service.cancel_import(require_runtime(request), scope, import_id, expected_revision)
    return Response(status_code=204)


@router.put(
    "/uploads/{upload_id}/content",
    operation_id="put_material_staging_content",
    status_code=204,
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.import"]},
)
async def upload(
    request: Request,
    upload_id: UUID,
    x_haruka_upload_capability: str = Header(min_length=1, max_length=1024),
) -> Response:
    if request.headers.get("cookie") or request.headers.get("authorization"):
        raise AppError(ErrorCode.SESSION_INVALID)
    runtime = require_runtime(request)
    scope = service.capability_scope(runtime, upload_id, x_haruka_upload_capability)
    maximum = await service.upload_allowance(runtime, scope, upload_id)
    if request.headers.get("content-length") is not None:
        try:
            length = int(request.headers["content-length"])
        except ValueError:
            raise AppError(ErrorCode.INPUT_INVALID) from None
        if length != maximum:
            raise AppError(ErrorCode.INPUT_INVALID)
    raw = bytearray()
    try:
        async with asyncio.timeout(120):
            async for chunk in request.stream():
                if len(raw) + len(chunk) > maximum:
                    raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
                raw.extend(chunk)
    except TimeoutError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    await service.upload_content(runtime, scope, upload_id, bytes(raw))
    return Response(status_code=204)


@router.post(
    "/uploads/{upload_id}/complete",
    operation_id="complete_material_upload",
    status_code=202,
    response_model=SuccessResponse[MaterialImportRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.import"]},
)
async def complete(
    request: Request,
    upload_id: UUID,
    payload: UploadComplete,
    idempotency_key: str = Header(min_length=1, max_length=128),
):
    scope = await context(request, "client.material.import", write=True)
    return success(
        request,
        await service.complete_upload(
            require_runtime(request),
            scope,
            upload_id,
            payload.expected_revision,
            getattr(request.state, "operation_id", None) or uuid4(),
            get_request_id(request),
        ),
    )


@router.get(
    "/materials",
    operation_id="list_materials",
    response_model=PageResponse[MaterialMetadataRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.list"]},
)
async def materials(
    request: Request,
    limit: int = Query(default=20, ge=1, le=100),
    cursor: UUID | None = None,
    material_type: MaterialType | None = None,
    language: MaterialLanguage | None = None,
    search: str | None = Query(default=None, max_length=200),
):
    scope = await context(request, "client.material.list")
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        rows = await repository.material_page(
            session,
            scope,
            limit=limit,
            cursor=cursor,
            material_type=material_type,
            language=language,
            search=search,
        )
        data = [await service.metadata(session, scope, row) for row in rows[:limit]]
    return PageResponse[MaterialMetadataRead](
        data=data,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=str(rows[limit - 1].id) if len(rows) > limit else None,
            has_more=len(rows) > limit,
        ),
    )


@router.get(
    "/materials/{material_id}",
    operation_id="get_material_metadata",
    response_model=SuccessResponse[MaterialMetadataRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.read"]},
)
async def material(request: Request, material_id: UUID):
    scope = await context(request, "client.material.read")
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        row = await repository.owned(session, scope, Material, material_id)
        return success(request, await service.metadata(session, scope, row))


@router.patch(
    "/materials/{material_id}",
    operation_id="update_material_title",
    response_model=SuccessResponse[MaterialMetadataRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.update"]},
)
async def update(request: Request, material_id: UUID, payload: MaterialTitlePatch):
    scope = await context(request, "client.material.update", write=True)
    value = await service.change_material(
        require_runtime(request), scope, material_id, payload.expected_revision, title=payload.title
    )
    return success(request, value)


@router.delete(
    "/materials/{material_id}",
    operation_id="delete_material",
    status_code=204,
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.delete"]},
)
async def delete(
    request: Request, material_id: UUID, expected_revision: int = Query(ge=1)
) -> Response:
    scope = await context(request, "client.material.delete", write=True)
    await service.change_material(
        require_runtime(request), scope, material_id, expected_revision, title=None
    )
    return Response(status_code=204)
