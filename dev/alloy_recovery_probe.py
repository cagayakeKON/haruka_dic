"""Verify a real API event emitted during a local Alloy outage is recovered."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from collections import deque
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

from app.core.settings import load_settings

from dev.infra import compose, is_object, local_docker_guard
from dev.isolated_app_run import read_ledger, run_root

ROOT = Path(__file__).resolve().parent.parent
REPORT_ROOT = ROOT / "artifacts/dev"
LOG_ROOT = ROOT / "dev/.local/logs"
RUN = re.compile(r"[a-f0-9]{32}\Z")
LABEL = re.compile(r"[a-z][a-z0-9-]{0,23}\Z")


def _alloy_running() -> bool:
    result = subprocess.run(
        ["docker", "inspect", "--format", "{{.State.Running}}", "haruka-local-alloy-1"],
        capture_output=True,
        check=False,
        timeout=5,
    )
    return result.returncode == 0 and result.stdout.strip() == b"true"


def _api_event(run_id: str, operation_id: UUID) -> bool:
    request = urllib.request.Request(
        "http://127.0.0.1:18081/api/v1/meta",
        headers={"X-Operation-ID": str(operation_id)},
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        value: object = json.load(response)
        if response.status != 200 or not is_object(value):
            return False
        data = value.get("data")
        return is_object(data) and data.get("instance_id") == f"haruka-test-{run_id}"


def _local_event(run_id: str, operation_id: UUID) -> str | None:
    settings = load_settings(run_root(run_id) / "runtime.env")
    path = settings.log_file
    if (
        settings.instance_id != f"haruka-test-{run_id}"
        or path is None
        or path.is_symlink()
        or path.resolve().parent != LOG_ROOT.resolve()
        or run_id not in path.stem
    ):
        return None
    files = sorted(LOG_ROOT.glob(f"{path.stem}.*{path.suffix}"))
    if not files or len(files) > 30:
        return None
    for candidate in files:
        if candidate.is_symlink() or candidate.resolve().parent != LOG_ROOT.resolve():
            return None
        with candidate.open(encoding="utf-8", errors="replace") as stream:
            tail = deque(stream, maxlen=1000)
        for line in reversed(tail):
            try:
                item: object = json.loads(line)
            except ValueError:
                continue
            if (
                is_object(item)
                and item.get("event") == "http.completed"
                and item.get("operation_id") == str(operation_id)
                and item.get("instance_id") == settings.instance_id
            ):
                event_id = item.get("event_id")
                if isinstance(event_id, str):
                    try:
                        return str(UUID(event_id))
                    except ValueError:
                        pass
    return None


def _loki_event(run_id: str, event_id: str, started_ns: int) -> tuple[int, bool]:
    query = (
        '{project="haruka",environment="test"} | json | '
        f'instance_id="haruka-test-{run_id}" | event_id="{event_id}"'
    )
    parameters = urllib.parse.urlencode(
        {"query": query, "start": str(started_ns), "limit": "10"}
    )
    try:
        with urllib.request.urlopen(
            f"http://127.0.0.1:13100/loki/api/v1/query_range?{parameters}", timeout=5
        ) as response:
            document: object = json.load(response)
            if response.status != 200 or not is_object(document):
                return response.status, False
            data = document.get("data")
            return response.status, is_object(data) and bool(data.get("result"))
    except (OSError, ValueError):
        return 0, False


def probe(run_id: str) -> dict[str, object]:
    local_docker_guard()
    if read_ledger(run_root(run_id), run_id)["state"] != "serving":
        raise RuntimeError("isolated API is not serving")
    if not _alloy_running():
        raise RuntimeError("Alloy must be running before the controlled outage")
    operation_id = uuid4()
    started = datetime.now(UTC)
    stopped = False
    api_ok = False
    event_id: str | None = None
    restarted = False
    failure_code: str | None = None
    try:
        compose("stop", "alloy")
        stopped = not _alloy_running()
        if not stopped:
            failure_code = "alloy_stop_unconfirmed"
        else:
            api_ok = _api_event(run_id, operation_id)
            if not api_ok:
                failure_code = "api_identity_mismatch"
            else:
                for _ in range(10):
                    event_id = _local_event(run_id, operation_id)
                    if event_id is not None:
                        break
                    time.sleep(0.5)
                if event_id is None:
                    failure_code = "local_api_event_missing"
    except Exception:  # noqa: BLE001 - keep raw service errors out of the safe report.
        failure_code = "probe_step_failed"
    finally:
        for _ in range(2):
            try:
                compose("start", "alloy")
                restarted = _alloy_running()
                if restarted:
                    break
            except Exception:  # noqa: BLE001 - a second safe restart attempt follows.
                failure_code = "alloy_restart_attempt_failed"
    status = 0
    recovered = False
    if event_id is not None and restarted:
        for _ in range(30):
            status, recovered = _loki_event(
                run_id, event_id, int(started.timestamp() * 1_000_000_000)
            )
            if recovered:
                break
            time.sleep(1)
    if failure_code is None and not restarted:
        failure_code = "alloy_restart_unconfirmed"
    elif failure_code is None and not recovered:
        failure_code = "loki_recovery_missing"
    passed = (
        failure_code is None
        and stopped
        and api_ok
        and event_id is not None
        and restarted
        and recovered
    )
    return {
        "schema_version": 1,
        "run_id": run_id,
        "started_at": started.isoformat(),
        "operation_id": str(operation_id),
        "event_id": event_id,
        "alloy_stopped_before_api": stopped,
        "api_identity_matched_while_alloy_stopped": api_ok,
        "api_event_persisted_locally": event_id is not None,
        "alloy_restarted": restarted,
        "loki_http_status": status,
        "same_event_id_recovered_loki": recovered,
        "failure_code": failure_code if failure_code is not None else None,
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
    path = REPORT_ROOT / f"alloy-recovery-{args.run_id}-{args.label}.json"
    if path.exists():
        raise SystemExit("Choose a new report label; existing evidence is preserved.")
    try:
        result = probe(args.run_id)
        with path.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(path.relative_to(ROOT).as_posix())
        return 0 if result["status"] == "passed" else 1
    except Exception:  # noqa: BLE001 - no raw local service error reaches stdout/stderr.
        print(
            "Alloy recovery probe failed; inspect Haruka-local service state.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
