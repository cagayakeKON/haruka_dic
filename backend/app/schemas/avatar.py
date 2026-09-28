"""Avatar upload declaration. The image itself is base64 inside JSON, not a URL."""

import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.responses import ApiModel
from app.services.avatar_image import MAX_IMAGE_BASE64_CHARS, MAX_INPUT_BYTES

AvatarFormat = Literal["jpeg", "png", "webp"]
_BASE64 = re.compile(r"^[A-Za-z0-9+/]+={0,2}$")


def _exact_int(value: object) -> int:
    if type(value) is not int:
        raise ValueError("Expected an integer")
    return value


class AvatarUploadIntentCreate(ApiModel):
    declared_format: AvatarFormat
    expected_size_bytes: int = Field(ge=1, le=MAX_INPUT_BYTES)
    expected_sha256: str = Field(min_length=64, max_length=64)

    @field_validator("expected_size_bytes", mode="before")
    @classmethod
    def exact_size(cls, value: object) -> int:
        return _exact_int(value)

    @field_validator("expected_sha256")
    @classmethod
    def lowercase_sha256(cls, value: str) -> str:
        if len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
            raise ValueError("expected_sha256 must be 64 lowercase hex characters")
        return value


class AvatarUploadIntentRead(ApiModel):
    id: UUID
    expires_at: datetime
    max_size_bytes: int
    accepted_formats: list[AvatarFormat]


class AvatarUploadComplete(ApiModel):
    expected_revision: int = Field(ge=1)
    image_base64: str = Field(min_length=4, max_length=MAX_IMAGE_BASE64_CHARS)

    @field_validator("expected_revision", mode="before")
    @classmethod
    def exact_revision(cls, value: object) -> int:
        return _exact_int(value)

    @field_validator("image_base64")
    @classmethod
    def standard_base64(cls, value: str) -> str:
        if _BASE64.fullmatch(value) is None:
            raise ValueError("image_base64 must be standard base64 without a URL or data prefix")
        return value


class AvatarDelete(ApiModel):
    expected_revision: int = Field(ge=1)

    @field_validator("expected_revision", mode="before")
    @classmethod
    def exact_revision(cls, value: object) -> int:
        return _exact_int(value)
