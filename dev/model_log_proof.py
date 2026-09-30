"""Inspect instance-bound model logs without persisting input secrets.

The key arrives only through stdin, stays in memory, and is never reported or
hashed. Evidence contains counts, safe event names and absence booleans.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path

from dev.infra import is_object
from dev.isolated_app_run import IsolatedRunError, read_ledger, run_root
from dev.observability_proof import (
    PROOF_ROOT,
    ProofError,
    read_isolated_local_lines,
    read_isolated_loki_lines,
)
from dev.secret_absence_proof import (
    SecretProofError,
    full_run_start,
    loki_has_event,
)


def absence_checks(
    local_lines: list[str], loki_lines: list[str], key: str
) -> dict[str, dict[str, bool]]:
    """Keep both matching values and source bodies out of the result."""
    if not 8 <= len(key) <= 4096 or not key.isascii():
        raise ProofError("model secret input is invalid")
    local = "".join(local_lines)
    loki = "".join(loki_lines)
    values = {
        "provider_key": key,
        "japanese_speech_sample": "こんにちは。",
        "english_speech_sample": "Hello.",
    }
    return {
        name: {"absent_local": value not in local, "absent_loki": value not in loki}
        for name, value in values.items()
    }


def safe_model_events(lines: list[str], instance_id: str) -> dict[str, int]:
    counts: Counter[str] = Counter()
    for line in lines:
        try:
            value: object = json.loads(line)
        except ValueError:
            continue
        if not is_object(value) or value.get("instance_id") != instance_id:
            continue
        event = value.get("event")
        if value.get("origin") == "client":
            if isinstance(event, str) and event in {
                "app.started",
                "screen.viewed",
                "auth.login.result",
                "http.completed",
                "http.failed",
                "settings.updated",
            }:
                counts[f"frontend.{event}"] += 1
            continue
        # Enumerated event names only; never copy arbitrary library text.
        if isinstance(event, str) and event in {
            "credential.created",
            "credential.rotated",
            "credential.deleted",
            "credential.test.accepted",
            "credential.test.completed",
            "credential.test.failed",
            "model.job.claimed",
            "model.job.cancelled",
            "model.attempt.started",
            "model.attempt.completed",
            "model.attempt.failed",
            "model.attempt.unknown",
            "outbox.model.published",
            "frontend.received",
            "database.query.completed",
            "http.completed",
            "http.failed",
        }:
            counts[event] += 1
    return dict(sorted(counts.items()))


def collect(run_id: str, key: str, *, window_seconds: int = 60) -> dict[str, object]:
    root = run_root(run_id)
    if read_ledger(root, run_id)["state"] not in {"serving", "stopped"}:
        raise ProofError("model log run is unavailable")
    local_lines, file_count = read_isolated_local_lines(run_id)
    instance_id = f"haruka-test-{run_id}"
    start, anchor, unbound_count = full_run_start(root, local_lines, instance_id)
    status, loki_lines, truncated = read_isolated_loki_lines(
        instance_id, start_utc=start, window_seconds=window_seconds
    )
    if status != 200 or truncated or not local_lines or not loki_lines:
        raise ProofError("model log query is unavailable or incomplete")
    if not loki_has_event(loki_lines, anchor):
        raise ProofError("model log query lacks the oldest local anchor")
    checks = absence_checks(local_lines, loki_lines, key)
    passed = all(all(check.values()) for check in checks.values())
    return {
        "run_id": run_id,
        "status": "passed" if passed else "failed",
        "scope": "provider key and fixed speech sample absence; model source event counts",
        "loki_from_utc": start.isoformat(),
        "loki_query_window_seconds": window_seconds,
        "oldest_local_event_present_in_loki": True,
        "local_lines_without_instance_id": unbound_count,
        "local_log_files": file_count,
        "local_lines": len(local_lines),
        "loki_lines": len(loki_lines),
        "checks": checks,
        "local_events": safe_model_events(local_lines, instance_id),
        "loki_events": safe_model_events(loki_lines, instance_id),
        "checked_utc": datetime.now(UTC).isoformat(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--window-seconds", type=int, default=60)
    args = parser.parse_args()
    try:
        if args.output.is_symlink():
            raise ProofError("model proof destination is linked")
        output = args.output.resolve()
        if output.parent != PROOF_ROOT.resolve() or output.exists():
            raise ProofError("model proof destination must be owned and new")
        key = sys.stdin.read(4098).strip()
        report = collect(args.run_id, key, window_seconds=args.window_seconds)
        key = ""
        with output.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, sort_keys=True)
            stream.write("\n")
        sys.stdout.write(f"{output}\n")
        return 0 if report["status"] == "passed" else 1
    except (OSError, ValueError, ProofError, SecretProofError, IsolatedRunError):
        sys.stderr.write("model log proof failed safely\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
