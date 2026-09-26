"""Collect and execute registered tooling tests, preserving individual real outcomes."""

from __future__ import annotations

import argparse
import sys
import unittest
from pathlib import Path
from types import TracebackType

from scripts.quality.cases import Case, check, identity, load_manifest
from scripts.quality.common import GateError, read_json, write_json

type TestError = tuple[type[BaseException], BaseException, TracebackType] | tuple[None, None, None]


class RecordedResult(unittest.TestResult):
    """Retain statuses only; unittest failure strings can contain fixture secrets."""

    def __init__(self) -> None:
        super().__init__()
        self.statuses: dict[str, str] = {}

    def addSuccess(self, test: unittest.TestCase) -> None:
        super().addSuccess(test)
        self.statuses.setdefault(test.id(), "passed")

    def addError(self, test: unittest.TestCase, err: TestError) -> None:
        super().addError(test, err)
        self.statuses[test.id()] = "error"

    def addFailure(self, test: unittest.TestCase, err: TestError) -> None:
        super().addFailure(test, err)
        self.statuses[test.id()] = "failed"

    def addSkip(self, test: unittest.TestCase, reason: str) -> None:
        super().addSkip(test, reason)
        self.statuses[test.id()] = "skipped"

    def addExpectedFailure(self, test: unittest.TestCase, err: TestError) -> None:
        super().addExpectedFailure(test, err)
        self.statuses[test.id()] = "xfail"

    def addUnexpectedSuccess(self, test: unittest.TestCase) -> None:
        super().addUnexpectedSuccess(test)
        self.statuses[test.id()] = "xpass"

    def addSubTest(
        self, test: unittest.TestCase, subtest: unittest.TestCase, err: TestError | None
    ) -> None:
        super().addSubTest(test, subtest, err)
        if err is not None:
            self.statuses[test.id()] = "failed"


def flatten(suite: unittest.TestSuite) -> list[unittest.TestCase]:
    result: list[unittest.TestCase] = []
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            result.extend(flatten(item))
        else:
            result.append(item)
    return result


def execute(cases: list[Case], scope: str, run_identity: dict[str, object], output: Path) -> bool:
    run_identity = identity(run_identity)
    if not cases or any(case.runner != "unittest" for case in cases):
        raise GateError("unittest_runner_scope_contains_other_drivers")
    report_paths = [
        output / f"{shard}-{phase}.json"
        for shard in {case.shard for case in cases}
        for phase in ("collection", "result")
    ]
    if any(path.exists() for path in report_paths):
        raise GateError("refuse_to_overwrite_previous_attempt")
    reports: list[dict[str, object]] = []
    for shard in sorted({case.shard for case in cases}):
        selected = [case for case in cases if case.shard == shard]
        mapping = {node: case for case in selected for node in case.nodes}
        loader = unittest.TestLoader()
        suite = loader.loadTestsFromNames(list(mapping))
        tests = flatten(suite)
        if (
            loader.errors
            or len(tests) != len(mapping)
            or {test.id() for test in tests} != set(mapping)
        ):
            raise GateError("required_unittest_not_collected")
        nodes: list[dict[str, object]] = [
            {
                "node_id": test.id(),
                "case_ids": [mapping[test.id()].case_id],
                "layers": [mapping[test.id()].layer],
                "selected": True,
                "status": "collected",
            }
            for test in tests
        ]
        common: dict[str, object] = {
            "schema_version": 1,
            "identity": run_identity,
            "shard": shard,
            "runner": "unittest",
            "platform": selected[0].platform,
            "attempt": 1,
        }
        collection = {**common, "phase": "collection", "nodes": nodes, "session_status": "passed"}
        write_json(output / f"{shard}-collection.json", collection)
        reports.append(collection)
        result = RecordedResult()
        suite.run(result)
        result_nodes = [
            {**node, "status": result.statuses.get(str(node["node_id"]), "interrupted")}
            for node in nodes
        ]
        for node_id in sorted(set(result.statuses) - set(mapping)):
            result_nodes.append(
                {
                    "node_id": node_id,
                    "case_ids": [],
                    "layers": [selected[0].layer],
                    "selected": True,
                    "status": result.statuses[node_id],
                }
            )
        execution = {
            **common,
            "phase": "result",
            "nodes": result_nodes,
            "session_status": "passed" if result.wasSuccessful() else "failed",
        }
        write_json(output / f"{shard}-result.json", execution)
        reports.append(execution)
    summary = check(
        cases,
        {scope: list(dict.fromkeys(case.case_id for case in cases))},
        scope,
        reports,
        run_identity,
    )
    write_json(output / "summary.json", summary)
    return summary["passed"] is True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--manifest", type=Path, default=Path(__file__).with_name("required_cases.json")
    )
    parser.add_argument("--scope", default="foundation-quality")
    parser.add_argument("--identity", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        cases, scopes = load_manifest(args.manifest, args.root)
        if args.scope not in scopes:
            raise GateError("unknown_scope")
        selected = [case for case in cases if case.case_id in scopes[args.scope]]
        return 0 if execute(selected, args.scope, read_json(args.identity), args.output) else 1
    except (GateError, OSError) as error:
        sys.stderr.write(f"Unittest evidence collection failed: {error}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
