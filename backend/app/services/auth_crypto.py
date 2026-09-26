"""Bounded password work and purpose-separated identity token primitives."""

import asyncio
import hashlib
import hmac
import json
import secrets
from base64 import b64decode, urlsafe_b64encode
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from cryptography.fernet import Fernet, InvalidToken
from pydantic import SecretStr, TypeAdapter, ValidationError

from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError

_HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4, hash_len=32, salt_len=16)
_HASH_SLOTS = asyncio.Semaphore(4)
_DUMMY_HASH = (
    "$argon2id$v=19$m=65536,t=3,p=4$2tcNNi3eYs7Lg25kSdzHuA"
    "$Viw2TiO3L8lRqpP8IgHPmyOOqroiRYwM9u8fEduX3KM"
)
_REJECTED_PASSWORDS = frozenset(
    {
        "password",
        "password123",
        "password123456",
        "123456789012345",
        "qwerty123456789",
        "haruka123456789",
    }
)


def validate_new_password(value: SecretStr) -> str:
    password = value.get_secret_value()
    if (
        not 15 <= len(password) <= 128
        or len(password.encode("utf-8")) > 1024
        or password.casefold() in _REJECTED_PASSWORDS
    ):
        raise AppError(ErrorCode.INPUT_INVALID)
    return password


async def hash_password(value: SecretStr) -> str:
    password = validate_new_password(value)
    async with _HASH_SLOTS:
        return await asyncio.to_thread(_HASHER.hash, password)


async def verify_password(stored_hash: str | None, value: SecretStr) -> bool:
    candidate = value.get_secret_value()
    if not 1 <= len(candidate) <= 128 or len(candidate.encode("utf-8")) > 1024:
        return False
    encoded = stored_hash or _DUMMY_HASH
    async with _HASH_SLOTS:
        try:
            valid = await asyncio.to_thread(_HASHER.verify, encoded, candidate)
        except (InvalidHashError, VerificationError):
            return False
    return bool(valid and stored_hash is not None)


def new_opaque_token() -> str:
    return secrets.token_urlsafe(32)


@dataclass(frozen=True)
class AuthCrypto:
    signing_key: bytes
    digest_key: bytes
    issuer: str
    signing_key_version: str
    digest_key_version: str
    mail_key: bytes | None
    mail_key_version: str

    @classmethod
    def from_settings(cls, settings: Settings) -> "AuthCrypto":
        if settings.auth_signing_key is None or settings.auth_digest_key is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        return cls(
            signing_key=b64decode(settings.auth_signing_key.get_secret_value(), altchars=b"-_"),
            digest_key=b64decode(settings.auth_digest_key.get_secret_value(), altchars=b"-_"),
            issuer=settings.instance_id,
            signing_key_version=settings.auth_signing_key_version,
            digest_key_version=settings.auth_digest_key_version,
            mail_key=(
                b64decode(settings.mail_encryption_key.get_secret_value(), altchars=b"-_")
                if settings.mail_encryption_key is not None
                else None
            ),
            mail_key_version=settings.mail_encryption_key_version,
        )

    def digest(self, purpose: str, token: str) -> bytes:
        return hmac.new(
            self.digest_key,
            purpose.encode("ascii") + b"\x00" + token.encode("utf-8"),
            hashlib.sha256,
        ).digest()

    def access_jwt(
        self, *, user_id: UUID, session_id: UUID, generation: int, expires_at: datetime
    ) -> str:
        return jwt.encode(
            {
                "iss": self.issuer,
                "aud": "haruka-client-native",
                "sub": str(user_id),
                "sid": str(session_id),
                "gen": generation,
                "iat": datetime.now(UTC),
                "exp": expires_at,
                "jti": secrets.token_urlsafe(12),
            },
            self.signing_key,
            algorithm="HS256",
            headers={"kid": self.signing_key_version, "typ": "JWT"},
        )

    def decode_access(self, token: str) -> tuple[UUID, UUID, int]:
        try:
            header = jwt.get_unverified_header(token)
            if header.get("alg") != "HS256" or header.get("kid") != self.signing_key_version:
                raise ValueError("unsupported access token header")
            claims = jwt.decode(
                token,
                self.signing_key,
                algorithms=["HS256"],
                issuer=self.issuer,
                audience="haruka-client-native",
                options={"require": ["iss", "aud", "sub", "sid", "gen", "iat", "exp", "jti"]},
                leeway=0,
            )
            generation = claims["gen"]
            if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
                raise ValueError("access generation is invalid")
            return UUID(claims["sub"]), UUID(claims["sid"]), generation
        except jwt.ExpiredSignatureError:
            raise AppError(ErrorCode.ACCESS_EXPIRED) from None
        except (jwt.PyJWTError, KeyError, TypeError, ValueError):
            raise AppError(ErrorCode.SESSION_INVALID) from None

    def encrypt_mail(self, *, email: str, link: str, purpose: str) -> bytes:
        if self.mail_key is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        payload = json.dumps(
            {"email": email, "link": link, "purpose": purpose},
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        return Fernet(urlsafe_b64encode(self.mail_key)).encrypt(payload)

    def decrypt_mail(self, payload: bytes) -> tuple[str, str, str]:
        if self.mail_key is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        try:
            data = TypeAdapter(dict[str, str]).validate_json(
                Fernet(urlsafe_b64encode(self.mail_key)).decrypt(
                    payload, ttl=int(timedelta(days=2).total_seconds())
                )
            )
            email, link, purpose = data["email"], data["link"], data["purpose"]
            return email, link, purpose
        except (InvalidToken, ValidationError, ValueError, KeyError, TypeError):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None

    def encrypt_refresh_receipt(self, payload: bytes) -> bytes:
        key = hmac.new(self.signing_key, b"native-refresh-receipt-v1", hashlib.sha256).digest()
        return Fernet(urlsafe_b64encode(key)).encrypt(payload)

    def decrypt_refresh_receipt(self, payload: bytes) -> bytes:
        key = hmac.new(self.signing_key, b"native-refresh-receipt-v1", hashlib.sha256).digest()
        try:
            return Fernet(urlsafe_b64encode(key)).decrypt(payload, ttl=10)
        except InvalidToken:
            raise AppError(ErrorCode.SESSION_INVALID) from None
