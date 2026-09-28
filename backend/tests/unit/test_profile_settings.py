"""Profile field masks reject unknown, unbounded and cross-field values without a database."""

from datetime import UTC, datetime
from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.schemas.profile import ProfileUpdate, SettingsUpdate, StudyProfileUpdate
from app.schemas.responses import ApiModel
from app.services.profile_settings import age_band

pytestmark = pytest.mark.unit


def test_age_band_is_coarse_and_omits_the_integer_age() -> None:
    today = datetime(2026, 9, 28, tzinfo=UTC)
    assert age_band(None, today=today) is None
    assert age_band(2010, today=today) == "under_18"
    assert age_band(2000, today=today) == "18_29"
    assert age_band(1990, today=today) == "30_49"
    assert age_band(1970, today=today) == "50_plus"
    assert age_band(2027, today=today) is None


def test_profile_mask_rejects_email_age_and_an_empty_update() -> None:
    with pytest.raises(ValidationError):
        ProfileUpdate.model_validate(
            {"expected_revision": 1, "fields": {"email": "person@example.com"}}
        )
    with pytest.raises(ValidationError):
        ProfileUpdate.model_validate({"expected_revision": 1, "fields": {"age": 20}})
    with pytest.raises(ValidationError):
        ProfileUpdate.model_validate({"expected_revision": 1, "fields": {}})
    saved = ProfileUpdate.model_validate(
        {
            "expected_revision": 1,
            "fields": {"display_name": "  遥  ", "use_optional_demographics_for_ai": False},
        }
    )
    assert saved.fields.display_name == "遥"
    assert saved.fields.use_optional_demographics_for_ai is False


def test_study_mask_rejects_a_target_outside_the_published_pair() -> None:
    with pytest.raises(ValidationError):
        StudyProfileUpdate.model_validate(
            {
                "expected_revision": 1,
                "fields": {
                    "target_languages": [{"language_tag": "ko", "self_assessed_level": "beginner"}]
                },
            }
        )
    saved = StudyProfileUpdate.model_validate(
        {
            "expected_revision": 2,
            "fields": {
                "native_languages": ["zh-Hans"],
                "explanation_language": "zh-Hans",
                "target_languages": [
                    {
                        "language_tag": "ja",
                        "self_assessed_level": "beginner",
                        "learning_goals": ["reading"],
                    }
                ],
                "active_target_language": "ja",
            },
        }
    )
    assert saved.fields.active_target_language == "ja"


def test_settings_mask_keeps_budget_and_speed_inside_the_published_range() -> None:
    with pytest.raises(ValidationError):
        SettingsUpdate.model_validate(
            {"expected_revision": 1, "fields": {"query_context_budget_tokens": 999}}
        )
    with pytest.raises(ValidationError):
        SettingsUpdate.model_validate(
            {"expected_revision": 1, "fields": {"query_context_budget_tokens": 5000.0}}
        )
    with pytest.raises(ValidationError):
        SettingsUpdate.model_validate(
            {"expected_revision": 1, "fields": {"playback_speed": "1.60"}}
        )
    with pytest.raises(ValidationError):
        SettingsUpdate.model_validate(
            {"expected_revision": 1, "fields": {"model_provider": "gemini"}}
        )
    saved = SettingsUpdate.model_validate(
        {
            "expected_revision": 3,
            "fields": {
                "timezone": "Asia/Tokyo",
                "query_context_budget_tokens": 5000,
                "playback_speed": "0.70",
                "theme_mode": "dark",
            },
        }
    )
    assert saved.fields.timezone == "Asia/Tokyo"
    assert saved.fields.query_context_budget_tokens == 5000
    assert saved.fields.playback_speed == Decimal("0.70")


@pytest.mark.parametrize("revision", [True, "1", 1.0])
@pytest.mark.parametrize("schema", [ProfileUpdate, StudyProfileUpdate, SettingsUpdate])
def test_expected_revision_requires_an_exact_integer(
    schema: type[ApiModel], revision: object
) -> None:
    field = (
        "display_name"
        if schema is ProfileUpdate
        else ("native_languages" if schema is StudyProfileUpdate else "timezone")
    )
    value: object = (
        "learner"
        if schema is ProfileUpdate
        else ([] if schema is StudyProfileUpdate else "Asia/Tokyo")
    )
    with pytest.raises(ValidationError):
        schema.model_validate({"expected_revision": revision, "fields": {field: value}})


@pytest.mark.parametrize("value", ["1e100", "1e-100000", "NaN", "Infinity"])
def test_extreme_decimal_preferences_are_validation_errors(value: str) -> None:
    with pytest.raises(ValidationError):
        SettingsUpdate.model_validate(
            {"expected_revision": 1, "fields": {"reading_font_size": value}}
        )
