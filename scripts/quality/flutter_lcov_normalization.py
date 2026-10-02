"""Normalize frozen VM/DDC line inventories without sharing execution hits between shards."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from scripts.quality.common import (
    GateError,
    array,
    digest,
    fields,
    obj,
    read_json,
    repo_path,
    string,
    version,
    write_json,
)
from scripts.quality.coverage import inventory, normalize_path

PROBE = "frontend/test/support/coverage_semantics_probe.dart"


def proof_hashes(proof: dict[str, object]) -> dict[str, str]:
    if "source_hashes" in proof:
        return {name: string(value) for name, value in obj(proof["source_hashes"]).items()}
    result: dict[str, str] = {}
    for raw in array(proof.get("sources")):
        record = obj(raw)
        name = string(record.get("path"))
        if name in result:
            raise GateError("duplicate_frozen_source")
        result[name] = string(record.get("sha256"))
    return result


def parse(
    root: Path,
    path: Path,
    files: dict[str, dict[str, object]],
    hashes: dict[str, str],
    frozen: dict[str, tuple[str, int]],
) -> tuple[dict[str, dict[int, int]], list[str]]:
    records: dict[str, dict[int, int]] = {}
    excluded: list[str] = []
    current: str | None = None
    counts: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(("BRDA:", "BRF:", "BRH:")):
            raise GateError("incompatible_flutter_branch_semantics")
        if line.startswith("SF:"):
            if current is not None:
                raise GateError("unterminated_lcov_record")
            raw = line[3:].replace("\\", "/")
            candidate = "frontend/" + raw
            current = PROBE if candidate == PROBE else normalize_path(root, "frontend", raw, files)
            if current != PROBE and files[current]["language"] != "flutter":
                raise GateError("wrong_lcov_language")
            if current in records or current in excluded:
                raise GateError("duplicate_lcov_source")
            if current not in frozen:
                content = repo_path(root, current).read_bytes()
                frozen[current] = (
                    hashlib.sha256(content).hexdigest(),
                    len(content.decode("utf-8").splitlines()),
                )
            if hashes.get(current) != frozen[current][0]:
                raise GateError("frozen_source_hash_mismatch")
            counts = {}
        elif line.startswith("DA:"):
            if current is None:
                raise GateError("lcov_hits_outside_file")
            pieces = line[3:].split(",")
            if len(pieces) != 2:
                raise GateError("unsupported_lcov_line_semantics")
            try:
                number, count = map(int, pieces)
            except ValueError as error:
                raise GateError("invalid_lcov_line") from error
            if number < 1 or count < 0 or number in counts:
                raise GateError("invalid_lcov_point")
            if number > frozen[current][1]:
                raise GateError("lcov_point_outside_source")
            counts[number] = count
        elif line == "end_of_record":
            if current is None:
                raise GateError("missing_lcov_source")
            if current == PROBE:
                excluded.append(current)
            else:
                records[current] = counts
            current = None
        elif line and not line.startswith(("TN:", "LF:", "LH:", "FN:", "FNDA:", "FNF:", "FNH:")):
            raise GateError("unsupported_lcov_record")
    if current is not None or not records:
        raise GateError("empty_or_incomplete_lcov")
    return records, excluded


def normalize(
    root: Path, manifest: dict[str, object], plan: dict[str, object], output: str
) -> dict[str, object]:
    version(plan)
    fields(plan, {"schema_version", "reports"})
    files = inventory(root, manifest)
    required = {string(name) for name in array(obj(manifest["required_shards"])["flutter"])}
    shards: dict[str, dict[str, dict[int, int]]] = {}
    denominators: dict[str, set[int]] = {}
    proofs: list[dict[str, object]] = []
    sources: dict[str, str] = {}
    seen: set[str] = set()
    input_paths: set[Path] = set()
    frozen: dict[str, tuple[str, int]] = {}
    for raw in array(plan["reports"]):
        report = obj(raw)
        fields(
            report,
            {
                "id",
                "shard",
                "compiler",
                "path",
                "sha256",
                "source_proof",
                "source_proof_sha256",
                "execution_proof",
                "execution_proof_sha256",
            },
        )
        identifier = string(report["id"])
        input_path = repo_path(root, report["path"]).resolve()
        if input_path in input_paths:
            raise GateError("duplicate_actual_lcov_input")
        input_paths.add(input_path)
        shard = string(report["shard"])
        compiler = string(report["compiler"])
        if identifier in seen or shard not in required:
            raise GateError("duplicate_or_unknown_normalization_input")
        seen.add(identifier)
        if compiler not in {"vm", "ddc"}:
            raise GateError("unknown_flutter_compiler")
        if (shard == "flutter-unit-widget") != (compiler == "vm"):
            raise GateError("compiler_shard_mismatch")
        path = repo_path(root, report["path"])
        source_proof = repo_path(root, report["source_proof"])
        execution_proof = repo_path(root, report["execution_proof"])
        if (
            digest(path) != report["sha256"]
            or digest(source_proof) != report["source_proof_sha256"]
            or digest(execution_proof) != report["execution_proof_sha256"]
        ):
            raise GateError("normalization_provenance_digest_mismatch")
        execution = read_json(execution_proof)
        if execution.get("lcov_sha256") != digest(path):
            raise GateError("lcov_not_bound_to_execution_proof")
        if type(execution.get("exit_code")) is not int or execution["exit_code"] != 0:
            raise GateError("failed_or_missing_native_execution")
        if type(execution.get("error_count")) is not int or execution["error_count"] != 0:
            raise GateError("failed_native_execution")
        if obj(execution.get("native_done")).get("success") is not True:
            raise GateError("failed_native_execution")
        for dependency in array(execution.get("evidence_artifacts", [])):
            evidence = obj(dependency)
            fields(evidence, {"path", "sha256"})
            if digest(repo_path(root, evidence["path"])) != evidence["sha256"]:
                raise GateError("native_evidence_digest_mismatch")
        hashes = proof_hashes(read_json(source_proof))
        records, excluded = parse(root, path, files, hashes, frozen)
        target = shards.setdefault(shard, {})
        for name, counts in records.items():
            sources[name] = hashes[name]
            denominators.setdefault(name, set()).update(counts)
            own = target.setdefault(name, {})
            for number, count in counts.items():
                own[number] = own.get(number, 0) + count
        proofs.append(
            report | {"excluded_probe_sources": excluded, "execution_metadata": execution}
        )
    if set(shards) != required:
        raise GateError("missing_actual_flutter_shard")
    executable = {
        name
        for name, item in files.items()
        if item["language"] == "flutter" and item["kind"] in {"ordinary", "core"}
    }
    if any(not denominators.get(name) for name in executable):
        raise GateError("source_missing_from_actual_coverage")
    if any(digest(repo_path(root, name)) != expected for name, (expected, _) in frozen.items()):
        raise GateError("frozen_source_changed_during_normalization")
    destination = repo_path(root, output, must_exist=False)
    if destination.exists():
        raise GateError("normalization_output_already_exists")
    outputs: list[dict[str, object]] = []
    contents: dict[str, str] = {}
    for shard, own in sorted(shards.items()):
        text: list[str] = []
        padding = 0
        hit_count = 0
        for name, numbers in sorted(denominators.items()):
            text.append("SF:" + name)
            for number in sorted(numbers):
                count = own.get(name, {}).get(number, 0)
                padding += number not in own.get(name, {})
                hit_count += count > 0
                text.append(f"DA:{number},{count}")
            text.extend(
                [
                    f"LF:{len(numbers)}",
                    f"LH:{sum(own.get(name, {}).get(n, 0) > 0 for n in numbers)}",
                    "end_of_record",
                ]
            )
        relative = output.rstrip("/") + "/" + shard + ".lcov"
        contents[relative] = "\n".join(text) + "\n"
        outputs.append(
            {
                "id": shard,
                "language": "flutter",
                "format": "lcov",
                "path": relative,
                "path_base": ".",
                "zero_padded_points": padding,
                "hit_points": hit_count,
            }
        )
    destination.mkdir(parents=True)
    for relative, content in contents.items():
        repo_path(root, relative, must_exist=False).write_text(
            content, encoding="utf-8", newline="\n"
        )
    for record in outputs:
        record["sha256"] = digest(repo_path(root, record["path"]))
    result: dict[str, object] = {
        "schema_version": 1,
        "method": "frozen-vm-ddc-actual-line-union-independent-hits",
        "normalizer_sha256": digest(Path(__file__)),
        "source_hashes": sources,
        "inputs": proofs,
        "outputs": outputs,
        "gate_shards": [
            {
                key: value
                for key, value in record.items()
                if key in {"id", "language", "format", "path", "path_base", "sha256"}
            }
            for record in outputs
        ],
        "canonical_line_points": sum(map(len, denominators.values())),
        "branch_semantics": "line-only; branch-bearing inputs rejected",
    }
    write_json(destination / "provenance.json", result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--manifest", default="scripts/quality/coverage_manifest.json")
    parser.add_argument("--plan", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    normalize(
        args.root,
        read_json(repo_path(args.root, args.manifest)),
        read_json(repo_path(args.root, args.plan)),
        args.output_dir,
    )


if __name__ == "__main__":
    main()
