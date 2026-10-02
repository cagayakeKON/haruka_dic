"""Owner field masks and corrupt persistence fail safely at repository boundaries.

These service tests replace database I/O and authentication only. Real transaction
and owner-isolation evidence remains in the PostgreSQL integration suite.
"""

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.identity_security import UserExtension, UserLanguage
from app.schemas.profile import ProfileUpdate, SettingsUpdate, StudyProfileUpdate
from app.services import profile_settings as service

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


@pytest.fixture
def owner_scope() -> ScopeContext:
    return ScopeContext(
        user_id=uuid4(),
        session_id=uuid4(),
        audience="client",
        transport="web",
        user_authz_version=1,
        policy_authz_version=1,
        security_epoch=0,
        absolute_expires_at=datetime.now(UTC) + timedelta(hours=1),
    )


@pytest.fixture
def extension(owner_scope: ScopeContext) -> UserExtension:
    return UserExtension(
        user_id=owner_scope.user_id,
        profile_revision=4,
        study_revision=5,
        settings_revision=6,
        display_name="Existing",
        birth_year=2000,
        gender_code="self_described",
        gender_self_description="Existing description",
        use_optional_demographics_for_ai=False,
        avatar_asset_id=None,
        avatar_revision=0,
        active_target_language="ja",
        explanation_language="zh-Hans",
        timezone="Asia/Tokyo",
        ui_locale="zh-Hans",
        theme_mode="system",
        reduce_motion="system",
        reading_font_family="serif",
        reading_font_size=Decimal("18"),
        reading_line_height=Decimal("1.50"),
        reading_theme="sepia",
        playback_speed=Decimal("1.00"),
        query_context_budget_tokens=5000,
    )


@pytest.fixture
def session() -> AsyncSession:
    result = MagicMock(spec=AsyncSession)
    result.begin.return_value.__aenter__ = AsyncMock()
    result.begin.return_value.__aexit__ = AsyncMock(return_value=False)
    return result


@pytest.fixture
def repo(
    monkeypatch: pytest.MonkeyPatch, extension: UserExtension
) -> Iterator[dict[str, AsyncMock]]:
    mocks = {
        "verify": AsyncMock(),
        "extension": AsyncMock(return_value=extension),
        "languages": AsyncMock(return_value=[]),
        "replace_kind": AsyncMock(),
    }
    monkeypatch.setattr(service, "verify_scope_in_transaction", mocks["verify"])
    for name in ("extension", "languages", "replace_kind"):
        monkeypatch.setattr(service.repository, name, mocks[name])
    yield mocks


@pytest.mark.parametrize("operation", ["profile", "study", "settings"])
async def test_read_authorizes_owner_before_repository_access(
    operation: str,
    session: AsyncSession,
    owner_scope: ScopeContext,
    repo: dict[str, AsyncMock],
) -> None:
    repo["verify"].side_effect = AppError(ErrorCode.PERMISSION_DENIED)
    read = {
        "profile": service.read_profile,
        "study": service.read_study_profile,
        "settings": service.read_settings,
    }[operation]
    with pytest.raises(AppError) as error:
        await read(session, owner_scope)
    assert error.value.code == ErrorCode.PERMISSION_DENIED
    repo["extension"].assert_not_awaited()
    repo["languages"].assert_not_awaited()
    assert repo["verify"].await_args is not None
    assert repo["verify"].await_args.kwargs["user_id"] == owner_scope.user_id


@pytest.mark.parametrize("operation", ["profile", "study", "settings"])
async def test_missing_private_root_is_service_failure(
    operation: str,
    session: AsyncSession,
    owner_scope: ScopeContext,
    repo: dict[str, AsyncMock],
) -> None:
    repo["extension"].return_value = None
    read = {
        "profile": service.read_profile,
        "study": service.read_study_profile,
        "settings": service.read_settings,
    }[operation]
    with pytest.raises(AppError) as error:
        await read(session, owner_scope)
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    repo["languages"].assert_not_awaited()


async def test_profile_clear_is_masked_and_demographics_stay_owner_only(
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    result = await service.update_profile(
        session,
        owner_scope,
        ProfileUpdate.model_validate(
            {
                "expected_revision": 4,
                "fields": {"display_name": None, "gender_code": "female"},
            }
        ),
    )
    assert result.revision == 5 and result.display_name is None
    assert result.birth_year == 2000
    assert result.gender_self_description is None
    assert not result.use_optional_demographics_for_ai
    assert extension.study_revision == 5 and extension.settings_revision == 6
    repo["replace_kind"].assert_not_awaited()
    assert repo["verify"].await_args is not None
    assert repo["verify"].await_args.kwargs["lock_user"] is True


async def test_profile_updates_optional_demographics_only_after_explicit_opt_in(
    session: AsyncSession,
    owner_scope: ScopeContext,
    repo: dict[str, AsyncMock],
) -> None:
    result = await service.update_profile(
        session,
        owner_scope,
        ProfileUpdate.model_validate(
            {
                "expected_revision": 4,
                "fields": {
                    "birth_year": None,
                    "gender_self_description": " New ",
                    "use_optional_demographics_for_ai": True,
                },
            }
        ),
    )
    assert result.birth_year is None and result.age_band is None
    assert result.gender_self_description == "New"
    assert result.use_optional_demographics_for_ai


async def test_description_only_mask_cannot_bypass_persisted_gender(
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    extension.gender_code = "female"
    with pytest.raises(AppError) as error:
        await service.update_profile(
            session,
            owner_scope,
            ProfileUpdate.model_validate(
                {
                    "expected_revision": 4,
                    "fields": {"gender_self_description": "No"},
                }
            ),
        )
    assert error.value.code == ErrorCode.INPUT_INVALID
    assert extension.profile_revision == 4


async def test_demographics_opt_in_cannot_be_cleared(
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    with pytest.raises(AppError) as error:
        await service.update_profile(
            session,
            owner_scope,
            ProfileUpdate.model_validate(
                {
                    "expected_revision": 4,
                    "fields": {"use_optional_demographics_for_ai": None},
                }
            ),
        )
    assert error.value.code == ErrorCode.INPUT_INVALID
    assert extension.profile_revision == 4


async def test_study_replaces_only_selected_kinds_and_clears_removed_active_target(
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    repo["languages"].side_effect = [
        [],
        [
            UserLanguage(
                user_id=owner_scope.user_id,
                language_kind="target",
                language_tag="en",
                sort_order=0,
                self_assessed_level="beginner",
                learning_goals=["reading"],
            )
        ],
    ]
    result = await service.update_study_profile(
        session,
        owner_scope,
        StudyProfileUpdate.model_validate(
            {
                "expected_revision": 5,
                "fields": {
                    "native_languages": ["en"],
                    "explanation_language": None,
                    "target_languages": [
                        {
                            "language_tag": "en",
                            "self_assessed_level": "beginner",
                            "learning_goals": ["reading"],
                        }
                    ],
                },
            }
        ),
    )
    assert result.revision == 6 and result.active_target_language is None
    assert result.explanation_language is None
    assert [row.language_tag for row in result.target_languages] == ["en"]
    assert repo["replace_kind"].await_count == 2
    for call in repo["replace_kind"].await_args_list:
        assert call.args[1] == owner_scope.user_id
        assert all(row.user_id == owner_scope.user_id for row in call.args[3])
    assert extension.profile_revision == 4 and extension.settings_revision == 6


async def test_active_target_must_exist_even_without_target_list_mask(
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    with pytest.raises(AppError) as error:
        await service.update_study_profile(
            session,
            owner_scope,
            StudyProfileUpdate.model_validate(
                {
                    "expected_revision": 5,
                    "fields": {"active_target_language": "en"},
                }
            ),
        )
    assert error.value.code == ErrorCode.INPUT_INVALID
    assert extension.study_revision == 5


async def test_settings_null_clear_and_value_update_leave_other_groups_untouched(
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    result = await service.update_settings(
        session,
        owner_scope,
        SettingsUpdate.model_validate(
            {
                "expected_revision": 6,
                "fields": {
                    "timezone": None,
                    "theme_mode": "dark",
                    "reduce_motion": "on",
                    "reading_font_family": None,
                    "reading_font_size": None,
                    "reading_line_height": None,
                    "reading_theme": None,
                    "playback_speed": "1.20",
                    "query_context_budget_tokens": 64000,
                },
            }
        ),
    )
    assert result.revision == 7 and result.timezone is None
    assert result.theme_mode == "dark" and result.reduce_motion == "on"
    assert result.reading_font_family is None and result.reading_font_size is None
    assert result.reading_line_height is None and result.reading_theme is None
    assert result.playback_speed == Decimal("1.20")
    assert result.query_context_budget_tokens == 64000
    assert extension.profile_revision == 4 and extension.study_revision == 5


@pytest.mark.parametrize("operation", ["profile", "study", "settings"])
async def test_revision_conflict_does_not_replace_or_increment_any_group(
    operation: str,
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    with pytest.raises(AppError) as error:
        if operation == "profile":
            await service.update_profile(
                session,
                owner_scope,
                ProfileUpdate.model_validate(
                    {
                        "expected_revision": 1,
                        "fields": {"display_name": "Rejected"},
                    }
                ),
            )
        elif operation == "study":
            await service.update_study_profile(
                session,
                owner_scope,
                StudyProfileUpdate.model_validate(
                    {
                        "expected_revision": 1,
                        "fields": {"native_languages": []},
                    }
                ),
            )
        else:
            await service.update_settings(
                session,
                owner_scope,
                SettingsUpdate.model_validate(
                    {
                        "expected_revision": 1,
                        "fields": {"timezone": None},
                    }
                ),
            )
    assert error.value.code == ErrorCode.REVISION_CONFLICT
    assert (extension.profile_revision, extension.study_revision, extension.settings_revision) == (
        4,
        5,
        6,
    )
    assert extension.display_name == "Existing" and extension.timezone == "Asia/Tokyo"
    repo["replace_kind"].assert_not_awaited()


@pytest.mark.parametrize("operation", ["profile", "study", "settings"])
async def test_corrupt_persistence_is_not_returned_as_unvalidated_owner_data(
    operation: str,
    session: AsyncSession,
    owner_scope: ScopeContext,
    extension: UserExtension,
    repo: dict[str, AsyncMock],
) -> None:
    extension.profile_revision = 0
    extension.study_revision = 0
    extension.settings_revision = 0
    read = {
        "profile": service.read_profile,
        "study": service.read_study_profile,
        "settings": service.read_settings,
    }[operation]
    with pytest.raises(AppError) as error:
        await read(session, owner_scope)
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
