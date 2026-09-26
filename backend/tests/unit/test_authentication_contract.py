"""Authentication transport rejects malformed secrets without disclosing them."""

import pytest
from fastapi import Request
from httpx2 import ASGITransport, AsyncClient
from pydantic import SecretStr

import app.api.authentication as authentication
from app.bootstrap import Runtime
from app.core.settings import Settings
from app.main import create_app
from app.schemas.auth import TokenRequest

pytestmark = pytest.mark.unit


@pytest.mark.asyncio
async def test_email_token_wire_validation_and_safe_http_error() -> None:
    valid = "A" * 43
    assert TokenRequest(token=SecretStr(valid)).token.get_secret_value() == valid

    app = create_app(schema_only=True)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        accepted = await client.post("/api/v1/auth/email/verify", json={"token": valid})
        malformed = await client.post("/api/v1/auth/email/verify", json={"token": "bad.token"})

    # A valid body reaches the service, where the schema-only app rejects missing runtime.
    assert accepted.status_code == 503
    assert accepted.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    assert malformed.status_code == 422
    assert malformed.json()["error"]["code"] == "INPUT_INVALID"
    assert "bad.token" not in malformed.text


def test_authentication_openapi_exposes_complete_source_and_nullable_legacy_verification() -> None:
    schema = create_app(schema_only=True).openapi()
    schemas = schema["components"]["schemas"]
    assert "/api/v1/meta" in schema["paths"]
    assert "/api/v1/auth/native/login" in schema["paths"]
    assert "first_chapter_id" in schemas["MaterialSummary"]["required"]
    assert "source_locator" in schemas["NovelBlockRead"]["required"]
    assert "library_id" in schemas["NovelChapterRead"]["required"]
    assert "email_verified_at" in schemas["AccountRead"]["properties"]
    assert "anyOf" in schemas["AccountRead"]["properties"]["email_verified_at"]
    token = schemas["TokenRequest"]["properties"]["token"]
    assert token["pattern"] == "^[A-Za-z0-9_-]{43}$"
    assert token["minLength"] == token["maxLength"] == 43
    password = schemas["RegisterRequest"]["properties"]["password"]
    assert (password["minLength"], password["maxLength"]) == (15, 128)


@pytest.mark.asyncio
async def test_shared_anonymous_action_distinguishes_native_and_browser_writes(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    runtime = Runtime(settings=settings)

    def fake_runtime(_request: Request) -> Runtime:
        return runtime

    monkeypatch.setattr(authentication, "require_runtime", fake_runtime)
    app = create_app(schema_only=True)
    payload = {"email": "person@example.test", "password": "valid-length-passphrase"}
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        native = await client.post("/api/v1/auth/register", json=payload)
        same_origin_browser = await client.post(
            "/api/v1/auth/register",
            json=payload,
            headers={"Origin": settings.public_base_url, "Sec-Fetch-Site": "same-origin"},
        )
        hostile_browser = await client.post(
            "/api/v1/auth/register",
            json=payload,
            headers={"Origin": "https://untrusted.example", "Sec-Fetch-Site": "cross-site"},
        )
        form = await client.post(
            "/api/v1/auth/register",
            content="email=person%40example.test",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
    assert native.status_code == same_origin_browser.status_code == 503
    assert hostile_browser.status_code == 403
    assert hostile_browser.json()["error"]["code"] == "CSRF_FAILED"
    assert form.status_code == 422
    assert form.json()["error"]["code"] == "INPUT_INVALID"
