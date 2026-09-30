"""Actor-bound encrypted PG receipts, committed with administrative actions."""

import hashlib
import hmac
from base64 import urlsafe_b64encode
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from cryptography.fernet import Fernet, InvalidToken
from pydantic import BaseModel, ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import AuthChallenge, IdempotencyRecord, User
from app.services.auth_context import require_permissions
from app.services.auth_crypto import AuthCrypto
from app.services.governance_security import verify_admin_write


@dataclass(frozen=True)
class GovernanceReceiptContext:
    action: str
    key: str
    request_text: str
    permissions: tuple[str, ...]
    user_id: UUID | None = None
    role_id: UUID | None = None
    challenge_id: UUID | None = None
    deleted_role: bool = False


async def _authorize_target(
    session: AsyncSession, scope: ScopeContext, context: GovernanceReceiptContext
) -> None:
    from app.services import role_governance, user_governance

    if context.user_id is not None:
        await user_governance.authorize_account_receipt(
            session, actor_id=scope.user_id, user_id=context.user_id
        )
    if context.role_id is not None:
        await role_governance.authorize_role_receipt(
            session,
            actor_id=scope.user_id,
            role_id=context.role_id,
            deleted=context.deleted_role,
        )


async def commit_governance_receipt[T: BaseModel](
    session: AsyncSession,
    scope: ScopeContext,
    context: GovernanceReceiptContext,
    crypto: AuthCrypto,
    result_type: type[T],
    operation: Callable[[], Awaitable[T]],
) -> T:
    await verify_admin_write(session, scope)
    await require_permissions(
        session, user_id=scope.user_id, audience="admin", codes=context.permissions
    )
    action = context.action
    request_digest = crypto.digest("governance-request", context.request_text)
    key_digest = crypto.digest("governance-idempotency", context.key)
    lookup_digest = hashlib.sha256(context.key.encode()).digest()
    receipt = await session.scalar(
        select(IdempotencyRecord)
        .where(
            IdempotencyRecord.owner_user_id == scope.user_id,
            IdempotencyRecord.audience == "admin",
            IdempotencyRecord.action_code == action,
            IdempotencyRecord.lookup_digest == lookup_digest,
        )
        .with_for_update()
    )
    if receipt is None:
        legacy = await session.scalar(
            select(IdempotencyRecord.id)
            .where(
                IdempotencyRecord.owner_user_id == scope.user_id,
                IdempotencyRecord.audience == "admin",
                IdempotencyRecord.action_code == action,
                IdempotencyRecord.lookup_digest.is_(None),
            )
            .limit(1)
        )
        if legacy is not None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    cipher = Fernet(
        urlsafe_b64encode(
            hmac.new(crypto.signing_key, b"haruka-governance-receipt-v1", hashlib.sha256).digest()
        )
    )
    if receipt is not None:
        if (
            receipt.safe_response is None
            or receipt.safe_response.get("digest_key_version") != crypto.digest_key_version
        ):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        if receipt.request_digest != request_digest:
            raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
        await _authorize_target(session, scope, context)
        stored = receipt.safe_response
        ciphertext = stored.get("ciphertext") if stored else None
        if stored.get("key_version") != crypto.signing_key_version or not isinstance(
            ciphertext, str
        ):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        try:
            result = result_type.model_validate_json(cipher.decrypt(ciphertext.encode()))
        except (InvalidToken, ValidationError, ValueError):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
        challenge_id = context.challenge_id
        if challenge_id is not None and getattr(result, "token", None) is not None:
            user = await session.scalar(
                select(User).where(User.id == context.user_id).with_for_update()
            )
            challenge = await session.scalar(
                select(AuthChallenge).where(AuthChallenge.id == challenge_id).with_for_update()
            )
            if (
                user is None
                or user.status != "active"
                or challenge is None
                or challenge.security_epoch != user.security_epoch
                or challenge.password_version != user.password_version
                or challenge.target_email_digest
                != crypto.digest("email-target", user.email_normalized)
                or challenge.user_id != context.user_id
                or challenge.expires_at <= datetime.now(UTC)
                or challenge.consumed_at is not None
                or challenge.revoked_at is not None
            ):
                # Preserve the issued result receipt while never redisclosing an
                # expired/consumed bearer challenge. This does not execute again.
                raise AppError(ErrorCode.RESOURCE_EXPIRED)
        return result
    result = await operation()
    _, operation_id = current_correlation()
    session.add(
        IdempotencyRecord(
            owner_user_id=scope.user_id,
            library_id=None,
            audience="admin",
            action_code=action,
            key_digest=key_digest,
            lookup_digest=lookup_digest,
            request_digest=request_digest,
            state="committed",
            result_kind="governance_result",
            result_id=None,
            response_schema_version=1,
            safe_response={
                "ciphertext": cipher.encrypt(result.model_dump_json().encode()).decode(),
                "key_version": crypto.signing_key_version,
                "digest_key_version": crypto.digest_key_version,
            },
            http_status=200,
            expires_at=datetime.now(UTC) + timedelta(days=7),
            operation_id=operation_id or uuid4(),
        )
    )
    await session.flush()
    return result
