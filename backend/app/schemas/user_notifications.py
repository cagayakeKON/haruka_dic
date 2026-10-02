"""Safe owner notification projections and commit-sequence read snapshots."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import ConfigDict, Field, model_validator

from app.schemas.responses import ApiModel, PageMeta, PageResponse

NotificationKind = Literal["completed", "failed", "needs_review"]
NotificationMessage = Literal[
    "material.import.completed",
    "material.import.failed",
    "material.import.needs_review",
    "notification.resource_unavailable",
]


class UserNotificationRead(ApiModel):
    id: UUID
    notification_kind: NotificationKind
    message_code: NotificationMessage
    schema_version: Literal[1] = 1
    safe_parameters: dict[str, str | int] = Field(default_factory=dict, max_length=0)
    job_id: UUID
    resource_kind: Literal["material"] = "material"
    resource_id: UUID | None
    resource_version: int | None = Field(ge=1)
    resource_available: bool
    route_key: Literal["material"] | None
    created_at: datetime
    read_at: datetime | None

    @model_validator(mode="after")
    def safe_destination(self) -> "UserNotificationRead":
        available = (
            self.resource_id is not None
            and self.resource_version is not None
            and self.route_key == "material"
        )
        if self.resource_available != available:
            raise ValueError("Notification destination availability does not match references")
        if available and self.message_code != f"material.import.{self.notification_kind}":
            raise ValueError("Notification message does not match its committed event kind")
        if not self.resource_available and (
            self.resource_id is not None
            or self.resource_version is not None
            or self.route_key is not None
            or self.message_code != "notification.resource_unavailable"
        ):
            raise ValueError("Unavailable notification must use a generic safe projection")
        return self


class UserNotificationPageMeta(PageMeta):
    unread_count: int = Field(ge=0)
    snapshot_token: str = Field(min_length=1, max_length=2048)
    snapshot_expires_at: datetime


class UserNotificationPage(PageResponse[UserNotificationRead]):
    model_config = ConfigDict(frozen=True)
    # Pydantic validates this concrete metadata subtype; the page cannot be reassigned.
    meta: UserNotificationPageMeta  # pyright: ignore[reportIncompatibleVariableOverride]


class NotificationsReadAll(ApiModel):
    snapshot_token: str = Field(min_length=1, max_length=2048)


class NotificationsReadAllResult(ApiModel):
    changed_count: int = Field(ge=0)
    unread_count: int = Field(ge=0)
