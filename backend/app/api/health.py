"""Public process probes; these endpoints never expose configuration or private data."""

from fastapi import APIRouter, Request

from app.api.responses import error_responses, get_request_id
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.schemas.health import HealthRead
from app.schemas.responses import ResponseMeta, SuccessResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get(
    "/live",
    operation_id="get_liveness",
    response_model=SuccessResponse[HealthRead],
    responses=error_responses(500, 503),
    openapi_extra={"x-haruka-access": "public-health"},
)
async def liveness(request: Request) -> SuccessResponse[HealthRead]:
    runtime: object = getattr(request.app.state, "runtime", None)
    if not isinstance(runtime, Runtime) or not runtime.active:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return SuccessResponse[HealthRead](
        data=HealthRead(), meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/ready",
    operation_id="get_readiness",
    response_model=SuccessResponse[HealthRead],
    responses=error_responses(500, 503),
    openapi_extra={"x-haruka-access": "public-health"},
)
async def readiness(request: Request) -> SuccessResponse[HealthRead]:
    runtime: object = getattr(request.app.state, "runtime", None)
    if not isinstance(runtime, Runtime) or not await runtime.check_readiness():
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return SuccessResponse[HealthRead](
        data=HealthRead(), meta=ResponseMeta(request_id=get_request_id(request))
    )
