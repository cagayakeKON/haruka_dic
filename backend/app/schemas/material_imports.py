"""Owner-scoped source uploads and safe material catalog contracts."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator, model_validator

from app.schemas.responses import ApiModel

MaterialType = Literal["novel", "textbook", "exam"]
MaterialLanguage = Literal["ja", "en"]
SourceFormat = Literal["md", "epub", "pdf", "png", "jpeg", "webp"]
ImportStatus = Literal[
    "awaiting_upload", "verifying", "accepted", "cancelled", "rejected", "expired"
]


class MaterialSourceFile(ApiModel):
    filename: str = Field(min_length=1, max_length=255)
    format: SourceFormat
    size_bytes: int = Field(gt=0, strict=True)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")

    @field_validator("filename")
    @classmethod
    def safe_filename(cls, value: str) -> str:
        if any(ord(char) < 32 for char in value) or "/" in value or "\\" in value:
            raise ValueError("A display filename is required")
        return value


class MaterialRequestedStages(ApiModel):
    extract: Literal[True] = True
    analyze: Literal[False] = False

    @field_validator("extract", "analyze", mode="before")
    @classmethod
    def explicit_boolean(cls, value: object) -> object:
        if type(value) is not bool:
            raise ValueError("Requested stages require explicit booleans")
        return value


class MaterialImportCreate(ApiModel):
    schema_version: Literal[1] = 1
    material_type: MaterialType
    title: str | None = Field(default=None, min_length=1, max_length=200)
    language: MaterialLanguage
    file: MaterialSourceFile | None = None
    source_material_id: UUID | None = None
    requested_stages: MaterialRequestedStages = Field(default_factory=MaterialRequestedStages)

    @field_validator("title")
    @classmethod
    def meaningful_title(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("A nonblank title is required")
        return value.strip() if value is not None else None

    @model_validator(mode="after")
    def type_format_contract(self) -> "MaterialImportCreate":
        if (self.file is None) == (self.source_material_id is None):
            raise ValueError("Exactly one new file or owned source material is required")
        if (
            self.file is not None
            and self.material_type != "exam"
            and self.file.format not in {"md", "epub", "pdf"}
        ):
            raise ValueError("The selected material type does not support this format")
        return self


class StagingUploadRead(ApiModel):
    id: UUID
    method: Literal["PUT"] = "PUT"
    url: str
    headers: dict[str, str]
    expires_at: datetime


class MaterialImportRead(ApiModel):
    id: UUID
    revision: int = Field(ge=1)
    material_type: MaterialType
    language: MaterialLanguage
    status: ImportStatus
    upload: StagingUploadRead | None = None
    material_id: UUID | None = None
    job_id: UUID | None = None
    error_code: str | None = None
    expires_at: datetime

    @model_validator(mode="after")
    def accepted_references(self) -> "MaterialImportRead":
        accepted = self.status == "accepted"
        if accepted != (self.material_id is not None and self.job_id is not None):
            raise ValueError("Only an accepted source has committed material and job references")
        if not accepted and (self.material_id is not None or self.job_id is not None):
            raise ValueError("Unaccepted source references must be absent")
        if self.upload is not None and self.status != "awaiting_upload":
            raise ValueError("Only an awaiting source can expose a staging capability")
        return self


class UploadComplete(ApiModel):
    expected_revision: int = Field(ge=1)


class MaterialTitlePatch(ApiModel):
    expected_revision: int = Field(ge=1)
    title: str = Field(min_length=1, max_length=200)

    @field_validator("title")
    @classmethod
    def meaningful_title(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("A nonblank title is required")
        return value.strip()


class MaterialDelete(ApiModel):
    expected_revision: int = Field(ge=1)


class MaterialImportCapability(ApiModel):
    material_type: MaterialType
    formats: list[SourceFormat]
    languages: list[MaterialLanguage]
    max_size_bytes: int = Field(gt=0)
    format_max_size_bytes: dict[SourceFormat, int] = Field(default_factory=dict[SourceFormat, int])


class MaterialImportCapabilitiesRead(ApiModel):
    schema_version: Literal[1] = 1
    capabilities: list[MaterialImportCapability]
    quota_bytes: int = Field(ge=0)
    used_bytes: int = Field(ge=0)
    reserved_bytes: int = Field(ge=0)
    upload_ttl_seconds: int = Field(gt=0)


class MaterialMetadataRead(ApiModel):
    id: UUID
    library_id: UUID
    material_type: MaterialType
    title: str
    language: MaterialLanguage | None
    source_format: SourceFormat | None
    source_status: Literal["parsing", "readable", "degraded", "failed"]
    analysis_status: Literal["not_requested", "pending", "ready", "failed"]
    revision: int = Field(ge=1)
    delete_generation: int = Field(ge=0)
    revision_id: UUID | None
    source_revision_number: int | None = Field(default=None, ge=1)
    first_chapter_id: UUID | None
    job_id: UUID | None
    progress_percent: int | None = Field(default=None, ge=0, le=100)
    readable: bool
    created_at: datetime
    updated_at: datetime
