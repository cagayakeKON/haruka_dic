"""Authenticated cache validation registration boundary."""

from datetime import UTC, datetime

from fastapi import APIRouter, Request

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_authenticated_native_write, require_session_csrf
from app.schemas.client_cache import (
    CacheAuthzVersion,
    CacheValidationRequest,
    CacheValidationScope,
    ClientCacheValidation,
)
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.services.client_cache import CLIENT_CACHE_REGISTRY

router = APIRouter(prefix="/api/v1", tags=["client-cache"])


@router.post(
    "/me/cache/validate",
    operation_id="validate_client_cache",
    response_model=SuccessResponse[ClientCacheValidation],
    responses=error_responses(400, 401, 403, 413, 415, 422, 429, 500, 503),
    openapi_extra={"x-haruka-permissions": []},
)
async def validate_client_cache(
    request: Request, payload: CacheValidationRequest
) -> SuccessResponse[ClientCacheValidation]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client")
    if scope.transport == "web":
        await require_session_csrf(request, runtime, scope)
    else:
        require_authenticated_native_write(request)
    results = await CLIENT_CACHE_REGISTRY.validate(scope, payload.items)
    return SuccessResponse[ClientCacheValidation](
        data=ClientCacheValidation(
            protocol_version=payload.protocol_version,
            server_time=datetime.now(UTC),
            scope=CacheValidationScope(
                instance_id=runtime.settings.instance_id,
                user_id=scope.user_id,
                audience=scope.audience,
                session_ref=scope.session_id,
                security_epoch=scope.security_epoch,
                authz_version=CacheAuthzVersion(
                    user=scope.user_authz_version, policy=scope.policy_authz_version
                ),
            ),
            items=results,
        ),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )
