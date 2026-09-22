"""Adversarial acceptance-matrix samples; process success is never evidence."""

from __future__ import annotations

import copy
import importlib
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from scripts.quality.cases import Case, check, load_manifest
from scripts.quality.common import GateError, array, digest, obj, read_json, write_json
from scripts.quality.unittest_runner import RecordedResult, execute

IDENTITY: dict[str, object] = {
    "commit": "a" * 40,
    "build_id": "b0-local",
    "configuration": "test",
    "toolchain_sha256": "b" * 64,
    "run_id": "run-a",
}


def sample_case() -> Case:
    return Case(
        "SCF-B0-07",
        ("SCF-B0-07",),
        "unit",
        "unittest",
        "host",
        "harness",
        "local",
        "{}",
        "quality",
        ("test_guard",),
        "test.py",
    )


def sample_reports() -> list[dict[str, object]]:
    return [
        {
            "schema_version": 1,
            "identity": IDENTITY.copy(),
            "phase": phase,
            "shard": "quality",
            "runner": "unittest",
            "platform": "host",
            "attempt": 1,
            "session_status": "passed",
            "nodes": [
                {
                    "node_id": "test_guard",
                    "case_ids": ["SCF-B0-07"],
                    "layers": ["unit"],
                    "selected": True,
                    "status": status,
                }
            ],
        }
        for phase, status in (("collection", "collected"), ("result", "passed"))
    ]


def first_node(report: dict[str, object]) -> dict[str, object]:
    return obj(array(report["nodes"])[0])


class RequiredCaseChecks(unittest.TestCase):
    def evaluate(
        self, reports: list[dict[str, object]], cases: list[Case] | None = None
    ) -> dict[str, object]:
        return check(cases or [sample_case()], {"B0": ["SCF-B0-07"]}, "B0", reports, IDENTITY)

    def test_real_collection_and_result_are_both_required(self) -> None:
        self.assertTrue(self.evaluate(sample_reports())["passed"])
        self.assertFalse(self.evaluate(sample_reports()[1:])["passed"])
        self.assertFalse(self.evaluate([])["passed"])

    def test_every_nonpassing_status_blocks(self) -> None:
        for status in ("failed", "error", "skipped", "xfail", "xpass", "deselected", "interrupted"):
            with self.subTest(status=status):
                reports = sample_reports()
                first_node(reports[1])["status"] = status
                self.assertFalse(self.evaluate(reports)["passed"])

    def test_unknown_case_and_wrong_driver_are_rejected(self) -> None:
        for change in ("case", "runner", "platform"):
            with self.subTest(change=change):
                reports = sample_reports()
                if change == "case":
                    first_node(reports[0])["case_ids"] = ["UNKNOWN"]
                else:
                    reports[1][change] = "playwright" if change == "runner" else "android"
                with self.assertRaises(GateError):
                    self.evaluate(reports)

    def test_missing_or_multiple_primary_layers_are_rejected(self) -> None:
        for layers in ([], ["unit", "integration"], ["unknown"]):
            with self.subTest(layers=layers):
                reports = sample_reports()
                first_node(reports[0])["layers"] = layers
                with self.assertRaises(GateError):
                    self.evaluate(reports)

    def test_missing_case_mapping_and_excluded_slow_case_block(self) -> None:
        reports = sample_reports()
        first_node(reports[0])["case_ids"] = []
        self.assertFalse(self.evaluate(reports)["passed"])
        reports = sample_reports()
        first_node(reports[0]).update(selected=False, status="deselected")
        self.assertFalse(self.evaluate(reports)["passed"])

    def test_partial_parameters_or_missing_shard_cannot_shrink_matrix(self) -> None:
        case = sample_case()
        second = replace(case, parameters='{"mode":"failure"}', nodes=("test_failure",))
        self.assertNotEqual(case.key, second.key)
        self.assertFalse(self.evaluate(sample_reports(), [case, second])["passed"])
        second = replace(case, platform="android", runner="integration_test", shard="android")
        self.assertFalse(self.evaluate(sample_reports(), [case, second])["passed"])

    def test_empty_duplicate_and_wrong_commit_reports_are_rejected(self) -> None:
        for change in ("empty", "duplicate", "commit"):
            with self.subTest(change=change):
                reports = sample_reports()
                if change == "empty":
                    reports[1]["nodes"] = []
                elif change == "duplicate":
                    reports.append(copy.deepcopy(reports[1]))
                else:
                    obj(reports[1]["identity"])["commit"] = "c" * 40
                with self.assertRaises(GateError):
                    self.evaluate(reports)

    def test_retry_success_preserves_original_failure(self) -> None:
        reports = sample_reports()
        retry = copy.deepcopy(reports[1])
        retry["attempt"] = 2
        first_node(reports[1])["status"] = "failed"
        reports.append(retry)
        self.assertFalse(self.evaluate(reports)["passed"])

    def test_orphan_retry_and_extra_unmapped_failure_cannot_pass(self) -> None:
        reports = sample_reports()
        reports[0]["attempt"] = 2
        reports[1]["attempt"] = 2
        self.assertFalse(self.evaluate(reports)["passed"])
        reports = sample_reports()
        array(reports[1]["nodes"]).append(
            {
                "node_id": "extra",
                "case_ids": [],
                "layers": ["unit"],
                "selected": True,
                "status": "failed",
            }
        )
        self.assertFalse(self.evaluate(reports)["passed"])

    def test_attempts_cannot_supply_each_others_missing_nodes(self) -> None:
        case = replace(sample_case(), nodes=("test_guard", "test_second"))
        reports = sample_reports()
        second = copy.deepcopy(reports)
        for report in second:
            report["attempt"] = 2
            first_node(report)["node_id"] = "test_second"
        self.assertFalse(self.evaluate([*reports, *second], [case])["passed"])

    def test_unittest_class_cleanup_error_is_preserved_in_failed_json(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module_name = "quality_suite_teardown_probe"
            (root / f"{module_name}.py").write_text(
                "import unittest\nclass Probe(unittest.TestCase):\n"
                "    def test_ok(self):\n        self.assertTrue(True)\n"
                "    @classmethod\n    def tearDownClass(cls):\n"
                "        raise RuntimeError('synthetic cleanup failure')\n",
                encoding="utf-8",
            )
            sys.path.insert(0, str(root))
            importlib.invalidate_caches()
            try:
                case = replace(sample_case(), nodes=(f"{module_name}.Probe.test_ok",))
                self.assertFalse(execute([case], "probe", IDENTITY, root / "reports"))
                result = read_json(root / "reports/quality-result.json")
                self.assertEqual(result["session_status"], "failed")
                self.assertTrue(
                    any(
                        "tearDownClass" in str(obj(node)["node_id"])
                        for node in array(result["nodes"])
                    )
                )
                self.assertFalse(read_json(root / "reports/summary.json")["passed"])
            finally:
                sys.path.remove(str(root))
                sys.modules.pop(module_name, None)
                importlib.invalidate_caches()

    def test_unittest_collector_records_real_skip_failure_and_xfail(self) -> None:
        class SyntheticCases(unittest.TestCase):
            def test_pass(self) -> None:
                self.assertTrue(True)

            def test_failure(self) -> None:
                self.fail("synthetic negative")

            @unittest.skip("synthetic negative")
            def test_skip(self) -> None:
                self.fail("must not execute")

            @unittest.expectedFailure
            def test_expected_failure(self) -> None:
                self.fail("synthetic negative")

            def test_subtest(self) -> None:
                with self.subTest(variant="bad"):
                    self.fail("synthetic negative")

        cases = [
            SyntheticCases(name)
            for name in (
                "test_pass",
                "test_failure",
                "test_skip",
                "test_expected_failure",
                "test_subtest",
            )
        ]
        result = RecordedResult()
        unittest.TestSuite(cases).run(result)
        self.assertEqual(
            [result.statuses[case.id()] for case in cases],
            ["passed", "failed", "skipped", "xfail", "failed"],
        )

    def test_procedure_requires_each_hashed_assertion_and_independent_review(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "probe.json"
            write_json(artifact, {"synthetic_probe": "completed"})
            case = replace(
                sample_case(), layer="platform", runner="procedure", assertions=("launch", "close")
            )
            reports = sample_reports()
            for report in reports:
                report["runner"] = "procedure"
                first_node(report)["layers"] = ["platform"]
            receipt: dict[str, object] = {
                "author": "author-agent",
                "reviewer": "review-agent",
                "reviewed_at": "2026-09-22T00:00:00Z",
                "assertions": {
                    name: {
                        "passed": True,
                        "evidence_path": "probe.json",
                        "sha256": digest(artifact),
                    }
                    for name in case.assertions
                },
            }
            first_node(reports[1])["procedure"] = receipt
            result = check(
                [case], {"B0": [case.case_id]}, "B0", reports, IDENTITY, evidence_root=root
            )
            self.assertTrue(result["passed"])
            for variant in (
                "missing",
                "self-review",
                "unchecked",
                "digest",
                "failed",
                "naive-time",
            ):
                with self.subTest(variant=variant):
                    invalid = copy.deepcopy(reports)
                    candidate = obj(first_node(invalid[1])["procedure"])
                    if variant == "missing":
                        del first_node(invalid[1])["procedure"]
                    elif variant == "self-review":
                        candidate["reviewer"] = candidate["author"]
                    elif variant == "unchecked":
                        del obj(candidate["assertions"])["close"]
                    elif variant == "digest":
                        obj(obj(candidate["assertions"])["close"])["sha256"] = "0" * 64
                    elif variant == "failed":
                        obj(obj(candidate["assertions"])["close"])["passed"] = False
                    else:
                        candidate["reviewed_at"] = "2026-09-22T00:00:00"
                    with self.assertRaises(GateError):
                        check(
                            [case],
                            {"B0": [case.case_id]},
                            "B0",
                            invalid,
                            IDENTITY,
                            evidence_root=root,
                        )

    def test_manifest_missing_implementation_and_conflicting_keys_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "test.py").write_text("", encoding="utf-8")
            case: dict[str, object] = {
                "case_id": "SCF-B0-07",
                "acceptance_refs": ["SCF-B0-07"],
                "layer": "unit",
                "runner": "unittest",
                "platform": "host",
                "audience": "harness",
                "transport": "local",
                "parameters": {},
                "shard": "quality",
                "nodes": ["test_guard"],
                "source": "test.py",
            }
            data: dict[str, object] = {
                "schema_version": 1,
                "cases": [case],
                "scopes": {"B0": ["SCF-B0-07"]},
            }
            path = root / "manifest.json"
            write_json(path, data)
            self.assertEqual(len(load_manifest(path, root)[0]), 1)
            case["source"] = "missing.py"
            write_json(path, data)
            with self.assertRaises(GateError):
                load_manifest(path, root)
            case["source"] = "test.py"
            data["cases"] = [case, case]
            write_json(path, data)
            with self.assertRaises(GateError):
                load_manifest(path, root)


if __name__ == "__main__":
    unittest.main()
