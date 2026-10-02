"""Admin account and session DTOs. Password, profile, and private content stay out."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.responses import ApiModel

_MAX_ROLES = 32


class AccountCreate(ApiModel):
    email: str = Field(min_length=3, max_length=254)
    display_name: str | None = Field(default=None, max_length=100)
    role_ids: list[UUID] = Field(default_factory=list[UUID], max_length=_MAX_ROLES)

    @model_validator(mode="after")
    def _unique_roles(self) -> "AccountCreate":
        if len(set(self.role_ids)) != len(self.role_ids):
            raise ValueError("roles must be unique")
        if self.display_name is not None:
            self.display_name = self.display_name.strip() or None
        return self


class AccountStatusUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    status: Literal["active", "disabled"]


class AccountApprovalUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    decision: Literal["approve", "reject"]


class ManualRecoveryDecision(ApiModel):
    challenge_id: UUID
    expected_revision: int = Field(ge=1)
    decision: Literal["issue", "reject"]
    verification_method: Literal["in_person", "known_channel"] | None = None

    @model_validator(mode="after")
    def _method_matches_decision(self) -> "ManualRecoveryDecision":
        if self.decision == "issue" and self.verification_method is None:
            raise ValueError("verification method is required")
        if self.decision == "reject" and self.verification_method is not None:
            raise ValueError("verification method is only recorded when issuing")
        return self


class ManualRecoveryRead(ApiModel):
    challenge_id: UUID
    status: Literal["requested", "issued", "rejected", "consumed", "expired"]
    created_at: datetime
    expires_at: datetime


class ManualRecoveryDecisionResult(ApiModel):
    challenge_id: UUID
    status: Literal["issued", "rejected"]
    revision: int = Field(ge=1)
    authorization_revision: int = Field(ge=1)
    expires_at: datetime
    token: str | None = None


class AccountRolesUpdate(ApiModel):
    expected_revision: int = Field(ge=1)
    role_ids: list[UUID] = Field(max_length=_MAX_ROLES)

    @model_validator(mode="after")
    def _unique_roles(self) -> "AccountRolesUpdate":
        if len(set(self.role_ids)) != len(self.role_ids):
            raise ValueError("roles must be unique")
        return self


class SessionRevocation(ApiModel):
    expected_revision: int = Field(ge=1)
    session_id: UUID | None = None
    audience: Literal["client", "admin"] | None = None
    all_sessions: bool = False

    @model_validator(mode="after")
    def _one_target(self) -> "SessionRevocation":
        selected = sum((self.session_id is not None, self.audience is not None, self.all_sessions))
        if selected != 1:
            raise ValueError("choose one session, one audience, or all sessions")
        return self


class AccountRoleRead(ApiModel):
    role_id: UUID
    code: str
    name: str
    enabled: bool
    protected: bool


class AccountRead(ApiModel):
    user_id: UUID
    email: str
    display_name: str | None
    status: Literal["pending", "active", "disabled"]
    email_verified: bool
    locked: bool
    approval_status: Literal["not_required", "pending", "approved", "rejected"]
    audiences: list[Literal["client", "admin"]]
    roles: list[AccountRoleRead]
    live_session_count: int = Field(ge=0)
    revision: int = Field(ge=1)


class AccountSessionRead(ApiModel):
    session_id: UUID
    audience: Literal["client", "admin"]
    transport: Literal["web", "native"]
    platform: str
    device_summary: str | None
    created_at: datetime
    last_seen_at: datetime | None
    absolute_expires_at: datetime
    revoked_at: datetime | None


class AccountCeilingsRead(ApiModel):
    assign_role_ids: list[UUID]
    manage_account_role_ids: list[UUID]
    manage_unassigned_accounts: bool


class AccountWriteResult(ApiModel):
    user_id: UUID
    revision: int = Field(ge=1)
    authorization_revision: int = Field(ge=1)
    audit_id: UUID | None
    affected_count: int = Field(ge=0)
