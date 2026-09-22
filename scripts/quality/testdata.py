"""Validate repository-owned B0 assets and nonexecuting preparation scenarios."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from scripts.quality.common import (
    GateError,
    array,
    digest,
    fields,
    integer,
    obj,
    read_json,
    repo_path,
    safe_name,
    string,
    strings,
    version,
    write_json,
)

ASSET_FIELDS = {
    "asset_id",
    "version",
    "path",
    "sha256",
    "media_type",
    "bytes",
    "languages",
    "source",
    "license",
    "purpose",
    "text_protocol",
}
SCENARIO_FIELDS = {
    "schema_version",
    "scenario_id",
    "scenario_version",
    "acceptance_refs",
    "setup_recipe",
    "asset_refs",
    "actors_profile",
    "recipe_params",
    "clock_profile",
    "provider_profile",
    "expected_aliases",
}


def validate_assets(root: Path) -> dict[str, dict[str, object]]:
    asset_root = root / "testdata/assets"
    manifest = read_json(asset_root / "manifest.json")
    version(manifest)
    fields(manifest, {"schema_version", "assets"})
    result: dict[str, dict[str, object]] = {}
    paths: set[str] = set()
    for raw in array(manifest["assets"]):
        item = obj(raw)
        fields(item, ASSET_FIELDS)
        asset_id = safe_name(item["asset_id"])
        if asset_id in result or integer(item["version"], minimum=1) != 1:
            raise GateError("duplicate_or_unsupported_asset_version")
        path = repo_path(asset_root, item["path"])
        relative = path.relative_to(asset_root).as_posix()
        if relative in paths or relative == "manifest.json":
            raise GateError("duplicate_asset_path")
        paths.add(relative)
        size = integer(item["bytes"], minimum=1)
        if size > 1024 * 1024 or path.stat().st_size != size:
            raise GateError("asset_size_mismatch_or_limit")
        if digest(path) != item["sha256"]:
            raise GateError("asset_digest_mismatch")
        if not set(strings(item["languages"])) <= {"en", "ja", "zh-Hans", "und"}:
            raise GateError("unsupported_asset_language")
        if (
            item["license"] != "CC0-1.0"
            or item["source"] != "Haruka contributors; synthetic original fixture"
        ):
            raise GateError("asset_provenance_not_registered")
        string(item["purpose"])
        media = string(item["media_type"])
        if media not in {"text/plain", "application/json"}:
            raise GateError("asset_media_not_in_b0_scope")
        if item["text_protocol"] != "canonical-text-v1":
            raise GateError("unsupported_text_protocol")
        content = path.read_text(encoding="utf-8")
        if b"\r" in path.read_bytes() or "\x00" in content:
            raise GateError("asset_text_not_canonical")
        if media == "application/json":
            read_json(path)
        result[asset_id] = item
    actual = {
        path.relative_to(asset_root).as_posix()
        for path in asset_root.rglob("*")
        if path.is_file() and path != asset_root / "manifest.json"
    }
    if not result or paths != actual:
        raise GateError("empty_or_unregistered_asset")
    return result


def validate_scenario(
    data: dict[str, object], assets: dict[str, dict[str, object]]
) -> dict[str, object]:
    """The B0 recipe reads immutable fixtures only; it cannot create business data."""
    version(data)
    fields(data, SCENARIO_FIELDS)
    safe_name(data["scenario_id"])
    if integer(data["scenario_version"], minimum=1) != 1:
        raise GateError("unsupported_scenario_version")
    if data["setup_recipe"] != "validate_static_assets" or data["actors_profile"] != "none":
        raise GateError("recipe_or_actors_not_in_b0_scope")
    if data["clock_profile"] != "none" or data["provider_profile"] != "blocked":
        raise GateError("scenario_must_not_enable_clock_or_provider")
    references = strings(data["acceptance_refs"])
    if any(not re.fullmatch(r"(?:SCF-B0-0[1-7]|TDS-0[12])", ref) for ref in references):
        raise GateError("scenario_acceptance_not_in_b0_scope")
    asset_refs = strings(data["asset_refs"])
    if set(asset_refs) - set(assets):
        raise GateError("unknown_asset_reference")
    parameters = obj(data["recipe_params"])
    fields(parameters, {"assets"})
    aliases = obj(parameters["assets"])
    if not aliases or any(not re.fullmatch(r"assets\.[a-z][a-z0-9_]*", alias) for alias in aliases):
        raise GateError("invalid_asset_alias")
    if {string(value) for value in aliases.values()} != set(asset_refs):
        raise GateError("asset_binding_mismatch")
    if set(strings(data["expected_aliases"])) != set(aliases):
        raise GateError("expected_alias_mismatch")
    # Outputs contain identifiers and hashes only, never file bodies or runtime credentials.
    return {
        "scenario_id": data["scenario_id"],
        "scenario_version": 1,
        "aliases": {
            alias: {"asset_id": value, "sha256": assets[string(value)]["sha256"]}
            for alias, value in aliases.items()
        },
    }


def inspect(root: Path) -> dict[str, object]:
    assets = validate_assets(root)
    scenario_root = root / "testdata/scenarios"
    paths = sorted(path for path in scenario_root.rglob("*") if path.is_file())
    if not paths or any(path.suffix != ".json" for path in paths):
        raise GateError("missing_or_non_json_scenario")
    scenarios = [validate_scenario(read_json(path), assets) for path in paths]
    if len({string(item["scenario_id"]) for item in scenarios}) != len(scenarios):
        raise GateError("duplicate_scenario_id")
    return {
        "schema_version": 1,
        "passed": True,
        "scope": "B0-static-assets-only",
        "asset_count": len(assets),
        "scenarios": scenarios,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        write_json(args.output, inspect(args.root))
        return 0
    except (GateError, OSError, UnicodeError) as error:
        sys.stderr.write(f"Test-data gate rejected input: {error}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
