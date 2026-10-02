"""Private notification receipts with independently authorized read actions."""

from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_session_csrf
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.schemas.user_notifications import (
    NotificationMarkRead,
    NotificationsReadAll,
    NotificationsReadAllResult,
    UserNotificationPage,
    UserNotificationPageMeta,
    UserNotificationRead,
)
from app.services import user_notifications as service

router = APIRouter(prefix="/api/v1/notifications", tags=["user-notifications"])
COMMON = error_responses(400, 401, 403, 404, 409, 410, 422, 429, 500, 503)
READ = ("client.notification.read",)
WRITE = (*READ, "client.notification.update")


async def context(request: Request, *, write: bool = False) -> ScopeContext:
    scope = await require_scope(request, audience="client", permissions=WRITE if write else READ)
    if write:
        if scope.transport == "web":
            await require_session_csrf(request, require_runtime(request), scope)
        elif (
            request.headers.get("origin")
            or request.headers.get("cookie")
            or request.headers.get("content-type", "").split(";", 1)[0] != "application/json"
        ):
            raise AppError(ErrorCode.SESSION_INVALID)
    return scope


@router.get(
    "",
    operation_id="list_user_notifications",
    response_model=UserNotificationPage,
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": list(READ)},
)
async def list_notifications(
    request: Request,
    unread_only: bool = False,
    limit: int = Query(default=50, ge=1, le=100),
    cursor: str | None = Query(default=None, min_length=1, max_length=2048),
) -> UserNotificationPage:
    scope = await context(request)
    result = await service.list_notifications(
        require_runtime(request), scope, unread_only=unread_only, limit=limit, cursor=cursor
    )
    return UserNotificationPage(
        data=result.items,
        meta=UserNotificationPageMeta(
            request_id=get_request_id(request),
            next_cursor=result.next_cursor,
            has_more=result.next_cursor is not None,
            unread_count=result.unread_count,
            snapshot_token=result.snapshot_token,
            snapshot_expires_at=result.snapshot_expires_at,
        ),
    )


@router.post(
    "/read-all",
    operation_id="mark_all_user_notifications_read",
    response_model=SuccessResponse[NotificationsReadAllResult],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": list(WRITE)},
)
async def mark_all_read(
    request: Request, payload: NotificationsReadAll
) -> SuccessResponse[NotificationsReadAllResult]:
    scope = await context(request, write=True)
    result = await service.mark_all_read(require_runtime(request), scope, payload.snapshot_token)
    return SuccessResponse[NotificationsReadAllResult](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/{notification_id}/read",
    operation_id="mark_user_notification_read",
    response_model=SuccessResponse[UserNotificationRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": list(WRITE)},
)
async def mark_read(
    request: Request, notification_id: UUID, payload: NotificationMarkRead
) -> SuccessResponse[UserNotificationRead]:
    scope = await context(request, write=True)
    result = await service.mark_read(require_runtime(request), scope, notification_id)
    return SuccessResponse[UserNotificationRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )
