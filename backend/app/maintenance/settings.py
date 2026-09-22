"""A separate, narrowly scoped credential boundary for local database maintenance."""

from pathlib import Path
from typing import Literal, Self, TypedDict, Unpack
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine
from sqlalchemy.pool import NullPool


class MaintenanceInput(TypedDict, total=False):
    database_url: SecretStr
    declared_app_env: Literal["dev", "test", "staging", "production"] | None
    test_schema: str | None
    _env_file: Path | None
    _env_file_encoding: str


class MaintenanceSettings(BaseSettings):
    """Only a dedicated Haruka maintenance account on an explicit loopback database."""

    model_config = SettingsConfigDict(
        env_prefix="HARUKA_",
        extra="forbid",
        frozen=True,
        hide_input_in_errors=True,
        populate_by_name=True,
    )

    database_url: SecretStr
    declared_app_env: Literal["dev", "test", "staging", "production"] | None = Field(
        default=None, validation_alias="HARUKA_APP_ENV"
    )
    test_schema: str | None = Field(default=None, pattern=r"^haruka_migration_test_[a-f0-9]{32}$")

    def __init__(self, **values: Unpack[MaintenanceInput]) -> None:
        super().__init__(**values)
        if self.test_schema is not None and "test_schema" not in values:
            raise ValueError(
                "migration test schemas require explicit programmatic test configuration"
            )

    @model_validator(mode="after")
    def validate_target(self) -> Self:
        parsed = urlsplit(self.database_url.get_secret_value())
        if (
            parsed.scheme != "postgresql+asyncpg"
            or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
            or parsed.port is None
            or not parsed.password
            or parsed.path not in {"/haruka_dev", "/haruka_test"}
            or parsed.username != f"{parsed.path.removeprefix('/')}_maintenance"
            or parsed.query
            or parsed.fragment
        ):
            raise ValueError(
                "maintenance requires an isolated Haruka database and maintenance role"
            )
        if self.test_schema is not None and self.app_env != "test":
            raise ValueError("an isolated migration test schema requires the test database")
        if self.declared_app_env is not None and self.declared_app_env != self.app_env:
            raise ValueError("declared maintenance environment must match the isolated database")
        return self

    @property
    def app_env(self) -> Literal["dev", "test"]:
        return "test" if self.database == "haruka_test" else "dev"

    @property
    def database(self) -> str:
        return urlsplit(self.database_url.get_secret_value()).path.removeprefix("/")

    @property
    def instance_id(self) -> str:
        return "haruka-test-integration" if self.app_env == "test" else "haruka-local-dev"

    @property
    def database_schema(self) -> str:
        return self.test_schema or "public"

    @property
    def application_name(self) -> str:
        suffix = f"-{self.test_schema[-8:]}" if self.test_schema is not None else ""
        return f"{self.instance_id}-maintenance{suffix}"


def load_maintenance_settings(config: Path) -> MaintenanceSettings:
    """Require the selected file; never discover credentials using the working directory."""
    if not config.is_file():
        raise ValueError("maintenance configuration file does not exist")
    return MaintenanceSettings(_env_file=config, _env_file_encoding="utf-8")


def create_maintenance_engine(settings: MaintenanceSettings) -> AsyncEngine:
    """A fresh, non-reconnecting pool owner; callers must dispose it in a finally block."""
    return create_async_engine(
        settings.database_url.get_secret_value(),
        poolclass=NullPool,
        echo=False,
        hide_parameters=True,
        connect_args={
            "timeout": 5,
            "command_timeout": 60,
            "server_settings": {
                "application_name": settings.application_name,
                "timezone": "UTC",
                "search_path": settings.database_schema,
                "statement_timeout": "60000",
                "lock_timeout": "10000",
                "idle_in_transaction_session_timeout": "15000",
            },
        },
    )
