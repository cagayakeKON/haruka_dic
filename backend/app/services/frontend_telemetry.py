"""Bounded client telemetry validation, scope binding and Redis replay control."""

import logging
from datetime import UTC, datetime, timedelta
from typing import cast
from uuid import UUID

from pydantic import ValidationError

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.frontend_telemetry import (
    ANONYMOUS_EVENTS,
    CLIENT_EVENT_ATTRIBUTES,
    CLIENT_EVENTS,
    RejectReason,
    TelemetryBatchRead,
    TelemetryBatchRequest,
    TelemetryEvent,
    TelemetryItemResult,
)
from app.services.auth_crypto import AuthCrypto

logger = logging.getLogger(__name__)
_REPLAY_SECONDS = 26 * 60 * 60


def _event_id(value: object) -> UUID | None:
    if not isinstance(value, dict):
        return None
    candidate = cast("dict[str, object]", value).get("event_id")
    if not isinstance(candidate, str):
        return None
    try:
        event_id = UUID(candidate)
    except ValueError:
        return None
    return event_id if event_id.version == 4 else None


def _reject(index: int, value: object, reason: RejectReason) -> TelemetryItemResult:
    return TelemetryItemResult(
        index=index,
        event_id=_event_id(value),
        status="rejected",
        reason=reason,
    )


def validate_client_event(
    value: object, *, anonymous: bool, web_transport: bool, now: datetime
) -> tuple[TelemetryEvent | None, RejectReason | None]:
    try:
        event = TelemetryEvent.model_validate(value)
    except ValidationError as exc:
        if any(error["type"] == "extra_forbidden" for error in exc.errors()):
            return None, "invalid_record"
        locations = {str(error["loc"][0]) for error in exc.errors() if error["loc"]}
        if "attributes" in locations:
            return None, "invalid_attributes"
        if "occurred_at" in locations:
            return None, "invalid_time"
        if "client_platform" in locations:
            return None, "invalid_platform"
        if "event" in locations:
            return None, "invalid_event"
        return None, "invalid_record"
    if event.event not in CLIENT_EVENTS:
        return None, "invalid_event"
    if anonymous and event.event not in ANONYMOUS_EVENTS:
        return None, "not_allowed_for_audience"
    if (event.client_platform == "web") != web_transport:
        return None, "invalid_platform"
    occurred = event.occurred_at
    if occurred.tzinfo is None or not (
        now - timedelta(hours=24) <= occurred.astimezone(UTC) <= now + timedelta(minutes=5)
    ):
        return None, "invalid_time"
    if event.safe_stack_frames is not None and (
        event.event != "app.crash.capture" or event.record_type != "crash"
    ):
        return None, "invalid_record"
    if event.event == "app.crash.capture" and event.record_type != "crash":
        return None, "invalid_record"
    if event.event != "app.crash.capture" and event.record_type == "crash":
        return None, "invalid_record"
    if event.attributes is not None and not event.attributes.model_fields_set.issubset(
        CLIENT_EVENT_ATTRIBUTES[event.event]
    ):
        return None, "invalid_attributes"
    return event, None


async def _rate_limit(
    runtime: Runtime, *, address: str, client_session_id: UUID, anonymous: bool
) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    subjects = [
        ("ip", crypto.digest("telemetry-ip", address).hex(), 120 if anonymous else 300),
        ("session", str(client_session_id), 60 if anonymous else 300),
        ("global", "all", 3000),
    ]
    try:
        for kind, value, ceiling in subjects:
            key = resources.cache.key("telemetry", "rate", kind, value)
            count = await resources.cache.client.eval(
                "local n=redis.call('INCR',KEYS[1]); "
                "if redis.call('PTTL',KEYS[1])<0 then redis.call('PEXPIRE',KEYS[1],60000) end; "
                "return n",
                1,
                key,
            )
            if not isinstance(count, int):
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            if count > ceiling:
                raise AppError(ErrorCode.RATE_LIMITED)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def receive(
    runtime: Runtime,
    batch: TelemetryBatchRequest,
    *,
    scope: ScopeContext | None,
    anonymous: bool,
    web_transport: bool,
    address: str,
    ingest_request_id: UUID,
) -> TelemetryBatchRead:
    """Accepted means validated and emitted to process logging, not Loki durability."""
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if anonymous != (scope is None) or (anonymous and len(batch.events) > 5):
        raise AppError(ErrorCode.INPUT_INVALID)
    await _rate_limit(
        runtime, address=address, client_session_id=batch.client_session_id, anonymous=anonymous
    )
    now = datetime.now(UTC)
    subject = (
        (scope.audience, str(scope.user_id))
        if scope is not None
        else (
            "anonymous",
            AuthCrypto.from_settings(runtime.settings)
            .digest("telemetry-anonymous", f"{address}:{batch.client_session_id}")
            .hex(),
        )
    )
    results: list[TelemetryItemResult] = []
    for index, value in enumerate(batch.events):
        event, reason = validate_client_event(
            value, anonymous=anonymous, web_transport=web_transport, now=now
        )
        if event is None:
            results.append(_reject(index, value, reason or "invalid_record"))
            continue
        key = resources.cache.key("telemetry", "seen", *subject, str(event.event_id))
        try:
            first = await resources.cache.client.set(key, b"1", nx=True, ex=_REPLAY_SECONDS)
        except Exception:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
        if not first:
            results.append(
                TelemetryItemResult(index=index, event_id=event.event_id, status="duplicate")
            )
            continue
        logger.info(
            "frontend.received",
            extra={
                "client_telemetry": event,
                "bound_user_id": scope.user_id if scope is not None else None,
                "bound_audience": scope.audience if scope is not None else "anonymous",
                "ingest_request_id": ingest_request_id,
            },
        )
        results.append(TelemetryItemResult(index=index, event_id=event.event_id, status="accepted"))
    return TelemetryBatchRead(results=results)
