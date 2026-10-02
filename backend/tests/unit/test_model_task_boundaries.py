"""Persistent task safety rules and speech HTTP boundaries without supplier calls."""

import json
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import cast
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import httpx2 as httpx
import pytest
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import models as adapter
from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import User
from app.models.model_tasks import (
    AiRun,
    ExternalCallAttempt,
    InboxEvent,
    Job,
    JobStage,
    ModelCatalogEntry,
    ProviderCredential,
)
from app.schemas.model_settings import CredentialTest, ModelLimits
from app.services import model_tasks as service


def session_mock() -> tuple[AsyncSession, AsyncMock]:
    mock = AsyncMock(spec=AsyncSession)
    return cast(AsyncSession, mock), mock


def current_scope() -> ScopeContext:
    return ScopeContext(uuid4(), uuid4(), "client", "web", 1, 1, 1, datetime.now(UTC))


def job_fixture(state: str) -> Job:
    now = datetime.now(UTC)
    return Job(
        id=uuid4(),
        operation_kind="credential_test",
        run_id=uuid4(),
        credential_id=uuid4(),
        state=state,
        revision=4,
        generation=2,
        progress_seq=3,
        fence=1,
        created_at=now,
        updated_at=now,
    )


@pytest.mark.asyncio
@pytest.mark.parametrize("state", ["queued", "running", "retry_wait", "cancel_requested"])
async def test_cancel_pending_and_running_tasks_preserves_attempt_boundary(state: str) -> None:
    session, mock = session_mock()
    current = current_scope()
    job = job_fixture(state)
    job.owner_user_id = current.user_id
    run = AiRun(state="running")
    mock.scalar.side_effect = [None, job]
    mock.get.return_value = run
    with patch.object(service.configuration, "authorize", new_callable=AsyncMock) as authorize:
        result = await service.change_job(session, current, job.id, 4, retry=False)
    assert result.state == ("cancel_requested" if state == "running" else "cancelled")
    assert result.revision == 5 and result.sequence == 4
    assert job.generation == 2 and job.fence == 1
    assert run.state == ("running" if state == "running" else "cancelled")
    assert mock.add.call_count == 1
    assert authorize.await_args is not None
    assert "client.job.cancel" in authorize.await_args.args[2]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "retry,state,calls", [(False, "succeeded", 0), (True, "running", 0), (True, "failed", 1)]
)
async def test_invalid_changes_or_unconfirmed_new_attempt_do_not_mutate_task(
    retry: bool,
    state: str,
    calls: int,
) -> None:
    session, mock = session_mock()
    current, job = current_scope(), job_fixture(state)
    mock.scalar.side_effect = [None, job, calls]
    mock.get.return_value = AiRun(state="failed")
    with (
        patch.object(service.configuration, "authorize", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await service.change_job(session, current, job.id, 4, retry=retry)
    assert error.value.code == ErrorCode.STATE_CONFLICT
    assert job.state == state and job.revision == 4 and job.generation == 2
    mock.add.assert_not_called()


@pytest.mark.asyncio
async def test_confirmed_retry_creates_new_generation_and_preserves_prior_run() -> None:
    session, mock = session_mock()
    current, job = current_scope(), job_fixture("failed")
    job.owner_user_id = current.user_id
    job.input_refs = {"voice_id": None}
    old_id = job.run_id
    old = AiRun(
        id=old_id,
        state="failed",
        provider="openrouter",
        model_id=adapter.TEXT_MODEL,
        capability="text",
        generation_config={"catalog_revision": 1, "expected_revision": 1},
    )
    secret = ProviderCredential(id=uuid4(), provider="openrouter", revision=6, credential_version=8)
    model = ModelCatalogEntry(revision=5)
    mock.scalar.side_effect = [None, job, 1]
    mock.get.return_value = old
    with (
        patch.object(service.configuration, "authorize", new_callable=AsyncMock),
        patch.object(service, "check_capacity", new_callable=AsyncMock),
        patch.object(
            service.configuration, "credential", new_callable=AsyncMock, return_value=secret
        ),
        patch.object(
            service.configuration, "require_model", new_callable=AsyncMock, return_value=model
        ),
    ):
        result = await service.change_job(
            session,
            current,
            job.id,
            4,
            retry=True,
            confirm_new_attempt=True,
            credential_id=secret.id,
        )
    assert result.state == "queued" and result.generation == 3 and result.run_id != old_id
    assert old.state == "failed" and old.generation_config["catalog_revision"] == 1
    added = [call.args[0] for call in mock.add.call_args_list]
    new = next(value for value in added if isinstance(value, AiRun))
    assert new.generation == 3 and new.credential_version == 8
    assert (
        new.generation_config["catalog_revision"] == 5
        and new.generation_config["expected_revision"] == 6
    )
    assert new.owner_user_id == current.user_id


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "since,until",
    [
        (None, datetime(2026, 1, 1)),
        (datetime(2026, 1, 1), datetime(2026, 1, 2, tzinfo=UTC)),
        (datetime(2026, 1, 3, tzinfo=UTC), datetime(2026, 1, 2, tzinfo=UTC)),
    ],
)
async def test_usage_rejects_ambiguous_or_reversed_date_window_before_query(
    since: datetime | None,
    until: datetime,
) -> None:
    session, mock = session_mock()
    with pytest.raises(AppError) as error:
        await service.usage_projection(session, uuid4(), since=since, until=until)
    assert error.value.code == ErrorCode.INPUT_INVALID
    mock.execute.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("reason", ["absent", "wrong_owner", "inactive", "locked"])
async def test_worker_rejects_invalid_actor_before_permission_or_provider_access(
    reason: str,
) -> None:
    session, mock = session_mock()
    job = job_fixture("queued")
    job.owner_user_id = job.actor_user_id = uuid4()
    user = User(
        id=job.actor_user_id if reason != "wrong_owner" else uuid4(),
        status="disabled" if reason == "inactive" else "active",
        locked_until=datetime.now(UTC) + timedelta(minutes=1) if reason == "locked" else None,
    )
    mock.scalar.return_value = None if reason == "absent" else user
    runtime = Runtime(
        Settings(
            app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
        )
    )
    with (
        patch(
            "app.services.auth_context.require_permissions", new_callable=AsyncMock
        ) as permissions,
        pytest.raises(AppError) as error,
    ):
        await service.worker_scope(session, runtime, job)
    assert error.value.code == ErrorCode.PERMISSION_DENIED
    permissions.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("existing", [False, True])
async def test_inbox_commits_once_and_rejects_changed_redelivery(existing: bool) -> None:
    session, mock = session_mock()
    identifier = uuid4()
    mock.scalar.return_value = InboxEvent(payload_digest=b"original") if existing else None
    await service.commit_inbox(session, (identifier, b"original"))
    assert mock.add.call_count == (0 if existing else 1)
    if existing:
        with pytest.raises(AppError) as error:
            await service.commit_inbox(session, (identifier, b"changed"))
        assert error.value.code == ErrorCode.IDEMPOTENCY_CONFLICT
        mock.add.assert_not_called()


@pytest.mark.parametrize(
    "capability,changes",
    [
        ("text", {"enabled": False}),
        ("text", {"max_model_calls": 0}),
        ("text", {"max_output_tokens": 0}),
        ("text", {"timeout_seconds": 0}),
        ("vision", {"max_test_image_bytes": 0}),
        ("tts", {"tts_timeout_seconds": 0}),
        ("tts", {"max_tts_characters": 5}),
    ],
)
def test_probe_limit_protection_precedes_supplier_call(
    capability: str, changes: dict[str, object]
) -> None:
    config = CredentialTest.model_validate(
        {"expected_revision": 1, "capability": capability, "model_id": "exact"}
    )
    with pytest.raises(AppError) as error:
        service.require_probe_limits(
            ModelLimits.model_validate(ModelLimits().model_dump() | changes), config
        )
    assert error.value.code == ErrorCode.QUOTA_EXCEEDED


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "status,content_type,payload,error_code",
    [
        (401, "audio/mpeg", b"", "KEY_REJECTED"),
        (429, "audio/mpeg", b"", "PROVIDER_RATE_LIMIT"),
        (200, "text/html", b"html", "OUTPUT_INVALID"),
        (200, "audio/mpeg", b"broken", "OUTPUT_INVALID"),
        (200, "audio/mpeg", bytes(1024 * 1024 + 1), "OUTPUT_INVALID"),
    ],
    ids=["key-rejected", "rate-limit", "wrong-type", "bad-frames", "oversize"],
)
async def test_speech_rejects_http_format_and_audio_failures_without_fallback(
    status: int,
    content_type: str,
    payload: bytes,
    error_code: str,
) -> None:
    requests: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(status, headers={"content-type": content_type}, content=payload)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handle))
    config = CredentialTest(
        expected_revision=1,
        capability="tts",
        model_id=adapter.TTS_MODEL,
        voice_id="Kore",
        language_tag="en",
    )
    with (
        patch.object(adapter.httpx, "AsyncClient", return_value=client),
        pytest.raises(adapter.ProviderFailure) as error,
    ):
        await adapter.speech_probe(SecretStr("synthetic-speech-key"), config)
    assert error.value.code == error_code
    assert len(requests) == 1
    assert b'"allow_fallbacks":false' in requests[0].content


@pytest.mark.asyncio
async def test_speech_accepts_complete_frames_and_reports_only_character_usage() -> None:
    frame = bytes.fromhex("fffb9000") + bytes(413)
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda request: httpx.Response(
                200, headers={"content-type": "audio/mpeg; charset=binary"}, content=frame * 2
            )
        )
    )
    config = CredentialTest(
        expected_revision=1, capability="tts", model_id=adapter.TTS_MODEL, voice_id="Kore"
    )
    with patch.object(adapter.httpx, "AsyncClient", return_value=client):
        result = await adapter.speech_probe(SecretStr("synthetic-speech-key"), config)
    assert result.usage == {"input_characters": 6}
    assert result.simulated is False


@pytest.mark.asyncio
@pytest.mark.parametrize("vision,valid", [(False, True), (True, True), (True, False)])
async def test_openrouter_structured_probe_uses_exact_provider_and_keeps_failure_usage(
    vision: bool,
    valid: bool,
) -> None:
    requests: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "id": "synthetic-completion",
                "object": "chat.completion",
                "provider": "synthetic-provider",
                "created": 1,
                "model": adapter.TEXT_MODEL,
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "logprobs": None,
                        "message": {
                            "role": "assistant",
                            "content": json.dumps(
                                {"ok": True, "color": "red" if valid else "blue"}
                                if vision
                                else {"ok": True}
                            ),
                        },
                    }
                ],
                "usage": {
                    "prompt_tokens": 12,
                    "completion_tokens": 4,
                    "total_tokens": 16,
                    "prompt_tokens_details": {"cached_tokens": 3},
                },
            },
        )

    original_init = httpx.AsyncClient.__init__

    def isolated_init(client: httpx.AsyncClient, **kwargs: object) -> None:
        original_init(
            client,
            transport=httpx.MockTransport(handle),
            timeout=60,
            follow_redirects=False,
            event_hooks=cast(
                dict[str, list[Callable[[httpx.Response], Awaitable[None]]]], kwargs["event_hooks"]
            ),
        )

    settings = Settings(
        app_env="test",
        instance_id="haruka-test-model",
        public_base_url="http://127.0.0.1:8080",
        model_execution_mode="live",
    )
    config = CredentialTest(
        expected_revision=1, capability="vision" if vision else "text", model_id=adapter.TEXT_MODEL
    )
    with patch.object(adapter.httpx.AsyncClient, "__init__", new=isolated_init):
        if valid:
            result = await adapter.execute_probe(
                settings, "openrouter", SecretStr("synthetic-key"), config
            )
        else:
            with pytest.raises(adapter.ProviderFailure) as error:
                await adapter.execute_probe(
                    settings, "openrouter", SecretStr("synthetic-key"), config
                )
            assert error.value.code == "OUTPUT_INVALID" and error.value.facts is not None
            result = error.value.facts
    assert result.usage == {
        "input_tokens": 12,
        "output_tokens": 4,
        "total_tokens": 16,
        "cache_read_tokens": 3,
    }
    assert result.simulated is False
    assert len(requests) == 1
    body = json.loads(requests[0].content)
    assert body["model"] == adapter.TEXT_MODEL
    assert body["provider"] == {"allow_fallbacks": False, "require_parameters": True}


def worker_runtime(mock: AsyncMock) -> Runtime:
    mock.__aenter__.return_value = mock
    resources = MagicMock(spec=Resources)
    resources.database = MagicMock()
    resources.database.sessions.return_value = mock
    return Runtime(
        Settings(
            app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
        ),
        resources=cast(Resources, resources),
    )


@pytest.mark.asyncio
@pytest.mark.parametrize("cancelling,started", [(False, True), (True, True), (False, False)])
async def test_restart_after_attempt_started_never_reissues_supplier_call(
    cancelling: bool,
    started: bool,
) -> None:
    _, mock = session_mock()
    job = job_fixture("cancel_requested" if cancelling else "running")
    job.owner_user_id = uuid4()
    run = AiRun(state="running")
    stage = JobStage(state="running")
    attempt = ExternalCallAttempt(
        status="started" if started else "unknown", aggregation_revision=1
    )
    mock.get.return_value = job
    mock.scalar.side_effect = [None, job, run, stage, attempt]
    with (
        patch.object(service, "lock_job_owner", new_callable=AsyncMock),
        patch.object(service, "execute_probe", new_callable=AsyncMock) as probe,
    ):
        await service.execute_job(worker_runtime(mock), job.id, "worker")
    assert job.state == ("cancelled" if cancelling else "blocked")
    assert run.state == "unknown_outcome" and job.error_code == "EXTERNAL_RESULT_UNKNOWN"
    assert job.fence == 2 and job.lease_owner is None and job.lease_expires_at is None
    assert attempt.status == "unknown" and attempt.aggregation_revision == (2 if started else 1)
    probe.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "status,cancelling",
    [("succeeded", False), ("failed", False), ("unknown", False), ("succeeded", True)],
)
async def test_recorded_attempt_publication_uses_current_fence_and_authorized_metadata(
    status: str,
    cancelling: bool,
) -> None:
    _, mock = session_mock()
    job = job_fixture("cancel_requested" if cancelling else "running")
    job.owner_user_id = uuid4()
    run = AiRun(
        credential_version=7,
        provider="openrouter",
        model_id=adapter.TEXT_MODEL,
        capability="text",
        generation_config={"catalog_revision": 3},
    )
    attempt = ExternalCallAttempt(
        id=uuid4(), status=status, error_code=None if status == "succeeded" else "OUTPUT_INVALID"
    )
    stage = JobStage(
        state="committed", fence=job.fence, result_refs={"attempt_id": str(attempt.id)}
    )
    mock.scalar.side_effect = [job, run, stage, attempt]
    with (
        patch.object(service, "lock_job_owner", new_callable=AsyncMock),
        patch.object(service, "worker_scope", new_callable=AsyncMock),
        patch.object(
            service.configuration,
            "credential",
            new_callable=AsyncMock,
            return_value=ProviderCredential(credential_version=7),
        ),
        patch.object(
            service.configuration,
            "require_model",
            new_callable=AsyncMock,
            return_value=ModelCatalogEntry(revision=3),
        ),
        patch.object(service, "execute_probe", new_callable=AsyncMock) as probe,
    ):
        await service.publish_recorded(worker_runtime(mock), job.id)
    assert job.state == (
        "cancelled" if cancelling else "blocked" if status == "unknown" else status
    )
    assert run.state == ("unknown_outcome" if status == "unknown" else job.state)
    assert job.revision == 5 and job.progress_seq == 4
    assert job.finished_at is not None and job.lease_owner is None
    probe.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "credential_version,catalog_revision,stage_fence", [(8, 3, 1), (7, 4, 1), (7, 3, 2)]
)
async def test_recorded_publication_blocks_changed_key_catalog_and_ignores_stale_stage(
    credential_version: int,
    catalog_revision: int,
    stage_fence: int,
) -> None:
    _, mock = session_mock()
    job = job_fixture("running")
    job.owner_user_id = uuid4()
    run = AiRun(
        credential_version=7,
        provider="openrouter",
        model_id=adapter.TEXT_MODEL,
        capability="text",
        generation_config={"catalog_revision": 3},
    )
    attempt = ExternalCallAttempt(id=uuid4(), status="succeeded")
    stage = JobStage(
        state="committed", fence=stage_fence, result_refs={"attempt_id": str(attempt.id)}
    )
    mock.scalar.side_effect = [job, run, stage, attempt]
    with (
        patch.object(service, "lock_job_owner", new_callable=AsyncMock),
        patch.object(service, "worker_scope", new_callable=AsyncMock),
        patch.object(
            service.configuration,
            "credential",
            new_callable=AsyncMock,
            return_value=ProviderCredential(credential_version=credential_version),
        ),
        patch.object(
            service.configuration,
            "require_model",
            new_callable=AsyncMock,
            return_value=ModelCatalogEntry(revision=catalog_revision),
        ),
    ):
        await service.publish_recorded(worker_runtime(mock), job.id)
    if stage_fence != job.fence:
        assert job.state == "running" and job.revision == 4
        mock.add.assert_not_called()
    else:
        assert job.state == "blocked" and run.state == "interrupted"
        assert job.error_code == ("KEY_REQUIRED" if credential_version != 7 else "STATE_CONFLICT")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    ["permission", "rotated-key", "catalog-fence", "disabled-limit", "missing-ciphertext"],
)
async def test_worker_preflight_blocks_before_creating_attempt_or_calling_provider(
    failure: str,
) -> None:
    _, mock = session_mock()
    job = job_fixture("queued")
    job.owner_user_id = uuid4()
    run = AiRun(
        id=job.run_id,
        state="queued",
        credential_version=7,
        provider="openrouter",
        model_id=adapter.TEXT_MODEL,
        capability="text",
        generation_config={
            "expected_revision": 1,
            "capability": "text",
            "model_id": adapter.TEXT_MODEL,
            "catalog_revision": 3,
        },
    )
    stage = JobStage(state="pending")
    secret = ProviderCredential(
        credential_version=8 if failure == "rotated-key" else 7, encrypted_key=None
    )
    mock.get.return_value = job
    mock.scalar.side_effect = [None, job, run, stage, None]
    with (
        patch.object(service, "lock_job_owner", new_callable=AsyncMock),
        patch.object(
            service,
            "worker_scope",
            new_callable=AsyncMock,
            side_effect=AppError(ErrorCode.PERMISSION_DENIED) if failure == "permission" else None,
        ),
        patch.object(
            service.configuration, "credential", new_callable=AsyncMock, return_value=secret
        ),
        patch.object(
            service.configuration,
            "require_model",
            new_callable=AsyncMock,
            return_value=ModelCatalogEntry(revision=4 if failure == "catalog-fence" else 3),
        ),
        patch.object(
            service.configuration,
            "effective_limits",
            new_callable=AsyncMock,
            return_value=ModelLimits(enabled=failure != "disabled-limit"),
        ),
        patch.object(service, "execute_probe", new_callable=AsyncMock) as probe,
    ):
        await service.execute_job(worker_runtime(mock), job.id, "worker")
    expected = (
        "PERMISSION_DENIED"
        if failure == "permission"
        else "STATE_CONFLICT"
        if failure == "catalog-fence"
        else "QUOTA_EXCEEDED"
        if failure == "disabled-limit"
        else "KEY_REQUIRED"
    )
    assert job.state == "blocked" and run.state == "interrupted"
    assert job.error_code == expected and run.error_code == expected
    assert job.fence == 1 and stage.state == "pending"
    assert job.revision == 5 and job.progress_seq == 4
    assert not any(
        isinstance(call.args[0], ExternalCallAttempt) for call in mock.add.call_args_list
    )
    probe.assert_not_awaited()


@pytest.mark.asyncio
async def test_cancel_requested_before_first_attempt_commits_cancel_without_supplier() -> None:
    _, mock = session_mock()
    job = job_fixture("cancel_requested")
    job.owner_user_id = uuid4()
    run = AiRun(id=job.run_id, state="queued")
    stage = JobStage(state="pending")
    mock.get.return_value = job
    mock.scalar.side_effect = [None, job, run, stage, None]
    with (
        patch.object(service, "lock_job_owner", new_callable=AsyncMock),
        patch.object(service, "worker_scope", new_callable=AsyncMock) as auth,
        patch.object(service, "execute_probe", new_callable=AsyncMock) as probe,
        patch.object(service, "commit_inbox", new_callable=AsyncMock) as inbox,
    ):
        await service.execute_job(worker_runtime(mock), job.id, "worker")
    assert job.state == run.state == "cancelled"
    assert job.finished_at == run.finished_at and job.finished_at is not None
    assert job.fence == 2 and job.revision == 5 and job.progress_seq == 4
    assert job.lease_owner is None and job.lease_expires_at is None
    auth.assert_not_awaited()
    probe.assert_not_awaited()
    inbox.assert_awaited_once()
    assert not any(
        isinstance(call.args[0], ExternalCallAttempt) for call in mock.add.call_args_list
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    ["revoked-after-call", "invalid-output", "http-rejected", "unknown-outcome", "late-generation"],
)
async def test_attempt_facts_are_sealed_but_late_or_unauthorized_results_do_not_publish(
    failure: str,
) -> None:
    from pydantic_ai.exceptions import UnexpectedModelBehavior

    class Rejected(Exception):
        status_code = 401

    _, mock = session_mock()
    job = job_fixture("queued")
    job.owner_user_id = uuid4()
    run = AiRun(
        id=job.run_id,
        state="queued",
        credential_version=7,
        provider="openrouter",
        model_id=adapter.TEXT_MODEL,
        capability="text",
        generation_config={
            "expected_revision": 1,
            "capability": "text",
            "model_id": adapter.TEXT_MODEL,
            "catalog_revision": 3,
        },
    )
    stage = JobStage(state="pending", fence=1, result_refs={})
    attempt = ExternalCallAttempt(id=uuid4(), status="started", aggregation_revision=0, usage={})
    secret = ProviderCredential(
        id=job.credential_id,
        owner_user_id=job.owner_user_id,
        credential_version=7,
        encryption_key_version=1,
        encrypted_key=b"synthetic-encrypted",
    )
    current_job = job_fixture("running") if failure == "late-generation" else job
    if failure == "late-generation":
        current_job.generation = 3
    mock.get.return_value = job
    mock.scalar.side_effect = [
        None,
        job,
        run,
        stage,
        None,
        attempt,
        stage,
        current_job,
        job,
        run,
        stage,
        attempt,
    ]
    outcome = adapter.ModelOutcome(
        {
            "input_tokens": 3,
            "output_tokens": None,
            "cache_read_tokens": 0,
            "unrecognized": 17,
            "total_tokens": -1,
        },
        "fixture-safe",
        True,
    )
    error = (
        UnexpectedModelBehavior("synthetic invalid output")
        if failure == "invalid-output"
        else Rejected()
        if failure == "http-rejected"
        else RuntimeError("fixturesecret")
        if failure == "unknown-outcome"
        else None
    )

    async def isolated_probe(*_args: object) -> adapter.ModelOutcome:
        created = next(
            call.args[0]
            for call in mock.add.call_args_list
            if isinstance(call.args[0], ExternalCallAttempt)
        )
        attempt.id = created.id
        if error is not None:
            raise error
        return outcome

    with (
        patch.object(service, "lock_job_owner", new_callable=AsyncMock),
        patch.object(
            service,
            "worker_scope",
            new_callable=AsyncMock,
            side_effect=[None, AppError(ErrorCode.PERMISSION_DENIED)]
            if failure == "revoked-after-call"
            else None,
        ),
        patch.object(
            service.configuration, "credential", new_callable=AsyncMock, return_value=secret
        ),
        patch.object(
            service.configuration,
            "require_model",
            new_callable=AsyncMock,
            return_value=ModelCatalogEntry(revision=3),
        ),
        patch.object(
            service.configuration,
            "effective_limits",
            new_callable=AsyncMock,
            return_value=ModelLimits(),
        ),
        patch.object(service.CredentialCrypto, "decrypt", return_value=SecretStr("synthetic-key")),
        patch.object(service, "heartbeat_lease", new_callable=AsyncMock),
        patch.object(
            service,
            "execute_probe",
            new_callable=AsyncMock,
            side_effect=isolated_probe,
        ) as probe,
    ):
        if failure == "late-generation":
            with pytest.raises(AppError) as denied:
                await service.execute_job(worker_runtime(mock), job.id, "worker")
            assert denied.value.code == ErrorCode.STATE_CONFLICT
        else:
            await service.execute_job(worker_runtime(mock), job.id, "worker")
    probe.assert_awaited_once()
    assert attempt.aggregation_revision == 1 and attempt.finished_at is not None
    if failure in {"revoked-after-call", "late-generation"}:
        assert attempt.status == "succeeded"
        assert attempt.usage == {"input_tokens": 3, "output_tokens": None, "cache_read_tokens": 0}
        assert attempt.input_tokens == 3 and attempt.usage_status == "partial"
    else:
        assert attempt.status == ("unknown" if failure == "unknown-outcome" else "failed")
        assert attempt.error_code == (
            "EXTERNAL_RESULT_UNKNOWN"
            if failure == "unknown-outcome"
            else "KEY_REJECTED"
            if failure == "http-rejected"
            else "OUTPUT_INVALID"
        )
    if failure == "late-generation":
        assert stage.state == "running" and stage.result_refs == {}
    elif failure == "revoked-after-call":
        assert (
            job.state == "blocked"
            and run.state == "interrupted"
            and job.error_code == "PERMISSION_DENIED"
        )
        assert stage.state == "committed"
    else:
        assert job.state == ("blocked" if failure == "unknown-outcome" else "failed")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", ["disabled", "invalid-key", "receipt-replay", "receipt-conflict"]
)
async def test_acceptance_rejects_or_replays_before_new_attempt_and_capacity(failure: str) -> None:
    session, mock = session_mock()
    current = current_scope()
    runtime = worker_runtime(mock)
    runtime = Runtime(
        runtime.settings.model_copy(
            update={"model_execution_mode": "disabled" if failure == "disabled" else "fake"}
        ),
        resources=runtime.resources,
    )
    identifier = uuid4()
    payload = CredentialTest(expected_revision=1, capability="text", model_id=adapter.TEXT_MODEL)
    old = job_fixture("succeeded")
    old.input_digest = service.digest(
        payload.model_dump(mode="json")
        | {
            "credential_id": str(identifier),
            "required_permissions": [
                "client.login",
                "client.credential.read",
                "client.credential.test",
            ],
            "input_schema_version": 1,
        }
    )
    if failure == "receipt-conflict":
        old.input_digest = b"changed"
    mock.scalar.return_value = old
    with (
        patch.object(service, "lock_policy", new_callable=AsyncMock),
        patch.object(service.configuration, "authorize", new_callable=AsyncMock) as authorize,
        patch.object(service, "check_capacity", new_callable=AsyncMock) as capacity,
        patch.object(service.configuration, "credential", new_callable=AsyncMock) as credential,
    ):
        if failure == "receipt-replay":
            result = await service.accept_test(
                session, runtime, current, identifier, payload, "valid-idempotency-key"
            )
            assert (
                result.job_id == old.id
                and result.run_id == old.run_id
                and result.generation == old.generation
            )
        else:
            with pytest.raises(AppError) as error:
                await service.accept_test(
                    session,
                    runtime,
                    current,
                    identifier,
                    payload,
                    "bad key" if failure == "invalid-key" else "valid-idempotency-key",
                )
            assert error.value.code == (
                ErrorCode.SERVICE_UNAVAILABLE
                if failure == "disabled"
                else ErrorCode.INPUT_INVALID
                if failure == "invalid-key"
                else ErrorCode.IDEMPOTENCY_CONFLICT
            )
    authorize.assert_awaited_once_with(
        session, current, ("client.credential.read", "client.credential.test")
    )
    capacity.assert_not_awaited()
    credential.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["missing-policy", "owner-cap", "instance-cap", "disabled"])
async def test_reservation_capacity_fails_closed_at_persistent_policy_root(failure: str) -> None:
    from app.models.model_tasks import ModelLimitPolicy, UserRuntimeLimit

    session, mock = session_mock()
    owner = uuid4()
    mock.scalar.side_effect = (
        [None]
        if failure == "missing-policy"
        else [
            ModelLimitPolicy(),
            UserRuntimeLimit(value_limit=0) if failure == "owner-cap" else None,
            0,
            4 if failure == "instance-cap" else 0,
        ]
    )
    with (
        patch.object(
            service.configuration,
            "effective_limits",
            new_callable=AsyncMock,
            return_value=ModelLimits(enabled=failure != "disabled"),
        ),
        pytest.raises(AppError) as error,
    ):
        await service.check_capacity(session, owner)
    assert error.value.code == (
        ErrorCode.SERVICE_UNAVAILABLE if failure == "missing-policy" else ErrorCode.QUOTA_EXCEEDED
    )
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    ["missing-job", "wrong-fence", "wrong-generation", "wrong-worker", "terminal", "renew"],
)
async def test_heartbeat_renews_only_current_worker_generation_and_fence(failure: str) -> None:
    import asyncio

    _, mock = session_mock()
    job = job_fixture("succeeded" if failure == "terminal" else "running")
    job.lease_owner = "other-worker" if failure == "wrong-worker" else "worker"
    job.lease_expires_at = datetime.now(UTC)
    job.heartbeat_at = None
    if failure == "wrong-fence":
        job.fence = 3
    if failure == "wrong-generation":
        job.generation = 3
    mock.scalar.return_value = None if failure == "missing-job" else job
    stopped = MagicMock(spec=asyncio.Event)
    stopped.is_set.side_effect = [False, True]
    stopped.wait = AsyncMock(return_value=False)

    async def expired(waiter: Awaitable[bool], *, timeout: float) -> bool:  # noqa: ASYNC109 - match asyncio.wait_for boundary
        assert timeout == 15
        await waiter
        raise TimeoutError

    with (
        patch.object(service.asyncio, "wait_for", new=expired),
        patch.object(service, "lock_job_owner", new_callable=AsyncMock) as lock,
    ):
        await service.heartbeat_lease(worker_runtime(mock), job.id, "worker", 1, 2, stopped)
    lock.assert_awaited_once()
    if failure == "renew":
        heartbeat_at = job.heartbeat_at
        assert heartbeat_at is not None and job.updated_at == heartbeat_at
        assert job.lease_expires_at == heartbeat_at + timedelta(seconds=120)
    else:
        assert job.heartbeat_at is None
    assert job.revision == 4 and job.progress_seq == 3
    assert not any(
        isinstance(call.args[0], ExternalCallAttempt) for call in mock.add.call_args_list
    )


@pytest.mark.asyncio
async def test_heartbeat_stops_without_database_access_when_stop_event_arrives() -> None:
    import asyncio

    _, mock = session_mock()
    stopped = asyncio.Event()
    stopped.set()
    await service.heartbeat_lease(worker_runtime(mock), uuid4(), "worker", 1, 2, stopped)
    mock.scalar.assert_not_awaited()


@pytest.mark.asyncio
async def test_heartbeat_waiting_stop_event_returns_before_lease_query() -> None:
    import asyncio

    _, mock = session_mock()
    stopped = asyncio.Event()
    asyncio.get_running_loop().call_soon(stopped.set)
    await service.heartbeat_lease(worker_runtime(mock), uuid4(), "worker", 1, 2, stopped)
    assert stopped.is_set()
    mock.scalar.assert_not_awaited()


@pytest.mark.asyncio
async def test_model_worker_and_publication_fail_closed_when_runtime_resources_disappear() -> None:
    import asyncio

    runtime = Runtime(
        Settings(
            app_env="test", instance_id="haruka-test-model", public_base_url="http://127.0.0.1:8080"
        )
    )
    with patch.object(service, "execute_probe", new_callable=AsyncMock) as probe:
        with pytest.raises(AppError) as execution:
            await service.execute_job(runtime, uuid4(), "worker")
        with pytest.raises(AppError) as publication:
            await service.publish_recorded(runtime, uuid4())
        await service.heartbeat_lease(runtime, uuid4(), "worker", 1, 2, asyncio.Event())
    assert execution.value.code == publication.value.code == ErrorCode.SERVICE_UNAVAILABLE
    probe.assert_not_awaited()
