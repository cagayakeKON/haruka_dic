"""Real ASGI boundaries; synthetic routes exist only in this test application."""

from collections.abc import Iterator
from typing import Annotated
from uuid import UUID

import pytest
from fastapi import FastAPI, Query
from fastapi.testclient import TestClient
from pydantic import Field
from starlette.responses import Response

from app.api.responses import error_responses
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError
from app.main import create_app
from app.schemas.responses import ApiModel

pytestmark = pytest.mark.contract


class Input(ApiModel):
    term: str = Field(max_length=8)


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    app = create_app(settings)

    @app.post("/contract-input", responses=error_responses(400, 422, 500))
    async def input_route(body: Input, limit: Annotated[int, Query(ge=1)] = 20) -> Input:
        return body

    @app.get("/contract-error/{code}")
    async def application_error(code: ErrorCode) -> None:
        raise AppError(code)

    @app.get("/contract-unexpected")
    async def unexpected_error() -> None:
        raise RuntimeError("private-body-sentinel fake-secret-sentinel")

    @app.get("/contract-invalid-response", response_model=Input)
    async def invalid_response() -> dict[str, int]:
        return {"term": 123}

    @app.delete("/contract-empty", status_code=204)
    async def empty_response() -> Response:
        return Response(status_code=204, headers={"X-Custom": "preserved"})

    with TestClient(app, raise_server_exceptions=False) as running:
        yield running
    assert app.state.runtime is None


def test_health_and_readiness_are_distinct(client: TestClient) -> None:
    response = client.get("/health/live", headers={"X-Request-ID": str(UUID(int=0))})
    assert response.status_code == 200
    payload = response.json()
    assert payload["data"] == {"status": "ok"}
    assert UUID(payload["meta"]["request_id"]) != UUID(int=0)
    assert response.headers["x-request-id"] == payload["meta"]["request_id"]
    ready = client.get("/health/ready")
    assert ready.status_code == 503
    assert ready.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    assert ready.json()["error"]["retryable"] is False


@pytest.mark.parametrize(
    ("method", "path", "status", "code"),
    [
        ("get", "/api/v1/me", 404, "RESOURCE_NOT_FOUND"),
        ("post", "/health/live", 405, "METHOD_NOT_ALLOWED"),
        ("get", "/contract-error/AUTH_REQUIRED", 401, "AUTH_REQUIRED"),
        ("get", "/contract-error/PERMISSION_DENIED", 403, "PERMISSION_DENIED"),
        ("get", "/contract-unexpected", 500, "INTERNAL_ERROR"),
        ("get", "/contract-invalid-response", 500, "INTERNAL_ERROR"),
    ],
)
def test_error_envelope_correlation_and_cors(
    client: TestClient, method: str, path: str, status: int, code: str
) -> None:
    response = client.request(method, path, headers={"Origin": "http://localhost:8080"})
    assert response.status_code == status
    payload = response.json()
    assert payload["error"]["code"] == code
    assert payload["error"]["message_args"] == {}
    assert payload["error"]["field_errors"] == []
    assert payload["error"]["details"] is None
    assert response.headers["x-request-id"] == payload["meta"]["request_id"]
    assert response.headers["content-language"] == "zh-Hans"
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["access-control-allow-origin"] == "http://localhost:8080"
    assert "sentinel" not in response.text
    if status == 405:
        assert "GET" in response.headers["allow"]


def test_invalid_json_and_field_errors_are_sanitized(client: TestClient) -> None:
    malformed = client.post(
        "/contract-input", content="{", headers={"Content-Type": "application/json"}
    )
    assert malformed.status_code == 400
    assert malformed.json()["error"]["code"] == "BAD_REQUEST"
    invalid = client.post(
        "/contract-input?limit=0",
        json={
            "term": "private-body-sentinel",
            "fake-secret-sentinel": "hidden",
        },
    )
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "INPUT_INVALID"
    assert "sentinel" not in invalid.text
    fields = invalid.json()["error"]["field_errors"]
    assert {item["code"] for item in fields} == {
        "VALIDATION_TOO_LONG",
        "VALIDATION_UNKNOWN_FIELD",
        "VALIDATION_OUT_OF_RANGE",
    }
    assert all(item["path"] == [] and item["message_args"] == {} for item in fields)
    assert (
        "HTTPValidationError" not in client.app.openapi()["components"]["schemas"]
        if isinstance(client.app, FastAPI)
        else False
    )


def test_error_count_is_bounded_and_204_is_not_wrapped(client: TestClient) -> None:
    invalid = client.post("/contract-input", json={str(i): "sentinel" for i in range(100)})
    assert len(invalid.json()["error"]["field_errors"]) == 50
    empty = client.delete("/contract-empty")
    assert empty.status_code == 204
    assert empty.content == b""
    assert empty.headers["x-custom"] == "preserved"
    assert "x-request-id" in empty.headers


def test_unknown_origin_is_not_reflected(client: TestClient) -> None:
    response = client.get("/contract-unexpected", headers={"Origin": "https://untrusted.example"})
    assert response.status_code == 500
    assert "access-control-allow-origin" not in response.headers


def test_cors_preflight_has_correlation_and_completion_log(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level("INFO", logger="app.api.context"):
        response = client.options(
            "/health/live",
            headers={
                "Origin": "http://localhost:8080",
                "Access-Control-Request-Method": "GET",
            },
        )
    assert response.status_code == 200
    request_id = UUID(response.headers["x-request-id"])
    events = [record for record in caplog.records if record.msg == "http.completed"]
    assert len(events) == 1
    assert vars(events[0])["request_id"] == request_id
