"""Minimal public health projection; contains no configuration values."""

from typing import Literal

from app.schemas.responses import ApiModel


class HealthRead(ApiModel):
    status: Literal["ok"] = "ok"
