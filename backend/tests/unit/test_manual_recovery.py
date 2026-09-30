"""Manual recovery decisions accept only a controlled verification method."""

from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.user_governance import ManualRecoveryDecision


def test_issue_requires_a_controlled_method() -> None:
    with pytest.raises(ValidationError):
        ManualRecoveryDecision(
            challenge_id=uuid4(),
            expected_revision=1,
            decision="issue",
        )


def test_profile_fields_are_not_verification_evidence() -> None:
    with pytest.raises(ValidationError):
        ManualRecoveryDecision.model_validate(
            {
                "challenge_id": str(uuid4()),
                "expected_revision": 1,
                "decision": "issue",
                "verification_method": "in_person",
                "display_name": "not evidence",
                "birth_year": 1990,
                "gender": "unspecified",
            }
        )


def test_reject_does_not_record_a_method() -> None:
    with pytest.raises(ValidationError):
        ManualRecoveryDecision(
            challenge_id=uuid4(),
            expected_revision=1,
            decision="reject",
            verification_method="known_channel",
        )
