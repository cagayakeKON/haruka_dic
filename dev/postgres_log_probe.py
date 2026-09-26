"""Prove a synthetic PostgreSQL error is sanitized before entering Loki."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path
from typing import TypeGuard

from dev.infra import is_object, local_docker_guard
from dev.isolated_app_run import read_ledger, run_root

ROOT = Path(__file__).resolve().parent.parent
REPORT_ROOT = ROOT / "artifacts/dev"
RUN = re.compile(r"[a-f0-9]{32}\Z")
LABEL = re.compile(r"[a-z][a-z0-9-]{0,23}\Z")
CONTAINER = "haruka-local-postgres-1"


def _is_array(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


def _loki_lines(start_ns: int) -> tuple[int, list[str], bool]:
    query = '{project="haruka",service="postgres"}'
    parameters = urllib.parse.urlencode(
        {
            "query": query,
            "start": str(start_ns),
            "limit": "1000",
            "direction": "forward",
        }
    )
    request = urllib.request.Request(
        f"http://127.0.0.1:13100/loki/api/v1/query_range?{parameters}"
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
            document: object = json.load(response)
    except (OSError, ValueError):
        return 0, [], False
    lines: list[str] = []
    data = document.get("data") if is_object(document) else None
    if is_object(data):
        streams = data.get("result")
        if _is_array(streams):
            for stream in streams:
                values = stream.get("values") if is_object(stream) else None
                if not _is_array(values):
                    continue
                for row in values:
                    if _is_array(row) and len(row) == 2 and isinstance(row[1], str):
                        lines.append(row[1])
    return status, lines, len(lines) >= 1000


def probe(run_id: str) -> dict[str, object]:
    local_docker_guard()
    ledger = read_ledger(run_root(run_id), run_id)
    if ledger["state"] not in {"stopped", "serving"}:
        raise RuntimeError("isolated run is not prepared")
    instance_id = f"haruka-test-{run_id}"
    sentinel = "haruka_pg_probe_" + secrets.token_hex(20)
    started = datetime.now(UTC)
    statement = f"SELECT pg_backend_pid();\nSELECT '{sentinel}'::uuid;\n"
    process = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            "-e",
            f"PGAPPNAME={instance_id}",
            CONTAINER,
            "psql",
            "-U",
            "haruka_bootstrap",
            "-d",
            "haruka_test",
            "-At",
            "-v",
            "ON_ERROR_STOP=1",
        ],
        input=statement,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    # PostgreSQL/psql error output contains the synthetic marker. Keep it in
    # memory only and never include it or the statement in diagnostics.
    backend_pid = process.stdout.strip().splitlines()
    pid = int(backend_pid[0]) if backend_pid and backend_pid[0].isdecimal() else None
    source = subprocess.run(
        ["docker", "logs", "--since", started.isoformat(), "--tail", "2000", CONTAINER],
        capture_output=True,
        timeout=8,
        check=False,
    )
    source_contains_marker = sentinel.encode() in source.stderr + source.stdout
    start_ns = int(started.timestamp() * 1_000_000_000)
    status = 0
    lines: list[str] = []
    truncated = False
    matched = False
    leaked = False
    for _ in range(20):
        status, lines, truncated = _loki_lines(start_ns)
        leaked = any(sentinel in line for line in lines)
        for line in lines:
            try:
                event: object = json.loads(line)
            except ValueError:
                continue
            if (
                is_object(event)
                and event.get("record_type") == "postgres_engine"
                and event.get("event") == "database.engine"
                and event.get("database_name") == "haruka_test"
                and event.get("application_name") == instance_id
                and event.get("backend_pid") == pid
                and event.get("sqlstate") == "22P02"
                and event.get("severity") == "ERROR"
            ):
                matched = True
        if matched or leaked:
            break
        time.sleep(1)
    passed = (
        process.returncode == 3
        and pid is not None
        and source_contains_marker
        and status == 200
        and matched
        and not leaked
        and not truncated
    )
    return {
        "schema_version": 1,
        "run_id": run_id,
        "instance_id": instance_id,
        "injected_at": started.isoformat(),
        "synthetic_marker_sha256": hashlib.sha256(sentinel.encode()).hexdigest(),
        "backend_pid": pid,
        "expected_sql_error_seen": process.returncode == 3,
        "raw_source_contains_synthetic_marker": source_contains_marker,
        "loki_http_status": status,
        "loki_sample_line_count": len(lines),
        "loki_sample_truncated": truncated,
        "loki_sanitized_pid_sqlstate_match": matched,
        "synthetic_marker_absent_loki": not leaked,
        "status": "passed" if passed else "failed",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    if not RUN.fullmatch(args.run_id) or not LABEL.fullmatch(args.label):
        raise SystemExit("A controlled run and safe report label are required.")
    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    path = REPORT_ROOT / f"postgres-engine-{args.run_id}-{args.label}.json"
    if path.exists():
        raise SystemExit("Choose a new report label; existing evidence is preserved.")
    try:
        result = probe(args.run_id)
        with path.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(path.relative_to(ROOT).as_posix())
        return 0 if result["status"] == "passed" else 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        print("PostgreSQL log probe failed; no raw error was printed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
