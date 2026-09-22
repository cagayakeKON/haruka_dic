"""Decimal request validation, response serialization and OpenAPI agree exactly."""

import re
from decimal import Decimal

import pytest
from pydantic import BaseModel, TypeAdapter, ValidationError

from app.schemas.scalars import (
    DECIMAL_INPUT_PATTERN,
    DECIMAL_OUTPUT_PATTERN,
    CanonicalDecimal,
)

pytestmark = pytest.mark.contract


class Amount(BaseModel):
    amount: CanonicalDecimal


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        ("1E+3", "1000"),
        ("1E-7", "0.0000001"),
        ("-1E-7", "-0.0000001"),
        ("0E-10", "0.0000000000"),
        ("-0.00", "-0.00"),
        ("12345678901234567890.123456789", "12345678901234567890.123456789"),
    ],
)
def test_decimal_read_write_round_trip(source: str, expected: str) -> None:
    value = Amount.model_validate_json('{"amount":"' + source + '"}')
    assert value.amount == Decimal(source)
    assert value.model_dump(mode="json") == {"amount": expected}
    assert re.fullmatch(DECIMAL_OUTPUT_PATTERN, expected)
    assert Amount.model_validate(value.model_dump(mode="json")) == value
    assert Amount(amount=Decimal(source)).model_dump(mode="json") == {"amount": expected}


@pytest.mark.parametrize(
    "value",
    [
        "NaN",
        "Infinity",
        "-Infinity",
        "sNaN",
        "not-decimal",
        " 1.2 ",
        1.2,
        1000,
        True,
        Decimal("NaN"),
        Decimal("Infinity"),
        Decimal("-Infinity"),
    ],
)
def test_decimal_rejects_nonfinite_and_inexact_input(value: object) -> None:
    with pytest.raises(ValidationError):
        Amount.model_validate({"amount": value})


def test_decimal_schema_describes_distinct_input_and_output_forms() -> None:
    adapter = TypeAdapter[Decimal](CanonicalDecimal)
    assert adapter.json_schema(mode="validation") == {
        "type": "string",
        "pattern": DECIMAL_INPUT_PATTERN,
    }
    assert adapter.json_schema(mode="serialization") == {
        "type": "string",
        "pattern": DECIMAL_OUTPUT_PATTERN,
    }
