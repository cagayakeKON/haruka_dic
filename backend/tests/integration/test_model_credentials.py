"""Credential isolation, durable attempts and model-setting CAS on real PG/Redis."""

import asyncio
from collections.abc import Awaitable, Callable
from concurrent.futures import Future
from contextlib import suppress
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol, cast
from uuid import UUID

import pytest
from confluent_kafka.admin import AdminClient
from confluent_kafka.cimpl import NewTopic
from cryptography.fernet import Fernet
from pydantic import SecretStr
from sqlalchemy import func, select

from app.bootstrap import Runtime
from app.core.logging import configure_logging
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthPolicy, AuthSession
from app.models.model_tasks import ExternalCallAttempt, ProviderCredential
from app.services.model_tasks import execute_job
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]
from tests.support.bound_client import BoundAsyncClient


class _KafkaAdmin(Protocol):
    def create_topics(self, new_topics: list[NewTopic]) -> dict[str, Future[object]]: ...
    def delete_topics(self, topics: list[str]) -> dict[str, Future[object]]: ...


ROOT = Path(__file__).resolve().parents[3]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


async def test_credentials_isolation_cas_and_one_durable_fake_attempt(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for owner, headers in _owner(
        runtime, maintenance, f"model-a-{run_id}@haruka.example.test"
    ):
        async for other, _other_headers in _owner(
            runtime, maintenance, f"model-b-{run_id}@haruka.example.test"
        ):
            response = await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "label": "test", "key": "synthetic-model-key"},
                headers=headers,
            )
            assert response.status_code == 201, response.text
            credential = response.json()["data"]
            identifier = credential["id"]
            assert "synthetic-model-key" not in response.text
            assert (await other.get("/api/v1/provider-credentials")).json()["data"]["items"] == []
            assert (
                await other.get(f"/api/v1/provider-credentials/{identifier}/deletion-impact")
            ).status_code == 404
            async with runtime.resources.database.sessions() as session:
                stored = await session.get(ProviderCredential, UUID(identifier))
                assert stored is not None and stored.encrypted_key is not None
                assert b"synthetic-model-key" not in stored.encrypted_key
            settings = (await owner.get("/api/v1/users/me/model-settings")).json()["data"]
            bindings = {
                "text": {
                    "credential_id": identifier,
                    "provider": "openrouter",
                    "model_id": "google/gemini-2.5-flash",
                }
            }
            saved = await owner.patch(
                "/api/v1/users/me/model-settings",
                json={"expected_revision": settings["revision"], "bindings": bindings},
                headers=headers,
            )
            assert saved.status_code == 200, saved.text
            stale = await owner.patch(
                "/api/v1/users/me/model-settings",
                json={"expected_revision": settings["revision"], "bindings": bindings},
                headers=headers,
            )
            assert stale.status_code == 409
            assert (await owner.get("/api/v1/users/me/settings")).json()["data"][
                "revision"
            ] == saved.json()["data"]["revision"]
            request = {
                "expected_revision": credential["revision"],
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            }
            test_headers = {**headers, "Idempotency-Key": "model-test-" + run_id}
            accepted = await owner.post(
                f"/api/v1/provider-credentials/{identifier}/test",
                json=request,
                headers=test_headers,
            )
            assert accepted.status_code == 202, accepted.text
            accepted_data = accepted.json()["data"]
            duplicate = await owner.post(
                f"/api/v1/provider-credentials/{identifier}/test",
                json=request,
                headers=test_headers,
            )
            assert (
                duplicate.status_code == 202
                and duplicate.json()["data"]["job_id"] == accepted_data["job_id"]
            )
            assert (await other.get("/api/v1/jobs/" + accepted_data["job_id"])).status_code == 404
            conflict = await owner.post(
                f"/api/v1/provider-credentials/{identifier}/test",
                json={**request, "capability": "vision"},
                headers=test_headers,
            )
            assert (
                conflict.status_code == 409
                and conflict.json()["error"]["code"] == "IDEMPOTENCY_CONFLICT"
            )
            assert (
                await other.get(
                    f"/api/v1/provider-credentials/{identifier}/tests/{accepted_data['run_id']}"
                )
            ).status_code == 404

            await execute_job(runtime, UUID(accepted_data["job_id"]), "test-worker")
            await execute_job(runtime, UUID(accepted_data["job_id"]), "test-worker")
            snapshot = await owner.get("/api/v1/jobs/" + accepted_data["job_id"])
            assert (
                snapshot.status_code == 200 and snapshot.json()["data"]["state"] == "succeeded"
            ), snapshot.text
            async with runtime.resources.database.sessions() as session:
                assert (
                    await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 1
                )
            result = await owner.get(
                f"/api/v1/provider-credentials/{identifier}/tests/{accepted_data['run_id']}"
            )
            assert result.status_code == 200 and result.json()["data"]["state"] == "succeeded", (
                result.text
            )
            async with runtime.resources.database.sessions() as session, session.begin():
                stored = await session.get(ProviderCredential, UUID(identifier))
                assert stored is not None
                auth_sessions = list(
                    await session.scalars(
                        select(AuthSession)
                        .where(AuthSession.user_id == stored.owner_user_id)
                        .with_for_update()
                    )
                )
                for auth_session in auth_sessions:
                    auth_session.reauthenticated_at = datetime.now(UTC) - timedelta(minutes=6)
            expired = await owner.patch(
                f"/api/v1/provider-credentials/{identifier}",
                json={"expected_revision": 1, "key": "synthetic-new-key"},
                headers=headers,
            )
            assert (
                expired.status_code == 403
                and expired.json()["error"]["code"] == "REAUTHENTICATION_REQUIRED"
            )
            async with runtime.resources.database.sessions() as session, session.begin():
                for auth_session in await session.scalars(select(AuthSession).with_for_update()):
                    auth_session.reauthenticated_at = datetime.now(UTC)
            revoked = await owner.request(
                "DELETE",
                f"/api/v1/provider-credentials/{identifier}",
                json={"expected_revision": credential["revision"]},
                headers=headers,
            )
            assert revoked.status_code == 200, revoked.text
            async with runtime.resources.database.sessions() as session:
                stored = await session.get(ProviderCredential, UUID(identifier))
                assert (
                    stored is not None
                    and stored.status == "revoked"
                    and stored.encrypted_key is None
                )


async def test_unknown_attempt_never_reissued_and_logout_keeps_intent(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.adapters.models import ProviderFailure
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    runtime.settings = runtime.settings.model_copy(
        update={"log_file": ROOT / "dev/.local/logs" / f"test.model-fault.{run_id}.jsonl"}
    )
    configure_logging(runtime.settings, "worker")
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    calls = 0

    async def unknown(*args: object, **kwargs: object) -> None:
        nonlocal calls
        calls += 1
        raise ProviderFailure("EXTERNAL_RESULT_UNKNOWN", unknown=True)

    monkeypatch.setattr(model_tasks, "execute_probe", unknown)
    async for owner, headers in _owner(
        runtime, maintenance, f"unknown-{run_id}@haruka.example.test"
    ):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-provider-key"},
                headers=headers,
            )
        ).json()["data"]
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={
                "expected_revision": 1,
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            },
            headers={**headers, "Idempotency-Key": "unknown-" + run_id},
        )
        assert accepted.status_code == 202, accepted.text
        identifier = UUID(accepted.json()["data"]["job_id"])
        assert (await owner.post("/api/v1/auth/logout", headers=headers)).status_code == 204
        await execute_job(runtime, identifier, "worker-a")
        await execute_job(runtime, identifier, "worker-b")
        assert calls == 1
        async with runtime.resources.database.sessions() as session:
            attempts = list(await session.scalars(select(ExternalCallAttempt)))
            assert len(attempts) == 1 and attempts[0].status == "unknown"
            assert attempts[0].input_tokens is None and attempts[0].output_tokens is None
            assert attempts[0].aggregation_revision == 1
            usage = await model_tasks.usage_projection(session, attempts[0].owner_user_id)
            assert usage.groups[0].metrics["input_tokens"].known_sum is None
            assert usage.groups[0].unknown_count == 1


async def test_committed_provider_stage_recovers_without_second_call(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.adapters.models import ModelOutcome
    from app.contracts.errors import ErrorCode
    from app.domain.errors import AppError
    from app.models.model_tasks import JobStage
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    calls = 0

    async def provider(*args: object, **kwargs: object) -> ModelOutcome:
        nonlocal calls
        calls += 1
        return ModelOutcome({"input_tokens": 4}, "simulated-test-v1", True)

    async def unavailable(*args: object, **kwargs: object) -> None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)

    original = model_tasks.publish_recorded
    monkeypatch.setattr(model_tasks, "execute_probe", provider)
    async for owner, headers in _owner(
        runtime, maintenance, f"resume-{run_id}@haruka.example.test"
    ):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-provider-key"},
                headers=headers,
            )
        ).json()["data"]
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={
                "expected_revision": 1,
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            },
            headers={**headers, "Idempotency-Key": "resume-" + run_id},
        )
        assert accepted.status_code == 202, accepted.text
        identifier = UUID(accepted.json()["data"]["job_id"])
        monkeypatch.setattr(model_tasks, "publish_recorded", unavailable)
        with pytest.raises(AppError):
            await execute_job(runtime, identifier, "worker-a")
        async with runtime.resources.database.sessions() as session:
            stage = await session.scalar(select(JobStage).where(JobStage.job_id == identifier))
            assert stage is not None and stage.state == "committed"
        monkeypatch.setattr(model_tasks, "publish_recorded", original)
        await execute_job(runtime, identifier, "worker-b")
        assert calls == 1
        snapshot = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
        assert snapshot["state"] == "succeeded"
        async with runtime.resources.database.sessions() as session:
            attempt = await session.scalar(
                select(ExternalCallAttempt).where(ExternalCallAttempt.job_id == identifier)
            )
            assert (
                attempt is not None
                and attempt.aggregation_revision == 1
                and attempt.input_tokens == 4
            )


async def test_rotation_revocation_and_cancel_at_call_publication_boundaries(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.adapters.models import ModelOutcome
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    entered, release = asyncio.Event(), asyncio.Event()
    calls = 0

    async def paused(*args: object, **kwargs: object) -> ModelOutcome:
        nonlocal calls
        calls += 1
        entered.set()
        await release.wait()
        return ModelOutcome({"input_tokens": 3}, "simulated-test-v1", True)

    monkeypatch.setattr(model_tasks, "execute_probe", paused)
    async for owner, headers in _owner(
        runtime, maintenance, f"boundary-{run_id}@haruka.example.test"
    ):
        for during in (False, True):
            for mutation in ("rotate", "revoke", "cancel"):
                entered.clear()
                release.clear()
                credential = (
                    await owner.post(
                        "/api/v1/provider-credentials",
                        json={"provider": "openrouter", "key": "synthetic-provider-key"},
                        headers=headers,
                    )
                ).json()["data"]
                accepted = await owner.post(
                    f"/api/v1/provider-credentials/{credential['id']}/test",
                    json={
                        "expected_revision": 1,
                        "capability": "text",
                        "model_id": "google/gemini-2.5-flash",
                    },
                    headers={
                        **headers,
                        "Idempotency-Key": f"boundary-{during}-{mutation}-{run_id}",
                    },
                )
                assert accepted.status_code == 202, accepted.text
                identifier = UUID(accepted.json()["data"]["job_id"])
                task = (
                    asyncio.create_task(execute_job(runtime, identifier, "worker"))
                    if during
                    else None
                )
                if task:
                    await asyncio.wait_for(entered.wait(), 10)
                if mutation == "rotate":
                    changed = await owner.patch(
                        f"/api/v1/provider-credentials/{credential['id']}",
                        json={"expected_revision": 1, "key": "synthetic-new-key"},
                        headers=headers,
                    )
                elif mutation == "revoke":
                    changed = await owner.request(
                        "DELETE",
                        f"/api/v1/provider-credentials/{credential['id']}",
                        json={"expected_revision": 1},
                        headers=headers,
                    )
                else:
                    state = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
                    changed = await owner.post(
                        f"/api/v1/jobs/{identifier}/cancel",
                        json={"expected_revision": state["revision"]},
                        headers=headers,
                    )
                assert changed.status_code == 200, changed.text
                if task:
                    release.set()
                    await task
                else:
                    await execute_job(runtime, identifier, "worker")
                state = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
                assert state["state"] == ("cancelled" if mutation == "cancel" else "blocked"), state
                async with runtime.resources.database.sessions() as session:
                    count = await session.scalar(
                        select(func.count())
                        .select_from(ExternalCallAttempt)
                        .where(ExternalCallAttempt.job_id == identifier)
                    )
                    assert count == (1 if during else 0)
        assert calls == 3


async def test_zero_limits_override_and_concurrent_acceptance_are_transactional(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    from app.models.model_tasks import ModelLimitPolicy, UserRuntimeLimit

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for owner, headers in _owner(
        runtime, maintenance, f"limits-{run_id}@haruka.example.test"
    ):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-provider-key"},
                headers=headers,
            )
        ).json()["data"]

        async def accept(
            suffix: str,
            bound_owner: BoundAsyncClient = owner,
            bound_headers: dict[str, str] = headers,
            credential_id: str = credential["id"],
        ):
            return await bound_owner.post(
                f"/api/v1/provider-credentials/{credential_id}/test",
                json={
                    "expected_revision": 1,
                    "capability": "text",
                    "model_id": "google/gemini-2.5-flash",
                },
                headers={**bound_headers, "Idempotency-Key": suffix + run_id},
            )

        first, second = await asyncio.gather(accept("concurrent-a-"), accept("concurrent-b-"))
        assert sorted([first.status_code, second.status_code]) == [202, 429], (
            first.text,
            second.text,
        )
        winner = first if first.status_code == 202 else second
        identifier = winner.json()["data"]["job_id"]
        assert (
            await owner.post(
                f"/api/v1/jobs/{identifier}/cancel", json={"expected_revision": 1}, headers=headers
            )
        ).status_code == 200
        async with runtime.resources.database.sessions() as session, session.begin():
            policy = await session.scalar(
                select(ModelLimitPolicy)
                .where(
                    ModelLimitPolicy.subject_kind == "instance",
                    ModelLimitPolicy.limit_code == "instance_concurrent_jobs",
                )
                .with_for_update()
            )
            assert policy is not None
            policy.value_limit = 0
        assert (await accept("instance-zero-")).status_code == 429
        async with runtime.resources.database.sessions() as session, session.begin():
            policy = await session.scalar(
                select(ModelLimitPolicy)
                .where(
                    ModelLimitPolicy.subject_kind == "instance",
                    ModelLimitPolicy.limit_code == "instance_concurrent_jobs",
                )
                .with_for_update()
            )
            assert policy is not None
            policy.value_limit = 4
            stored = await session.get(ProviderCredential, UUID(credential["id"]))
            assert stored is not None
            session.add(
                UserRuntimeLimit(
                    owner_user_id=stored.owner_user_id,
                    revision=1,
                    limit_code="max_concurrent_jobs",
                    value_limit=0,
                )
            )
        assert (await accept("user-zero-")).status_code == 429
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0


async def test_expired_lease_takeover_fences_late_provider_result(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.adapters.models import ModelOutcome
    from app.models.model_tasks import Job
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    entered, release = asyncio.Event(), asyncio.Event()
    calls = 0

    async def paused(*args: object, **kwargs: object) -> ModelOutcome:
        nonlocal calls
        calls += 1
        entered.set()
        await release.wait()
        return ModelOutcome({"input_tokens": 3}, "simulated-test-v1", True)

    monkeypatch.setattr(model_tasks, "execute_probe", paused)
    async for owner, headers in _owner(runtime, maintenance, f"fence-{run_id}@haruka.example.test"):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-provider-key"},
                headers=headers,
            )
        ).json()["data"]
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={
                "expected_revision": 1,
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            },
            headers={**headers, "Idempotency-Key": "fence-" + run_id},
        )
        assert accepted.status_code == 202, accepted.text
        identifier = UUID(accepted.json()["data"]["job_id"])
        task = asyncio.create_task(execute_job(runtime, identifier, "worker-old"))
        await asyncio.wait_for(entered.wait(), 10)
        async with runtime.resources.database.sessions() as session, session.begin():
            job = await session.get(Job, identifier, with_for_update=True)
            assert job is not None and job.fence == 1
            job.lease_expires_at = datetime.now(UTC) - timedelta(seconds=1)
        await execute_job(runtime, identifier, "worker-new")
        release.set()
        await task
        assert calls == 1
        state = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
        assert state["state"] == "blocked" and state["error_code"] == "EXTERNAL_RESULT_UNKNOWN", (
            state
        )
        async with runtime.resources.database.sessions() as session:
            job = await session.get(Job, identifier)
            assert job is not None and job.fence == 2


async def test_outbox_publish_mark_gap_and_consumer_commit_ack_gap_replay_once(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import json

    from app.adapters.models import ModelOutcome
    from app.adapters.queue import KafkaConsumer, KafkaProducer
    from app.bootstrap import Resources
    from app.core.settings import load_settings
    from app.models import OutboxEvent
    from app.models.model_tasks import InboxEvent
    from app.services import model_tasks
    from app.services.model_worker import run_worker
    from app.services.outbox_delivery import deliver_model_event

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    template = load_settings(ROOT / "dev/.local/test.env")
    configuration = template.infrastructure().model_copy(
        update={"namespace": runtime.settings.instance_id}
    )
    topic = runtime.settings.instance_id + ".jobs"
    assert topic == "haruka-test-" + run_id + ".jobs"
    admin = cast(
        _KafkaAdmin, AdminClient({"bootstrap.servers": configuration.kafka_bootstrap_servers})
    )
    await asyncio.to_thread(
        lambda: admin.create_topics([NewTopic(topic, num_partitions=1, replication_factor=1)])[
            topic
        ].result(15)
    )
    producer = KafkaProducer(configuration)
    group = runtime.settings.instance_id + ".fault-consumer"
    consumer = KafkaConsumer(configuration, group=group)
    original_resources = runtime.resources
    runtime.resources = Resources(
        original_resources.database, original_resources.cache, producer, None, consumer
    )
    calls = 0

    async def probe(*args: object, **kwargs: object) -> ModelOutcome:
        nonlocal calls
        calls += 1
        return ModelOutcome({"input_tokens": 3}, "simulated-test-v1", True)

    monkeypatch.setattr(model_tasks, "execute_probe", probe)
    try:
        async with runtime.resources.database.sessions() as session, session.begin():
            policy = await session.get(AuthPolicy, "registration", with_for_update=True)
            assert policy is not None
            policy.registration_mode = "open"
        async for owner, headers in _owner(
            runtime, maintenance, f"queue-{run_id}@haruka.example.test"
        ):
            credential = (
                await owner.post(
                    "/api/v1/provider-credentials",
                    json={"provider": "openrouter", "key": "synthetic-provider-key"},
                    headers=headers,
                )
            ).json()["data"]
            accepted = await owner.post(
                f"/api/v1/provider-credentials/{credential['id']}/test",
                json={
                    "expected_revision": 1,
                    "capability": "text",
                    "model_id": "google/gemini-2.5-flash",
                },
                headers={**headers, "Idempotency-Key": "queue-fault-" + run_id},
            )
            assert accepted.status_code == 202, accepted.text
            identifier = UUID(accepted.json()["data"]["job_id"])
            broken_producer = KafkaProducer(
                configuration.model_copy(update={"kafka_bootstrap_servers": "127.0.0.1:1"})
            )
            runtime.resources = Resources(
                original_resources.database,
                original_resources.cache,
                broken_producer,
                None,
                consumer,
            )
            try:
                with pytest.raises(RuntimeError):
                    await deliver_model_event(runtime)
                async with runtime.resources.database.sessions() as session, session.begin():
                    event = await session.scalar(
                        select(OutboxEvent)
                        .where(OutboxEvent.event_type == "model.job.accepted")
                        .with_for_update()
                    )
                    assert (
                        event is not None
                        and event.status == "pending"
                        and event.delivery_fence == 1
                    )
                    event.delivery_lease_until = datetime.now(UTC) - timedelta(seconds=1)
            finally:
                with suppress(RuntimeError):
                    await broken_producer.aclose()
                runtime.resources = Resources(
                    original_resources.database, original_resources.cache, producer, None, consumer
                )
            original_publish = producer.publish

            async def publish_then_lose_mark(
                topic_name: str,
                *,
                key: bytes,
                value: bytes,
                publish: Callable[..., Awaitable[None]] = original_publish,
            ) -> None:
                await publish(topic_name, key=key, value=value)
                raise RuntimeError("synthetic gap after acknowledged publication")

            monkeypatch.setattr(producer, "publish", publish_then_lose_mark)
            with pytest.raises(RuntimeError, match="synthetic gap"):
                await deliver_model_event(runtime)
            async with runtime.resources.database.sessions() as session, session.begin():
                event = await session.scalar(
                    select(OutboxEvent)
                    .where(OutboxEvent.event_type == "model.job.accepted")
                    .with_for_update()
                )
                assert event is not None and event.status == "pending" and event.delivery_fence == 2
                event_id = event.id
                event.delivery_lease_until = datetime.now(UTC) - timedelta(seconds=1)
            monkeypatch.setattr(producer, "publish", original_publish)
            assert await deliver_model_event(runtime)
            async with runtime.resources.database.sessions() as session:
                event = await session.get(OutboxEvent, event_id)
                assert (
                    event is not None and event.status == "published" and event.delivery_fence == 3
                )

            async def lose_ack(*args: object, **kwargs: object) -> None:
                raise RuntimeError("synthetic gap after business inbox commit")

            monkeypatch.setattr(consumer, "acknowledge", lose_ack)
            async with asyncio.timeout(30):
                while True:
                    try:
                        await run_worker(runtime, asyncio.Event(), once=True)
                    except RuntimeError as error:
                        assert "synthetic gap" in str(error)
                        break
            async with runtime.resources.database.sessions() as session:
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(InboxEvent)
                        .where(InboxEvent.event_id == event_id)
                    )
                    == 1
                )
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(ExternalCallAttempt)
                        .where(ExternalCallAttempt.job_id == identifier)
                    )
                    == 1
                )
            await consumer.aclose()
            consumer = KafkaConsumer(configuration, group=group)
            runtime.resources = Resources(
                original_resources.database, original_resources.cache, producer, None, consumer
            )
            await consumer.subscribe(topic)
            async with asyncio.timeout(30):
                while True:
                    record = await consumer.read()
                    if record is not None:
                        assert record.value is not None and json.loads(record.value)[
                            "event_id"
                        ] == str(event_id)
                        break
            # First delivery was intentionally not ACKed. Its committed Inbox
            # rejects business repetition when the same broker event is replayed.
            await model_tasks.execute_job(
                runtime,
                identifier,
                "replay-worker",
                inbox=(event_id, __import__("hashlib").sha256(record.value).digest()),
            )
            await consumer.acknowledge(record)
            assert calls == 1
            snapshot = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
            assert snapshot["state"] == "succeeded"
            from app.models.model_tasks import Job

            entered, release = asyncio.Event(), asyncio.Event()

            async def cancelled_probe(
                *args: object,
                entered: asyncio.Event = entered,
                release: asyncio.Event = release,
                **kwargs: object,
            ) -> ModelOutcome:
                nonlocal calls
                calls += 1
                entered.set()
                await release.wait()
                return ModelOutcome({"input_tokens": 3}, "simulated-test-v1", True)

            monkeypatch.setattr(model_tasks, "execute_probe", cancelled_probe)
            interrupted = await owner.post(
                f"/api/v1/provider-credentials/{credential['id']}/test",
                json={
                    "expected_revision": 1,
                    "capability": "text",
                    "model_id": "google/gemini-2.5-flash",
                },
                headers={**headers, "Idempotency-Key": "cancel-recovery-" + run_id},
            )
            assert interrupted.status_code == 202
            cancelled_id = UUID(interrupted.json()["data"]["job_id"])
            old_task = asyncio.create_task(execute_job(runtime, cancelled_id, "interrupted-worker"))
            try:
                await asyncio.wait_for(entered.wait(), 10)
                current = (await owner.get(f"/api/v1/jobs/{cancelled_id}")).json()["data"]
                assert (
                    await owner.post(
                        f"/api/v1/jobs/{cancelled_id}/cancel",
                        json={"expected_revision": current["revision"]},
                        headers=headers,
                    )
                ).status_code == 200
                async with runtime.resources.database.sessions() as session, session.begin():
                    stale = await session.get(Job, cancelled_id, with_for_update=True)
                    assert stale is not None and stale.state == "cancel_requested"
                    stale.lease_expires_at = datetime.now(UTC) - timedelta(seconds=1)
                await run_worker(runtime, asyncio.Event(), once=True)
                recovered = (await owner.get(f"/api/v1/jobs/{cancelled_id}")).json()["data"]
                assert recovered["state"] == "cancelled"
                async with runtime.resources.database.sessions() as session:
                    fact = await session.scalar(
                        select(ExternalCallAttempt).where(
                            ExternalCallAttempt.job_id == cancelled_id
                        )
                    )
                    assert fact is not None and fact.status == "unknown"
                    assert fact.input_tokens is None
                fresh = await owner.post(
                    f"/api/v1/provider-credentials/{credential['id']}/test",
                    json={
                        "expected_revision": 1,
                        "capability": "text",
                        "model_id": "google/gemini-2.5-flash",
                    },
                    headers={**headers, "Idempotency-Key": "freed-slot-" + run_id},
                )
                assert fresh.status_code == 202
            finally:
                release.set()
                await old_task
            assert calls == 2
            assert (await owner.get(f"/api/v1/jobs/{cancelled_id}")).json()["data"][
                "state"
            ] == "cancelled"
    finally:
        await consumer.aclose()
        await producer.aclose()
        runtime.resources = original_resources
        assert topic == "haruka-test-" + run_id + ".jobs"
        await asyncio.to_thread(lambda: admin.delete_topics([topic])[topic].result(15))


async def test_websocket_origin_bearer_reconnect_owner_and_dependency_failure(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    import json
    import socket

    import httpx2 as httpx
    import uvicorn
    from websockets.asyncio.client import connect
    from websockets.exceptions import ConnectionClosed, InvalidStatus
    from websockets.typing import Origin

    from app.adapters.cache import Cache
    from app.bootstrap import Resources
    from app.main import create_app
    from tests.integration.test_authentication_flow import ORIGIN

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()
    listener.setblocking(False)
    address = f"ws://127.0.0.1:{listener.getsockname()[1]}/api/v1/jobs/events"
    server = uvicorn.Server(
        uvicorn.Config(
            app, log_config=None, access_log=False, lifespan="off", ws="websockets-sansio"
        )
    )
    serving = asyncio.create_task(server.serve(sockets=[listener]))
    try:
        async with asyncio.timeout(10):
            # Uvicorn exposes a started flag rather than a ready Event.
            while not server.started:  # noqa: ASYNC110
                await asyncio.sleep(0.01)
        async for owner, headers in _owner(
            runtime, maintenance, f"ws-a-{run_id}@haruka.example.test"
        ):
            async for other, _headers in _owner(
                runtime, maintenance, f"ws-b-{run_id}@haruka.example.test"
            ):
                credential = (
                    await owner.post(
                        "/api/v1/provider-credentials",
                        json={"provider": "openrouter", "key": "synthetic-provider-key"},
                        headers=headers,
                    )
                ).json()["data"]
                accepted = await owner.post(
                    f"/api/v1/provider-credentials/{credential['id']}/test",
                    json={
                        "expected_revision": 1,
                        "capability": "text",
                        "model_id": "google/gemini-2.5-flash",
                    },
                    headers={**headers, "Idempotency-Key": "ws-" + run_id},
                )
                assert accepted.status_code == 202, accepted.text
                identifier = accepted.json()["data"]["job_id"]
                cookie = "haruka_client_session=" + owner.cookies["haruka_client_session"]
                with pytest.raises(InvalidStatus):
                    async with connect(
                        address,
                        origin=Origin("https://untrusted.example.test"),
                        additional_headers={"Cookie": cookie},
                    ):
                        pytest.fail("untrusted Origin accepted")
                async with connect(
                    address, origin=Origin(ORIGIN), additional_headers={"Cookie": cookie}
                ) as invalid_stream:
                    await invalid_stream.send(
                        json.dumps(
                            {"schema_version": 2, "type": "subscribe", "job_ids": [identifier]}
                        )
                    )
                    with pytest.raises(ConnectionClosed) as invalid_closed:
                        await invalid_stream.recv()
                    assert (
                        invalid_closed.value.rcvd is not None
                        and invalid_closed.value.rcvd.code == 1008
                    )
                async with connect(
                    address, origin=Origin(ORIGIN), additional_headers={"Cookie": cookie}
                ) as stream:
                    await stream.send(
                        json.dumps(
                            {
                                "schema_version": 1,
                                "type": "subscribe",
                                "job_ids": [identifier],
                                "cursors": {},
                            }
                        )
                    )
                    first = json.loads(await asyncio.wait_for(stream.recv(), 10))
                    assert first["type"] == "snapshot" and first["job_id"] == identifier
                async with connect(
                    address, origin=Origin(ORIGIN), additional_headers={"Cookie": cookie}
                ) as stream:
                    await stream.send(
                        json.dumps(
                            {
                                "schema_version": 1,
                                "type": "subscribe",
                                "job_ids": [identifier],
                                "cursors": {identifier: {"generation": 1, "sequence": 0}},
                            }
                        )
                    )
                    second = json.loads(await asyncio.wait_for(stream.recv(), 10))
                    assert second["payload"] == first["payload"]
                foreign_cookie = "haruka_client_session=" + other.cookies["haruka_client_session"]
                async with connect(
                    address, origin=Origin(ORIGIN), additional_headers={"Cookie": foreign_cookie}
                ) as stream:
                    await stream.send(
                        json.dumps(
                            {"schema_version": 1, "type": "subscribe", "job_ids": [identifier]}
                        )
                    )
                    with pytest.raises(ConnectionClosed) as closed:
                        await stream.recv()
                    assert closed.value.rcvd is not None and closed.value.rcvd.code == 1008
                async with httpx.AsyncClient(
                    transport=httpx.ASGITransport(app=app), base_url=ORIGIN
                ) as native:
                    login = await native.post(
                        "/api/v1/auth/native/login",
                        json={
                            "email": f"ws-a-{run_id}@haruka.example.test",
                            "password": "synthetic-profile-password-2026",
                            "platform": "android",
                        },
                    )
                    assert login.status_code == 200
                    token = login.json()["data"]["access_token"]
                    async with connect(
                        address, additional_headers={"Authorization": "Bearer " + token}
                    ) as stream:
                        await stream.send(
                            json.dumps(
                                {"schema_version": 1, "type": "subscribe", "job_ids": [identifier]}
                            )
                        )
                        assert (
                            json.loads(await asyncio.wait_for(stream.recv(), 10))["job_id"]
                            == identifier
                        )
                async with connect(
                    address, origin=Origin(ORIGIN), additional_headers={"Cookie": cookie}
                ) as stream:
                    await stream.send(
                        json.dumps(
                            {"schema_version": 1, "type": "subscribe", "job_ids": [identifier]}
                        )
                    )
                    await asyncio.wait_for(stream.recv(), 10)
                    original = runtime.resources
                    broken = Cache(
                        runtime.settings.core_infrastructure().model_copy(
                            update={"redis_url": SecretStr("redis://127.0.0.1:1/1")}
                        )
                    )
                    runtime.resources = Resources(original.database, broken, None, None, None)
                    try:
                        with pytest.raises(ConnectionClosed) as closed:
                            await asyncio.wait_for(stream.recv(), 10)
                        assert closed.value.rcvd is not None and closed.value.rcvd.code == 1013
                    finally:
                        runtime.resources = original
                        await broken.aclose()
    finally:
        server.should_exit = True
        try:
            await serving
        finally:
            listener.close()


async def test_permission_revocation_at_call_and_publication_boundaries(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from sqlalchemy import delete

    from app.adapters.models import ModelOutcome
    from app.models import AuthorizationRevision, User, UserRole
    from app.models.model_tasks import Job
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    calls = 0
    entered, release = asyncio.Event(), asyncio.Event()

    async def paused(*args: object, **kwargs: object) -> ModelOutcome:
        nonlocal calls
        calls += 1
        entered.set()
        await release.wait()
        return ModelOutcome({"input_tokens": 3}, "simulated-test-v1", True)

    monkeypatch.setattr(model_tasks, "execute_probe", paused)
    for during in (False, True):
        entered.clear()
        release.clear()
        async for owner, headers in _owner(
            runtime, maintenance, f"permission-{during}-{run_id}@haruka.example.test"
        ):
            credential = (
                await owner.post(
                    "/api/v1/provider-credentials",
                    json={"provider": "openrouter", "key": "synthetic-provider-key"},
                    headers=headers,
                )
            ).json()["data"]
            accepted = await owner.post(
                f"/api/v1/provider-credentials/{credential['id']}/test",
                json={
                    "expected_revision": 1,
                    "capability": "text",
                    "model_id": "google/gemini-2.5-flash",
                },
                headers={**headers, "Idempotency-Key": f"permission-{during}-{run_id}"},
            )
            assert accepted.status_code == 202, accepted.text
            identifier = UUID(accepted.json()["data"]["job_id"])
            task = (
                asyncio.create_task(execute_job(runtime, identifier, "worker")) if during else None
            )
            if task:
                await asyncio.wait_for(entered.wait(), 10)
            async with runtime.resources.database.sessions() as session, session.begin():
                revision = await session.get(AuthorizationRevision, "global", with_for_update=True)
                stored = await session.get(ProviderCredential, UUID(credential["id"]))
                assert stored is not None and revision is not None
                user = await session.get(User, stored.owner_user_id, with_for_update=True)
                assert user is not None
                await session.execute(delete(UserRole).where(UserRole.user_id == user.id))
                user.authz_version += 1
                revision.revision += 1
            if task:
                release.set()
                await task
            else:
                await execute_job(runtime, identifier, "worker")
            async with runtime.resources.database.sessions() as session:
                job = await session.get(Job, identifier)
                assert (
                    job is not None
                    and job.state == "blocked"
                    and job.error_code == "PERMISSION_DENIED"
                )
                assert await session.scalar(
                    select(func.count())
                    .select_from(ExternalCallAttempt)
                    .where(ExternalCallAttempt.job_id == identifier)
                ) == (1 if during else 0)
    assert calls == 1


async def test_invalid_output_reported_usage_provider_limit_and_explicit_retry(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.adapters.models import ModelOutcome, ProviderFailure
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    runtime.settings = runtime.settings.model_copy(
        update={"log_file": ROOT / "dev/.local/logs" / f"test.model-fault.{run_id}.jsonl"}
    )
    configure_logging(runtime.settings, "worker")
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    calls = 0

    async def failed(*args: object, **kwargs: object) -> None:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise ProviderFailure(
                "OUTPUT_INVALID",
                facts=ModelOutcome({"input_tokens": 7}, "simulated-failure-usage-v1", True),
            )
        raise ProviderFailure("PROVIDER_RATE_LIMIT")

    monkeypatch.setattr(model_tasks, "execute_probe", failed)
    async for owner, headers in _owner(
        runtime, maintenance, f"invalid-{run_id}@haruka.example.test"
    ):
        missing = await owner.post(
            "/api/v1/provider-credentials", json={"provider": "openrouter"}, headers=headers
        )
        assert missing.status_code == 422
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-provider-key"},
                headers=headers,
            )
        ).json()["data"]
        payload = {
            "expected_revision": 1,
            "capability": "text",
            "model_id": "google/gemini-2.5-flash",
        }
        test_headers = {**headers, "Idempotency-Key": "invalid-" + run_id}
        self_reported = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={**payload, "fake": True},
            headers=test_headers,
        )
        assert self_reported.status_code == 422
        unsupported = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={**payload, "model_id": "unregistered/example"},
            headers=test_headers,
        )
        assert unsupported.json()["error"]["code"] == "CAPABILITY_UNSUPPORTED"
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json=payload,
            headers=test_headers,
        )
        assert accepted.status_code == 202, accepted.text
        identifier = UUID(accepted.json()["data"]["job_id"])
        await execute_job(runtime, identifier, "worker")
        state = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
        assert (
            state["state"] == "failed"
            and state["error_code"] == "OUTPUT_INVALID"
            and state["requires_new_attempt_confirmation"]
        )
        rejected = await owner.post(
            f"/api/v1/jobs/{identifier}/retry",
            json={"expected_revision": state["revision"], "confirm_new_attempt": False},
            headers=headers,
        )
        assert rejected.status_code == 409
        restarted = await owner.post(
            f"/api/v1/jobs/{identifier}/retry",
            json={"expected_revision": state["revision"], "confirm_new_attempt": True},
            headers=headers,
        )
        assert restarted.status_code == 200 and restarted.json()["data"]["generation"] == 2, (
            restarted.text
        )
        await execute_job(runtime, identifier, "worker")
        state = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
        assert state["state"] == "failed" and state["error_code"] == "PROVIDER_RATE_LIMIT"
        assert calls == 2
        usage = (await owner.get("/api/v1/users/me/model-usage")).json()["data"]["groups"][0]
        assert usage["attempt_count"] == 2 and usage["failed_count"] == 2
        assert usage["metrics"]["input_tokens"] == {
            "known_sum": 7,
            "known_attempt_count": 1,
            "unknown_attempt_count": 1,
            "completeness": "partial",
        }
        assert usage["metrics"]["output_tokens"]["known_sum"] is None


@pytest.mark.parametrize("mutation", ["disabled", "revision", "missing_frozen_revision"])
@pytest.mark.parametrize("during", [False, True])
async def test_catalog_mutation_at_call_and_publication_boundaries(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    mutation: str,
    during: bool,
) -> None:
    from app.adapters.models import ModelOutcome
    from app.models.model_tasks import AiRun, ModelCatalogEntry
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    entered, release = asyncio.Event(), asyncio.Event()
    calls = 0

    async def paused(*args: object, **kwargs: object) -> ModelOutcome:
        nonlocal calls
        calls += 1
        entered.set()
        await release.wait()
        return ModelOutcome({"input_tokens": 3}, "simulated-test-v1", True)

    monkeypatch.setattr(model_tasks, "execute_probe", paused)
    async for owner, headers in _owner(
        runtime, maintenance, f"catalog-{run_id}@haruka.example.test"
    ):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={
                    "provider": "openrouter",
                    "key": "synthetic-provider-key",
                },
                headers=headers,
            )
        ).json()["data"]
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={
                "expected_revision": 1,
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            },
            headers={**headers, "Idempotency-Key": "catalog-" + run_id},
        )
        assert accepted.status_code == 202
        identifier = UUID(accepted.json()["data"]["job_id"])
        async with runtime.resources.database.sessions() as session:
            run = await session.get(AiRun, UUID(accepted.json()["data"]["run_id"]))
            assert run is not None and run.generation_config["catalog_revision"] == 1
            assert run.model_revision is None
        task = asyncio.create_task(execute_job(runtime, identifier, "worker")) if during else None
        if task:
            await asyncio.wait_for(entered.wait(), 10)
        async with runtime.resources.database.sessions() as session, session.begin():
            model = await session.scalar(
                select(ModelCatalogEntry)
                .where(
                    ModelCatalogEntry.provider == "openrouter",
                    ModelCatalogEntry.model_code == "google/gemini-2.5-flash",
                )
                .with_for_update()
            )
            assert model is not None
            if mutation == "missing_frozen_revision":
                stored_run = await session.get(
                    AiRun, UUID(accepted.json()["data"]["run_id"]), with_for_update=True
                )
                assert stored_run is not None
                stored_run.generation_config = {
                    key: value
                    for key, value in stored_run.generation_config.items()
                    if key != "catalog_revision"
                }
            else:
                model.revision += 1
            if mutation == "disabled":
                model.enabled = False
        release.set()
        if task:
            await task
        else:
            await execute_job(runtime, identifier, "worker")
        state = (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"]
        assert state["state"] == "blocked"
        assert calls == (1 if during else 0)
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(
                select(func.count())
                .select_from(ExternalCallAttempt)
                .where(
                    ExternalCallAttempt.job_id == identifier,
                )
            ) == (1 if during else 0)


async def test_undeclared_provider_and_arbitrary_endpoint_reject_without_egress(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    calls = 0

    async def forbidden(*args: object, **kwargs: object) -> None:
        nonlocal calls
        calls += 1
        raise AssertionError("unexpected provider dispatch")

    monkeypatch.setattr(model_tasks, "execute_probe", forbidden)
    async for owner, headers in _owner(
        runtime, maintenance, f"egress-{run_id}@haruka.example.test"
    ):
        for payload in (
            {"provider": "undeclared", "key": "synthetic-provider-key"},
            {
                "provider": "openrouter",
                "key": "synthetic-provider-key",
                "base_url": "https://untrusted.invalid",
            },
            {
                "provider": "openrouter",
                "key": "synthetic-provider-key",
                "endpoint": "https://untrusted.invalid",
            },
        ):
            rejected = await owner.post(
                "/api/v1/provider-credentials", json=payload, headers=headers
            )
            assert rejected.status_code == 422
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={
                    "provider": "openrouter",
                    "key": "synthetic-provider-key",
                },
                headers=headers,
            )
        ).json()["data"]
        for extra in (
            {"provider": "undeclared"},
            {"endpoint": "https://untrusted.invalid"},
            {"base_url": "https://untrusted.invalid"},
        ):
            rejected = await owner.post(
                f"/api/v1/provider-credentials/{credential['id']}/test",
                json={
                    "expected_revision": 1,
                    "capability": "text",
                    "model_id": "google/gemini-2.5-flash",
                    **extra,
                },
                headers={**headers, "Idempotency-Key": "egress-" + run_id},
            )
            assert rejected.status_code == 422
        assert calls == 0
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0


async def test_usage_groups_separate_simulated_and_real_facts(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for owner, headers in _owner(
        runtime, maintenance, f"usage-split-{run_id}@haruka.example.test"
    ):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={
                    "provider": "openrouter",
                    "key": "synthetic-provider-key",
                },
                headers=headers,
            )
        ).json()["data"]
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={
                "expected_revision": 1,
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            },
            headers={**headers, "Idempotency-Key": "usage-split-" + run_id},
        )
        assert accepted.status_code == 202
        identifier = UUID(accepted.json()["data"]["job_id"])
        await execute_job(runtime, identifier, "worker")
        async with runtime.resources.database.sessions() as session, session.begin():
            attempt = await session.scalar(
                select(ExternalCallAttempt).where(ExternalCallAttempt.job_id == identifier)
            )
            assert attempt is not None and attempt.simulated
            owner_id = attempt.owner_user_id
            # Aggregation-only fixture: no actual live dispatch; the false marker is
            # synthetic persisted ledger input, never an external execution claim.
            session.add(
                ExternalCallAttempt(
                    owner_user_id=owner_id,
                    job_id=identifier,
                    ai_run_id=attempt.ai_run_id,
                    credential_id=attempt.credential_id,
                    credential_version=attempt.credential_version,
                    provider=attempt.provider,
                    model_id=attempt.model_id,
                    capability=attempt.capability,
                    operation_kind=attempt.operation_kind,
                    attempt_no=2,
                    status="failed",
                    simulated=False,
                    usage_status="unavailable",
                    usage={},
                    aggregation_revision=1,
                    started_at=datetime.now(UTC),
                    error_code="KEY_REJECTED",
                )
            )
        async with runtime.resources.database.sessions() as session:
            result = await model_tasks.usage_projection(session, owner_id)
        assert len(result.groups) == 2
        groups = {group.simulated: group for group in result.groups}
        assert groups[True].attempt_count == 1 and groups[True].succeeded_count == 1
        assert groups[False].attempt_count == 1 and groups[False].failed_count == 1
        assert groups[False].metrics["input_tokens"].known_sum is None
        assert groups[False].metrics["input_tokens"].unknown_attempt_count == 1
        assert groups[True].metrics["input_tokens"].known_attempt_count == 1
        assert result.aggregation_revision == 2
        history = await owner.get(
            f"/api/v1/provider-credentials/{credential['id']}/tests/{accepted.json()['data']['run_id']}"
        )
        assert history.status_code == 200
        assert {group["simulated"] for group in history.json()["data"]["usage"]["groups"]} == {
            True,
            False,
        }


async def test_historical_usage_and_active_credentials_survive_revoked_history(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    from app.models.model_tasks import AiRun
    from app.services import model_tasks

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    async for owner, headers in _owner(
        runtime, maintenance, f"history-{run_id}@haruka.example.test"
    ):
        credential = (
            await owner.post(
                "/api/v1/provider-credentials",
                json={"provider": "openrouter", "key": "synthetic-provider-key"},
                headers=headers,
            )
        ).json()["data"]
        accepted = await owner.post(
            f"/api/v1/provider-credentials/{credential['id']}/test",
            json={
                "expected_revision": 1,
                "capability": "text",
                "model_id": "google/gemini-2.5-flash",
            },
            headers={**headers, "Idempotency-Key": "history-" + run_id},
        )
        assert accepted.status_code == 202
        identifier = UUID(accepted.json()["data"]["job_id"])
        await execute_job(runtime, identifier, "worker")
        old = datetime.now(UTC) - timedelta(days=31)
        async with runtime.resources.database.sessions() as session, session.begin():
            stored = await session.get(
                ProviderCredential, UUID(credential["id"]), with_for_update=True
            )
            assert stored is not None
            owner_id = stored.owner_user_id
            run = await session.get(
                AiRun, UUID(accepted.json()["data"]["run_id"]), with_for_update=True
            )
            assert run is not None
            run.created_at = old
            attempt = await session.scalar(
                select(ExternalCallAttempt).where(ExternalCallAttempt.job_id == identifier)
            )
            assert attempt is not None
            attempt.started_at = old
            session.add(
                ExternalCallAttempt(
                    owner_user_id=owner_id,
                    job_id=identifier,
                    ai_run_id=run.id,
                    credential_id=stored.id,
                    credential_version=1,
                    provider="openrouter",
                    model_id=run.model_id,
                    capability="text",
                    operation_kind="credential_test",
                    attempt_no=2,
                    status="failed",
                    simulated=False,
                    usage_status="unavailable",
                    usage={},
                    aggregation_revision=1,
                    started_at=old,
                )
            )
            for index in range(101):
                session.add(
                    ProviderCredential(
                        owner_user_id=owner_id,
                        provider="openrouter",
                        label=f"Revoked {index}",
                        encrypted_key=None,
                        encryption_key_version="v1",
                        masked_key="****",
                        credential_version=2,
                        revision=2,
                        status="revoked",
                        revoked_at=old,
                        created_at=old,
                        updated_at=old,
                    )
                )
        history = await owner.get(f"/api/v1/provider-credentials/{credential['id']}/tests/{run.id}")
        assert history.status_code == 200
        groups = history.json()["data"]["usage"]["groups"]
        assert len(groups) == 2 and {g["simulated"] for g in groups} == {True, False}
        assert (
            next(g for g in groups if not g["simulated"])["metrics"]["input_tokens"]["known_sum"]
            is None
        )
        async with runtime.resources.database.sessions() as session:
            assert (await model_tasks.usage_projection(session, owner_id)).groups == []
        listing = (await owner.get("/api/v1/provider-credentials")).json()["data"]["items"]
        assert any(row["id"] == credential["id"] and row["status"] == "active" for row in listing)

        # Revocation removes the current secret, not already persisted test facts.
        revoked = await owner.request(
            "DELETE",
            f"/api/v1/provider-credentials/{credential['id']}",
            json={"expected_revision": 1},
            headers=headers,
        )
        assert revoked.status_code == 200
        retained = await owner.get(
            f"/api/v1/provider-credentials/{credential['id']}/tests/{run.id}"
        )
        assert retained.status_code == 200 and len(retained.json()["data"]["usage"]["groups"]) == 2


async def test_admin_catalog_projection_and_safe_retry_request_contract(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import httpx2 as httpx

    from app.main import create_app
    from app.models.model_tasks import Job
    from app.schemas.model_settings import AdminJobRead, ModelCapabilities
    from app.services import model_tasks
    from tests.integration.test_authentication_flow import ORIGIN

    runtime, maintenance, run_id = identity_runtime
    runtime.settings = runtime.settings.model_copy(
        update={
            "model_execution_mode": "fake",
            "credential_keyring": {"v1": SecretStr(Fernet.generate_key().decode())},
        }
    )
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as admin:
        headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
        login = await admin.post(
            "/api/v1/admin/auth/login",
            json={
                "email": f"admin-{run_id}@haruka.example.test",
                "password": "synthetic-admin-password-2026",
            },
            headers=headers,
        )
        assert login.status_code == 200
        csrf = (await admin.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
        headers = {**headers, "X-CSRF-Token": csrf}
        directory = ModelCapabilities.model_validate(
            (await admin.get("/api/v1/admin/model-catalog")).json()["data"]
        )
        model = next(
            row
            for row in directory.models
            if row.provider == "openrouter" and row.model_id == "google/gemini-2.5-flash"
        )
        patched = await admin.patch(
            f"/api/v1/admin/model-catalog/{model.id}",
            json={"expected_revision": model.revision, "enabled": False},
            headers=headers,
        )
        assert patched.status_code == 200
        projection = ModelCapabilities.model_validate(patched.json()["data"])
        changed = next(row for row in projection.models if row.id == model.id)
        assert not changed.enabled and changed.revision == model.revision + 1
        assert (
            await admin.patch(
                f"/api/v1/admin/model-catalog/{model.id}",
                json={"expected_revision": changed.revision, "enabled": True},
                headers=headers,
            )
        ).status_code == 200
        async for owner, owner_headers in _owner(
            runtime, maintenance, f"admin-actions-{run_id}@haruka.example.test"
        ):
            credential = (
                await owner.post(
                    "/api/v1/provider-credentials",
                    json={"provider": "openrouter", "key": "synthetic-provider-key"},
                    headers=owner_headers,
                )
            ).json()["data"]
            accepted = await owner.post(
                f"/api/v1/provider-credentials/{credential['id']}/test",
                json={
                    "expected_revision": 1,
                    "capability": "text",
                    "model_id": "google/gemini-2.5-flash",
                },
                headers={**owner_headers, "Idempotency-Key": "admin-actions-" + run_id},
            )
            assert accepted.status_code == 202
            identifier = UUID(accepted.json()["data"]["job_id"])
            original = model_tasks.publish_recorded

            async def lose_publish(*args: object, **kwargs: object) -> None:
                raise RuntimeError("synthetic publish interruption")

            monkeypatch.setattr(model_tasks, "publish_recorded", lose_publish)
            with pytest.raises(RuntimeError, match="synthetic publish interruption"):
                await execute_job(runtime, identifier, "worker")
            monkeypatch.setattr(model_tasks, "publish_recorded", original)
            async with runtime.resources.database.sessions() as session, session.begin():
                job = await session.get(Job, identifier, with_for_update=True)
                assert job is not None
                job.state = "blocked"
                revision = job.revision
            invalid = await admin.post(
                f"/api/v1/admin/jobs/{identifier}/retry",
                json={"expected_revision": revision, "confirm_new_attempt": False},
                headers=headers,
            )
            assert invalid.status_code == 422
            restored = await admin.post(
                f"/api/v1/admin/jobs/{identifier}/retry",
                json={"expected_revision": revision},
                headers=headers,
            )
            assert restored.status_code == 200
            assert AdminJobRead.model_validate(restored.json()["data"]).state == "queued"
            await execute_job(runtime, identifier, "recovery-worker")
            assert (await owner.get(f"/api/v1/jobs/{identifier}")).json()["data"][
                "state"
            ] == "succeeded"
            async with runtime.resources.database.sessions() as session:
                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(ExternalCallAttempt)
                        .where(ExternalCallAttempt.job_id == identifier)
                    )
                    == 1
                )
