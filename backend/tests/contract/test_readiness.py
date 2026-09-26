"""Readiness must recheck live dependencies after startup and recover safely."""

from functools import partial

import pytest
from fastapi.testclient import TestClient

import app.bootstrap as assembly
from app.core.settings import InfrastructureSettings, Settings
from app.main import create_app

pytestmark = pytest.mark.contract


@pytest.mark.parametrize("unavailable", ["database", "cache", "revision", "kafka", "storage"])
def test_readiness_revalidates_dependencies(
    infrastructure_settings: Settings, monkeypatch: pytest.MonkeyPatch, unavailable: str
) -> None:
    failed: set[str] = set()
    closed: list[str] = []
    schema_checks = 0
    revision_checks = 0

    class Resource:
        def __init__(self, name: str, _configuration: InfrastructureSettings) -> None:
            self.name = name

        async def check(self) -> None:
            if self.name in failed:
                raise RuntimeError("private-dependency-sentinel")

        async def aclose(self) -> None:
            closed.append(self.name)

    async def schema_check(_database: object) -> None:
        nonlocal schema_checks
        schema_checks += 1

    async def revision_check(_database: object) -> None:
        nonlocal revision_checks
        revision_checks += 1
        if "revision" in failed:
            raise RuntimeError("private-revision-sentinel")

    monkeypatch.setattr(assembly, "_check_database_schema", schema_check)
    monkeypatch.setattr(assembly, "_check_database_revision", revision_check)
    for symbol, name in (
        ("Database", "database"),
        ("Cache", "cache"),
        ("KafkaProducer", "kafka"),
        ("ObjectStorage", "storage"),
    ):
        monkeypatch.setattr(assembly, symbol, partial(Resource, name))
    with TestClient(create_app(infrastructure_settings)) as client:
        assert client.get("/health/ready").status_code == 200
        assert client.get("/health/ready").status_code == 200
        failed.add(unavailable)
        failure = client.get("/health/ready")
        assert failure.status_code == 503
        assert failure.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
        assert "sentinel" not in failure.text
        assert client.get("/health/live").status_code == 200
        failed.clear()
        assert client.get("/health/ready").status_code == 200
    assert schema_checks == 1
    assert revision_checks == 4
    assert closed == ["storage", "kafka", "cache", "database"]
