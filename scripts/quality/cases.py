"""Fail closed on missing collection, variants, drivers, shards, or passing results."""

from __future__ import annotations

import argparse
import hashlib
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from scripts.quality.common import (
    GateError,
    array,
    canonical,
    digest,
    fields,
    integer,
    obj,
    read_json,
    repo_path,
    safe_name,
    string,
    strings,
    version,
    write_json,
)

LAYERS = frozenset({"unit", "widget", "contract", "integration", "platform", "artifact"})
RUNNERS = frozenset(
    {"pytest", "unittest", "flutter_test", "integration_test", "playwright", "patrol", "procedure"}
)
STATUSES = frozenset(
    {"passed", "failed", "error", "skipped", "xfail", "xpass", "deselected", "interrupted"}
)


@dataclass(frozen=True)
class Case:
    case_id: str
    acceptance_refs: tuple[str, ...]
    layer: str
    runner: str
    platform: str
    audience: str
    transport: str
    parameters: str
    shard: str
    nodes: tuple[str, ...]
    source: str
    assertions: tuple[str, ...] = ()

    @property
    def key(self) -> str:
        variant = canonical(
            [self.layer, self.runner, self.platform, self.audience, self.transport, self.parameters]
        )
        return self.case_id + ":" + hashlib.sha256(variant.encode()).hexdigest()[:20]


def load_manifest(path: Path, root: Path) -> tuple[list[Case], dict[str, list[str]]]:
    data = read_json(path)
    version(data)
    fields(data, {"schema_version", "cases", "scopes"})
    cases: list[Case] = []
    for raw in array(data["cases"]):
        item = obj(raw)
        fields(item, set(Case.__dataclass_fields__) - {"assertions"}, {"assertions"})
        case = Case(
            case_id=safe_name(item["case_id"]),
            acceptance_refs=tuple(strings(item["acceptance_refs"])),
            layer=string(item["layer"]),
            runner=string(item["runner"]),
            platform=safe_name(item["platform"]),
            audience=safe_name(item["audience"]),
            transport=safe_name(item["transport"]),
            parameters=canonical(obj(item["parameters"])),
            shard=safe_name(item["shard"]),
            nodes=tuple(strings(item["nodes"])),
            source=string(item["source"]),
            assertions=tuple(strings(item.get("assertions", []), empty=True)),
        )
        if case.layer not in LAYERS or case.runner not in RUNNERS:
            raise GateError("unknown_layer_or_runner")
        if (case.runner == "procedure") != bool(case.assertions):
            raise GateError("procedure_requires_explicit_assertion_checklist")
        repo_path(root, case.source)
        cases.append(case)
    if not cases or len({case.key for case in cases}) != len(cases):
        raise GateError("empty_or_duplicate_case_id")
    scopes = {safe_name(key): strings(value) for key, value in obj(data["scopes"]).items()}
    known = {case.case_id for case in cases}
    if not scopes or any(set(ids) - known for ids in scopes.values()):
        raise GateError("scope_has_unknown_case_id")
    if known - {case_id for ids in scopes.values() for case_id in ids}:
        raise GateError("case_not_in_any_scope")
    shards: dict[str, tuple[str, str]] = {}
    owners: set[tuple[str, str]] = set()
    for case in cases:
        signature = (case.runner, case.platform)
        if case.shard in shards and shards[case.shard] != signature:
            raise GateError("conflicting_shard_driver")
        shards[case.shard] = signature
        for node in case.nodes:
            pair = (case.shard, node)
            if pair in owners:
                raise GateError("conflicting_node_mapping")
            owners.add(pair)
    return cases, scopes


def identity(value: object) -> dict[str, object]:
    result = obj(value)
    fields(result, {"commit", "build_id", "configuration", "toolchain_sha256", "run_id"})
    for key, entry in result.items():
        safe_name(entry)
        if key in {"commit", "toolchain_sha256"}:
            token = string(entry)
            if len(token) not in ({40, 64} if key == "commit" else {64}):
                raise GateError("invalid_evidence_digest")
            if any(char not in "0123456789abcdef" for char in token):
                raise GateError("invalid_evidence_digest")
    return result


def procedure_evidence(value: object, case: Case, root: Path | None) -> None:
    """Require independently reviewed, hash-bound evidence for every manual assertion."""
    if root is None:
        raise GateError("procedure_evidence_root_required")
    receipt = obj(value)
    fields(receipt, {"author", "reviewer", "reviewed_at", "assertions"})
    if safe_name(receipt["author"]) == safe_name(receipt["reviewer"]):
        raise GateError("procedure_requires_independent_reviewer")
    try:
        reviewed_at = datetime.fromisoformat(string(receipt["reviewed_at"]))
    except ValueError as error:
        raise GateError("invalid_procedure_review_time") from error
    if reviewed_at.tzinfo is None:
        raise GateError("procedure_review_time_requires_timezone")
    assertions = obj(receipt["assertions"])
    if set(assertions) != set(case.assertions):
        raise GateError("procedure_assertion_checklist_mismatch")
    for value in assertions.values():
        entry = obj(value)
        fields(entry, {"passed", "evidence_path", "sha256"})
        if entry["passed"] is not True:
            raise GateError("procedure_assertion_failed")
        path = repo_path(root, entry["evidence_path"])
        if path.stat().st_size == 0 or digest(path) != entry["sha256"]:
            raise GateError("procedure_evidence_empty_or_digest_mismatch")


def check(
    cases: list[Case],
    scopes: dict[str, list[str]],
    scope: str,
    reports: list[dict[str, object]],
    expected_identity: dict[str, object],
    *,
    phase: str = "result",
    evidence_root: Path | None = None,
) -> dict[str, object]:
    """Validate the independently declared matrix against real collector records.

    Both phases require selected, correctly mapped nodes. Results additionally
    require every owned shard's first and subsequent attempts to have passed;
    a successful retry never erases a recorded failure.
    """
    if scope not in scopes or phase not in {"collection", "result"}:
        raise GateError("unknown_scope_or_phase")
    expected_identity = identity(expected_identity)
    selected = [case for case in cases if case.case_id in scopes[scope]]
    shards = {case.shard for case in selected}
    known = {case.case_id for case in cases}
    records: dict[tuple[str, str, int], list[dict[str, object]]] = {}
    seen_reports: set[tuple[str, str, int]] = set()
    report_failures: list[str] = []
    for report in reports:
        version(report)
        fields(
            report,
            {
                "schema_version",
                "identity",
                "phase",
                "shard",
                "runner",
                "platform",
                "attempt",
                "nodes",
                "session_status",
            },
        )
        if identity(report["identity"]) != expected_identity:
            raise GateError("evidence_identity_mismatch")
        shard = safe_name(report["shard"])
        report_phase = string(report["phase"])
        attempt = integer(report["attempt"], minimum=1)
        token = (shard, report_phase, attempt)
        if token in seen_reports or report_phase not in {"collection", "result"}:
            raise GateError("duplicate_or_invalid_report")
        seen_reports.add(token)
        if shard not in shards:
            raise GateError("unexpected_shard")
        expected = next(case for case in selected if case.shard == shard)
        if report["runner"] != expected.runner or report["platform"] != expected.platform:
            raise GateError("wrong_runner_or_platform")
        session_status = string(report["session_status"])
        if session_status not in {"passed", "failed", "interrupted"}:
            raise GateError("invalid_session_status")
        if session_status != "passed":
            report_failures.append("session_failed_or_interrupted")
        nodes = array(report["nodes"])
        if not nodes:
            raise GateError("empty_report")
        node_ids: set[str] = set()
        for value in nodes:
            node = obj(value)
            fields(node, {"node_id", "case_ids", "layers", "selected", "status"}, {"procedure"})
            node_id = string(node["node_id"])
            if node_id in node_ids:
                raise GateError("duplicate_node")
            node_ids.add(node_id)
            layers = strings(node["layers"])
            case_ids = strings(node["case_ids"], empty=True)
            if len(layers) != 1 or layers[0] not in LAYERS:
                raise GateError("zero_or_multiple_primary_layers")
            if set(case_ids) - known:
                raise GateError("unknown_case_id")
            if not isinstance(node["selected"], bool):
                raise GateError("invalid_selected_flag")
            status = string(node["status"])
            if report_phase == "collection" and status not in {"collected", "deselected"}:
                raise GateError("invalid_collection_status")
            if report_phase == "result" and status not in STATUSES:
                raise GateError("invalid_result_status")
            if report_phase == "result" and report["runner"] == "procedure" and status == "passed":
                owners = [
                    case for case in selected if case.shard == shard and node_id in case.nodes
                ]
                if len(owners) != 1:
                    raise GateError("procedure_node_without_unique_owner")
                procedure_evidence(node.get("procedure"), owners[0], evidence_root)
            if node["selected"] is True and not case_ids:
                report_failures.append("selected_node_without_case_id")
            if report_phase == "result" and node["selected"] is True and status != "passed":
                report_failures.append("nonpassing_selected_node")
            records.setdefault((shard, report_phase, attempt), []).append(node)
    checks: list[dict[str, object]] = []
    for shard, report_phase, attempt in seen_reports:
        if (shard, report_phase, 1) not in seen_reports:
            report_failures.append("missing_original_attempt")
        if phase == "result" and (shard, "collection", attempt) not in seen_reports:
            report_failures.append("attempt_missing_collection")
        if phase == "result" and (shard, "result", attempt) not in seen_reports:
            report_failures.append("attempt_missing_result")
    failures = len(report_failures)
    phases = ("collection", "result") if phase == "result" else ("collection",)
    for case in selected:
        attempts = sorted(
            {attempt for shard, _, attempt in seen_reports if shard == case.shard}
        ) or [1]
        for attempt in attempts:
            for requested_phase in phases:
                candidates = records.get((case.shard, requested_phase, attempt), [])
                for node_id in case.nodes:
                    matches = [node for node in candidates if node["node_id"] == node_id]
                    status = "missing"
                    if matches:
                        node = matches[0]
                        acceptable = "collected" if requested_phase == "collection" else "passed"
                        if node["case_ids"] != [case.case_id] or node["layers"] != [case.layer]:
                            status = "mapping_mismatch"
                        elif node["selected"] is not True or node["status"] != acceptable:
                            status = string(node["status"])
                            if status in {"passed", "collected"}:
                                status = "deselected"
                        else:
                            status = "passed"
                    if status != "passed":
                        failures += 1
                    checks.append(
                        {
                            "key": case.key,
                            "shard": case.shard,
                            "attempt": attempt,
                            "node_id": node_id,
                            "phase": requested_phase,
                            "status": status,
                        }
                    )
    return {
        "schema_version": 1,
        "scope": scope,
        "phase": phase,
        "identity": expected_identity,
        "passed": failures == 0,
        "failures": failures,
        "checks": checks,
        "report_failures": report_failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--manifest", type=Path, default=Path(__file__).with_name("required_cases.json")
    )
    parser.add_argument("--scope", required=True)
    parser.add_argument("--identity", type=Path, required=True)
    parser.add_argument("--phase", choices=["collection", "result"], default="result")
    parser.add_argument("--report", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        cases, scopes = load_manifest(args.manifest, args.root)
        result = check(
            cases,
            scopes,
            args.scope,
            [read_json(path) for path in args.report],
            read_json(args.identity),
            phase=args.phase,
            evidence_root=args.root,
        )
        write_json(args.output, result)
        return 0 if result["passed"] else 1
    except (GateError, OSError) as error:
        sys.stderr.write(f"Required-case gate rejected evidence: {error}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
