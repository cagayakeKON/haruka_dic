"""Bounded source admission, independent of reading structures and model calls."""

import re
import warnings
import zipfile
from dataclasses import dataclass
from io import BytesIO
from pathlib import PurePosixPath
from xml.etree import ElementTree

from PIL import Image
from pypdf import PdfReader
from pypdf.generic import ArrayObject, DictionaryObject, IndirectObject

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError

MAX_SOURCE_BYTES = 32 * 1024 * 1024
QUOTA_BYTES = 256 * 1024 * 1024
UPLOAD_TTL_SECONDS = 900
FORMATS = {
    "novel": ("md", "epub", "pdf"),
    "textbook": ("md", "epub", "pdf"),
    "exam": ("md", "epub", "pdf", "png", "jpeg", "webp"),
}
MEDIA_TYPES = {
    "md": "text/markdown",
    "epub": "application/epub+zip",
    "pdf": "application/pdf",
    "png": "image/png",
    "jpeg": "image/jpeg",
    "webp": "image/webp",
}
FORMAT_MAX_BYTES = {
    key: min(MAX_SOURCE_BYTES, limit)
    for key, limit in {
        "md": 20_000_000,
        "epub": 50_000_000,
        "pdf": 80_000_000,
        "png": 20_000_000,
        "jpeg": 20_000_000,
        "webp": 20_000_000,
    }.items()
}


@dataclass(frozen=True)
class ValidatedSource:
    format: str
    language: str | None
    width: int | None = None
    height: int | None = None


def _language(text: str) -> str | None:
    """Conservative deterministic evidence; uncertainty creates a blocking issue."""
    kana = len(re.findall(r"[\u3040-\u30ff]", text))
    latin = len(re.findall(r"[A-Za-z]", text))
    other_letters = len(re.findall(r"[\u0400-\u052f\u0600-\u06ff]", text))
    if kana >= 5 and kana >= latin / 5 and other_letters == 0:
        return "ja"
    if other_letters > 5:
        return "unsupported"
    # Alphabet alone cannot distinguish English from German/French/Spanish.
    # Without a dedicated reliable language model, Latin sources need explicit
    # confirmation at the persisted input checkpoint.
    return None


def _pdf_safety(reader: PdfReader) -> None:
    forbidden = {
        "/JS",
        "/JavaScript",
        "/Launch",
        "/EmbeddedFiles",
        "/EF",
        "/OpenAction",
        "/AA",
        "/RichMedia",
        "/XFA",
        "/URI",
        "/SubmitForm",
        "/ImportData",
    }
    seen: set[tuple[int, int]] = set()
    count = 0

    def visit(value: object, depth: int) -> None:
        nonlocal count
        count += 1
        if count > 20_000 or depth > 40:
            raise ValueError("bounded PDF graph")
        if isinstance(value, IndirectObject):
            identity = (value.idnum, value.generation)
            if identity in seen:
                return
            seen.add(identity)
            visit(value.get_object(), depth + 1)
        elif isinstance(value, DictionaryObject):
            for key, child in value.items():
                if str(key) in forbidden or (isinstance(child, str) and child in forbidden):
                    raise ValueError("active PDF content")
                visit(child, depth + 1)
        elif isinstance(value, ArrayObject):
            for child in value:
                visit(child, depth + 1)

    visit(reader.trailer, 0)


def _xml(raw: bytes) -> ElementTree.Element:
    # The admitted EPUB XML encoding is UTF-8. Scan decoded text rather than
    # raw ASCII bytes so alternate encodings cannot hide entity declarations.
    text = raw.decode("utf-8-sig")
    if "\x00" in text or "<!DOCTYPE" in text.upper() or "<!ENTITY" in text.upper():
        raise ValueError("unsafe XML")
    return ElementTree.fromstring(text)  # noqa: S314 -- UTF-8 entity declarations rejected above


def validate_source(raw: bytes, declared: str, material_type: str) -> ValidatedSource:
    if declared not in FORMATS.get(material_type, ()):
        raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
    if not raw or len(raw) > FORMAT_MAX_BYTES[declared]:
        raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
    try:
        if declared == "md":
            text = raw.decode("utf-8-sig")
            if "\x00" in text or not text.strip() or raw.startswith((b"%PDF-", b"PK\x03\x04")):
                raise ValueError("not UTF-8 text")
            return ValidatedSource(declared, _language(text[:100_000]))
        if declared == "epub":
            with zipfile.ZipFile(BytesIO(raw)) as archive:
                entries = archive.infolist()
                if not 1 <= len(entries) <= 2000 or len({e.filename for e in entries}) != len(
                    entries
                ):
                    raise ValueError("invalid archive count")
                if sum(e.file_size for e in entries) > 64 * 1024 * 1024:
                    raise ValueError("expanded archive too large")
                for entry in entries:
                    path = PurePosixPath(entry.filename)
                    if (
                        path.is_absolute()
                        or ".." in path.parts
                        or "\\" in entry.filename
                        or entry.flag_bits & 1
                        or entry.file_size > 8 * 1024 * 1024
                        or entry.file_size > max(1, entry.compress_size) * 200
                    ):
                        raise ValueError("unsafe archive member")
                if archive.read("mimetype") != b"application/epub+zip":
                    raise ValueError("not EPUB")
                container = _xml(archive.read("META-INF/container.xml"))
                roots = container.findall(".//{*}rootfile")
                if len(roots) != 1:
                    raise ValueError("invalid package")
                package_path = roots[0].attrib["full-path"]
                package = _xml(archive.read(package_path))
                manifest = {
                    e.attrib["id"]: e.attrib for e in package.findall(".//{*}manifest/{*}item")
                }
                spine = package.findall(".//{*}spine/{*}itemref")
                if not spine:
                    raise ValueError("empty spine")
                samples: list[str] = []
                for ref in spine[:20]:
                    item = manifest[ref.attrib["idref"]]
                    if item.get("media-type") != "application/xhtml+xml":
                        raise ValueError("unsupported spine")
                    href = item["href"]
                    if (
                        ":" in href
                        or "?" in href
                        or "#" in href
                        or ".." in PurePosixPath(href).parts
                    ):
                        raise ValueError("external spine")
                    document = _xml(archive.read(str(PurePosixPath(package_path).parent / href)))
                    samples.append(" ".join(document.itertext())[:5000])
                return ValidatedSource(declared, _language(" ".join(samples)))
        if declared == "pdf":
            if not raw.startswith(b"%PDF-") or b"%%EOF" not in raw[-1024:]:
                raise ValueError("invalid PDF envelope")
            reader = PdfReader(BytesIO(raw), strict=True)
            if reader.is_encrypted or not 1 <= len(reader.pages) <= 500:
                raise ValueError("encrypted or over-page PDF")
            _pdf_safety(reader)
            # PDF text extraction and scanned OCR belong to later domain slices.
            return ValidatedSource(declared, None)
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(raw)) as image:
                if (
                    image.format or ""
                ).lower() != declared or image.width * image.height > 20_000_000:
                    raise ValueError("image admission")
                width, height = image.size
                image.verify()
            with Image.open(BytesIO(raw)) as image:
                image.load()  # pyright: ignore[reportUnknownMemberType] -- Pillow's stub omits pixel access return
            return ValidatedSource(declared, None, width, height)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.MEDIA_TYPE_UNSUPPORTED) from None
