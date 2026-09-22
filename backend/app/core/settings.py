"""Explicit configuration; importing this module never reads the environment."""

from pathlib import Path
from typing import Literal, Self, TypedDict, Unpack
from urllib.parse import urlsplit

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class SettingsInput(TypedDict, total=False):
    app_env: Literal["dev", "test", "staging", "production"]
    instance_id: str
    public_base_url: str
    allowed_origins: tuple[str, ...]
    release: str
    _env_file: Path | None
    _env_file_encoding: str


class Settings(BaseSettings):
    """Validated public configuration for the development process shell.

    Persistent services are not assembled by B0-foundation. Production startup
    stays closed until the subsequent B0 slices implement those dependencies.
    """

    model_config = SettingsConfigDict(
        env_prefix="HARUKA_", extra="forbid", frozen=True, hide_input_in_errors=True
    )

    app_env: Literal["dev", "test", "staging", "production"]
    instance_id: str = Field(pattern=r"^haruka-[a-z0-9][a-z0-9-]{0,62}$")
    public_base_url: str
    allowed_origins: tuple[str, ...] = ()
    release: str = Field(default="0.1.0", pattern=r"^[a-zA-Z0-9._-]{1,64}$")

    def __init__(self, **values: Unpack[SettingsInput]) -> None:
        # Settings accepts absent constructor fields because environment/file
        # sources supply them. Keep this dynamic boundary explicitly validated.
        super().__init__(**values)

    @model_validator(mode="after")
    def validate_environment(self) -> Self:
        if self.app_env not in {"dev", "test"}:
            raise ValueError("runtime dependencies are not yet available for this environment")
        prefix = "haruka-local-" if self.app_env == "dev" else "haruka-test-"
        if not self.instance_id.startswith(prefix):
            raise ValueError("instance does not match the selected isolated environment")
        for address in (self.public_base_url, *self.allowed_origins):
            parsed = urlsplit(address)
            if (
                parsed.scheme not in {"http", "https"}
                or parsed.hostname not in {"localhost", "127.0.0.1", "::1"}
                or parsed.username is not None
                or parsed.password is not None
                or parsed.query
                or parsed.fragment
                or parsed.path not in {"", "/"}
            ):
                raise ValueError("shell endpoints must be explicit loopback origins")
            # Validate malformed ports even though the origin is never logged.
            _ = parsed.port
        return self


def load_settings(config: Path | None = None) -> Settings:
    """Load only the explicitly selected file; process environment takes precedence."""
    if config is not None and not config.is_file():
        raise ValueError("configuration file does not exist")
    return Settings(_env_file=config, _env_file_encoding="utf-8")
