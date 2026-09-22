"""Pure response construction and OpenAPI metadata, without exception registration."""

from uuid import UUID

from starlette.requests import Request
from starlette.responses import JSONResponse

from app.contracts.errors import ERRORS, ErrorCode
from app.schemas.responses import (
    ApiError,
    ErrorResponse,
    FieldError,
    ResponseMeta,
    RevisionConflictDetails,
)


def get_request_id(request: Request) -> UUID:
    value: object = request.state.request_id
    if not isinstance(value, UUID):
        raise RuntimeError("request context is not installed")
    return value


def error_responses(*statuses: int) -> dict[int | str, dict[str, object]]:
    return {status: {"model": ErrorResponse} for status in statuses}


def error_response(
    request: Request,
    code: ErrorCode,
    *,
    field_errors: list[FieldError] | None = None,
    revision: int | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    definition = ERRORS[code]
    envelope = ErrorResponse(
        error=ApiError(
            code=code,
            message=definition.message,
            field_errors=field_errors or [],
            details=RevisionConflictDetails(current_revision=revision)
            if revision is not None
            else None,
        ),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )
    return JSONResponse(
        status_code=definition.http_status,
        content=envelope.model_dump(mode="json"),
        headers={"Content-Language": "zh-Hans", "Cache-Control": "no-store", **(headers or {})},
    )
