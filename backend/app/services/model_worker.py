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
from app.maintenance.material_source_gc import collect_source_garbage
from app.models.model_tasks import InboxEvent, Job
from app.services.material_jobs import execute_source_job
from app.services.model_tasks import execute_job
from app.services.notification_delivery import recover_notifications
from app.services.notification_events import EVENT_TYPES, consume_event

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
            await dispatch_record(runtime, record.value, worker)
            await consumer.acknowledge(record)
        async with resources.database.sessions() as session:
            due = list(
                (
                    await session.execute(
                        select(Job.id, Job.operation_kind)
                        .where(
                            Job.state.in_(("running", "cancel_requested")),
                            Job.lease_expires_at <= datetime.now(UTC),
                        )
                        .limit(4)
                    )
                ).all()
            )
        for identifier, operation in due:
            if operation == "material_import":
                await execute_source_job(runtime, identifier, worker)
            elif operation == "credential_test":
                await execute_job(runtime, identifier, worker)
        await collect_source_garbage(runtime)
        await recover_notifications(runtime)
        if once:
            return


async def dispatch_record(runtime: Runtime, value: bytes, worker: str) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    envelope = json.loads(value)
    event_id = UUID(envelope["event_id"])
    if envelope["event_type"] in EVENT_TYPES:
        # The independent PG digest/Inbox bypasses every legacy model-worker ACK.
        await consume_event(runtime, event_id, envelope)
        return
    payload_digest = hashlib.sha256(value).digest()
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
        elif envelope["event_type"] == "material.job.accepted":
            await execute_source_job(
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
