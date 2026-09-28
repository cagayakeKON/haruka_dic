"""Request correlation and the pre-stream unexpected-error boundary."""

import logging
from time import monotonic
from uuid import UUID, uuid4

from starlette.datastructures import MutableHeaders
from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.api.exception_handlers import handle_internal_error
from app.api.responses import get_request_id
from app.domain.correlation import (
    audience_context,
    operation_id_context,
    request_id_context,
    user_id_context,
)

logger = logging.getLogger(__name__)


def _optional_uuid(value: str | None) -> UUID | None:
    if value is None or len(value) != 36:
        return None
    try:
        parsed = UUID(value)
    except ValueError:
        return None
    return parsed if str(parsed) == value.lower() else None


class RequestContextMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request_id = uuid4()
        state = scope.setdefault("state", {})
        state["request_id"] = request_id
        request_headers = Request(scope).headers
        operation_id = _optional_uuid(request_headers.get("x-operation-id"))
        client_request_id = _optional_uuid(request_headers.get("x-client-request-id"))
        state["operation_id"] = operation_id
        state["client_request_id"] = client_request_id
        request_token = request_id_context.set(request_id)
        operation_token = operation_id_context.set(operation_id)
        user_token = user_id_context.set(None)
        audience_token = audience_context.set(None)
        status_code = 500
        beginning = monotonic()

        async def correlated_send(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = MutableHeaders(scope=message)
                headers["X-Request-ID"] = str(request_id)
                headers["Cache-Control"] = "no-store"
                if state.get("session_ref") and state.get("instance_id"):
                    headers["X-Haruka-Instance-ID"] = state["instance_id"]
                    headers["X-Haruka-Session-Ref"] = state["session_ref"]
            await send(message)

        try:
            await self.app(scope, receive, correlated_send)
        finally:
            try:
                route = scope.get("route")
                route_template = getattr(route, "path", None)
                if not isinstance(route_template, str) or len(route_template) > 200:
                    route_template = None
                logger.info(
                    "http.completed",
                    extra={
                        "request_id": request_id,
                        "status_code": status_code,
                        "duration_ms": (monotonic() - beginning) * 1000,
                        "operation_id": operation_id,
                        "client_request_id": client_request_id,
                        "user_id": state.get("user_id"),
                        "audience": state.get("audience"),
                        "route_template": route_template,
                    },
                )
            finally:
                audience_context.reset(audience_token)
                user_id_context.reset(user_token)
                operation_id_context.reset(operation_token)
                request_id_context.reset(request_token)


class ErrorBoundaryMiddleware:
    """Catch errors inside CORS; correlation wraps both this boundary and CORS."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False

        async def track_start(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, receive, track_start)
        except Exception as exc:
            request = Request(scope)
            if started:
                # Never append JSON to an already-started stream or swallow cancellation.
                logger.error(
                    "http.failed", exc_info=exc, extra={"request_id": get_request_id(request)}
                )
                raise
            response = await handle_internal_error(request, exc)
            await response(scope, receive, track_start)
