"""Function-scoped configuration; tests do not contact infrastructure or providers."""

import pytest
from pydantic import SecretStr

from app.core.settings import Settings


@pytest.fixture
def settings() -> Settings:
    return Settings(
        app_env="test",
        instance_id="haruka-test-contracts",
        public_base_url="http://127.0.0.1:8000",
        allowed_origins=("http://localhost:8080",),
    )


@pytest.fixture
def infrastructure_settings() -> Settings:
    """Synthetic configuration only; unit tests replace resource factories."""
    return Settings(
        app_env="test",
        instance_id="haruka-test-unit",
        public_base_url="http://127.0.0.1:8000",
        infrastructure_enabled=True,
        database_url=SecretStr(
            "postgresql+asyncpg://runtime:test-only@127.0.0.1:15432/haruka_test"
        ),
        redis_url=SecretStr("redis://:test-only@127.0.0.1:16379/1"),
        resource_namespace="haruka-test-unit",
        kafka_bootstrap_servers="127.0.0.1:19092",
        s3_endpoint="http://127.0.0.1:19100",
        s3_access_key=SecretStr("test-only-access"),
        s3_secret_key=SecretStr("test-only-secret"),
        s3_bucket="haruka-test-unit",
    )
