"""The bounded process transport preserves each admitted format's actual evidence."""

from io import BytesIO

import pytest
from PIL import Image

from app.adapters.source_validation import validate_bounded
from app.domain.errors import AppError
from tests.unit.test_material_sources import epub, pdf

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


@pytest.mark.parametrize("kind", ["novel", "textbook", "exam"])
@pytest.mark.parametrize("format", ["md", "epub", "pdf"])
async def test_process_preserves_registered_source_admission(kind: str, format: str) -> None:
    raw = {
        "md": "これは日本語の小説です。今日はとてもいい天気です。".encode(),
        "epub": epub(),
        "pdf": pdf(),
    }[format]
    result = await validate_bounded(raw, format, kind)
    assert result.format == format and result.language == (None if format == "pdf" else "ja")


@pytest.mark.parametrize("format", ["png", "jpeg", "webp"])
async def test_process_preserves_verified_image_dimensions(format: str) -> None:
    output = BytesIO()
    Image.new("RGB", (24, 18)).save(output, format=format.upper())
    result = await validate_bounded(output.getvalue(), format, "exam")
    assert (result.format, result.width, result.height, result.language) == (format, 24, 18, None)


async def test_process_returns_only_registered_safe_failure() -> None:
    with pytest.raises(AppError) as error:
        await validate_bounded(b"private bad bytes", "pdf", "exam")
    assert error.value.code.value == "MEDIA_TYPE_UNSUPPORTED"
