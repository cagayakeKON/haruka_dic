"""Admission rejects active/mislabelled assets and never guesses Latin language."""

from io import BytesIO
from zipfile import ZipFile

import pytest
from PIL import Image
from pypdf import PdfWriter
from pypdf.generic import DictionaryObject, NameObject, TextStringObject

from app.domain.errors import AppError
from app.domain.material_sources import validate_source

pytestmark = pytest.mark.unit


def epub() -> bytes:
    output = BytesIO()
    with ZipFile(output, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip")
        archive.writestr(
            "META-INF/container.xml",
            '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
        )
        archive.writestr(
            "book.opf",
            '<package><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>',
        )
        archive.writestr(
            "one.xhtml",
            "<html><body>これは日本語の小説です。今日はとてもいい天気です。</body></html>",
        )
    return output.getvalue()


def pdf(*, active: bool = False) -> bytes:
    writer = PdfWriter()
    writer.add_blank_page(width=100, height=200)
    if active:
        writer.root_object[NameObject("/OpenAction")] = DictionaryObject(
            {
                NameObject("/S"): NameObject("/JavaScript"),
                NameObject("/JS"): TextStringObject("synthetic script"),
            }
        )
    output = BytesIO()
    writer.write(output)
    return output.getvalue()


@pytest.mark.parametrize("kind", ["novel", "textbook", "exam"])
@pytest.mark.parametrize("format", ["md", "epub", "pdf"])
def test_registered_type_sources_keep_reading_unpublished(kind: str, format: str) -> None:
    raw = {
        "md": "これは日本語の小説です。今日はとてもいい天気です。".encode(),
        "epub": epub(),
        "pdf": pdf(),
    }[format]
    value = validate_source(raw, format, kind)
    assert value.format == format
    assert value.language == (None if format == "pdf" else "ja")


@pytest.mark.parametrize(
    "text",
    [
        "This is an English source whose language still needs reliable verification.",
        "Dies ist ein deutscher Text mit vielen lateinischen Buchstaben und Wörtern.",
        "Este es un texto español escrito para comprobar la detección del idioma.",
        "Ceci est un texte français comportant de nombreuses lettres latines.",
    ],
)
def test_latin_script_is_not_automatic_english_admission(text: str) -> None:
    assert validate_source(text.encode(), "md", "novel").language is None


def test_third_script_cannot_be_confirmed_as_supported() -> None:
    assert (
        validate_source(
            "Это русский текст для проверки неподдерживаемого языка.".encode(), "md", "novel"
        ).language
        == "unsupported"
    )


@pytest.mark.parametrize("format", ["png", "jpeg", "webp"])
def test_exam_images_have_actual_dimensions_and_no_guessed_language(format: str) -> None:
    output = BytesIO()
    Image.new("RGB", (24, 18)).save(output, format=format.upper())
    value = validate_source(output.getvalue(), format, "exam")
    assert (value.width, value.height, value.language) == (24, 18, None)
    with pytest.raises(AppError):
        validate_source(output.getvalue(), format, "novel")


@pytest.mark.parametrize(
    "raw,format",
    [
        (b"%PDF-1.7 invalid %%EOF", "pdf"),
        (b"%PDF-1.7 body", "md"),
        (b"broken zip", "epub"),
        (pdf(active=True), "pdf"),
    ],
)
def test_fake_formats_and_active_pdf_are_rejected(raw: bytes, format: str) -> None:
    with pytest.raises(AppError):
        validate_source(raw, format, "novel")


def test_epub_traversal_and_entities_are_rejected() -> None:
    output = BytesIO()
    with ZipFile(output, "w") as archive:
        archive.writestr("../outside", "private")
    with pytest.raises(AppError):
        validate_source(output.getvalue(), "epub", "novel")


@pytest.mark.parametrize("encoding", ["utf-8", "utf-16", "utf-16-le", "utf-16-be"])
def test_epub_xml_entities_are_rejected_in_alternate_encodings(encoding: str) -> None:
    output = BytesIO()
    unsafe = '<?xml version="1.0"?><!DOCTYPE root [<!ENTITY public "synthetic text">]><root>&public;</root>'
    with ZipFile(output, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip")
        archive.writestr("META-INF/container.xml", unsafe.encode(encoding))
    with pytest.raises(AppError):
        validate_source(output.getvalue(), "epub", "novel")
