"""Request correlation and the pre-stream unexpected-error boundary."""

import logging
from time import monotonic
from uuid import uuid4

from starlette.datastructures import MutableHeaders
from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.api.exception_handlers import handle_internal_error
from app.api.responses import get_request_id

logger = logging.getLogger(__name__)


class RequestContextMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request_id = uuid4()
        scope.setdefault("state", {})["request_id"] = request_id
        status_code = 500
        beginning = monotonic()

        async def correlated_send(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = MutableHeaders(scope=message)
                headers["X-Request-ID"] = str(request_id)
                headers["Cache-Control"] = "no-store"
            await send(message)

        try:
            await self.app(scope, receive, correlated_send)
        finally:
            logger.info(
                "http.completed",
                extra={
                    "request_id": request_id,
                    "status_code": status_code,
                    "duration_ms": (monotonic() - beginning) * 1000,
                },
            )


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
