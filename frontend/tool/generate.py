"""Regenerate owned frontend metadata and Flutter localizations without editing sources."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TypeGuard

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = (
    "lib/generated/ui_test_ids.dart",
    "lib/generated/build_targets.dart",
    "lib/generated/l10n/app_localizations.dart",
    "lib/generated/l10n/app_localizations_zh.dart",
    "windows/haruka_build_targets.cmake",
)


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def is_json_object(value: object) -> TypeGuard[dict[str, object]]:
    # This boundary only receives JSON-decoded values; the parser guarantees string keys.
    return isinstance(value, dict)


def json_object(value: object) -> dict[str, object]:
    if not is_json_object(value):
        raise ValueError("Expected a JSON object")
    return value


def is_json_list(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


def required_string(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError("Expected a non-empty JSON string")
    return value


def string_list(value: object) -> list[str]:
    if not is_json_list(value):
        raise ValueError("Expected a JSON string list")
    return [required_string(item) for item in value]


def read_registry(path: Path) -> dict[str, object]:
    parsed: object = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    document = json_object(parsed)
    if document.get("schema_version") != 1:
        raise ValueError("Registry must use schema_version 1")
    return document


def validate_ids(registry: dict[str, object]) -> dict[str, str]:
    if set(registry) != {"schema_version", "static", "templates"}:
        raise ValueError("Unexpected UI registry fields")
    if registry["templates"] != {}:
        raise ValueError("Dynamic templates are not implemented in this scaffold")
    values: set[str] = set()
    identifiers: dict[str, str] = {}
    for key, value in json_object(registry["static"]).items():
        if not re.fullmatch(r"[a-z][A-Za-z0-9]*", key):
            raise ValueError(f"Invalid Dart identifier: {key}")
        if not isinstance(value, str) or not re.fullmatch(
            r"(?:client|admin)(?:\.[a-z][a-z0-9_]*){3}", value
        ):
            raise ValueError(f"Invalid UI identifier: {key}")
        if value in values:
            raise ValueError(f"Duplicate UI identifier: {value}")
        values.add(value)
        identifiers[key] = value
    return identifiers


@dataclass(frozen=True)
class WindowsIdentity:
    application_id: str
    binary_name: str


@dataclass(frozen=True)
class PublicBuildTargets:
    development_instance_id: str
    development_api_base_url: str
    development_api_base_urls: list[str]
    display_names: dict[str, str]
    application_ids: dict[str, dict[str, str]]
    windows: dict[str, WindowsIdentity]


def build_targets(registry: dict[str, object]) -> PublicBuildTargets:
    """Validate untyped JSON fields once before generating Dart or host build code."""
    environments = json_object(registry["environments"])
    if set(environments) != {"dev", "production"}:
        raise ValueError("Expected dev and production environment definitions")
    development = json_object(environments["dev"])
    names = {
        name: required_string(json_object(value)["display_name"])
        for name, value in environments.items()
    }
    platforms = json_object(registry["platforms"])
    if set(platforms) != {"android", "windows", "web"}:
        raise ValueError("Expected Android, Windows and Web platform definitions")
    application_ids: dict[str, dict[str, str]] = {}
    windows: dict[str, WindowsIdentity] = {}
    for platform, platform_value in platforms.items():
        variants = json_object(platform_value)
        if set(variants) != {"dev", "production"}:
            raise ValueError("Expected both environments for each platform")
        if platform == "web":
            continue
        application_ids[platform] = {}
        for environment, variant_value in variants.items():
            variant = json_object(variant_value)
            application_id = required_string(variant["application_id"])
            application_ids[platform][environment] = application_id
            if platform == "windows":
                windows[environment] = WindowsIdentity(
                    application_id=application_id,
                    binary_name=required_string(variant["binary_name"]),
                )
    return PublicBuildTargets(
        development_instance_id=required_string(development["instance_id"]),
        development_api_base_url=required_string(development["api_base_url"]),
        development_api_base_urls=string_list(development["allowed_api_base_urls"]),
        display_names=names,
        application_ids=application_ids,
        windows=windows,
    )


def header(source: str) -> str:
    document = read_registry(ROOT / source)
    canonical = json.dumps(document, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(canonical).hexdigest()
    return f"// GENERATED from {source}; sha256:{digest}. Do not edit.\n"


def emit(directory: Path, relative: str, content: str) -> None:
    target = directory / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(content)


def run(command: list[str], directory: Path) -> None:
    resolved = shutil.which(command[0])
    if resolved is None:
        raise RuntimeError(f"Required executable is missing: {command[0]}")
    # Command names and arguments are fixed below, with no shell or registry-supplied commands.
    subprocess.run([resolved, *command[1:]], cwd=directory, check=True)  # noqa: S603


def generate(directory: Path) -> None:
    ids = validate_ids(read_registry(ROOT / "config/ui_test_ids.json"))
    declarations = "\n".join(
        f"  static const {key} = {json.dumps(value)};" for key, value in sorted(ids.items())
    )
    emit(
        directory,
        OUTPUTS[0],
        header("config/ui_test_ids.json")
        + "abstract final class UiTestIds {\n"
        + declarations
        + "\n}\n",
    )

    targets = build_targets(read_registry(ROOT / "config/build_targets.json"))
    emit(
        directory,
        OUTPUTS[1],
        header("config/build_targets.json")
        + f"""abstract final class BuildTargets {{
  static const developmentInstanceId = {json.dumps(targets.development_instance_id)};
  static const developmentApiBaseUrl = {json.dumps(targets.development_api_base_url)};
  static const developmentApiBaseUrls = <String>{json.dumps(targets.development_api_base_urls)};
  static const displayNames = <String, String>{json.dumps(targets.display_names)};
  static const applicationIds = <String, Map<String, String>>{json.dumps(targets.application_ids)};
}}
""",
    )
    production_define = base64.b64encode(b"HARUKA_ENV=production").decode()
    cmake = header("config/build_targets.json").replace("//", "#", 1)
    cmake += f'if(",${{DART_DEFINES}}," MATCHES ",{production_define},")\n'
    for environment, branch in (("production", ""), ("dev", "else()\n")):
        variant = targets.windows[environment]
        cmake += branch
        cmake += f'  set(BINARY_NAME "{variant.binary_name}")\n'
        cmake += f'  set(HARUKA_APP_ID "{variant.application_id}")\n'
        cmake += f'  set(HARUKA_APP_NAME "{targets.display_names[environment]}")\n'
    cmake += "endif()\n"
    emit(directory, OUTPUTS[4], cmake)

    # Flutter reads l10n.yaml from cwd, so use an isolated mini project to keep --check read-only.
    for source in ("pubspec.yaml", "l10n.yaml", "lib/l10n/app_zh.arb"):
        emit(directory, source, (ROOT / source).read_text(encoding="utf-8"))
    emit(directory, "analysis_options.yaml", "formatter:\n  page_width: 100\n")
    run(["flutter", "gen-l10n"], directory)
    run(["dart", "format", "lib/generated"], directory)


class Arguments(argparse.Namespace):
    write: bool = False
    check: bool = False
    output_dir: Path | None = None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument(
        "--output-dir", type=Path, help="Export the generated outputs to this directory"
    )
    arguments = parser.parse_args(namespace=Arguments())
    with tempfile.TemporaryDirectory(prefix="haruka-frontend-codegen-") as temporary:
        staging = Path(temporary)
        generate(staging)
        target = arguments.output_dir.resolve() if arguments.output_dir else ROOT
        failures: list[str] = []
        for relative in OUTPUTS:
            expected = (staging / relative).read_text(encoding="utf-8")
            destination = target / relative
            if arguments.write:
                emit(target, relative, expected)
            elif not destination.is_file() or destination.read_text(encoding="utf-8") != expected:
                failures.append(relative)
        unknown = set(
            p.relative_to(ROOT).as_posix()
            for p in (ROOT / "lib/generated").rglob("*")
            if p.is_file()
        ) - set(OUTPUTS)
        if unknown:
            failures.extend(f"unmanaged generated file: {path}" for path in sorted(unknown))
        if failures:
            raise SystemExit("Generated files differ: " + ", ".join(failures))
    message = (
        "Frontend generated outputs are current."
        if arguments.check
        else "Frontend generated outputs written."
    )
    sys.stdout.write(message + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
