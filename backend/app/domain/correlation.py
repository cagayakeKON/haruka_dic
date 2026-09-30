"""Server-owned request correlation shared by API and append-only audit writes."""

from contextvars import ContextVar
from typing import Literal
from uuid import UUID

request_id_context: ContextVar[UUID | None] = ContextVar("haruka_request_id", default=None)
operation_id_context: ContextVar[UUID | None] = ContextVar("haruka_operation_id", default=None)
job_id_context: ContextVar[UUID | None] = ContextVar("haruka_job_id", default=None)
ai_run_id_context: ContextVar[UUID | None] = ContextVar("haruka_ai_run_id", default=None)
user_id_context: ContextVar[UUID | None] = ContextVar("haruka_user_id", default=None)
audience_context: ContextVar[Literal["client", "admin"] | None] = ContextVar(
    "haruka_audience", default=None
)


def current_correlation() -> tuple[UUID | None, UUID | None]:
    return request_id_context.get(), operation_id_context.get()


def current_log_context() -> dict[str, object]:
    """Trusted correlation fields for safe structured business events."""
    return {
        "request_id": request_id_context.get(),
        "operation_id": operation_id_context.get(),
        "user_id": user_id_context.get(),
        "job_id": job_id_context.get(),
        "ai_run_id": ai_run_id_context.get(),
        "audience": audience_context.get(),
    }
