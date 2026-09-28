"""B2a cache validation envelope; resource kinds register with their owning domains."""

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.schemas.responses import ApiModel


class CacheValidationRequest(ApiModel):
    protocol_version: int = Field(ge=1, le=1)
    # Registry dispatch parses each nonempty item through its exact domain schema.
    items: list[object] = Field(max_length=50)


class CacheValidationItem(ApiModel):
    request_ref: UUID
    kind: str
    projection: str
    action: str


class CacheValidationResult(ApiModel):
    request_ref: UUID
    state: str
    validated_versions: None = None
    read_ref: None = None
    offline_grant: None = None
    grant_revoked: bool = False


class CacheAuthzVersion(ApiModel):
    user: int
    policy: int


class CacheValidationScope(ApiModel):
    instance_id: str
    user_id: UUID
    audience: str
    session_ref: UUID
    security_epoch: int
    authz_version: CacheAuthzVersion


class ClientCacheValidation(ApiModel):
    protocol_version: int
    server_time: datetime
    scope: CacheValidationScope
    items: list[CacheValidationResult]
