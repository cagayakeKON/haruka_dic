"""Admin role, grant, and ceiling DTOs. Clients cannot submit an owner or a protected flag."""

import re
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator, model_validator

from app.schemas.responses import ApiModel

_CODE = re.compile(r"[a-z][a-z0-9_]{0,63}")
_MAX_GRANTS = 256
_MAX_PARENTS = 32
_MAX_BOUNDARIES = 256


class RoleCreate(ApiModel):
    code: str
    name: str
    description: str | None = None

    @field_validator("code")
    @classmethod
    def _code(cls, value: str) -> str:
        if _CODE.fullmatch(value) is None:
            raise ValueError("role code is invalid")
        return value

    @field_validator("name")
    @classmethod
    def _name(cls, value: str) -> str:
        if not value.strip() or len(value) > 100:
            raise ValueError("role name is invalid")
        return value

    @field_validator("description")
    @classmethod
    def _description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if len(value) > 2000:
            raise ValueError("role description is invalid")
        return value or None


class RoleMetadataUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    name: str
    description: str | None = None

    @field_validator("name")
    @classmethod
    def _name(cls, value: str) -> str:
        if not value.strip() or len(value) > 100:
            raise ValueError("role name is invalid")
        return value

    @field_validator("description")
    @classmethod
    def _description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if len(value) > 2000:
            raise ValueError("role description is invalid")
        return value or None


class RoleEnabledUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    enabled: bool


class RoleGrantWrite(ApiModel):
    permission_code: str = Field(min_length=1, max_length=100)
    effect: Literal["allow", "deny"]
    data_scope: Literal["self", "platform_metadata"]


class RoleGrantsUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    grants: list[RoleGrantWrite] = Field(max_length=_MAX_GRANTS)

    @model_validator(mode="after")
    def _unique(self) -> "RoleGrantsUpdate":
        seen = {(item.permission_code, item.effect, item.data_scope) for item in self.grants}
        if len(seen) != len(self.grants):
            raise ValueError("role grants must be unique")
        return self


class RoleInheritanceUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    parent_role_ids: list[UUID] = Field(max_length=_MAX_PARENTS)

    @model_validator(mode="after")
    def _unique(self) -> "RoleInheritanceUpdate":
        if len(set(self.parent_role_ids)) != len(self.parent_role_ids):
            raise ValueError("parent roles must be unique")
        return self


class RoleDelete(ApiModel):
    expected_revision: int = Field(ge=1)


class GrantBoundaryWrite(ApiModel):
    boundary_kind: Literal[
        "assign_role", "assign_permission", "manage_account_role", "manage_unassigned_accounts"
    ]
    target_role_id: UUID | None = None
    permission_code: str | None = Field(default=None, max_length=100)
    data_scope: Literal["self", "platform_metadata"] | None = None

    @model_validator(mode="after")
    def _shape(self) -> "GrantBoundaryWrite":
        if self.boundary_kind in {"assign_role", "manage_account_role"}:
            valid = (
                self.target_role_id is not None
                and self.permission_code is None
                and self.data_scope is None
            )
        elif self.boundary_kind == "assign_permission":
            valid = (
                self.target_role_id is None
                and bool(self.permission_code)
                and self.data_scope is not None
            )
        else:
            valid = (
                self.target_role_id is None
                and self.permission_code is None
                and self.data_scope is None
            )
        if not valid:
            raise ValueError("grant boundary shape is invalid")
        return self


class GrantBoundariesUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    boundaries: list[GrantBoundaryWrite] = Field(max_length=_MAX_BOUNDARIES)

    @model_validator(mode="after")
    def _unique(self) -> "GrantBoundariesUpdate":
        unassigned = [
            item for item in self.boundaries if item.boundary_kind == "manage_unassigned_accounts"
        ]
        if len(unassigned) > 1:
            raise ValueError("unassigned-account ceiling is singular")
        keys = {
            (item.boundary_kind, item.target_role_id, item.permission_code, item.data_scope)
            for item in self.boundaries
        }
        if len(keys) != len(self.boundaries):
            raise ValueError("grant boundaries must be unique")
        return self


class RoleGrantRead(ApiModel):
    permission_code: str
    effect: Literal["allow", "deny"]
    data_scope: Literal["self", "platform_metadata"]


class RoleParentRead(ApiModel):
    role_id: UUID
    code: str
    enabled: bool


class RoleRead(ApiModel):
    id: UUID
    code: str
    name: str
    description: str | None
    protected: bool
    enabled: bool
    revision: int = Field(ge=1)
    grants: list[RoleGrantRead]
    parents: list[RoleParentRead]
    member_count: int = Field(ge=0)


class PermissionCatalogRead(ApiModel):
    code: str
    audience: Literal["client", "admin"]
    data_scope: Literal["self", "platform_metadata"]
    enabled: bool


class GrantBoundaryRead(ApiModel):
    boundary_kind: Literal[
        "assign_role", "assign_permission", "manage_account_role", "manage_unassigned_accounts"
    ]
    target_role_id: UUID | None
    permission_code: str | None
    data_scope: Literal["self", "platform_metadata"] | None
    revision: int = Field(ge=1)


class AuthorizationWriteResult(ApiModel):
    role_id: UUID
    revision: int = Field(ge=1)
    authorization_revision: int = Field(ge=1)
    audit_id: UUID | None
    affected_count: int = Field(ge=0)
