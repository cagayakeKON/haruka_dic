"""Durable, leased mail delivery with an explicit at-least-once SMTP boundary."""

import asyncio
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import or_, select

from app.adapters.mail import send_smtp_message
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.models import AuthChallenge, AuthChallengeDelivery, User
from app.services.auth_crypto import AuthCrypto
from app.services.auth_policy import mail_ready

_LEASE = timedelta(seconds=30)
_MAX_ATTEMPTS = 5
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class MailLease:
    delivery_id: UUID
    user_id: UUID
    challenge_id: UUID
    generation: int
    owner: UUID
    encrypted_payload: bytes
    encryption_key_version: str


async def claim_due_mail(runtime: Runtime, owner: UUID) -> MailLease | None:
    if runtime.resources is None or not runtime.ready or not mail_ready(runtime):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    now = datetime.now(UTC)
    crypto = AuthCrypto.from_settings(runtime.settings)
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            candidate = (
                await session.execute(
                    select(
                        AuthChallengeDelivery.id,
                        AuthChallengeDelivery.user_id,
                        AuthChallengeDelivery.challenge_id,
                    )
                    .where(
                        or_(
                            (AuthChallengeDelivery.status == "pending")
                            & (AuthChallengeDelivery.next_attempt_at <= now),
                            (AuthChallengeDelivery.status == "sending")
                            & (AuthChallengeDelivery.lease_until <= now),
                        )
                    )
                    .order_by(AuthChallengeDelivery.next_attempt_at, AuthChallengeDelivery.id)
                    .limit(1)
                )
            ).first()
            if candidate is None:
                return None
            user = await session.scalar(
                select(User).where(User.id == candidate.user_id).with_for_update()
            )
            challenge = await session.scalar(
                select(AuthChallenge)
                .where(AuthChallenge.id == candidate.challenge_id)
                .with_for_update()
            )
            delivery = await session.scalar(
                select(AuthChallengeDelivery)
                .where(AuthChallengeDelivery.id == candidate.id)
                .with_for_update(skip_locked=True)
            )
            if delivery is None:
                return None
            if (
                user is None
                or challenge is None
                or challenge.user_id != delivery.user_id
                or challenge.consumed_at is not None
                or challenge.revoked_at is not None
                or challenge.expires_at <= now
                or delivery.expires_at <= now
                or challenge.security_epoch != user.security_epoch
                or challenge.password_version != user.password_version
                or challenge.target_email_digest
                != crypto.digest("email-target", user.email_normalized)
                or (challenge.purpose == "email_verify" and user.status != "pending")
                or (challenge.purpose == "password_recovery" and user.status != "active")
                or challenge.purpose not in {"email_verify", "password_recovery"}
            ):
                delivery.status = "expired"
                delivery.encrypted_payload = None
                delivery.encryption_key_version = None
                delivery.lease_owner = None
                delivery.lease_until = None
                return None
            if delivery.status == "pending" and (
                delivery.next_attempt_at is None or delivery.next_attempt_at > now
            ):
                return None
            if delivery.status == "sending" and (
                delivery.lease_until is None or delivery.lease_until > now
            ):
                return None
            if delivery.status not in {"pending", "sending"}:
                return None
            if delivery.attempt_count >= _MAX_ATTEMPTS:
                delivery.status = "failed"
                delivery.encrypted_payload = None
                delivery.encryption_key_version = None
                delivery.lease_owner = None
                delivery.lease_until = None
                delivery.next_attempt_at = None
                delivery.last_error_code = "attempt_limit"
                return None
            if delivery.encrypted_payload is None or delivery.encryption_key_version is None:
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            delivery.status = "sending"
            delivery.lease_owner = owner
            delivery.lease_until = now + _LEASE
            delivery.lease_generation += 1
            delivery.attempt_count += 1
            return MailLease(
                delivery_id=delivery.id,
                user_id=delivery.user_id,
                challenge_id=delivery.challenge_id,
                generation=delivery.lease_generation,
                owner=owner,
                encrypted_payload=delivery.encrypted_payload,
                encryption_key_version=delivery.encryption_key_version,
            )
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def finish_mail(runtime: Runtime, lease: MailLease, *, sent: bool) -> bool:
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    now = datetime.now(UTC)
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            user = await session.scalar(
                select(User).where(User.id == lease.user_id).with_for_update()
            )
            challenge = await session.scalar(
                select(AuthChallenge)
                .where(AuthChallenge.id == lease.challenge_id)
                .with_for_update()
            )
            delivery = await session.scalar(
                select(AuthChallengeDelivery)
                .where(AuthChallengeDelivery.id == lease.delivery_id)
                .with_for_update()
            )
            if (
                user is None
                or challenge is None
                or delivery is None
                or challenge.user_id != user.id
                or delivery.user_id != user.id
                or delivery.challenge_id != challenge.id
                or delivery.status != "sending"
                or delivery.lease_owner != lease.owner
                or delivery.lease_generation != lease.generation
            ):
                return False
            delivery.lease_owner = None
            delivery.lease_until = None
            if sent:
                delivery.status = "sent"
                delivery.encrypted_payload = None
                delivery.encryption_key_version = None
                delivery.next_attempt_at = None
                delivery.last_error_code = None
            elif delivery.attempt_count >= _MAX_ATTEMPTS or delivery.expires_at <= now:
                delivery.status = "failed"
                delivery.encrypted_payload = None
                delivery.encryption_key_version = None
                delivery.next_attempt_at = None
                delivery.last_error_code = "smtp_result_unknown"
            else:
                delivery.status = "pending"
                seconds = min(300, 2**delivery.attempt_count)
                delivery.next_attempt_at = now + timedelta(seconds=seconds)
                delivery.last_error_code = "smtp_result_unknown"
            return True
    except AppError:
        raise
    except Exception:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def deliver_one(runtime: Runtime, *, owner: UUID | None = None) -> bool:
    if not mail_ready(runtime):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    lease = await claim_due_mail(runtime, owner or uuid4())
    if lease is None:
        return False
    crypto = AuthCrypto.from_settings(runtime.settings)
    if lease.encryption_key_version != crypto.mail_key_version:
        await finish_mail(runtime, lease, sent=False)
        logger.warning("mail.delivery.key_unavailable")
        return True
    try:
        email, link, purpose = crypto.decrypt_mail(lease.encrypted_payload)
        await asyncio.to_thread(send_smtp_message, runtime.settings, email, link, purpose)
    except Exception:
        if await finish_mail(runtime, lease, sent=False):
            logger.warning("mail.delivery.retry_or_failed")
    else:
        if await finish_mail(runtime, lease, sent=True):
            logger.info("mail.delivery.sent")
    return True
