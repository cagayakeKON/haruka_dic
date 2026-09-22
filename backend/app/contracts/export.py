"""Deterministic schema export that never reads configuration or starts a service."""

import argparse
import hashlib
import json
from pathlib import Path

from app.contracts.errors import ERRORS, FIELD_MESSAGES
from app.contracts.permissions import permission_document
from app.core.logging import EVENTS
from app.main import create_app
from app.models.dictionary import database_document


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"


def documents() -> dict[str, object]:
    """Export implemented protocol surfaces only; absence is not a capability grant."""
    payloads: dict[str, object] = {
        "permissions.json": permission_document(),
        "database-schema.json": database_document(),
        "openapi.json": create_app(schema_only=True).openapi(),
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
            "scope": "backend-runtime",
            "events": sorted([*EVENTS, "library.log"]),
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
                "release",
                "origin",
                "request_id",
                "status_code",
                "duration_ms",
                "stack_frames",
            ],
            "private_payloads": False,
        },
    }
    payloads["version.json"] = {
        "schema_version": 1,
        "scope": "B0-identity-foundation",
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
