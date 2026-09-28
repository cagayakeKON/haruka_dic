"""Owner avatar intent, publish, private read and pointer delete."""

import logging
from collections.abc import Awaitable, Callable
from typing import Concatenate
from uuid import UUID

from fastapi import APIRouter, Request
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.responses import Response

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_authenticated_native_write, require_session_csrf
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import current_log_context
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.avatar import (
    AvatarDelete,
    AvatarUploadComplete,
    AvatarUploadIntentCreate,
    AvatarUploadIntentRead,
)
from app.schemas.profile import ProfileRead
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.services import avatar
from app.services.avatar_image import decode_image_base64

router = APIRouter(prefix="/api/v1", tags=["profile"])
logger = logging.getLogger(__name__)
ERRORS = error_responses(400, 401, 403, 404, 409, 413, 415, 422, 429, 500, 503)
_WRITE = ("client.profile.read", "client.profile.avatar.update")


async def _write_scope(request: Request) -> tuple[Runtime, ScopeContext]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client", permissions=_WRITE)
    if scope.transport == "web":
        await require_session_csrf(request, runtime, scope)
    else:
        require_authenticated_native_write(request)
    return runtime, scope


@router.post(
    "/users/me/avatar-upload-intents",
    operation_id="create_avatar_upload_intent",
    response_model=SuccessResponse[AvatarUploadIntentRead],
    responses=ERRORS,
    openapi_extra={"x-haruka-permissions": list(_WRITE)},
)
async def create_avatar_upload_intent(
    request: Request, payload: AvatarUploadIntentCreate
) -> SuccessResponse[AvatarUploadIntentRead]:
    runtime, scope = await _write_scope(request)
    return SuccessResponse[AvatarUploadIntentRead](
        data=await _call(runtime, avatar.create_intent, scope, payload),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.post(
    "/users/me/avatar-upload-intents/{intent_id}/complete",
    operation_id="complete_avatar_upload_intent",
    response_model=SuccessResponse[ProfileRead],
    responses=ERRORS,
    openapi_extra={"x-haruka-permissions": list(_WRITE)},
)
async def complete_avatar_upload_intent(
    request: Request, intent_id: UUID, payload: AvatarUploadComplete
) -> SuccessResponse[ProfileRead]:
    runtime, scope = await _write_scope(request)
    raw = decode_image_base64(payload.image_base64)
    result = await _call(
        runtime, avatar.complete_intent, scope, intent_id, payload.expected_revision, raw
    )
    if result.revision > payload.expected_revision:
        logger.info(
            "profile.avatar.updated",
            extra={**current_log_context(), "size_bucket": _size_bucket(len(raw))},
        )
    return SuccessResponse[ProfileRead](
        data=result,
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/users/me/avatar",
    operation_id="get_my_avatar",
    response_model=None,
    responses={200: {"content": {"image/jpeg": {}}}, **ERRORS},
    openapi_extra={"x-haruka-permissions": ["client.profile.read"]},
)
async def my_avatar(request: Request) -> Response:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client", permissions=("client.profile.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        content = await avatar.read_avatar(session, scope)
    return Response(
        content=content,
        media_type="image/jpeg",
        headers={
            "Cache-Control": "private, no-store",
            "Pragma": "no-cache",
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.delete(
    "/users/me/avatar",
    operation_id="delete_my_avatar",
    response_model=SuccessResponse[ProfileRead],
    responses=ERRORS,
    openapi_extra={"x-haruka-permissions": list(_WRITE)},
)
async def delete_my_avatar(request: Request, payload: AvatarDelete) -> SuccessResponse[ProfileRead]:
    runtime, scope = await _write_scope(request)
    result = await _call(runtime, avatar.delete_avatar, scope, payload.expected_revision)
    if result.revision > payload.expected_revision:
        logger.info("profile.avatar.deleted", extra=current_log_context())
    return SuccessResponse[ProfileRead](
        data=result,
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


async def _call[T, **P](
    runtime: Runtime,
    operation: Callable[Concatenate[AsyncSession, ScopeContext, P], Awaitable[T]],
    scope: ScopeContext,
    *args: P.args,
    **kwargs: P.kwargs,
) -> T:
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        return await operation(session, scope, *args, **kwargs)


def _size_bucket(size: int) -> str:
    if size <= 1024 * 1024:
        return "up_to_1mb"
    if size <= 3 * 1024 * 1024:
        return "up_to_3mb"
    return "up_to_5mb"
