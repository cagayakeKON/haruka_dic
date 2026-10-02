"""Explicit installed-SDK compatibility proof; never mutates SDK bytes."""

import ast
import os
from pathlib import Path

import pytest
from tools.coverage.adapter import SDK_SHA256, patched_source
from tools.coverage.runner import digest


def test_installed_sdk_exact_signatures_and_readonly(tmp_path: Path) -> None:
    selected = os.environ.get("HARUKA_COVERAGE_READONLY_SDK")
    if selected is None:
        pytest.skip("Explicit read-only SDK compatibility shard not selected")
    source = Path(selected) / "packages/flutter_tools/lib/src/test/flutter_web_platform.dart"
    original = source.read_bytes()
    if digest(original) != SDK_SHA256:
        pytest.fail("Unexpected original SDK fingerprint")
    helper = tmp_path / "capture.dart"
    patched = patched_source(original, helper)
    if patched == original or source.read_bytes() != original:
        pytest.fail("SDK patch did not transform in memory or mutated source")
    # Independent reviewed replacement list is evidence-only, not runtime dependency.
    root = Path(__file__).resolve().parents[3]
    tree = ast.parse((root / "artifacts/stage1/run_web_widget_current.py").read_text())
    assignment = next(
        node
        for node in tree.body
        if isinstance(node, ast.Assign)
        and isinstance(node.targets[0], ast.Name)
        and node.targets[0].id == "replacements"
    )
    expected = original.decode().replace("\r\n", "\n")
    if not isinstance(assignment.value, ast.List):
        pytest.fail("Reviewed replacements must be an explicit list")
    for pair in assignment.value.elts:
        if not isinstance(pair, ast.Tuple):
            pytest.fail("Invalid reviewed replacement evidence")
        old = ast.literal_eval(pair.elts[0])
        # Gold second field has one helper URI expression; match adapter via import.
        if old == "import 'dart:typed_data';":
            new = old + "\nimport '" + helper.as_uri() + "';"
        else:
            new = ast.literal_eval(pair.elts[1])
        if expected.count(old) != 1:
            pytest.fail("Reviewed installed SDK signature not unique")
        expected = expected.replace(old, new)
    # The subsequent defect fix adds one explicit pending-capture barrier.
    expected = expected.replace(
        "    _ownedCoverage?.event('suite-load', suiteID);",
        "    await _ownedCoverage?.pending;\n    _ownedCoverage?.event('suite-load', suiteID);",
    )
    if patched != expected.encode():
        pytest.fail("Formal adapter differs from reviewed SDK transformation")
