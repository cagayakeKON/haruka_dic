"""Loopback-only, opt-in HTTP fault transport for an owned isolated test run.

Rules live in the run's private directory. The proxy never records request or
response bodies, query strings, headers, or authentication material. An injected
authenticated telemetry failure records only canonical event UUIDs from its bounded
batch so later delivery can be verified against the same events.
"""

from __future__ import annotations

import argparse
import contextlib
import http.client
import json
import math
import os
import re
import socket
import sys
import threading
import time
from collections.abc import Generator
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Literal, TypedDict, cast
from urllib.parse import urlsplit
from uuid import UUID, uuid4

from dev.local_smtp_capture import LOCAL_ROOT, private_directory, restrict_private_file

RUN_ID = re.compile(r"[0-9a-f]{32}\Z")
COLLECTION_PATH = "/api/v1/collections"
TELEMETRY_PATHS = frozenset(
    {
        "/api/v1/frontend-logs",
        "/api/v1/admin/frontend-logs",
        "/api/v1/frontend-logs/anonymous",
    }
)
DELAY_PATHS = frozenset({"/api/v1/materials", COLLECTION_PATH})
MAX_BODY_BYTES = 2_097_152
MAX_RESPONSE_BYTES = 4_194_304
MAX_TELEMETRY_PROOF_BYTES = 128 * 1024
Mode = Literal["before_503", "after_response_drop", "delay_response"]


class FaultProxyError(Exception):
    """Safe diagnostic without caller-controlled request content."""


class Rule(TypedDict):
    version: int
    run_id: str
    rule_id: str
    mode: Mode
    method: str
    path: str
    remaining: int
    expires_at: float
    delay_ms: int


def owned_root(run_id: str) -> Path:
    if not RUN_ID.fullmatch(run_id):
        raise FaultProxyError("invalid isolated run identity")
    root = LOCAL_ROOT / run_id
    if root.is_symlink() or root.resolve().parent != LOCAL_ROOT.resolve():
        raise FaultProxyError("fault control escaped the isolated run")
    if not root.is_dir():
        raise FaultProxyError("isolated run directory is missing")
    return root


def control_path(root: Path) -> Path:
    return root / "fault.pending.json"


def active_path(root: Path) -> Path:
    return root / "fault.active.json"


def write_private(path: Path, document: dict[str, object]) -> None:
    if path.is_symlink():
        raise FaultProxyError("fault control path is a symbolic link")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, separators=(",", ":"), sort_keys=True)
            stream.write("\n")
        restrict_private_file(path)
    except BaseException:
        path.unlink(missing_ok=True)
        raise


@contextlib.contextmanager
def control_lock(root: Path) -> Generator[None, None, None]:
    """Serialize rule publication, claim, and cancellation across processes."""
    path = root / "fault-control.lock"
    if path.is_symlink():
        raise FaultProxyError("fault lock is linked")
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        restrict_private_file(path)
        if os.name == "nt":
            import msvcrt

            os.lseek(descriptor, 0, os.SEEK_SET)
            msvcrt.locking(descriptor, msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                os.lseek(descriptor, 0, os.SEEK_SET)
                msvcrt.locking(descriptor, msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(descriptor, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(descriptor, fcntl.LOCK_UN)
    finally:
        os.close(descriptor)


def validate_rule(document: object, run_id: str) -> Rule:
    if not isinstance(document, dict):
        raise FaultProxyError("invalid fault control document")
    value = cast("dict[str, object]", document)
    mode = value.get("mode")
    method = value.get("method")
    path = value.get("path")
    count = value.get("remaining")
    expires_at = value.get("expires_at")
    delay_ms = value.get("delay_ms")
    rule_id = value.get("rule_id")
    if (
        set(value)
        != {
            "version",
            "run_id",
            "rule_id",
            "mode",
            "method",
            "path",
            "remaining",
            "expires_at",
            "delay_ms",
        }
        or value.get("version") != 1
        or value.get("run_id") != run_id
        or not isinstance(rule_id, str)
        or not RUN_ID.fullmatch(rule_id)
        or not isinstance(method, str)
        or not isinstance(path, str)
        or type(count) is not int
        or not isinstance(expires_at, (int, float))
        or isinstance(expires_at, bool)
        or not math.isfinite(expires_at)
        or type(delay_ms) is not int
    ):
        raise FaultProxyError("invalid fault control document")
    allowed = (
        (
            mode == "before_503"
            and method == "POST"
            and path in TELEMETRY_PATHS
            and 1 <= count <= 20
            and delay_ms == 0
        )
        or (
            mode == "after_response_drop"
            and method == "POST"
            and path == COLLECTION_PATH
            and count == 1
            and delay_ms == 0
        )
        or (
            mode == "delay_response"
            and method == "GET"
            and path in DELAY_PATHS
            and count == 1
            and 1 <= delay_ms <= 5000
        )
    )
    if not allowed or expires_at <= time.time() or expires_at > time.time() + 125:
        raise FaultProxyError("fault control is expired or outside the allowlist")
    return cast("Rule", value)


def read_rule(path: Path, run_id: str) -> Rule:
    if path.is_symlink() or not path.is_file():
        raise FaultProxyError("fault control file is missing or linked")
    try:
        return validate_rule(json.loads(path.read_text(encoding="utf-8")), run_id)
    except (OSError, ValueError) as error:
        raise FaultProxyError("fault control document could not be read") from error


def arm(
    run_id: str,
    *,
    mode: Mode,
    method: str,
    path: str,
    count: int = 1,
    duration_seconds: int = 120,
    delay_ms: int = 0,
) -> str:
    root = owned_root(run_id)
    if not (root / "fault-proxy.enabled").is_file():
        raise FaultProxyError("this isolated run is not serving with the fault proxy")
    if not 1 <= duration_seconds <= 120:
        raise FaultProxyError("fault duration must be within 120 seconds")
    rule_id = uuid4().hex
    rule = cast(
        "Rule",
        {
            "version": 1,
            "run_id": run_id,
            "rule_id": rule_id,
            "mode": mode,
            "method": method,
            "path": path,
            "remaining": count,
            "expires_at": time.time() + duration_seconds,
            "delay_ms": delay_ms,
        },
    )
    validate_rule(rule, run_id)
    with control_lock(root):
        if control_path(root).exists() or active_path(root).exists():
            raise FaultProxyError("this run already has a pending fault rule")
        temporary = root / f"fault.next.{rule_id}.json"
        try:
            write_private(temporary, cast("dict[str, object]", rule))
            # No reader sees a partially serialized rule; the lock also keeps
            # claim/disarm from observing an intermediate rename.
            os.rename(temporary, control_path(root))
        finally:
            temporary.unlink(missing_ok=True)
    return rule_id


def disarm(run_id: str, rule_id: str) -> None:
    root = owned_root(run_id)
    if not RUN_ID.fullmatch(rule_id):
        raise FaultProxyError("invalid fault rule identity")
    with control_lock(root):
        matching: list[Path] = []
        for path in (control_path(root), active_path(root)):
            if path.exists():
                if path.is_symlink() or not path.is_file():
                    raise FaultProxyError("fault control is linked or missing")
                try:
                    document: object = json.loads(path.read_text(encoding="utf-8"))
                except (OSError, ValueError) as error:
                    raise FaultProxyError("fault control cannot be read") from error
                fields = (
                    cast("dict[str, object]", document)
                    if isinstance(document, dict)
                    else None
                )
                if (
                    fields is None
                    or fields.get("run_id") != run_id
                    or fields.get("rule_id") != rule_id
                ):
                    raise FaultProxyError(
                        "fault rule identity differs from active control"
                    )
                matching.append(path)
        if not matching:
            raise FaultProxyError("fault rule is no longer active")
        # A marker also cancels a rule already held in the proxy's memory. It
        # is scoped to a unique ID, so later rules remain usable.
        write_private(
            root / f"fault.cancel.{rule_id}", {"run_id": run_id, "rule_id": rule_id}
        )
        for path in matching:
            path.unlink(missing_ok=True)


def canonical_uuid(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        parsed = UUID(value)
    except (ValueError, AttributeError):
        return None
    return str(parsed) if str(parsed) == value else None


def telemetry_event_ids(path: str, body: bytes | None) -> list[str]:
    """Extract only bounded canonical v4 event IDs from an authenticated log batch."""
    if (
        path not in {"/api/v1/frontend-logs", "/api/v1/admin/frontend-logs"}
        or body is None
        or not 0 < len(body) <= MAX_TELEMETRY_PROOF_BYTES
    ):
        return []
    try:
        document: object = json.loads(body)
    except (UnicodeDecodeError, ValueError):
        return []
    if not isinstance(document, dict):
        return []
    events: object = cast("dict[str, object]", document).get("events")
    if not isinstance(events, list):
        return []
    typed_events = cast("list[object]", events)
    if not 1 <= len(typed_events) <= 20:
        return []
    identifiers: list[str] = []
    for raw in typed_events:
        if not isinstance(raw, dict):
            return []
        event_id = cast("dict[str, object]", raw).get("event_id")
        if not isinstance(event_id, str):
            return []
        canonical = canonical_uuid(event_id)
        if canonical is None or UUID(canonical).version != 4:
            return []
        identifiers.append(canonical)
    return sorted(set(identifiers))


class FaultState:
    def __init__(self, root: Path, run_id: str) -> None:
        self.root = root
        self.run_id = run_id
        self.lock = threading.Lock()
        self.current: Rule | None = None

    def claim(self, method: str, path: str) -> Rule | None:
        with self.lock, control_lock(self.root):
            old = self.current
            if old is not None and (
                (self.root / f"fault.cancel.{old['rule_id']}").exists()
                or time.time() >= old["expires_at"]
            ):
                self.current = None
                active_path(self.root).unlink(missing_ok=True)
            if self.current is None and control_path(self.root).is_file():
                pending = control_path(self.root)
                try:
                    rule = read_rule(pending, self.run_id)
                except FaultProxyError:
                    pending.unlink(missing_ok=True)
                    return None
                os.replace(pending, active_path(self.root))
                self.current = rule
            rule = self.current
            if rule is None:
                return None
            if rule["method"] != method or rule["path"] != path:
                return None
            rule["remaining"] -= 1
            claimed = cast("Rule", dict(rule))
            if rule["remaining"] == 0:
                self.current = None
                active_path(self.root).unlink(missing_ok=True)
            return claimed

    def receipt(
        self,
        rule: Rule,
        *,
        operation_id: str | None,
        client_request_id: str | None,
        upstream_status: int | None,
        injected: bool,
        event_ids: list[str] | None = None,
    ) -> None:
        receipt_id = uuid4().hex
        temporary = self.root / f"fault.next.receipt.{receipt_id}.json"
        published = self.root / f"fault.receipt.{receipt_id}.json"
        try:
            write_private(
                temporary,
                {
                    "run_id": self.run_id,
                    "rule_id": rule["rule_id"],
                    "mode": rule["mode"],
                    "method": rule["method"],
                    "path": rule["path"],
                    "operation_id": operation_id,
                    "client_request_id": client_request_id,
                    "upstream_status": upstream_status,
                    "injected": injected,
                    "event_ids": event_ids if event_ids is not None else [],
                    "at": datetime.now(UTC).isoformat(),
                },
            )
            os.rename(temporary, published)
        finally:
            temporary.unlink(missing_ok=True)


class FaultHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "HarukaIsolatedTransport"
    sys_version = ""
    upstream_port = 18082
    state: FaultState

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        self.forward()

    def do_POST(self) -> None:
        self.forward()

    def do_PATCH(self) -> None:
        self.forward()

    def do_PUT(self) -> None:
        self.forward()

    def do_DELETE(self) -> None:
        self.forward()

    def do_OPTIONS(self) -> None:
        self.forward()

    def _safe_response(self, status: int, payload: bytes) -> None:
        self.send_response_only(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)
        self.close_connection = True

    def forward(self) -> None:
        connection: http.client.HTTPConnection | None = None
        try:
            raw_length = self.headers.get("Content-Length")
            if self.command in {"POST", "PUT", "PATCH"} and raw_length is None:
                self._safe_response(411, b"Length required")
                return
            length = int(raw_length or "0")
            if (
                length < 0
                or length > MAX_BODY_BYTES
                or "Transfer-Encoding" in self.headers
            ):
                self._safe_response(413, b"Request too large")
                return
            body = self.rfile.read(length) if length else None
            path = urlsplit(self.path).path
            rule = self.state.claim(self.command, path)
            operation_id = canonical_uuid(self.headers.get("X-Operation-ID"))
            client_request_id = canonical_uuid(self.headers.get("X-Client-Request-ID"))
            if rule is not None and rule["mode"] == "before_503":
                self.state.receipt(
                    rule,
                    operation_id=operation_id,
                    client_request_id=client_request_id,
                    upstream_status=None,
                    injected=True,
                    event_ids=telemetry_event_ids(path, body),
                )
                self._safe_response(503, b"Isolated service unavailable")
                return
            connection = http.client.HTTPConnection(
                "127.0.0.1", self.upstream_port, timeout=12
            )
            connection.putrequest(self.command, self.path, skip_host=True)
            for key, value in self.headers.items():
                if key.lower() not in {
                    "host",
                    "connection",
                    "transfer-encoding",
                    "content-length",
                }:
                    connection.putheader(key, value)
            connection.putheader("Host", f"127.0.0.1:{self.upstream_port}")
            if body is not None:
                connection.putheader("Content-Length", str(length))
            connection.endheaders(body)
            response = connection.getresponse()
            if response.length is not None and response.length > MAX_RESPONSE_BYTES:
                raise FaultProxyError(
                    "upstream response exceeds isolated transport limit"
                )
            payload = response.read(MAX_RESPONSE_BYTES + 1)
            if len(payload) > MAX_RESPONSE_BYTES:
                raise FaultProxyError(
                    "upstream response exceeds isolated transport limit"
                )
            status = response.status
            if (
                rule is not None
                and rule["mode"] == "after_response_drop"
                and 200 <= status < 300
            ):
                self.state.receipt(
                    rule,
                    operation_id=operation_id,
                    client_request_id=client_request_id,
                    upstream_status=status,
                    injected=True,
                )
                self.close_connection = True
                with contextlib.suppress(OSError):
                    self.connection.shutdown(socket.SHUT_RDWR)
                return
            if rule is not None and rule["mode"] == "delay_response":
                time.sleep(rule["delay_ms"] / 1000)
            self.send_response_only(status, response.reason)
            for key, value in response.getheaders():
                if key.lower() not in {
                    "connection",
                    "transfer-encoding",
                    "content-length",
                }:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            if rule is not None:
                self.state.receipt(
                    rule,
                    operation_id=operation_id,
                    client_request_id=client_request_id,
                    upstream_status=status,
                    injected=rule["mode"] == "delay_response",
                )
        except (OSError, ValueError, http.client.HTTPException, FaultProxyError):
            with contextlib.suppress(OSError):
                self._safe_response(502, b"Isolated upstream unavailable")
        finally:
            if connection is not None:
                connection.close()


def serve(run_id: str, port: int, upstream_port: int, shutdown_file: Path) -> None:
    root = owned_root(run_id)
    if (
        not 1 <= port <= 65535
        or not 1 <= upstream_port <= 65535
        or port == upstream_port
        or not shutdown_file.is_absolute()
        or shutdown_file.resolve().parent != root
        or shutdown_file.exists()
        or not (root / "fault-proxy.enabled").is_file()
    ):
        raise FaultProxyError("invalid isolated fault proxy process configuration")
    private_directory(root)
    FaultHandler.upstream_port = upstream_port
    FaultHandler.state = FaultState(root, run_id)
    server = ThreadingHTTPServer(("127.0.0.1", port), FaultHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        while not shutdown_file.exists():
            time.sleep(0.1)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Owned loopback API fault transport")
    commands = parser.add_subparsers(dest="command", required=True)
    serving = commands.add_parser("serve")
    serving.add_argument("--run-id", required=True)
    serving.add_argument("--port", type=int, default=18081)
    serving.add_argument("--upstream-port", type=int, default=18082)
    serving.add_argument("--shutdown-file", type=Path, required=True)
    arming = commands.add_parser("arm")
    arming.add_argument("--run-id", required=True)
    arming.add_argument(
        "--mode",
        choices=["before_503", "after_response_drop", "delay_response"],
        required=True,
    )
    arming.add_argument("--method", required=True)
    arming.add_argument("--path", required=True)
    arming.add_argument("--count", type=int, default=1)
    arming.add_argument("--duration-seconds", type=int, default=120)
    arming.add_argument("--delay-ms", type=int, default=0)
    disarming = commands.add_parser("disarm")
    disarming.add_argument("--run-id", required=True)
    disarming.add_argument("--rule-id", required=True)
    args = parser.parse_args()
    try:
        if args.command == "serve":
            serve(args.run_id, args.port, args.upstream_port, args.shutdown_file)
        elif args.command == "arm":
            print(
                arm(
                    args.run_id,
                    mode=args.mode,
                    method=args.method,
                    path=args.path,
                    count=args.count,
                    duration_seconds=args.duration_seconds,
                    delay_ms=args.delay_ms,
                )
            )
        else:
            disarm(args.run_id, args.rule_id)
        return 0
    except (FaultProxyError, OSError):
        print("isolated API fault transport failed safely", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
