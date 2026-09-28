"""Owner profile, study-profile and settings projections.

Each endpoint carries only its field group. Optional demographics stay on the
owner profile and are not copied into a model request by this contract.
"""

from datetime import UTC, datetime
from decimal import Decimal
from typing import Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones

from pydantic import Field, field_validator, model_validator

from app.schemas.responses import ApiModel
from app.schemas.scalars import CanonicalDecimal

GenderCode = Literal[
    "unspecified", "female", "male", "non_binary", "self_described", "prefer_not_to_say"
]
LearningLanguage = Literal["ja", "en"]
ExplanationLanguage = Literal["zh-Hans", "ja", "en"]
NativeLanguage = Literal["zh-Hans", "zh-Hant", "ja", "en", "ko"]
LearningLevel = Literal["unknown", "beginner", "elementary", "intermediate", "advanced"]
LearningGoal = Literal[
    "reading", "textbook", "exam", "listening", "speaking", "writing", "vocabulary", "grammar"
]
ThemeMode = Literal["system", "light", "dark"]
ReduceMotion = Literal["system", "on"]
ReadingFont = Literal["serif", "sans"]
ReadingTheme = Literal["light", "dark", "sepia"]
AgeBand = Literal["under_18", "18_29", "30_49", "50_plus"]
_TIMEZONES = available_timezones()


def _exact_int(value: object) -> int:
    if type(value) is not int:
        raise ValueError("Expected an integer")
    return value


class ProfileCompleteness(ApiModel):
    display_name: bool
    explanation_language: bool
    target_language: bool
    timezone: bool


class ProfileRead(ApiModel):
    revision: int = Field(ge=1)
    display_name: str | None = None
    birth_year: int | None = Field(default=None, ge=1900)
    age_band: AgeBand | None = None
    gender_code: GenderCode | None = None
    gender_self_description: str | None = Field(default=None, max_length=200)
    use_optional_demographics_for_ai: bool
    avatar_asset_id: UUID | None = None
    avatar_revision: int = Field(ge=0)
    profile_completeness: ProfileCompleteness


class ProfileFields(ApiModel):
    display_name: str | None = Field(default=None, max_length=100)
    birth_year: int | None = Field(default=None, ge=1900)
    gender_code: GenderCode | None = None
    gender_self_description: str | None = Field(default=None, max_length=200)
    use_optional_demographics_for_ai: bool | None = None

    @field_validator("birth_year")
    @classmethod
    def reject_future_birth_year(cls, value: int | None) -> int | None:
        if value is not None and value > datetime.now(UTC).year:
            raise ValueError("birth year is in the future")
        return value

    @field_validator("display_name")
    @classmethod
    def clean_display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            return None
        if any(ord(char) < 32 for char in cleaned):
            raise ValueError("display name contains unsupported characters")
        return cleaned

    @field_validator("gender_self_description")
    @classmethod
    def clean_description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None

    @model_validator(mode="after")
    def require_mask(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("field mask is empty")
        if (
            "gender_code" in self.model_fields_set
            and self.gender_code != "self_described"
            and self.gender_self_description is not None
        ):
            raise ValueError("gender description requires self_described")
        return self


class ProfileUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    fields: ProfileFields

    @field_validator("expected_revision", mode="before")
    @classmethod
    def exact_revision(cls, value: object) -> int:
        return _exact_int(value)


class TargetLanguageRead(ApiModel):
    language_tag: LearningLanguage
    self_assessed_level: LearningLevel
    learning_goals: list[LearningGoal]


def _empty_goals() -> list[LearningGoal]:
    return []


class TargetLanguageInput(ApiModel):
    language_tag: LearningLanguage
    self_assessed_level: LearningLevel = "unknown"
    learning_goals: list[LearningGoal] = Field(default_factory=_empty_goals)

    @model_validator(mode="after")
    def unique_goals(self) -> Self:
        if (
            len(set(self.learning_goals)) != len(self.learning_goals)
            or len(self.learning_goals) > 8
        ):
            raise ValueError("learning goals must be unique and bounded")
        return self


class StudyProfileRead(ApiModel):
    revision: int = Field(ge=1)
    native_languages: list[NativeLanguage]
    explanation_language: ExplanationLanguage | None = None
    active_target_language: LearningLanguage | None = None
    target_languages: list[TargetLanguageRead]


class StudyFields(ApiModel):
    native_languages: list[NativeLanguage] | None = None
    explanation_language: ExplanationLanguage | None = None
    active_target_language: LearningLanguage | None = None
    target_languages: list[TargetLanguageInput] | None = None

    @model_validator(mode="after")
    def require_mask(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("field mask is empty")
        natives = self.native_languages or []
        targets = self.target_languages or []
        if len(natives) != len(set(natives)) or len(natives) > 8:
            raise ValueError("native languages must be unique and bounded")
        tags = [item.language_tag for item in targets]
        if len(tags) != len(set(tags)) or len(tags) > 2:
            raise ValueError("target languages must be unique and bounded")
        if (
            "active_target_language" in self.model_fields_set
            and "target_languages" in self.model_fields_set
            and self.active_target_language is not None
            and self.active_target_language not in tags
        ):
            raise ValueError("active target language is not selected")
        return self


class StudyProfileUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    fields: StudyFields

    @field_validator("expected_revision", mode="before")
    @classmethod
    def exact_revision(cls, value: object) -> int:
        return _exact_int(value)


class SettingsRead(ApiModel):
    revision: int = Field(ge=1)
    ui_locale: Literal["zh-Hans"]
    timezone: str | None = None
    theme_mode: ThemeMode
    reduce_motion: ReduceMotion
    reading_font_family: ReadingFont | None = None
    reading_font_size: CanonicalDecimal | None = None
    reading_line_height: CanonicalDecimal | None = None
    reading_theme: ReadingTheme | None = None
    playback_speed: CanonicalDecimal
    query_context_budget_tokens: int = Field(ge=1000, le=64000)


class SettingsFields(ApiModel):
    timezone: str | None = None
    theme_mode: ThemeMode | None = None
    reduce_motion: ReduceMotion | None = None
    reading_font_family: ReadingFont | None = None
    reading_font_size: CanonicalDecimal | None = None
    reading_line_height: CanonicalDecimal | None = None
    reading_theme: ReadingTheme | None = None
    playback_speed: CanonicalDecimal | None = None
    query_context_budget_tokens: int | None = None

    @field_validator("query_context_budget_tokens", mode="before")
    @classmethod
    def exact_budget(cls, value: object) -> object:
        if value is None:
            return None
        return _exact_int(value)

    @field_validator("timezone")
    @classmethod
    def known_timezone(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if len(value) > 64 or any(char.isspace() for char in value):
            raise ValueError("timezone is not a published IANA identifier")
        try:
            ZoneInfo(value)
        except ZoneInfoNotFoundError:
            raise ValueError("timezone is not a published IANA identifier") from None
        if _TIMEZONES and value not in _TIMEZONES:
            raise ValueError("timezone is not a published IANA identifier")
        return value

    @model_validator(mode="after")
    def require_mask(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("field mask is empty")
        for name in (
            "theme_mode",
            "reduce_motion",
            "playback_speed",
            "query_context_budget_tokens",
        ):
            if name in self.model_fields_set and getattr(self, name) is None:
                raise ValueError("required preference cannot be cleared")
        if self.query_context_budget_tokens is not None and not (
            1000 <= self.query_context_budget_tokens <= 64000
        ):
            raise ValueError("query budget is outside the published range")
        _bounded_decimal(self.reading_font_size, Decimal("12"), Decimal("48"))
        _bounded_decimal(self.reading_line_height, Decimal("1.00"), Decimal("2.50"))
        _bounded_decimal(self.playback_speed, Decimal("0.70"), Decimal("1.50"))
        return self


class SettingsUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    fields: SettingsFields

    @field_validator("expected_revision", mode="before")
    @classmethod
    def exact_revision(cls, value: object) -> int:
        return _exact_int(value)


def _bounded_decimal(value: Decimal | None, lower: Decimal, upper: Decimal) -> None:
    if value is None:
        return
    hundredths = Decimal("0.01")
    if not value.is_finite() or not lower <= value <= upper:
        raise ValueError("decimal preference is outside the published range")
    if value != value.quantize(hundredths):
        raise ValueError("decimal preference is outside the published range")
