"""The Dart fixture export is validated Python data and never a production endpoint."""

import pytest
from pydantic import ValidationError

from app.main import create_app
from app.schemas.responses import PageResponse, SuccessResponse
from tests.support.api_compatibility import (
    CompatibilityRead,
    compatibility_openapi,
    compatibility_samples,
)

pytestmark = pytest.mark.contract


def test_samples_preserve_numeric_and_optional_protocol_semantics() -> None:
    samples = compatibility_samples()
    missing = SuccessResponse[CompatibilityRead].model_validate(samples["success_missing"])
    null = SuccessResponse[CompatibilityRead].model_validate(samples["success_null"])
    value = SuccessResponse[CompatibilityRead].model_validate(samples["success_value"])
    assert "nullable_optional" not in missing.data.model_fields_set
    assert "nullable_optional" in null.data.model_fields_set
    assert value.data.nullable_optional == "present"
    assert str(missing.data.exact_amount) == "12345678901234567890.123456789"
    assert len(PageResponse[CompatibilityRead].model_validate(samples["page"]).data) == 2
    with pytest.raises(ValidationError):
        CompatibilityRead.model_validate(samples["unknown_enum"])
    assert compatibility_openapi()["paths"]
    assert all(
        not path.startswith("/samples/") for path in create_app(schema_only=True).openapi()["paths"]
    )
