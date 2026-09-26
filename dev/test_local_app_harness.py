"""Focused checks for the current slice local-only mailbox and HTTPS gateway."""

from __future__ import annotations

import asyncio
import hashlib
import http.client
import json
import os
import smtplib
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from dev import (
    isolated_app_run,
    local_https_gateway,
    local_smtp_capture,
    local_web_static,
)


class ReleaseWebChecks(unittest.TestCase):
    def test_web_rebuild_requires_stopped_run_and_preserves_previous_release(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            local_root = workspace / "dev/.local/b1"
            run_id = "b" * 32
            owned = local_root / run_id
            owned.mkdir(parents=True)
            schema = f"haruka_migration_test_{run_id}"
            (owned / "ledger.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "run_id": run_id,
                        "schema": schema,
                        "state": "serving",
                    }
                ),
                encoding="utf-8",
            )
            source = workspace / "frontend/build/web"
            source.mkdir(parents=True)
            (source / "index.html").write_text("new release", encoding="utf-8")
            (source / "main.dart.js").write_text("new program", encoding="utf-8")
            previous = owned / "web"
            previous.mkdir()
            (previous / "index.html").write_text("old release", encoding="utf-8")
            settings = SimpleNamespace(
                instance_id=f"haruka-test-{run_id}", test_schema=schema
            )
            with (
                patch.object(isolated_app_run, "ROOT", workspace),
                patch.object(isolated_app_run, "LOCAL_ROOT", local_root),
                patch.object(local_web_static, "LOCAL_ROOT", local_root),
                patch.object(isolated_app_run, "load_settings", return_value=settings),
                patch.object(
                    isolated_app_run, "tool", return_value=["flutter"]
                ) as flutter_tool,
                patch.object(
                    local_smtp_capture, "current_windows_sid", return_value="S-1-5-21-1"
                ),
                patch.object(
                    isolated_app_run.subprocess,
                    "run",
                    return_value=SimpleNamespace(returncode=0),
                ),
            ):
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.build_web(run_id, replace=True)
                self.assertEqual((previous / "index.html").read_text(), "old release")
                flutter_tool.assert_not_called()
                (owned / "ledger.json").write_text(
                    json.dumps(
                        {
                            "version": 1,
                            "run_id": run_id,
                            "schema": schema,
                            "state": "stopped",
                        }
                    ),
                    encoding="utf-8",
                )
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.build_web(run_id)
                isolated_app_run.build_web(run_id, replace=True)
                self.assertEqual((owned / "web/index.html").read_text(), "new release")
                retained = list(owned.glob("web.previous.*"))
                self.assertEqual(len(retained), 1)
                self.assertEqual(
                    (retained[0] / "index.html").read_text(), "old release"
                )

    def test_web_publish_retries_a_transient_stage_lock(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory)
            owned = local_root / ("a" * 32)
            stage = owned / "web.next"
            target = owned / "web"
            stage.mkdir(parents=True)
            target.mkdir()
            (stage / "index.html").write_text("new", encoding="utf-8")
            (stage / "main.dart.js").write_text("new program", encoding="utf-8")
            (target / "index.html").write_text("old", encoding="utf-8")
            original_rename = Path.rename
            stage_attempts = 0

            def transient_rename(path: Path, destination: Path) -> Path:
                nonlocal stage_attempts
                if path == stage and destination == target:
                    stage_attempts += 1
                    if stage_attempts == 1:
                        raise PermissionError(13, "transient directory lock")
                return original_rename(path, destination)

            with (
                patch.object(local_web_static, "LOCAL_ROOT", local_root),
                patch.object(Path, "rename", transient_rename),
                patch.object(isolated_app_run.time, "sleep"),
            ):
                isolated_app_run.publish_web_stage(target, stage)
            self.assertEqual(stage_attempts, 2)
            self.assertEqual((target / "index.html").read_text(), "new")
            retained = list(owned.glob("web.previous.*"))
            self.assertEqual(len(retained), 1)
            self.assertEqual((retained[0] / "index.html").read_text(), "old")

    def test_web_publish_restores_old_release_after_stage_move_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            owned = Path(directory) / ("a" * 32)
            stage = owned / "web.next"
            target = owned / "web"
            stage.mkdir(parents=True)
            target.mkdir()
            (stage / "index.html").write_text("new", encoding="utf-8")
            (stage / "main.dart.js").write_text("new program", encoding="utf-8")
            (target / "index.html").write_text("old", encoding="utf-8")
            original_rename = Path.rename

            def locked_stage_rename(path: Path, destination: Path) -> Path:
                if path == stage and destination == target:
                    raise PermissionError(13, "persistent directory lock")
                return original_rename(path, destination)

            with (
                patch.object(Path, "rename", locked_stage_rename),
                patch.object(isolated_app_run.time, "sleep"),
                self.assertRaisesRegex(
                    isolated_app_run.IsolatedRunError, "previous release restored"
                ),
            ):
                isolated_app_run.publish_web_stage(target, stage)
            self.assertEqual((target / "index.html").read_text(), "old")
            self.assertEqual((stage / "index.html").read_text(), "new")
            self.assertEqual(list(owned.glob("web.previous.*")), [])

    def test_web_recovery_requires_stopped_run_and_verified_build(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            local_root = workspace / "dev/.local/b1"
            run_id = "b" * 32
            owned = local_root / run_id
            stage = owned / "web.next"
            stage.mkdir(parents=True)
            source = workspace / "frontend/build/web"
            source.mkdir(parents=True)
            program = (f"haruka-test-{run_id} https://localhost:18443").encode("ascii")
            digest = hashlib.sha256(program).hexdigest()
            for path in (stage, source):
                (path / "index.html").write_text("release", encoding="utf-8")
                (path / "main.dart.js").write_bytes(program)
            (stage / "flutter_bootstrap.js").write_text("first", encoding="utf-8")
            (source / "flutter_bootstrap.js").write_text("later", encoding="utf-8")
            schema = f"haruka_migration_test_{run_id}"
            ledger = owned / "ledger.json"
            ledger.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "run_id": run_id,
                        "schema": schema,
                        "state": "serving",
                    }
                ),
                encoding="utf-8",
            )
            settings = SimpleNamespace(
                instance_id=f"haruka-test-{run_id}", test_schema=schema
            )
            with (
                patch.object(isolated_app_run, "ROOT", workspace),
                patch.object(isolated_app_run, "LOCAL_ROOT", local_root),
                patch.object(local_web_static, "LOCAL_ROOT", local_root),
                patch.object(isolated_app_run, "load_settings", return_value=settings),
            ):
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.recover_web(run_id, expected_main_sha=digest)
                ledger.write_text(
                    json.dumps(
                        {
                            "version": 1,
                            "run_id": run_id,
                            "schema": schema,
                            "state": "stopped",
                        }
                    ),
                    encoding="utf-8",
                )
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.recover_web(run_id, expected_main_sha="0" * 64)
                self.assertTrue(stage.is_dir())
                self.assertFalse((owned / "web").exists())
                isolated_app_run.recover_web(run_id, expected_main_sha=digest)
                self.assertEqual((owned / "web/index.html").read_text(), "release")

    def test_static_release_serves_assets_and_deep_links_without_directory_listing(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory)
            web = local_root / ("a" * 32) / "web"
            web.mkdir(parents=True)
            (web / "index.html").write_bytes(b"<html>release</html>")
            (web / "main.dart.js").write_bytes(b"release-js")
            (web / "assets").mkdir()
            with patch.object(local_web_static, "LOCAL_ROOT", local_root):
                self.assertEqual(local_web_static.validate_web_root(web), web)
                server = ThreadingHTTPServer(
                    ("127.0.0.1", 0),
                    partial(local_web_static.StaticHandler, directory=str(web)),
                )
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                try:
                    connection = http.client.HTTPConnection(
                        "127.0.0.1", server.server_port, timeout=2
                    )
                    for path, expected in (
                        ("/admin/login", b"<html>release</html>"),
                        ("/verify-email", b"<html>release</html>"),
                        ("/reset-password", b"<html>release</html>"),
                        ("/main.dart.js", b"release-js"),
                    ):
                        connection.request("GET", path)
                        response = connection.getresponse()
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.read(), expected)
                    connection.request("GET", "/assets/")
                    response = connection.getresponse()
                    self.assertEqual(response.status, 404)
                    response.read()
                    for path in ("/assets/missing", "/api/v1/missing"):
                        connection.request("GET", path)
                        response = connection.getresponse()
                        self.assertEqual(response.status, 404)
                        response.read()
                    connection.close()
                finally:
                    server.shutdown()
                    server.server_close()
                    thread.join(timeout=2)


class MailboxChecks(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.spool = self.root / "b1run123" / "mail"
        self.root_patch = patch.object(local_smtp_capture, "LOCAL_ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.server = await asyncio.start_server(
            lambda reader, writer: local_smtp_capture.serve_client(
                reader, writer, self.spool
            ),
            host="127.0.0.1",
            port=0,
        )
        self.addAsyncCleanup(self.close_server)

    async def close_server(self) -> None:
        self.server.close()
        await self.server.wait_closed()

    async def test_capture_rejects_external_recipient_and_extracts_fragment_privately(
        self,
    ) -> None:
        port = self.server.sockets[0].getsockname()[1]

        def send() -> None:
            with smtplib.SMTP("127.0.0.1", port, timeout=3) as client:
                with self.assertRaises(smtplib.SMTPRecipientsRefused):
                    client.sendmail(
                        "sender@example.test",
                        ["outside@example.com"],
                        "Subject: reject\r\n\r\nExternal recipient",
                    )
                client.rset()
                client.sendmail(
                    "sender@example.test",
                    ["alpha@haruka.example.test"],
                    "Subject: verify\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
                    "https://localhost:18443/verify-email#token=opaque-test-value",
                )

        await asyncio.to_thread(send)
        output = self.spool / "extracted.txt"
        local_smtp_capture.extract_link(
            self.spool, "alpha@haruka.example.test", "verify", output, 0
        )
        self.assertEqual(
            output.read_text(encoding="utf-8").strip(),
            "https://localhost:18443/verify-email#token=opaque-test-value",
        )
        self.assertEqual(len(list(self.spool.glob("*.eml"))), 1)
        if os.name == "nt":
            acl = await asyncio.to_thread(
                subprocess.run,
                ["icacls", str(self.spool)],
                capture_output=True,
                check=True,
            )
            self.assertNotIn("(I)", acl.stdout.decode("utf-8", errors="replace"))
        with self.assertRaises(FileExistsError):
            local_smtp_capture.extract_link(
                self.spool, "alpha@haruka.example.test", "verify", output, 0
            )

    async def test_oversized_data_is_not_captured(self) -> None:
        port = self.server.sockets[0].getsockname()[1]

        def send() -> None:
            with (
                smtplib.SMTP("127.0.0.1", port, timeout=3) as client,
                self.assertRaises(smtplib.SMTPServerDisconnected),
            ):
                client.sendmail(
                    "sender@example.test",
                    ["alpha@haruka.example.test"],
                    "Subject: too large\r\n\r\n" + "X" * 128,
                )

        with patch.object(local_smtp_capture, "MAX_MESSAGE_BYTES", 64):
            await asyncio.to_thread(send)
        self.assertEqual(list(self.spool.glob("*.eml")), [])

    async def test_guard_rejects_spool_outside_run_root(self) -> None:
        with self.assertRaises(local_smtp_capture.MailboxError):
            local_smtp_capture.guarded_spool(self.root.parent / "someone-else" / "mail")


class GatewayChecks(unittest.TestCase):
    def test_real_tls_gateway_preserves_api_cookies_csrf_and_deep_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_root = Path(directory) / "b1run123"
            cert, key = local_https_gateway.create_certificate(run_root)
            self.assertEqual(
                (cert, key), local_https_gateway.create_certificate(run_root)
            )
            seen: list[tuple[str, str, str, bytes]] = []

            class Api(BaseHTTPRequestHandler):
                def log_message(self, format: str, *args: object) -> None:
                    return

                def do_POST(self) -> None:
                    body = self.rfile.read(int(self.headers["Content-Length"]))
                    seen.append(
                        (
                            self.path,
                            self.headers["Origin"],
                            self.headers["X-CSRF-Token"],
                            body,
                        )
                    )
                    self.send_response(201)
                    self.send_header(
                        "Set-Cookie", "client=one; Secure; HttpOnly; SameSite=Lax"
                    )
                    self.send_header("Set-Cookie", "csrf=two; Secure; SameSite=Lax")
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", "2")
                    self.end_headers()
                    self.wfile.write(b"{}")

            class Web(BaseHTTPRequestHandler):
                def log_message(self, format: str, *args: object) -> None:
                    return

                def do_GET(self) -> None:
                    if self.path == "/failure":
                        self.connection.shutdown(socket.SHUT_RDWR)
                        self.connection.close()
                        return
                    seen.append((self.path, "", "", b""))
                    payload = b"<html>Flutter</html>"
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)

            api = ThreadingHTTPServer(("127.0.0.1", 0), Api)
            web = ThreadingHTTPServer(("127.0.0.1", 0), Web)
            old_api = local_https_gateway.LocalProxy.api_port
            old_web = local_https_gateway.LocalProxy.web_port
            old_timeout = local_https_gateway.LocalProxy.upstream_timeout
            local_https_gateway.LocalProxy.api_port = api.server_port
            local_https_gateway.LocalProxy.web_port = web.server_port
            local_https_gateway.LocalProxy.upstream_timeout = 0.5
            gateway = ThreadingHTTPServer(
                ("127.0.0.1", 0), local_https_gateway.LocalProxy
            )
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.load_cert_chain(str(cert), str(key))
            gateway.socket = tls.wrap_socket(gateway.socket, server_side=True)
            threads = [
                threading.Thread(target=server.serve_forever, daemon=True)
                for server in (api, web, gateway)
            ]
            for thread in threads:
                thread.start()
            try:
                trust = ssl.create_default_context(cafile=str(cert))
                trust.hostname_checks_common_name = False
                connection = http.client.HTTPSConnection(
                    "localhost", gateway.server_port, context=trust, timeout=2
                )
                body = json.dumps({"operation": "test"}).encode("utf-8")
                connection.request(
                    "POST",
                    "/api/v1/auth/login",
                    body=body,
                    headers={
                        "Content-Type": "application/json",
                        "Origin": "https://localhost:18443",
                        "X-CSRF-Token": "synthetic-csrf",
                    },
                )
                response = connection.getresponse()
                self.assertEqual(response.status, 201)
                self.assertEqual(response.read(), b"{}")
                self.assertEqual(
                    response.headers.get_all("Set-Cookie"),
                    [
                        "client=one; Secure; HttpOnly; SameSite=Lax",
                        "csrf=two; Secure; SameSite=Lax",
                    ],
                )
                self.assertEqual(
                    seen[0],
                    (
                        "/api/v1/auth/login",
                        "https://localhost:18443",
                        "synthetic-csrf",
                        body,
                    ),
                )
                connection.request("GET", "/verify-email")
                page = connection.getresponse()
                self.assertEqual(page.status, 200)
                self.assertEqual(page.read(), b"<html>Flutter</html>")
                self.assertEqual(seen[1][0], "/")
                connection.close()

                failure = http.client.HTTPSConnection(
                    "localhost", gateway.server_port, context=trust, timeout=2
                )
                started = time.monotonic()
                failure.request("GET", "/failure")
                failed_response = failure.getresponse()
                self.assertEqual(failed_response.status, 502)
                self.assertEqual(
                    failed_response.read(), b"Isolated upstream unavailable"
                )
                self.assertLess(time.monotonic() - started, 3)
                failure.close()
            finally:
                for server in (gateway, web, api):
                    server.shutdown()
                    server.server_close()
                for thread in threads:
                    thread.join(timeout=2)
                local_https_gateway.LocalProxy.api_port = old_api
                local_https_gateway.LocalProxy.web_port = old_web
                local_https_gateway.LocalProxy.upstream_timeout = old_timeout


class RunnerBoundaryChecks(unittest.TestCase):
    def test_login_only_scenario_uses_existing_verified_owner_in_owned_schema(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_id = "e" * 32
            schema = f"haruka_migration_test_{run_id}"
            user_id = uuid4()
            settings = SimpleNamespace(
                app_env="test", instance_id=f"haruka-test-{run_id}", test_schema=schema
            )
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", Path(directory)),
                patch.object(isolated_app_run, "load_settings", return_value=settings),
                patch.object(isolated_app_run, "isolated_maintenance") as maintenance,
                patch(
                    "tests.support.identity_scenarios.prepare_login_only_user",
                    new_callable=AsyncMock,
                    return_value=user_id,
                ) as prepare_user,
            ):
                root = isolated_app_run.run_root(run_id)
                root.mkdir()
                isolated_app_run.write_ledger(
                    root, run_id=run_id, state="prepared", schema=schema
                )
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    asyncio.run(
                        isolated_app_run.prepare_login_only(
                            run_id, "limited@haruka.example.test"
                        )
                    )
                prepare_user.assert_not_awaited()
                isolated_app_run.write_ledger(
                    root, run_id=run_id, state="serving", schema=schema
                )
                self.assertEqual(
                    asyncio.run(
                        isolated_app_run.prepare_login_only(
                            run_id, "limited@haruka.example.test"
                        )
                    ),
                    str(user_id),
                )
                prepare_user.assert_awaited_once_with(
                    maintenance.return_value, email="limited@haruka.example.test"
                )

    def test_process_absence_check_rejects_live_or_malformed_pids(self) -> None:
        self.assertTrue(
            isolated_app_run.confirmed_processes_absent(
                [{"pid": 99999999, "target_pid": 99999998}]
            )
        )
        self.assertFalse(
            isolated_app_run.confirmed_processes_absent(
                [{"pid": os.getpid(), "target_pid": os.getpid()}]
            )
        )
        self.assertFalse(
            isolated_app_run.confirmed_processes_absent(
                [{"pid": True, "target_pid": 99}]
            )
        )

    def test_run_id_and_ledger_must_match_exact_owned_schema(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_id = "a" * 32
            with patch.object(isolated_app_run, "LOCAL_ROOT", Path(directory)):
                root = isolated_app_run.run_root(run_id)
                root.mkdir()
                isolated_app_run.write_ledger(
                    root,
                    run_id=run_id,
                    state="created",
                    schema=f"haruka_migration_test_{run_id}",
                )
                self.assertEqual(
                    isolated_app_run.read_ledger(root, run_id)["state"], "created"
                )
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.run_root("../public")
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.read_ledger(root, "b" * 32)

    def test_running_ledger_cannot_trigger_schema_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_id = "b" * 32
            with patch.object(isolated_app_run, "LOCAL_ROOT", Path(directory)):
                root = isolated_app_run.run_root(run_id)
                root.mkdir()
                isolated_app_run.write_ledger(
                    root,
                    run_id=run_id,
                    state="serving",
                    schema=f"haruka_migration_test_{run_id}",
                )
                with patch.object(isolated_app_run, "remove_owned_schema") as drop:
                    with self.assertRaises(isolated_app_run.IsolatedRunError):
                        asyncio.run(isolated_app_run.cleanup(run_id))
                    drop.assert_not_called()

    def test_cleanup_records_progress_before_drop_and_can_resume(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_id = "c" * 32
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", Path(directory)),
                patch.object(local_smtp_capture, "LOCAL_ROOT", Path(directory)),
                patch.object(
                    isolated_app_run,
                    "remove_owned_cache_namespace",
                    new_callable=AsyncMock,
                ) as clear_cache,
                patch.object(
                    isolated_app_run, "remove_owned_schema", new_callable=AsyncMock
                ) as drop,
            ):
                root = isolated_app_run.run_root(run_id)
                root.mkdir()
                schema = f"haruka_migration_test_{run_id}"
                isolated_app_run.write_ledger(
                    root, run_id=run_id, state="prepared", schema=schema
                )
                drop.side_effect = [RuntimeError("interrupted"), None]
                with self.assertRaises(RuntimeError):
                    asyncio.run(isolated_app_run.cleanup(run_id))
                self.assertEqual(
                    isolated_app_run.read_ledger(root, run_id)["state"], "cleaning"
                )
                asyncio.run(isolated_app_run.cleanup(run_id))
                self.assertEqual(
                    isolated_app_run.read_ledger(root, run_id)["state"], "cleaned"
                )
                self.assertEqual(clear_cache.await_count, 2)
                self.assertEqual(drop.await_count, 2)

    def test_serving_run_requires_owned_stop_report_and_process_absence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_id = "d" * 32
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", Path(directory)),
                patch.object(local_smtp_capture, "LOCAL_ROOT", Path(directory)),
                patch.object(
                    isolated_app_run,
                    "remove_owned_cache_namespace",
                    new_callable=AsyncMock,
                ),
                patch.object(
                    isolated_app_run, "remove_owned_schema", new_callable=AsyncMock
                ),
            ):
                root = isolated_app_run.run_root(run_id)
                root.mkdir()
                schema = f"haruka_migration_test_{run_id}"
                isolated_app_run.write_ledger(
                    root, run_id=run_id, state="serving", schema=schema
                )
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    asyncio.run(isolated_app_run.cleanup(run_id))
                (root / "stop-report.json").write_text(
                    '[{"pid": 99999999, "target_pid": 99999998}]', encoding="utf-8"
                )
                with (
                    patch.object(
                        isolated_app_run,
                        "confirmed_processes_absent",
                        return_value=False,
                    ),
                    self.assertRaises(isolated_app_run.IsolatedRunError),
                ):
                    asyncio.run(isolated_app_run.cleanup(run_id))
                with patch.object(
                    isolated_app_run, "confirmed_processes_absent", return_value=True
                ):
                    asyncio.run(isolated_app_run.cleanup(run_id))
                self.assertEqual(
                    isolated_app_run.read_ledger(root, run_id)["state"], "cleaned"
                )

    @unittest.skipUnless(
        os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
        == "dev/.local/test-maintenance.env",
        "requires explicit isolated PostgreSQL maintenance target",
    )
    def test_real_pg_schema_marker_and_repeatable_owned_cleanup(self) -> None:
        from app.maintenance.settings import create_maintenance_engine
        from sqlalchemy import text

        run_id = uuid4().hex
        schema = f"haruka_migration_test_{run_id}"

        async def exercise() -> None:
            await isolated_app_run.create_owned_schema(schema, run_id)
            try:
                engine = create_maintenance_engine(isolated_app_run.test_maintenance())
                try:
                    async with engine.connect() as connection:
                        marker = await connection.scalar(
                            text(
                                "SELECT obj_description(oid, 'pg_namespace') "
                                "FROM pg_namespace WHERE nspname=:schema"
                            ),
                            {"schema": schema},
                        )
                    self.assertEqual(marker, f"haruka-b1-run:{run_id}")
                    with self.assertRaises(isolated_app_run.IsolatedRunError):
                        await isolated_app_run.remove_owned_schema(schema, "f" * 32)
                finally:
                    await engine.dispose()
            finally:
                await isolated_app_run.remove_owned_schema(schema, run_id)
            await isolated_app_run.remove_owned_schema(
                schema, run_id, allow_missing=True
            )

        asyncio.run(exercise())


if __name__ == "__main__":
    unittest.main()
