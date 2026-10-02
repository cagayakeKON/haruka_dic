"""Portable fixture export preserves canonical bytes and rejects unsafe destinations."""

import base64
import hashlib
import json
import re
from pathlib import Path
from unittest.mock import patch

import pytest
from tools.export_compatibility import DART_FIXTURE_TARGET, dart_fixture, export


def decode_dart(source: str) -> bytes:
    encoded = "".join(re.findall(r"^    '([A-Za-z0-9+/=]+)'", source, re.MULTILINE))
    return base64.b64decode(encoded, validate=True)


def test_optional_dart_export_matches_canonical_samples_and_deterministic_manifest(
    tmp_path: Path,
) -> None:
    first, second = tmp_path / "first", tmp_path / "second"
    target = tmp_path / "stage" / Path(DART_FIXTURE_TARGET).name
    export(first, dart_output=target)
    initial = target.read_bytes()
    manifest = json.loads((first / "manifest.json").read_text("utf-8"))
    assert decode_dart(initial.decode()) == (first / "samples.json").read_bytes()
    record = manifest["dart_fixture"]
    assert record == {
        "target": DART_FIXTURE_TARGET,
        "sha256": hashlib.sha256(initial).hexdigest(),
        "source": "samples.json",
        "source_sha256": manifest["sha256"]["samples.json"],
        "test_only": True,
    }
    assert (
        record["source_sha256"] == hashlib.sha256((first / "samples.json").read_bytes()).hexdigest()
    )
    assert str(tmp_path) not in (first / "manifest.json").read_text("utf-8")
    export(second, dart_output=target)
    assert target.read_bytes() == initial
    for name in ("openapi.json", "samples.json", "manifest.json"):
        assert (first / name).read_bytes() == (second / name).read_bytes()


def test_legacy_export_still_has_only_three_json_outputs_and_original_manifest(
    tmp_path: Path,
) -> None:
    export(tmp_path)
    assert {path.name for path in tmp_path.iterdir()} == {
        "openapi.json",
        "samples.json",
        "manifest.json",
    }
    manifest = json.loads((tmp_path / "manifest.json").read_text("utf-8"))
    assert set(manifest) == {"schema_version", "source", "generated_by", "test_only", "sha256"}
    assert set(manifest["sha256"]) == {"openapi.json", "samples.json"}


@pytest.mark.parametrize("failure", ["filename", "traversal", "parent-file", "target-directory"])
def test_bad_dart_destination_rejects_before_any_export_write(tmp_path: Path, failure: str) -> None:
    filename = Path(DART_FIXTURE_TARGET).name
    target = tmp_path / filename
    if failure == "filename":
        target = tmp_path / "production.dart"
    elif failure == "traversal":
        target = tmp_path / "child" / ".." / filename
    elif failure == "parent-file":
        parent = tmp_path / "regular-file"
        parent.write_text("keep")
        target = parent / filename
    else:
        target.mkdir()
    output = tmp_path / "json"
    with pytest.raises(ValueError):
        export(output, dart_output=target)
    assert not output.exists()
    if failure == "parent-file":
        assert (tmp_path / "regular-file").read_text() == "keep"


@pytest.mark.parametrize(
    "method,location",
    [("is_symlink", "parent"), ("is_junction", "parent"), ("is_symlink", "target")],
)
def test_link_metadata_rejects_without_overwriting_existing_fixture(
    tmp_path: Path, method: str, location: str
) -> None:
    target = tmp_path / Path(DART_FIXTURE_TARGET).name
    target.write_text("keep")
    flagged = target if location == "target" else tmp_path

    def linked(path: Path) -> bool:
        return path == flagged

    with patch.object(Path, method, new=linked), pytest.raises(ValueError):
        export(tmp_path / "json", dart_output=target)
    assert target.read_text() == "keep" and not (tmp_path / "json").exists()


def test_constant_encoding_preserves_quotes_interpolation_unicode_and_line_endings() -> None:
    original = "\r\n\"quoted\" 'single' \\ $interpolation 日本語 😀\n"
    rendered = dart_fixture(original, hashlib.sha256(original.encode()).hexdigest())
    assert decode_dart(rendered) == original.encode("utf-8")
    assert "dart:io" not in rendered and "apiCompatibilitySamplesJson" in rendered
    assert "$interpolation" not in rendered
