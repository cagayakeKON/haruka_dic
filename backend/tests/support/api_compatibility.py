"""Pydantic authority for cross-language samples, without production sample routes."""

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from fastapi import FastAPI, Response
from pydantic import AwareDatetime, Field, field_validator

from app.contracts.errors import ErrorCode, FieldErrorCode
from app.schemas.responses import (
    ApiError,
    ApiModel,
    ErrorResponse,
    FieldError,
    PageMeta,
    PageResponse,
    ResponseMeta,
    RevisionConflictDetails,
    SuccessResponse,
)
from app.schemas.scalars import CanonicalDecimal

REQUEST_ID = UUID("018f1234-1234-7123-8123-123456789abc")
RESOURCE_ID = UUID("018f1234-5678-7123-8123-123456789abc")


class TextCard(ApiModel):
    kind: Literal["text"]
    text: str


class ChoiceCard(ApiModel):
    kind: Literal["choice"]
    choices: list[str]


class CompatibilityRead(ApiModel):
    resource_id: UUID
    created_at: AwareDatetime
    exact_amount: CanonicalDecimal
    status: Literal["pending", "complete"]
    nullable_optional: str | None = None
    card: Annotated[TextCard | ChoiceCard, Field(discriminator="kind")]

    @field_validator("created_at")
    @classmethod
    def require_utc(cls, value: datetime) -> datetime:
        offset = value.utcoffset()
        if offset is None or offset.total_seconds() != 0:
            raise ValueError("UTC timestamp required")
        return value


def compatibility_openapi() -> dict[str, object]:
    """Export isolated response types plus transport shapes; app.main never uses this app."""
    app = FastAPI(title="Haruka test-only Dart compatibility", version="1")

    @app.get("/samples/read", response_model=SuccessResponse[CompatibilityRead])
    def read_sample() -> Response:
        return Response(status_code=501)

    @app.get("/samples/page", response_model=PageResponse[CompatibilityRead])
    def page_sample() -> Response:
        return Response(status_code=501)

    @app.get("/samples/error", response_model=ErrorResponse)
    def error_sample() -> Response:
        return Response(status_code=501)

    @app.delete("/samples/empty", status_code=204)
    def empty_sample() -> Response:
        return Response(status_code=204)

    @app.get(
        "/samples/binary",
        response_class=Response,
        responses={
            200: {
                "content": {
                    "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
                }
            }
        },
    )
    def binary_sample() -> Response:
        return Response(content=b"haruka", media_type="application/octet-stream")

    @app.put(
        "/samples/upload",
        status_code=204,
        openapi_extra={
            "requestBody": {
                "required": True,
                "content": {
                    "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
                },
            }
        },
    )
    def upload_sample() -> Response:
        return Response(status_code=204)

    @app.post("/samples/decimal", response_model=SuccessResponse[CompatibilityRead])
    def decimal_sample(value: CompatibilityRead) -> SuccessResponse[CompatibilityRead]:
        return SuccessResponse(data=value, meta=ResponseMeta(request_id=REQUEST_ID))

    return app.openapi()


def compatibility_samples() -> dict[str, object]:
    """Serialize validated Python values, preserving omitted/null/value distinctions."""
    common: dict[str, object] = {
        "resource_id": str(RESOURCE_ID),
        "created_at": "2026-09-22T01:02:03.123456Z",
        "exact_amount": "12345678901234567890.123456789",
        "status": "complete",
        "card": {"kind": "text", "text": "日本語 / English"},
    }
    missing = CompatibilityRead.model_validate(common)
    null = CompatibilityRead.model_validate({**common, "nullable_optional": None})
    value = CompatibilityRead.model_validate(
        {
            **common,
            "nullable_optional": "present",
            "card": {"kind": "choice", "choices": ["A", "B"]},
        }
    )
    meta = ResponseMeta(request_id=REQUEST_ID)
    success = SuccessResponse[CompatibilityRead](data=missing, meta=meta)
    page = PageResponse[CompatibilityRead](
        data=[null, value],
        meta=PageMeta(request_id=REQUEST_ID, next_cursor="cursor-2", has_more=True),
    )
    error = ErrorResponse(
        error=ApiError(
            code=ErrorCode.INPUT_INVALID,
            message="输入信息有误",
            field_errors=[
                FieldError(
                    source="body",
                    path=["items", 0, "text"],
                    code=FieldErrorCode.TOO_LONG,
                    message="内容超过允许长度",
                    message_args={"limit": 10, "unit": "characters"},
                )
            ],
        ),
        meta=meta,
    )
    conflict = ErrorResponse(
        error=ApiError(
            code=ErrorCode.REVISION_CONFLICT,
            message="内容已更新，请重新加载",
            details=RevisionConflictDetails(current_revision=7),
        ),
        meta=meta,
    )
    return {
        "schema_version": 1,
        "success_missing": success.model_dump(mode="json", exclude_unset=True),
        "success_null": SuccessResponse[CompatibilityRead](data=null, meta=meta).model_dump(
            mode="json", exclude_unset=True
        ),
        "success_value": SuccessResponse[CompatibilityRead](data=value, meta=meta).model_dump(
            mode="json", exclude_unset=True
        ),
        "page": page.model_dump(mode="json"),
        "error": error.model_dump(mode="json"),
        "conflict": conflict.model_dump(mode="json"),
        "unknown_enum": {**common, "status": "future_status"},
        "decimal_boundaries": [
            {
                "input": numeric,
                "output": SuccessResponse[CompatibilityRead](
                    data=CompatibilityRead.model_validate(
                        {**common, "exact_amount": Decimal(numeric)}
                    ),
                    meta=meta,
                ).model_dump(mode="json"),
            }
            for numeric in (
                "1E+3",
                "1E-7",
                "-1E-7",
                "0E-10",
                "-0.00",
                "12345678901234567890.123456789",
            )
        ],
        "transports": {
            "empty": {"status": 204, "body": ""},
            "binary": {"status": 200, "bytes": [104, 97, 114, 117, 107, 97]},
            "upload": {"method": "PUT", "media_type": "application/octet-stream"},
        },
    }
