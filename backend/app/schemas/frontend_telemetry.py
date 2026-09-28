"""current slice client telemetry wire contract; every item is validated independently."""

import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import UUID4, Field, JsonValue, field_validator

from app.schemas.responses import ApiModel

ClientPlatform = Literal["web", "windows", "android"]
RecordType = Literal["log", "analytics", "performance", "crash"]
TelemetryLevel = Literal["debug", "info", "warn", "error", "fatal"]
ItemStatus = Literal["accepted", "duplicate", "rejected"]
RejectReason = Literal[
    "invalid_event",
    "invalid_attributes",
    "invalid_time",
    "invalid_platform",
    "invalid_record",
    "not_allowed_for_audience",
]

# This is the implemented current slice subset of the observability event dictionary.
# Server-side business outcomes are never accepted as authoritative client facts.
CLIENT_EVENTS = frozenset(
    {
        "app.started",
        "screen.viewed",
        "app.crash.capture",
        "auth.register.submitted",
        "auth.login.result",
        "auth.password.change.submitted",
        "auth.logout.requested",
        "auth.session.revoked",
        "access.snapshot.updated",
        "authz.denied",
        "reading.chapter.opened",
        "explanation.requested",
        "collection.saved",
        "profile.updated",
        "study_profile.updated",
        "settings.updated",
        "profile.avatar.updated",
        "profile.avatar.deleted",
        "http.completed",
        "http.failed",
        "telemetry.delivery.recovered",
        "cache.read.hit",
        "cache.read.miss",
        "cache.validation",
        "cache.invalidated",
        "cache.cleared",
        "cache.storage.degraded",
        "cache.stale_response.discarded",
        "cache.download",
        "cache.evicted",
        "schema.migration",
        "connection.probed",
        "account.scope.changed",
    }
)
ANONYMOUS_EVENTS = frozenset(
    {
        "app.started",
        "app.crash.capture",
        "auth.register.submitted",
        "auth.login.result",
        "connection.probed",
        "account.scope.changed",
    }
)
CLIENT_EVENT_ATTRIBUTES: dict[str, frozenset[str]] = {
    "app.started": frozenset({"duration_ms"}),
    "screen.viewed": frozenset({"screen_name", "duration_ms"}),
    "app.crash.capture": frozenset({"error_category"}),
    "auth.register.submitted": frozenset(),
    "auth.login.result": frozenset({"result", "error_category", "transport", "duration_ms"}),
    "auth.password.change.submitted": frozenset(),
    "auth.logout.requested": frozenset(),
    "auth.session.revoked": frozenset({"result"}),
    "access.snapshot.updated": frozenset({"result"}),
    "authz.denied": frozenset({"error_category"}),
    "reading.chapter.opened": frozenset({"material_type", "duration_ms"}),
    "explanation.requested": frozenset({"target_kind", "duration_ms"}),
    "collection.saved": frozenset({"card_type", "result", "duration_ms"}),
    "profile.updated": frozenset(),
    "study_profile.updated": frozenset(),
    "settings.updated": frozenset(),
    "profile.avatar.updated": frozenset(),
    "profile.avatar.deleted": frozenset(),
    "http.completed": frozenset({"status_code", "duration_ms", "retry_count"}),
    "http.failed": frozenset({"status_code", "duration_ms", "retry_count", "error_category"}),
    "telemetry.delivery.recovered": frozenset({"dropped_count", "drop_reason"}),
    "cache.read.hit": frozenset({"source"}),
    "cache.read.miss": frozenset({"source"}),
    "cache.validation": frozenset({"result"}),
    "cache.invalidated": frozenset({"result"}),
    "cache.cleared": frozenset({"result"}),
    "cache.storage.degraded": frozenset({"reason"}),
    "cache.stale_response.discarded": frozenset({"result"}),
    "cache.download": frozenset({"result"}),
    "cache.evicted": frozenset({"result"}),
    "schema.migration": frozenset({"result"}),
    "connection.probed": frozenset({"result", "duration_ms"}),
    "account.scope.changed": frozenset({"reason", "result"}),
}


class TelemetryAttributes(ApiModel):
    """Only low-risk categories/counts; no text, email, URL, token or resource ID."""

    screen_name: (
        Literal[
            "welcome",
            "login",
            "register",
            "recovery",
            "verify_email",
            "reset_password",
            "account",
            "sessions",
            "materials",
            "chapter",
            "collection",
            "settings",
            "admin_policy",
        ]
        | None
    ) = None
    result: (
        Literal[
            "success",
            "failure",
            "cancelled",
            "denied",
            "hit",
            "miss",
            "same",
            "changed",
            "unavailable",
        ]
        | None
    ) = None
    source: Literal["network", "memory", "disk"] | None = None
    reason: (
        Literal[
            "writer_unavailable",
            "browser_storage_unsafe",
            "quota_exceeded",
            "audio_unavailable",
            "invalid_payload",
            "instance_switch",
        ]
        | None
    ) = None
    error_category: (
        Literal[
            "authentication",
            "authorization",
            "conflict",
            "network",
            "timeout",
            "server",
            "validation",
            "flutter_framework",
            "dart_unhandled",
            "platform_channel",
            "other",
        ]
        | None
    ) = None
    transport: Literal["web", "native"] | None = None
    material_type: Literal["novel"] | None = None
    target_kind: Literal["material_content"] | None = None
    card_type: Literal["word"] | None = None
    status_code: int | None = Field(default=None, ge=100, le=599)
    duration_ms: float | None = Field(default=None, ge=0, le=86_400_000)
    retry_count: int | None = Field(default=None, ge=0, le=100)
    dropped_count: int | None = Field(default=None, ge=0, le=5_000)
    drop_reason: (
        Literal[
            "queue_full",
            "expired",
            "auth_scope_changed",
            "upload_failure",
            "invalid_event",
            "storage_unavailable",
        ]
        | None
    ) = None


class TelemetryEvent(ApiModel):
    schema_version: Literal[1] = 1
    event_id: UUID4
    record_type: RecordType
    event: str = Field(pattern=r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*){1,3}$", max_length=80)
    level: TelemetryLevel
    occurred_at: datetime
    client_platform: ClientPlatform
    release: str | None = Field(default=None, pattern=r"^[A-Za-z0-9._-]{1,64}$")
    build: str | None = Field(default=None, pattern=r"^[A-Za-z0-9._-]{1,64}$")
    operation_id: UUID4 | None = None
    request_id: UUID | None = None
    client_request_id: UUID4 | None = None
    attributes: TelemetryAttributes | None = None
    # The client converts a stack to symbol:line[:column] first. Paths, URLs,
    # source excerpts and exception messages cannot match this bounded form.
    safe_stack_frames: list[str] | None = Field(default=None, max_length=20)

    @field_validator("safe_stack_frames")
    @classmethod
    def validate_safe_frames(cls, frames: list[str] | None) -> list[str] | None:
        if frames is not None and any(
            re.fullmatch(
                r"[A-Za-z_$][A-Za-z0-9_.$]{0,63}:[1-9][0-9]{0,6}(?::[1-9][0-9]{0,4})?", frame
            )
            is None
            for frame in frames
        ):
            raise ValueError("unsafe stack frame")
        return frames


class TelemetryBatchRequest(ApiModel):
    """Raw JSON items let the receiver reject a bad event without losing siblings."""

    schema_version: Literal[1] = 1
    client_session_id: UUID4
    events: list[JsonValue] = Field(min_length=1, max_length=20)


class TelemetryBatchDocumented(ApiModel):
    """OpenAPI item shape; runtime parses raw items for independent rejects."""

    schema_version: Literal[1] = 1
    client_session_id: UUID4
    events: list[TelemetryEvent] = Field(min_length=1, max_length=20)


class TelemetryItemResult(ApiModel):
    index: int = Field(ge=0)
    event_id: UUID | None
    status: ItemStatus
    reason: RejectReason | None = None


class TelemetryBatchRead(ApiModel):
    results: list[TelemetryItemResult]
