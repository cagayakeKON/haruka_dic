"""Kafka business consumption with persistent inbox and bounded recovery scan."""

import asyncio
import hashlib
import json
import logging
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import select

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.models.model_tasks import InboxEvent, Job
from app.services.model_tasks import execute_job

logger = logging.getLogger(__name__)


async def run_worker(runtime: Runtime, stop: asyncio.Event, *, once: bool = False) -> None:
    resources = runtime.resources
    if resources is None or resources.consumer is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    consumer = resources.consumer
    await consumer.subscribe(runtime.settings.instance_id + ".jobs")
    worker = str(uuid4())
    while not stop.is_set():
        record = await consumer.read()
        if record and record.value:
            envelope = json.loads(record.value)
            event_id = UUID(envelope["event_id"])
            payload_digest = hashlib.sha256(record.value).digest()
            async with resources.database.sessions() as session:
                old = await session.scalar(
                    select(InboxEvent).where(
                        InboxEvent.consumer_name == "model-worker", InboxEvent.event_id == event_id
                    )
                )
                if old and old.payload_digest != payload_digest:
                    raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
            if old is None:
                if envelope["event_type"] == "model.job.accepted":
                    await execute_job(
                        runtime,
                        UUID(envelope["payload"]["job_id"]),
                        worker,
                        inbox=(event_id, payload_digest),
                    )
                async with resources.database.sessions() as session, session.begin():
                    # Unique event identity is committed before broker ACK.
                    old = await session.scalar(
                        select(InboxEvent).where(
                            InboxEvent.consumer_name == "model-worker",
                            InboxEvent.event_id == event_id,
                        )
                    )
                    if old is None:
                        session.add(
                            InboxEvent(
                                consumer_name="model-worker",
                                event_id=event_id,
                                payload_digest=payload_digest,
                                processed_at=datetime.now(UTC),
                            )
                        )
            await consumer.acknowledge(record)
        async with resources.database.sessions() as session:
            due = list(
                await session.scalars(
                    select(Job.id)
                    .where(
                        Job.state.in_(("running", "cancel_requested")),
                        Job.lease_expires_at <= datetime.now(UTC),
                    )
                    .limit(4)
                )
            )
        for identifier in due:
            await execute_job(runtime, identifier, worker)
        if once:
            return
