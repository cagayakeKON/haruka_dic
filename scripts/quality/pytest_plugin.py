"""Optional pytest adapter preserving collection, deselection and per-node outcomes.

Load explicitly with ``-p scripts.quality.pytest_plugin`` from a harness that makes
the repository root importable. No production application imports this module.
"""

from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass, field
from pathlib import Path

import pytest

from scripts.quality.cases import Case, check, identity, load_manifest
from scripts.quality.common import GateError, read_json, string, write_json


@dataclass
class State:
    cases: list[Case]
    scope: str
    shard: str
    output: Path
    run_identity: dict[str, object]
    deselected: list[pytest.Item] = field(default_factory=list[pytest.Item])
    collection: list[dict[str, object]] = field(default_factory=list[dict[str, object]])
    statuses: dict[str, str] = field(default_factory=dict[str, str])
    collection_failed: bool = False

    def report(
        self, phase: str, nodes: list[dict[str, object]], session_status: str = "passed"
    ) -> dict[str, object]:
        return {
            "schema_version": 1,
            "identity": self.run_identity,
            "phase": phase,
            "shard": self.shard,
            "runner": "pytest",
            "platform": self.cases[0].platform,
            "attempt": 1,
            "nodes": nodes,
            "session_status": session_status,
        }


STATE = pytest.StashKey[State]()


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("haruka-quality")
    for name in ("manifest", "identity", "shard", "output", "scope"):
        group.addoption("--quality-" + name, action="store", required=True)


def option(config: pytest.Config, name: str) -> str:
    value: object = config.getoption("quality_" + name)
    return string(value)


def pytest_configure(config: pytest.Config) -> None:
    root = Path(__file__).resolve().parents[2]
    cases, scopes = load_manifest(Path(option(config, "manifest")), root)
    scope = option(config, "scope")
    shard = option(config, "shard")
    if scope not in scopes:
        raise pytest.UsageError("Unknown quality scope")
    selected = [case for case in cases if case.case_id in scopes[scope] and case.shard == shard]
    if not selected or any(case.runner != "pytest" for case in selected):
        raise pytest.UsageError("Shard is not a registered pytest shard")
    output = Path(option(config, "output"))
    if any((output / f"{shard}-{phase}.json").exists() for phase in ("collection", "result")):
        raise pytest.UsageError("Refusing to overwrite previous test evidence")
    config.stash[STATE] = State(
        selected, scope, shard, output, identity(read_json(Path(option(config, "identity"))))
    )


def pytest_deselected(items: list[pytest.Item]) -> None:
    if items:
        items[0].config.stash[STATE].deselected.extend(items)


def pytest_collection_finish(session: pytest.Session) -> None:
    state = session.config.stash[STATE]
    state.collection_failed = session.testsfailed != 0
    mapping = {node: case for case in state.cases for node in case.nodes}
    selected_ids = {item.nodeid for item in session.items}
    for item in [*session.items, *state.deselected]:
        layers = [
            name for name in ("unit", "contract", "integration") if list(item.iter_markers(name))
        ]
        declared_ids: list[str] = []
        for marker in item.iter_markers("case_id"):
            if len(marker.args) != 1:
                raise pytest.UsageError("case_id marker requires exactly one identifier")
            value: object = marker.args[0]
            declared_ids.append(string(value))
        case_ids = [mapping[item.nodeid].case_id] if item.nodeid in mapping else []
        if declared_ids and declared_ids != case_ids:
            raise pytest.UsageError("case_id marker does not match the authoritative node mapping")
        selected = item.nodeid in selected_ids
        state.collection.append(
            {
                "node_id": item.nodeid,
                "case_ids": case_ids,
                "layers": layers,
                "selected": selected,
                "status": "collected" if selected else "deselected",
            }
        )
    report = state.report(
        "collection", state.collection, "failed" if state.collection_failed else "passed"
    )
    write_json(state.output / f"{state.shard}-collection.json", report)
    try:
        summary = check(
            state.cases,
            {state.scope: list(dict.fromkeys(case.case_id for case in state.cases))},
            state.scope,
            [report],
            state.run_identity,
            phase="collection",
        )
        if summary["passed"] is not True:
            raise GateError("required_pytest_nodes_missing_or_deselected")
    except GateError as error:
        raise pytest.UsageError(str(error)) from error


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(
    item: pytest.Item, call: pytest.CallInfo[None]
) -> Generator[None, pytest.TestReport, pytest.TestReport]:
    report = yield
    state = item.config.stash[STATE]
    expected_failure: object = getattr(report, "wasxfail", None)
    if report.skipped:
        state.statuses[item.nodeid] = "xfail" if expected_failure else "skipped"
    elif report.failed:
        state.statuses[item.nodeid] = "failed" if report.when == "call" else "error"
    elif report.when == "call":
        state.statuses.setdefault(item.nodeid, "xpass" if expected_failure else "passed")
    return report


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    state = session.config.stash.get(STATE, None)
    if state is None:
        return
    results = [
        {
            **node,
            "status": state.statuses.get(
                str(node["node_id"]), "deselected" if node["selected"] is False else "interrupted"
            ),
        }
        for node in state.collection
    ]
    collection = state.report(
        "collection", state.collection, "failed" if state.collection_failed else "passed"
    )
    report = state.report("result", results, "passed" if exitstatus == 0 else "failed")
    write_json(state.output / f"{state.shard}-result.json", report)
    try:
        summary = check(
            state.cases,
            {state.scope: list(dict.fromkeys(case.case_id for case in state.cases))},
            state.scope,
            [collection, report],
            state.run_identity,
        )
    except GateError:
        session.exitstatus = pytest.ExitCode.TESTS_FAILED
        return
    write_json(state.output / f"{state.shard}-summary.json", summary)
    if summary["passed"] is not True:
        session.exitstatus = pytest.ExitCode.TESTS_FAILED
