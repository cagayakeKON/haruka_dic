"""Purpose-bound notification cursors and committed-sequence read snapshots."""

import hashlib
import hmac
import re
from base64 import urlsafe_b64decode, urlsafe_b64encode
from datetime import UTC, datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError, model_validator

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext

TTL_SECONDS = 900
_ENCODING = re.compile(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}")


class NotificationToken(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True, hide_input_in_errors=True)

    purpose: Literal["snapshot", "cursor"]
    instance: str
    owner: UUID
    library: UUID
    audience: Literal["client"]
    upper: int = Field(ge=0)
    issued_at: int = Field(ge=0)
    expires_at: int = Field(ge=0)
    unread_only: bool | None = None
    anchor_at: AwareDatetime | None = None
    anchor_id: UUID | None = None

    @model_validator(mode="after")
    def shape(self) -> Self:
        if self.expires_at - self.issued_at != TTL_SECONDS:
            raise ValueError("Invalid notification token lifetime")
        cursor = (
            self.unread_only is not None
            and self.anchor_at is not None
            and self.anchor_id is not None
        )
        if self.purpose == "cursor" and not cursor:
            raise ValueError("Cursor anchor required")
        if self.purpose == "snapshot" and any(
            value is not None for value in (self.unread_only, self.anchor_at, self.anchor_id)
        ):
            raise ValueError("Snapshot cannot contain a cursor")
        return self

    def expiry(self) -> datetime:
        return datetime.fromtimestamp(self.expires_at, UTC)


def initial_snapshot(
    *, instance: str, scope: ScopeContext, library_id: UUID, upper: int, now: datetime
) -> NotificationToken:
    if scope.audience != "client":
        raise AppError(ErrorCode.PERMISSION_DENIED)
    issued = int(now.timestamp())
    return NotificationToken(
        purpose="snapshot",
        instance=instance,
        owner=scope.user_id,
        library=library_id,
        audience="client",
        upper=upper,
        issued_at=issued,
        expires_at=issued + TTL_SECONDS,
    )


def cursor_for(
    snapshot: NotificationToken, *, unread_only: bool, anchor_at: datetime, anchor_id: UUID
) -> NotificationToken:
    # Retain the first committed upper and its expiry across every page.
    return snapshot.model_copy(
        update={
            "purpose": "cursor",
            "unread_only": unread_only,
            "anchor_at": anchor_at,
            "anchor_id": anchor_id,
        }
    )


def snapshot_from(cursor: NotificationToken) -> NotificationToken:
    return cursor.model_copy(
        update={
            "purpose": "snapshot",
            "unread_only": None,
            "anchor_at": None,
            "anchor_id": None,
        }
    )


def encode(token: NotificationToken, key: bytes) -> str:
    body = urlsafe_b64encode(token.model_dump_json().encode()).rstrip(b"=").decode("ascii")
    digest = hmac.new(
        key,
        b"haruka-notifications-v1\x00"
        + token.purpose.encode("ascii")
        + b"\x00"
        + body.encode("ascii"),
        hashlib.sha256,
    ).digest()
    return body + "." + urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def decode(
    value: str,
    key: bytes,
    *,
    purpose: Literal["snapshot", "cursor"],
    instance: str,
    scope: ScopeContext,
    library_id: UUID,
    now: datetime,
    unread_only: bool | None = None,
) -> NotificationToken:
    if not 1 <= len(value) <= 2048 or _ENCODING.fullmatch(value) is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    body, supplied = value.split(".")
    expected = (
        urlsafe_b64encode(
            hmac.new(
                key,
                b"haruka-notifications-v1\x00"
                + purpose.encode("ascii")
                + b"\x00"
                + body.encode("ascii"),
                hashlib.sha256,
            ).digest()
        )
        .rstrip(b"=")
        .decode("ascii")
    )
    if not hmac.compare_digest(expected, supplied):
        raise AppError(ErrorCode.INPUT_INVALID)
    try:
        token = NotificationToken.model_validate_json(
            urlsafe_b64decode(body + "=" * (-len(body) % 4))
        )
    except (ValueError, ValidationError):
        raise AppError(ErrorCode.INPUT_INVALID) from None
    if (
        token.purpose != purpose
        or token.instance != instance
        or token.owner != scope.user_id
        or token.library != library_id
        or scope.audience != "client"
        or token.audience != scope.audience
        or (purpose == "cursor" and token.unread_only != unread_only)
        or token.issued_at > int(now.timestamp())
    ):
        raise AppError(ErrorCode.INPUT_INVALID)
    if token.expires_at <= int(now.timestamp()):
        raise AppError(ErrorCode.RESOURCE_EXPIRED)
    return token
