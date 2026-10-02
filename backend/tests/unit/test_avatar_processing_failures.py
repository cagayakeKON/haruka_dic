"""Untrusted avatar containers and worker errors keep only sanitized output."""

import asyncio
import base64
import io
from collections.abc import Callable
from hashlib import sha256
from unittest.mock import MagicMock

import pytest
from PIL import Image

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.services import avatar_image

pytestmark = pytest.mark.unit


def _unexpected_processor(_data: bytes, *, declared_format: str) -> avatar_image.PublishedAvatar:
    raise ValueError("private input must not be transported")


def _denied_processor(_data: bytes, *, declared_format: str) -> avatar_image.PublishedAvatar:
    raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)


@pytest.mark.parametrize(
    "processor,code",
    [
        (_unexpected_processor, ErrorCode.SERVICE_UNAVAILABLE),
        (_denied_processor, ErrorCode.MEDIA_TYPE_UNSUPPORTED),
    ],
)
def test_disposable_worker_reports_only_safe_code_and_recovers(
    processor: Callable[..., avatar_image.PublishedAvatar], code: ErrorCode
) -> None:
    with pytest.raises(AppError) as error:
        avatar_image.run_avatar_process(b"synthetic bytes", "png", processor=processor)
    assert error.value.code == code
    assert "private input" not in str(error.value)
    image = Image.new("RGB", (2, 2), "blue")
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    result = avatar_image.run_avatar_process(buffer.getvalue(), "png")
    assert result.sha256 == sha256(result.content).digest()


@pytest.mark.parametrize(
    "value,code",
    [
        ("", ErrorCode.INPUT_INVALID),
        ("invalid!", ErrorCode.INPUT_INVALID),
        (
            base64.b64encode(b"x" * (avatar_image.MAX_INPUT_BYTES + 1)).decode(),
            ErrorCode.PAYLOAD_TOO_LARGE,
        ),
    ],
    ids=["empty", "non-base64", "oversized"],
)
def test_base64_boundary_rejects_unusable_and_oversized_bytes(value: str, code: ErrorCode) -> None:
    with pytest.raises(AppError) as error:
        avatar_image.decode_image_base64(value)
    assert error.value.code == code


@pytest.mark.parametrize("mode", ["RGBA", "LA", "P"])
def test_transparent_source_is_flattened_to_rgb_white_without_metadata(mode: str) -> None:
    image = Image.new(mode, (4, 4))
    if mode == "P":
        image.info["transparency"] = 0
    image.info["comment"] = b"private metadata"
    raw = io.BytesIO()
    image.save(raw, format="PNG")
    result = avatar_image.publish_avatar(raw.getvalue(), declared_format="png")
    with Image.open(io.BytesIO(result.content)) as published:
        assert published.mode == "RGB"
        assert published.getpixel((0, 0)) == (255, 255, 255)
        assert "comment" not in published.info
        assert not published.getexif()


def test_truncated_supported_magic_is_rejected_by_real_decoder() -> None:
    with pytest.raises(AppError) as error:
        avatar_image.publish_avatar(b"\x89PNG\r\n\x1a\nnot a container", declared_format="png")
    assert error.value.code == ErrorCode.MEDIA_TYPE_UNSUPPORTED


def test_input_size_is_enforced_before_unsupported_magic_decode() -> None:
    with pytest.raises(AppError) as error:
        avatar_image.publish_avatar(
            b"x" * (avatar_image.MAX_INPUT_BYTES + 1), declared_format="png"
        )
    assert error.value.code == ErrorCode.PAYLOAD_TOO_LARGE


@pytest.mark.asyncio
async def test_processing_slot_saturation_does_not_start_worker_and_recovers(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    slots = asyncio.Semaphore(0)
    worker = MagicMock(side_effect=AssertionError("must not run when full"))
    monkeypatch.setattr(avatar_image, "_PROCESSOR_SLOTS", slots)
    monkeypatch.setattr(avatar_image, "run_avatar_process", worker)
    with pytest.raises(AppError) as error:
        await avatar_image.publish_avatar_bounded(b"synthetic", declared_format="png")
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    worker.assert_not_called()
    slots.release()
    result = avatar_image.PublishedAvatar(content=b"safe", width=1, sha256=sha256(b"safe").digest())
    worker.side_effect = None
    worker.return_value = result
    assert await avatar_image.publish_avatar_bounded(b"synthetic", declared_format="png") == result
    await asyncio.sleep(0)
    assert not slots.locked()
