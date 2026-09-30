"""Admin menu layout DTOs. Route and component keys are not client input."""

import re
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator, model_validator

from app.schemas.auth import NavigationRead
from app.schemas.responses import ApiModel

_CODE = re.compile(r"[a-z][a-z0-9_]{0,63}")
_PERMISSION = re.compile(r"[a-z][a-z0-9_.]{0,99}")
_MAX_ITEMS = 64
_MAX_EXTRAS = 32


class MenuLayoutItem(ApiModel):
    menu_id: UUID
    expected_revision: int = Field(ge=1)
    title: str
    parent_menu_id: UUID | None = None
    sort_order: int = Field(ge=0, le=10000)
    icon_key: str | None = None
    enabled: bool
    permission_match: Literal["all", "any"]
    permission_codes: list[str] = Field(max_length=_MAX_EXTRAS)

    @field_validator("title")
    @classmethod
    def _title(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped or len(stripped) > 100:
            raise ValueError("menu title is invalid")
        return stripped

    @field_validator("permission_codes")
    @classmethod
    def _codes(cls, value: list[str]) -> list[str]:
        if any(_PERMISSION.fullmatch(code) is None for code in value) or len(set(value)) != len(
            value
        ):
            raise ValueError("menu permission codes are invalid")
        return value


class MenuLayoutUpdate(ApiModel):
    items: list[MenuLayoutItem] = Field(min_length=1, max_length=_MAX_ITEMS)

    @model_validator(mode="after")
    def _unique(self) -> "MenuLayoutUpdate":
        if len({item.menu_id for item in self.items}) != len(self.items):
            raise ValueError("menu layout items must be unique")
        return self


class MenuGroupCreate(ApiModel):
    code: str
    audience: Literal["client", "admin"]
    title: str
    parent_menu_id: UUID | None = None
    sort_order: int = Field(default=0, ge=0, le=10000)

    @field_validator("code")
    @classmethod
    def _code(cls, value: str) -> str:
        if _CODE.fullmatch(value) is None:
            raise ValueError("menu code is invalid")
        return value

    @field_validator("title")
    @classmethod
    def _title(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped or len(stripped) > 100:
            raise ValueError("menu title is invalid")
        return stripped


class MenuDelete(ApiModel):
    expected_revision: int = Field(ge=1)


class MenuPreviewRequest(ApiModel):
    user_id: UUID
    audience: Literal["client", "admin"]


class MenuRead(ApiModel):
    id: UUID
    code: str
    audience: Literal["client", "admin"]
    route_key: str | None
    component_key: str | None
    parent_menu_id: UUID | None
    title: str
    icon_key: str | None
    sort_order: int = Field(ge=0)
    permission_match: Literal["all", "any"]
    enabled: bool
    floor: list[str]
    permission_codes: list[str]
    revision: int = Field(ge=1)


class MenuCatalogPage(ApiModel):
    code: str
    audience: Literal["client", "admin"]
    route_key: str
    component_key: str
    floor: list[str]
    icon_key: str
    title: str
    sort_order: int = Field(ge=0)


class MenuPermissionChoice(ApiModel):
    code: str
    audience: Literal["client", "admin"]


class MenuCatalogRead(ApiModel):
    pages: list[MenuCatalogPage]
    icons: list[str]
    permission_codes: list[MenuPermissionChoice]


class MenuPreviewRead(ApiModel):
    navigation: list[NavigationRead]


class MenuWriteResult(ApiModel):
    authorization_revision: int = Field(ge=1)
    audit_id: UUID | None
    affected_count: int = Field(ge=0)
    menus: list[MenuRead]
