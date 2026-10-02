"""One JSON logging exit with bounded, typed metadata and no raw messages."""

import json
import logging
import os
import sys
from contextlib import suppress
from datetime import UTC, datetime
from logging.handlers import RotatingFileHandler
from typing import TextIO
from uuid import UUID, uuid4

from app.core.settings import Settings
from app.schemas.frontend_telemetry import CLIENT_EVENTS, TelemetryEvent

EVENTS = frozenset(
    {
        "credential.created",
        "material.import.created",
        "material.import.accepted",
        "material.upload.staged",
        "material.source.accepted",
        "material.import.completed",
        "material.import.failed",
        "material.import.needs_review",
        "material.staging.cleanup_pending",
        "material.metadata.updated",
        "material.deleted",
        "notification.created",
        "notification.delivery.failed",
        "notification.list.loaded",
        "notification.read.updated",
        "notification.read_all.updated",
        "credential.rotated",
        "credential.deleted",
        "credential.test.accepted",
        "credential.test.completed",
        "credential.test.failed",
        "model.job.claimed",
        "model.job.cancelled",
        "model.job.retry.accepted",
        "model.attempt.started",
        "model.attempt.completed",
        "model.attempt.failed",
        "model.attempt.unknown",
        "model.worker.unavailable",
        "outbox.model.published",
        "process.started",
        "process.stopped",
        "http.completed",
        "http.failed",
        "process.unavailable",
        "infrastructure.connected",
        "infrastructure.unavailable",
        "frontend.received",
        "auth.session.revoked",
        "authz.denied",
        "auth.password.changed",
        "auth.password.recovered",
        "auth.registration.accepted",
        "auth.email.verified",
        "auth.login.succeeded",
        "auth.login.rejected",
        "auth.login.action_required",
        "auth.policy.updated",
        "auth.verification.request.accepted",
        "auth.recovery.request.accepted",
        "auth.recovery.manual.accepted",
        "auth.cache_invalidation.deferred",
        "collection.saved",
        "profile.updated",
        "study_profile.updated",
        "settings.updated",
        "profile.avatar.updated",
        "profile.avatar.deleted",
        "mail.delivery.key_unavailable",
        "mail.delivery.retry_or_failed",
        "mail.delivery.sent",
        "mail.worker.unavailable",
        "outbox.identity.published",
        "outbox.worker.unavailable",
        "database.query.completed",
        "database.query.failed",
        "database.connection.failed",
        "database.transaction.rolled_back",
    }
)


class _SafeHandlerFailure:
    def handleError(self, record: logging.LogRecord) -> None:
        """logging's default error path dumps raw msg/args; never use that fallback."""
        # Do not recurse through logging or expose the failed record.
        with suppress(OSError, ValueError):
            sys.stderr.write("Haruka logging output unavailable.\n")


class SafeStreamHandler(_SafeHandlerFailure, logging.StreamHandler[TextIO]):
    pass


class SafeFileHandler(_SafeHandlerFailure, RotatingFileHandler):
    pass


class SafeJsonFormatter(logging.Formatter):
    """Never serialize library messages, exception text, args or request bodies."""

    def __init__(self, settings: Settings, service: str) -> None:
        super().__init__()
        self.settings = settings
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        event = (
            record.msg if isinstance(record.msg, str) and record.msg in EVENTS else "library.log"
        )
        payload: dict[str, object] = {
            "schema_version": 1,
            "event_id": str(uuid4()),
            "occurred_at": datetime.now(UTC).isoformat(),
            "record_type": "log",
            "event": event,
            "level": record.levelname.lower(),
            "project": "haruka",
            "environment": self.settings.app_env,
            "service": self.service,
            "instance_id": self.settings.instance_id,
            "release": self.settings.release,
            "origin": "server",
        }
        request_id: object = getattr(record, "request_id", None)
        if isinstance(request_id, UUID):
            payload["request_id"] = str(request_id)
        for field in ("operation_id", "client_request_id", "user_id", "job_id", "ai_run_id"):
            value: object = getattr(record, field, None)
            if isinstance(value, UUID):
                payload[field] = str(value)
        audience: object = getattr(record, "audience", None)
        if audience in {"client", "admin"}:
            payload["audience"] = audience
        route_template: object = getattr(record, "route_template", None)
        if (
            isinstance(route_template, str)
            and route_template.startswith("/api/v1/")
            and len(route_template) <= 150
            and "?" not in route_template
            and "#" not in route_template
        ):
            payload["route_template"] = route_template
        status_code: object = getattr(record, "status_code", None)
        if isinstance(status_code, int) and 100 <= status_code <= 599:
            payload["status_code"] = status_code
        duration_ms: object = getattr(record, "duration_ms", None)
        if isinstance(duration_ms, (int, float)) and 0 <= duration_ms < 86_400_000:
            payload["duration_ms"] = round(duration_ms, 3)
        if event.startswith("database."):
            database_name: object = getattr(record, "database_name", None)
            expected_database = "haruka_dev" if self.settings.app_env == "dev" else "haruka_test"
            if database_name == expected_database:
                payload["database_name"] = database_name
            application_name: object = getattr(record, "application_name", None)
            if (
                application_name == self.settings.instance_id
                and isinstance(application_name, str)
                and len(application_name.encode("utf-8")) <= 63
            ):
                payload["application_name"] = application_name
            backend_pid: object = getattr(record, "backend_pid", None)
            if type(backend_pid) is int and 0 < backend_pid <= 2_147_483_647:
                payload["backend_pid"] = backend_pid
            sqlstate: object = getattr(record, "sqlstate", None)
            if (
                event in {"database.query.failed", "database.connection.failed"}
                and isinstance(sqlstate, str)
                and len(sqlstate) == 5
                and all(char in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" for char in sqlstate)
            ):
                payload["sqlstate"] = sqlstate
        if event in {"database.query.completed", "database.query.failed"}:
            fingerprint: object = getattr(record, "sql_fingerprint", None)
            if (
                isinstance(fingerprint, str)
                and len(fingerprint) == 32
                and all(character in "0123456789abcdef" for character in fingerprint)
            ):
                payload["sql_fingerprint"] = fingerprint
            statement_kind: object = getattr(record, "statement_kind", None)
            if statement_kind in {
                "SELECT",
                "INSERT",
                "UPDATE",
                "DELETE",
                "WITH",
                "CREATE",
                "ALTER",
                "DROP",
                "COMMENT",
                "OTHER",
            }:
                payload["statement_kind"] = statement_kind
        if event == "collection.saved":
            outcome: object = getattr(record, "collection_outcome", None)
            if outcome in {"created", "existing", "replayed"}:
                payload["collection_outcome"] = outcome
        if event in {"profile.updated", "study_profile.updated", "settings.updated"}:
            field_count: object = getattr(record, "field_count", None)
            if type(field_count) is int and 1 <= field_count <= 12:
                payload["field_count"] = field_count
        if event == "profile.avatar.updated":
            size_bucket: object = getattr(record, "size_bucket", None)
            if size_bucket in {"up_to_1mb", "up_to_3mb", "up_to_5mb"}:
                payload["size_bucket"] = size_bucket
        client_event: object = getattr(record, "client_telemetry", None)
        if (
            event == "frontend.received"
            and isinstance(client_event, TelemetryEvent)
            and client_event.event in CLIENT_EVENTS
        ):
            payload.update(
                {
                    "event_id": str(client_event.event_id),
                    "occurred_at": client_event.occurred_at.isoformat(),
                    "received_at": datetime.now(UTC).isoformat(),
                    "record_type": client_event.record_type,
                    "event": client_event.event,
                    "level": client_event.level,
                    "origin": "client",
                    "emitter_service": "flutter",
                    "client_platform": client_event.client_platform,
                    "message": "Validated client event received.",
                }
            )
            if client_event.release is not None:
                payload["client_release"] = client_event.release
            if client_event.build is not None:
                payload["client_build"] = client_event.build
            for source_name, output_name in (
                ("operation_id", "operation_id"),
                ("request_id", "request_id"),
                ("client_request_id", "client_request_id"),
            ):
                value = getattr(client_event, source_name)
                if isinstance(value, UUID):
                    payload[output_name] = str(value)
            if client_event.attributes is not None:
                payload["attributes"] = client_event.attributes.model_dump(exclude_none=True)
            if client_event.safe_stack_frames is not None:
                payload["safe_stack_frames"] = client_event.safe_stack_frames
            for source_name, output_name in (
                ("bound_user_id", "user_id"),
                ("ingest_request_id", "ingest_request_id"),
            ):
                value = getattr(record, source_name, None)
                if isinstance(value, UUID):
                    payload[output_name] = str(value)
            audience: object = getattr(record, "bound_audience", None)
            if audience in {"client", "admin", "anonymous"}:
                payload["audience"] = audience
        # Known source coordinates support debugging without serializing local variables.
        if record.exc_info is not None and record.exc_info[2] is not None:
            frames: list[str] = []
            traceback = record.exc_info[2]
            while traceback is not None and len(frames) < 20:
                frame = traceback.tb_frame
                frames.append(f"{frame.f_code.co_name}:{traceback.tb_lineno}")
                traceback = traceback.tb_next
            payload["stack_frames"] = ";".join(frames)
        return json.dumps(payload, ensure_ascii=False, allow_nan=False)


def configure_logging(settings: Settings, service: str, stream: TextIO | None = None) -> None:
    """Configure once at the CLI boundary, including third-party loggers."""
    handler = SafeStreamHandler(stream or sys.stdout)
    handler.setFormatter(SafeJsonFormatter(settings, service))
    handlers: list[logging.Handler] = [handler]
    if settings.log_file is not None:
        settings.log_file.parent.mkdir(parents=True, exist_ok=True)
        # Standard rotating handlers are process-local, never share a file
        # between API, maintenance, Worker and Outbox processes.
        path = settings.log_file.with_name(
            f"{settings.log_file.stem}.{service}.{os.getpid()}{settings.log_file.suffix}"
        )
        file_handler = SafeFileHandler(path, maxBytes=10_000_000, backupCount=3, encoding="utf-8")
        file_handler.setFormatter(SafeJsonFormatter(settings, service))
        handlers.append(file_handler)
    logging.basicConfig(level=logging.INFO, handlers=handlers, force=True)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
