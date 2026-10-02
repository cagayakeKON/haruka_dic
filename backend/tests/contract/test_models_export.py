"""Envelope invariants and offline contracts have independent expected assertions."""

import json
from pathlib import Path
from typing import cast
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.contracts.errors import ERRORS, ErrorCode
from app.contracts.export import canonical_json, documents
from app.core.settings import load_settings
from app.domain.errors import AppError
from app.maintenance.migrations import load_migration_resources
from app.schemas.responses import ApiError, PageMeta, PageResponse, RevisionConflictDetails

pytestmark = pytest.mark.contract


def test_exported_database_revision_matches_verified_migration_bundle() -> None:
    backend = Path(__file__).resolve().parents[2]
    database = cast(dict[str, object], documents()["database-schema.json"])
    assert database["migration_revision"] == load_migration_resources(backend / "alembic").head


@pytest.mark.parametrize(("has_more", "cursor"), [(True, None), (True, ""), (False, "opaque")])
def test_page_cursor_inconsistent_state_rejected(has_more: bool, cursor: str | None) -> None:
    with pytest.raises(ValidationError):
        PageMeta(request_id=uuid4(), has_more=has_more, next_cursor=cursor)


def test_empty_page_is_flat_and_null_is_preserved() -> None:
    page = PageResponse[str](
        data=[], meta=PageMeta(request_id=uuid4(), has_more=False, next_cursor=None)
    )
    result = page.model_dump(mode="json")
    assert result["data"] == []
    assert result["meta"]["next_cursor"] is None


def test_arbitrary_error_parameters_and_mismatched_details_rejected() -> None:
    with pytest.raises(ValidationError):
        ApiError(code=ErrorCode.INTERNAL_ERROR, message="safe", message_args={"token": "sentinel"})
    with pytest.raises(ValidationError):
        ApiError(
            code=ErrorCode.INTERNAL_ERROR,
            message="safe",
            details=RevisionConflictDetails(current_revision=1),
        )
    with pytest.raises(ValueError):
        AppError(ErrorCode.RESOURCE_NOT_FOUND, current_revision=1)


def test_export_is_offline_deterministic_and_contains_only_real_routes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("HARUKA_APP_ENV", "production")
    monkeypatch.setenv("HARUKA_PUBLIC_BASE_URL", "fake-secret-sentinel")
    first = canonical_json(documents())
    assert first == canonical_json(documents())
    assert "sentinel" not in first
    payload = json.loads(first)
    schema = payload["openapi.json"]
    assert len(schema["paths"]) == 103
    assert {
        "/health/live",
        "/health/ready",
        "/api/v1/meta",
        "/api/v1/auth/register",
        "/api/v1/auth/email/verify",
        "/api/v1/auth/recovery/complete",
        "/api/v1/admin/auth-policy",
        "/api/v1/explanations/resolve",
        "/api/v1/collections",
        "/api/v1/frontend-logs",
        "/api/v1/language-capabilities",
        "/api/v1/me/cache/validate",
        "/api/v1/material-import-capabilities",
        "/api/v1/material-imports",
        "/api/v1/material-imports/{import_id}",
        "/api/v1/uploads/{upload_id}/content",
        "/api/v1/uploads/{upload_id}/complete",
        "/api/v1/notifications",
        "/api/v1/notifications/{notification_id}/read",
        "/api/v1/notifications/read-all",
    } <= set(schema["paths"])
    assert all(path.startswith(("/health/", "/api/v1/")) for path in schema["paths"])
    operations = {
        method["operationId"]
        for methods in schema["paths"].values()
        for verb, method in methods.items()
        if verb in {"get", "post", "patch", "put", "delete"}
    }
    assert {
        "get_liveness",
        "get_readiness",
        "register_account",
        "verify_email",
        "complete_password_recovery",
        "login_native_client",
        "get_client_access",
        "update_admin_auth_policy",
        "resolve_explanations",
        "create_collection",
        "receive_client_telemetry",
        "get_my_profile",
        "update_my_profile",
        "get_my_study_profile",
        "update_my_study_profile",
        "get_my_settings",
        "update_my_settings",
        "create_avatar_upload_intent",
        "complete_avatar_upload_intent",
        "get_my_avatar",
        "delete_my_avatar",
        "get_language_capabilities",
        "validate_client_cache",
        "list_user_notifications",
        "mark_user_notification_read",
        "mark_all_user_notifications_read",
    } <= operations
    assert "SuccessResponse_HealthRead_" in schema["components"]["schemas"]
    assert "ErrorResponse" in schema["components"]["schemas"]
    assert "HTTPValidationError" not in schema["components"]["schemas"]
    assert set(ERRORS) == set(ErrorCode)


def test_default_web_origin_matches_backend_template() -> None:
    root = Path(__file__).resolve().parents[3]
    frontend = json.loads((root / "frontend/config/build_targets.json").read_text(encoding="utf-8"))
    web_origin = frontend["platforms"]["web"]["dev"]["origin"]
    settings = load_settings(root / "backend/.env.example")
    assert isinstance(web_origin, str)
    assert web_origin in settings.allowed_origins


def test_material_and_notification_dto_exports_resolve_without_route_claims() -> None:
    payload = documents()
    for name in ("material-import-contract.json", "user-notification-contract.json"):
        document = cast(dict[str, object], payload[name])
        assert document["scope"] == "dto-definitions"
        encoded = json.loads(canonical_json(document))
        for reference in encoded["models"].values():
            parts = reference["$ref"].removeprefix("#/").split("/")
            target = encoded
            for part in parts:
                target = target[part]
            assert target["type"] == "object"
    material = json.loads(canonical_json(payload["material-import-contract.json"]))["$defs"]
    assert {"file", "source_material_id", "requested_stages"} <= set(
        material["MaterialImportCreate"]["properties"]
    )
    assert material["MaterialRequestedStages"]["properties"]["analyze"]["const"] is False
    notifications = json.loads(canonical_json(payload["user-notification-contract.json"]))["$defs"]
    assert notifications["NotificationsReadAll"]["additionalProperties"] is False
    assert set(notifications["NotificationsReadAll"]["properties"]) == {"snapshot_token"}
    assert notifications["UserNotificationPageMeta"]["properties"]["unread_count"]["minimum"] == 0
