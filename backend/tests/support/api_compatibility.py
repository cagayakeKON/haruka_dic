"""Pydantic authority for cross-language samples, without production sample routes."""

import base64
import hashlib
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from fastapi import FastAPI, Response
from pydantic import AwareDatetime, Field, field_validator

from app.contracts.errors import ErrorCode, FieldErrorCode
from app.schemas.auth import (
    AccessRead,
    AccountRead,
    ActivationRequired,
    AuthzVersionRead,
    CsrfRead,
    MailAccepted,
    NativeAuthenticated,
    NativeLoginRead,
    NavigationRead,
    PermissionRead,
    SessionSummary,
    WebAuthenticated,
    WebLoginRead,
)
from app.schemas.avatar import (
    AvatarDelete,
    AvatarUploadComplete,
    AvatarUploadIntentCreate,
    AvatarUploadIntentRead,
)
from app.schemas.language_capabilities import LanguageCapabilitiesRead
from app.schemas.learning_reference import (
    CollectionRead,
    ExplanationResolveRead,
    NovelContentLocator,
    ResolvedCard,
    SourceSpan,
    WordCardPayload,
    WordCardRead,
    WordExample,
)
from app.schemas.profile import (
    ProfileCompleteness,
    ProfileRead,
    ProfileUpdate,
    SettingsRead,
    SettingsUpdate,
    StudyProfileRead,
    StudyProfileUpdate,
    TargetLanguageRead,
)
from app.schemas.responses import (
    ApiError,
    ApiModel,
    ErrorResponse,
    FieldError,
    PageMeta,
    PageResponse,
    ResponseMeta,
    RevisionConflictDetails,
    SuccessResponse,
)
from app.schemas.scalars import CanonicalDecimal
from app.services.language_capabilities import read_catalogue

REQUEST_ID = UUID("018f1234-1234-7123-8123-123456789abc")
RESOURCE_ID = UUID("018f1234-5678-7123-8123-123456789abc")
SAMPLE_NON_CREDENTIAL = "SYNTHETIC_SAMPLE_NOT_VALID"


class TextCard(ApiModel):
    kind: Literal["text"]
    text: str


class ChoiceCard(ApiModel):
    kind: Literal["choice"]
    choices: list[str]


class CompatibilityRead(ApiModel):
    resource_id: UUID
    created_at: AwareDatetime
    exact_amount: CanonicalDecimal
    status: Literal["pending", "complete"]
    nullable_optional: str | None = None
    card: Annotated[TextCard | ChoiceCard, Field(discriminator="kind")]

    @field_validator("created_at")
    @classmethod
    def require_utc(cls, value: datetime) -> datetime:
        offset = value.utcoffset()
        if offset is None or offset.total_seconds() != 0:
            raise ValueError("UTC timestamp required")
        return value


def compatibility_openapi() -> dict[str, object]:
    """Export isolated response types plus transport shapes; app.main never uses this app."""
    app = FastAPI(title="Haruka test-only Dart compatibility", version="1")

    @app.get("/samples/read", response_model=SuccessResponse[CompatibilityRead])
    def read_sample() -> Response:
        return Response(status_code=501)

    @app.get("/samples/page", response_model=PageResponse[CompatibilityRead])
    def page_sample() -> Response:
        return Response(status_code=501)

    @app.get("/samples/error", response_model=ErrorResponse)
    def error_sample() -> Response:
        return Response(status_code=501)

    @app.delete("/samples/empty", status_code=204)
    def empty_sample() -> Response:
        return Response(status_code=204)

    @app.get(
        "/samples/binary",
        response_class=Response,
        responses={
            200: {
                "content": {
                    "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
                }
            }
        },
    )
    def binary_sample() -> Response:
        return Response(content=b"haruka", media_type="application/octet-stream")

    @app.put(
        "/samples/upload",
        status_code=204,
        openapi_extra={
            "requestBody": {
                "required": True,
                "content": {
                    "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
                },
            }
        },
    )
    def upload_sample() -> Response:
        return Response(status_code=204)

    @app.post("/samples/decimal", response_model=SuccessResponse[CompatibilityRead])
    def decimal_sample(value: CompatibilityRead) -> SuccessResponse[CompatibilityRead]:
        return SuccessResponse(data=value, meta=ResponseMeta(request_id=REQUEST_ID))

    @app.get("/samples/auth/web-login", response_model=SuccessResponse[WebLoginRead])
    def auth_web_login() -> Response:
        return Response(status_code=501)

    @app.get("/samples/auth/native-login", response_model=SuccessResponse[NativeLoginRead])
    def auth_native_login() -> Response:
        return Response(status_code=501)

    @app.get("/samples/auth/access", response_model=SuccessResponse[AccessRead])
    def auth_access() -> Response:
        return Response(status_code=501)

    @app.get("/samples/auth/account", response_model=SuccessResponse[AccountRead])
    def auth_account() -> Response:
        return Response(status_code=501)

    @app.get("/samples/auth/sessions", response_model=PageResponse[SessionSummary])
    def auth_sessions() -> Response:
        return Response(status_code=501)

    @app.get("/samples/auth/csrf", response_model=SuccessResponse[CsrfRead])
    def auth_csrf() -> Response:
        return Response(status_code=501)

    @app.post(
        "/samples/auth/mail-accepted",
        status_code=202,
        response_model=SuccessResponse[MailAccepted],
    )
    def auth_mail_accepted() -> Response:
        return Response(status_code=501)

    @app.post("/samples/auth/verified", status_code=204)
    def auth_verified() -> Response:
        return Response(status_code=204)

    @app.get("/samples/learning/word-card", response_model=SuccessResponse[WordCardRead])
    def learning_word_card() -> Response:
        return Response(status_code=501)

    @app.get("/samples/learning/collection", response_model=SuccessResponse[CollectionRead])
    def learning_collection() -> Response:
        return Response(status_code=501)

    @app.get("/samples/learning/resolve", response_model=SuccessResponse[ExplanationResolveRead])
    def learning_resolve() -> Response:
        return Response(status_code=501)

    @app.get("/samples/settings/profile", response_model=SuccessResponse[ProfileRead])
    def profile_read() -> Response:
        return Response(status_code=501)

    @app.patch("/samples/settings/profile", response_model=SuccessResponse[ProfileRead])
    def profile_update(body: ProfileUpdate) -> Response:
        return Response(status_code=501)

    @app.get("/samples/settings/study", response_model=SuccessResponse[StudyProfileRead])
    def study_read() -> Response:
        return Response(status_code=501)

    @app.patch("/samples/settings/study", response_model=SuccessResponse[StudyProfileRead])
    def study_update(body: StudyProfileUpdate) -> Response:
        return Response(status_code=501)

    @app.get("/samples/settings/preferences", response_model=SuccessResponse[SettingsRead])
    def settings_read() -> Response:
        return Response(status_code=501)

    @app.patch("/samples/settings/preferences", response_model=SuccessResponse[SettingsRead])
    def settings_update(body: SettingsUpdate) -> Response:
        return Response(status_code=501)

    @app.get(
        "/samples/settings/languages", response_model=SuccessResponse[LanguageCapabilitiesRead]
    )
    def languages_read() -> Response:
        return Response(status_code=501)

    @app.post(
        "/samples/settings/avatar-intent", response_model=SuccessResponse[AvatarUploadIntentRead]
    )
    def avatar_intent(body: AvatarUploadIntentCreate) -> Response:
        return Response(status_code=501)

    @app.post("/samples/settings/avatar-complete", response_model=SuccessResponse[ProfileRead])
    def avatar_complete(body: AvatarUploadComplete) -> Response:
        return Response(status_code=501)

    @app.delete("/samples/settings/avatar", response_model=SuccessResponse[ProfileRead])
    def avatar_delete(body: AvatarDelete) -> Response:
        return Response(status_code=501)

    return app.openapi()


def compatibility_samples() -> dict[str, object]:
    """Serialize validated Python values, preserving omitted/null/value distinctions."""
    common: dict[str, object] = {
        "resource_id": str(RESOURCE_ID),
        "created_at": "2026-09-22T01:02:03.123456Z",
        "exact_amount": "12345678901234567890.123456789",
        "status": "complete",
        "card": {"kind": "text", "text": "日本語 / English"},
    }
    missing = CompatibilityRead.model_validate(common)
    null = CompatibilityRead.model_validate({**common, "nullable_optional": None})
    value = CompatibilityRead.model_validate(
        {
            **common,
            "nullable_optional": "present",
            "card": {"kind": "choice", "choices": ["A", "B"]},
        }
    )
    meta = ResponseMeta(request_id=REQUEST_ID)
    success = SuccessResponse[CompatibilityRead](data=missing, meta=meta)
    page = PageResponse[CompatibilityRead](
        data=[null, value],
        meta=PageMeta(request_id=REQUEST_ID, next_cursor="cursor-2", has_more=True),
    )
    error = ErrorResponse(
        error=ApiError(
            code=ErrorCode.INPUT_INVALID,
            message="输入信息有误",
            field_errors=[
                FieldError(
                    source="body",
                    path=["items", 0, "text"],
                    code=FieldErrorCode.TOO_LONG,
                    message="内容超过允许长度",
                    message_args={"limit": 10, "unit": "characters"},
                )
            ],
        ),
        meta=meta,
    )
    conflict = ErrorResponse(
        error=ApiError(
            code=ErrorCode.REVISION_CONFLICT,
            message="内容已更新，请重新加载",
            details=RevisionConflictDetails(current_revision=7),
        ),
        meta=meta,
    )
    return {
        "schema_version": 1,
        "success_missing": success.model_dump(mode="json", exclude_unset=True),
        "success_null": SuccessResponse[CompatibilityRead](data=null, meta=meta).model_dump(
            mode="json", exclude_unset=True
        ),
        "success_value": SuccessResponse[CompatibilityRead](data=value, meta=meta).model_dump(
            mode="json", exclude_unset=True
        ),
        "page": page.model_dump(mode="json"),
        "error": error.model_dump(mode="json"),
        "conflict": conflict.model_dump(mode="json"),
        "unknown_enum": {**common, "status": "future_status"},
        "decimal_boundaries": [
            {
                "input": numeric,
                "output": SuccessResponse[CompatibilityRead](
                    data=CompatibilityRead.model_validate(
                        {**common, "exact_amount": Decimal(numeric)}
                    ),
                    meta=meta,
                ).model_dump(mode="json"),
            }
            for numeric in (
                "1E+3",
                "1E-7",
                "-1E-7",
                "0E-10",
                "-0.00",
                "12345678901234567890.123456789",
            )
        ],
        "transports": {
            "empty": {"status": 204, "body": ""},
            "binary": {"status": 200, "bytes": [104, 97, 114, 117, 107, 97]},
            "upload": {"method": "PUT", "media_type": "application/octet-stream"},
        },
        **_auth_samples(),
        **_settings_samples(),
    }


def _settings_samples() -> dict[str, object]:
    """B2a wire samples, including field masks and the avatar transport declaration."""
    meta = ResponseMeta(request_id=REQUEST_ID)
    completeness = ProfileCompleteness(
        display_name=False, explanation_language=False, target_language=False, timezone=False
    )
    empty_profile = ProfileRead(
        revision=1,
        use_optional_demographics_for_ai=False,
        avatar_revision=0,
        profile_completeness=completeness,
    )
    filled_profile = ProfileRead(
        revision=2,
        display_name="遥",
        birth_year=1998,
        age_band="18_29",
        gender_code="self_described",
        gender_self_description="合成样本",
        use_optional_demographics_for_ai=False,
        avatar_asset_id=RESOURCE_ID,
        avatar_revision=1,
        profile_completeness=ProfileCompleteness(
            display_name=True, explanation_language=True, target_language=True, timezone=True
        ),
    )
    empty_study = StudyProfileRead(revision=1, native_languages=[], target_languages=[])
    filled_study = StudyProfileRead(
        revision=2,
        native_languages=["zh-Hans"],
        explanation_language="zh-Hans",
        active_target_language="ja",
        target_languages=[
            TargetLanguageRead(
                language_tag="ja",
                self_assessed_level="beginner",
                learning_goals=["reading", "listening"],
            )
        ],
    )
    empty_settings = SettingsRead(
        revision=1,
        ui_locale="zh-Hans",
        theme_mode="system",
        reduce_motion="system",
        playback_speed=Decimal("1.00"),
        query_context_budget_tokens=8000,
    )
    filled_settings = SettingsRead(
        revision=2,
        ui_locale="zh-Hans",
        timezone="Asia/Tokyo",
        theme_mode="dark",
        reduce_motion="on",
        reading_font_family="serif",
        reading_font_size=Decimal("18.00"),
        reading_line_height=Decimal("1.50"),
        reading_theme="sepia",
        playback_speed=Decimal("1.25"),
        query_context_budget_tokens=16000,
    )
    # Wire-only bytes have a PNG signature so the Dart declaration code accepts them.
    # They are not an image-processing fixture and must never be uploaded to an API.
    avatar_bytes = bytes.fromhex("89504e470d0a1a0a00000000")
    avatar_base64 = base64.b64encode(avatar_bytes).decode("ascii")

    def success(value: ApiModel) -> dict[str, object]:
        return SuccessResponse(data=value, meta=meta).model_dump(mode="json")

    def body(value: ApiModel) -> dict[str, object]:
        return value.model_dump(mode="json", exclude_unset=True)

    return {
        "settings_profile_empty": success(empty_profile),
        "settings_profile_present": success(filled_profile),
        "settings_profile_patch_null": body(
            ProfileUpdate.model_validate({"expected_revision": 2, "fields": {"birth_year": None}})
        ),
        "settings_study_empty": success(empty_study),
        "settings_study_present": success(filled_study),
        "settings_study_patch": body(
            StudyProfileUpdate.model_validate(
                {
                    "expected_revision": 1,
                    "fields": {
                        "native_languages": ["zh-Hans"],
                        "explanation_language": "zh-Hans",
                        "active_target_language": "ja",
                        "target_languages": [
                            {
                                "language_tag": "ja",
                                "self_assessed_level": "beginner",
                                "learning_goals": ["reading", "listening"],
                            }
                        ],
                    },
                }
            )
        ),
        "settings_preferences_empty": success(empty_settings),
        "settings_preferences_present": success(filled_settings),
        "settings_preferences_patch": body(
            SettingsUpdate.model_validate(
                {
                    "expected_revision": 1,
                    "fields": {
                        "timezone": None,
                        "reading_font_size": "18.00",
                        "playback_speed": "1.25",
                    },
                }
            )
        ),
        "settings_language_capabilities": success(read_catalogue()),
        "settings_avatar_intent": success(
            AvatarUploadIntentRead(
                id=RESOURCE_ID,
                expires_at=datetime.fromisoformat("2026-09-28T01:02:03+00:00"),
                max_size_bytes=5 * 1024 * 1024,
                accepted_formats=["jpeg", "png", "webp"],
            )
        ),
        "settings_avatar_create": body(
            AvatarUploadIntentCreate(
                declared_format="png",
                expected_size_bytes=len(avatar_bytes),
                expected_sha256=hashlib.sha256(avatar_bytes).hexdigest(),
            )
        ),
        "settings_avatar_complete": body(
            AvatarUploadComplete(expected_revision=1, image_base64=avatar_base64)
        ),
        "settings_avatar_delete": body(AvatarDelete(expected_revision=2)),
        "settings_avatar_bytes": list(avatar_bytes),
        "settings_revision_conflict": ErrorResponse(
            error=ApiError(
                code=ErrorCode.REVISION_CONFLICT,
                message="内容已更新，请重新加载",
                details=RevisionConflictDetails(current_revision=2),
            ),
            meta=meta,
        ).model_dump(mode="json"),
    }


def _auth_samples() -> dict[str, object]:
    """Cross-language authentication and learning fixtures use synthetic IDs and non-credential sentinels."""
    at = datetime.fromisoformat("2026-09-26T01:02:03+00:00")
    expires = datetime.fromisoformat("2026-09-27T01:02:03+00:00")
    user = UUID("018f1234-0000-7000-8000-000000000001")
    session = UUID("018f1234-0000-7000-8000-000000000002")
    library = UUID("018f1234-0000-7000-8000-000000000003")
    material = UUID("018f1234-0000-7000-8000-000000000004")
    revision = UUID("018f1234-0000-7000-8000-000000000005")
    chapter = UUID("018f1234-0000-7000-8000-000000000006")
    chapter_block = UUID("018f1234-0000-7000-8000-000000000007")
    block = UUID("018f1234-0000-7000-8000-000000000008")
    card_id = UUID("018f1234-0000-7000-8000-000000000009")
    locator = NovelContentLocator(
        instance_id="haruka-test-0123456789abcdef0123456789abcdef",
        library_id=library,
        material_id=material,
        material_revision_id=revision,
        novel_chapter_id=chapter,
        chapter_block_id=chapter_block,
        quote="青い空",
        prefix="",
        suffix="が見える。",
        source_title="合成短篇",
        node_title="第一章",
        spans=[SourceSpan(block_id=block, start=0, end=3)],
    )
    payload = WordCardPayload(
        term="青い",
        reading="あおい",
        part_of_speech="形容詞",
        context_meaning="蓝色的",
        other_meanings=["年轻的"],
        examples=[
            WordExample(text="青い空です。", meaning="是蓝天。"),
            WordExample(text="青い花が咲く。", meaning="蓝色的花开了。"),
        ],
    )
    card = WordCardRead(
        card_id=card_id,
        card_revision=1,
        target_language="ja",
        explanation_language="zh-Hans",
        payload=payload,
        source_refs=[locator],
        created_at=at,
    )
    collection = CollectionRead(
        id=UUID("018f1234-0000-7000-8000-000000000010"),
        revision=1,
        card_id=card_id,
        card_revision=1,
        display_text="青い",
        target_language="ja",
        payload=payload,
        source_refs=[locator],
        created_at=at,
    )
    web = WebAuthenticated(
        session_ref=session,
        audience="client",
        absolute_expires_at=expires,
        idle_expires_at=expires,
        server_time=at,
    )
    pending = ActivationRequired(
        continuation_token=SAMPLE_NON_CREDENTIAL,
        continuation_expires_at=expires,
    )
    native = NativeAuthenticated(
        session_ref=session,
        access_token=SAMPLE_NON_CREDENTIAL,
        access_expires_at=expires,
        refresh_token=SAMPLE_NON_CREDENTIAL,
        refresh_expires_at=expires,
        session_generation=1,
        absolute_expires_at=expires,
        server_time=at,
    )
    client_access = AccessRead(
        user_id=user,
        instance_id="haruka-test-0123456789abcdef0123456789abcdef",
        audience="client",
        session_ref=session,
        authz_version=AuthzVersionRead(user=1, policy=3),
        permissions=[PermissionRead(code="client.login", data_scope="self")],
        navigation=[],
        feature_flags=[],
    )
    admin_access = AccessRead(
        user_id=user,
        instance_id="haruka-test-0123456789abcdef0123456789abcdef",
        audience="admin",
        session_ref=session,
        authz_version=AuthzVersionRead(user=2, policy=3),
        permissions=[PermissionRead(code="admin.auth_policy.read", data_scope="platform_metadata")],
        navigation=[NavigationRead(key="administration", route_key="/admin", title="管理")],
        feature_flags=[],
    )
    meta = ResponseMeta(request_id=REQUEST_ID)

    def success(value: object) -> dict[str, object]:
        return SuccessResponse(data=value, meta=meta).model_dump(mode="json")

    return {
        "auth_web_authenticated": success(web),
        "auth_web_action_required": success(pending),
        "auth_native_authenticated": success(native),
        "auth_native_action_required": success(pending),
        "auth_client_access_login_only": success(client_access),
        "auth_admin_access": success(admin_access),
        "auth_account_legacy_unverified": success(
            AccountRead(email="legacy@example.test", email_verified_at=None, created_at=at)
        ),
        "auth_sessions_page": PageResponse[SessionSummary](
            data=[
                SessionSummary(
                    id=session,
                    audience="client",
                    transport="native",
                    platform="android",
                    device_summary="Example emulator",
                    created_at=at,
                    last_seen_at=at,
                    absolute_expires_at=expires,
                    revoked_at=None,
                    is_current=True,
                )
            ],
            meta=PageMeta(request_id=REQUEST_ID, next_cursor=None, has_more=False),
        ).model_dump(mode="json"),
        "auth_csrf": success(CsrfRead(session_ref=session, csrf_token=SAMPLE_NON_CREDENTIAL)),
        "auth_mail_accepted": {
            "status": 202,
            "response": success(MailAccepted(next_step="check_email")),
        },
        "auth_verified_empty": {"status": 204, "body": ""},
        "learning_word_card": success(card),
        "learning_collection": success(collection),
        "learning_resolve_found": success(
            ExplanationResolveRead(results=[ResolvedCard(card=card)])
        ),
    }
