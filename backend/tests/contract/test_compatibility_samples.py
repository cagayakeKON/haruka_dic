"""The Dart fixture export is validated Python data and never a production endpoint."""

import pytest
from pydantic import ValidationError

from app.contracts.navigation import PUBLISHED_ICONS, PUBLISHED_PAGES
from app.contracts.permissions import ADMIN_CODES, CLIENT_CODES
from app.main import create_app
from app.schemas.avatar import (
    AvatarDelete,
    AvatarUploadComplete,
    AvatarUploadIntentCreate,
    AvatarUploadIntentRead,
)
from app.schemas.language_capabilities import LanguageCapabilitiesRead
from app.schemas.menu_governance import MenuCatalogRead, MenuPreviewRead
from app.schemas.profile import (
    ProfileRead,
    ProfileUpdate,
    SettingsRead,
    SettingsUpdate,
    StudyProfileRead,
    StudyProfileUpdate,
)
from app.schemas.responses import (
    ErrorResponse,
    PageResponse,
    RevisionConflictDetails,
    SuccessResponse,
)
from app.schemas.role_governance import RoleRead
from tests.support.api_compatibility import (
    CompatibilityRead,
    compatibility_openapi,
    compatibility_samples,
)

pytestmark = pytest.mark.contract


def test_governance_samples_follow_published_registry_and_parent_wire_shape() -> None:
    samples = compatibility_samples()
    catalog = SuccessResponse[MenuCatalogRead].model_validate(samples["admin_menu_catalog"]).data
    assert {page.code for page in catalog.pages} == {page.code for page in PUBLISHED_PAGES}
    assert set(catalog.icons) == set(PUBLISHED_ICONS)
    assert {choice.code for choice in catalog.permission_codes} == set(ADMIN_CODES) | set(
        CLIENT_CODES
    )
    preview = SuccessResponse[MenuPreviewRead].model_validate(samples["admin_menu_preview"]).data
    assert {item.route_key for item in preview.navigation} == {
        page.route_key for page in PUBLISHED_PAGES if page.audience == "admin"
    }
    role = SuccessResponse[RoleRead].model_validate(samples["admin_role_with_parent"]).data
    assert role.parents[0].code == "client_readonly" and role.parents[0].enabled
    assert role.parents[0].role_id != role.id


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


def test_settings_cross_language_samples_are_validated_wire_shapes() -> None:
    samples = compatibility_samples()
    for key in ("settings_profile_empty", "settings_profile_present"):
        SuccessResponse[ProfileRead].model_validate(samples[key])
    for key in ("settings_study_empty", "settings_study_present"):
        SuccessResponse[StudyProfileRead].model_validate(samples[key])
    for key in ("settings_preferences_empty", "settings_preferences_present"):
        SuccessResponse[SettingsRead].model_validate(samples[key])
    SuccessResponse[LanguageCapabilitiesRead].model_validate(
        samples["settings_language_capabilities"]
    )
    SuccessResponse[AvatarUploadIntentRead].model_validate(samples["settings_avatar_intent"])
    ProfileUpdate.model_validate(samples["settings_profile_patch_null"])
    StudyProfileUpdate.model_validate(samples["settings_study_patch"])
    SettingsUpdate.model_validate(samples["settings_preferences_patch"])
    AvatarUploadIntentCreate.model_validate(samples["settings_avatar_create"])
    AvatarUploadComplete.model_validate(samples["settings_avatar_complete"])
    AvatarDelete.model_validate(samples["settings_avatar_delete"])
    assert ProfileUpdate.model_validate(samples["settings_profile_patch_null"]).fields.model_dump(
        exclude_unset=True
    ) == {"birth_year": None}
    assert (
        SettingsUpdate.model_validate(samples["settings_preferences_patch"]).fields.timezone is None
    )
    assert (
        SuccessResponse[SettingsRead]
        .model_validate(samples["settings_preferences_present"])
        .data.reading_font_size
        == 18
    )
    details = ErrorResponse.model_validate(samples["settings_revision_conflict"]).error.details
    assert isinstance(details, RevisionConflictDetails)
    assert details.current_revision == 2
