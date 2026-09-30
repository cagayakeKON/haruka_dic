"""Read-only audit and identity governance summaries. No secrets or private content."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.schemas.responses import ApiModel


class AuditEventRead(ApiModel):
    event_id: UUID
    action: str
    actor: str
    actor_user_id: UUID | None
    audience: Literal["client", "admin"] | None
    permission_code: str | None
    target_type: str | None
    target_id: UUID | None
    target_code: str | None
    result: Literal["accepted", "committed", "denied", "failed"] | None
    reason_code: str | None
    authorization_revision: int = Field(ge=1)
    request_id: UUID | None
    operation_id: UUID | None
    change_summary: dict[str, str] | None
    created_at: datetime


class GovernanceSummaryRead(ApiModel):
    accounts_active: int = Field(ge=0)
    accounts_pending: int = Field(ge=0)
    accounts_disabled: int = Field(ge=0)
    approvals_pending: int = Field(ge=0)
    roles_enabled: int = Field(ge=0)
    authorization_revision: int = Field(ge=1)
    open_manual_recoveries: int = Field(ge=0)
