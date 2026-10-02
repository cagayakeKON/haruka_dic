"""Bounded replay of committed source outcomes using the notification Inbox."""

from sqlalchemy import exists, select

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.models import OutboxEvent
from app.models.model_tasks import InboxEvent
from app.services.notification_events import CONSUMER_NAME, EVENT_TYPES, consume_event


async def recover_notifications(runtime: Runtime, *, limit: int = 20) -> int:
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if not 1 <= limit <= 20:
        raise ValueError("notification recovery batch must be between one and twenty")
    async with runtime.resources.database.sessions() as session:
        identifiers = list(
            await session.scalars(
                select(OutboxEvent.id)
                .where(
                    OutboxEvent.event_type.in_(EVENT_TYPES),
                    OutboxEvent.status.in_(("pending", "published")),
                    ~exists().where(
                        InboxEvent.consumer_name == CONSUMER_NAME,
                        InboxEvent.event_id == OutboxEvent.id,
                    ),
                )
                .order_by(OutboxEvent.created_at, OutboxEvent.id)
                .limit(limit)
            )
        )
    created = 0
    for identifier in identifiers:
        created += int(await consume_event(runtime, identifier))
    return created
