"""Read-only audit chronology and identity governance counts."""

from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.schemas.audit_governance import AuditEventRead, GovernanceSummaryRead
from app.schemas.responses import PageMeta, PageResponse, ResponseMeta, SuccessResponse
from app.services import audit_governance

router = APIRouter(prefix="/api/v1", tags=["audit-governance"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)


@router.get(
    "/admin/audit-events",
    operation_id="list_admin_audit_events",
    response_model=PageResponse[AuditEventRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.audit.read"]},
)
async def list_admin_audit_events(
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    cursor: str | None = Query(default=None, max_length=120),
    action: str | None = Query(default=None, max_length=100),
    result: str | None = Query(default=None, max_length=24),
    actor_user_id: UUID | None = None,
    target_type: str | None = Query(default=None, max_length=64),
) -> PageResponse[AuditEventRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.audit.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        events, next_cursor = await audit_governance.list_audit_events(
            session,
            actor_id=scope.user_id,
            limit=limit,
            cursor=cursor,
            action=action,
            result=result,
            actor_user_id=actor_user_id,
            target_type=target_type,
        )
    return PageResponse[AuditEventRead](
        data=events,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )


@router.get(
    "/admin/governance-summary",
    operation_id="read_admin_governance_summary",
    response_model=SuccessResponse[GovernanceSummaryRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.dashboard.view"]},
)
async def read_admin_governance_summary(
    request: Request,
) -> SuccessResponse[GovernanceSummaryRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.dashboard.view",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        summary = await audit_governance.read_governance_summary(session, actor_id=scope.user_id)
    return SuccessResponse[GovernanceSummaryRead](
        data=summary, meta=ResponseMeta(request_id=get_request_id(request))
    )
