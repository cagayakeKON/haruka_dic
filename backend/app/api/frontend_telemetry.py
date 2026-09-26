"""Authenticated and anonymous Flutter telemetry ingestion."""

from typing import cast

from fastapi import APIRouter, Request
from pydantic import ValidationError

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import (
    require_authenticated_native_write,
    require_public_write,
    require_session_csrf,
)
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.frontend_telemetry import (
    TelemetryBatchDocumented,
    TelemetryBatchRead,
    TelemetryBatchRequest,
)
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.services.frontend_telemetry import receive

router = APIRouter(prefix="/api/v1", tags=["frontend-telemetry"])
COMMON = error_responses(400, 401, 403, 413, 415, 422, 429, 500, 503)
_AUTHENTICATED_BYTES = 128 * 1024
_ANONYMOUS_BYTES = 16 * 1024


def _inline_local_definitions(schema: dict[str, object]) -> dict[str, object]:
    definitions_value: object = schema.pop("$defs", {})
    if not isinstance(definitions_value, dict):
        raise RuntimeError("invalid telemetry OpenAPI definitions")
    definitions = cast("dict[str, object]", definitions_value)

    def expand(value: object) -> object:
        if isinstance(value, list):
            return [expand(item) for item in cast("list[object]", value)]
        if not isinstance(value, dict):
            return value
        mapping = cast("dict[str, object]", value)
        reference = mapping.get("$ref")
        if isinstance(reference, str) and reference.startswith("#/$defs/"):
            name = reference.removeprefix("#/$defs/")
            definition = definitions.get(name)
            if not isinstance(definition, dict):
                raise RuntimeError("unknown telemetry OpenAPI definition")
            return expand(cast("dict[str, object]", definition))
        return {key: expand(item) for key, item in mapping.items()}

    expanded = expand(schema)
    if not isinstance(expanded, dict):
        raise RuntimeError("invalid telemetry OpenAPI schema")
    return cast("dict[str, object]", expanded)


_BODY_SCHEMA = {
    "requestBody": {
        "required": True,
        "content": {
            "application/json": {
                "schema": _inline_local_definitions(TelemetryBatchDocumented.model_json_schema())
            }
        },
    }
}


async def _batch(request: Request, *, anonymous: bool) -> TelemetryBatchRequest:
    maximum = _ANONYMOUS_BYTES if anonymous else _AUTHENTICATED_BYTES
    length = request.headers.get("content-length")
    if length is not None:
        try:
            if int(length) > maximum:
                raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
        except ValueError:
            raise AppError(ErrorCode.INPUT_INVALID) from None
    body = bytearray()
    async for chunk in request.stream():
        if len(chunk) > maximum - len(body):
            raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
        body.extend(chunk)
    try:
        batch = TelemetryBatchRequest.model_validate_json(bytes(body))
    except ValidationError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    if anonymous and len(batch.events) > 5:
        raise AppError(ErrorCode.INPUT_INVALID)
    return batch


def _address(request: Request) -> str:
    return request.client.host if request.client is not None else "unknown"


async def _authenticated(request: Request, *, audience: str) -> SuccessResponse[TelemetryBatchRead]:
    selected = "client" if audience == "client" else "admin"
    runtime = require_runtime(request)
    permission = "client.login" if selected == "client" else "admin.login"
    scope: ScopeContext = await require_scope(request, audience=selected, permissions=(permission,))
    if scope.transport == "web":
        await require_session_csrf(request, runtime, scope)
    else:
        require_authenticated_native_write(request)
    batch = await _batch(request, anonymous=False)
    result = await receive(
        runtime,
        batch,
        scope=scope,
        anonymous=False,
        web_transport=scope.transport == "web",
        address=_address(request),
        ingest_request_id=get_request_id(request),
    )
    return SuccessResponse[TelemetryBatchRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/frontend-logs",
    operation_id="receive_client_telemetry",
    response_model=SuccessResponse[TelemetryBatchRead],
    responses=COMMON,
    openapi_extra={**_BODY_SCHEMA, "x-haruka-permissions": ["client.login"]},
)
async def client_frontend_logs(request: Request) -> SuccessResponse[TelemetryBatchRead]:
    return await _authenticated(request, audience="client")


@router.post(
    "/admin/frontend-logs",
    operation_id="receive_admin_telemetry",
    response_model=SuccessResponse[TelemetryBatchRead],
    responses=COMMON,
    openapi_extra={**_BODY_SCHEMA, "x-haruka-permissions": ["admin.login"]},
)
async def admin_frontend_logs(request: Request) -> SuccessResponse[TelemetryBatchRead]:
    return await _authenticated(request, audience="admin")


@router.post(
    "/frontend-logs/anonymous",
    operation_id="receive_anonymous_telemetry",
    response_model=SuccessResponse[TelemetryBatchRead],
    responses=COMMON,
    openapi_extra=_BODY_SCHEMA,
)
async def anonymous_frontend_logs(request: Request) -> SuccessResponse[TelemetryBatchRead]:
    runtime = require_runtime(request)
    require_public_write(request, runtime)
    batch = await _batch(request, anonymous=True)
    result = await receive(
        runtime,
        batch,
        scope=None,
        anonymous=True,
        web_transport=bool(request.headers.get("origin")),
        address=_address(request),
        ingest_request_id=get_request_id(request),
    )
    return SuccessResponse[TelemetryBatchRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )
