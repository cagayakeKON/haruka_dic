"""Append-only, allowlisted identity events sharing the audit/outbox chain."""

from typing import Literal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.correlation import current_correlation
from app.models import AdminAuditEvent, OutboxEvent

IdentityAction = Literal[
    "account.registered",
    "email.verified",
    "password.recovered",
    "password.changed",
    "session.created",
    "session.revoked",
    "refresh.replayed",
    "auth.login.denied",
]


async def append_identity_event(
    session: AsyncSession,
    *,
    action: IdentityAction,
    authorization_revision: int,
    actor: Literal[
        "public-registration",
        "email-challenge",
        "password-recovery",
        "authenticated-user",
        "identity-service",
    ],
    actor_user_id: UUID | None,
    audience: Literal["client", "admin"] | None,
    target_type: Literal["user", "session", "challenge", "login"],
    target_id: UUID | None,
    result: Literal["accepted", "committed", "denied", "failed"],
    reason_code: str | None = None,
    request_id: UUID | None = None,
    operation_id: UUID | None = None,
    outbox: bool = True,
) -> None:
    current_request, current_operation = current_correlation()
    event = AdminAuditEvent(
        action=action,
        actor=actor,
        actor_user_id=actor_user_id,
        audience=audience,
        target_type=target_type,
        target_id=target_id,
        target_user_id=target_id if target_type == "user" else None,
        result=result,
        reason_code=reason_code,
        request_id=request_id or current_request,
        operation_id=operation_id or current_operation,
        payload_schema_version=1,
        authorization_revision=authorization_revision,
    )
    session.add(event)
    await session.flush()
    if outbox:
        session.add(
            OutboxEvent(
                event_type="identity.security",
                audit_event_id=event.id,
                authorization_revision=authorization_revision,
                status="pending",
            )
        )
