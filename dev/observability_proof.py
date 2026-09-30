"""Write a bounded, content-free proof of isolated host log collection."""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import TypeGuard
from uuid import UUID

from dev.infra import is_object
from dev.local_smtp_capture import LOCAL_ROOT
from sqlalchemy import select

from app.adapters.database import Database
from app.core.settings import load_settings
from app.models.identity_security import AuthChallengeDelivery

ROOT = Path(__file__).resolve().parent.parent
LOG_ROOT = ROOT / "dev/.local/logs"
PROOF_ROOT = ROOT / "artifacts/dev"
RUN = re.compile(r"[a-f0-9]{32}\Z")
# Long cross-platform runs may exceed 100k records. Keep the complete run
# bounded by both a finite count and the independent 128 MiB byte ceiling.
MAX_LINES = 200_000
MAX_TOTAL_BYTES = 128 * 1024 * 1024
LOKI_PAGE_LIMIT = 5_000
LOKI_URL = "http://127.0.0.1:13100"
GRAFANA_URL = "http://127.0.0.1:13000"
POSTGRES_CONTAINER = "haruka-local-postgres-1"


class ProofError(Exception):
    """Safe local evidence failure."""


def _is_array(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


def _empty_requests() -> set[str]:
    return set()


def _request(
    url: str, *, authorization: str | None = None, timeout: float = 5
) -> tuple[int, bytes]:
    if urllib.parse.urlsplit(url).netloc not in {
        "127.0.0.1:13100",
        "127.0.0.1:13000",
    } or not url.startswith("http://"):
        return 0, b""
    headers = {"Authorization": authorization} if authorization is not None else {}
    request = urllib.request.Request(url, headers=headers)  # noqa: S310 - exact loopback HTTP origins checked above.
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - same guarded request.
            return response.status, response.read(5_000_000)
    except urllib.error.HTTPError as error:
        return error.code, b""
    except (OSError, ValueError):
        return 0, b""


def _events(lines: list[str], instance_id: str) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for line in lines:
        try:
            value: object = json.loads(line)
        except ValueError:
            continue
        if is_object(value) and value.get("instance_id") == instance_id:
            result.append(value)
    return result


def _local_lines(run_id: str) -> tuple[list[str], int]:
    lines: list[str] = []
    total_bytes = 0
    config = LOCAL_ROOT / run_id / "runtime.env"
    if not config.is_file():
        raise ProofError("isolated runtime configuration is unavailable")
    settings = load_settings(config)
    base = settings.log_file
    if (
        settings.instance_id != f"haruka-test-{run_id}"
        or base is None
        or base.resolve().parent != LOG_ROOT.resolve()
        or run_id not in base.stem
    ):
        raise ProofError("isolated log location differs from its run")
    files = sorted(LOG_ROOT.glob(f"{base.stem}.*{base.suffix}"))
    for path in files:
        if path.is_symlink() or path.resolve().parent != LOG_ROOT.resolve():
            raise ProofError("isolated log path escaped the local log directory")
        try:
            with path.open(encoding="utf-8", errors="strict") as stream:
                for line in stream:
                    lines.append(line)
                    total_bytes += len(line.encode("utf-8"))
                    if len(lines) > MAX_LINES or total_bytes > MAX_TOTAL_BYTES:
                        raise ProofError("isolated log proof exceeds its bounded input")
        except (OSError, UnicodeError):
            raise ProofError("isolated log is unavailable or not valid UTF-8") from None
    return lines, len(files)


def _loki_lines(
    instance_id: str, *, start_utc: datetime | None = None, window_seconds: int = 300
) -> tuple[int, list[str], bool]:
    end = datetime.now(UTC)
    start = start_utc if start_utc is not None else end - timedelta(hours=6)
    if start.tzinfo is None or start >= end or end - start > timedelta(hours=24):
        raise ProofError("Loki query start is invalid")
    if not 1 <= window_seconds <= 300:
        raise ProofError("Loki query window is invalid")
    query = (
        f'{{project="haruka",environment="test"}}'
        f' |= "{instance_id}" | json | instance_id="{instance_id}"'
    )
    lower_bound = int(start.timestamp() * 1_000_000_000)
    upper_bound = int(end.timestamp() * 1_000_000_000)
    window_ns = window_seconds * 1_000_000_000
    lines: list[str] = []
    total_bytes = 0
    while lower_bound <= upper_bound:
        # Small disjoint windows keep old runs queryable on the local Loki.
        # An exactly full window is ambiguous, so fail instead of skipping
        # same-timestamp entries at a pagination boundary.
        window_end = min(lower_bound + window_ns - 1, upper_bound)
        parameters = urllib.parse.urlencode(
            {
                "query": query,
                "start": str(lower_bound),
                "end": str(window_end),
                "limit": str(LOKI_PAGE_LIMIT),
                "direction": "forward",
            }
        )
        status, raw = _request(f"{LOKI_URL}/loki/api/v1/query_range?{parameters}", timeout=20)
        if status != 200:
            return status, lines, False
        try:
            document: object = json.loads(raw)
            if not is_object(document) or document.get("status") != "success":
                return status, lines, True
            data = document.get("data")
            if not is_object(data):
                return status, lines, True
            results = data.get("result")
            if not _is_array(results):
                return status, lines, True
            page: list[tuple[int, str]] = []
            for stream in results:
                if not is_object(stream):
                    return status, lines, True
                values = stream.get("values")
                if not _is_array(values):
                    return status, lines, True
                for row in values:
                    if not (
                        _is_array(row)
                        and len(row) == 2
                        and isinstance(row[0], str)
                        and row[0].isdecimal()
                        and isinstance(row[1], str)
                    ):
                        return status, lines, True
                    page.append((int(row[0]), row[1]))
            page.sort(key=lambda item: item[0])
            lines.extend(line for _timestamp, line in page)
            total_bytes += sum(len(line.encode("utf-8")) for _timestamp, line in page)
            if (
                len(page) >= LOKI_PAGE_LIMIT
                or len(lines) > MAX_LINES
                or total_bytes > MAX_TOTAL_BYTES
            ):
                return status, lines, True
            lower_bound = window_end + 1
        except (KeyError, TypeError, ValueError):
            return status, lines, True
    return 200, lines, False


def read_isolated_local_lines(run_id: str) -> tuple[list[str], int]:
    """Reuse the bounded, owned-run local log reader for safety probes."""
    return _local_lines(run_id)


def read_isolated_loki_lines(
    instance_id: str, *, start_utc: datetime | None = None, window_seconds: int = 300
) -> tuple[int, list[str], bool]:
    """Reuse the bounded run-scoped Loki reader for safety probes."""
    return _loki_lines(instance_id, start_utc=start_utc, window_seconds=window_seconds)


def _grafana_authorization() -> str | None:
    secret = ROOT / "dev/.local/secrets/grafana_password"
    if not secret.is_file():
        return None
    password = secret.read_text(encoding="utf-8").strip()
    if not password:
        return None
    encoded = base64.b64encode(f"haruka:{password}".encode()).decode("ascii")
    return f"Basic {encoded}"


def _grafana_health() -> tuple[int, int]:
    status, _ = _request(f"{GRAFANA_URL}/api/health")
    authorization = _grafana_authorization()
    if authorization is None:
        return status, 0
    datasource_status, _ = _request(
        f"{GRAFANA_URL}/api/datasources/uid/haruka-local-loki/health",
        authorization=authorization,
    )
    return status, datasource_status


def _grafana_loki_query(instance_id: str) -> tuple[int, bool]:
    authorization = _grafana_authorization()
    if authorization is None:
        return 0, False
    query = f'{{project="haruka",environment="test"}} | json | instance_id="{instance_id}"'
    parameters = urllib.parse.urlencode(
        {
            "query": query,
            "start": str(int((datetime.now(UTC) - timedelta(hours=6)).timestamp() * 1_000_000_000)),
            "limit": "1",
        }
    )
    status, raw = _request(
        f"{GRAFANA_URL}/api/datasources/proxy/uid/haruka-local-loki/loki/api/v1/query_range?{parameters}",
        authorization=authorization,
    )
    if status != 200:
        return status, False
    try:
        document: object = json.loads(raw)
        if not is_object(document) or document.get("status") != "success":
            return status, False
        data = document.get("data")
        return status, is_object(data) and bool(data.get("result"))
    except ValueError:
        return status, False


def _postgres_engine_source(instance_id: str) -> dict[str, object]:
    """Report only safe settings and counts, never PostgreSQL log message bodies."""
    settings_query = (
        "SELECT json_object_agg(name, setting)::text FROM pg_settings "
        "WHERE name IN ('log_line_prefix','log_connections','log_disconnections',"
        "'log_lock_waits','log_min_duration_statement','log_min_error_statement',"
        "'log_error_verbosity',"
        "'log_parameter_max_length','log_parameter_max_length_on_error',"
        "'log_statement','logging_collector')"
    )
    result = subprocess.run(  # noqa: S603 - fixed local Docker/psql inspection; no caller command input.
        [  # noqa: S607 - repository-owned local Docker CLI, static container and SQL.
            "docker",
            "exec",
            POSTGRES_CONTAINER,
            "psql",
            "-U",
            "haruka_bootstrap",
            "-d",
            "haruka_test",
            "-At",
            "-v",
            "ON_ERROR_STOP=1",
            "-c",
            settings_query,
        ],
        capture_output=True,
        check=False,
        timeout=8,
    )
    try:
        settings: object = json.loads(result.stdout) if result.returncode == 0 else None
    except ValueError:
        settings = None
    if not is_object(settings):
        return {
            "settings_available": False,
            "source_captured": False,
            "run_attributed": False,
        }

    safe_names = (
        "log_connections",
        "log_disconnections",
        "log_lock_waits",
        "log_min_duration_statement",
        "log_min_error_statement",
        "log_error_verbosity",
        "log_parameter_max_length",
        "log_parameter_max_length_on_error",
        "log_statement",
        "logging_collector",
    )
    safe_settings = {
        name: settings.get(name) for name in safe_names if isinstance(settings.get(name), str)
    }
    prefix = settings.get("log_line_prefix")
    has_database = isinstance(prefix, str) and "%d" in prefix
    has_application = isinstance(prefix, str) and "%a" in prefix
    has_sqlstate = isinstance(prefix, str) and "%e" in prefix

    query = '{project="haruka",service="postgres"}'
    parameters = urllib.parse.urlencode(
        {
            "query": query,
            "start": str(int((datetime.now(UTC) - timedelta(hours=6)).timestamp() * 1_000_000_000)),
            "limit": "1000",
            "direction": "backward",
        }
    )
    status, raw = _request(f"{LOKI_URL}/loki/api/v1/query_range?{parameters}")
    line_count = 0
    attributed_count = 0
    if status == 200:
        try:
            document: object = json.loads(raw)
            data = document.get("data") if is_object(document) else None
            if is_object(data):
                results = data.get("result")
                if _is_array(results):
                    for stream in results:
                        values = stream.get("values") if is_object(stream) else None
                        if not _is_array(values):
                            continue
                        for row in values:
                            if _is_array(row) and len(row) == 2 and isinstance(row[1], str):
                                line_count += 1
                                if instance_id in row[1]:
                                    attributed_count += 1
        except ValueError:
            pass
    return {
        "settings_available": True,
        "settings": safe_settings,
        "prefix_has_database": has_database,
        "prefix_has_application": has_application,
        "prefix_has_sqlstate": has_sqlstate,
        "loki_http_status": status,
        "sample_line_count": line_count,
        "run_line_count": attributed_count,
        "sample_may_be_truncated": line_count >= 1000,
        "source_captured": status == 200 and line_count > 0,
        "run_attributed": (
            status == 200
            and attributed_count > 0
            and has_database
            and has_application
            and has_sqlstate
        ),
    }


async def _mail_state(run_id: str) -> dict[str, object]:
    config = LOCAL_ROOT / run_id / "runtime.env"
    if not config.is_file():
        return {"available": False}
    settings = load_settings(config)
    if (
        settings.instance_id != f"haruka-test-{run_id}"
        or settings.test_schema != f"haruka_migration_test_{run_id}"
    ):
        raise ProofError("mail proof configuration differs from isolated run")
    database = Database(settings.core_infrastructure())
    try:
        await database.check()
        async with database.sessions() as session:
            rows = (
                await session.execute(
                    select(
                        AuthChallengeDelivery.status,
                        AuthChallengeDelivery.attempt_count,
                    )
                )
            ).all()
        counts = Counter(str(status) for status, _attempts in rows)
        return {
            "available": True,
            "status_counts": dict(sorted(counts.items())),
            "max_attempt_count": max((attempts for _status, attempts in rows), default=0),
        }
    finally:
        await database.aclose()


def _summary(events: list[dict[str, object]]) -> dict[str, object]:
    names = Counter(str(event.get("event")) for event in events)
    services = Counter(str(event.get("service")) for event in events)
    operations = {
        str(value)
        for event in events
        if (value := event.get("operation_id")) is not None
        and isinstance(value, str)
        and _valid_uuid(value)
    }
    request_count = sum(
        isinstance(event.get("request_id"), str) and _valid_uuid(str(event["request_id"]))
        for event in events
    )
    return {
        "count": len(events),
        "event_counts": dict(sorted(names.items())),
        "service_counts": dict(sorted(services.items())),
        "request_correlated_count": request_count,
        "operation_ids": sorted(operations)[:5],
        "operation_ids_truncated": len(operations) > 5,
    }


@dataclass
class _CorrelationGroup:
    client: int = 0
    http: int = 0
    business: int = 0
    database: int = 0
    requests: set[str] = field(default_factory=_empty_requests)

    def counts(self) -> dict[str, int]:
        return {
            "client": self.client,
            "http": self.http,
            "business": self.business,
            "database": self.database,
        }


def _correlation_chain(events: list[dict[str, object]]) -> dict[str, object]:
    groups: dict[str, _CorrelationGroup] = {}
    business: set[str] = {
        "auth.registration.accepted",
        "auth.email.verified",
        "auth.login.succeeded",
        "auth.login.rejected",
        "auth.login.action_required",
        "auth.session.revoked",
        "auth.password.changed",
        "auth.password.recovered",
        "auth.policy.updated",
        "auth.verification.request.accepted",
        "auth.recovery.request.accepted",
        "collection.saved",
        "mail.delivery.sent",
        "mail.delivery.retry_or_failed",
    }
    for event in events:
        operation = event.get("operation_id")
        if not isinstance(operation, str) or not _valid_uuid(operation):
            continue
        group = groups.setdefault(operation, _CorrelationGroup())
        name = event.get("event")
        if event.get("origin") == "client":
            group.client += 1
        elif name in {"http.completed", "http.failed"}:
            group.http += 1
        elif isinstance(name, str) and name.startswith("database."):
            group.database += 1
        elif name in business:
            group.business += 1
        request = event.get("request_id")
        if isinstance(request, str) and _valid_uuid(request):
            group.requests.add(request)
    ordered = sorted(
        groups.items(),
        key=lambda item: (
            -sum(int(value > 0) for value in item[1].counts().values()),
            -sum(item[1].counts().values()),
            item[0],
        ),
    )
    if not ordered:
        return {"available": False, "complete": False}
    operation, group = ordered[0]
    request_list = sorted(group.requests)
    counts = group.counts()
    return {
        "available": True,
        "complete": all(counts.values()),
        "operation_id": operation,
        "event_counts": counts,
        "request_ids": request_list[:5],
        "request_ids_truncated": len(request_list) > 5,
    }


def _valid_uuid(value: str) -> bool:
    try:
        UUID(value)
    except ValueError:
        return False
    return True


def _sentinel_receipt(run_id: str, sentinel: bytes | None) -> dict[str, object]:
    if sentinel is None:
        return {"verified": False}
    path = LOCAL_ROOT / run_id / "telemetry-sentinel-receipt.json"
    if not path.is_file() or path.is_symlink():
        return {"verified": False}
    try:
        value: object = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"verified": False}
    if not is_object(value):
        return {"verified": False}
    event_id = value.get("event_id")
    request_id = value.get("request_id")
    verified = (
        value.get("run_id") == run_id
        and value.get("http_status") == 200
        and value.get("item_status") == "rejected"
        and value.get("reason") == "invalid_record"
        and value.get("sentinel_sha256") == hashlib.sha256(sentinel).hexdigest()
        and isinstance(event_id, str)
        and _valid_uuid(event_id)
        and isinstance(request_id, str)
        and _valid_uuid(request_id)
    )
    return {
        "verified": verified,
        "event_id": event_id if verified else None,
        "request_id": request_id if verified else None,
    }


async def collect(run_id: str, sentinel: bytes | None) -> dict[str, object]:
    instance_id = f"haruka-test-{run_id}"
    local_lines, file_count = await asyncio.to_thread(_local_lines, run_id)
    loki_status, loki_lines, truncated = await asyncio.to_thread(_loki_lines, instance_id)
    local_events = _events(local_lines, instance_id)
    loki_events = _events(loki_lines, instance_id)
    local_ids = {
        value
        for event in local_events
        if isinstance((value := event.get("event_id")), str) and _valid_uuid(value)
    }
    loki_ids = {
        value
        for event in loki_events
        if isinstance((value := event.get("event_id")), str) and _valid_uuid(value)
    }
    grafana_status, datasource_status = await asyncio.to_thread(_grafana_health)
    grafana_query_status, grafana_query_matched = await asyncio.to_thread(
        _grafana_loki_query, instance_id
    )
    postgres_source = await asyncio.to_thread(_postgres_engine_source, instance_id)
    receipt = _sentinel_receipt(run_id, sentinel)
    probe_request_id = receipt.get("request_id")
    alloy = await asyncio.to_thread(
        subprocess.run,
        ["docker", "inspect", "--format", "{{.State.Running}}", "haruka-local-alloy-1"],
        capture_output=True,
        check=False,
        timeout=5,
    )
    return {
        "schema_version": 1,
        "run_id": run_id,
        "instance_id": instance_id,
        "observed_at": datetime.now(UTC).isoformat(),
        "local_file_count": file_count,
        "local": _summary(local_events),
        "loki_http_status": loki_status,
        "loki_result_truncated": truncated,
        "loki": _summary(loki_events),
        "loki_matching_event_id_count": len(local_ids & loki_ids),
        "correlation_chain_local": _correlation_chain(local_events),
        "correlation_chain_loki": _correlation_chain(loki_events),
        "alloy_running": alloy.returncode == 0 and alloy.stdout.strip() == b"true",
        "grafana_health_status": grafana_status,
        "grafana_loki_datasource_status": datasource_status,
        "grafana_loki_query_status": grafana_query_status,
        "grafana_loki_query_matched": grafana_query_matched,
        "postgres_engine_source": postgres_source,
        "mail_delivery": await _mail_state(run_id),
        "sentinel_checked": sentinel is not None,
        "sentinel_injection_verified": receipt["verified"],
        "sentinel_probe_request_id": probe_request_id,
        "sentinel_probe_http_log_local": any(
            event.get("request_id") == probe_request_id and event.get("event") == "http.completed"
            for event in local_events
        )
        if receipt["verified"]
        else False,
        "sentinel_probe_http_log_loki": any(
            event.get("request_id") == probe_request_id and event.get("event") == "http.completed"
            for event in loki_events
        )
        if receipt["verified"]
        else False,
        "sentinel_absent_local": sentinel is not None
        and all(sentinel not in line.encode("utf-8") for line in local_lines),
        "sentinel_absent_loki": sentinel is not None
        and all(sentinel not in line.encode("utf-8") for line in loki_lines),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize isolated log collection safely")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--sentinel-file", type=Path)
    args = parser.parse_args()
    try:
        if RUN.fullmatch(args.run_id) is None:
            raise ProofError("invalid isolated run id")
        if re.fullmatch(r"[a-z][a-z0-9-]{0,23}", args.label) is None:
            raise ProofError("invalid proof label")
        sentinel: bytes | None = None
        if args.sentinel_file is not None:
            marker = args.sentinel_file
            if (
                marker.is_symlink()
                or marker.resolve().parent != (LOCAL_ROOT / args.run_id).resolve()
            ):
                raise ProofError("sentinel file must belong to this isolated run")
            candidate = marker.read_bytes().strip()
            if not 8 <= len(candidate) <= 100:
                raise ProofError("invalid sentinel length")
            sentinel = candidate
        proof = asyncio.run(collect(args.run_id, sentinel))
        PROOF_ROOT.mkdir(parents=True, exist_ok=True)
        path = PROOF_ROOT / f"observability-{args.run_id}-{args.label}.json"
        with path.open("x", encoding="utf-8") as stream:
            json.dump(proof, stream, indent=2, sort_keys=True)
            stream.write("\n")
        sys.stdout.write(f"{path.relative_to(ROOT).as_posix()}\n")
        return 0
    except (OSError, ProofError, subprocess.SubprocessError):
        sys.stderr.write("isolated observability proof failed\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
