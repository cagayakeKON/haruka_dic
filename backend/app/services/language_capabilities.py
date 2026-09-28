"""Versioned, public-safe language catalogue for authenticated clients."""

from app.schemas.language_capabilities import LanguageCapabilitiesRead, LanguageCapability


def read_catalogue() -> LanguageCapabilitiesRead:
    return LanguageCapabilitiesRead(
        version=1,
        languages=[
            LanguageCapability(
                code="zh-Hans",
                label="简体中文",
                ui_supported=True,
                learning_supported=False,
                explanation_supported=True,
                native_supported=True,
            ),
            LanguageCapability(
                code="zh-Hant",
                label="繁體中文",
                ui_supported=False,
                learning_supported=False,
                explanation_supported=False,
                native_supported=True,
            ),
            LanguageCapability(
                code="ja",
                label="日本語",
                ui_supported=False,
                learning_supported=True,
                explanation_supported=True,
                native_supported=True,
            ),
            LanguageCapability(
                code="en",
                label="English",
                ui_supported=False,
                learning_supported=True,
                explanation_supported=True,
                native_supported=True,
            ),
            LanguageCapability(
                code="ko",
                label="한국어",
                ui_supported=False,
                learning_supported=False,
                explanation_supported=False,
                native_supported=True,
            ),
        ],
    )
