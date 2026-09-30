"""Account create accepts no password and no owner."""

import pytest
from pydantic import ValidationError

from app.schemas.user_governance import AccountCreate, SessionRevocation

pytestmark = pytest.mark.unit


def test_account_create_rejects_password_and_owner() -> None:
    with pytest.raises(ValidationError):
        AccountCreate.model_validate(
            {"email": "desk@example.test", "password": "synthetic-password-2026"}
        )
    with pytest.raises(ValidationError):
        AccountCreate.model_validate(
            {"email": "desk@example.test", "user_id": "00000000-0000-4000-8000-000000000001"}
        )


def test_session_revocation_chooses_one_target() -> None:
    with pytest.raises(ValidationError):
        SessionRevocation.model_validate(
            {"expected_revision": 1, "all_sessions": True, "audience": "client"}
        )
