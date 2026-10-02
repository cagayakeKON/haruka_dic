"""Strict safe event keys and digest identity across broker serialization."""

import json
from uuid import uuid4

import pytest

from app.domain.errors import AppError
from app.models import OutboxEvent
from app.services.notification_events import envelope_bytes, source_outcome

pytestmark = pytest.mark.unit


def outcome() -> OutboxEvent:
    return OutboxEvent(
        id=uuid4(),
        event_type="material.import.completed",
        status="pending",
        payload={
            "schema_version": 1,
            "job_id": str(uuid4()),
            "material_id": str(uuid4()),
            "material_revision_id": str(uuid4()),
            "resource_version": 1,
            "owner_user_id": str(uuid4()),
            "library_id": str(uuid4()),
            "job_generation": 1,
            "delete_generation": 0,
        },
    )


@pytest.mark.parametrize("key", list(outcome().payload))
def test_source_outcome_requires_each_registered_key(key: str) -> None:
    event = outcome()
    event.payload.pop(key)
    with pytest.raises(AppError):
        source_outcome(event, None)


@pytest.mark.parametrize(
    "bad", [{"body": "synthetic"}, {"schema_version": True}, {"job_generation": 1.0}]
)
def test_source_outcome_rejects_unknown_text_and_coerced_versions(bad: dict[str, object]) -> None:
    event = outcome()
    event.payload.update(bad)
    with pytest.raises(AppError):
        source_outcome(event, None)


def test_canonical_identity_excludes_delivery_state_and_rejects_wire_type_change() -> None:
    event = outcome()
    envelope: dict[str, object] = {
        "event_id": str(event.id),
        "event_type": event.event_type,
        "payload": event.payload,
    }
    parsed: dict[str, object] = json.loads(json.dumps(envelope, indent=2, sort_keys=True))
    assert source_outcome(event, parsed).schema_version == 1
    original = envelope_bytes(envelope)
    event.status = "published"
    assert source_outcome(event, parsed).schema_version == 1
    assert envelope_bytes(parsed) == original
    for altered in (
        {**parsed, "extra": 1},
        {**parsed, "payload": {**event.payload, "schema_version": True}},
        {**parsed, "payload": {**event.payload, "resource_version": 1.0}},
    ):
        with pytest.raises(AppError):
            source_outcome(event, altered)
