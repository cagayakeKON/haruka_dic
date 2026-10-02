"""Deterministic schema export that never reads configuration or starts a service."""

import argparse
import hashlib
import json
from pathlib import Path

from pydantic import BaseModel
from pydantic.json_schema import models_json_schema

from app.contracts.errors import ERRORS, FIELD_MESSAGES
from app.contracts.permissions import permission_document
from app.core.logging import EVENTS
from app.main import create_app
from app.models.dictionary import database_document
from app.schemas.frontend_telemetry import CLIENT_EVENT_ATTRIBUTES, CLIENT_EVENTS
from app.schemas.material_imports import (
    MaterialDelete,
    MaterialImportCapabilitiesRead,
    MaterialImportCreate,
    MaterialImportRead,
    MaterialMetadataRead,
    MaterialTitlePatch,
    UploadComplete,
)
from app.schemas.user_notifications import (
    NotificationsReadAll,
    NotificationsReadAllResult,
    UserNotificationPage,
    UserNotificationRead,
)


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"


def dto_document(models: tuple[type[BaseModel], ...]) -> dict[str, object]:
    """Publish DTO definitions separately from the currently implemented HTTP routes."""
    references, definitions = models_json_schema([(model, "validation") for model in models])
    return {
        "schema_version": 1,
        "scope": "dto-definitions",
        "models": {model.__name__: references[(model, "validation")] for model in models},
        **definitions,
    }


def documents() -> dict[str, object]:
    """Export implemented protocol surfaces only; absence is not a capability grant."""
    payloads: dict[str, object] = {
        "permissions.json": permission_document(),
        "database-schema.json": database_document(),
        "openapi.json": create_app(schema_only=True).openapi(),
        "material-import-contract.json": dto_document(
            (
                MaterialImportCreate,
                MaterialImportRead,
                UploadComplete,
                MaterialImportCapabilitiesRead,
                MaterialMetadataRead,
                MaterialTitlePatch,
                MaterialDelete,
            )
        ),
        "user-notification-contract.json": dto_document(
            (
                UserNotificationRead,
                UserNotificationPage,
                NotificationsReadAll,
                NotificationsReadAllResult,
            )
        ),
        "errors.json": {
            "schema_version": 1,
            "locale": "zh-Hans",
            "errors": [
                {
                    "code": code,
                    "http_status": item.http_status,
                    "message": item.message,
                    "message_args": {},
                    "retryable": False,
                    "details_kind": "revision_conflict" if code == "REVISION_CONFLICT" else None,
                }
                for code, item in sorted(ERRORS.items())
            ],
            "field_errors": [
                {"code": code, "message": message, "message_args": {}}
                for code, message in sorted(FIELD_MESSAGES.items())
            ],
        },
        "telemetry.json": {
            "schema_version": 1,
            "scope": "client-and-backend",
            "events": sorted(set(EVENTS) | CLIENT_EVENTS | {"library.log"}),
            "client_events": sorted(CLIENT_EVENTS),
            "client_event_attributes": {
                event: sorted(attributes)
                for event, attributes in sorted(CLIENT_EVENT_ATTRIBUTES.items())
            },
            "fields": [
                "schema_version",
                "event_id",
                "occurred_at",
                "record_type",
                "event",
                "level",
                "project",
                "environment",
                "service",
                "instance_id",
                "release",
                "origin",
                "request_id",
                "ingest_request_id",
                "operation_id",
                "job_id",
                "ai_run_id",
                "client_request_id",
                "user_id",
                "audience",
                "route_template",
                "client_platform",
                "client_release",
                "client_build",
                "emitter_service",
                "received_at",
                "attributes",
                "safe_stack_frames",
                "status_code",
                "duration_ms",
                "sql_fingerprint",
                "statement_kind",
                "sqlstate",
                "database_name",
                "application_name",
                "backend_pid",
                "stack_frames",
            ],
            "private_payloads": False,
        },
    }
    payloads["version.json"] = {
        "schema_version": 1,
        "scope": "account-and-learning",
        "sha256": {
            name: hashlib.sha256(canonical_json(value).encode()).hexdigest()
            for name, value in sorted(payloads.items())
        },
    }
    return payloads


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, value in documents().items():
        (args.output / name).write_text(canonical_json(value), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
