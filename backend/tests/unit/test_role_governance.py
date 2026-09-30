"""Role creation rejects grant fields that belong on the assignment route."""

import pytest
from pydantic import ValidationError

from app.schemas.role_governance import RoleCreate

pytestmark = pytest.mark.unit


def test_role_create_rejects_embedded_grants() -> None:
    with pytest.raises(ValidationError):
        RoleCreate.model_validate({"code": "desk", "name": "Desk", "grants": [], "protected": True})
