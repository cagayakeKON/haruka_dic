"""Real owned Kafka dispatch/replay and durable no-model source lease recovery."""

import asyncio
import json
from concurrent.futures import Future
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol, cast
from uuid import UUID, uuid4

import pytest
from confluent_kafka.admin import AdminClient
from confluent_kafka.cimpl import NewTopic
from sqlalchemy import func, select

from app.adapters.queue import KafkaConsumer, KafkaProducer, KafkaRecord
from app.bootstrap import Runtime
from app.core.settings import load_settings
from app.maintenance.settings import MaintenanceSettings
from app.models import AiRun, ExternalCallAttempt, Job, OutboxEvent
from app.models.model_tasks import InboxEvent
from app.services.model_worker import run_worker
from app.services.outbox_delivery import deliver_model_event
from tests.integration.test_material_source_boundaries import accepted_source, source_runtime
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
ROOT = Path(__file__).resolve().parents[3]
# The imported fixture owns the isolated PG/MinIO lifecycle for this module.
assert source_runtime


class KafkaAdmin(Protocol):
    def create_topics(self, new_topics: list[NewTopic]) -> dict[str, Future[object]]: ...
    def delete_topics(self, topics: list[str]) -> dict[str, Future[object]]: ...


async def test_real_kafka_source_dispatch_replay_and_expired_lease_recovery(
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
    consumer = KafkaConsumer(configuration, group=runtime.settings.instance_id + ".source-consumer")
    runtime.resources = replace(original_resources, kafka=producer, consumer=consumer)
    acknowledged: list[int] = []
    actual_ack = consumer.acknowledge

    async def record_ack(record: KafkaRecord) -> None:
        await actual_ack(record)
        acknowledged.append(record.offset)

    monkeypatch.setattr(consumer, "acknowledge", record_ack)
    try:
        async for web, headers in _owner(
            runtime, maintenance, f"source-kafka-{run_id}@haruka.example.test"
        ):
            material_id, job_id = await accepted_source(
                runtime, web, headers, "これは日本語の小説です。今日はとてもいい天気です。".encode()
            )
            assert await deliver_model_event(runtime)
            async with runtime.resources.database.sessions() as session:
                event = await session.scalar(
                    select(OutboxEvent).where(OutboxEvent.event_type == "material.job.accepted")
                )
                assert event is not None and event.status == "published"
                event_id = event.id
                envelope = {
                    "event_id": str(event.id),
                    "event_type": event.event_type,
                    "payload": event.payload,
                }
            async with asyncio.timeout(20):
                while not acknowledged:
                    await run_worker(runtime, asyncio.Event(), once=True)
            state = (await web.get(f"/api/v1/jobs/{job_id}")).json()["data"]
            assert state["state"] == "succeeded" and state["credential_id"] is None
            await producer.publish(
                topic, key=str(event_id).encode(), value=json.dumps(envelope).encode()
            )
            async with asyncio.timeout(10):
                while len(acknowledged) < 2:
                    await run_worker(runtime, asyncio.Event(), once=True)
            assert acknowledged[0] != acknowledged[1]
            assert (await web.get(f"/api/v1/jobs/{job_id}")).json()["data"] == state
            reused = await web.post(
                "/api/v1/material-imports",
                json={
                    "material_type": "textbook",
                    "language": "ja",
                    "source_material_id": str(material_id),
                },
                headers={**headers, "Idempotency-Key": str(uuid4())},
            )
            assert reused.status_code == 201, reused.text
            recovered_id = UUID(reused.json()["data"]["job_id"])
            # Only prepare a durable abandoned lease; the real Worker must perform
            # validation/publication through its operation-aware recovery scan.
            async with runtime.resources.database.sessions() as session, session.begin():
                abandoned = await session.get(Job, recovered_id, with_for_update=True)
                assert abandoned is not None and abandoned.state == "queued"
                abandoned.state, abandoned.lease_owner = "running", "abandoned-source-worker"
                abandoned.fence = 1
                abandoned.lease_expires_at = datetime.now(UTC) - timedelta(seconds=1)
                abandoned.heartbeat_at = abandoned.updated_at = datetime.now(UTC)
            await run_worker(runtime, asyncio.Event(), once=True)
            assert (await web.get(f"/api/v1/jobs/{recovered_id}")).json()["data"][
                "state"
            ] == "succeeded"
            async with runtime.resources.database.sessions() as session:
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(InboxEvent)
                        .where(
                            InboxEvent.event_id == event_id,
                            InboxEvent.consumer_name == "model-worker",
                        )
                    )
                    == 1
                )
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(OutboxEvent)
                        .where(OutboxEvent.event_type == "material.import.completed")
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
