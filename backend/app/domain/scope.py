"""Authenticated account scope passed to services and logical-reference repositories."""

from dataclasses import dataclass
from datetime import datetime
from typing import Literal
from uuid import UUID

Audience = Literal["client", "admin"]


@dataclass(frozen=True)
class ScopeContext:
    user_id: UUID
    session_id: UUID
    audience: Audience
    transport: Literal["web", "native"]
    user_authz_version: int
    policy_authz_version: int
    security_epoch: int
    absolute_expires_at: datetime
