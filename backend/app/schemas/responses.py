"""Single source of JSON response envelopes."""

from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.contracts.errors import ErrorCode, FieldErrorCode


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)


class ResponseMeta(ApiModel):
    request_id: UUID


class PageMeta(ResponseMeta):
    next_cursor: str | None
    has_more: bool

    @model_validator(mode="after")
    def validate_cursor(self) -> Self:
        if (self.has_more and not self.next_cursor) or (
            not self.has_more and self.next_cursor is not None
        ):
            raise ValueError("has_more and next_cursor must agree")
        return self


class SuccessResponse[T](ApiModel):
    data: T
    meta: ResponseMeta


class PageResponse[T](ApiModel):
    data: list[T]
    meta: PageMeta


class FieldError(ApiModel):
    source: Literal["body", "query", "path", "header", "cookie"]
    path: list[str | int]
    code: FieldErrorCode
    message: str
    message_args: dict[str, str | int] = Field(default_factory=dict)


class RevisionConflictDetails(ApiModel):
    kind: Literal["revision_conflict"] = "revision_conflict"
    current_revision: int = Field(ge=0)


class ApiError(ApiModel):
    code: ErrorCode
    message: str
    retryable: bool = False
    message_args: dict[str, str | int] = Field(default_factory=dict)
    field_errors: list[FieldError] = Field(default_factory=lambda: list[FieldError]())
    details: RevisionConflictDetails | None = None

    @model_validator(mode="after")
    def validate_details(self) -> Self:
        if self.details is not None and self.code != ErrorCode.REVISION_CONFLICT:
            raise ValueError("details do not match error code")
        # No safe message parameters are registered by this initial slice.
        if self.message_args:
            raise ValueError("unregistered error message parameters")
        return self


class ErrorResponse(ApiModel):
    error: ApiError
    meta: ResponseMeta
