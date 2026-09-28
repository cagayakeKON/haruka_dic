"""Published language choices for the client profile and study settings."""

from pydantic import Field

from app.schemas.responses import ApiModel


class LanguageCapability(ApiModel):
    code: str
    label: str
    ui_supported: bool
    learning_supported: bool
    explanation_supported: bool
    native_supported: bool


class LanguageCapabilitiesRead(ApiModel):
    version: int = Field(ge=1)
    languages: list[LanguageCapability]
