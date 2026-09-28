"""Owner profile, study-profile and settings routes."""

import logging
from collections.abc import Awaitable, Callable

from fastapi import APIRouter, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_authenticated_native_write, require_session_csrf
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import current_log_context
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.language_capabilities import LanguageCapabilitiesRead
from app.schemas.profile import (
    ProfileRead,
    ProfileUpdate,
    SettingsRead,
    SettingsUpdate,
    StudyProfileRead,
    StudyProfileUpdate,
)
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.services import profile_settings
from app.services.language_capabilities import read_catalogue

router = APIRouter(prefix="/api/v1", tags=["profile"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)
logger = logging.getLogger(__name__)


@router.get(
    "/language-capabilities",
    operation_id="get_language_capabilities",
    response_model=SuccessResponse[LanguageCapabilitiesRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": []},
)
async def language_capabilities(request: Request) -> SuccessResponse[LanguageCapabilitiesRead]:
    await require_scope(request, audience="client")
    return SuccessResponse[LanguageCapabilitiesRead](
        data=read_catalogue(), meta=ResponseMeta(request_id=get_request_id(request))
    )


async def _write_scope(request: Request) -> tuple[Runtime, ScopeContext]:
    runtime = require_runtime(request)
    scope = await require_scope(
        request, audience="client", permissions=("client.profile.read", "client.profile.update")
    )
    if scope.transport == "web":
        await require_session_csrf(request, runtime, scope)
    else:
        require_authenticated_native_write(request)
    return runtime, scope


@router.get(
    "/users/me/profile",
    operation_id="get_my_profile",
    response_model=SuccessResponse[ProfileRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.profile.read"]},
)
async def my_profile(request: Request) -> SuccessResponse[ProfileRead]:
    return SuccessResponse[ProfileRead](
        data=await _read(request, profile_settings.read_profile),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.patch(
    "/users/me/profile",
    operation_id="update_my_profile",
    response_model=SuccessResponse[ProfileRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.profile.read", "client.profile.update"]},
)
async def update_my_profile(
    request: Request, payload: ProfileUpdate
) -> SuccessResponse[ProfileRead]:
    runtime, scope = await _write_scope(request)
    result = await _update(runtime, scope, profile_settings.update_profile, payload)
    logger.info(
        "profile.updated",
        extra={**current_log_context(), "field_count": len(payload.fields.model_fields_set)},
    )
    return SuccessResponse[ProfileRead](
        data=result,
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/users/me/study-profile",
    operation_id="get_my_study_profile",
    response_model=SuccessResponse[StudyProfileRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.profile.read"]},
)
async def my_study_profile(request: Request) -> SuccessResponse[StudyProfileRead]:
    return SuccessResponse[StudyProfileRead](
        data=await _read(request, profile_settings.read_study_profile),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.patch(
    "/users/me/study-profile",
    operation_id="update_my_study_profile",
    response_model=SuccessResponse[StudyProfileRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.profile.read", "client.profile.update"]},
)
async def update_my_study_profile(
    request: Request, payload: StudyProfileUpdate
) -> SuccessResponse[StudyProfileRead]:
    runtime, scope = await _write_scope(request)
    result = await _update(runtime, scope, profile_settings.update_study_profile, payload)
    logger.info(
        "study_profile.updated",
        extra={**current_log_context(), "field_count": len(payload.fields.model_fields_set)},
    )
    return SuccessResponse[StudyProfileRead](
        data=result,
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/users/me/settings",
    operation_id="get_my_settings",
    response_model=SuccessResponse[SettingsRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.profile.read"]},
)
async def my_settings(request: Request) -> SuccessResponse[SettingsRead]:
    return SuccessResponse[SettingsRead](
        data=await _read(request, profile_settings.read_settings),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.patch(
    "/users/me/settings",
    operation_id="update_my_settings",
    response_model=SuccessResponse[SettingsRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.profile.read", "client.profile.update"]},
)
async def update_my_settings(
    request: Request, payload: SettingsUpdate
) -> SuccessResponse[SettingsRead]:
    runtime, scope = await _write_scope(request)
    result = await _update(runtime, scope, profile_settings.update_settings, payload)
    logger.info(
        "settings.updated",
        extra={**current_log_context(), "field_count": len(payload.fields.model_fields_set)},
    )
    return SuccessResponse[SettingsRead](
        data=result,
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


async def _read[T](
    request: Request, reader: Callable[[AsyncSession, ScopeContext], Awaitable[T]]
) -> T:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client", permissions=("client.profile.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        return await reader(session, scope)


async def _update[T, P](
    runtime: Runtime,
    scope: ScopeContext,
    writer: Callable[[AsyncSession, ScopeContext, P], Awaitable[T]],
    payload: P,
) -> T:
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        return await writer(session, scope, payload)
