"""Function-scoped configuration; tests do not contact infrastructure or providers."""

import pytest

from app.core.settings import Settings


@pytest.fixture
def settings() -> Settings:
    return Settings(
        app_env="test",
        instance_id="haruka-test-contracts",
        public_base_url="http://127.0.0.1:8000",
        allowed_origins=("http://localhost:8080",),
    )
