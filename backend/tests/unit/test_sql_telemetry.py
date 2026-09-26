"""SQL telemetry emits bounded correlation without SQL text or bind values."""

import asyncio
import json
import logging
import sqlite3
from pathlib import Path
from typing import cast
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine.interfaces import DBAPIConnection
from sqlalchemy.exc import OperationalError
from sqlalchemy.exc import TimeoutError as PoolTimeoutError
from sqlalchemy.util.concurrency import greenlet_spawn

from app.core.logging import SafeJsonFormatter
from app.core.settings import Settings
from app.core.sql_telemetry import TelemetryAsyncQueuePool, install_sql_telemetry
from app.domain.correlation import (
    audience_context,
    operation_id_context,
    request_id_context,
    user_id_context,
)


def test_sql_success_and_failure_keep_only_fingerprint_and_duration(
    caplog: pytest.LogCaptureFixture,
) -> None:
    settings = Settings.model_construct(
        app_env="test", instance_id="haruka-test-" + "a" * 32, release="test"
    )
    formatter = SafeJsonFormatter(settings, "api")
    engine = create_engine("sqlite+pysqlite:///:memory:")
    install_sql_telemetry(
        engine, database_name="haruka_test", application_name=settings.instance_id
    )
    request_id = uuid4()
    operation_id = uuid4()
    user_id = uuid4()
    request_token = request_id_context.set(request_id)
    operation_token = operation_id_context.set(operation_id)
    user_token = user_id_context.set(user_id)
    audience_token = audience_context.set("client")
    try:
        with (
            caplog.at_level(logging.INFO, logger="haruka.database"),
            engine.connect() as connection,
        ):
            connection.execute(text("SELECT :value"), {"value": "secret-sentinel-value"})
            with pytest.raises(OperationalError):
                connection.execute(
                    text("SELECT * FROM missing_private_table WHERE key=:value"),
                    {"value": "secret-sentinel-value"},
                )
        records = [
            record
            for record in caplog.records
            if record.name == "haruka.database"
            and record.msg in {"database.query.completed", "database.query.failed"}
        ]
        assert [record.msg for record in records] == [
            "database.query.completed",
            "database.query.failed",
        ]
        for record in records:
            output = formatter.format(record)
            payload = json.loads(output)
            assert payload["request_id"] == str(request_id)
            assert payload["operation_id"] == str(operation_id)
            assert payload["user_id"] == str(user_id)
            assert payload["audience"] == "client"
            assert payload["instance_id"] == settings.instance_id
            assert payload["database_name"] == "haruka_test"
            assert payload["application_name"] == settings.instance_id
            assert payload["statement_kind"] == "SELECT"
            assert len(payload["sql_fingerprint"]) == 32
            assert payload["duration_ms"] >= 0
            assert "secret-sentinel-value" not in output
            assert "missing_private_table" not in output
            assert "parameters" not in output
    finally:
        audience_context.reset(audience_token)
        user_id_context.reset(user_token)
        operation_id_context.reset(operation_token)
        request_id_context.reset(request_token)
        engine.dispose()


def test_sql_diagnostic_fields_reject_untrusted_values() -> None:
    settings = Settings.model_construct(
        app_env="test", instance_id="haruka-test-" + "b" * 32, release="test"
    )
    formatter = SafeJsonFormatter(settings, "api")
    record = logging.makeLogRecord(
        {
            "name": "haruka.database",
            "levelno": logging.WARNING,
            "levelname": "WARNING",
            "msg": "database.query.failed",
            "database_name": "another_database",
            "application_name": "untrusted-app",
            "backend_pid": -1,
            "sqlstate": "unsafe-content",
        }
    )
    output = formatter.format(record)
    payload = json.loads(output)
    assert all(
        name not in payload
        for name in ("database_name", "application_name", "backend_pid", "sqlstate")
    )
    assert "unsafe-content" not in output

    valid_record = logging.makeLogRecord(
        {
            "name": "haruka.database",
            "levelno": logging.WARNING,
            "levelname": "WARNING",
            "msg": "database.query.failed",
            "database_name": "haruka_test",
            "application_name": settings.instance_id,
            "backend_pid": 12345,
            "sqlstate": "42P01",
        }
    )
    payload = json.loads(formatter.format(valid_record))
    assert payload["database_name"] == "haruka_test"
    assert payload["application_name"] == settings.instance_id
    assert payload["backend_pid"] == 12345
    assert payload["sqlstate"] == "42P01"


def test_connection_failure_and_rollback_are_classified_without_driver_text(
    caplog: pytest.LogCaptureFixture, tmp_path: Path
) -> None:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    install_sql_telemetry(engine)
    with caplog.at_level(logging.INFO, logger="haruka.database"), engine.connect() as connection:
        transaction = connection.begin()
        connection.execute(text("SELECT 1"))
        transaction.rollback()
    assert any(record.msg == "database.transaction.rolled_back" for record in caplog.records)
    engine.dispose()

    invalid = tmp_path / "not-created" / "private.sqlite"
    failing_engine = create_engine("sqlite+pysqlite:///" + invalid.as_posix())
    install_sql_telemetry(failing_engine)
    with caplog.at_level(logging.INFO, logger="haruka.database"), pytest.raises(OperationalError):
        failing_engine.connect()
    failures = [record for record in caplog.records if record.msg == "database.connection.failed"]
    assert failures
    assert "private.sqlite" not in str(failures[0].__dict__)
    failing_engine.dispose()


def test_pool_checkout_timeout_is_safe_connection_failure(
    caplog: pytest.LogCaptureFixture,
) -> None:
    pool = TelemetryAsyncQueuePool(
        lambda: cast(DBAPIConnection, sqlite3.connect(":memory:")),
        pool_size=1,
        max_overflow=0,
        timeout=0.02,
    )

    async def exhaust() -> None:
        held = await greenlet_spawn(pool.connect)
        try:
            with pytest.raises(PoolTimeoutError):
                await greenlet_spawn(pool.connect)
        finally:
            await greenlet_spawn(held.close)

    with caplog.at_level(logging.INFO, logger="haruka.database"):
        asyncio.run(exhaust())
    failures = [record for record in caplog.records if record.msg == "database.connection.failed"]
    assert len(failures) == 1
    assert "QueuePool limit" not in str(failures[0].__dict__)
    pool.dispose()
