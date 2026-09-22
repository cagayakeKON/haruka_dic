"""Coverage completeness and denominator regressions using explicit small sources."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.quality.common import GateError, array, digest, obj, write_json
from scripts.quality.coverage import gate, inventory
from scripts.tests.test_quality_cases import IDENTITY


class CoverageChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for relative, text in {
            "backend/app/core.py": "value = 1\n",
            "frontend/lib/core.dart": "int value = 1;\n",
            "tools/codegen.json": '{"frontend": []}\n',
        }.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        self.manifest: dict[str, object] = {
            "schema_version": 1,
            "source_roots": {"python": "backend/app", "flutter": "frontend/lib"},
            "generation_manifest": "tools/codegen.json",
            "files": {
                "backend/app/core.py": {
                    "language": "python",
                    "kind": "core",
                    "groups": ["python-core"],
                },
                "frontend/lib/core.dart": {
                    "language": "flutter",
                    "kind": "core",
                    "groups": ["flutter-core"],
                },
            },
            "core_groups": {
                "python-core": {
                    "language": "python",
                    "threshold": 90,
                    "required_prefixes": ["backend/app/core.py"],
                },
                "flutter-core": {
                    "language": "flutter",
                    "threshold": 85,
                    "required_prefixes": ["frontend/lib/core.dart"],
                },
            },
            "thresholds": {"python": 80, "flutter": 75},
            "required_shards": {"python": ["python"], "flutter": ["flutter"]},
        }
        self.python_file: dict[str, object] = {
            "executed_lines": [1],
            "missing_lines": [],
            "executed_branches": [],
            "missing_branches": [],
        }
        self.python_report: dict[str, object] = {
            "meta": {"branch_coverage": True},
            "files": {"app/core.py": self.python_file},
        }
        self.lcov = "SF:lib/core.dart\nDA:1,1\nend_of_record\n"

    def evidence(self) -> dict[str, object]:
        write_json(self.root / "python.json", self.python_report)
        (self.root / "flutter.lcov").write_text(self.lcov, encoding="utf-8")
        return {
            "schema_version": 1,
            "identity": IDENTITY.copy(),
            "shards": [
                {
                    "id": "python",
                    "language": "python",
                    "format": "coverage-json",
                    "path": "python.json",
                    "sha256": digest(self.root / "python.json"),
                    "path_base": "backend",
                },
                {
                    "id": "flutter",
                    "language": "flutter",
                    "format": "lcov",
                    "path": "flutter.lcov",
                    "sha256": digest(self.root / "flutter.lcov"),
                    "path_base": "frontend",
                },
            ],
        }

    def test_inventory_and_weighted_reports_pass_at_threshold(self) -> None:
        self.assertEqual(len(inventory(self.root, self.manifest)), 2)
        self.python_file.update(executed_lines=list(range(1, 10)), missing_lines=[10])
        result = gate(self.root, self.manifest, self.evidence(), IDENTITY)
        self.assertTrue(result["passed"])
        self.python_file.update(executed_lines=list(range(1, 9)), missing_lines=[9, 10])
        self.assertFalse(gate(self.root, self.manifest, self.evidence(), IDENTITY)["passed"])

    def test_new_never_imported_handwritten_file_fails_inventory_then_report(self) -> None:
        (self.root / "backend/app/unimported.py").write_text("value = 0\n", encoding="utf-8")
        with self.assertRaisesRegex(GateError, "unclassified"):
            inventory(self.root, self.manifest)
        obj(self.manifest["files"])["backend/app/unimported.py"] = {
            "language": "python",
            "kind": "ordinary",
            "groups": [],
        }
        with self.assertRaisesRegex(GateError, "source_missing"):
            gate(self.root, self.manifest, self.evidence(), IDENTITY)

    def test_empty_or_incomplete_core_groups_are_rejected(self) -> None:
        self.manifest["core_groups"] = {}
        with self.assertRaisesRegex(GateError, "core"):
            inventory(self.root, self.manifest)

    def test_critical_prefix_cannot_be_reclassified_as_ordinary(self) -> None:
        obj(obj(self.manifest["files"])["backend/app/core.py"]).update(kind="ordinary", groups=[])
        with self.assertRaisesRegex(GateError, "core"):
            inventory(self.root, self.manifest)

    def test_generated_and_declaration_exclusions_cannot_hide_code(self) -> None:
        entry = obj(obj(self.manifest["files"])["backend/app/core.py"])
        for kind in ("generated", "declaration"):
            with self.subTest(kind=kind):
                entry.update(kind=kind, groups=[], reason="intentional bad sample")
                with self.assertRaises(GateError):
                    inventory(self.root, self.manifest)

    def test_unknown_external_and_conflicting_paths_are_rejected(self) -> None:
        for name in ("app/unknown.py", "../outside.py", "/outside.py"):
            with self.subTest(name=name):
                self.python_report["files"] = {name: self.python_file}
                with self.assertRaises(GateError):
                    gate(self.root, self.manifest, self.evidence(), IDENTITY)
        self.python_report["files"] = {
            "app/core.py": self.python_file,
            "app/CORE.py": self.python_file,
        }
        with self.assertRaises(GateError):
            gate(self.root, self.manifest, self.evidence(), IDENTITY)

    def test_missing_empty_corrupt_and_zero_denominator_reports_fail(self) -> None:
        self.python_report["files"] = {}
        with self.assertRaisesRegex(GateError, "empty"):
            gate(self.root, self.manifest, self.evidence(), IDENTITY)
        self.python_report["files"] = {
            "app/core.py": {
                "executed_lines": [],
                "missing_lines": [],
                "executed_branches": [],
                "missing_branches": [],
            }
        }
        with self.assertRaisesRegex(GateError, "zero"):
            gate(self.root, self.manifest, self.evidence(), IDENTITY)
        self.python_report["files"] = {"app/core.py": self.python_file}
        for content in ("", "not lcov", "SF:lib/core.dart\nDA:bad,1\nend_of_record\n"):
            with self.subTest(content=content):
                self.lcov = content
                with self.assertRaises(GateError):
                    gate(self.root, self.manifest, self.evidence(), IDENTITY)

    def test_missing_shard_and_report_digest_mismatch_fail(self) -> None:
        evidence = self.evidence()
        evidence["shards"] = []
        with self.assertRaisesRegex(GateError, "missing_coverage_shard"):
            gate(self.root, self.manifest, evidence, IDENTITY)
        evidence = self.evidence()
        (self.root / "python.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(GateError, "digest"):
            gate(self.root, self.manifest, evidence, IDENTITY)

    def test_overlapping_shards_use_union_not_summed_percentages(self) -> None:
        self.python_file.update(executed_lines=list(range(1, 9)), missing_lines=[9, 10])
        evidence = self.evidence()
        duplicate = obj(array(evidence["shards"])[0]).copy()
        duplicate["id"] = "python-second"
        array(evidence["shards"]).append(duplicate)
        obj(self.manifest["required_shards"])["python"] = ["python", "python-second"]
        result = gate(self.root, self.manifest, evidence, IDENTITY)
        self.assertFalse(result["passed"])
        groups = array(result["groups"])
        self.assertEqual(obj(groups[0])["denominator"], 10)

    def test_average_file_percentages_cannot_pass_weighted_threshold(self) -> None:
        (self.root / "backend/app/large.py").write_text("value = 1\n" * 100, encoding="utf-8")
        obj(self.manifest["files"])["backend/app/large.py"] = {
            "language": "python",
            "kind": "ordinary",
            "groups": [],
        }
        obj(self.python_report["files"])["app/large.py"] = {
            "executed_lines": list(range(1, 61)),
            "missing_lines": list(range(61, 101)),
            "executed_branches": [],
            "missing_branches": [],
        }
        # Averaging 100% and 60% would pass 80%; weighted coverage is only 61/101.
        self.assertFalse(gate(self.root, self.manifest, self.evidence(), IDENTITY)["passed"])

    def test_branches_are_in_python_denominator(self) -> None:
        self.python_file.update(executed_branches=[[1, 2]], missing_branches=[[1, -1]])
        self.assertFalse(gate(self.root, self.manifest, self.evidence(), IDENTITY)["passed"])

    def test_cross_platform_paths_require_explicit_checkout_mapping(self) -> None:
        self.python_report["files"] = {"C:\\agent\\work\\backend\\app\\CORE.py": self.python_file}
        evidence = self.evidence()
        with self.assertRaises(GateError):
            gate(self.root, self.manifest, evidence, IDENTITY)
        obj(array(evidence["shards"])[0])["checkout_root"] = "C:/agent/work"
        self.assertTrue(gate(self.root, self.manifest, evidence, IDENTITY)["passed"])


if __name__ == "__main__":
    unittest.main()
