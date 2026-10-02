"""The current slice ingestion contract must be exportable and never trust client identity."""

from collections.abc import Iterator
from datetime import UTC, datetime
from typing import cast
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.main import create_app
from app.schemas.frontend_telemetry import TelemetryBatchRequest
from app.services.frontend_telemetry import validate_client_event


def _references(value: object) -> Iterator[str]:
    if isinstance(value, dict):
        for key, item in cast("dict[str, object]", value).items():
            if key == "$ref" and isinstance(item, str):
                yield item
            else:
                yield from _references(item)
    elif isinstance(value, list):
        for item in cast("list[object]", value):
            yield from _references(item)


def _reference_step(value: object, segment: str) -> object:
    assert isinstance(value, dict)
    return cast("object", value[segment.replace("~1", "/").replace("~0", "~")])


def test_openapi_local_references_resolve() -> None:
    document = cast("dict[str, object]", create_app(schema_only=True).openapi())
    for reference in _references(document):
        assert reference.startswith("#/"), reference
        target: object = document
        for segment in reference.removeprefix("#/").split("/"):
            target = _reference_step(target, segment)
        assert target is not None
    paths = cast("dict[str, object]", document["paths"])
    route = cast("dict[str, object]", paths["/api/v1/frontend-logs"])
    post = cast("dict[str, object]", route["post"])
    request = cast("dict[str, object]", post["requestBody"])
    assert request["required"] is True
    content = cast("dict[str, object]", request["content"])
    media = cast("dict[str, object]", content["application/json"])
    schema = cast("dict[str, object]", media["schema"])
    properties = cast("dict[str, object]", schema["properties"])
    assert properties["events"]


def test_batch_rejects_client_identity_override_and_keeps_raw_items() -> None:
    event_id = uuid4()
    with pytest.raises(ValidationError):
        TelemetryBatchRequest.model_validate(
            {"client_session_id": str(uuid4()), "events": [{}], "audience": "admin"}
        )
    batch = TelemetryBatchRequest.model_validate(
        {
            "schema_version": 1,
            "client_session_id": str(uuid4()),
            "events": [{"event_id": str(event_id), "user_id": str(uuid4())}],
        }
    )
    assert len(batch.events) == 1
    _event, reason = validate_client_event(
        batch.events[0],
        anonymous=True,
        web_transport=True,
        now=datetime.now(UTC),
    )
    assert reason == "invalid_record"


@pytest.mark.parametrize(
    ("changes", "reason"),
    [
        ({"message": "user typed a password"}, "invalid_record"),
        ({"safe_stack_frames": ["C:/users/private/file.dart:10"]}, "invalid_record"),
        ({"attributes": {"card_type": "word"}}, "invalid_attributes"),
        ({"occurred_at": "2020-01-01T00:00:00Z"}, "invalid_time"),
        ({"client_platform": "ios"}, "invalid_platform"),
    ],
)
def test_client_event_rejects_unregistered_content(changes: dict[str, object], reason: str) -> None:
    event: dict[str, object] = {
        "event_id": str(uuid4()),
        "record_type": "analytics",
        "event": "app.started",
        "level": "info",
        "occurred_at": datetime.now(UTC).isoformat(),
        "client_platform": "web",
    }
    event.update(changes)
    _validated, actual = validate_client_event(
        event, anonymous=True, web_transport=True, now=datetime.now(UTC)
    )
    assert actual == reason


def test_material_events_accept_registered_owner_categories_and_deny_anonymous() -> None:
    now = datetime.now(UTC)
    for event_name in (
        "material.import.submitted",
        "material.metadata.updated",
        "material.deleted",
    ):
        for material_type in ("novel", "textbook", "exam"):
            payload = {
                "event_id": str(uuid4()),
                "record_type": "analytics",
                "event": event_name,
                "level": "info",
                "occurred_at": now.isoformat(),
                "client_platform": "web",
                "attributes": {"material_type": material_type, "result": "success"},
            }
            value, reason = validate_client_event(
                payload, anonymous=False, web_transport=True, now=now
            )
            assert reason is None and value is not None
            _value, reason = validate_client_event(
                payload, anonymous=True, web_transport=True, now=now
            )
            assert reason == "not_allowed_for_audience"


def test_material_events_reject_private_and_unregistered_attributes() -> None:
    now = datetime.now(UTC)
    for attributes in (
        {"material_type": "novel", "result": "success", "title": "private"},
        {"material_type": "other", "result": "success"},
        {"material_type": "novel", "result": "success", "duration_ms": 10},
    ):
        payload = {
            "event_id": str(uuid4()),
            "record_type": "analytics",
            "event": "material.import.submitted",
            "level": "info",
            "occurred_at": now.isoformat(),
            "client_platform": "web",
            "attributes": attributes,
        }
        value, reason = validate_client_event(payload, anonymous=False, web_transport=True, now=now)
        assert value is None and reason in {"invalid_attributes", "invalid_record"}
