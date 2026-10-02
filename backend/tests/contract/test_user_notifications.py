"""Notification wire contracts cannot carry private content or unsafe destinations."""

from datetime import UTC, datetime
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.schemas.user_notifications import (
    NotificationsReadAll,
    UserNotificationPage,
    UserNotificationRead,
)

pytestmark = pytest.mark.contract


def projection() -> dict[str, object]:
    return {
        "id": UUID(int=1),
        "notification_kind": "completed",
        "message_code": "material.import.completed",
        "job_id": UUID(int=2),
        "resource_id": UUID(int=3),
        "resource_version": 1,
        "resource_available": True,
        "route_key": "material",
        "created_at": datetime(2026, 10, 2, tzinfo=UTC),
        "read_at": None,
    }


def test_notification_page_keeps_snapshot_and_flat_page_envelope() -> None:
    expected_reference = "server-issued-snapshot"
    page = UserNotificationPage.model_validate(
        {
            "data": [projection()],
            "meta": {
                "request_id": UUID(int=4),
                "next_cursor": None,
                "has_more": False,
                "unread_count": 1,
                "snapshot_token": expected_reference,
                "snapshot_expires_at": datetime(2026, 10, 2, 1, tzinfo=UTC),
            },
        }
    )
    wire = page.model_dump(mode="json")
    assert isinstance(wire["data"], list)
    assert wire["meta"]["snapshot_token"] == expected_reference
    assert wire["meta"]["unread_count"] == 1
    assert wire["data"][0]["read_at"] is None
    assert "items" not in wire


@pytest.mark.parametrize(
    "changed",
    [
        {"safe_parameters": {"text": "private-source-body"}},
        {"prompt": "private-source-body"},
        {"route_key": "https://untrusted.example.test"},
        {"message_code": "material.import.failed"},
        {"resource_available": False},
    ],
)
def test_notification_projection_rejects_content_and_inconsistent_routes(
    changed: dict[str, object],
) -> None:
    with pytest.raises(ValidationError):
        UserNotificationRead.model_validate(projection() | changed)


def test_unavailable_resource_has_only_generic_projection() -> None:
    row = UserNotificationRead.model_validate(
        projection()
        | {
            "message_code": "notification.resource_unavailable",
            "resource_id": None,
            "resource_version": None,
            "route_key": None,
            "resource_available": False,
        }
    )
    assert row.resource_id is None and row.route_key is None
    assert row.safe_parameters == {}


def test_read_all_cannot_select_an_owner_or_submit_arbitrary_members() -> None:
    valid = {"snapshot_token": "server-issued-snapshot"}
    assert NotificationsReadAll.model_validate(valid).snapshot_token == valid["snapshot_token"]
    for extra in ({"user_id": str(UUID(int=5))}, {"notification_ids": [str(UUID(int=6))]}):
        with pytest.raises(ValidationError):
            NotificationsReadAll.model_validate(valid | extra)
