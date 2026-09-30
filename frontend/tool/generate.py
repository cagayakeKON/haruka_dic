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
    "lib/generated/api_catalog.dart",
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
    allowed_templates = {
        "referenceMaterialRow": ("materialId", "client.reference.materials.row."),
        "referenceBlock": ("blockId", "client.reference.chapter.block."),
        "referenceCollectionRow": ("collectionId", "client.reference.collections.row."),
        "sessionRevoke": ("sessionId", "client.account.sessions.revoke."),
    }
    for key, value in json_object(registry["templates"]).items():
        expected = allowed_templates.get(key)
        if (
            not isinstance(value, str)
            or expected is None
            or key in identifiers
            or value != f"{expected[1]}{{{expected[0]}}}"
        ):
            raise ValueError(f"Unsupported UI identifier template: {key}")
        if value in values:
            raise ValueError(f"Duplicate UI identifier template: {value}")
        values.add(value)
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
    test_instance_pattern: str
    test_api_base_urls: dict[str, list[str]]
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
        test_instance_pattern=required_string(development["test_instance_pattern"]),
        test_api_base_urls={
            platform: string_list(urls)
            for platform, urls in json_object(development["test_api_base_urls"]).items()
        },
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


def validate_reviewed_schemas(schemas: dict[str, object], digest: object) -> None:
    actual_digest = hashlib.sha256(
        json.dumps(schemas, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    if digest != actual_digest:
        raise ValueError("API schemas changed: review handwritten DTOs and compatibility tests")


def validate_error_catalog(
    catalog: dict[str, object], locales: dict[str, object]
) -> tuple[list[str], list[str]]:
    error_codes: list[str] = []
    translations: list[str] = []
    for category in ("errors", "field_errors"):
        records = catalog[category]
        if not is_json_list(records):
            raise ValueError("Expected catalog entries")
        for item in records:
            record = json_object(item)
            code = required_string(record["code"])
            key = "api" + "".join(part.title() for part in code.lower().split("_"))
            required_string(locales.get(key))
            if json_object(record["message_args"]):
                raise ValueError("Parameterized errors require reviewed Dart adapters")
            metadata = json_object(locales.get("@" + key, {}))
            if metadata.get("placeholders", {}) != {}:
                raise ValueError("Unexpected ARB error placeholders")
            if category == "errors":
                error_codes.append(code)
            translations.append(f"    {json.dumps(code)} => strings.{key},")
    return error_codes, translations


def generate_ui_identifiers(directory: Path) -> None:
    id_registry = read_registry(ROOT / "config/ui_test_ids.json")
    ids = validate_ids(id_registry)
    declarations = "\n".join(
        f"  static const {key} = {json.dumps(value)};" for key, value in sorted(ids.items())
    )
    templates = json_object(id_registry["templates"])
    parameters = {
        "referenceMaterialRow": "materialId",
        "referenceBlock": "blockId",
        "referenceCollectionRow": "collectionId",
        "sessionRevoke": "sessionId",
    }
    for key, value in sorted(templates.items()):
        if not isinstance(value, str):
            raise ValueError("UI identifier templates must be strings")
        parameter = parameters[key]
        prefix = value.split("{")[0]
        declarations += (
            f"\n  static String {key}(String {parameter}) {{\n"
            f"    if (!RegExp(r'^[0-9a-fA-F]{{8}}-(?:[0-9a-fA-F]{{4}}-){{3}}[0-9a-fA-F]{{12}}$')"
            f".hasMatch({parameter})) {{\n"
            f"      throw ArgumentError.value({parameter}, {json.dumps(parameter)}, 'Expected UUID');\n"
            f"    }}\n"
            f"    return {json.dumps(prefix)} + {parameter}.toLowerCase();\n"
            f"  }}"
        )
    emit(
        directory,
        OUTPUTS[0],
        header("config/ui_test_ids.json")
        + "abstract final class UiTestIds {\n"
        + declarations
        + "\n}\n",
    )


def generate_error_catalog(directory: Path) -> None:
    catalog = json_object(json.loads((ROOT.parent / "contracts/errors.json").read_text("utf-8")))
    locales = json_object(json.loads((ROOT / "lib/l10n/app_zh.arb").read_text("utf-8")))
    error_codes, translations = validate_error_catalog(catalog, locales)
    digest = hashlib.sha256(json.dumps(catalog, sort_keys=True).encode()).hexdigest()
    emit(
        directory,
        OUTPUTS[5],
        f"// GENERATED from contracts/errors.json; sha256:{digest}. Do not edit.\n"
        "import 'l10n/app_localizations.dart';\n"
        "abstract final class ApiCatalog {\n"
        + "  static const errorCodes = <String>{"
        + ", ".join(json.dumps(code) for code in sorted(error_codes))
        + "};\n"
        + "  static String message(AppLocalizations strings, String code) => switch (code) {\n"
        + "\n".join(translations)
        + "\n    _ => strings.apiUnknownError,\n  };\n}\n",
    )


def generate_localizations(directory: Path) -> None:
    # Flutter reads l10n.yaml from cwd, so use an isolated mini project to keep --check read-only.
    for source in ("pubspec.yaml", "l10n.yaml", "lib/l10n/app_zh.arb"):
        emit(directory, source, (ROOT / source).read_text(encoding="utf-8"))
    emit(directory, "analysis_options.yaml", "formatter:\n  page_width: 100\n")
    run(["flutter", "gen-l10n"], directory)


def generate_build_targets(directory: Path) -> None:
    targets = build_targets(read_registry(ROOT / "config/build_targets.json"))
    emit(
        directory,
        OUTPUTS[1],
        header("config/build_targets.json")
        + f"""abstract final class BuildTargets {{
  static const developmentInstanceId = {json.dumps(targets.development_instance_id)};
  static const developmentApiBaseUrl = {json.dumps(targets.development_api_base_url)};
  static const developmentApiBaseUrls = <String>{json.dumps(targets.development_api_base_urls)};
  static const testInstancePattern = r{json.dumps(targets.test_instance_pattern)};
  static const testApiBaseUrls = <String, List<String>>{json.dumps(targets.test_api_base_urls)};
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


def generate(directory: Path) -> None:
    reviewed = json_object(
        json.loads((ROOT.parent / "tools/codegen/dart-api/transition.json").read_text("utf-8"))
    )
    openapi = json_object(json.loads((ROOT.parent / "contracts/openapi.json").read_text("utf-8")))
    schemas = json_object(json_object(openapi["components"])["schemas"])
    validate_reviewed_schemas(schemas, reviewed.get("reviewed_schemas_sha256"))
    generate_error_catalog(directory)
    generate_ui_identifiers(directory)

    generate_build_targets(directory)

    generate_localizations(directory)
    run(["dart", "format", "lib/generated"], directory)


def generate_selection(directory: Path, only: str | None) -> None:
    if only is None:
        generate(directory)
        return
    if only == "ui-identifiers":
        generate_ui_identifiers(directory)
        emit(directory, "analysis_options.yaml", "formatter:\n  page_width: 100\n")
    elif only == "build-targets":
        generate_build_targets(directory)
        emit(directory, "analysis_options.yaml", "formatter:\n  page_width: 100\n")
    elif only == "client-resources":
        generate_error_catalog(directory)
        generate_localizations(directory)
    else:
        raise ValueError("Unsupported independent generation selection")
    run(["dart", "format", "lib/generated"], directory)


class Arguments(argparse.Namespace):
    write: bool = False
    check: bool = False
    output_dir: Path | None = None
    only: str | None = None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument(
        "--output-dir", type=Path, help="Export the generated outputs to this directory"
    )
    parser.add_argument(
        "--only",
        choices=("ui-identifiers", "client-resources", "build-targets"),
        help="Generate independent UI identifiers or error/localization resources; API schema review gate remains unchanged",
    )
    arguments = parser.parse_args(namespace=Arguments())
    with tempfile.TemporaryDirectory(prefix="haruka-frontend-codegen-") as temporary:
        staging = Path(temporary)
        generate_selection(staging, arguments.only)
        target = arguments.output_dir.resolve() if arguments.output_dir else ROOT
        failures: list[str] = []
        selected_outputs = (
            OUTPUTS
            if arguments.only is None
            else (OUTPUTS[0],)
            if arguments.only == "ui-identifiers"
            else (OUTPUTS[1], OUTPUTS[4])
            if arguments.only == "build-targets"
            else (OUTPUTS[2], OUTPUTS[3], OUTPUTS[5])
        )
        for relative in selected_outputs:
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
