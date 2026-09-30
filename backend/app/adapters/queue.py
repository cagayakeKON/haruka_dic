"""Confluent Kafka clients with bounded, serialized SDK calls and explicit ownership."""

import logging
from dataclasses import dataclass
from functools import partial
from typing import Protocol, runtime_checkable

from confluent_kafka import Consumer, KafkaError, Message, Producer

from app.adapters.blocking import BlockingClient
from app.core.settings import InfrastructureSettings

logger = logging.getLogger(__name__)


@runtime_checkable
class _ProducerClose(Protocol):
    # The official 2.15.1 C extension provides close(), but cimpl.pyi omits it.
    # Keep that exact SDK boundary checked at runtime instead of suppressing types.
    def close(self) -> bool: ...


def client_configuration(settings: InfrastructureSettings) -> dict[str, object]:
    return {
        "bootstrap.servers": settings.kafka_bootstrap_servers,
        "client.id": settings.namespace,
        "socket.timeout.ms": 3000,
        "socket.connection.setup.timeout.ms": 3000,
        "logger": logger,
    }


def validate_topic(namespace: str, topic: str) -> None:
    if not topic.startswith(f"{namespace}.") or len(topic) > 249:
        raise ValueError("topic must belong to this environment")


class KafkaProducer:
    def __init__(self, settings: InfrastructureSettings) -> None:
        self.namespace = settings.namespace
        self._client = Producer(
            {
                **client_configuration(settings),
                "enable.idempotence": True,
                "acks": "all",
                "message.timeout.ms": 5000,
                "queue.buffering.max.messages": 1000,
            }
        )
        self._lane = BlockingClient("kafka-producer")

    async def check(self) -> None:
        metadata: object = await self._lane.call(partial(self._client.list_topics, timeout=5))
        if metadata is None:
            raise RuntimeError("Kafka metadata probe failed")

    async def publish(self, topic: str, *, key: bytes, value: bytes) -> None:
        """Transport only. The future Outbox owns durable acceptance and recovery."""
        validate_topic(self.namespace, topic)

        def send() -> None:
            delivered = False

            def on_delivery(error: KafkaError | None, _message: Message) -> None:
                nonlocal delivered
                delivered = error is None

            self._client.produce(topic, key=key, value=value, on_delivery=on_delivery)
            remaining = self._client.flush(6)
            if remaining or not delivered:
                raise RuntimeError("Kafka delivery failed or remains uncertain")

        await self._lane.call(send)

    async def aclose(self) -> None:
        def close() -> None:
            try:
                if self._client.flush(6):
                    self._client.purge()
                    self._client.poll(0)
                    raise RuntimeError("Kafka shutdown has undelivered records")
            finally:
                if not isinstance(self._client, _ProducerClose):
                    raise RuntimeError("Kafka SDK does not support explicit close")
                self._client.close()

        await self._lane.close(close)


@dataclass(frozen=True)
class KafkaRecord:
    key: bytes | None
    value: bytes | None
    topic: str
    partition: int
    offset: int


class KafkaConsumer:
    def __init__(self, settings: InfrastructureSettings, *, group: str) -> None:
        if not group.startswith(f"{settings.namespace}."):
            raise ValueError("consumer group must belong to this environment")
        self.namespace = settings.namespace
        self._client = Consumer(
            {
                **client_configuration(settings),
                "group.id": group,
                "allow.auto.create.topics": False,
                "enable.auto.commit": False,
                "enable.auto.offset.store": False,
                "auto.offset.reset": "earliest",
                "session.timeout.ms": 6000,
            }
        )
        self._lane = BlockingClient("kafka-consumer")

    async def subscribe(self, topic: str) -> None:
        validate_topic(self.namespace, topic)
        await self._lane.call(partial(self._client.subscribe, [topic]))

    async def read(self) -> KafkaRecord | None:
        def receive() -> KafkaRecord | None:
            message = self._client.poll(1)
            if message is None:
                return None
            if message.error() is not None:
                raise RuntimeError("Kafka receive failed")
            topic = message.topic()
            partition = message.partition()
            offset = message.offset()
            if topic is None or partition is None or offset is None:
                raise RuntimeError("Kafka returned an incomplete record")
            return KafkaRecord(message.key(), message.value(), topic, partition, offset)

        return await self._lane.call(receive)

    async def aclose(self) -> None:
        # No automatic acknowledgment; business completion controls the commit boundary.
        await self._lane.close(self._client.close)

    async def acknowledge(self, record: KafkaRecord) -> None:
        """Commit only after the matching persistent consumer transaction."""
        from confluent_kafka import TopicPartition

        await self._lane.call(
            partial(
                self._client.commit,
                offsets=[TopicPartition(record.topic, record.partition, record.offset + 1)],
                asynchronous=False,
            )
        )
