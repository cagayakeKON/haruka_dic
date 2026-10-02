"""Frozen compiler inventories share denominator points, never cross-shard execution hits."""

from __future__ import annotations

import copy
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.quality.common import GateError, array, digest, obj, write_json
from scripts.quality.coverage import Hits, flutter_hits
from scripts.quality.flutter_lcov_normalization import normalize
from scripts.tests import test_quality_coverage as coverage_fixture


class NormalizationChecks(unittest.TestCase):
    def setUp(self) -> None:
        fixture = coverage_fixture.CoverageChecks()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.root = fixture.root
        self.manifest = copy.deepcopy(fixture.manifest)
        self.manifest["required_shards"] = {
            "python": ["python"],
            "flutter": ["flutter-unit-widget", "flutter-web-widget"],
        }
        (self.root / "frontend/lib/core.dart").write_text(
            "int get value => 1;\nfinal count = 2;\nint value = 3;\n"
        )
        self.reports: list[dict[str, object]] = []
        self.add_report("vm", "flutter-unit-widget", {1: 4, 2: 0})
        self.add_report("web", "flutter-web-widget", {2: 7, 3: 0})

    def add_report(self, name: str, shard: str, counts: dict[int, int]) -> None:
        raw = self.root / (name + ".lcov")
        raw.write_text(
            "SF:lib/core.dart\n"
            + "".join(f"DA:{n},{v}\n" for n, v in counts.items())
            + "end_of_record\n"
        )
        source = self.root / (name + "-sources.json")
        execution = self.root / (name + "-execution.json")
        write_json(
            source,
            {
                "source_hashes": {
                    "frontend/lib/core.dart": digest(self.root / "frontend/lib/core.dart")
                }
            },
        )
        write_json(
            execution,
            {
                "lcov_sha256": digest(raw),
                "exit_code": 0,
                "error_count": 0,
                "native_done": {"success": True},
                "compiler_version": "fixture-v1",
            },
        )
        self.reports.append(
            {
                "id": name,
                "shard": shard,
                "compiler": "vm" if shard == "flutter-unit-widget" else "ddc",
                "path": raw.name,
                "sha256": digest(raw),
                "source_proof": source.name,
                "source_proof_sha256": digest(source),
                "execution_proof": execution.name,
                "execution_proof_sha256": digest(execution),
            }
        )

    def run_normalize(self) -> dict[str, object]:
        return normalize(
            self.root,
            self.manifest,
            {"schema_version": 1, "reports": self.reports},
            "normalized",
        )

    def test_union_pads_zero_and_keeps_each_real_shards_hits_and_multiple_vm_runs(
        self,
    ) -> None:
        self.add_report("vm-extra", "flutter-unit-widget", {1: 5, 3: 2})
        original = {p: p.read_bytes() for p in self.root.glob("*.lcov")}
        result = self.run_normalize()
        vm = flutter_hits(self.root / "normalized/flutter-unit-widget.lcov")[
            "frontend/lib/core.dart"
        ]
        web = flutter_hits(self.root / "normalized/flutter-web-widget.lcov")[
            "frontend/lib/core.dart"
        ]
        self.assertEqual(vm.lines, {1, 2, 3})
        self.assertEqual(web.lines, {1, 2, 3})
        self.assertEqual(vm.hit_lines, {1, 3})
        self.assertEqual(web.hit_lines, {2})
        self.assertIn("DA:1,9", (self.root / "normalized/flutter-unit-widget.lcov").read_text())
        vm.merge(web)
        self.assertEqual(vm.hit_lines, {1, 2, 3})
        self.assertEqual(result["canonical_line_points"], 3)
        for path, content in original.items():
            self.assertEqual(path.read_bytes(), content)

    def test_general_merge_still_rejects_different_denominators(self) -> None:
        with self.assertRaisesRegex(GateError, "conflicting_shard_denominators"):
            Hits({1}, {1}).merge(Hits({2}, {2}))

    def test_changed_source_hash_rejects_before_output(self) -> None:
        (self.root / "frontend/lib/core.dart").write_text("changed\n")
        with self.assertRaisesRegex(GateError, "frozen_source_hash_mismatch"):
            self.run_normalize()
        self.assertFalse((self.root / "normalized").exists())

    def test_report_hash_and_native_binding_are_required(self) -> None:
        self.reports[0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(GateError, "provenance_digest"):
            self.run_normalize()
        self.reports[0]["sha256"] = digest(self.root / "vm.lcov")
        write_json(self.root / "vm-execution.json", {"lcov_sha256": "0" * 64, "exit_code": 0})
        self.reports[0]["execution_proof_sha256"] = digest(self.root / "vm-execution.json")
        with self.assertRaisesRegex(GateError, "lcov_not_bound"):
            self.run_normalize()

    def test_unknown_source_path_rejects(self) -> None:
        path = self.root / "vm.lcov"
        path.write_text(path.read_text().replace("lib/core.dart", "../../outside.dart"))
        self.rebind_vm()
        with self.assertRaises(GateError):
            self.run_normalize()

    def rebind_vm(self) -> None:
        self.reports[0]["sha256"] = digest(self.root / "vm.lcov")
        write_json(
            self.root / "vm-execution.json",
            {
                "lcov_sha256": self.reports[0]["sha256"],
                "exit_code": 0,
                "error_count": 0,
                "native_done": {"success": True},
            },
        )
        self.reports[0]["execution_proof_sha256"] = digest(self.root / "vm-execution.json")

    def test_zero_outside_source_duplicate_and_negative_points_reject(self) -> None:
        for values in ["DA:0,1", "DA:4,1", "DA:1,-1", "DA:1,1\nDA:1,0"]:
            with self.subTest(values=values):
                (self.root / "vm.lcov").write_text(
                    "SF:lib/core.dart\n" + values + "\nend_of_record\n"
                )
                self.rebind_vm()
                with self.assertRaises(GateError):
                    self.run_normalize()

    def test_branch_records_fail_closed(self) -> None:
        path = self.root / "vm.lcov"
        path.write_text(path.read_text().replace("end_of_record", "BRDA:1,0,0,1\nend_of_record"))
        self.rebind_vm()
        with self.assertRaisesRegex(GateError, "incompatible_flutter_branch_semantics"):
            self.run_normalize()

    def test_missing_real_shard_and_duplicate_actual_report_reject(self) -> None:
        missing = self.reports.pop()
        with self.assertRaisesRegex(GateError, "missing_actual_flutter_shard"):
            self.run_normalize()
        self.reports.append(missing)
        self.reports.append(self.reports[0] | {"id": "duplicate"})
        with self.assertRaisesRegex(GateError, "duplicate_actual_lcov_input"):
            self.run_normalize()

    def test_missing_source_across_all_reports_remains_fatal(self) -> None:
        (self.root / "frontend/lib/new.dart").write_text("final n = 1;\n")
        obj(self.manifest["files"])["frontend/lib/new.dart"] = {
            "language": "flutter",
            "kind": "ordinary",
            "groups": [],
        }
        with self.assertRaisesRegex(GateError, "source_missing_from_actual_coverage"):
            self.run_normalize()

    def test_probe_is_verified_and_excluded_without_losing_business_points(
        self,
    ) -> None:
        probe = self.root / "frontend/test/support/coverage_semantics_probe.dart"
        probe.parent.mkdir(parents=True)
        probe.write_text("int probe = 1;\n")
        path = self.root / "web.lcov"
        path.write_text(
            path.read_text()
            + "SF:test/support/coverage_semantics_probe.dart\nDA:1,7\nend_of_record\n"
        )
        source = self.root / "web-sources.json"
        write_json(
            source,
            {
                "source_hashes": {
                    "frontend/lib/core.dart": digest(self.root / "frontend/lib/core.dart"),
                    "frontend/test/support/coverage_semantics_probe.dart": digest(probe),
                }
            },
        )
        self.reports[1]["sha256"] = digest(path)
        self.reports[1]["source_proof_sha256"] = digest(source)
        execution = self.root / "web-execution.json"
        write_json(
            execution,
            {
                "lcov_sha256": digest(path),
                "exit_code": 0,
                "error_count": 0,
                "native_done": {"success": True},
            },
        )
        self.reports[1]["execution_proof_sha256"] = digest(execution)
        result = self.run_normalize()
        self.assertNotIn(
            "probe.dart", (self.root / "normalized/flutter-web-widget.lcov").read_text()
        )
        self.assertEqual(result["canonical_line_points"], 3)
        self.assertEqual(len(array(result["gate_shards"])), 2)

    def test_wrong_compiler_failed_execution_and_existing_output_reject(self) -> None:
        self.reports[0]["compiler"] = "ddc"
        with self.assertRaisesRegex(GateError, "compiler_shard_mismatch"):
            self.run_normalize()
        self.reports[0]["compiler"] = "vm"
        path = self.root / "vm-execution.json"
        write_json(path, {"lcov_sha256": digest(self.root / "vm.lcov"), "exit_code": 1})
        self.reports[0]["execution_proof_sha256"] = digest(path)
        with self.assertRaises(GateError):
            self.run_normalize()
        self.rebind_vm()
        (self.root / "normalized").mkdir()
        with self.assertRaisesRegex(GateError, "output_already_exists"):
            self.run_normalize()

    def test_source_changed_after_cached_parse_rejects_before_output(self) -> None:
        source = self.root / "frontend/lib/core.dart"

        def changed_digest(path: Path) -> str:
            if path == source:
                source.write_text("changed source\n")
            return digest(path)

        with (
            patch(
                "scripts.quality.flutter_lcov_normalization.digest",
                side_effect=changed_digest,
            ),
            self.assertRaisesRegex(GateError, "frozen_source_changed_during_normalization"),
        ):
            self.run_normalize()
        self.assertFalse((self.root / "normalized").exists())

    def test_missing_native_status_failed_count_and_done_reject(self) -> None:
        execution = self.root / "web-execution.json"
        for evidence in [
            {},
            {"exit_code": False},
            {"exit_code": 0, "error_count": 5, "native_done": {"success": True}},
            {
                "exit_code": 0,
                "error_count": 0,
                "native_done": {"success": False},
            },
        ]:
            with self.subTest(evidence=evidence):
                write_json(execution, {"lcov_sha256": digest(self.root / "web.lcov")} | evidence)
                self.reports[1]["execution_proof_sha256"] = digest(execution)
                with self.assertRaises(GateError):
                    self.run_normalize()
