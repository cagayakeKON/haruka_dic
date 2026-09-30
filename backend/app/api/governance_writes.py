"""HTTP parsing for transactional administrative action receipts."""

import json
import re
from collections.abc import Awaitable, Callable
from typing import cast
from uuid import UUID

from fastapi import Request
from fastapi.routing import APIRoute
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.services.auth_crypto import AuthCrypto
from app.services.governance_receipts import GovernanceReceiptContext, commit_governance_receipt

GOVERNANCE_WRITE_HEADERS = {
    "parameters": [
        {
            "name": "Idempotency-Key",
            "in": "header",
            "required": True,
            "schema": {
                "type": "string",
                "minLength": 16,
                "maxLength": 128,
                "pattern": "^[A-Za-z0-9._:-]+$",
            },
            "description": "Stable key for one administrative user intent; retain for retries.",
        }
    ]
}


async def governance_write[T: BaseModel](
    session: AsyncSession,
    request: Request,
    scope: ScopeContext,
    result_type: type[T],
    operation: Callable[[], Awaitable[T]],
) -> T:
    runtime = require_runtime(request)
    route = request.scope.get("route")
    if not isinstance(route, APIRoute) or route.openapi_extra is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    key = request.headers.get("idempotency-key", "")
    if re.fullmatch(r"[A-Za-z0-9._:-]{16,128}", key) is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    action = f"{request.method}:{route.path}"
    if len(action) > 128:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        parsed: object = json.loads(await request.body())
        if not isinstance(parsed, dict):
            raise ValueError("object required")
        payload = cast(dict[str, object], parsed)
        canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    except (ValueError, TypeError):
        raise AppError(ErrorCode.INPUT_INVALID) from None
    raw_codes: object = route.openapi_extra.get("x-haruka-permissions", ())
    if not isinstance(raw_codes, list):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    codes: list[str] = []
    for code in cast(list[object], raw_codes):
        if not isinstance(code, str):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        codes.append(code)
    if route.operation_id == "set_admin_user_status":
        codes = ["admin.user.enable" if payload.get("status") == "active" else "admin.user.disable"]
    request.state.governance_permission = codes[0] if len(codes) == 1 else None
    context = GovernanceReceiptContext(
        action=action,
        key=key,
        request_text=request.url.path + "\n" + canonical,
        permissions=tuple(codes),
        user_id=UUID(str(request.path_params["user_id"]))
        if "user_id" in request.path_params
        else None,
        role_id=UUID(str(request.path_params["role_id"]))
        if "role_id" in request.path_params
        else None,
        challenge_id=UUID(str(payload["challenge_id"])) if "challenge_id" in payload else None,
        deleted_role=route.operation_id == "delete_admin_role",
    )
    return await commit_governance_receipt(
        session, scope, context, AuthCrypto.from_settings(runtime.settings), result_type, operation
    )
