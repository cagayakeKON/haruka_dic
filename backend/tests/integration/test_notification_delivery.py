"""Real isolated Kafka ACK boundaries and old committed Outbox recovery."""

import asyncio
import hashlib
import json
from collections.abc import Awaitable, Callable
from concurrent.futures import Future
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol, cast
from uuid import UUID, uuid4

import pytest
from confluent_kafka.admin import AdminClient
from confluent_kafka.cimpl import NewTopic
from sqlalchemy import event as sql_event
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.adapters.queue import KafkaConsumer, KafkaProducer, KafkaRecord
from app.bootstrap import Runtime
from app.core.settings import load_settings
from app.maintenance.settings import MaintenanceSettings
from app.models import AiRun, ExternalCallAttempt, Library, OutboxEvent
from app.models.model_tasks import InboxEvent
from app.models.user_notifications import UserNotification
from app.services.material_jobs import execute_source_job
from app.services.model_worker import run_worker
from app.services.notification_delivery import recover_notifications
from app.services.notification_events import CONSUMER_NAME, canonical_envelope
from app.services.outbox_delivery import deliver_model_event
from tests.integration.test_material_source_boundaries import accepted_source, source_runtime
from tests.integration.test_notification_events import source_event
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
ROOT = Path(__file__).resolve().parents[3]
assert source_runtime


class KafkaAdmin(Protocol):
    def create_topics(self, new_topics: list[NewTopic]) -> dict[str, Future[object]]: ...
    def delete_topics(self, topics: list[str]) -> dict[str, Future[object]]: ...


async def test_real_kafka_atomic_ack_canonical_replay_and_published_backfill(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    original_resources = runtime.resources
    configuration = (
        load_settings(ROOT / "dev/.local/test.env")
        .infrastructure()
        .model_copy(update={"namespace": runtime.settings.instance_id})
    )
    topic = runtime.settings.instance_id + ".jobs"
    assert topic == "haruka-test-" + run_id + ".jobs"
    admin = cast(
        KafkaAdmin, AdminClient({"bootstrap.servers": configuration.kafka_bootstrap_servers})
    )
    await asyncio.to_thread(
        lambda: admin.create_topics([NewTopic(topic, num_partitions=1, replication_factor=1)])[
            topic
        ].result(15)
    )
    producer = KafkaProducer(configuration)
    group = runtime.settings.instance_id + ".notification-consumer"
    consumer = KafkaConsumer(configuration, group=group)
    runtime.resources = replace(original_resources, kafka=producer, consumer=consumer)
    acknowledged: list[int] = []
    try:
        async for web, headers in _owner(
            runtime, maintenance, f"notify-kafka-{run_id}@haruka.example.test"
        ):
            material_id, job_id = await accepted_source(
                runtime, web, headers, "これは日本語の小説です。".encode()
            )
            await execute_source_job(runtime, job_id, "notification-kafka-source")
            first = await source_event(runtime, job_id)
            wire = canonical_envelope(first)
            # Simulate the old consumer receipt only; the new Inbox stays absent.
            async with runtime.resources.database.sessions() as session, session.begin():
                session.add(
                    InboxEvent(
                        consumer_name="model-worker",
                        event_id=first.id,
                        payload_digest=hashlib.sha256(json.dumps(wire).encode()).digest(),
                        processed_at=datetime.now(UTC),
                    )
                )
            await producer.publish(
                topic,
                key=str(first.id).encode(),
                value=json.dumps(wire, indent=2, sort_keys=True).encode(),
            )

            original_ack = consumer.acknowledge

            async def no_ack(
                record: KafkaRecord,
                *,
                acknowledge: Callable[[KafkaRecord], Awaitable[None]] = original_ack,
            ) -> None:
                acknowledged.append(record.offset)
                await acknowledge(record)

            monkeypatch.setattr(consumer, "acknowledge", no_ack)

            def refuse_notification(session: Session, _context: object, _instances: object) -> None:
                if any(isinstance(item, UserNotification) for item in session.new):
                    raise RuntimeError("controlled consumer commit failure")

            sql_event.listen(Session, "before_flush", refuse_notification)
            try:
                with pytest.raises(RuntimeError, match="controlled consumer commit failure"):
                    async with asyncio.timeout(20):
                        while True:
                            await run_worker(runtime, asyncio.Event(), once=True)
            finally:
                sql_event.remove(Session, "before_flush", refuse_notification)
            assert acknowledged == []
            async with runtime.resources.database.sessions() as session:
                assert await session.scalar(select(func.count()).select_from(UserNotification)) == 0
                assert await session.scalar(select(func.sum(Library.notification_sequence))) == 0
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(InboxEvent)
                        .where(InboxEvent.consumer_name == CONSUMER_NAME)
                    )
                    == 0
                )
            # Restart the real group before committing an offset; its pending
            # record must still produce exactly one business+Inbox commit.
            await consumer.aclose()
            consumer = KafkaConsumer(configuration, group=group)
            runtime.resources = replace(original_resources, kafka=producer, consumer=consumer)
            actual_ack = consumer.acknowledge

            async def committed_ack(
                record: KafkaRecord,
                *,
                acknowledge: Callable[[KafkaRecord], Awaitable[None]] = actual_ack,
            ) -> None:
                assert runtime.resources is not None
                if record.value:
                    event_id = UUID(json.loads(record.value)["event_id"])
                    async with runtime.resources.database.sessions() as session:
                        inbox = await session.scalar(
                            select(InboxEvent).where(
                                InboxEvent.consumer_name == CONSUMER_NAME,
                                InboxEvent.event_id == event_id,
                            )
                        )
                        assert inbox is not None
                await acknowledge(record)
                acknowledged.append(record.offset)

            monkeypatch.setattr(consumer, "acknowledge", committed_ack)
            async with asyncio.timeout(20):
                while not acknowledged:
                    await run_worker(runtime, asyncio.Event(), once=True)
            await producer.publish(
                topic,
                key=str(first.id).encode(),
                value=json.dumps(wire, separators=(",", ":")).encode(),
            )
            async with asyncio.timeout(10):
                while len(acknowledged) < 2:
                    await run_worker(runtime, asyncio.Event(), once=True)
            assert acknowledged[0] != acknowledged[1]
            reused = await web.post(
                "/api/v1/material-imports",
                json={
                    "material_type": "textbook",
                    "language": "ja",
                    "source_material_id": str(material_id),
                },
                headers={**headers, "Idempotency-Key": str(uuid4())},
            )
            assert reused.status_code == 201
            second_job = UUID(reused.json()["data"]["job_id"])
            await execute_source_job(runtime, second_job, "notification-kafka-second")
            second = await source_event(runtime, second_job)
            # Use the actual publisher to establish the historical published row;
            # do not prefill the notification or its consumer receipt.
            for _ in range(8):
                async with runtime.resources.database.sessions() as session:
                    published = await session.get(OutboxEvent, second.id)
                    assert published is not None
                    if published.status == "published":
                        break
                assert await deliver_model_event(runtime)
            else:
                pytest.fail("bounded source publisher did not publish the second outcome")
            assert await recover_notifications(runtime, limit=1) == 1
            assert await recover_notifications(runtime, limit=1) == 0
            async with runtime.resources.database.sessions() as session:
                assert await session.scalar(select(func.count()).select_from(UserNotification)) == 2
                assert await session.scalar(select(func.sum(Library.notification_sequence))) == 2
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(InboxEvent)
                        .where(InboxEvent.consumer_name == CONSUMER_NAME)
                    )
                    == 2
                )
                assert await session.scalar(select(func.count()).select_from(AiRun)) == 0
                assert (
                    await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
                )
    finally:
        await consumer.aclose()
        await producer.aclose()
        runtime.resources = original_resources
        await asyncio.to_thread(lambda: admin.delete_topics([topic])[topic].result(15))
