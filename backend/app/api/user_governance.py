"""Admin account, membership, and session routes."""

from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.governance_writes import GOVERNANCE_WRITE_HEADERS, governance_write
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_session_csrf
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.responses import PageMeta, PageResponse, ResponseMeta, SuccessResponse
from app.schemas.user_governance import (
    AccountApprovalUpdate,
    AccountCeilingsRead,
    AccountCreate,
    AccountRead,
    AccountRolesUpdate,
    AccountSessionRead,
    AccountStatusUpdate,
    AccountWriteResult,
    ManualRecoveryDecision,
    ManualRecoveryDecisionResult,
    ManualRecoveryRead,
    SessionRevocation,
)
from app.services import user_governance
from app.services.auth_crypto import AuthCrypto
from app.services.registration import email_identity

router = APIRouter(prefix="/api/v1", tags=["user-governance"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)


async def _admin_write(request: Request) -> tuple[Runtime, ScopeContext]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin")
    await require_session_csrf(request, runtime, scope)
    return runtime, scope


@router.get(
    "/admin/users",
    operation_id="list_admin_users",
    response_model=PageResponse[AccountRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.user.read"]},
)
async def list_admin_users(
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    cursor: str | None = None,
    query: str | None = Query(default=None, max_length=254),
) -> PageResponse[AccountRead]:
    after_email = None
    if cursor is not None:
        _, after_email = email_identity(cursor)
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.user.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        accounts, next_cursor = await user_governance.list_accounts(
            session,
            actor_id=scope.user_id,
            limit=limit,
            after_email=after_email,
            query=query,
        )
    return PageResponse[AccountRead](
        data=accounts,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )


@router.post(
    "/admin/users",
    operation_id="create_admin_user",
    response_model=SuccessResponse[AccountWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.user.create"]},
)
async def create_admin_user(
    request: Request, payload: AccountCreate
) -> SuccessResponse[AccountWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        created = await governance_write(
            session,
            request,
            scope,
            AccountWriteResult,
            lambda: user_governance.create_account(
                session,
                actor_id=scope.user_id,
                email=payload.email,
                display_name=payload.display_name,
                role_ids=tuple(payload.role_ids),
            ),
        )
    return SuccessResponse[AccountWriteResult](
        data=created, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/account-ceilings",
    operation_id="get_admin_account_ceilings",
    response_model=SuccessResponse[AccountCeilingsRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.user.read"]},
)
async def get_admin_account_ceilings(request: Request) -> SuccessResponse[AccountCeilingsRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.user.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        ceilings = await user_governance.read_account_ceilings(session, actor_id=scope.user_id)
    return SuccessResponse[AccountCeilingsRead](
        data=ceilings, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/users/{user_id}",
    operation_id="get_admin_user",
    response_model=SuccessResponse[AccountRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.user.read"]},
)
async def get_admin_user(request: Request, user_id: UUID) -> SuccessResponse[AccountRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.user.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        account = await user_governance.read_account(
            session, actor_id=scope.user_id, user_id=user_id
        )
    return SuccessResponse[AccountRead](
        data=account, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/users/{user_id}/status",
    operation_id="set_admin_user_status",
    response_model=SuccessResponse[AccountWriteResult],
    responses=COMMON,
    openapi_extra={
        **GOVERNANCE_WRITE_HEADERS,
        "x-haruka-permissions": ["admin.user.enable", "admin.user.disable"],
    },
)
async def set_admin_user_status(
    request: Request, user_id: UUID, payload: AccountStatusUpdate
) -> SuccessResponse[AccountWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AccountWriteResult,
            lambda: user_governance.set_account_status(
                session,
                actor_id=scope.user_id,
                user_id=user_id,
                expected_revision=payload.expected_revision,
                status=payload.status,
            ),
        )
    return SuccessResponse[AccountWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/users/{user_id}/approval",
    operation_id="decide_admin_user_approval",
    response_model=SuccessResponse[AccountWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.user.approve"]},
)
async def decide_admin_user_approval(
    request: Request, user_id: UUID, payload: AccountApprovalUpdate
) -> SuccessResponse[AccountWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AccountWriteResult,
            lambda: user_governance.decide_account_approval(
                session,
                actor_id=scope.user_id,
                user_id=user_id,
                expected_revision=payload.expected_revision,
                decision=payload.decision,
            ),
        )
    return SuccessResponse[AccountWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/users/{user_id}/recovery-requests",
    operation_id="list_admin_user_recovery_requests",
    response_model=SuccessResponse[list[ManualRecoveryRead]],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.user.read"]},
)
async def list_admin_user_recovery_requests(
    request: Request, user_id: UUID
) -> SuccessResponse[list[ManualRecoveryRead]]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.user.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        rows = await user_governance.list_manual_recoveries(
            session, actor_id=scope.user_id, user_id=user_id
        )
    return SuccessResponse[list[ManualRecoveryRead]](
        data=rows, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/users/{user_id}/recovery-decisions",
    operation_id="decide_admin_user_recovery",
    response_model=SuccessResponse[ManualRecoveryDecisionResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.user.update"]},
)
async def decide_admin_user_recovery(
    request: Request, user_id: UUID, payload: ManualRecoveryDecision
) -> SuccessResponse[ManualRecoveryDecisionResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    async with runtime.resources.database.sessions() as session, session.begin():
        decided = await governance_write(
            session,
            request,
            scope,
            ManualRecoveryDecisionResult,
            lambda: user_governance.decide_manual_recovery(
                session,
                actor_id=scope.user_id,
                user_id=user_id,
                challenge_id=payload.challenge_id,
                expected_revision=payload.expected_revision,
                decision=payload.decision,
                verification_method=payload.verification_method,
                crypto=crypto,
            ),
        )
    return SuccessResponse[ManualRecoveryDecisionResult](
        data=decided, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/users/{user_id}/roles",
    operation_id="replace_admin_user_roles",
    response_model=SuccessResponse[AccountWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.user.role.assign"]},
)
async def replace_admin_user_roles(
    request: Request, user_id: UUID, payload: AccountRolesUpdate
) -> SuccessResponse[AccountWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        updated = await governance_write(
            session,
            request,
            scope,
            AccountWriteResult,
            lambda: user_governance.replace_account_roles(
                session,
                actor_id=scope.user_id,
                user_id=user_id,
                expected_revision=payload.expected_revision,
                role_ids=tuple(payload.role_ids),
            ),
        )
    return SuccessResponse[AccountWriteResult](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/users/{user_id}/sessions",
    operation_id="list_admin_user_sessions",
    response_model=SuccessResponse[list[AccountSessionRead]],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.session.read"]},
)
async def list_admin_user_sessions(
    request: Request, user_id: UUID
) -> SuccessResponse[list[AccountSessionRead]]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.session.read",))
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session:
        rows = await user_governance.list_account_sessions(
            session, actor_id=scope.user_id, user_id=user_id
        )
    return SuccessResponse[list[AccountSessionRead]](
        data=rows, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/users/{user_id}/session-revocations",
    operation_id="revoke_admin_user_sessions",
    response_model=SuccessResponse[AccountWriteResult],
    responses=COMMON,
    openapi_extra={**GOVERNANCE_WRITE_HEADERS, "x-haruka-permissions": ["admin.session.revoke"]},
)
async def revoke_admin_user_sessions(
    request: Request, user_id: UUID, payload: SessionRevocation
) -> SuccessResponse[AccountWriteResult]:
    runtime, scope = await _admin_write(request)
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with runtime.resources.database.sessions() as session, session.begin():
        revoked = await governance_write(
            session,
            request,
            scope,
            AccountWriteResult,
            lambda: user_governance.revoke_account_sessions(
                session,
                actor_id=scope.user_id,
                user_id=user_id,
                expected_revision=payload.expected_revision,
                session_id=payload.session_id,
                audience=payload.audience,
                all_sessions=payload.all_sessions,
            ),
        )
    return SuccessResponse[AccountWriteResult](
        data=revoked, meta=ResponseMeta(request_id=get_request_id(request))
    )
