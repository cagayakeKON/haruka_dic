"""Environment selection fails closed before starting a public process."""

from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.settings import Settings, load_settings

pytestmark = pytest.mark.unit


@pytest.mark.parametrize(
    "values",
    [
        {},
        {
            "app_env": "production",
            "instance_id": "haruka-production",
            "public_base_url": "https://example.com",
        },
        {
            "app_env": "test",
            "instance_id": "haruka-local-dev",
            "public_base_url": "http://localhost",
        },
        {
            "app_env": "dev",
            "instance_id": "haruka-local-dev",
            "public_base_url": "https://example.com",
        },
        {
            "app_env": "dev",
            "instance_id": "haruka-local-dev",
            "public_base_url": "http://localhost/?key=SENTINEL",
        },
        {
            "app_env": "dev",
            "instance_id": "haruka-local-dev",
            "public_base_url": "http://localhost:wrong",
        },
        {
            "app_env": "dev",
            "instance_id": "haruka-local-dev",
            "public_base_url": "http://user:fake@localhost",
        },
    ],
    ids=[
        "missing",
        "production",
        "environment-mismatch",
        "remote",
        "query",
        "bad-port",
        "userinfo",
    ],
)
def test_unsafe_configuration_rejected(values: dict[str, str]) -> None:
    with pytest.raises(ValidationError):
        Settings.model_validate(values)


def test_explicit_file_environment_precedence_and_no_cwd_discovery(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    config = tmp_path / "explicit.env"
    config.write_text(
        "HARUKA_APP_ENV=dev\nHARUKA_INSTANCE_ID=haruka-local-file\n"
        "HARUKA_PUBLIC_BASE_URL=http://localhost:8000\n",
        encoding="utf-8",
    )
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text("HARUKA_APP_ENV=production\n", encoding="utf-8")
    monkeypatch.setenv("HARUKA_INSTANCE_ID", "haruka-local-environment")
    assert load_settings(config).instance_id == "haruka-local-environment"
    with pytest.raises(ValidationError):
        load_settings()
    with pytest.raises(ValueError, match="does not exist"):
        load_settings(tmp_path / "missing.env")
