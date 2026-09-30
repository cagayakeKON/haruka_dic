"""Explicit configuration; importing this module never reads the environment."""

import binascii
import re
from base64 import b64decode
from pathlib import Path
from typing import Literal, Self, TypedDict, Unpack
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.domain.email_address import normalize_email


class SettingsInput(TypedDict, total=False):
    credential_keyring: dict[str, SecretStr]
    credential_encryption_key_version: str
    model_execution_mode: Literal["disabled", "fake", "live"]
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
    test_schema: str | None
    auth_signing_key: SecretStr | None
    auth_digest_key: SecretStr | None
    mail_encryption_key: SecretStr | None
    auth_signing_key_version: str
    auth_digest_key_version: str
    mail_encryption_key_version: str
    mail_delivery_enabled: bool
    smtp_host: str | None
    smtp_port: int
    smtp_from: str | None
    smtp_starttls: bool
    smtp_username: str | None
    smtp_password: SecretStr | None
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
    test_schema: str | None = None


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
    test_schema: str | None = None
    auth_signing_key: SecretStr | None = None
    auth_digest_key: SecretStr | None = None
    mail_encryption_key: SecretStr | None = None
    auth_signing_key_version: str = "v1"
    auth_digest_key_version: str = "v1"
    mail_encryption_key_version: str = "v1"
    mail_delivery_enabled: bool = False
    smtp_host: str | None = None
    smtp_port: int = Field(default=25, ge=1, le=65535)
    smtp_from: str | None = None
    smtp_starttls: bool = True
    smtp_username: str | None = None
    smtp_password: SecretStr | None = None
    kafka_bootstrap_servers: str | None = None
    s3_endpoint: str | None = None
    s3_access_key: SecretStr | None = None
    s3_secret_key: SecretStr | None = None
    s3_bucket: str | None = None
    log_file: Path | None = None
    credential_keyring: dict[str, SecretStr] = Field(default_factory=dict, repr=False)
    credential_encryption_key_version: str = "v1"
    model_execution_mode: Literal["disabled", "fake", "live"] = "disabled"

    def __init__(self, **values: Unpack[SettingsInput]) -> None:
        # Settings accepts absent constructor fields because environment/file
        # sources supply them. Keep this dynamic boundary explicitly validated.
        super().__init__(**values)

    @model_validator(mode="after")
    def validate_environment(self) -> Self:
        if self.model_execution_mode == "fake" and self.app_env not in {"dev", "test"}:
            raise ValueError("fake provider assembly is limited to isolated environments")
        if self.credential_keyring:
            if self.credential_encryption_key_version not in self.credential_keyring:
                raise ValueError("active credential encryption key is absent")
            for version, secret in self.credential_keyring.items():
                if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", version):
                    raise ValueError("credential encryption version is invalid")
                try:
                    raw = b64decode(secret.get_secret_value(), altchars=b"-_", validate=True)
                except (ValueError, binascii.Error):
                    raise ValueError("credential encryption encoding is invalid") from None
                if len(raw) != 32:
                    raise ValueError("credential encryption key length is invalid")
        if self.app_env not in {"dev", "test"}:
            raise ValueError("runtime dependencies are not yet available for this environment")
        prefix = "haruka-local-" if self.app_env == "dev" else "haruka-test-"
        if not self.instance_id.startswith(prefix):
            raise ValueError("instance does not match the selected isolated environment")
        if self.test_schema is not None and (
            self.app_env != "test"
            or not re.fullmatch(r"haruka_migration_test_[a-f0-9]{32}", self.test_schema)
        ):
            raise ValueError("runtime test schema must be a random isolated test schema")
        for version in (
            self.auth_signing_key_version,
            self.auth_digest_key_version,
            self.mail_encryption_key_version,
        ):
            if re.fullmatch(r"[A-Za-z0-9_-]{1,64}", version) is None:
                raise ValueError("security key version is invalid")
        for value, expected_length in (
            (self.auth_signing_key, 32),
            (self.auth_digest_key, 32),
            (self.mail_encryption_key, 32),
        ):
            if value is None:
                continue
            try:
                raw = b64decode(value.get_secret_value(), altchars=b"-_", validate=True)
            except (binascii.Error, ValueError):
                raise ValueError("security key encoding is invalid") from None
            if len(raw) != expected_length:
                raise ValueError("security key length is invalid")
        if self.mail_delivery_enabled:
            if self.smtp_host not in {"localhost", "127.0.0.1", "::1"}:
                raise ValueError("mail transport must be explicit loopback until deployment review")
            try:
                valid_from = normalize_email(self.smtp_from or "")[0] == self.smtp_from
            except ValueError:
                valid_from = False
            if not valid_from:
                raise ValueError("mail sender identity is invalid")
            if (self.smtp_username is None) != (self.smtp_password is None):
                raise ValueError("mail authentication settings must be paired")
            if self.mail_encryption_key is None or self.auth_digest_key is None:
                raise ValueError("mail delivery requires challenge and payload keys")
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
            test_schema=self.test_schema,
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
            test_schema=core.test_schema,
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
