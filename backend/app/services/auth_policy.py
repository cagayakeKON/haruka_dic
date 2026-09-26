"""Read the authoritative registration policy without exposing mail credentials."""

import logging
from datetime import UTC, datetime
from typing import Literal, cast
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
from app.domain.errors import AppError
from app.models import (
    AdminAuditEvent,
    AuthPolicy,
    OutboxEvent,
    PermissionCatalog,
    Role,
    RolePermission,
)
from app.repositories.identity import (
    current_user_for_update,
    global_revision_for_update,
    registration_policy,
)
from app.schemas.auth import AdminAuthPolicyRead, AdminAuthPolicyUpdate, AuthPolicyRead
from app.services.auth_context import ScopeContext, verify_scope_in_transaction

_LOGGER = logging.getLogger(__name__)


def mail_ready(runtime: Runtime) -> bool:
    settings = runtime.settings
    return bool(
        settings.mail_delivery_enabled
        and settings.smtp_host
        and settings.smtp_from
        and settings.auth_digest_key
        and settings.mail_encryption_key
    )


async def read_public_policy(runtime: Runtime) -> AuthPolicyRead:
    if not runtime.ready or runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        async with runtime.resources.database.sessions() as session:
            policy = await _registration_policy(session)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    enabled = mail_ready(runtime)
    return AuthPolicyRead(
        registration_enabled=policy.registration_mode == "open" and enabled,
        recovery_enabled=policy.recovery_mode == "email" and enabled,
        action_link_base_url=runtime.settings.public_base_url,
        password_min_length=15,
        password_max_length=128,
    )


async def _registration_policy(session: AsyncSession) -> AuthPolicy:
    policy = await registration_policy(session)
    if (
        policy is None
        or policy.registration_mode not in {"closed", "open"}
        or not policy.require_email_verification
        or policy.recovery_mode != "email"
    ):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return policy


def _admin_view(policy: AuthPolicy) -> AdminAuthPolicyRead:
    return AdminAuthPolicyRead(
        registration_mode=cast(Literal["closed", "open"], policy.registration_mode),
        registration_enabled=policy.registration_mode == "open",
        revision=policy.revision,
    )


async def read_admin_policy(runtime: Runtime, scope: ScopeContext) -> AdminAuthPolicyRead:
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        async with runtime.resources.database.sessions() as session:
            await verify_scope_in_transaction(
                session,
                user_id=scope.user_id,
                session_id=scope.session_id,
                audience="admin",
                transport="web",
                permissions=("admin.auth_policy.read",),
            )
            policy = await _registration_policy(session)
            return _admin_view(policy)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def update_admin_policy(
    runtime: Runtime, scope: ScopeContext, payload: AdminAuthPolicyUpdate
) -> AdminAuthPolicyRead:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if payload.registration_mode == "open" and not mail_ready(runtime):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        async with resources.database.sessions() as session, session.begin():
            revision = await global_revision_for_update(session)
            user = await current_user_for_update(session, scope)
            if revision is None or user is None:
                raise AppError(ErrorCode.SESSION_INVALID)
            await verify_scope_in_transaction(
                session,
                user_id=scope.user_id,
                session_id=scope.session_id,
                audience="admin",
                transport="web",
                permissions=("admin.auth_policy.update",),
            )
            policy = await registration_policy(session, for_update=True)
            if (
                policy is None
                or not policy.require_email_verification
                or policy.recovery_mode != "email"
            ):
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            if policy.revision != payload.expected_revision:
                raise AppError(ErrorCode.REVISION_CONFLICT)
            if payload.registration_mode == "open":
                # The public role remains non-protected and client-only at the point of opening.
                await validate_public_registration_role(session, policy.default_role_id)
            if policy.registration_mode == payload.registration_mode:
                return _admin_view(policy)
            policy.registration_mode = payload.registration_mode
            policy.revision += 1
            policy.updated_at = datetime.now(UTC)
            revision.revision += 1
            request_id, operation_id = current_correlation()
            audit = AdminAuditEvent(
                action="auth_policy.updated",
                actor="authenticated-admin",
                actor_user_id=scope.user_id,
                audience="admin",
                permission_code="admin.auth_policy.update",
                target_type="auth_policy",
                target_code="registration",
                result="committed",
                payload_schema_version=1,
                change_summary={"registration_mode": payload.registration_mode},
                request_id=request_id,
                operation_id=operation_id,
                authorization_revision=revision.revision,
            )
            session.add(audit)
            await session.flush()
            session.add(
                OutboxEvent(
                    event_type="authorization.changed",
                    audit_event_id=audit.id,
                    authorization_revision=revision.revision,
                    status="pending",
                )
            )
            result = _admin_view(policy)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    request_id, operation_id = current_correlation()
    _LOGGER.info(
        "auth.policy.updated",
        extra={
            "request_id": request_id,
            "operation_id": operation_id,
            "user_id": scope.user_id,
            "audience": "admin",
        },
    )
    return result


async def validate_public_registration_role(session: AsyncSession, role_id: UUID) -> Role:
    role = await session.scalar(select(Role).where(Role.id == role_id).with_for_update())
    if role is None or not role.enabled or role.protected:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    grants = (
        await session.execute(
            select(
                RolePermission.permission_code, RolePermission.effect, RolePermission.data_scope
            ).where(RolePermission.role_id == role.id)
        )
    ).all()
    if ("client.login", "allow", "self") not in grants:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    codes = {code for code, _, _ in grants}
    catalog = {
        entry.code: entry
        for entry in (
            await session.scalars(
                select(PermissionCatalog).where(PermissionCatalog.code.in_(codes))
            )
        ).all()
    }
    if any(
        code not in catalog
        or catalog[code].audience != "client"
        or catalog[code].data_scope != "self"
        or not catalog[code].enabled
        or scope != "self"
        for code, _, scope in grants
    ):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if ("client.login", "deny", "self") in grants:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return role
