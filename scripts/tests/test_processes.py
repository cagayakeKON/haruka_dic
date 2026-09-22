"""Real owned-process lifecycle checks; no existing applications or ports are stopped."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from collections.abc import Callable
from pathlib import Path
from unittest.mock import patch

from scripts import dev, development, processes


def wait_until(condition: Callable[[], bool], timeout: float = 5) -> None:
    deadline = time.monotonic() + timeout
    while not condition():
        if time.monotonic() >= deadline:
            raise AssertionError("Owned process did not reach the required state")
        time.sleep(0.02)


def write_config(root: Path) -> Path:
    path = root / "runtime.env"
    path.write_text(
        "HARUKA_APP_ENV=dev\nHARUKA_INSTANCE_ID=haruka-local-dev\n"
        "HARUKA_RESOURCE_NAMESPACE=haruka-local-dev\nHARUKA_INFRASTRUCTURE_ENABLED=true\n"
        'HARUKA_PUBLIC_BASE_URL=http://127.0.0.1:8000\nHARUKA_ALLOWED_ORIGINS=["http://localhost:5173"]\n',
        encoding="utf-8",
    )
    return path


class OwnedProcessChecks(unittest.TestCase):
    def test_graceful_parent_with_residual_descendant_is_forced_and_keeps_outsider(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outsider = subprocess.Popen(
                [sys.executable, "-c", "import time; time.sleep(120)"],
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            )
            owner = processes.ProcessOwner("test-residual", "haruka-test-process")
            try:
                script = root / "parent.py"
                script.write_text(
                    "import os, pathlib, subprocess, sys, time\n"
                    "source = 'import pathlib,signal,socket,sys,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); s=socket.socket(); s.bind((\"127.0.0.1\",0)); s.listen(); pathlib.Path(sys.argv[1]).write_text(str(s.getsockname()[1])); time.sleep(120)'\n"
                    "subprocess.Popen([sys.executable, '-c', source, sys.argv[1]], creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)\n"
                    "while not pathlib.Path(sys.argv[2]).exists(): time.sleep(0.02)\n",
                    encoding="utf-8",
                )
                marker = root / "port"
                child = owner.start(
                    "parent",
                    [sys.executable, str(script), str(marker), str(root / "stop")],
                    cwd=root,
                    shutdown_file=root / "stop",
                )
                wait_until(marker.exists)
                port = int(marker.read_text(encoding="utf-8"))
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    pass
                results = owner.stop(grace_seconds=1)
                self.assertEqual(results[0]["exit_code"], 0)
                remaining = results[0]["remaining_app_processes"]
                self.assertTrue(isinstance(remaining, int) and remaining > 0)
                self.assertTrue(results[0]["forced"])
                self.assertIsNotNone(child.process.poll())
                wait_until(lambda: self.port_closed(port))
                self.assertIsNone(outsider.poll())
            finally:
                owner.stop(grace_seconds=0.1)
                outsider.terminate()
                outsider.wait(timeout=3)

    def test_graceful_marker_shutdown_preserves_identity_and_is_repeatable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = root / "worker.py"
            script.write_text(
                "import pathlib, sys, time\n"
                "while not pathlib.Path(sys.argv[1]).exists(): time.sleep(0.02)\n",
                encoding="utf-8",
            )
            owner = processes.ProcessOwner("test-graceful", "haruka-test-process")
            try:
                child = owner.start(
                    "fixture",
                    [sys.executable, str(script), str(root / "stop")],
                    cwd=root,
                    shutdown_file=root / "stop",
                )
                self.assertEqual(child.identity["namespace"], "haruka-test-process")
                wait_until(lambda: (child.collect(), child.target_pid is not None)[1])
                results = owner.stop(grace_seconds=3)
                self.assertEqual(results[0]["exit_code"], 0)
                self.assertFalse(results[0]["forced"], results)
                self.assertEqual(results[0]["remaining_app_processes"], 0)
                self.assertIsNotNone(child.process.poll())
                self.assertEqual(owner.stop(), results)
            finally:
                owner.stop(grace_seconds=0.2)

    def test_forced_cleanup_removes_descendant_but_keeps_unrelated_process(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outsider = subprocess.Popen(
                [sys.executable, "-c", "import time; time.sleep(120)"],
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            )
            owner = processes.ProcessOwner("test-forced", "haruka-test-process")
            try:
                script = root / "tree.py"
                script.write_text(
                    "import os, pathlib, subprocess, sys, time\n"
                    "source = 'import pathlib,signal,socket,sys,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); s=socket.socket(); s.bind((\"127.0.0.1\",0)); s.listen(); pathlib.Path(sys.argv[1]).write_text(str(s.getsockname()[1])); time.sleep(120)'\n"
                    "subprocess.Popen([sys.executable, '-c', source, sys.argv[1]], creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)\n"
                    "time.sleep(120)\n",
                    encoding="utf-8",
                )
                marker = root / "port"
                child = owner.start("tree", [sys.executable, str(script), str(marker)], cwd=root)
                wait_until(marker.exists)
                port = int(marker.read_text(encoding="utf-8"))
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    pass
                results = owner.stop(grace_seconds=0.1)
                self.assertTrue(results[0]["forced"])
                self.assertIsNotNone(child.process.poll())
                wait_until(lambda: self.port_closed(port))
                self.assertIsNone(outsider.poll())
            finally:
                owner.stop(grace_seconds=0.1)
                outsider.terminate()
                outsider.wait(timeout=3)

    @staticmethod
    def port_closed(port: int) -> bool:
        with socket.socket() as probe:
            probe.settimeout(0.2)
            return probe.connect_ex(("127.0.0.1", port)) != 0

    def test_failed_child_reports_actual_exit_and_cleans_its_supervisor(self) -> None:
        owner = processes.ProcessOwner("test-failed", "haruka-test-process")
        try:
            child = owner.start(
                "failed", [sys.executable, "-c", "raise SystemExit(9)"], cwd=Path.cwd()
            )
            wait_until(lambda: (child.collect(), child.target_exit is not None)[1])
            with self.assertRaises(processes.ProcessError):
                owner.require_running()
            results = owner.stop(grace_seconds=0.1)
            self.assertEqual(results[0]["exit_code"], 9)
            self.assertIsNotNone(child.process.poll())
        finally:
            owner.stop(grace_seconds=0.1)

    def test_second_process_failure_still_closes_the_first_process(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = root / "first.py"
            script.write_text(
                "import pathlib,sys,time\nwhile not pathlib.Path(sys.argv[1]).exists(): time.sleep(0.02)\n",
                encoding="utf-8",
            )
            owner = processes.ProcessOwner("test-partial-startup", "haruka-test-process")
            try:
                first = owner.start(
                    "first",
                    [sys.executable, str(script), str(root / "stop")],
                    cwd=root,
                    shutdown_file=root / "stop",
                )
                second = owner.start(
                    "failed", [sys.executable, "-c", "raise SystemExit(9)"], cwd=root
                )
                wait_until(lambda: (second.collect(), second.target_exit is not None)[1])
                with self.assertRaises(processes.ProcessError):
                    owner.require_running()
                results = owner.stop(grace_seconds=3)
                self.assertEqual(
                    {item["name"]: item["exit_code"] for item in results}, {"first": 0, "failed": 9}
                )
                self.assertIsNotNone(first.process.poll())
                self.assertIsNotNone(second.process.poll())
            finally:
                owner.stop(grace_seconds=0.1)

    def test_missing_executable_fails_without_starting_a_process(self) -> None:
        owner = processes.ProcessOwner("test-missing", "haruka-test-process")
        try:
            with self.assertRaises(processes.ProcessError):
                owner.start("missing", [str(Path.cwd() / "does-not-exist.exe")], cwd=Path.cwd())
            self.assertEqual(owner.children, [])
        finally:
            owner.stop(grace_seconds=0.1)


class DevelopmentDiagnostics(unittest.TestCase):
    def test_platform_probe_allows_closed_connection_rebind(self) -> None:
        if os.name == "nt":
            # Windows keeps its existing exclusive-address policy; the actual
            # TIME_WAIT rebind acceptance below belongs to the POSIX platform.
            with patch("scripts.development.socket.socket") as factory:
                candidate = factory.return_value.__enter__.return_value
                development.require_free_port(18080)
            candidate.setsockopt.assert_called_once_with(
                socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1
            )
            candidate.bind.assert_called_once_with(("127.0.0.1", 18080))
            candidate.listen.assert_not_called()
            return
        with socket.socket() as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            port = listener.getsockname()[1]
            with socket.create_connection(("127.0.0.1", port), timeout=2) as client:
                peer, _ = listener.accept()
                with peer:
                    peer.sendall(b"proof")
                self.assertEqual(client.recv(5), b"proof")
                self.assertEqual(client.recv(1), b"")
        # Observe TIME_WAIT itself, so a race or an unused socket cannot satisfy
        # the rebind regression without reproducing the relevant kernel state.
        address = f"0100007F:{port:04X}"

        def in_time_wait() -> bool:
            lines = Path("/proc/net/tcp").read_text(encoding="ascii").splitlines()[1:]
            return any(
                row[1] == address and row[3] == "06" for row in (line.split() for line in lines)
            )

        wait_until(in_time_wait)
        development.require_free_port(port)
        with socket.socket() as restarted:
            restarted.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            restarted.bind(("127.0.0.1", port))
            restarted.listen(1)

    def test_live_reusable_listener_is_rejected_and_remains_reachable(self) -> None:
        with socket.socket() as holder:
            holder.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            holder.bind(("127.0.0.1", 0))
            holder.listen(1)
            port = holder.getsockname()[1]
            with self.assertRaisesRegex(development.DevelopmentError, "occupied or unavailable"):
                development.require_free_port(port)
            with socket.create_connection(("127.0.0.1", port), timeout=2):
                peer, _ = holder.accept()
                peer.close()

    def test_unlistened_exclusive_bind_is_rejected(self) -> None:
        with socket.socket() as holder:
            if os.name == "nt":
                holder.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            holder.bind(("127.0.0.1", 0))
            port = holder.getsockname()[1]
            with self.assertRaisesRegex(development.DevelopmentError, "occupied or unavailable"):
                development.require_free_port(port)
            self.assertEqual(holder.getsockname()[1], port)

    def test_doctor_missing_environment_refuses_without_installing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            root = Path(temporary)
            config = self.doctor_fixture(root)
            before = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
            with (
                patch("scripts.dev.ROOT", root),
                patch("scripts.dev.subprocess.run") as command,
                self.assertRaisesRegex(dev.DevError, "bootstrap --scope backend"),
            ):
                dev.runtime_doctor(
                    dev.Report("doctor", "backend"),
                    config,
                    profile="core",
                    target=None,
                    device=None,
                )
            command.assert_not_called()
            self.assertEqual(
                before, sorted(str(path.relative_to(root)) for path in root.rglob("*"))
            )
            self.assertFalse((root / "backend/.venv").exists())

    def test_doctor_uses_only_installed_entry_without_a_dependency_resolver(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            root = Path(temporary)
            config = self.doctor_fixture(root)
            entry = (
                root
                / "backend/.venv"
                / ("Scripts/haruka-manage.exe" if os.name == "nt" else "bin/haruka-manage")
            )
            entry.parent.mkdir(parents=True)
            entry.write_bytes(b"fixture")
            with (
                patch("scripts.dev.ROOT", root),
                patch(
                    "scripts.dev.subprocess.run",
                    return_value=subprocess.CompletedProcess([], 0, stdout="", stderr=""),
                ) as command,
            ):
                dev.runtime_doctor(
                    dev.Report("doctor", "backend"),
                    config,
                    profile="core",
                    target=None,
                    device=None,
                )
            self.assertEqual(command.call_count, 2)
            self.assertEqual(
                [call.args[0] for call in command.call_args_list],
                [
                    [str(entry), "--config", str(config), "--check-config"],
                    [str(entry), "--config", str(config), "check-infrastructure"],
                ],
            )

    @staticmethod
    def doctor_fixture(root: Path) -> Path:
        config = write_config(root)
        registry = root / "frontend/config/build_targets.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(
            json.dumps(
                {"environments": {"dev": {"allowed_api_base_urls": ["http://127.0.0.1:8000"]}}}
            ),
            encoding="utf-8",
        )
        (root / "backend").mkdir()
        return config

    def test_occupied_port_is_reported_without_disturbing_its_holder(self) -> None:
        with socket.socket() as holder:
            holder.bind(("127.0.0.1", 0))
            holder.listen()
            port = holder.getsockname()[1]
            with self.assertRaises(development.DevelopmentError):
                development.require_free_port(port)
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                pass

    def test_public_config_accepts_declared_scope_and_refuses_environment_override(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            path = write_config(Path(temporary))
            config = development.read_public_config(path)
            self.assertEqual(config.namespace, "haruka-local-dev")
            with patch.dict(os.environ, {"HARUKA_S3_SECRET_KEY": "fake-sentinel"}):
                with self.assertRaises(development.DevelopmentError) as raised:
                    development.read_public_config(path)
                self.assertNotIn("fake-sentinel", str(raised.exception))

    def test_public_config_rejects_production_and_wrong_namespace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            path = write_config(Path(temporary))
            original = path.read_text(encoding="utf-8")
            for invalid in (
                original.replace("APP_ENV=dev", "APP_ENV=production"),
                original.replace(
                    "RESOURCE_NAMESPACE=haruka-local-dev", "RESOURCE_NAMESPACE=other-project"
                ),
            ):
                path.write_text(invalid, encoding="utf-8")
                with self.assertRaises(development.DevelopmentError):
                    development.read_public_config(path)


if __name__ == "__main__":
    unittest.main()
