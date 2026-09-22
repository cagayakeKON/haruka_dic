"""Envelope invariants and offline contracts have independent expected assertions."""

import json
from pathlib import Path
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.contracts.errors import ERRORS, ErrorCode
from app.contracts.export import canonical_json, documents
from app.core.settings import load_settings
from app.domain.errors import AppError
from app.schemas.responses import ApiError, PageMeta, PageResponse, RevisionConflictDetails

pytestmark = pytest.mark.contract


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
    assert set(schema["paths"]) == {"/health/live", "/health/ready"}
    operations = [entry["get"]["operationId"] for entry in schema["paths"].values()]
    assert set(operations) == {"get_liveness", "get_readiness"}
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
