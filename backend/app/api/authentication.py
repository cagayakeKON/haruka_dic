"""Authentication, account security, and session HTTP routes."""

import re
from typing import NoReturn
from uuid import UUID

from fastapi import APIRouter, Header, Query, Request, Response

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import (
    rate_limit,
    require_authenticated_native_write,
    require_native_write,
    require_public_write,
    require_session_csrf,
    require_web_write,
)
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.email_address import normalize_existing_login_email
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.auth import (
    AccessRead,
    AccountRead,
    ActivationStatusRead,
    AdminAuthPolicyRead,
    AdminAuthPolicyUpdate,
    AuthPolicyRead,
    CsrfRead,
    EmailRequest,
    LoginRequest,
    MailAccepted,
    MetaRead,
    NativeAuthenticated,
    NativeLoginRead,
    NativeLoginRequest,
    NativeRefreshRequest,
    PasswordChangeRequest,
    RecoveryCompleteRequest,
    RegisterRequest,
    SessionSummary,
    TokenRequest,
    WebAuthenticated,
    WebLoginRead,
)
from app.schemas.responses import PageMeta, PageResponse, ResponseMeta, SuccessResponse
from app.services.auth_policy import read_admin_policy, read_public_policy, update_admin_policy
from app.services.registration import activation_status as read_activation_status
from app.services.registration import complete_recovery as consume_password_recovery
from app.services.registration import email_identity, register, request_challenge
from app.services.registration import verify_email as consume_email_verification
from app.services.sessions import (
    change_password,
    issue_csrf,
    list_sessions,
    login,
    read_access,
    read_account,
    refresh_native,
    renew_web,
    revoke_session,
)

router = APIRouter(prefix="/api/v1", tags=["authentication"])
COMMON = error_responses(400, 401, 403, 404, 409, 410, 415, 422, 429, 500, 503)


def unavailable() -> NoReturn:
    """An unwired endpoint must never produce a fabricated success."""
    raise AppError(ErrorCode.SERVICE_UNAVAILABLE)


async def _write_scope(request: Request, audience: str) -> tuple[Runtime, ScopeContext]:
    selected = "admin" if audience == "admin" else "client"
    runtime = require_runtime(request)
    scope = await require_scope(request, audience=selected)
    if scope.transport == "web":
        await require_session_csrf(request, runtime, scope)
    else:
        require_authenticated_native_write(request)
    return runtime, scope


@router.get(
    "/meta",
    operation_id="get_public_meta",
    response_model=SuccessResponse[MetaRead],
    responses=error_responses(500, 503),
    openapi_extra={"x-haruka-access": "public-meta"},
)
async def public_meta(request: Request) -> SuccessResponse[MetaRead]:
    runtime: object = getattr(request.app.state, "runtime", None)
    if not isinstance(runtime, Runtime) or not runtime.active:
        unavailable()
    return SuccessResponse[MetaRead](
        data=MetaRead(
            instance_id=runtime.settings.instance_id,
            release=runtime.settings.release,
        ),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/auth/policy",
    operation_id="get_auth_policy",
    response_model=SuccessResponse[AuthPolicyRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-auth-policy"},
)
async def auth_policy(request: Request) -> SuccessResponse[AuthPolicyRead]:
    runtime: object = getattr(request.app.state, "runtime", None)
    if not isinstance(runtime, Runtime):
        unavailable()
    policy = await read_public_policy(runtime)
    return SuccessResponse[AuthPolicyRead](
        data=policy, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/admin/auth-policy",
    operation_id="get_admin_auth_policy",
    response_model=SuccessResponse[AdminAuthPolicyRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.auth_policy.read"]},
)
async def admin_auth_policy(request: Request) -> SuccessResponse[AdminAuthPolicyRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin", permissions=("admin.auth_policy.read",))
    return SuccessResponse[AdminAuthPolicyRead](
        data=await read_admin_policy(runtime, scope),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.patch(
    "/admin/auth-policy",
    operation_id="update_admin_auth_policy",
    response_model=SuccessResponse[AdminAuthPolicyRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.auth_policy.update"]},
)
async def update_admin_auth_policy(
    request: Request, payload: AdminAuthPolicyUpdate
) -> SuccessResponse[AdminAuthPolicyRead]:
    runtime, scope = await _write_scope(request, "admin")
    updated = await update_admin_policy(runtime, scope, payload)
    return SuccessResponse[AdminAuthPolicyRead](
        data=updated, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/register",
    operation_id="register_account",
    status_code=202,
    response_model=SuccessResponse[MailAccepted],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-registration"},
)
async def register_account(
    request: Request, payload: RegisterRequest
) -> SuccessResponse[MailAccepted]:
    runtime = require_runtime(request)
    require_public_write(request, runtime)
    _, normalized = email_identity(payload.email)
    await rate_limit(request, runtime, purpose="register", identity=normalized)
    receipt = await register(runtime, email=payload.email, password=payload.password)
    return SuccessResponse[MailAccepted](
        data=receipt, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/email/resend",
    operation_id="resend_email_verification",
    status_code=202,
    response_model=SuccessResponse[MailAccepted],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-email-resend"},
)
async def resend_email(request: Request, payload: EmailRequest) -> SuccessResponse[MailAccepted]:
    runtime = require_runtime(request)
    require_public_write(request, runtime)
    _, normalized = email_identity(payload.email)
    await rate_limit(request, runtime, purpose="email-resend", identity=normalized)
    receipt = await request_challenge(runtime, email=payload.email, purpose="email_verify")
    return SuccessResponse[MailAccepted](
        data=receipt, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/email/verify",
    operation_id="verify_email",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-email-verify"},
)
async def verify_email(request: Request, payload: TokenRequest) -> Response:
    runtime = require_runtime(request)
    require_public_write(request, runtime)
    await rate_limit(request, runtime, purpose="email-verify")
    await consume_email_verification(runtime, token=payload.token)
    return Response(status_code=204)


@router.post(
    "/auth/recovery/request",
    operation_id="request_password_recovery",
    status_code=202,
    response_model=SuccessResponse[MailAccepted],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-password-recovery"},
)
async def request_recovery(
    request: Request, payload: EmailRequest
) -> SuccessResponse[MailAccepted]:
    runtime = require_runtime(request)
    require_public_write(request, runtime)
    _, normalized = email_identity(payload.email)
    await rate_limit(request, runtime, purpose="recovery", identity=normalized)
    receipt = await request_challenge(runtime, email=payload.email, purpose="password_recovery")
    return SuccessResponse[MailAccepted](
        data=receipt, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/recovery/complete",
    operation_id="complete_password_recovery",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-password-recovery"},
)
async def complete_recovery(request: Request, payload: RecoveryCompleteRequest) -> Response:
    runtime = require_runtime(request)
    require_public_write(request, runtime)
    await rate_limit(request, runtime, purpose="password-recovery-complete")
    await consume_password_recovery(runtime, token=payload.token, new_password=payload.new_password)
    return Response(status_code=204)


@router.get(
    "/auth/activation/status",
    operation_id="get_activation_status",
    response_model=SuccessResponse[ActivationStatusRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "limited-continuation"},
)
async def activation_status(
    request: Request, authorization: str = Header()
) -> SuccessResponse[ActivationStatusRead]:
    if (
        not authorization.startswith("Bearer ")
        or re.fullmatch(r"[A-Za-z0-9_-]{43}", authorization.removeprefix("Bearer ")) is None
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    runtime = require_runtime(request)
    await rate_limit(request, runtime, purpose="activation-status")
    result = await read_activation_status(
        runtime, continuation=authorization.removeprefix("Bearer ")
    )
    return SuccessResponse[ActivationStatusRead](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/login",
    operation_id="login_web_client",
    response_model=SuccessResponse[WebLoginRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-client-login-web"},
)
async def login_web_client(
    request: Request, response: Response, payload: LoginRequest
) -> SuccessResponse[WebLoginRead]:
    runtime = require_runtime(request)
    require_web_write(request, runtime, anonymous=True)
    try:
        _, normalized = normalize_existing_login_email(payload.email)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    await rate_limit(request, runtime, purpose="login-client", identity=normalized)
    result = await login(
        runtime,
        email=payload.email,
        password=payload.password,
        audience="client",
        transport="web",
        platform="web",
    )
    if isinstance(result.response, NativeAuthenticated):
        raise AppError(ErrorCode.INTERNAL_ERROR)
    if result.web_cookie is not None:
        response.set_cookie(
            "haruka_client_session",
            result.web_cookie,
            max_age=7 * 24 * 60 * 60,
            path="/api/v1",
            secure=True,
            httponly=True,
            samesite="strict",
        )
    return SuccessResponse[WebLoginRead](
        data=result.response, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/auth/login",
    operation_id="login_web_admin",
    response_model=SuccessResponse[WebLoginRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-admin-login-web"},
)
async def login_web_admin(
    request: Request, response: Response, payload: LoginRequest
) -> SuccessResponse[WebLoginRead]:
    runtime = require_runtime(request)
    require_web_write(request, runtime, anonymous=True)
    try:
        _, normalized = normalize_existing_login_email(payload.email)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    await rate_limit(request, runtime, purpose="login-admin", identity=normalized)
    result = await login(
        runtime,
        email=payload.email,
        password=payload.password,
        audience="admin",
        transport="web",
        platform="web",
    )
    if isinstance(result.response, NativeAuthenticated):
        raise AppError(ErrorCode.INTERNAL_ERROR)
    if result.web_cookie is not None:
        response.set_cookie(
            "haruka_admin_session",
            result.web_cookie,
            max_age=8 * 60 * 60,
            path="/api/v1/admin",
            secure=True,
            httponly=True,
            samesite="strict",
        )
    return SuccessResponse[WebLoginRead](
        data=result.response, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/native/login",
    operation_id="login_native_client",
    response_model=SuccessResponse[NativeLoginRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "public-client-login-native"},
)
async def login_native_client(
    request: Request, payload: NativeLoginRequest
) -> SuccessResponse[NativeLoginRead]:
    runtime = require_runtime(request)
    require_native_write(request)
    try:
        _, normalized = normalize_existing_login_email(payload.email)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    await rate_limit(request, runtime, purpose="login-client", identity=normalized)
    result = await login(
        runtime,
        email=payload.email,
        password=payload.password,
        audience="client",
        transport="native",
        platform=payload.platform,
        device_summary=payload.device_summary,
    )
    if isinstance(result.response, WebAuthenticated):
        raise AppError(ErrorCode.INTERNAL_ERROR)
    return SuccessResponse[NativeLoginRead](
        data=result.response, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/auth/csrf",
    operation_id="get_client_csrf",
    response_model=SuccessResponse[CsrfRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def client_csrf(request: Request) -> SuccessResponse[CsrfRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client")
    token = await issue_csrf(runtime, scope)
    return SuccessResponse[CsrfRead](
        data=CsrfRead(session_ref=scope.session_id, csrf_token=token),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/admin/auth/csrf",
    operation_id="get_admin_csrf",
    response_model=SuccessResponse[CsrfRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def admin_csrf(request: Request) -> SuccessResponse[CsrfRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin")
    token = await issue_csrf(runtime, scope)
    return SuccessResponse[CsrfRead](
        data=CsrfRead(session_ref=scope.session_id, csrf_token=token),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.post(
    "/auth/refresh",
    operation_id="refresh_client_web_session",
    response_model=SuccessResponse[WebAuthenticated],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def refresh_client_web(request: Request) -> SuccessResponse[WebAuthenticated]:
    runtime, scope = await _write_scope(request, "client")
    if scope.transport != "web":
        raise AppError(ErrorCode.SESSION_INVALID)
    cookie = request.cookies.get("haruka_client_session", "")
    result = await renew_web(runtime, scope, cookie)
    return SuccessResponse[WebAuthenticated](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/admin/auth/refresh",
    operation_id="refresh_admin_web_session",
    response_model=SuccessResponse[WebAuthenticated],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def refresh_admin_web(request: Request) -> SuccessResponse[WebAuthenticated]:
    runtime, scope = await _write_scope(request, "admin")
    if scope.transport != "web":
        raise AppError(ErrorCode.SESSION_INVALID)
    cookie = request.cookies.get("haruka_admin_session", "")
    result = await renew_web(runtime, scope, cookie)
    return SuccessResponse[WebAuthenticated](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.post(
    "/auth/native/refresh",
    operation_id="refresh_client_native_session",
    response_model=SuccessResponse[NativeAuthenticated],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-native-refresh"},
)
async def refresh_client_native(
    request: Request, payload: NativeRefreshRequest
) -> SuccessResponse[NativeAuthenticated]:
    runtime = require_runtime(request)
    require_native_write(request)
    result = await refresh_native(
        runtime,
        refresh_token=payload.refresh_token,
        refresh_request_id=payload.refresh_request_id,
    )
    return SuccessResponse[NativeAuthenticated](
        data=result, meta=ResponseMeta(request_id=get_request_id(request))
    )


@router.get(
    "/me/access",
    operation_id="get_client_access",
    response_model=SuccessResponse[AccessRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["client.login"]},
)
async def client_access(request: Request) -> SuccessResponse[AccessRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client")
    return SuccessResponse[AccessRead](
        data=await read_access(runtime, scope),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/admin/me/access",
    operation_id="get_admin_access",
    response_model=SuccessResponse[AccessRead],
    responses=COMMON,
    openapi_extra={"x-haruka-permissions": ["admin.login"]},
)
async def admin_access(request: Request) -> SuccessResponse[AccessRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin")
    return SuccessResponse[AccessRead](
        data=await read_access(runtime, scope),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/users/me/account",
    operation_id="get_my_account",
    response_model=SuccessResponse[AccountRead],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def own_account(request: Request) -> SuccessResponse[AccountRead]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client")
    return SuccessResponse[AccountRead](
        data=await read_account(runtime, scope),
        meta=ResponseMeta(request_id=get_request_id(request)),
    )


@router.get(
    "/auth/sessions",
    operation_id="list_client_sessions",
    response_model=PageResponse[SessionSummary],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def client_sessions(
    request: Request, limit: int = Query(default=20, ge=1, le=100), cursor: str | None = None
) -> PageResponse[SessionSummary]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="client")
    rows, next_cursor = await list_sessions(runtime, scope, limit=limit, cursor=cursor)
    return PageResponse[SessionSummary](
        data=rows,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )


@router.get(
    "/admin/auth/sessions",
    operation_id="list_admin_sessions",
    response_model=PageResponse[SessionSummary],
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def admin_sessions(
    request: Request, limit: int = Query(default=20, ge=1, le=100), cursor: str | None = None
) -> PageResponse[SessionSummary]:
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin")
    rows, next_cursor = await list_sessions(runtime, scope, limit=limit, cursor=cursor)
    return PageResponse[SessionSummary](
        data=rows,
        meta=PageMeta(
            request_id=get_request_id(request),
            next_cursor=next_cursor,
            has_more=next_cursor is not None,
        ),
    )


@router.post(
    "/auth/sessions/{session_id}/revoke",
    operation_id="revoke_client_session",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def revoke_client_session(request: Request, session_id: UUID) -> Response:
    runtime, scope = await _write_scope(request, "client")
    await revoke_session(runtime, scope, target_id=session_id)
    return Response(status_code=204)


@router.post(
    "/admin/auth/sessions/{session_id}/revoke",
    operation_id="revoke_admin_session",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def revoke_admin_session(request: Request, session_id: UUID) -> Response:
    runtime, scope = await _write_scope(request, "admin")
    await revoke_session(runtime, scope, target_id=session_id)
    return Response(status_code=204)


@router.post(
    "/auth/sessions/revoke-all",
    operation_id="revoke_all_client_sessions",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def revoke_all_client_sessions(request: Request) -> Response:
    runtime, scope = await _write_scope(request, "client")
    await revoke_session(runtime, scope, target_id=scope.session_id, all_audience=True)
    return Response(status_code=204)


@router.post(
    "/admin/auth/sessions/revoke-all",
    operation_id="revoke_all_admin_sessions",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def revoke_all_admin_sessions(request: Request) -> Response:
    runtime, scope = await _write_scope(request, "admin")
    await revoke_session(runtime, scope, target_id=scope.session_id, all_audience=True)
    return Response(status_code=204)


@router.post(
    "/auth/password/change",
    operation_id="change_client_password",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def change_client_password(request: Request, payload: PasswordChangeRequest) -> Response:
    runtime, scope = await _write_scope(request, "client")
    await change_password(
        runtime,
        scope,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )
    return Response(status_code=204)


@router.post(
    "/admin/auth/password/change",
    operation_id="change_admin_password",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def change_admin_password(request: Request, payload: PasswordChangeRequest) -> Response:
    runtime, scope = await _write_scope(request, "admin")
    await change_password(
        runtime,
        scope,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )
    return Response(status_code=204)


@router.post(
    "/auth/logout",
    operation_id="logout_client",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "client-identity"},
)
async def logout_client(request: Request, response: Response) -> Response:
    runtime, scope = await _write_scope(request, "client")
    await revoke_session(runtime, scope, target_id=scope.session_id)
    result = Response(status_code=204)
    if scope.transport == "web":
        result.delete_cookie(
            "haruka_client_session", path="/api/v1", secure=True, httponly=True, samesite="strict"
        )
    return result


@router.post(
    "/admin/auth/logout",
    operation_id="logout_admin",
    status_code=204,
    response_model=None,
    response_class=Response,
    responses=COMMON,
    openapi_extra={"x-haruka-access": "admin-identity"},
)
async def logout_admin(request: Request) -> Response:
    runtime, scope = await _write_scope(request, "admin")
    await revoke_session(runtime, scope, target_id=scope.session_id)
    result = Response(status_code=204)
    result.delete_cookie(
        "haruka_admin_session", path="/api/v1/admin", secure=True, httponly=True, samesite="strict"
    )
    return result
