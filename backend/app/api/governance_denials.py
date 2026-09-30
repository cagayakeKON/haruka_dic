"""Persist governance authorization refusal after the business transaction rolls back."""

import logging
from typing import cast
from uuid import UUID

from fastapi import Request
from fastapi.routing import APIRoute
from sqlalchemy import select

from app.bootstrap import Runtime
from app.domain.correlation import current_correlation
from app.domain.scope import ScopeContext
from app.models import AdminAuditEvent, AuthorizationRevision, OutboxEvent, User

logger = logging.getLogger(__name__)


async def record_governance_denial(request: Request) -> None:
    route = request.scope.get("route")
    if not isinstance(route, APIRoute):
        return
    if not set(route.tags) & {
        "role-governance",
        "user-governance",
        "menu-governance",
        "audit-governance",
    } and route.operation_id not in {"update_admin_auth_policy", "get_admin_auth_policy"}:
        return
    runtime: object = getattr(request.app.state, "runtime", None)
    scope: object = getattr(request.state, "authenticated_scope", None)
    if (
        not isinstance(runtime, Runtime)
        or runtime.resources is None
        or not isinstance(scope, ScopeContext)
        or scope.audience != "admin"
        or getattr(request.state, "governance_denial_recorded", False)
    ):
        return
    request.state.governance_denial_recorded = True
    permission: object = getattr(request.state, "governance_permission", None)
    if not isinstance(permission, str):
        listed: object = (route.openapi_extra or {}).get("x-haruka-permissions", ())
        items = cast(list[object], listed) if isinstance(listed, list) else []
        permission = items[0] if len(items) == 1 else None
    target_type = "auth_policy" if route.path.endswith("/auth-policy") else "governance"
    target_id = None
    for parameter, kind in (("user_id", "user"), ("role_id", "role"), ("menu_id", "menu")):
        raw: object = request.path_params.get(parameter)
        if isinstance(raw, (str, UUID)):
            try:
                target_id = UUID(str(raw))
                target_type = kind
            except ValueError:
                pass
            break
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            revision = await session.scalar(
                select(AuthorizationRevision)
                .where(AuthorizationRevision.code == "global")
                .with_for_update()
            )
            actor = await session.get(User, scope.user_id, with_for_update=True)
            if revision is None or actor is None:
                return
            request_id, operation_id = current_correlation()
            event = AdminAuditEvent(
                action="authorization.denied",
                actor="authenticated-admin",
                actor_user_id=scope.user_id,
                audience="admin",
                permission_code=permission if isinstance(permission, str) else None,
                target_type=target_type,
                target_id=target_id,
                target_code="registration" if target_type == "auth_policy" else None,
                result="denied",
                reason_code="PERMISSION_DENIED",
                payload_schema_version=1,
                authorization_revision=revision.revision,
                request_id=request_id,
                operation_id=operation_id,
                change_summary={"method": request.method, "operation": route.operation_id},
            )
            session.add(event)
            await session.flush()
            session.add(
                OutboxEvent(
                    event_type="identity.security",
                    audit_event_id=event.id,
                    authorization_revision=revision.revision,
                    status="pending",
                )
            )
        logger.info("authz.denied")
    except Exception:
        # No exception/SQL/payload detail is permitted in this fallback.
        logger.error("http.failed")
