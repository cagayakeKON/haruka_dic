"""Run the B0 quality-checker slice with genuine collected test evidence."""

from __future__ import annotations

import argparse
import hashlib
import platform
import sys
from pathlib import Path
from uuid import uuid4

from scripts.quality.cases import load_manifest
from scripts.quality.common import GateError, digest, read_json, string, write_json
from scripts.quality.coverage import inventory
from scripts.quality.testdata import inspect
from scripts.quality.unittest_runner import execute


def source_fingerprint(root: Path) -> str:
    paths: set[Path] = {root / "tools/toolchain.json", root / "tools/codegen/manifest.json"}
    for directory, glob in (
        ("scripts/quality", "*.py"),
        ("scripts/quality", "*.json"),
        ("scripts/tests", "test_quality*.py"),
        ("testdata", "*"),
        ("tools/ci", "*"),
        ("backend/app", "*.py"),
        ("frontend/lib", "*.dart"),
    ):
        paths.update(
            path
            for path in (root / directory).rglob(glob)
            if path.is_file() and "__pycache__" not in path.parts
        )
    result = hashlib.sha256()
    for path in sorted(paths):
        result.update(path.relative_to(root).as_posix().encode())
        result.update(digest(path).encode())
    return result.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--commit", required=True)
    parser.add_argument(
        "--scope", choices=["B0-quality", "B0-pytest-adapter"], default="B0-quality"
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        sys.stderr.write("Refusing to overwrite an earlier evidence directory.\n")
        return 1
    try:
        toolchain_path = args.root / "tools/toolchain.json"
        toolchain = read_json(toolchain_path)
        if platform.python_version() != toolchain["python"]:
            raise GateError("python_version_does_not_match_toolchain")
        fingerprint = source_fingerprint(args.root)
        run_identity: dict[str, object] = {
            "commit": args.commit,
            "build_id": "B0-quality-" + platform.system().lower() + "-" + fingerprint[:20],
            "configuration": "test-offline",
            "toolchain_sha256": digest(toolchain_path),
            "run_id": uuid4().hex,
        }
        cases, scopes = load_manifest(args.root / "scripts/quality/required_cases.json", args.root)
        selected = [case for case in cases if case.case_id in scopes[args.scope]]
        write_json(args.output / "identity.json", run_identity)
        tests_passed = execute(selected, args.scope, run_identity, args.output)
        write_json(args.output / "testdata.json", inspect(args.root))
        sources = inventory(
            args.root, read_json(args.root / "scripts/quality/coverage_manifest.json")
        )
        write_json(
            args.output / "inventory.json",
            {
                "schema_version": 1,
                "scope": "source_inventory_only",
                "files": sources,
                "passed": True,
            },
        )
        if source_fingerprint(args.root) != fingerprint:
            raise GateError("source_changed_during_acceptance")
        write_json(
            args.output / "environment.json",
            {
                "python": platform.python_version(),
                "platform": platform.system(),
                "scope": args.scope,
                "full_b0_accepted": False,
                "coverage_thresholds_executed": False,
                "working_tree_fingerprint": fingerprint,
            },
        )
        sys.stdout.write(
            "B0 quality slice passed.\n" if tests_passed else "B0 quality slice failed.\n"
        )
        return 0 if tests_passed else 1
    except (GateError, OSError, SyntaxError, UnicodeError) as error:
        # Gate errors contain fixed codes or public source paths, never source bodies.
        sys.stderr.write("B0 quality slice rejected: " + string(str(error)) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
