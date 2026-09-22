"""Raw input and exception values cannot enter the structured logging exit."""

import io
import json
import logging
from uuid import uuid4

import pytest

from app.core.logging import SafeJsonFormatter
from app.core.settings import Settings

pytestmark = pytest.mark.unit


def test_log_whitelist_discards_secrets_and_preserves_normal_events(settings: Settings) -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(SafeJsonFormatter(settings, "api"))
    logger = logging.Logger("isolated-test", level=logging.INFO)
    logger.addHandler(handler)
    request_id = uuid4()
    logger.info(
        "http.completed",
        extra={
            "request_id": request_id,
            "status_code": 200,
            "duration_ms": 4.25,
            "authorization": "fake-secret-sentinel",
            "body": "private-body-sentinel",
        },
    )
    try:
        raise ValueError("fake-secret-sentinel private-body-sentinel")
    except ValueError:
        logger.exception("https://private.example/?token=fake-secret-sentinel")
    output = stream.getvalue()
    assert "sentinel" not in output
    assert "private.example" not in output
    records: list[dict[str, object]] = [json.loads(line) for line in output.splitlines()]
    assert records[0]["event"] == "http.completed"
    assert records[0]["request_id"] == str(request_id)
    assert records[0]["status_code"] == 200
    assert records[1]["event"] == "library.log"
    assert "stack_frames" in records[1]
