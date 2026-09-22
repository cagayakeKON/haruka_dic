"""Strict JSON and repository path boundaries shared by offline quality gates."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import TypeGuard


class GateError(ValueError):
    """A missing, malformed, or noncompliant piece of acceptance evidence."""


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise GateError("duplicate_json_key")
        result[key] = value
    return result


def is_object(value: object) -> TypeGuard[dict[str, object]]:
    # Inputs are JSON-decoded or explicitly typed records, never arbitrary mappings.
    return isinstance(value, dict)


def is_array(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


def obj(value: object) -> dict[str, object]:
    if not is_object(value):
        raise GateError("expected_object")
    return value


def array(value: object) -> list[object]:
    if not is_array(value):
        raise GateError("expected_array")
    return value


def string(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise GateError("expected_nonempty_string")
    return value


def strings(value: object, *, empty: bool = False) -> list[str]:
    result = [string(item) for item in array(value)]
    if (not result and not empty) or len(result) != len(set(result)):
        raise GateError("empty_or_duplicate_string_list")
    return result


def integer(value: object, *, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise GateError("invalid_integer")
    return value


def fields(value: dict[str, object], required: set[str], optional: set[str] | None = None) -> None:
    if set(value) - required - (optional or set()) or required - set(value):
        raise GateError("unknown_or_missing_field")


def version(value: dict[str, object]) -> None:
    if type(value.get("schema_version")) is not int or value.get("schema_version") != 1:
        raise GateError("unsupported_schema_version")


def read_json(path: Path) -> dict[str, object]:
    try:
        if path.stat().st_size > 16 * 1024 * 1024:
            raise GateError("oversized_json")
        return obj(json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object))
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise GateError("missing_or_invalid_json") from error


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def safe_name(value: object) -> str:
    name = string(value)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}", name):
        raise GateError("invalid_identifier")
    return name


def repo_path(root: Path, value: object, *, must_exist: bool = True) -> Path:
    name = string(value).replace("\\", "/")
    if name.startswith("/") or ":" in name or ".." in name.split("/"):
        raise GateError("path_outside_repository")
    path = root / name
    if not path.resolve().is_relative_to(root.resolve()):
        raise GateError("path_outside_repository")
    if must_exist and not path.is_file():
        raise GateError("missing_repository_file")
    return path


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
