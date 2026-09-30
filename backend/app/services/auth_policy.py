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
    global_revision_for_update,
    registration_policy,
)
from app.schemas.auth import AdminAuthPolicyRead, AdminAuthPolicyUpdate, AuthPolicyRead
from app.services.auth_context import ScopeContext, require_permissions, verify_scope_in_transaction

_LOGGER = logging.getLogger(__name__)
RECOVERY_MODES = frozenset({"disabled", "email", "manual", "email_or_manual"})
EMAIL_RECOVERY_MODES = frozenset({"email", "email_or_manual"})
MANUAL_RECOVERY_MODES = frozenset({"manual", "email_or_manual"})
RecoveryMode = Literal["disabled", "email", "manual", "email_or_manual"]


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
    offered = policy.registration_mode in {"open", "approval"}
    mode = cast(RecoveryMode, policy.recovery_mode)
    return AuthPolicyRead(
        registration_enabled=offered and enabled,
        approval_required=policy.registration_mode == "approval",
        recovery_enabled=mode in MANUAL_RECOVERY_MODES
        or (mode in EMAIL_RECOVERY_MODES and enabled),
        recovery_mode=mode,
        action_link_base_url=runtime.settings.public_base_url,
        password_min_length=15,
        password_max_length=128,
    )


async def _registration_policy(session: AsyncSession) -> AuthPolicy:
    policy = await registration_policy(session)
    if (
        policy is None
        or policy.registration_mode not in {"closed", "approval", "open"}
        or not policy.require_email_verification
        or policy.recovery_mode not in RECOVERY_MODES
    ):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return policy


def _admin_view(policy: AuthPolicy) -> AdminAuthPolicyRead:
    mode = cast(Literal["closed", "approval", "open"], policy.registration_mode)
    recovery = cast(RecoveryMode, policy.recovery_mode)
    return AdminAuthPolicyRead(
        registration_mode=mode,
        registration_enabled=mode != "closed",
        recovery_mode=recovery,
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


async def write_admin_policy(
    session: AsyncSession,
    scope: ScopeContext,
    payload: AdminAuthPolicyUpdate,
    *,
    mail_available: bool,
) -> AdminAuthPolicyRead:
    if (
        payload.registration_mode in {"open", "approval"}
        or payload.recovery_mode in EMAIL_RECOVERY_MODES
    ) and not mail_available:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    revision = await global_revision_for_update(session)
    if revision is None:
        raise AppError(ErrorCode.SESSION_INVALID)
    await require_permissions(
        session, user_id=scope.user_id, audience="admin", codes=("admin.auth_policy.update",)
    )
    policy = await registration_policy(session, for_update=True)
    if (
        policy is None
        or not policy.require_email_verification
        or policy.registration_mode not in {"closed", "approval", "open"}
        or policy.recovery_mode not in RECOVERY_MODES
    ):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if policy.revision != payload.expected_revision:
        raise AppError(ErrorCode.REVISION_CONFLICT)
    next_recovery = payload.recovery_mode or policy.recovery_mode
    registration_changed = policy.registration_mode != payload.registration_mode
    recovery_changed = policy.recovery_mode != next_recovery
    if not registration_changed and not recovery_changed:
        return _admin_view(policy)
    if registration_changed and payload.registration_mode in {"open", "approval"}:
        # The public role remains non-protected and client-only at the point of opening.
        await validate_public_registration_role(session, policy.default_role_id)
    # Existing accounts, approval snapshots, and in-flight challenges stay as stored.
    policy.registration_mode = payload.registration_mode
    policy.recovery_mode = next_recovery
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
        change_summary={
            "registration_mode": payload.registration_mode,
            "recovery_mode": next_recovery,
        },
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
    return _admin_view(policy)


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
