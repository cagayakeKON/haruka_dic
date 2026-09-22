"""Failure-focused checks for the local runner and documentation verifier."""

from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Sequence
from pathlib import Path
from unittest.mock import patch

from scripts import dev
from scripts.quality.docs import anchors, inspect, visible_lines


class DocumentationChecks(unittest.TestCase):
    def test_fence_example_can_contain_shorter_nested_fence(self) -> None:
        text = "# Title\n\n~~~~text\n~~~python\n[bad](missing.md)\n~~~\n~~~~\n"
        lines, unclosed = visible_lines(text)
        self.assertIsNone(unclosed)
        self.assertNotIn("[bad](missing.md)", [line for _, line in lines])

    def test_links_anchors_case_and_unclosed_fences_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Target.md").write_text("# 中文 标题\n", encoding="utf-8")
            source = root / "README.md"
            source.write_text(
                "# Test\n\n[ok](Target.md#中文-标题)\n[case](target.md)\n"
                "[anchor](Target.md#absent)\n[missing](absent.md)\n\n~~~python\nx = 1\n",
                encoding="utf-8",
            )
            findings, unverified = inspect(root, [source])
            self.assertEqual(
                sorted(item.code for item in findings),
                [
                    "missing_anchor",
                    "missing_or_wrong_case_target",
                    "missing_or_wrong_case_target",
                    "unclosed_fence",
                ],
            )
            self.assertEqual(unverified, [])

    def test_duplicate_heading_anchors_have_suffix(self) -> None:
        self.assertEqual(anchors("# Same\n## Same\n## **Same**\n"), {"same", "same-1", "same-2"})

    def test_adjacent_repository_is_recorded_unverified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            source = root / "README.md"
            source.write_text("# Test\n\n[reference](../absent/file.py)\n", encoding="utf-8")
            findings, unverified = inspect(root, [source])
            self.assertEqual(findings, [])
            self.assertEqual(len(unverified), 1)


class ResultGates(unittest.TestCase):
    def test_console_reconfigures_cp932_stdout_and_stderr_before_chinese_output(self) -> None:
        stdout_bytes = io.BytesIO()
        stderr_bytes = io.BytesIO()
        stdout = io.TextIOWrapper(stdout_bytes, encoding="cp932")
        stderr = io.TextIOWrapper(stderr_bytes, encoding="cp932")
        with patch("scripts.dev.sys.stdout", stdout), patch("scripts.dev.sys.stderr", stderr):
            dev.configure_console()
            dev.emit("目录检查失败")
            sys.stderr.write("错误输出\n")
            stdout.flush()
            stderr.flush()
            self.assertEqual(stdout_bytes.getvalue().decode("utf-8"), "目录检查失败\n")
            self.assertEqual(stderr_bytes.getvalue().decode("utf-8"), "错误输出\n")

    def test_codegen_check_does_not_write_and_unknown_files_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tools/codegen").mkdir(parents=True)
            (root / "frontend/tool").mkdir(parents=True)
            (root / "contracts").mkdir()
            (root / "tools/codegen/manifest.json").write_text(
                json.dumps({"backend_outputs": ["openapi.json"]}), encoding="utf-8"
            )
            (root / "frontend/tool/generate.py").write_text("", encoding="utf-8")
            target = root / "contracts/openapi.json"
            target.write_text('{"version":1}\n', encoding="utf-8")

            def export(
                _report: dev.Report, name: str, arguments: Sequence[str], **_kwargs: object
            ) -> str:
                if "tools.check_registries" in arguments:
                    return ""
                if name == "uv":
                    outputs = (
                        ("manifest.json", "openapi.json", "samples.json")
                        if "tools.export_compatibility" in arguments
                        else ("openapi.json",)
                    )
                    for output in outputs:
                        (Path(arguments[-1]) / output).write_text(
                            '{"version":2}\n', encoding="utf-8"
                        )
                return ""

            with (
                patch("scripts.dev.ROOT", root),
                patch("scripts.dev.doctor"),
                patch("scripts.dev.run", side_effect=export),
            ):
                with self.assertRaisesRegex(dev.DevError, "drift"):
                    dev.codegen(dev.Report("codegen", "check"), write=False)
                self.assertEqual(target.read_text(encoding="utf-8"), '{"version":1}\n')
                dev.codegen(dev.Report("codegen", "write"), write=True)
                self.assertEqual(target.read_text(encoding="utf-8"), '{"version":2}\n')
                fixtures = root / "tools/codegen/dart-api/fixtures"
                self.assertEqual(
                    {path.name for path in fixtures.iterdir()},
                    {"manifest.json", "openapi.json", "samples.json"},
                )
                dev.codegen(dev.Report("codegen", "check"), write=False)
                (fixtures / "samples.json").unlink()
                with self.assertRaisesRegex(dev.DevError, "compatibility fixture drift"):
                    dev.codegen(dev.Report("codegen", "check"), write=False)
                self.assertFalse((fixtures / "samples.json").exists())
                dev.codegen(dev.Report("codegen", "write"), write=True)
                (root / "contracts/unmanaged.txt").write_text("keep", encoding="utf-8")
                with self.assertRaisesRegex(dev.DevError, "Unknown"):
                    dev.codegen(dev.Report("codegen", "write"), write=True)
                self.assertEqual(
                    (root / "contracts/unmanaged.txt").read_text(encoding="utf-8"), "keep"
                )

    def test_junit_rejects_empty_skipped_failure_and_invalid_reports(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary) / "result.xml"
            for content in (
                "<testsuites/>",
                '<testsuite><testcase name="x"><skipped/></testcase></testsuite>',
                '<testsuite><testcase name="x"><failure/></testcase></testsuite>',
                '<testsuite><testcase name="x"><error/></testcase></testsuite>',
                "invalid",
            ):
                with self.subTest(content=content):
                    report.write_text(content, encoding="utf-8")
                    with self.assertRaises(dev.DevError):
                        dev.junit_results(report)
            report.write_text('<testsuite><testcase name="x"/></testsuite>', encoding="utf-8")
            self.assertEqual(dev.junit_results(report), 1)

    def test_flutter_rejects_empty_incomplete_skipped_or_failed_results(self) -> None:
        success = {"type": "testDone", "result": "success", "skipped": False, "hidden": False}
        end = {"type": "done", "success": True}
        for events in (
            [],
            [success],
            [end],
            [dict(success, skipped=True), end],
            [dict(success, result="failure"), end],
        ):
            with self.subTest(events=events), self.assertRaises(dev.DevError):
                dev.flutter_results("\n".join(json.dumps(event) for event in events))
        self.assertEqual(
            dev.flutter_results("\n".join(json.dumps(event) for event in [success, end])), 1
        )

    def test_unittest_rejects_zero_or_skipped_tests(self) -> None:
        for output in ("Ran 0 tests in 0.0s\nOK", "Ran 1 test in 0.0s\nOK (skipped=1)", ""):
            with self.subTest(output=output), self.assertRaises(dev.DevError):
                dev.unittest_results(output)
        self.assertEqual(dev.unittest_results("Ran 2 tests in 0.1s\nOK"), 2)

    def test_bootstrap_never_overwrites_existing_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "backend").mkdir()
            target = root / "backend/.env"
            target.write_text("LOCAL_VALUE=preserve\n", encoding="utf-8")
            (root / "backend/.env.example").write_text("LOCAL_VALUE=template\n", encoding="utf-8")
            with (
                patch("scripts.dev.ROOT", root),
                patch("scripts.dev.doctor"),
                patch("scripts.dev.run"),
            ):
                dev.bootstrap(dev.Report("bootstrap", "backend"), "backend")
            self.assertEqual(target.read_text(encoding="utf-8"), "LOCAL_VALUE=preserve\n")

    def test_unimplemented_milestones_never_pass(self) -> None:
        for stage in ("B0", "B1", "B2"):
            with self.subTest(stage=stage), self.assertRaises(dev.DevError):
                dev.check(dev.Report("check", stage), stage)

    def test_b0_requires_explicit_identity_and_reports_and_other_scopes_refuse_them(self) -> None:
        for identity, reports in (
            (None, ()),
            (Path("identity.json"), ()),
            (None, (Path("report.json"),)),
        ):
            with self.subTest(identity=identity, reports=reports), patch("scripts.dev.run") as run:
                with self.assertRaisesRegex(dev.DevError, "explicit --identity"):
                    dev.check(
                        dev.Report("check", "B0"), "B0", identity=identity, evidence_reports=reports
                    )
                run.assert_not_called()
        for stage in (
            "docs",
            "tooling",
            "backend",
            "frontend",
            "infrastructure",
            "B0-foundation",
            "B1",
            "B2",
        ):
            with self.subTest(stage=stage), patch("scripts.dev.run") as run:
                with self.assertRaises(dev.DevError):
                    dev.check(
                        dev.Report("check", stage),
                        stage,
                        identity=Path("identity.json"),
                        evidence_reports=[Path("report.json")],
                    )
                run.assert_not_called()

    def test_b0_cli_forwards_only_explicit_reports_and_records_candidate_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            identity = root / "identity.json"
            identity.write_text('{"commit":"explicit-candidate"}', encoding="utf-8")
            reports = [root / "one.json", root / "two.json"]
            for path in (*reports, root / "not-selected.json"):
                path.write_text("{}", encoding="utf-8")
            calls: list[list[str]] = []

            def gate(
                _report: dev.Report, name: str, arguments: Sequence[str], **_kwargs: object
            ) -> str:
                self.assertEqual(name, "python")
                calls.append(list(arguments))
                target = Path(arguments[arguments.index("--output") + 1])
                target.write_text(
                    json.dumps(
                        {
                            "passed": True,
                            "scope": "B0",
                            "phase": "result",
                            "identity": {"commit": "explicit-candidate"},
                        }
                    ),
                    encoding="utf-8",
                )
                return ""

            with patch("scripts.dev.ROOT", root), patch("scripts.dev.run", side_effect=gate):
                code = dev.main(
                    [
                        "check",
                        "--stage",
                        "B0",
                        "--identity",
                        str(identity),
                        "--report",
                        str(reports[0]),
                        "--report",
                        str(reports[1]),
                    ]
                )
            self.assertEqual(code, 0)
            self.assertEqual(len(calls), 1)
            command = calls[0]
            self.assertEqual(command[:2], ["-m", "scripts.quality.cases"])
            self.assertEqual(command[command.index("--scope") + 1], "B0")
            self.assertEqual(command[command.index("--identity") + 1], str(identity.resolve()))
            self.assertEqual(
                [command[index + 1] for index, value in enumerate(command) if value == "--report"],
                [str(path.resolve()) for path in reports],
            )
            outputs = list((root / "artifacts/dev").glob("check-*-matrix.json"))
            self.assertEqual(len(outputs), 1)
            report = json.loads(
                outputs[0].with_name(outputs[0].name.replace("-matrix", "")).read_text()
            )
            record = report["records"][-1]
            self.assertEqual(record["candidate_identity"], {"commit": "explicit-candidate"})
            self.assertEqual(record["acceptance_target"], "explicit_candidate_identity")
            self.assertFalse(record["current_head_automatically_accepted"])
            self.assertFalse(record["ci_executed"])
            self.assertFalse(record["tests_reexecuted"])
            self.assertEqual(identity.read_text(), '{"commit":"explicit-candidate"}')
            self.assertTrue(all(path.read_text() == "{}" for path in reports))

    def test_b0_downstream_failure_and_missing_output_remain_failed(self) -> None:
        for gate_exit in (0, 1):
            with self.subTest(gate_exit=gate_exit), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                identity, evidence = root / "identity.json", root / "evidence.json"
                identity.write_text("{}", encoding="utf-8")
                evidence.write_text("{}", encoding="utf-8")
                with (
                    patch("scripts.dev.ROOT", root),
                    patch(
                        "scripts.dev.subprocess.run",
                        return_value=subprocess.CompletedProcess([], gate_exit, "", ""),
                    ),
                ):
                    code = dev.main(
                        [
                            "check",
                            "--stage",
                            "B0",
                            "--identity",
                            str(identity),
                            "--report",
                            str(evidence),
                        ]
                    )
                self.assertEqual(code, 1)
                report = json.loads(next((root / "artifacts/dev").glob("check-*.json")).read_text())
                self.assertEqual(report["result"], "failed")
                self.assertFalse(
                    any(record["name"] == "acceptance_scope" for record in report["records"])
                )

    def test_missing_executable_and_failed_subprocess_do_not_succeed(self) -> None:
        with patch("scripts.dev.shutil.which", return_value=None), self.assertRaises(dev.DevError):
            dev.tool("nonexistent")
        with self.assertRaises(dev.DevError):
            dev.run(
                dev.Report("test", "tooling"),
                "python",
                ["-c", "raise SystemExit(7)"],
                show_output=False,
            )

    def test_report_redacts_credentials_and_machine_paths(self) -> None:
        output = dev.redact(
            "postgresql://sample:fake-password@localhost/db token=fake-token api_key=fake-value "
            + str(dev.ROOT)
        )
        self.assertNotIn("fake-password", output)
        self.assertNotIn("fake-token", output)
        self.assertNotIn("fake-value", output)
        self.assertNotIn(str(dev.ROOT), output)
        data = {"cwd": str(dev.ROOT), "arguments": ["token=fake-token", str(Path.home())]}
        serialized = json.dumps(dev.redact_data(data))
        self.assertNotIn("fake-token", serialized)
        self.assertNotIn(json.dumps(str(dev.ROOT)), serialized)
        self.assertNotIn(json.dumps(str(Path.home())), serialized)

    def test_saved_report_is_valid_json_after_nested_secret_and_path_redaction(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = dev.Report("test", "tooling")
            report.record(
                "example",
                "failed",
                reason="token=fake-token",
                cwd=str(root),
                nested={"arguments": ["api_key=fake-value", str(Path.home())]},
            )
            with patch("scripts.dev.ROOT", root):
                path = report.save()
            serialized = path.read_text(encoding="utf-8")
            document = dev.json_object(json.loads(serialized))
            self.assertEqual(document["command"], "test")
            self.assertNotIn("fake-token", serialized)
            self.assertNotIn("fake-value", serialized)
            self.assertNotIn(json.dumps(str(root)), serialized)
            self.assertIn("<repository>", serialized)


class InfrastructureChecks(unittest.TestCase):
    def test_initialization_does_not_require_a_running_docker_daemon(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "dev").mkdir()
            (root / "dev/infra.py").write_text("", encoding="utf-8")
            (root / "dev/compose.yaml").write_text("", encoding="utf-8")
            with (
                patch("scripts.dev.ROOT", root),
                patch(
                    "scripts.dev.load_toolchain", return_value={"python": sys.version.split()[0]}
                ),
                patch("scripts.dev.doctor") as doctor,
                patch("scripts.dev.run") as run,
            ):
                dev.infra(dev.Report("infra", "init"), "init")
                doctor.assert_not_called()
                self.assertEqual(
                    run.call_args.args[1:3], ("python", [str(root / "dev/infra.py"), "init"])
                )

    def test_missing_infrastructure_script_and_unknown_action_cannot_launch(self) -> None:
        with (
            tempfile.TemporaryDirectory() as temporary,
            patch("scripts.dev.ROOT", Path(temporary)),
            patch("scripts.dev.run") as run,
        ):
            for action in ("up", "down", "delete-all-volumes"):
                with self.subTest(action=action), self.assertRaises(dev.DevError):
                    dev.infra(dev.Report("infra", action), action)
            run.assert_not_called()

    def test_doctor_rejects_missing_daemon_or_docker_version_drift(self) -> None:
        manifest = {
            "schema_version": 1,
            "python": "3.13.6",
            "docker": "29.5.2",
            "docker_compose": "5.1.4",
        }
        for daemon_result in ("29.5.1", dev.DevError("Docker daemon is unavailable")):
            with (
                self.subTest(daemon_result=type(daemon_result).__name__),
                patch("scripts.dev.load_toolchain", return_value=manifest),
                patch("scripts.dev.require_files"),
                patch("scripts.dev.run", side_effect=["3.13.6", "29.5.2", daemon_result, "5.1.4"]),
                patch("scripts.dev.emit"),
                self.assertRaises(dev.DevError),
            ):
                dev.doctor(dev.Report("doctor", "infra"), "infra")

    def test_missing_test_target_never_falls_back_to_another_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with (
                patch("scripts.dev.ROOT", Path(temporary)),
                patch("scripts.dev.run") as run,
                self.assertRaisesRegex(dev.DevError, "dev/.local/test.env"),
            ):
                dev.check_infrastructure(dev.Report("check", "infrastructure"))
            run.assert_not_called()

    def test_empty_or_skipped_infrastructure_unit_results_block_live_checks(self) -> None:
        for output in ("Ran 0 tests in 0.0s\nOK", "Ran 1 test in 0.0s\nOK (skipped=1)"):
            with (
                self.subTest(output=output),
                patch("scripts.dev.require_files"),
                patch("scripts.dev.doctor"),
                patch("scripts.dev.run", return_value=output),
                patch("scripts.dev.infra") as infra,
                self.assertRaises(dev.DevError),
            ):
                dev.check_infrastructure(dev.Report("check", "infrastructure"))
            infra.assert_not_called()

    def test_child_environment_is_private_and_is_not_written_to_the_report(self) -> None:
        report = dev.Report("test", "tooling")
        with patch.dict(os.environ, {"HARUKA_TEST_ENV_SENTINEL": "original"}):
            output = dev.run(
                report,
                "python",
                ["-c", "import os; print(os.environ['HARUKA_TEST_ENV_SENTINEL'])"],
                show_output=False,
                environment={"HARUKA_TEST_ENV_SENTINEL": "fake-environment-secret"},
            )
            self.assertEqual(output.strip(), "fake-environment-secret")
            self.assertEqual(os.environ["HARUKA_TEST_ENV_SENTINEL"], "original")
        self.assertNotIn("fake-environment-secret", json.dumps(report.records))


if __name__ == "__main__":
    unittest.main()
