"""Account transport DTOs; no ORM model is ever serialized directly."""

import re
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field, SecretStr, field_validator

from app.schemas.responses import ApiModel


def _bounded_password_input(value: SecretStr) -> SecretStr:
    secret = value.get_secret_value()
    if not 1 <= len(secret) <= 128 or len(secret.encode("utf-8")) > 1024:
        raise ValueError("password input exceeds supported bounds")
    return value


def _opaque_token_input(value: SecretStr) -> SecretStr:
    if re.fullmatch(r"[A-Za-z0-9_-]{43}", value.get_secret_value()) is None:
        raise ValueError("token format is invalid")
    return value


class AuthPolicyRead(ApiModel):
    registration_enabled: bool
    approval_required: bool
    email_verification_required: Literal[True] = True
    recovery_enabled: bool
    recovery_mode: Literal["disabled", "email", "manual", "email_or_manual"]
    action_link_base_url: str
    password_min_length: int = Field(ge=1)
    password_max_length: int = Field(ge=1)


class MetaRead(ApiModel):
    instance_id: str
    api_version: Literal["v1"] = "v1"
    release: str


class AdminAuthPolicyRead(ApiModel):
    registration_mode: Literal["closed", "approval", "open"]
    registration_enabled: bool
    email_verification_required: Literal[True] = True
    recovery_mode: Literal["disabled", "email", "manual", "email_or_manual"]
    revision: int = Field(ge=1)


class AdminAuthPolicyUpdate(ApiModel):
    registration_mode: Literal["closed", "approval", "open"]
    recovery_mode: Literal["disabled", "email", "manual", "email_or_manual"] | None = None
    expected_revision: int = Field(ge=1)


class RegisterRequest(ApiModel):
    email: str = Field(min_length=3, max_length=254)
    password: SecretStr = Field(json_schema_extra={"minLength": 15, "maxLength": 128})

    @field_validator("password")
    @classmethod
    def validate_password_length(cls, value: SecretStr) -> SecretStr:
        if not 15 <= len(value.get_secret_value()) <= 128:
            raise ValueError("password length violates the published policy")
        return value


class EmailRequest(ApiModel):
    email: str = Field(min_length=3, max_length=254)


class MailAccepted(ApiModel):
    state: Literal["accepted"] = "accepted"
    next_step: Literal["verify_email", "check_email", "await_review"]


class TokenRequest(ApiModel):
    token: SecretStr = Field(
        json_schema_extra={"pattern": "^[A-Za-z0-9_-]{43}$", "minLength": 43, "maxLength": 43}
    )

    @field_validator("token")
    @classmethod
    def validate_token_format(cls, value: SecretStr) -> SecretStr:
        return _opaque_token_input(value)


class RecoveryCompleteRequest(TokenRequest):
    new_password: SecretStr = Field(json_schema_extra={"minLength": 15, "maxLength": 128})

    @field_validator("new_password")
    @classmethod
    def validate_password_length(cls, value: SecretStr) -> SecretStr:
        if not 15 <= len(value.get_secret_value()) <= 128:
            raise ValueError("password length violates the published policy")
        return value


class LoginRequest(ApiModel):
    email: str = Field(min_length=3, max_length=254)
    password: SecretStr = Field(json_schema_extra={"minLength": 1, "maxLength": 128})

    @field_validator("password")
    @classmethod
    def validate_password_input(cls, value: SecretStr) -> SecretStr:
        return _bounded_password_input(value)


class NativeLoginRequest(LoginRequest):
    platform: Literal["windows", "android"]
    device_summary: str | None = Field(default=None, max_length=200)


class WebAuthenticated(ApiModel):
    state: Literal["authenticated"] = "authenticated"
    session_ref: UUID
    audience: Literal["client", "admin"]
    absolute_expires_at: datetime
    idle_expires_at: datetime
    server_time: datetime


class NativeAuthenticated(ApiModel):
    state: Literal["authenticated"] = "authenticated"
    session_ref: UUID
    audience: Literal["client"] = "client"
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime
    session_generation: int = Field(ge=1)
    absolute_expires_at: datetime
    server_time: datetime


class ActivationRequired(ApiModel):
    state: Literal["action_required"] = "action_required"
    action_required: Literal["verify_email", "await_approval", "rejected"] = "verify_email"
    continuation_token: str
    continuation_expires_at: datetime


WebLoginRead = Annotated[WebAuthenticated | ActivationRequired, Field(discriminator="state")]
NativeLoginRead = Annotated[NativeAuthenticated | ActivationRequired, Field(discriminator="state")]


class ActivationStatusRead(ApiModel):
    state: Literal["pending_email", "pending_approval", "rejected", "active"]
    action_required: Literal["verify_email"] | None
    expires_at: datetime


class CsrfRead(ApiModel):
    session_ref: UUID
    csrf_token: str


class NativeRefreshRequest(ApiModel):
    refresh_token: SecretStr = Field(
        json_schema_extra={"pattern": "^[A-Za-z0-9_-]{43}$", "minLength": 43, "maxLength": 43}
    )
    refresh_request_id: UUID

    @field_validator("refresh_token")
    @classmethod
    def validate_refresh_token(cls, value: SecretStr) -> SecretStr:
        return _opaque_token_input(value)


class PasswordChangeRequest(ApiModel):
    current_password: SecretStr
    new_password: SecretStr = Field(json_schema_extra={"minLength": 15, "maxLength": 128})

    @field_validator("current_password")
    @classmethod
    def validate_current_password(cls, value: SecretStr) -> SecretStr:
        return _bounded_password_input(value)

    @field_validator("new_password")
    @classmethod
    def validate_password_length(cls, value: SecretStr) -> SecretStr:
        if not 15 <= len(value.get_secret_value()) <= 128:
            raise ValueError("password length violates the published policy")
        return value


class PermissionRead(ApiModel):
    code: str
    data_scope: str


class AuthzVersionRead(ApiModel):
    user: int = Field(ge=1)
    policy: int = Field(ge=1)


class NavigationRead(ApiModel):
    key: str
    route_key: str
    title: str
    icon_key: str | None = None
    title_customized: bool = False
    icon_customized: bool = False


class AccessRead(ApiModel):
    user_id: UUID
    instance_id: str
    audience: Literal["client", "admin"]
    session_ref: UUID
    account_status: Literal["active"] = "active"
    authz_version: AuthzVersionRead
    permissions: list[PermissionRead]
    navigation: list[NavigationRead]
    feature_flags: list[str]


class AccountRead(ApiModel):
    email: str
    status: Literal["active"] = "active"
    email_verified_at: datetime | None
    created_at: datetime


class SessionSummary(ApiModel):
    id: UUID
    audience: Literal["client", "admin"]
    transport: Literal["web", "native"]
    platform: Literal["web", "windows", "android"]
    device_summary: str | None
    created_at: datetime
    last_seen_at: datetime | None
    absolute_expires_at: datetime
    revoked_at: datetime | None
    is_current: bool
