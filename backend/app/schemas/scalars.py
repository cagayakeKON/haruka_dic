"""Exact scalar wire formats shared by response and request models."""

import re
from decimal import Decimal
from typing import Annotated

from pydantic import BeforeValidator, Field, PlainSerializer, WithJsonSchema

DECIMAL_INPUT_PATTERN = r"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"
DECIMAL_OUTPUT_PATTERN = r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"


def decimal_input(value: object) -> Decimal | str:
    """Accept exact Python Decimal or a decimal string, never JSON float/int coercion."""
    if isinstance(value, Decimal):
        return value
    if isinstance(value, str) and re.fullmatch(DECIMAL_INPUT_PATTERN, value):
        return value
    raise ValueError("Expected a finite decimal string")


def decimal_string(value: Decimal) -> str:
    return format(value, "f")


CanonicalDecimal = Annotated[
    Decimal,
    BeforeValidator(decimal_input),
    Field(allow_inf_nan=False),
    PlainSerializer(decimal_string, return_type=str, when_used="json"),
    WithJsonSchema({"type": "string", "pattern": DECIMAL_INPUT_PATTERN}, mode="validation"),
    WithJsonSchema({"type": "string", "pattern": DECIMAL_OUTPUT_PATTERN}, mode="serialization"),
]
