"""Export test-only Python/Dart compatibility assets to an explicit directory."""

import argparse
import hashlib
from pathlib import Path

from tests.support.api_compatibility import compatibility_openapi, compatibility_samples

from app.contracts.export import canonical_json


def export(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    assets = {
        "openapi.json": compatibility_openapi(),
        "samples.json": compatibility_samples(),
    }
    hashes: dict[str, str] = {}
    for name, value in assets.items():
        content = canonical_json(value)
        (output / name).write_text(content, encoding="utf-8", newline="\n")
        hashes[name] = hashlib.sha256(content.encode()).hexdigest()
    (output / "manifest.json").write_text(
        canonical_json(
            {
                "schema_version": 1,
                "source": "backend/tests/support/api_compatibility.py",
                "generated_by": "python -m tools.export_compatibility --output <directory>",
                "test_only": True,
                "sha256": hashes,
            }
        ),
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    export(parser.parse_args().output)


if __name__ == "__main__":
    main()
