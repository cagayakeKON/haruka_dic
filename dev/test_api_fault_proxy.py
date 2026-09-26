"""Protocol checks for the opt-in, isolated API fault transport."""

from __future__ import annotations

import http.client
import json
import math
import socket
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from dev import local_api_fault_proxy


class FaultProxyProtocolChecks(unittest.TestCase):
    def test_telemetry_receipt_extracts_only_bounded_target_event_ids(self) -> None:
        first = str(uuid4())
        second = str(uuid4())
        secret = "secret-body-and-token"
        body = json.dumps(
            {
                "events": [
                    {"event_id": first, "attributes": {"text": secret}},
                    {"event_id": second, "stack": secret},
                    {"event_id": first},
                ]
            }
        ).encode()
        self.assertEqual(
            local_api_fault_proxy.telemetry_event_ids("/api/v1/frontend-logs", body),
            sorted([first, second]),
        )
        self.assertEqual(
            local_api_fault_proxy.telemetry_event_ids(
                "/api/v1/admin/frontend-logs", body
            ),
            sorted([first, second]),
        )
        exact_limit = body + b" " * (
            local_api_fault_proxy.MAX_TELEMETRY_PROOF_BYTES - len(body)
        )
        self.assertEqual(
            local_api_fault_proxy.telemetry_event_ids(
                "/api/v1/frontend-logs", exact_limit
            ),
            sorted([first, second]),
        )
        self.assertEqual(
            local_api_fault_proxy.telemetry_event_ids(
                "/api/v1/frontend-logs", exact_limit + b" "
            ),
            [],
        )
        self.assertEqual(
            local_api_fault_proxy.telemetry_event_ids("/api/v1/collections", body),
            [],
        )
        for invalid in (
            b"not-json",
            json.dumps({"events": [{"event_id": "not-a-uuid"}]}).encode(),
            json.dumps(
                {"events": [{"event_id": "00000000-0000-1000-8000-000000000000"}]}
            ).encode(),
            json.dumps({"events": [{}]}).encode(),
            json.dumps({"events": [{"event_id": first}] * 21}).encode(),
            b"{" + b" " * (128 * 1024) + b"}",
        ):
            self.assertEqual(
                local_api_fault_proxy.telemetry_event_ids(
                    "/api/v1/frontend-logs", invalid
                ),
                [],
            )

    def test_unavailable_upstream_returns_bounded_safe_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            unavailable = socket.socket()
            unavailable.bind(("127.0.0.1", 0))
            unused_port = unavailable.getsockname()[1]
            unavailable.close()
            previous_port = local_api_fault_proxy.FaultHandler.upstream_port
            previous_state = getattr(local_api_fault_proxy.FaultHandler, "state", None)
            local_api_fault_proxy.FaultHandler.upstream_port = unused_port
            local_api_fault_proxy.FaultHandler.state = local_api_fault_proxy.FaultState(
                root, uuid4().hex
            )
            proxy = ThreadingHTTPServer(
                ("127.0.0.1", 0), local_api_fault_proxy.FaultHandler
            )
            thread = threading.Thread(target=proxy.serve_forever, daemon=True)
            thread.start()
            try:
                connection = http.client.HTTPConnection(
                    "127.0.0.1", proxy.server_port, timeout=15
                )
                connection.request("GET", "/api/v1/meta?private-query=sentinel")
                response = connection.getresponse()
                self.assertEqual(response.status, 502)
                self.assertEqual(response.read(), b"Isolated upstream unavailable")
                connection.close()
                self.assertEqual(list(root.glob("fault.receipt.*.json")), [])
            finally:
                proxy.shutdown()
                proxy.server_close()
                thread.join(timeout=2)
                local_api_fault_proxy.FaultHandler.upstream_port = previous_port
                if previous_state is not None:
                    local_api_fault_proxy.FaultHandler.state = previous_state

    def test_disarm_then_new_rule_applies_to_the_first_matching_request(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory)
            run_id = uuid4().hex
            root = local_root / run_id
            root.mkdir()
            (root / "fault-proxy.enabled").write_text("enabled", encoding="utf-8")
            state = local_api_fault_proxy.FaultState(root, run_id)
            with patch.object(local_api_fault_proxy, "LOCAL_ROOT", local_root):
                first = local_api_fault_proxy.arm(
                    run_id,
                    mode="before_503",
                    method="POST",
                    path="/api/v1/frontend-logs",
                    count=2,
                    duration_seconds=30,
                )
                first_claimed = state.claim("POST", "/api/v1/frontend-logs")
                self.assertIsNotNone(first_claimed)
                self.assertEqual(
                    first_claimed["rule_id"] if first_claimed else None, first
                )
                local_api_fault_proxy.disarm(run_id, first)
                second = local_api_fault_proxy.arm(
                    run_id,
                    mode="after_response_drop",
                    method="POST",
                    path="/api/v1/collections",
                    duration_seconds=30,
                )
                claimed = state.claim("POST", "/api/v1/collections")
                self.assertIsNotNone(claimed)
                self.assertEqual(claimed["rule_id"] if claimed else None, second)

    def test_expired_pending_rule_can_be_explicitly_disarmed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory)
            run_id = uuid4().hex
            root = local_root / run_id
            root.mkdir()
            (root / "fault-proxy.enabled").write_text("enabled", encoding="utf-8")
            with patch.object(local_api_fault_proxy, "LOCAL_ROOT", local_root):
                rule_id = local_api_fault_proxy.arm(
                    run_id,
                    mode="before_503",
                    method="POST",
                    path="/api/v1/frontend-logs",
                    duration_seconds=1,
                )
                future = time.time() + 5
                with patch.object(
                    local_api_fault_proxy.time, "time", return_value=future
                ):
                    local_api_fault_proxy.disarm(run_id, rule_id)
                self.assertFalse(local_api_fault_proxy.control_path(root).exists())
                self.assertTrue((root / f"fault.cancel.{rule_id}").is_file())

    def test_receipt_is_atomic_and_nonfinite_expiry_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run_id = uuid4().hex
            state = local_api_fault_proxy.FaultState(root, run_id)
            rule: local_api_fault_proxy.Rule = {
                "version": 1,
                "run_id": run_id,
                "rule_id": uuid4().hex,
                "mode": "before_503",
                "method": "POST",
                "path": "/api/v1/frontend-logs",
                "remaining": 1,
                "expires_at": time.time() + 30,
                "delay_ms": 0,
            }
            for invalid in (math.nan, math.inf, -math.inf):
                with self.assertRaises(local_api_fault_proxy.FaultProxyError):
                    local_api_fault_proxy.validate_rule(
                        {**rule, "expires_at": invalid}, run_id
                    )
            written = threading.Event()
            release = threading.Event()
            original_write = local_api_fault_proxy.write_private
            failures: list[Exception] = []

            def held_write(path: Path, document: dict[str, object]) -> None:
                original_write(path, document)
                if path.name.startswith("fault.next.receipt."):
                    written.set()
                    if not release.wait(timeout=3):
                        raise AssertionError("atomic receipt test timed out")

            def issue_receipt() -> None:
                try:
                    state.receipt(
                        rule,
                        operation_id=str(uuid4()),
                        client_request_id=None,
                        upstream_status=None,
                        injected=True,
                    )
                except (OSError, AssertionError) as error:
                    failures.append(error)

            with patch.object(
                local_api_fault_proxy, "write_private", side_effect=held_write
            ):
                worker = threading.Thread(target=issue_receipt)
                worker.start()
                try:
                    self.assertTrue(written.wait(timeout=2))
                    self.assertEqual(list(root.glob("fault.receipt.*.json")), [])
                finally:
                    release.set()
                    worker.join(timeout=3)
            self.assertEqual(failures, [])
            receipts = list(root.glob("fault.receipt.*.json"))
            self.assertEqual(len(receipts), 1)
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["rule_id"],
                rule["rule_id"],
            )

    def test_claim_waits_for_complete_atomic_rule_publication(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory)
            run_id = uuid4().hex
            root = local_root / run_id
            root.mkdir()
            (root / "fault-proxy.enabled").write_text("enabled", encoding="utf-8")
            written = threading.Event()
            release = threading.Event()
            claimed_done = threading.Event()
            armed: list[str] = []
            claimed: list[local_api_fault_proxy.Rule | None] = []
            failures: list[Exception] = []
            original_write = local_api_fault_proxy.write_private

            def held_write(path: Path, document: dict[str, object]) -> None:
                original_write(path, document)
                if path.name.startswith("fault.next."):
                    written.set()
                    if not release.wait(timeout=3):
                        raise AssertionError("atomic publication test timed out")

            def arm_worker() -> None:
                try:
                    armed.append(
                        local_api_fault_proxy.arm(
                            run_id,
                            mode="before_503",
                            method="POST",
                            path="/api/v1/frontend-logs",
                            duration_seconds=30,
                        )
                    )
                except (
                    local_api_fault_proxy.FaultProxyError,
                    OSError,
                    AssertionError,
                ) as error:
                    failures.append(error)

            state = local_api_fault_proxy.FaultState(root, run_id)

            def claim_worker() -> None:
                try:
                    claimed.append(state.claim("POST", "/api/v1/frontend-logs"))
                except (local_api_fault_proxy.FaultProxyError, OSError) as error:
                    failures.append(error)
                finally:
                    claimed_done.set()

            with (
                patch.object(local_api_fault_proxy, "LOCAL_ROOT", local_root),
                patch.object(
                    local_api_fault_proxy, "write_private", side_effect=held_write
                ),
            ):
                writer = threading.Thread(target=arm_worker)
                reader = threading.Thread(target=claim_worker)
                writer.start()
                try:
                    self.assertTrue(written.wait(timeout=2))
                    self.assertFalse(local_api_fault_proxy.control_path(root).exists())
                    reader.start()
                    self.assertFalse(claimed_done.wait(timeout=0.1))
                finally:
                    release.set()
                    writer.join(timeout=3)
                    if reader.ident is not None:
                        reader.join(timeout=3)
            self.assertEqual(failures, [])
            self.assertEqual(len(armed), 1)
            self.assertEqual(len(claimed), 1)
            self.assertIsNotNone(claimed[0])
            self.assertEqual(claimed[0]["rule_id"] if claimed[0] else None, armed[0])

    def test_allowlisted_faults_preserve_real_request_and_safe_receipts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory)
            run_id = uuid4().hex
            root = local_root / run_id
            root.mkdir()
            (root / "fault-proxy.enabled").write_text("enabled", encoding="utf-8")
            seen: list[tuple[str, str, bytes, str, str, str]] = []
            committed: dict[str, bytes] = {}

            class Upstream(BaseHTTPRequestHandler):
                protocol_version = "HTTP/1.1"

                def log_message(self, format: str, *args: object) -> None:
                    return

                def do_POST(self) -> None:
                    body = self.rfile.read(int(self.headers["Content-Length"]))
                    seen.append(
                        (
                            self.command,
                            self.path,
                            body,
                            self.headers.get("Origin", ""),
                            self.headers.get("X-CSRF-Token", ""),
                            self.headers.get("Cookie", ""),
                        )
                    )
                    key = self.headers.get("Idempotency-Key", "")
                    payload = committed.setdefault(key, b'{"id":"same-business-uuid"}')
                    self.send_response_only(201)
                    self.send_header("Set-Cookie", "one=1; Secure; HttpOnly")
                    self.send_header("Set-Cookie", "two=2; Secure; HttpOnly")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)

                def do_GET(self) -> None:
                    seen.append((self.command, self.path, b"", "", "", ""))
                    payload = b"bounded-source"
                    self.send_response_only(200)
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)

            upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
            original_port = local_api_fault_proxy.FaultHandler.upstream_port
            original_state = getattr(local_api_fault_proxy.FaultHandler, "state", None)
            with patch.object(local_api_fault_proxy, "LOCAL_ROOT", local_root):
                local_api_fault_proxy.FaultHandler.upstream_port = upstream.server_port
                local_api_fault_proxy.FaultHandler.state = (
                    local_api_fault_proxy.FaultState(root, run_id)
                )
                proxy = ThreadingHTTPServer(
                    ("127.0.0.1", 0), local_api_fault_proxy.FaultHandler
                )
                threads = [
                    threading.Thread(target=server.serve_forever, daemon=True)
                    for server in (upstream, proxy)
                ]
                for thread in threads:
                    thread.start()
                try:
                    operation_id = str(uuid4())
                    request_id = str(uuid4())
                    headers = {
                        "Content-Type": "application/json",
                        "Origin": "https://localhost:18443",
                        "X-CSRF-Token": "secret-csrf",
                        "Cookie": "secret-cookie",
                        "Idempotency-Key": "secret-idempotency",
                        "X-Operation-ID": operation_id,
                        "X-Client-Request-ID": request_id,
                    }

                    def call(
                        method: str, path: str, body: bytes | None = None
                    ) -> tuple[int, bytes, list[tuple[str, str]]]:
                        connection = http.client.HTTPConnection(
                            "127.0.0.1", proxy.server_port, timeout=3
                        )
                        try:
                            connection.request(method, path, body=body, headers=headers)
                            response = connection.getresponse()
                            return (
                                response.status,
                                response.read(),
                                response.getheaders(),
                            )
                        finally:
                            connection.close()

                    with self.assertRaises(local_api_fault_proxy.FaultProxyError):
                        local_api_fault_proxy.arm(
                            run_id,
                            mode="before_503",
                            method="POST",
                            path="/api/v1/login",
                            count=1,
                        )
                    rule_id = local_api_fault_proxy.arm(
                        run_id,
                        mode="before_503",
                        method="POST",
                        path="/api/v1/frontend-logs",
                        count=2,
                        duration_seconds=30,
                    )
                    telemetry_event_id = str(uuid4())
                    telemetry_body = json.dumps(
                        {
                            "events": [
                                {
                                    "event_id": telemetry_event_id,
                                    "attributes": {"text": "secret-body"},
                                }
                            ]
                        }
                    ).encode()
                    for _ in range(2):
                        status, _, _ = call(
                            "POST", "/api/v1/frontend-logs", telemetry_body
                        )
                        self.assertEqual(status, 503)
                    self.assertEqual(len(seen), 0)
                    self.assertEqual(
                        call("POST", "/api/v1/frontend-logs", b"secret-body")[0], 201
                    )
                    self.assertEqual(len(seen), 1)
                    injected_receipts = [
                        json.loads(path.read_text(encoding="utf-8"))
                        for path in root.glob("fault.receipt.*.json")
                    ]
                    self.assertEqual(
                        [
                            item["event_ids"]
                            for item in injected_receipts
                            if item["rule_id"] == rule_id
                        ],
                        [[telemetry_event_id], [telemetry_event_id]],
                    )
                    admin_rule_id = local_api_fault_proxy.arm(
                        run_id,
                        mode="before_503",
                        method="POST",
                        path="/api/v1/admin/frontend-logs",
                        duration_seconds=30,
                    )
                    self.assertEqual(
                        call("POST", "/api/v1/admin/frontend-logs", telemetry_body)[0],
                        503,
                    )
                    admin_receipts = [
                        json.loads(path.read_text(encoding="utf-8"))
                        for path in root.glob("fault.receipt.*.json")
                        if admin_rule_id in path.read_text(encoding="utf-8")
                    ]
                    self.assertEqual(len(admin_receipts), 1)
                    self.assertEqual(
                        admin_receipts[0]["event_ids"], [telemetry_event_id]
                    )
                    self.assertEqual(
                        admin_receipts[0]["path"], "/api/v1/admin/frontend-logs"
                    )

                    local_api_fault_proxy.arm(
                        run_id,
                        mode="after_response_drop",
                        method="POST",
                        path="/api/v1/collections",
                        duration_seconds=30,
                    )
                    with self.assertRaises(
                        (http.client.RemoteDisconnected, ConnectionResetError)
                    ):
                        call("POST", "/api/v1/collections", b"secret-body")
                    status, payload, response_headers = call(
                        "POST", "/api/v1/collections", b"secret-body"
                    )
                    self.assertEqual(status, 201)
                    self.assertEqual(payload, b'{"id":"same-business-uuid"}')
                    self.assertEqual(
                        [
                            value
                            for key, value in response_headers
                            if key.lower() == "set-cookie"
                        ],
                        ["one=1; Secure; HttpOnly", "two=2; Secure; HttpOnly"],
                    )
                    self.assertEqual(len(committed), 1)
                    self.assertEqual(
                        seen[-1][2:],
                        (
                            b"secret-body",
                            "https://localhost:18443",
                            "secret-csrf",
                            "secret-cookie",
                        ),
                    )

                    local_api_fault_proxy.arm(
                        run_id,
                        mode="delay_response",
                        method="GET",
                        path="/api/v1/materials",
                        delay_ms=250,
                        duration_seconds=30,
                    )
                    started = time.monotonic()
                    self.assertEqual(
                        call("GET", "/api/v1/materials?limit=1&cursor=secret-cursor")[
                            0
                        ],
                        200,
                    )
                    self.assertGreaterEqual(time.monotonic() - started, 0.2)
                    self.assertEqual(
                        seen[-1][1], "/api/v1/materials?limit=1&cursor=secret-cursor"
                    )
                    deadline = time.monotonic() + 2
                    while (
                        len(list(root.glob("fault.receipt.*.json"))) < 5
                        and time.monotonic() < deadline
                    ):
                        time.sleep(0.01)
                    receipts = [
                        json.loads(path.read_text(encoding="utf-8"))
                        for path in root.glob("fault.receipt.*.json")
                    ]
                    self.assertEqual(len(receipts), 5)
                    self.assertTrue(all(item["run_id"] == run_id for item in receipts))
                    self.assertTrue(
                        any(item["operation_id"] == operation_id for item in receipts)
                    )
                    written = json.dumps(receipts)
                    for secret in (
                        "secret-body",
                        "secret-cookie",
                        "secret-csrf",
                        "secret-idempotency",
                        "secret-cursor",
                    ):
                        self.assertNotIn(secret, written)
                finally:
                    for server in (proxy, upstream):
                        server.shutdown()
                        server.server_close()
                    for thread in threads:
                        thread.join(timeout=2)
                    local_api_fault_proxy.FaultHandler.upstream_port = original_port
                    if original_state is not None:
                        local_api_fault_proxy.FaultHandler.state = original_state


if __name__ == "__main__":
    unittest.main()
