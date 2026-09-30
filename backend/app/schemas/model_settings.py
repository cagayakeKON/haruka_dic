"""Safe provider configuration, persistent tests and task progress contracts."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, SecretStr, field_validator, model_validator

from app.schemas.responses import ApiModel

Provider = Literal["openrouter", "gemini"]
Capability = Literal["text", "vision", "tts"]


class CredentialRead(ApiModel):
    id: UUID
    provider: Provider
    label: str
    masked_key: str
    revision: int
    credential_version: int
    status: Literal["active", "revoked"]
    created_at: datetime
    updated_at: datetime


class CredentialList(ApiModel):
    items: list[CredentialRead]


class CredentialCreate(ApiModel):
    provider: Provider
    label: str = Field(default="个人凭据", min_length=1, max_length=100)
    key: SecretStr = Field(min_length=8, max_length=4096)


class CredentialRotate(ApiModel):
    expected_revision: int = Field(ge=1)
    key: SecretStr = Field(min_length=8, max_length=4096)
    label: str | None = Field(default=None, min_length=1, max_length=100)


class CredentialDelete(ApiModel):
    expected_revision: int = Field(ge=1)


class CredentialImpact(ApiModel):
    credential_id: UUID
    revision: int
    bound_capabilities: list[Capability]
    unfinished_job_count: int


class ModelBinding(ApiModel):
    credential_id: UUID
    provider: Provider
    model_id: str = Field(min_length=1, max_length=256)
    voice_id: str | None = Field(default=None, max_length=128)
    language_tag: Literal["ja", "en"] = "ja"
    output_format: Literal["mp3"] = "mp3"


class ModelBindings(ApiModel):
    text: ModelBinding | None = None
    vision: ModelBinding | None = None
    tts: ModelBinding | None = None


class ModelSettingsRead(ApiModel):
    revision: int
    default_provider: Provider = "openrouter"
    bindings: ModelBindings


class ModelSettingsUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    bindings: ModelBindings


class ModelEntry(ApiModel):
    id: UUID
    provider: Provider
    model_id: str
    display_name: str
    capabilities: list[Capability]
    enabled: bool
    verified: bool
    revision: int
    adapter_id: str | None = None


class VoiceEntry(ApiModel):
    model_id: str
    provider: Provider
    voice_id: str
    language_tags: list[str]
    display_name: str
    output_formats: list[str]
    verified: bool


class ModelLimits(ApiModel):
    max_credentials: int = Field(default=10, ge=0, le=10)
    max_concurrent_jobs: int = Field(default=1, ge=0, le=1)
    instance_concurrent_jobs: int = Field(default=4, ge=0, le=4)
    max_model_calls: int = Field(default=1, ge=0, le=1)
    max_output_tokens: int = Field(default=128, ge=0, le=128)
    timeout_seconds: int = Field(default=60, ge=0, le=60)
    tts_timeout_seconds: int = Field(default=90, ge=0, le=90)
    max_test_image_bytes: int = Field(default=4096, ge=0, le=4096)
    max_tts_characters: int = Field(default=32, ge=0, le=32)
    websocket_max_jobs: int = Field(default=100, ge=0, le=100)
    enabled: bool = True
    revision: int = Field(default=1, ge=1)


class ModelCapabilities(ApiModel):
    revision: int
    default_provider: Provider = "openrouter"
    models: list[ModelEntry]
    voices: list[VoiceEntry]
    limits: ModelLimits


class CatalogUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    enabled: bool


class LimitsUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    limits: ModelLimits


class UserLimitRead(ApiModel):
    user_id: UUID
    revision: int
    scope: Literal["user_override"] = "user_override"
    max_concurrent_jobs: int = Field(ge=0, le=1)


class UserLimitList(ApiModel):
    items: list[UserLimitRead]


class UserLimitUpdate(ApiModel):
    expected_revision: int = Field(ge=0)
    max_concurrent_jobs: int = Field(ge=0, le=1)


class UserLimitDelete(ApiModel):
    expected_revision: int = Field(ge=1)


class CredentialTest(ApiModel):
    expected_revision: int = Field(ge=1)
    capability: Capability
    model_id: str = Field(min_length=1, max_length=256)
    voice_id: str | None = Field(default=None, max_length=128)
    language_tag: Literal["ja", "en"] = "ja"
    output_format: Literal["mp3"] = "mp3"

    @model_validator(mode="after")
    def voice_scope(self) -> "CredentialTest":
        if self.capability != "tts" and self.voice_id is not None:
            raise ValueError("voice only applies to tts")
        return self


class TestAccepted(ApiModel):
    job_id: UUID
    run_id: UUID
    generation: int
    state: str


class UsageMetric(ApiModel):
    known_sum: int | None
    known_attempt_count: int
    unknown_attempt_count: int
    completeness: Literal["complete", "partial", "unavailable"]


class UsageGroup(ApiModel):
    simulated: bool
    provider: str
    model_id: str
    capability: str
    operation_kind: str
    attempt_count: int
    started_count: int
    succeeded_count: int
    failed_count: int
    unknown_count: int
    metrics: dict[str, UsageMetric]


class ModelUsage(ApiModel):
    as_of: datetime
    aggregation_revision: int
    groups: list[UsageGroup]


class TestResult(ApiModel):
    run_id: UUID
    job_id: UUID
    credential_id: UUID
    credential_version: int
    provider: Provider
    model_id: str
    model_revision: str | None = None
    capability: Capability
    state: str
    tested_at: datetime | None = None
    error_code: str | None = None
    usage: ModelUsage


class JobRead(ApiModel):
    id: UUID
    run_id: UUID
    credential_id: UUID
    operation_kind: Literal["credential_test"] = "credential_test"
    state: str
    revision: int
    generation: int
    sequence: int
    stage: str | None = None
    progress_percent: int | None = None
    error_code: str | None = None
    can_cancel: bool
    can_retry: bool
    requires_new_attempt_confirmation: bool
    created_at: datetime
    updated_at: datetime


class JobList(ApiModel):
    items: list[JobRead]


class AdminJobRead(ApiModel):
    id: UUID
    operation_kind: str
    state: str
    revision: int
    generation: int
    sequence: int
    error_code: str | None = None
    can_cancel: bool
    can_retry: bool
    created_at: datetime
    updated_at: datetime


class AdminJobList(ApiModel):
    items: list[AdminJobRead]


class JobCancel(ApiModel):
    expected_revision: int = Field(ge=1)


class JobRetry(ApiModel):
    expected_revision: int = Field(ge=1)
    confirm_new_attempt: bool = False
    credential_id: UUID | None = None


class JobEvent(ApiModel):
    schema_version: Literal[1] = 1
    event_id: UUID
    job_id: UUID
    generation: int
    sequence: int
    type: Literal["snapshot", "progress", "completed", "failed", "cancelled", "resync_required"]
    occurred_at: datetime
    payload: JobRead


class JobCursor(ApiModel):
    generation: int = Field(ge=1, strict=True)
    sequence: int = Field(ge=0, strict=True)


class JobSubscription(ApiModel):
    schema_version: Literal[1]
    type: Literal["subscribe", "unsubscribe"]
    job_ids: list[UUID] = Field(max_length=100)
    cursors: dict[UUID, JobCursor] = Field(default_factory=dict[UUID, JobCursor])

    @field_validator("schema_version", mode="before")
    @classmethod
    def strict_version(cls, value: object) -> object:
        if type(value) is not int:
            raise ValueError("integer protocol version required")
        return value

    @model_validator(mode="after")
    def cursor_scope(self) -> "JobSubscription":
        if not set(self.cursors).issubset(self.job_ids):
            raise ValueError("cursor must belong to an explicitly subscribed job")
        return self
