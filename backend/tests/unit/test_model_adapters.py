"""Provider boundary validation keeps unknown usage and forbids secret substitution."""

from uuid import UUID, uuid4

import pytest
from cryptography.fernet import Fernet
from pydantic import SecretStr

from app.adapters.models import ProviderFailure, normalize_usage, validate_mp3
from app.core.settings import Settings
from app.domain.errors import AppError
from app.services.credential_crypto import CredentialCrypto


def test_credential_envelope_binds_owner_resource_and_version() -> None:
    settings = Settings(
        app_env="test",
        instance_id="haruka-test-model",
        public_base_url="http://127.0.0.1:8080",
        credential_keyring={"v1": SecretStr(Fernet.generate_key().decode())},
    )
    cipher = CredentialCrypto(settings)
    owner, credential = uuid4(), uuid4()
    secret = SecretStr("synthetic-provider-key")
    encrypted = cipher.encrypt(owner, credential, 1, secret)
    assert secret.get_secret_value().encode() not in encrypted
    assert cipher.decrypt(owner, credential, 1, "v1", encrypted) == secret
    for user, resource, version in [
        (uuid4(), credential, 1),
        (owner, uuid4(), 1),
        (owner, credential, 2),
    ]:
        with pytest.raises(AppError):
            cipher.decrypt(user, resource, version, "v1", encrypted)


def test_absent_usage_remains_unknown_and_invalid_counters_are_rejected() -> None:
    assert normalize_usage({}) == {}
    assert normalize_usage(
        {"prompt_tokens": 0, "completion_tokens": None, "total_tokens": True}
    ) == {"input_tokens": 0}
    assert normalize_usage({"prompt_tokens": -1, "completion_tokens": 2**63}) == {}
    assert normalize_usage({"prompt_tokens_details": {"cached_tokens": 4}}) == {
        "cache_read_tokens": 4
    }


def test_mp3_requires_multiple_complete_valid_frames() -> None:
    frame = bytes.fromhex("fffb9000") + bytes(413)
    validate_mp3(frame * 2)
    for payload in [b"ID3", b"not audio", frame, frame * 2 + b"truncated"]:
        with pytest.raises(ProviderFailure, match="OUTPUT_INVALID"):
            validate_mp3(payload)


@pytest.mark.asyncio
async def test_fake_execution_is_rejected_outside_development_and_test() -> None:
    from app.adapters.models import execute_probe
    from app.schemas.model_settings import CredentialTest

    settings = Settings(
        app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
    ).model_copy(update={"app_env": "prod", "model_execution_mode": "fake"})
    with pytest.raises(ProviderFailure, match="FAKE_FORBIDDEN"):
        await execute_probe(
            settings,
            "openrouter",
            SecretStr("synthetic-key"),
            CredentialTest(
                expected_revision=1, capability="text", model_id="google/gemini-2.5-flash"
            ),
        )


def test_job_subscription_validates_version_ids_cursor_and_unknown_fields() -> None:
    from pydantic import ValidationError

    from app.schemas.model_settings import JobSubscription

    identifier = str(uuid4())
    valid = {
        "schema_version": 1,
        "type": "subscribe",
        "job_ids": [identifier],
        "cursors": {identifier: {"generation": 1, "sequence": 0}},
    }
    assert JobSubscription.model_validate(valid).job_ids == [UUID(identifier)]
    invalid = [
        {key: value for key, value in valid.items() if key != "schema_version"},
        {**valid, "schema_version": 2},
        {**valid, "schema_version": True},
        {**valid, "extra": "no"},
        {**valid, "job_ids": ["invalid"]},
        {**valid, "job_ids": []},
        {**valid, "cursors": {identifier: {"generation": 0, "sequence": 0}}},
        {**valid, "cursors": {identifier: {"generation": 1, "sequence": -1}}},
        {**valid, "cursors": {identifier: {"generation": 1, "sequence": "0"}}},
    ]
    for message in invalid:
        with pytest.raises(ValidationError):
            JobSubscription.model_validate(message)


def test_model_logging_keeps_ids_and_drops_keys_prompts_and_responses() -> None:
    import json
    import logging

    from app.core.logging import SafeJsonFormatter

    settings = Settings(
        app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
    )
    job, run = uuid4(), uuid4()
    sample_value = "synthetic-secret-never-log"
    record = logging.getLogger("app.model").makeRecord(
        "app.model",
        logging.INFO,
        "",
        1,
        "model.attempt.started",
        (),
        None,
        extra={
            "job_id": job,
            "ai_run_id": run,
            "key": sample_value,
            "prompt": "synthetic-prompt-never-log",
            "response": "synthetic-response-never-log",
        },
    )
    encoded = SafeJsonFormatter(settings, "worker").format(record)
    value = json.loads(encoded)
    assert value["job_id"] == str(job) and value["ai_run_id"] == str(run)
    assert (
        sample_value not in encoded
        and "synthetic-prompt" not in encoded
        and "synthetic-response" not in encoded
    )
