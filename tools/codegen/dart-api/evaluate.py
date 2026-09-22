"""Reproduce the rejected dart-dio prototype without modifying application sources."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    config = json.loads(Path(__file__).with_name("evaluation.json").read_text(encoding="utf-8"))
    if hashlib.sha256(args.jar.read_bytes()).hexdigest() != config["sha256"]:
        raise SystemExit("Generator digest mismatch")
    java = shutil.which("java")
    dart = shutil.which("dart")
    if java is None or dart is None:
        raise SystemExit("Java and pinned Dart must be installed")
    output = args.output.resolve()
    if output == root or root not in output.parents or "artifacts" not in output.parts:
        raise SystemExit("Prototype output must be a new directory under repository artifacts")
    if output.exists():
        raise SystemExit("Use a fresh output directory to preserve previous evidence")
    properties = ",".join(
        f"{key}={str(value).lower() if isinstance(value, bool) else value}"
        for key, value in config["properties"].items()
    )
    # Fixed argument arrays; JAR digest is verified before executing the local tool.
    subprocess.run(  # noqa: S603
        [
            java,
            "-jar",
            str(args.jar.resolve()),
            "generate",
            "-g",
            "dart-dio",
            "-i",
            str(root / "contracts/openapi.json"),
            "-o",
            str(output),
            "--additional-properties=" + properties,
            "--global-property=apiTests=false,modelTests=false,apiDocs=false,modelDocs=false",
        ],
        check=True,
    )
    sample = output / "lib/generated/api/model/message_args_value.dart"
    completed = subprocess.run(  # noqa: S603
        [dart, "format", "--output=none", str(sample)],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    reproduced = completed.returncode != 0 and "could not be parsed" in completed.stderr
    (output / "evaluation-result.json").write_text(
        json.dumps(
            {
                "generator": config["version"],
                "jar_sha256": config["sha256"],
                "dart_parser_exit": completed.returncode,
                "known_blocker_reproduced": reproduced,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    sys.stdout.write(
        "Rejected prototype reproduced.\n"
        if reproduced
        else "Prototype behavior changed; review the generator decision.\n"
    )
    return 0 if reproduced else 1


if __name__ == "__main__":
    raise SystemExit(main())
