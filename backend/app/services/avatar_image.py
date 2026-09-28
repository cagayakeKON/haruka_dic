"""Decode an owner avatar and publish a square JPEG with no source metadata.

The published bytes are the only image this service returns. Callers must not
store or serve the original upload.
"""

import asyncio
import io
import multiprocessing
from base64 import b64decode
from binascii import Error as BinAsciiError
from collections.abc import Callable
from dataclasses import dataclass
from hashlib import sha256
from multiprocessing.connection import Connection

from PIL import Image, ImageOps, UnidentifiedImageError

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError

MAX_INPUT_BYTES = 5 * 1024 * 1024
MAX_OUTPUT_BYTES = 1024 * 1024
MAX_EDGE = 4096
OUTPUT_EDGE = 512
MAX_IMAGE_BASE64_CHARS = (MAX_INPUT_BYTES + 2) // 3 * 4
MAX_COMPLETE_BODY = MAX_IMAGE_BASE64_CHARS + 512
VALIDATION_PROFILE = "avatar-image-v1"
PROCESSOR_VERSION = "avatar-jpeg-square-v1"
_FORMATS = {
    "jpeg": "JPEG",
    "png": "PNG",
    "webp": "WEBP",
}
_PROCESSOR_SLOTS = asyncio.Semaphore(2)
_PROCESSING_TIMEOUT_SECONDS = 5.0


@dataclass(frozen=True)
class PublishedAvatar:
    content: bytes
    width: int
    sha256: bytes


def decode_image_base64(value: str) -> bytes:
    """Decode one standard-base64 image. The HTTP body stays JSON."""
    try:
        raw = b64decode(value, validate=True)
    except BinAsciiError:
        raise AppError(ErrorCode.INPUT_INVALID) from None
    if len(raw) > MAX_INPUT_BYTES:
        raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
    if not raw:
        raise AppError(ErrorCode.INPUT_INVALID)
    return raw


async def publish_avatar_bounded(data: bytes, *, declared_format: str) -> PublishedAvatar:
    """Decode in a disposable process; timeout kills the process before freeing its slot."""
    try:
        await asyncio.wait_for(_PROCESSOR_SLOTS.acquire(), timeout=0.25)
    except TimeoutError:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    try:
        future = asyncio.create_task(asyncio.to_thread(run_avatar_process, data, declared_format))
    except Exception:
        _PROCESSOR_SLOTS.release()
        raise
    future.add_done_callback(lambda _completed: _PROCESSOR_SLOTS.release())
    return await asyncio.shield(future)


def _image_worker(
    connection: Connection,
    data: bytes,
    declared_format: str,
    processor: Callable[..., PublishedAvatar],
) -> None:
    try:
        connection.send(("ok", processor(data, declared_format=declared_format)))
    except AppError as error:
        connection.send(("error", error.code))
    except Exception:
        connection.send(("error", ErrorCode.SERVICE_UNAVAILABLE))
    finally:
        connection.close()


def run_avatar_process(
    data: bytes,
    declared_format: str,
    *,
    processor: Callable[..., PublishedAvatar] | None = None,
    timeout_seconds: float = _PROCESSING_TIMEOUT_SECONDS,
) -> PublishedAvatar:
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_image_worker,
        args=(sender, data, declared_format, processor or publish_avatar),
    )
    try:
        process.start()
        sender.close()
        if not receiver.poll(timeout_seconds):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        kind, value = receiver.recv()
        if kind == "error" and isinstance(value, ErrorCode):
            raise AppError(value)
        if kind != "ok" or not isinstance(value, PublishedAvatar):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        return value
    except (EOFError, OSError):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    finally:
        if process.is_alive():
            process.terminate()
            process.join(timeout=1)
            if process.is_alive():
                process.kill()
        if process.pid is not None:
            process.join(timeout=1)
        receiver.close()
        sender.close()


def publish_avatar(data: bytes, *, declared_format: str) -> PublishedAvatar:
    """Reject unsupported or oversized input, then return a metadata-free JPEG."""
    if len(data) > MAX_INPUT_BYTES:
        raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
    detected = _detect(data)
    if detected != declared_format:
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)
    Image.MAX_IMAGE_PIXELS = MAX_EDGE * MAX_EDGE
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format != _FORMATS[detected]:
                raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)
            if (
                image.width > MAX_EDGE
                or image.height > MAX_EDGE
                or image.width < 1
                or image.height < 1
            ):
                raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
            if getattr(image, "n_frames", 1) > 1 or getattr(image, "is_animated", False):
                raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)
            image.getpixel((0, 0))
            square = _square_rgb(ImageOps.exif_transpose(image))
            content = _encode(square)
            width = square.width
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError):
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED) from None
    return PublishedAvatar(content=content, width=width, sha256=sha256(content).digest())


def _detect(data: bytes) -> str:
    if data.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if len(data) >= 12 and data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp"
    raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)


def _encode(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=85, optimize=True)
    content = buffer.getvalue()
    if (
        len(content) > MAX_OUTPUT_BYTES
        or not content.startswith(b"\xff\xd8\xff")
        or image.width != image.height
        or not 1 <= image.width <= OUTPUT_EDGE
    ):
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED)
    return content


def _square_rgb(image: Image.Image) -> Image.Image:
    if image.mode in {"RGBA", "LA"} or (image.mode == "P" and "transparency" in image.info):
        rgba = image.convert("RGBA")
        flattened = Image.new("RGB", rgba.size, (255, 255, 255))
        flattened.paste(rgba, mask=rgba.getchannel("A"))
        prepared = flattened
    else:
        prepared = image.convert("RGB")
    side = min(prepared.width, prepared.height)
    left = (prepared.width - side) // 2
    top = (prepared.height - side) // 2
    cropped = prepared.crop((left, top, left + side, top + side))
    if side > OUTPUT_EDGE:
        edge = (OUTPUT_EDGE, OUTPUT_EDGE)
        return cropped.resize(edge, Image.Resampling.LANCZOS)  # pyright: ignore[reportUnknownMemberType]
    return cropped
