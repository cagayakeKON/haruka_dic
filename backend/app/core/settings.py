"""Explicit configuration; importing this module never reads the environment."""

from pathlib import Path
from typing import Literal, Self, TypedDict, Unpack
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class SettingsInput(TypedDict, total=False):
    app_env: Literal["dev", "test", "staging", "production"]
    instance_id: str
    public_base_url: str
    allowed_origins: tuple[str, ...]
    release: str
    infrastructure_enabled: bool
    resource_profile: Literal["core", "jobs"]
    database_url: SecretStr
    redis_url: SecretStr
    resource_namespace: str
    kafka_bootstrap_servers: str
    s3_endpoint: str
    s3_access_key: SecretStr
    s3_secret_key: SecretStr
    s3_bucket: str
    log_file: Path | None
    _env_file: Path | None
    _env_file_encoding: str


class CoreInfrastructureSettings(BaseModel):
    """Validated process credentials, never a user or model credential container."""

    model_config = ConfigDict(frozen=True, hide_input_in_errors=True)

    database_url: SecretStr
    redis_url: SecretStr
    namespace: str


class InfrastructureSettings(CoreInfrastructureSettings):
    """The jobs profile adds broker and object storage to the core resources."""

    kafka_bootstrap_servers: str
    s3_endpoint: str
    s3_access_key: SecretStr
    s3_secret_key: SecretStr
    s3_bucket: str


class Settings(BaseSettings):
    """Explicit offline shell or isolated local infrastructure configuration.

    Production remains closed until migration, authentication and deployment
    safety are implemented. Optional credentials never enter repr or logs.
    """

    model_config = SettingsConfigDict(
        env_prefix="HARUKA_", extra="forbid", frozen=True, hide_input_in_errors=True
    )

    app_env: Literal["dev", "test", "staging", "production"]
    instance_id: str = Field(pattern=r"^haruka-[a-z0-9][a-z0-9-]{0,62}$")
    public_base_url: str
    allowed_origins: tuple[str, ...] = ()
    release: str = Field(default="0.1.0", pattern=r"^[a-zA-Z0-9._-]{1,64}$")
    infrastructure_enabled: bool = False
    resource_profile: Literal["core", "jobs"] = "jobs"
    database_url: SecretStr | None = None
    redis_url: SecretStr | None = None
    resource_namespace: str | None = None
    kafka_bootstrap_servers: str | None = None
    s3_endpoint: str | None = None
    s3_access_key: SecretStr | None = None
    s3_secret_key: SecretStr | None = None
    s3_bucket: str | None = None
    log_file: Path | None = None

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
        if self.log_file is not None and not self.log_file.is_absolute():
            raise ValueError("log file must be an explicit absolute path")
        if self.infrastructure_enabled:
            infrastructure = self.core_infrastructure()
            database = urlsplit(infrastructure.database_url.get_secret_value())
            redis = urlsplit(infrastructure.redis_url.get_secret_value())
            expected_database = "/haruka_dev" if self.app_env == "dev" else "/haruka_test"
            expected_redis = "/0" if self.app_env == "dev" else "/1"
            for parsed, scheme, path in (
                (database, "postgresql+asyncpg", expected_database),
                (redis, "redis", expected_redis),
            ):
                if (
                    parsed.scheme != scheme
                    or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
                    or not parsed.port
                    or not parsed.password
                    or parsed.path != path
                    or parsed.query
                    or parsed.fragment
                ):
                    raise ValueError("infrastructure target must match the local environment")
            if database.username != f"{expected_database.removeprefix('/')}_runtime":
                raise ValueError("a dedicated unprivileged runtime database account is required")
            if infrastructure.namespace != self.instance_id:
                raise ValueError("resource namespace must match the instance")
            if self.resource_profile == "core":
                return self
            jobs = self.infrastructure()
            if jobs.s3_bucket != self.instance_id:
                raise ValueError("bucket must match the instance")
            endpoint = urlsplit(jobs.s3_endpoint)
            if (
                endpoint.scheme not in {"http", "https"}
                or endpoint.hostname not in {"127.0.0.1", "localhost", "::1"}
                or not endpoint.port
                or endpoint.username
                or endpoint.password
                or endpoint.path not in {"", "/"}
                or endpoint.query
                or endpoint.fragment
            ):
                raise ValueError("object storage must use a local origin")
            for broker in jobs.kafka_bootstrap_servers.split(","):
                address = urlsplit(f"//{broker}")
                if (
                    address.hostname not in {"127.0.0.1", "localhost", "::1"}
                    or not address.port
                    or address.username
                    or address.password
                    or address.path
                    or address.query
                    or address.fragment
                ):
                    raise ValueError("Kafka bootstrap must contain local host:port entries")
        return self

    def core_infrastructure(self) -> CoreInfrastructureSettings:
        """Core startup does not require unused Kafka/MinIO credentials or clients."""
        if (
            not self.infrastructure_enabled
            or self.database_url is None
            or self.redis_url is None
            or self.resource_namespace is None
        ):
            raise ValueError("complete core infrastructure configuration is required")
        return CoreInfrastructureSettings(
            database_url=self.database_url,
            redis_url=self.redis_url,
            namespace=self.resource_namespace,
        )

    def infrastructure(self) -> InfrastructureSettings:
        """Produce a complete jobs configuration or fail before connecting."""
        if self.resource_profile != "jobs":
            raise ValueError("job resources are not enabled in the core profile")
        core = self.core_infrastructure()
        if (
            self.kafka_bootstrap_servers is None
            or self.s3_endpoint is None
            or self.s3_access_key is None
            or self.s3_secret_key is None
            or self.s3_bucket is None
            or not self.s3_access_key.get_secret_value()
            or not self.s3_secret_key.get_secret_value()
        ):
            raise ValueError("complete infrastructure configuration is required")
        return InfrastructureSettings(
            database_url=core.database_url,
            redis_url=core.redis_url,
            namespace=core.namespace,
            kafka_bootstrap_servers=self.kafka_bootstrap_servers,
            s3_endpoint=self.s3_endpoint,
            s3_access_key=self.s3_access_key,
            s3_secret_key=self.s3_secret_key,
            s3_bucket=self.s3_bucket,
        )


def load_settings(config: Path | None = None) -> Settings:
    """Load only the explicitly selected file; process environment takes precedence."""
    if config is not None and not config.is_file():
        raise ValueError("configuration file does not exist")
    return Settings(_env_file=config, _env_file_encoding="utf-8")
