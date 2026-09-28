"""Avatar bytes are re-encoded before they can be stored or returned."""

import io
import time

import httpx2 as httpx
import pytest
from PIL import Image
from pydantic import ValidationError

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.main import create_app
from app.schemas.avatar import AvatarUploadComplete, AvatarUploadIntentCreate
from app.services.avatar_image import (
    OUTPUT_EDGE,
    PublishedAvatar,
    publish_avatar,
    run_avatar_process,
)

pytestmark = pytest.mark.unit
_SHA = "a" * 64


def test_png_becomes_a_square_jpeg_without_the_source_container() -> None:
    source = _image("PNG", (40, 20))
    published = publish_avatar(source, declared_format="png")
    assert published.content.startswith(b"\xff\xd8\xff")
    assert published.width == 20
    assert len(published.sha256) == 32
    with Image.open(io.BytesIO(published.content)) as image:
        assert image.format == "JPEG"
        assert image.size == (20, 20)
        assert not image.getexif()


def test_exif_orientation_is_applied_and_removed() -> None:
    image = Image.new("RGB", (30, 10), (0, 0, 255))
    exif = Image.Exif()
    exif[274] = 6
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", exif=exif.tobytes())
    raw = buffer.getvalue()
    assert b"Exif\x00\x00" in raw
    published = publish_avatar(raw, declared_format="jpeg")
    assert published.width == 10
    assert b"Exif\x00\x00" not in published.content


def test_wide_image_is_limited_to_the_output_edge() -> None:
    published = publish_avatar(_image("PNG", (900, 600)), declared_format="png")
    assert published.width == OUTPUT_EDGE


def test_svg_gif_animation_and_oversize_edges_are_rejected() -> None:
    with pytest.raises(AppError) as svg:
        publish_avatar(b"<svg xmlns='http://www.w3.org/2000/svg'></svg>", declared_format="png")
    assert svg.value.code == ErrorCode.MEDIA_TYPE_UNSUPPORTED
    with pytest.raises(AppError) as gif:
        publish_avatar(_image("GIF", (8, 8)), declared_format="png")
    assert gif.value.code == ErrorCode.MEDIA_TYPE_UNSUPPORTED
    animated = io.BytesIO()
    frame = Image.new("RGB", (8, 8), (255, 0, 0))
    frame.save(
        animated,
        format="WEBP",
        save_all=True,
        append_images=[Image.new("RGB", (8, 8), (0, 0, 255))],
        duration=100,
    )
    with pytest.raises(AppError) as webp:
        publish_avatar(animated.getvalue(), declared_format="webp")
    assert webp.value.code == ErrorCode.MEDIA_TYPE_UNSUPPORTED
    with pytest.raises(AppError) as edge:
        publish_avatar(_image("PNG", (4097, 2)), declared_format="png")
    assert edge.value.code == ErrorCode.PAYLOAD_TOO_LARGE


def test_declared_format_must_match_the_bytes() -> None:
    png = _image("PNG", (8, 8))
    with pytest.raises(AppError) as mismatch:
        publish_avatar(png, declared_format="jpeg")
    assert mismatch.value.code == ErrorCode.MEDIA_TYPE_UNSUPPORTED
    assert publish_avatar(png, declared_format="png").width == 8


def _blocked_processor(_data: bytes, *, declared_format: str) -> PublishedAvatar:
    time.sleep(10)
    raise AssertionError(declared_format)


def test_processor_timeout_terminates_worker_and_allows_the_next_upload() -> None:
    raw = _image("PNG", (8, 8))
    with pytest.raises(AppError) as timeout:
        run_avatar_process(raw, "png", processor=_blocked_processor, timeout_seconds=0.2)
    assert timeout.value.code == ErrorCode.SERVICE_UNAVAILABLE
    assert run_avatar_process(raw, "png").width == 8


@pytest.mark.asyncio
async def test_extreme_content_length_is_rejected_before_json_parsing() -> None:
    app = create_app(schema_only=True)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test.local"
    ) as client:
        response = await client.post(
            "/api/v1/users/me/avatar-upload-intents/00000000-0000-0000-0000-000000000001/complete",
            content=b"{}",
            headers={"Content-Length": "9" * 4096, "Content-Type": "application/json"},
        )
    assert response.status_code == 413


def test_complete_json_rejects_a_url_and_accepts_base64() -> None:
    with pytest.raises(ValidationError):
        AvatarUploadComplete.model_validate(
            {"expected_revision": 1, "image_base64": "https://example.invalid/avatar.jpg"}
        )
    saved = AvatarUploadComplete.model_validate(
        {"expected_revision": 1, "image_base64": "aGVsbG8="}
    )
    assert saved.image_base64 == "aGVsbG8="


def test_intent_rejects_a_url_and_an_inexact_size() -> None:
    with pytest.raises(ValidationError):
        AvatarUploadIntentCreate.model_validate(
            {
                "declared_format": "jpeg",
                "expected_size_bytes": 12,
                "expected_sha256": _SHA,
                "source_url": "https://example.invalid/avatar.jpg",
            }
        )
    with pytest.raises(ValidationError):
        AvatarUploadIntentCreate.model_validate(
            {"declared_format": "jpeg", "expected_size_bytes": 12.0, "expected_sha256": _SHA}
        )
    saved = AvatarUploadIntentCreate.model_validate(
        {"declared_format": "png", "expected_size_bytes": 12, "expected_sha256": _SHA}
    )
    assert saved.declared_format == "png"


def _image(fmt: str, size: tuple[int, int]) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, (200, 20, 20)).save(buffer, format=fmt)
    return buffer.getvalue()
