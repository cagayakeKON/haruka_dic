"""Export test-only Python/Dart compatibility assets to an explicit directory."""

import argparse
import base64
import hashlib
from pathlib import Path

from tests.support.api_compatibility import compatibility_openapi, compatibility_samples

from app.contracts.export import canonical_json

DART_FIXTURE_TARGET = "frontend/test/support/generated/api_compatibility_samples.dart"


def validate_dart_output(target: Path) -> None:
    """Allow staging locations, but reject traversal and linked/nonregular destinations."""
    if target.name != Path(DART_FIXTURE_TARGET).name or ".." in target.parts:
        raise ValueError("Dart fixture must use the registered filename without traversal")
    for parent in target.absolute().parents:
        if parent.is_symlink() or parent.is_junction():
            raise ValueError("Dart fixture parents must not be links")
        if parent.exists() and not parent.is_dir():
            raise ValueError("Dart fixture parents must be directories")
    if target.is_symlink() or target.is_junction() or (target.exists() and not target.is_file()):
        raise ValueError("Dart fixture target must be a regular file")


def dart_fixture(content: str, source_digest: str) -> str:
    encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
    chunks = [encoded[index : index + 76] for index in range(0, len(encoded), 76)]
    literals = "\n".join(f"    '{chunk}'" for chunk in chunks)
    return (
        "// GENERATED test-only compatibility fixture. Do not edit.\n"
        f"// Source: samples.json; sha256:{source_digest}\n"
        "import 'dart:convert';\n\n"
        f"const String _apiCompatibilitySamplesBase64 =\n{literals};\n\n"
        "String get apiCompatibilitySamplesJson => "
        "utf8.decode(base64Decode(_apiCompatibilitySamplesBase64));\n"
    )


def export(output: Path, *, dart_output: Path | None = None) -> None:
    if dart_output is not None:
        validate_dart_output(dart_output)
    output.mkdir(parents=True, exist_ok=True)
    assets = {
        "openapi.json": compatibility_openapi(),
        "samples.json": compatibility_samples(),
    }
    hashes: dict[str, str] = {}
    samples_content = ""
    for name, value in assets.items():
        content = canonical_json(value)
        (output / name).write_text(content, encoding="utf-8", newline="\n")
        hashes[name] = hashlib.sha256(content.encode()).hexdigest()
        if name == "samples.json":
            samples_content = content
    manifest: dict[str, object] = {
        "schema_version": 1,
        "source": "backend/tests/support/api_compatibility.py",
        "generated_by": "python -m tools.export_compatibility --output <directory>",
        "test_only": True,
        "sha256": hashes,
    }
    if dart_output is not None:
        content = dart_fixture(samples_content, hashes["samples.json"])
        dart_output.parent.mkdir(parents=True, exist_ok=True)
        validate_dart_output(dart_output)
        dart_output.write_text(content, encoding="utf-8", newline="\n")
        manifest["dart_fixture"] = {
            "target": DART_FIXTURE_TARGET,
            "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
            "source": "samples.json",
            "source_sha256": hashes["samples.json"],
            "test_only": True,
        }
    (output / "manifest.json").write_text(
        canonical_json(manifest),
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--dart-output", type=Path, help="Optional registered test-only Dart fixture"
    )
    arguments = parser.parse_args()
    export(arguments.output, dart_output=arguments.dart_output)


if __name__ == "__main__":
    main()
