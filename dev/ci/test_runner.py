"""Failure cases for the Linux evidence boundary; no infrastructure or subprocess required."""

import json
import signal
import sys
import tempfile
import unittest
from pathlib import Path

from linux_runner import (
    FAILURE_REASONS,
    junit,
    private_config,
    require_failure_evidence,
    require_graceful_signal_exit,
    validate_lock,
)
from proxy import Bridge
from run import mount, validate_docker_context


class RunnerChecks(unittest.TestCase):
    def test_runtime_lock_drift_requires_actual_locked_diagnostic(self) -> None:
        report: dict[str, object] = {
            "result": "failed",
            "records": [
                {
                    "name": "uv",
                    "status": "failed",
                    "exit_code": 1,
                    "arguments": ["sync", "--locked", "--group", "dev"],
                },
                {"name": "result", "status": "failed", "reason": "uv failed with exit code 1"},
            ],
        }
        require_failure_evidence(
            "runtime-lock-drift",
            report,
            "The lockfile at `uv.lock` needs to be updated, but `--locked` was provided.",
        )
        with self.assertRaises(RuntimeError):
            require_failure_evidence(
                "runtime-lock-drift", report, "No solution found: unavailable offline cache"
            )

    def test_same_exit_with_wrong_or_missing_diagnostic_never_passes(self) -> None:
        name = "missing-required-script"
        report: dict[str, object] = {
            "result": "failed",
            "records": [{"name": "result", "status": "failed", "reason": FAILURE_REASONS[name]}],
        }
        require_failure_evidence(name, report, "")
        for records in (
            [],
            [{"name": "result", "status": "failed", "reason": "python could not finish (OSError)"}],
            [
                {"name": "result", "status": "failed", "reason": FAILURE_REASONS[name]},
                {"name": "result", "status": "failed", "reason": "another failure"},
            ],
        ):
            with self.subTest(records=records), self.assertRaises(RuntimeError):
                require_failure_evidence(name, {"result": "failed", "records": records}, "")
        for sample in ("runtime-lock-drift", "unreachable-service-doctor"):
            with self.subTest(sample=sample), self.assertRaises(RuntimeError):
                require_failure_evidence(
                    sample,
                    {
                        "result": "failed",
                        "records": [
                            {
                                "name": "result",
                                "status": "failed",
                                "reason": FAILURE_REASONS[sample],
                            }
                        ],
                    },
                    "--locked needs to be updated",
                )

    def test_signal_exit_requires_both_expected_status_and_closed_lifecycle(self) -> None:
        stopped = '{"event": "process.stopped"}'
        require_graceful_signal_exit("api", -signal.SIGTERM, stopped)
        require_graceful_signal_exit("worker", 0, stopped)
        for role, code, output in (
            ("api", -signal.SIGTERM, ""),
            ("api", 0, stopped),
            ("worker", -signal.SIGTERM, stopped),
            ("outbox", 0, ""),
        ):
            with self.subTest(role=role, code=code, output=output), self.assertRaises(RuntimeError):
                require_graceful_signal_exit(role, code, output)

    def test_docker_context_requires_exact_local_linux_engine(self) -> None:
        validate_docker_context("desktop-linux", "npipe:////./pipe/dockerDesktopLinuxEngine")
        for name, endpoint in (
            ("default", "npipe:////./pipe/dockerDesktopLinuxEngine"),
            ("desktop-linux", "tcp://remote:2375"),
            ("desktop-linux", "npipe:////./pipe/docker_engine"),
        ):
            with self.subTest(name=name, endpoint=endpoint), self.assertRaises(ValueError):
                validate_docker_context(name, endpoint)

    def test_private_config_preserves_credentials_and_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source, target = directory / "source.env", directory / "private.env"
            source.write_text(
                "HARUKA_APP_ENV=test\nHARUKA_PASSWORD=fake-sentinel\nHARUKA_LOG_FILE=old\n"
            )
            original = source.read_bytes()
            private_config(source, target, directory / "log.jsonl")
            self.assertEqual(source.read_bytes(), original)
            self.assertIn("HARUKA_PASSWORD=fake-sentinel", target.read_text())
            self.assertIn("HARUKA_APP_ENV=test", target.read_text())
            self.assertNotIn("HARUKA_LOG_FILE=old", target.read_text())
            with self.assertRaises(ValueError):
                private_config(source, target, directory / "other.jsonl")

    def test_duplicate_config_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "source.env"
            source.write_text("HARUKA_APP_ENV=test\nHARUKA_APP_ENV=dev\n")
            with self.assertRaises(ValueError):
                private_config(source, directory / "target.env", directory / "log.jsonl")

    def test_junit_requires_exact_nodes_and_passed_outcomes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.xml"
            case = '<testcase classname="tests.unit.test_a" name="test_one">{}</testcase>'
            for content in (
                "",
                case.format("<skipped/>"),
                case.format("<failure/>"),
                case.format("<error/>"),
                case.format("") * 2,
            ):
                with self.subTest(content=content):
                    path.write_text("<testsuite>" + content + "</testsuite>")
                    with self.assertRaises(ValueError):
                        junit(path, ["tests/unit/test_a.py::test_one"])
            path.write_text("<testsuite>" + case.format("") + "</testsuite>")
            self.assertEqual(junit(path, ["tests/unit/test_a.py::test_one"]), 1)

    def test_image_lock_and_project_versions_must_agree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "dev/ci").mkdir(parents=True)
            (root / "tools").mkdir()
            lock = {
                "base_image": "base",
                "debian_snapshot": "time",
                "platform": "linux/amd64",
                "artifacts": [
                    {"name": "uv", "version": "1"},
                    {"name": "flutter", "version": "2", "revision": "revision"},
                ],
            }
            main = {
                "python": sys.version.split()[0],
                "uv": "1",
                "flutter": {"version": "2", "revision": "revision"},
                "linux_validation": {
                    key: lock[key] for key in ("base_image", "debian_snapshot", "platform")
                },
            }
            source, image = root / "dev/ci/toolchain.lock.json", root / "image.json"
            source.write_text(json.dumps(lock))
            image.write_text(json.dumps(lock))
            (root / "tools/toolchain.json").write_text(json.dumps(main))
            validate_lock(root, image)
            main["uv"] = "other"
            (root / "tools/toolchain.json").write_text(json.dumps(main))
            with self.assertRaises(ValueError):
                validate_lock(root, image)
            image.write_text("{}")
            with self.assertRaises(ValueError):
                validate_lock(root, image)

    def test_proxy_refuses_unregistered_ports_before_binding(self) -> None:
        for port in (5432, 6379, 9000, 13000):
            with self.subTest(port=port), self.assertRaises(ValueError):
                Bridge(port)

    def test_mount_rejects_separator_injection(self) -> None:
        with self.assertRaises(ValueError):
            mount(Path("example,readonly=false"), "/input/test.env")
        self.assertTrue(mount(Path("explicit.env"), "/input/test.env")[1].endswith(",readonly"))


if __name__ == "__main__":
    unittest.main()
