"""Transactional pending-account creation and one-use mail challenges."""

import logging
from datetime import UTC, datetime, timedelta
from uuid import UUID

from pydantic import SecretStr
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import current_correlation
from app.domain.email_address import normalize_email
from app.domain.errors import AppError
from app.models import (
    AuthChallenge,
    AuthChallengeDelivery,
    AuthPolicy,
    Library,
    User,
    UserExtension,
    UserRole,
)
from app.repositories.identity import (
    active_sessions_for_recovery,
    challenge_by_id_for_update,
    challenge_identity_by_digest,
    global_revision_for_update,
    latest_challenge_for_update,
    registration_policy,
    user_by_email,
    user_for_challenge_for_update,
    user_for_continuation,
)
from app.schemas.auth import ActivationStatusRead, MailAccepted
from app.services.auth_crypto import AuthCrypto, hash_password, new_opaque_token
from app.services.auth_policy import mail_ready, validate_public_registration_role
from app.services.security_events import append_identity_event

_VERIFY_TTL = timedelta(hours=24)
_RECOVERY_TTL = timedelta(minutes=30)
_RESEND_COOLDOWN = timedelta(seconds=60)
_LOGGER = logging.getLogger(__name__)


def _identity_log_extra(user_id: UUID | None = None) -> dict[str, object]:
    request_id, operation_id = current_correlation()
    return {
        "request_id": request_id,
        "operation_id": operation_id,
        "user_id": user_id,
        "audience": "client",
    }


def _same_email_conflict(error: IntegrityError) -> bool:
    current: object | None = error.orig
    for _ in range(4):
        if (
            getattr(current, "sqlstate", None) == "23505"
            and getattr(current, "constraint_name", None) == "uq_users_email_normalized"
        ):
            return True
        current = getattr(current, "__cause__", None)
    return False


def email_identity(email: str) -> tuple[str, str]:
    try:
        return normalize_email(email)
    except ValueError:
        raise AppError(ErrorCode.INPUT_INVALID) from None


async def _policy(session: AsyncSession, *, lock: bool = False) -> AuthPolicy:
    policy = await registration_policy(session, for_update=lock)
    if (
        policy is None
        or policy.registration_mode not in {"closed", "open"}
        or not policy.require_email_verification
        or policy.recovery_mode != "email"
    ):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return policy


async def _issue_challenge(
    session: AsyncSession,
    *,
    runtime: Runtime,
    crypto: AuthCrypto,
    user: User,
    purpose: str,
    now: datetime,
) -> bool:
    current = await latest_challenge_for_update(session, user_id=user.id, purpose=purpose)
    if current is not None and current.created_at + _RESEND_COOLDOWN > now:
        return False
    if current is not None and current.consumed_at is None and current.revoked_at is None:
        current.revoked_at = now
    token = new_opaque_token()
    ttl = _VERIFY_TTL if purpose == "email_verify" else _RECOVERY_TTL
    challenge = AuthChallenge(
        user_id=user.id,
        purpose=purpose,
        audience="client",
        token_digest=crypto.digest(f"challenge-{purpose}", token),
        digest_key_version=crypto.digest_key_version,
        security_epoch=user.security_epoch,
        password_version=user.password_version,
        target_email_digest=crypto.digest("email-target", user.email_normalized),
        expires_at=now + ttl,
        failed_attempts=0,
    )
    session.add(challenge)
    await session.flush()
    path = "verify-email" if purpose == "email_verify" else "reset-password"
    link = f"{runtime.settings.public_base_url.rstrip('/')}/{path}#token={token}"
    session.add(
        AuthChallengeDelivery(
            user_id=user.id,
            challenge_id=challenge.id,
            encrypted_payload=crypto.encrypt_mail(email=user.email, link=link, purpose=purpose),
            encryption_key_version=crypto.mail_key_version,
            payload_schema_version=1,
            expires_at=challenge.expires_at,
            status="pending",
            attempt_count=0,
            next_attempt_at=now,
            lease_generation=0,
        )
    )
    return True


async def register(runtime: Runtime, *, email: str, password: SecretStr) -> MailAccepted:
    if runtime.resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    display, normalized = email_identity(email)
    try:
        async with runtime.resources.database.sessions() as session:
            public_policy = await _policy(session)
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None

    if public_policy.registration_mode != "open":
        raise AppError(ErrorCode.PERMISSION_DENIED)
    if not mail_ready(runtime):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    password_hash = await hash_password(password)
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            revision = await global_revision_for_update(session)
            if revision is None:
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            policy = await _policy(session, lock=True)
            if policy.registration_mode != "open":
                raise AppError(ErrorCode.PERMISSION_DENIED)
            role = await validate_public_registration_role(session, policy.default_role_id)
            existing = await user_by_email(session, normalized, for_update=True)
            if existing is not None:
                return MailAccepted(next_step="verify_email")
            user = User(
                email=display,
                email_normalized=normalized,
                password_hash=password_hash,
                status="pending",
                authz_version=1,
                password_version=1,
                security_epoch=0,
                revision=1,
                email_verified_at=None,
                locked_until=None,
                client_security_epoch=0,
                admin_security_epoch=0,
            )
            session.add(user)
            await session.flush()
            session.add_all(
                [
                    Library(owner_user_id=user.id),
                    UserExtension(user_id=user.id),
                    UserRole(user_id=user.id, role_id=role.id),
                ]
            )
            await _issue_challenge(
                session,
                runtime=runtime,
                crypto=crypto,
                user=user,
                purpose="email_verify",
                now=datetime.now(UTC),
            )
            revision.revision += 1
            await append_identity_event(
                session,
                action="account.registered",
                authorization_revision=revision.revision,
                actor="public-registration",
                actor_user_id=None,
                audience="client",
                target_type="user",
                target_id=user.id,
                result="accepted",
            )
        _LOGGER.info("auth.registration.accepted", extra=_identity_log_extra(user.id))
        return MailAccepted(next_step="verify_email")
    except AppError:
        raise
    except IntegrityError as exc:
        # Concurrent same-email registration is indistinguishable from an existing account.
        if _same_email_conflict(exc):
            return MailAccepted(next_step="verify_email")
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def activation_status(runtime: Runtime, *, continuation: str) -> ActivationStatusRead:
    resources = runtime.resources
    if resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    key = resources.cache.key(
        "auth", "continuation", crypto.digest("continuation", continuation).hex()
    )
    try:
        binding = await resources.cache.client.get(key)
        ttl = await resources.cache.client.ttl(key)
        if not isinstance(binding, bytes) or ttl <= 0:
            raise AppError(ErrorCode.RESOURCE_EXPIRED)
        user_id = UUID(binding.decode("ascii"))
        async with resources.database.sessions() as session:
            user = await user_for_continuation(session, user_id)
            if user is None or user.status not in {"pending", "active"}:
                raise AppError(ErrorCode.RESOURCE_EXPIRED)
            if user.status == "active" and user.email_verified_at is None:
                raise AppError(ErrorCode.RESOURCE_EXPIRED)
        pending = user.status == "pending"
        return ActivationStatusRead(
            state="pending_email" if pending else "active",
            action_required="verify_email" if pending else None,
            expires_at=datetime.now(UTC) + timedelta(seconds=ttl),
        )
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def request_challenge(runtime: Runtime, *, email: str, purpose: str) -> MailAccepted:
    if runtime.resources is None or not runtime.ready or not mail_ready(runtime):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    _, normalized = email_identity(email)
    crypto = AuthCrypto.from_settings(runtime.settings)
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            await _policy(session)
            user = await user_by_email(session, normalized, for_update=True)
            if user is not None and (
                (purpose == "email_verify" and user.status == "pending")
                or (purpose == "password_recovery" and user.status == "active")
            ):
                await _issue_challenge(
                    session,
                    runtime=runtime,
                    crypto=crypto,
                    user=user,
                    purpose=purpose,
                    now=datetime.now(UTC),
                )
        if purpose == "email_verify":
            _LOGGER.info("auth.verification.request.accepted", extra=_identity_log_extra())
        else:
            _LOGGER.info("auth.recovery.request.accepted", extra=_identity_log_extra())
        return MailAccepted(next_step="check_email")
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def verify_email(runtime: Runtime, *, token: SecretStr) -> None:
    if runtime.resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    digest = crypto.digest("challenge-email_verify", token.get_secret_value())
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            candidate = await challenge_identity_by_digest(
                session, key_version=crypto.digest_key_version, digest=digest
            )
            if candidate is None or candidate[2] != "email_verify":
                raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
            revision = await global_revision_for_update(session)
            if revision is None:
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            user = await user_for_challenge_for_update(session, candidate[1])
            challenge = await challenge_by_id_for_update(session, candidate[0])
            now = datetime.now(UTC)
            if user is None or challenge is None or user.status != "pending":
                raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
            if (
                challenge.consumed_at is not None
                or challenge.revoked_at is not None
                or challenge.expires_at <= now
            ):
                raise AppError(ErrorCode.RESOURCE_EXPIRED)
            if (
                challenge.security_epoch != user.security_epoch
                or challenge.password_version != user.password_version
                or challenge.target_email_digest
                != crypto.digest("email-target", user.email_normalized)
            ):
                raise AppError(ErrorCode.RESOURCE_EXPIRED)
            user.status = "active"
            user.email_verified_at = now
            user.revision += 1
            challenge.consumed_at = now
            revision.revision += 1
            await append_identity_event(
                session,
                action="email.verified",
                authorization_revision=revision.revision,
                actor="email-challenge",
                actor_user_id=None,
                audience="client",
                target_type="user",
                target_id=user.id,
                result="committed",
            )
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    _LOGGER.info("auth.email.verified", extra=_identity_log_extra(user.id))


async def complete_recovery(runtime: Runtime, *, token: SecretStr, new_password: SecretStr) -> None:
    """Consume one mail challenge and revoke every previous session atomically."""
    resources = runtime.resources
    if resources is None or not runtime.ready:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    crypto = AuthCrypto.from_settings(runtime.settings)
    digest = crypto.digest("challenge-password_recovery", token.get_secret_value())
    password_hash = await hash_password(new_password)
    try:
        async with resources.database.sessions() as session, session.begin():
            candidate = await challenge_identity_by_digest(
                session,
                key_version=crypto.digest_key_version,
                digest=digest,
                purpose="password_recovery",
            )
            if candidate is None:
                raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
            revision = await global_revision_for_update(session)
            user = await user_for_challenge_for_update(session, candidate[1])
            challenge = await challenge_by_id_for_update(session, candidate[0])
            now = datetime.now(UTC)
            if revision is None or user is None or challenge is None or user.status != "active":
                raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
            if (
                challenge.consumed_at is not None
                or challenge.revoked_at is not None
                or challenge.expires_at <= now
                or challenge.security_epoch != user.security_epoch
                or challenge.password_version != user.password_version
                or challenge.target_email_digest
                != crypto.digest("email-target", user.email_normalized)
            ):
                raise AppError(ErrorCode.RESOURCE_EXPIRED)
            sessions = await active_sessions_for_recovery(session, user_id=user.id)
            user.password_hash = password_hash
            user.password_version += 1
            user.security_epoch += 1
            user.revision += 1
            challenge.consumed_at = now
            for active in sessions:
                active.revoked_at = now
                active.revoke_reason_code = "password_recovery"
            await append_identity_event(
                session,
                action="password.recovered",
                authorization_revision=revision.revision,
                actor="password-recovery",
                actor_user_id=None,
                audience="client",
                target_type="user",
                target_id=user.id,
                result="committed",
            )
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    _LOGGER.info("auth.password.recovered", extra=_identity_log_extra(user.id))
