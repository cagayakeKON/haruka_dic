"""Exercise the public telemetry validator with a synthetic secret-like sentinel."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import ssl
import sys
import urllib.request
from datetime import UTC, datetime
from uuid import uuid4

from dev.isolated_app_run import read_ledger, run_root, write_private


class ProbeError(Exception):
    """Safe local probe failure."""


def probe(run_id: str) -> None:
    root = run_root(run_id)
    if read_ledger(root, run_id)["state"] != "serving":
        raise ProbeError("isolated API must be serving")
    secret_file = root / "telemetry-sentinel.secret"
    receipt_file = root / "telemetry-sentinel-receipt.json"
    if secret_file.exists() or receipt_file.exists():
        raise ProbeError("sentinel probe already exists for this run")
    certificate = root / "localhost.crt"
    if not certificate.is_file() or certificate.is_symlink():
        raise ProbeError("isolated HTTPS certificate is unavailable")
    sentinel = "sentinel-" + secrets.token_hex(24)
    write_private(secret_file, sentinel + "\n")
    event_id = uuid4()
    body = json.dumps(
        {
            "schema_version": 1,
            "client_session_id": str(uuid4()),
            "events": [
                {
                    "schema_version": 1,
                    "event_id": str(event_id),
                    "record_type": "log",
                    "event": "app.started",
                    "level": "info",
                    "occurred_at": datetime.now(UTC).isoformat(),
                    "client_platform": "web",
                    "message": sentinel,
                }
            ],
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        "https://localhost:18443/api/v1/frontend-logs/anonymous",
        data=body,
        headers={
            "Origin": "https://localhost:18443",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    context = ssl.create_default_context(cafile=str(certificate))
    with urllib.request.urlopen(request, context=context, timeout=5) as response:
        status = response.status
        document: object = json.loads(response.read(8_192))
    if not isinstance(document, dict):
        raise ProbeError("telemetry probe response is invalid")
    data = document.get("data")
    if not isinstance(data, dict):
        raise ProbeError("telemetry probe result is unavailable")
    results = data.get("results")
    if not isinstance(results, list) or len(results) != 1 or not isinstance(results[0], dict):
        raise ProbeError("telemetry probe item result is invalid")
    result = results[0]
    if status != 200 or result.get("status") != "rejected" or result.get("reason") != "invalid_record":
        raise ProbeError("unsafe telemetry item was not rejected")
    meta = document.get("meta")
    request_id = meta.get("request_id") if isinstance(meta, dict) else None
    if not isinstance(request_id, str) or re.fullmatch(r"[0-9a-f-]{36}", request_id) is None:
        raise ProbeError("telemetry probe lacks server request correlation")
    write_private(
        receipt_file,
        json.dumps(
            {
                "run_id": run_id,
                "event_id": str(event_id),
                "request_id": request_id,
                "http_status": status,
                "item_status": "rejected",
                "reason": "invalid_record",
                "sentinel_sha256": hashlib.sha256(sentinel.encode("utf-8")).hexdigest(),
                "performed_at": datetime.now(UTC).isoformat(),
            },
            sort_keys=True,
        ) + "\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Synthetic isolated telemetry rejection probe")
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    try:
        probe(args.run_id)
        print("sentinel_probe_rejected=true")
        return 0
    except (OSError, ValueError, ProbeError, ssl.SSLError):
        print("isolated telemetry sentinel probe failed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
