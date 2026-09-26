"""current slice published novel, prepared WordCard resolve, and own collection routes."""

from uuid import UUID

from fastapi import APIRouter, Header, Query, Request, Response

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_session_csrf
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.schemas.learning_reference import (
    CollectionCreate,
    CollectionRead,
    ExplanationResolveRead,
    ExplanationResolveRequest,
    MaterialSummary,
    NovelChapterRead,
)
from app.schemas.responses import PageMeta, PageResponse, ResponseMeta, SuccessResponse
from app.services import learning_reference
from app.services.auth_crypto import AuthCrypto

router = APIRouter(prefix="/api/v1", tags=["learning-reference"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)


@router.get(
    "/materials",
    operation_id="list_materials",
    response_model=PageResponse[MaterialSummary],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.list"]},
)
async def materials(
    request: Request, limit: int = Query(default=20, ge=1, le=100), cursor: str | None = None
) -> PageResponse[MaterialSummary]:
    scope = await require_scope(request, audience="client", permissions=("client.material.list",))
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        items, next_cursor = await learning_reference.list_materials(
            session, scope, limit=limit, cursor=cursor
        )
    return PageResponse[MaterialSummary](
        data=items,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )


@router.get(
    "/novels/{material_id}/revisions/{revision_id}/chapters/{node_id}",
    operation_id="get_novel_chapter",
    response_model=SuccessResponse[NovelChapterRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.material.read"]},
)
async def novel_chapter(
    request: Request, material_id: UUID, revision_id: UUID, node_id: UUID
) -> SuccessResponse[NovelChapterRead]:
    scope = await require_scope(request, audience="client", permissions=("client.material.read",))
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        result = await learning_reference.get_novel_chapter(
            session,
            scope,
            instance_id=runtime.settings.instance_id,
            material_id=material_id,
            revision_id=revision_id,
            node_id=node_id,
        )
    return SuccessResponse[NovelChapterRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/explanations/resolve",
    operation_id="resolve_explanations",
    response_model=SuccessResponse[ExplanationResolveRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.ai.explain", "client.material.read"]},
)
async def explanation_resolve(
    request: Request, payload: ExplanationResolveRequest
) -> SuccessResponse[ExplanationResolveRead]:
    scope = await require_scope(
        request, audience="client", permissions=("client.ai.explain", "client.material.read")
    )
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        result = await learning_reference.resolve_explanations(
            session, scope, instance_id=runtime.settings.instance_id, payload=payload
        )
    return SuccessResponse[ExplanationResolveRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/collections",
    operation_id="create_collection",
    status_code=201,
    response_model=SuccessResponse[CollectionRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.collection.create", "client.material.read"]},
)
async def collection_create(
    request: Request,
    response: Response,
    payload: CollectionCreate,
    idempotency_key: str = Header(min_length=1, max_length=128),
) -> SuccessResponse[CollectionRead]:
    scope = await require_scope(
        request, audience="client", permissions=("client.collection.create", "client.material.read")
    )
    runtime = require_runtime(request)
    if scope.transport == "web":
        await require_session_csrf(request, runtime, scope)
    elif (
        request.headers.get("origin")
        or request.headers.get("cookie")
        or request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        != "application/json"
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    key_digest = AuthCrypto.from_settings(runtime.settings).digest(
        "collection-idempotency", idempotency_key
    )
    async with runtime.resources.database.sessions() as session:
        result, status = await learning_reference.create_collection(
            session,
            scope,
            instance_id=runtime.settings.instance_id,
            payload=payload,
            key=idempotency_key,
            key_digest=key_digest,
            operation_id=getattr(request.state, "operation_id", None) or get_request_id(request),
        )
    response.status_code = status
    return SuccessResponse[CollectionRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/collections",
    operation_id="list_collections",
    response_model=PageResponse[CollectionRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.collection.read"]},
)
async def collections(
    request: Request, limit: int = Query(default=20, ge=1, le=100), cursor: str | None = None
) -> PageResponse[CollectionRead]:
    scope = await require_scope(request, audience="client", permissions=("client.collection.read",))
    runtime = require_runtime(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        items, next_cursor = await learning_reference.list_collections(
            session, scope, limit=limit, cursor=cursor
        )
    return PageResponse[CollectionRead](
        data=items,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )
