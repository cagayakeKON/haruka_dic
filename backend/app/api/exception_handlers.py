"""Central exception mapping with input and framework-detail redaction."""

import logging
from collections.abc import Sequence
from typing import Literal

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError, ResponseValidationError
from pydantic import ValidationError
from starlette.exceptions import HTTPException
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.api.responses import error_response, get_request_id
from app.contracts.errors import FIELD_MESSAGES, ErrorCode, FieldErrorCode
from app.domain.errors import AppError
from app.schemas.responses import FieldError

logger = logging.getLogger(__name__)


async def handle_app_error(request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, AppError):
        return error_response(request, ErrorCode.INTERNAL_ERROR)
    return error_response(request, exc.code, revision=exc.current_revision)


def field_code(error_type: str) -> FieldErrorCode:
    if error_type == "missing":
        return FieldErrorCode.REQUIRED
    if error_type == "extra_forbidden":
        return FieldErrorCode.UNKNOWN_FIELD
    if error_type.endswith("_type"):
        return FieldErrorCode.TYPE
    if error_type in {"string_too_long", "too_long", "bytes_too_long"}:
        return FieldErrorCode.TOO_LONG
    if error_type in {"greater_than", "greater_than_equal", "less_than", "less_than_equal"}:
        return FieldErrorCode.OUT_OF_RANGE
    if error_type.endswith(("_parsing", "_pattern_mismatch")):
        return FieldErrorCode.FORMAT
    return FieldErrorCode.INVALID


async def handle_request_validation(request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, RequestValidationError):
        return error_response(request, ErrorCode.INTERNAL_ERROR)
    errors = exc.errors()
    if any(item["type"] == "json_invalid" for item in errors):
        return error_response(request, ErrorCode.BAD_REQUEST)
    fields: list[FieldError] = []
    for item in errors[:50]:
        code = field_code(str(item["type"]))
        source: Literal["body", "query", "path", "header", "cookie"] = "body"
        location: Sequence[object] = item.get("loc", ())
        if location:
            candidate: object = location[0]
            if candidate in ("query", "path", "header", "cookie"):
                if candidate == "query":
                    source = "query"
                elif candidate == "path":
                    source = "path"
                elif candidate == "header":
                    source = "header"
                else:
                    source = "cookie"
        # Foundation has no business input schema. Unknown loc/dict keys collapse
        # to the safe container. Business routes must register public paths explicitly.
        fields.append(FieldError(source=source, path=[], code=code, message=FIELD_MESSAGES[code]))
    return error_response(request, ErrorCode.INPUT_INVALID, field_errors=fields)


async def handle_http_error(request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, HTTPException):
        return error_response(request, ErrorCode.INTERNAL_ERROR)
    code = {
        400: ErrorCode.BAD_REQUEST,
        401: ErrorCode.AUTH_REQUIRED,
        403: ErrorCode.PERMISSION_DENIED,
        404: ErrorCode.RESOURCE_NOT_FOUND,
        405: ErrorCode.METHOD_NOT_ALLOWED,
        413: ErrorCode.PAYLOAD_TOO_LARGE,
        415: ErrorCode.MEDIA_TYPE_UNSUPPORTED,
        429: ErrorCode.RATE_LIMITED,
        503: ErrorCode.SERVICE_UNAVAILABLE,
    }.get(exc.status_code, ErrorCode.INTERNAL_ERROR)
    headers: dict[str, str] = {}
    # Only the router-generated method list is used by this slice. Arbitrary
    # exception headers and raw detail never cross the public error boundary.
    if exc.status_code == 405 and exc.headers:
        allow = next((v for k, v in exc.headers.items() if k.lower() == "allow"), "")
        methods = {part.strip() for part in allow.split(",")}
        if methods and methods <= {"GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"}:
            headers["Allow"] = ", ".join(sorted(methods))
    return error_response(request, code, headers=headers)


async def handle_internal_error(request: Request, exc: Exception) -> JSONResponse:
    logger.error("http.failed", exc_info=exc, extra={"request_id": get_request_id(request)})
    return error_response(request, ErrorCode.INTERNAL_ERROR)


def install_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, handle_app_error)
    app.add_exception_handler(RequestValidationError, handle_request_validation)
    app.add_exception_handler(HTTPException, handle_http_error)
    app.add_exception_handler(ResponseValidationError, handle_internal_error)
    app.add_exception_handler(ValidationError, handle_internal_error)
