"""Bound selected JSON bodies before FastAPI parses or allocates their content."""

import re

from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.api.responses import error_response
from app.contracts.errors import ErrorCode
from app.services.avatar_image import MAX_COMPLETE_BODY

_AVATAR_COMPLETE = re.compile(
    r"/api/v1/users/me/avatar-upload-intents/"
    r"[0-9a-fA-F-]{36}/complete"
)
_CACHE_VALIDATE = "/api/v1/me/cache/validate"
_CACHE_MAX_BODY = 64 * 1024


class SelectedBodyLimitMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] != "POST":
            await self.app(scope, receive, send)
            return
        path = scope["path"]
        if path == _CACHE_VALIDATE:
            limit = _CACHE_MAX_BODY
        elif _AVATAR_COMPLETE.fullmatch(path):
            limit = MAX_COMPLETE_BODY
        else:
            await self.app(scope, receive, send)
            return
        declared = Request(scope).headers.get("content-length")
        if declared is not None and (
            not declared.isdecimal() or len(declared) > 8 or int(declared) > limit
        ):
            await error_response(Request(scope), ErrorCode.PAYLOAD_TOO_LARGE)(scope, receive, send)
            return
        chunks: list[bytes] = []
        total = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            total += len(chunk)
            if total > limit:
                await error_response(Request(scope), ErrorCode.PAYLOAD_TOO_LARGE)(
                    scope, receive, send
                )
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                break
        body = b"".join(chunks)
        delivered = False

        async def bounded_receive() -> Message:
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        await self.app(scope, bounded_receive, send)
