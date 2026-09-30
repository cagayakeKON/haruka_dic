"""Purpose-bound owner/version encryption; deployment keys never enter API DTOs."""

import json
from uuid import UUID

from cryptography.fernet import Fernet, InvalidToken
from pydantic import SecretStr

from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError


class CredentialCrypto:
    def __init__(self, settings: Settings):
        self.keyring = settings.credential_keyring
        self.version = settings.credential_encryption_key_version

    def encrypt(self, owner: UUID, credential: UUID, version: int, key: SecretStr) -> bytes:
        active = self.keyring.get(self.version)
        if active is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        envelope = json.dumps(
            {
                "purpose": "provider_credential",
                "owner": str(owner),
                "credential": str(credential),
                "version": version,
                "key": key.get_secret_value(),
            }
        )
        return Fernet(active.get_secret_value().encode()).encrypt(envelope.encode())

    def decrypt(
        self,
        owner: UUID,
        credential: UUID,
        version: int,
        encryption_version: str,
        ciphertext: bytes,
    ) -> SecretStr:
        active = self.keyring.get(encryption_version)
        if active is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        try:
            data = json.loads(Fernet(active.get_secret_value().encode()).decrypt(ciphertext))
            if (
                data["purpose"] != "provider_credential"
                or data["owner"] != str(owner)
                or data["credential"] != str(credential)
                or data["version"] != version
            ):
                raise ValueError("invalid envelope")
            return SecretStr(data["key"])
        except (InvalidToken, ValueError, KeyError, TypeError):
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
