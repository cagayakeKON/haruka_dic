"""Inventory every handwritten source and gate weighted, merged coverage reports."""

from __future__ import annotations

import argparse
import ast
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from scripts.quality.cases import identity
from scripts.quality.common import (
    GateError,
    array,
    digest,
    fields,
    integer,
    obj,
    read_json,
    repo_path,
    string,
    strings,
    version,
    write_json,
)


@dataclass
class Hits:
    lines: set[int] = field(default_factory=set[int])
    hit_lines: set[int] = field(default_factory=set[int])
    branches: set[tuple[int, int]] = field(default_factory=set[tuple[int, int]])
    hit_branches: set[tuple[int, int]] = field(default_factory=set[tuple[int, int]])

    def merge(self, other: Hits) -> None:
        if self.lines != other.lines or self.branches != other.branches:
            raise GateError("conflicting_shard_denominators")
        self.hit_lines.update(other.hit_lines)
        self.hit_branches.update(other.hit_branches)


def declaration_only(path: Path, language: str) -> bool:
    content = path.read_text(encoding="utf-8")
    if language == "python":
        tree = ast.parse(content)
        return all(
            isinstance(node, ast.Expr)
            and isinstance(node.value, ast.Constant)
            and isinstance(node.value.value, str)
            for node in tree.body
        )
    content = re.sub(r"//[^\n]*|/\*.*?\*/", "", content, flags=re.DOTALL)
    # Only directives are exempt; constants/getters/classes are executable sources.
    content = re.sub(r"\b(?:export|import|library|part)\s+[^;]+;", "", content)
    return not content.strip()


def inventory(root: Path, manifest: dict[str, object]) -> dict[str, dict[str, object]]:
    version(manifest)
    fields(
        manifest,
        {
            "schema_version",
            "source_roots",
            "files",
            "core_groups",
            "thresholds",
            "required_shards",
            "generation_manifest",
        },
    )
    roots = obj(manifest["source_roots"])
    if set(roots) != {"python", "flutter"}:
        raise GateError("missing_source_language")
    actual: dict[str, str] = {}
    for language, relative in roots.items():
        directory = repo_path(root, relative, must_exist=False)
        extension = "*.py" if language == "python" else "*.dart"
        found = list(directory.rglob(extension))
        if not found:
            raise GateError("empty_source_root")
        for path in found:
            relative_path = path.relative_to(root).as_posix()
            repo_path(root, relative_path)
            actual[relative_path] = language
    raw_files = obj(manifest["files"])
    if set(actual) != set(raw_files):
        raise GateError(
            "unclassified_or_missing_source: " + ", ".join(sorted(set(actual) ^ set(raw_files)))
        )
    generation = read_json(repo_path(root, manifest["generation_manifest"]))
    generated: set[str] = set()
    for value in array(generation.get("frontend")):
        entry = obj(value)
        if not string(entry.get("generator")):
            raise GateError("missing_regeneration_command")
        for source in strings(entry.get("source")):
            repo_path(root, source)
        generated.update(strings(entry.get("output")))
    groups = obj(manifest["core_groups"])
    if not groups:
        raise GateError("empty_core_groups")
    files: dict[str, dict[str, object]] = {}
    for name, raw in raw_files.items():
        item = obj(raw)
        fields(item, {"language", "kind", "groups"}, {"reason"})
        if item["language"] != actual[name]:
            raise GateError("source_language_mismatch")
        kind = string(item["kind"])
        memberships = strings(item["groups"], empty=True)
        if kind not in {"core", "ordinary", "generated", "declaration"}:
            raise GateError("unknown_source_classification")
        if (kind == "core") != bool(memberships) or set(memberships) - set(groups):
            raise GateError("invalid_core_classification")
        if kind == "generated" and name not in generated:
            raise GateError("fake_generated_exclusion")
        if kind in {"generated", "declaration"}:
            string(item.get("reason"))
        if kind == "declaration" and not declaration_only(root / name, actual[name]):
            raise GateError("executable_declaration_exclusion")
        files[name] = item
    for name, value in groups.items():
        group = obj(value)
        fields(group, {"language", "threshold", "required_prefixes"})
        language = string(group["language"])
        members = {
            path for path, item in files.items() if name in strings(item["groups"], empty=True)
        }
        required = {
            path
            for path, item in files.items()
            if item["kind"] not in {"declaration", "generated"}
            and any(path.startswith(prefix) for prefix in strings(group["required_prefixes"]))
        }
        if not members or not required or required - members:
            raise GateError("empty_or_incomplete_core_group")
        if any(files[path]["language"] != language for path in members):
            raise GateError("mixed_core_language")
        if integer(group["threshold"], minimum=1) > 100:
            raise GateError("invalid_threshold")
    thresholds = obj(manifest["thresholds"])
    shards = obj(manifest["required_shards"])
    if set(thresholds) != set(roots) or set(shards) != set(roots):
        raise GateError("missing_language_threshold_or_shards")
    for language in roots:
        if integer(thresholds[language], minimum=1) > 100:
            raise GateError("invalid_threshold")
        strings(shards[language])
    return files


def normalize_path(
    root: Path,
    base: str,
    name: str,
    files: dict[str, dict[str, object]],
    reported_root: str | None = None,
) -> str:
    """Normalize separators/case, retaining a single canonical repository spelling."""
    name = name.replace("\\", "/")
    resolved = Path(name)
    prefix = (reported_root.replace("\\", "/").rstrip("/") + "/") if reported_root else None
    if prefix and name.casefold().startswith(prefix.casefold()):
        candidate = name[len(prefix) :]
    elif resolved.is_absolute():
        try:
            candidate = resolved.resolve().relative_to(root.resolve()).as_posix()
        except ValueError as error:
            raise GateError("coverage_path_outside_repository") from error
    else:
        candidate = (Path(base) / name).as_posix()
    path = repo_path(root, candidate, must_exist=False)
    candidate = path.relative_to(root).as_posix().casefold()
    matches = [entry for entry in files if entry.casefold() == candidate]
    if len(matches) != 1:
        raise GateError("unknown_or_ambiguous_coverage_path")
    return matches[0]


def branch_set(value: object) -> set[tuple[int, int]]:
    result: set[tuple[int, int]] = set()
    for raw in array(value):
        pair = array(raw)
        if len(pair) != 2:
            raise GateError("invalid_branch_pair")
        # Coverage.py uses negative destinations to denote function exits.
        start = integer(pair[0], minimum=1)
        end = pair[1]
        if not isinstance(end, int) or isinstance(end, bool) or end == 0:
            raise GateError("invalid_branch_destination")
        result.add((start, end))
    return result


def python_hits(path: Path) -> dict[str, Hits]:
    report = read_json(path)
    if obj(report.get("meta")).get("branch_coverage") is not True:
        raise GateError("python_branch_coverage_required")
    result: dict[str, Hits] = {}
    for name, raw in obj(report.get("files")).items():
        item = obj(raw)
        covered = {integer(line, minimum=1) for line in array(item.get("executed_lines"))}
        missed = {integer(line, minimum=1) for line in array(item.get("missing_lines"))}
        covered_branches = branch_set(item.get("executed_branches"))
        missed_branches = branch_set(item.get("missing_branches"))
        if covered & missed or covered_branches & missed_branches:
            raise GateError("conflicting_coverage_hits")
        result[name] = Hits(
            covered | missed, covered, covered_branches | missed_branches, covered_branches
        )
    if not result:
        raise GateError("empty_coverage_report")
    return result


def flutter_hits(path: Path) -> dict[str, Hits]:
    result: dict[str, Hits] = {}
    current: str | None = None
    hits = Hits()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise GateError("missing_or_invalid_lcov") from error
    for line in lines:
        if line.startswith("SF:"):
            if current is not None:
                raise GateError("unterminated_lcov_record")
            current, hits = line[3:], Hits()
        elif line.startswith("DA:"):
            if current is None:
                raise GateError("lcov_hits_outside_file")
            try:
                number_text, count_text, *_ = line[3:].split(",")
                number, count = int(number_text), int(count_text)
            except ValueError as error:
                raise GateError("invalid_lcov_line") from error
            if number < 1 or count < 0 or number in hits.lines:
                raise GateError("invalid_or_duplicate_lcov_line")
            hits.lines.add(number)
            if count:
                hits.hit_lines.add(number)
        elif line == "end_of_record":
            if current is None or current in result:
                raise GateError("duplicate_or_missing_lcov_file")
            result[current], current = hits, None
    if current is not None or not result:
        raise GateError("empty_or_incomplete_lcov")
    return result


def gate(
    root: Path,
    manifest: dict[str, object],
    evidence: dict[str, object],
    expected_identity: dict[str, object],
) -> dict[str, object]:
    files = inventory(root, manifest)
    version(evidence)
    fields(evidence, {"schema_version", "identity", "shards"})
    expected_identity = identity(expected_identity)
    if identity(evidence["identity"]) != expected_identity:
        raise GateError("coverage_identity_mismatch")
    required = {
        (language, name)
        for language, names in obj(manifest["required_shards"]).items()
        for name in strings(names)
    }
    seen: set[tuple[str, str]] = set()
    merged: dict[str, Hits] = {}
    for raw in array(evidence["shards"]):
        shard = obj(raw)
        fields(
            shard, {"id", "language", "format", "path", "sha256", "path_base"}, {"checkout_root"}
        )
        language, name = string(shard["language"]), string(shard["id"])
        token = (language, name)
        if token in seen or token not in required:
            raise GateError("duplicate_or_unknown_coverage_shard")
        seen.add(token)
        path = repo_path(root, shard["path"])
        if digest(path) != shard["sha256"]:
            raise GateError("coverage_report_digest_mismatch")
        base = string(shard["path_base"])
        repo_path(root, base, must_exist=False)
        reported_root = string(shard["checkout_root"]) if "checkout_root" in shard else None
        format_name = "coverage-json" if language == "python" else "lcov"
        if shard["format"] != format_name:
            raise GateError("wrong_coverage_format")
        parsed = python_hits(path) if language == "python" else flutter_hits(path)
        canonical_paths: set[str] = set()
        for raw_path, hits in parsed.items():
            key = normalize_path(root, base, raw_path, files, reported_root)
            if key in canonical_paths or files[key]["language"] != language:
                raise GateError("duplicate_or_wrong_language_coverage_file")
            canonical_paths.add(key)
            if files[key]["kind"] in {"declaration", "generated"}:
                continue
            if not hits.lines or hits.lines & {0}:
                raise GateError("zero_executable_denominator")
            if key in merged:
                merged[key].merge(hits)
            else:
                merged[key] = hits
    if seen != required:
        raise GateError("missing_coverage_shard")
    executable = {path for path, item in files.items() if item["kind"] in {"core", "ordinary"}}
    if executable - set(merged):
        raise GateError(
            "source_missing_from_coverage: " + ", ".join(sorted(executable - set(merged)))
        )
    summaries: list[dict[str, object]] = []
    thresholds = obj(manifest["thresholds"])
    selections = [
        (
            language,
            {path for path in executable if files[path]["language"] == language},
            integer(threshold),
        )
        for language, threshold in thresholds.items()
    ]
    for name, raw in obj(manifest["core_groups"]).items():
        group = obj(raw)
        selections.append(
            (
                name,
                {path for path in executable if name in strings(files[path]["groups"], empty=True)},
                integer(group["threshold"]),
            )
        )
    for name, paths, threshold in selections:
        numerator = sum(
            len(merged[path].hit_lines) + len(merged[path].hit_branches) for path in paths
        )
        denominator = sum(len(merged[path].lines) + len(merged[path].branches) for path in paths)
        passed = denominator > 0 and numerator * 100 >= threshold * denominator
        summaries.append(
            {
                "group": name,
                "numerator": numerator,
                "denominator": denominator,
                "threshold": threshold,
                "passed": passed,
            }
        )
    details = [
        {
            "path": path,
            "groups": files[path]["groups"],
            "numerator": len(hits.hit_lines) + len(hits.hit_branches),
            "denominator": len(hits.lines) + len(hits.branches),
            "missing_lines": sorted(hits.lines - hits.hit_lines),
            "missing_branches": sorted(hits.branches - hits.hit_branches),
        }
        for path, hits in sorted(merged.items())
    ]
    return {
        "schema_version": 1,
        "identity": expected_identity,
        "passed": all(item["passed"] for item in summaries),
        "groups": summaries,
        "files": details,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--manifest", type=Path, default=Path(__file__).with_name("coverage_manifest.json")
    )
    parser.add_argument("--inventory-only", action="store_true")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        manifest = read_json(args.manifest)
        if args.inventory_only:
            files = inventory(args.root, manifest)
            result: dict[str, object] = {
                "schema_version": 1,
                "passed": True,
                "scope": "source_inventory_only",
                "files": files,
            }
        else:
            if args.evidence is None or args.identity is None:
                raise GateError("evidence_and_identity_required")
            result = gate(args.root, manifest, read_json(args.evidence), read_json(args.identity))
        write_json(args.output, result)
        return 0 if result["passed"] else 1
    except (GateError, OSError, SyntaxError) as error:
        sys.stderr.write(f"Coverage gate rejected evidence: {error}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
