"""Narrow typed JSON boundary shared by the standalone container tooling."""

import json
from pathlib import Path
from typing import TypeGuard


def is_object(value: object) -> TypeGuard[dict[str, object]]:
    return isinstance(value, dict)


def is_array(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


def obj(value: object) -> dict[str, object]:
    if not is_object(value):
        raise ValueError("JSON object required")
    return value


def objects(value: object) -> list[dict[str, object]]:
    if not is_array(value):
        raise ValueError("JSON object list required")
    return [obj(item) for item in value]


def string(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError("Nonempty JSON string required")
    return value


def strings(value: object) -> list[str]:
    if not is_array(value):
        raise ValueError("Nonempty unique JSON string list required")
    result = [string(item) for item in value]
    if not result or len(set(result)) != len(result):
        raise ValueError("Nonempty unique JSON string list required")
    return result


def unique(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON object key")
        result[key] = value
    return result


def read_object(path: Path) -> dict[str, object]:
    return obj(json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique))
