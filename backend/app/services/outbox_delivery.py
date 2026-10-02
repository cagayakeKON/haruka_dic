"""Retryable Redis invalidation for committed authorization and identity events."""

import json
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.models import AdminAuditEvent, AuthSession, OutboxEvent

logger = logging.getLogger(__name__)

_INVALIDATE = """
local previous = tonumber(redis.call('GET', KEYS[1]) or '0')
local revision = tonumber(ARGV[1])
if not revision then return redis.error_reply('invalid revision') end
if revision > previous then redis.call('SET', KEYS[1], ARGV[1]) end
for index = 2, #KEYS do redis.call('DEL', KEYS[index]) end
return 1
"""


async def deliver_outbox_one(runtime: Runtime) -> bool:
    """Apply one idempotent cache invalidation before marking its PG row published.

    A crash after Redis but before PG commit leaves a pending row; replay is safe.
    The database remains authoritative while invalidation is pending.
    """
    resources = runtime.resources
    if resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if await deliver_model_event(runtime):
        return True
    try:
        async with resources.database.sessions() as session, session.begin():
            event = await session.scalar(
                select(OutboxEvent)
                .where(
                    OutboxEvent.status == "pending",
                    ~OutboxEvent.event_type.like("model.%"),
                    ~OutboxEvent.event_type.like("material.%"),
                )
                .order_by(OutboxEvent.created_at, OutboxEvent.id)
                .limit(1)
                .with_for_update(skip_locked=True)
            )
            if event is None:
                return False
            audit = await session.get(AdminAuditEvent, event.audit_event_id)
            if (
                audit is None
                or event.authorization_revision is None
                or audit.authorization_revision != event.authorization_revision
            ):
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            session_ids = []
            if audit.action in {"password.changed", "password.recovered"}:
                if audit.target_type != "user" or audit.target_id is None:
                    raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
                session_ids = (
                    await session.scalars(
                        select(AuthSession.id).where(
                            AuthSession.user_id == audit.target_id,
                            AuthSession.revoked_at.is_not(None),
                        )
                    )
                ).all()
                owner = audit.target_id
            elif audit.action == "session.revoked":
                if audit.target_type == "user" and audit.target_id is not None:
                    owner = audit.target_id
                    session_ids = (
                        await session.scalars(
                            select(AuthSession.id).where(
                                AuthSession.user_id == owner,
                                AuthSession.revoked_at.is_not(None),
                            )
                        )
                    ).all()
                elif audit.target_type == "session" and audit.target_id is not None:
                    owner = await session.scalar(
                        select(AuthSession.user_id).where(
                            AuthSession.id == audit.target_id,
                            AuthSession.revoked_at.is_not(None),
                        )
                    )
                    if owner is None:
                        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
                    session_ids = [audit.target_id]
                else:
                    raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            else:
                owner = None
            keys = [resources.cache.key("authz", "revision")]
            if owner is not None:
                keys.extend(
                    resources.cache.key("auth", str(owner), str(session_id), "alive")
                    for session_id in session_ids
                )
            result = await resources.cache.client.eval(
                _INVALIDATE, len(keys), *keys, event.authorization_revision
            )
            if result != 1:
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            event.status = "published"
            logger.info("outbox.identity.published")
            return True
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def deliver_model_event(runtime: Runtime) -> bool:
    resources = runtime.resources
    if resources is None or resources.kafka is None:
        return False
    now = datetime.now(UTC)
    async with resources.database.sessions() as session, session.begin():
        event = await session.scalar(
            select(OutboxEvent)
            .where(
                OutboxEvent.status == "pending",
                or_(
                    OutboxEvent.event_type.like("model.%"),
                    OutboxEvent.event_type.like("material.%"),
                ),
                or_(
                    OutboxEvent.delivery_lease_until.is_(None),
                    OutboxEvent.delivery_lease_until <= now,
                ),
            )
            .order_by(OutboxEvent.created_at, OutboxEvent.id)
            .limit(1)
            .with_for_update(skip_locked=True)
        )
        if event is None:
            return False
        event.delivery_fence += 1
        event.delivery_lease_until = now + timedelta(seconds=120)
        event.updated_at = now
        identifier, fence = event.id, event.delivery_fence
        envelope = {
            "event_id": str(event.id),
            "event_type": event.event_type,
            "payload": event.payload,
        }
    # Kafka publication happens outside the PG claim transaction. A process
    # crash leaves a replayable event identity rather than an unbounded row lock.
    await resources.kafka.publish(
        runtime.settings.instance_id + ".jobs",
        key=str(identifier).encode(),
        value=json.dumps(envelope).encode(),
    )
    async with resources.database.sessions() as session, session.begin():
        event = await session.get(OutboxEvent, identifier, with_for_update=True)
        if event and event.status == "pending" and event.delivery_fence == fence:
            event.status = "published"
            event.delivery_lease_until = None
            event.updated_at = datetime.now(UTC)
    logger.info("outbox.model.published")
    return True
