"""Owner profile, study profile and settings updates with independent revisions."""

from datetime import UTC, datetime

from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.identity_security import UserExtension, UserLanguage
from app.repositories import profile as repository
from app.schemas.profile import (
    ProfileCompleteness,
    ProfileRead,
    ProfileUpdate,
    SettingsRead,
    SettingsUpdate,
    StudyProfileRead,
    StudyProfileUpdate,
)
from app.services.auth_context import verify_scope_in_transaction

_READ = ("client.profile.read",)
_UPDATE = ("client.profile.read", "client.profile.update")


def age_band(birth_year: int | None, *, today: datetime) -> str | None:
    """Coarse band for the owner profile. This module never sends it to a model."""
    if birth_year is None or birth_year > today.year:
        return None
    age = today.year - birth_year
    if age < 18:
        return "under_18"
    if age < 30:
        return "18_29"
    if age < 50:
        return "30_49"
    return "50_plus"


def completeness(extension: UserExtension, rows: list[UserLanguage]) -> ProfileCompleteness:
    return ProfileCompleteness(
        display_name=extension.display_name is not None,
        explanation_language=extension.explanation_language is not None,
        target_language=any(row.language_kind == "target" for row in rows),
        timezone=extension.timezone is not None,
    )


async def read_profile(session: AsyncSession, scope: ScopeContext) -> ProfileRead:
    extension, rows = await _load(session, scope, _READ, lock=False)
    return _profile(extension, rows)


async def update_profile(
    session: AsyncSession, scope: ScopeContext, payload: ProfileUpdate
) -> ProfileRead:
    async with session.begin():
        extension, rows = await _load(session, scope, _UPDATE, lock=True)
        _match(extension.profile_revision, payload.expected_revision)
        fields = payload.fields
        assigned = fields.model_fields_set
        if "display_name" in assigned:
            extension.display_name = fields.display_name
        if "birth_year" in assigned:
            extension.birth_year = fields.birth_year
        if "gender_code" in assigned:
            extension.gender_code = fields.gender_code
        if extension.gender_code != "self_described":
            if "gender_self_description" in assigned and fields.gender_self_description is not None:
                raise AppError(ErrorCode.INPUT_INVALID)
            extension.gender_self_description = None
        elif "gender_self_description" in assigned:
            extension.gender_self_description = fields.gender_self_description
        if "use_optional_demographics_for_ai" in assigned:
            if fields.use_optional_demographics_for_ai is None:
                raise AppError(ErrorCode.INPUT_INVALID)
            extension.use_optional_demographics_for_ai = fields.use_optional_demographics_for_ai
        extension.profile_revision += 1
        return _profile(extension, rows)


async def read_study_profile(session: AsyncSession, scope: ScopeContext) -> StudyProfileRead:
    extension, rows = await _load(session, scope, _READ, lock=False)
    return _study(extension, rows)


async def update_study_profile(
    session: AsyncSession, scope: ScopeContext, payload: StudyProfileUpdate
) -> StudyProfileRead:
    async with session.begin():
        extension, _existing = await _load(session, scope, _UPDATE, lock=True)
        _match(extension.study_revision, payload.expected_revision)
        fields = payload.fields
        assigned = fields.model_fields_set
        if "native_languages" in assigned:
            natives = fields.native_languages or []
            await repository.replace_kind(
                session,
                scope.user_id,
                "native",
                [
                    UserLanguage(
                        user_id=scope.user_id,
                        language_kind="native",
                        language_tag=tag,
                        sort_order=index,
                        self_assessed_level=None,
                        learning_goals=[],
                    )
                    for index, tag in enumerate(natives)
                ],
            )
        if "target_languages" in assigned:
            targets = fields.target_languages or []
            await repository.replace_kind(
                session,
                scope.user_id,
                "target",
                [
                    UserLanguage(
                        user_id=scope.user_id,
                        language_kind="target",
                        language_tag=item.language_tag,
                        sort_order=index,
                        self_assessed_level=item.self_assessed_level,
                        learning_goals=[*item.learning_goals],
                    )
                    for index, item in enumerate(targets)
                ],
            )
            selected = {item.language_tag for item in targets}
            if (
                "active_target_language" not in assigned
                and extension.active_target_language not in selected
            ):
                extension.active_target_language = None
        if "explanation_language" in assigned:
            extension.explanation_language = fields.explanation_language
        if "active_target_language" in assigned:
            extension.active_target_language = fields.active_target_language
        rows = await repository.languages(session, scope.user_id)
        selected = {row.language_tag for row in rows if row.language_kind == "target"}
        if (
            extension.active_target_language is not None
            and extension.active_target_language not in selected
        ):
            raise AppError(ErrorCode.INPUT_INVALID)
        extension.study_revision += 1
        return _study(extension, rows)


async def read_settings(session: AsyncSession, scope: ScopeContext) -> SettingsRead:
    extension, _rows = await _load(session, scope, _READ, lock=False)
    return _settings(extension)


async def update_settings(
    session: AsyncSession, scope: ScopeContext, payload: SettingsUpdate
) -> SettingsRead:
    async with session.begin():
        extension, _rows = await _load(session, scope, _UPDATE, lock=True)
        _match(extension.settings_revision, payload.expected_revision)
        fields = payload.fields
        assigned = fields.model_fields_set
        if "timezone" in assigned:
            extension.timezone = fields.timezone
        if "theme_mode" in assigned and fields.theme_mode is not None:
            extension.theme_mode = fields.theme_mode
        if "reduce_motion" in assigned and fields.reduce_motion is not None:
            extension.reduce_motion = fields.reduce_motion
        if "reading_font_family" in assigned:
            extension.reading_font_family = fields.reading_font_family
        if "reading_font_size" in assigned:
            extension.reading_font_size = fields.reading_font_size
        if "reading_line_height" in assigned:
            extension.reading_line_height = fields.reading_line_height
        if "reading_theme" in assigned:
            extension.reading_theme = fields.reading_theme
        if "playback_speed" in assigned and fields.playback_speed is not None:
            extension.playback_speed = fields.playback_speed
        if (
            "query_context_budget_tokens" in assigned
            and fields.query_context_budget_tokens is not None
        ):
            extension.query_context_budget_tokens = fields.query_context_budget_tokens
        extension.settings_revision += 1
        return _settings(extension)


async def _load(
    session: AsyncSession, scope: ScopeContext, permissions: tuple[str, ...], *, lock: bool
) -> tuple[UserExtension, list[UserLanguage]]:
    await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience="client",
        transport=scope.transport,
        permissions=permissions,
        lock_user=lock,
    )
    extension = await repository.extension(session, scope.user_id, lock=lock)
    if extension is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return extension, await repository.languages(session, scope.user_id)


def _match(current: int, expected: int) -> None:
    if current != expected:
        raise AppError(ErrorCode.REVISION_CONFLICT, current_revision=current)


def _profile(extension: UserExtension, rows: list[UserLanguage]) -> ProfileRead:
    try:
        return ProfileRead.model_validate(
            {
                "revision": extension.profile_revision,
                "display_name": extension.display_name,
                "birth_year": extension.birth_year,
                "age_band": age_band(extension.birth_year, today=datetime.now(UTC)),
                "gender_code": extension.gender_code,
                "gender_self_description": extension.gender_self_description,
                "use_optional_demographics_for_ai": extension.use_optional_demographics_for_ai,
                "avatar_asset_id": extension.avatar_asset_id,
                "avatar_revision": extension.avatar_revision,
                "profile_completeness": completeness(extension, rows),
            }
        )
    except ValidationError:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


def _study(extension: UserExtension, rows: list[UserLanguage]) -> StudyProfileRead:
    try:
        return StudyProfileRead.model_validate(
            {
                "revision": extension.study_revision,
                "native_languages": [
                    row.language_tag for row in rows if row.language_kind == "native"
                ],
                "explanation_language": extension.explanation_language,
                "active_target_language": extension.active_target_language,
                "target_languages": [
                    {
                        "language_tag": row.language_tag,
                        "self_assessed_level": row.self_assessed_level,
                        "learning_goals": list(row.learning_goals),
                    }
                    for row in rows
                    if row.language_kind == "target"
                ],
            }
        )
    except ValidationError:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


def _settings(extension: UserExtension) -> SettingsRead:
    try:
        return SettingsRead.model_validate(
            {
                "revision": extension.settings_revision,
                "ui_locale": extension.ui_locale,
                "timezone": extension.timezone,
                "theme_mode": extension.theme_mode,
                "reduce_motion": extension.reduce_motion,
                "reading_font_family": extension.reading_font_family,
                "reading_font_size": extension.reading_font_size,
                "reading_line_height": extension.reading_line_height,
                "reading_theme": extension.reading_theme,
                "playback_speed": extension.playback_speed,
                "query_context_budget_tokens": extension.query_context_budget_tokens,
            }
        )
    except ValidationError:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
