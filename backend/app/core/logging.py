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

EVENTS = frozenset(
    {
        "process.started",
        "process.stopped",
        "http.completed",
        "http.failed",
        "process.unavailable",
        "infrastructure.connected",
        "infrastructure.unavailable",
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
        payload: dict[str, str | int | float] = {
            "schema_version": 1,
            "event_id": str(uuid4()),
            "occurred_at": datetime.now(UTC).isoformat(),
            "record_type": "log",
            "event": event,
            "level": record.levelname.lower(),
            "project": "haruka",
            "environment": self.settings.app_env,
            "service": self.service,
            "release": self.settings.release,
            "origin": "server",
        }
        request_id: object = getattr(record, "request_id", None)
        if isinstance(request_id, UUID):
            payload["request_id"] = str(request_id)
        status_code: object = getattr(record, "status_code", None)
        if isinstance(status_code, int) and 100 <= status_code <= 599:
            payload["status_code"] = status_code
        duration_ms: object = getattr(record, "duration_ms", None)
        if isinstance(duration_ms, (int, float)) and 0 <= duration_ms < 86_400_000:
            payload["duration_ms"] = round(duration_ms, 3)
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
