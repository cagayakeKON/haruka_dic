"""Actual committed source actions and atomic private notification receipts."""

import asyncio
import hashlib
import json
import logging
from collections.abc import Generator, Mapping
from contextlib import contextmanager
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from sqlalchemy import event as sql_event
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.bootstrap import Runtime
from app.core.logging import SafeJsonFormatter
from app.domain.correlation import current_log_context
from app.domain.errors import AppError
from app.maintenance.settings import MaintenanceSettings
from app.models import (
    AiRun,
    AuthSession,
    ExternalCallAttempt,
    Job,
    Library,
    MaterialRevision,
    OutboxEvent,
    UploadIntent,
    User,
)
from app.models.learning_reference import Material
from app.models.material_imports import MaterialSourceAsset
from app.models.model_tasks import InboxEvent
from app.models.user_notifications import UserNotification
from app.services import notification_events
from app.services.material_jobs import execute_source_job
from app.services.notification_delivery import recover_notifications
from app.services.notification_events import CONSUMER_NAME, canonical_envelope, consume_event
from tests.integration.test_material_source_boundaries import accepted_source, source_runtime
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)
assert source_runtime


class SafeLogCapture(logging.Handler):
    def __init__(self, runtime: Runtime) -> None:
        super().__init__()
        self.setFormatter(SafeJsonFormatter(runtime.settings, "worker"))
        self.rows: list[dict[str, object]] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.rows.append(json.loads(self.format(record)))


@contextmanager
def capture_logs(runtime: Runtime) -> Generator[SafeLogCapture]:
    handler = SafeLogCapture(runtime)
    logger = notification_events.logger
    old_level = logger.level
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    try:
        yield handler
    finally:
        logger.removeHandler(handler)
        logger.setLevel(old_level)
        handler.close()


def assert_safe_log_correlation(row: dict[str, object], expected: Mapping[str, object]) -> None:
    for field, value in expected.items():
        assert row.get(field) == (str(value) if isinstance(value, UUID) else value)
    assert not {
        "payload",
        "secret",
        "token",
        "title",
        "email",
        "body",
        "sql_parameters",
    }.intersection(row)
    assert "controlled notification commit failure" not in json.dumps(row)


async def source_event(runtime: Runtime, job_id: UUID, kind: str = "completed") -> OutboxEvent:
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session:
        row = await session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.event_type == "material.import." + kind,
                OutboxEvent.payload["job_id"].astext == str(job_id),
            )
        )
        assert row is not None
        return row


async def test_concurrent_canonical_old_ack_and_disabled_logout_receipt(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(
        runtime, maintenance, f"notification-{run_id}@haruka.example.test"
    ):
        material_id, job_id = await accepted_source(
            runtime, web, headers, "これは日本語の小説です。今日はとてもいい天気です。".encode()
        )
        await execute_source_job(runtime, job_id, "notification-source")
        row = await source_event(runtime, job_id)
        wire = canonical_envelope(row)
        # Historical model-worker ACK is a fixture, not a notification result.
        async with runtime.resources.database.sessions() as session, session.begin():
            job = await session.get(Job, job_id)
            assert job is not None
            user = await session.get(User, job.owner_user_id, with_for_update=True)
            old_session = await session.get(AuthSession, job.session_id, with_for_update=True)
            assert user is not None and old_session is not None
            user.status, user.updated_at = "disabled", datetime.now(UTC)
            old_session.revoked_at = old_session.updated_at = datetime.now(UTC)
            session.add(
                InboxEvent(
                    consumer_name="model-worker",
                    event_id=row.id,
                    payload_digest=hashlib.sha256(json.dumps(wire).encode()).digest(),
                    processed_at=datetime.now(UTC),
                )
            )
            expected_context = {
                "request_id": job.request_id,
                "operation_id": job.operation_id,
                "job_id": job.id,
                "user_id": user.id,
                "ai_run_id": None,
                "audience": "client",
            }
        before = current_log_context()
        changed_order: dict[str, object] = json.loads(json.dumps(wire, sort_keys=True, indent=2))
        with capture_logs(runtime) as capture:
            results = await asyncio.gather(
                consume_event(runtime, row.id, changed_order), consume_event(runtime, row.id)
            )
        assert sorted(results) == [False, True]
        assert len(capture.rows) == 1 and capture.rows[0]["event"] == "notification.created"
        assert_safe_log_correlation(capture.rows[0], expected_context)
        assert current_log_context() == before
        # A fresh subsequent record serializes only its own current context.
        next_record = logging.LogRecord(
            __name__, logging.INFO, __file__, 1, "notification.created", (), None
        )
        for field, value in current_log_context().items():
            setattr(next_record, field, value)
        next_safe: dict[str, object] = json.loads(capture.format(next_record))
        assert_safe_log_correlation(next_safe, before)
        assert not await consume_event(runtime, row.id, wire)
        assert await recover_notifications(runtime) == 0
        async with runtime.resources.database.sessions() as session:
            receipt = await session.scalar(select(UserNotification))
            assert receipt is not None and receipt.resource_id == material_id
            assert receipt.resource_version == 1 and receipt.safe_parameters == {}
            library = await session.get(Library, receipt.library_id)
            assert library is not None and library.notification_sequence == 1
            assert await session.scalar(select(func.count()).select_from(UserNotification)) == 1
            assert await session.scalar(select(func.count()).select_from(InboxEvent)) == 2
            inbox = await session.scalar(
                select(InboxEvent).where(InboxEvent.consumer_name == CONSUMER_NAME)
            )
            assert (
                inbox is not None
                and inbox.payload_digest
                == hashlib.sha256(notification_events.envelope_bytes(wire)).digest()
            )
            assert await session.scalar(select(func.count()).select_from(AiRun)) == 0
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0


async def test_notification_commit_failure_rolls_back_counter_and_inbox(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(runtime, maintenance, f"atomic-{run_id}@haruka.example.test"):
        _, job_id = await accepted_source(
            runtime, web, headers, "これは日本語の小説です。".encode()
        )
        await execute_source_job(runtime, job_id, "atomic-notification-source")
        row = await source_event(runtime, job_id)
        async with runtime.resources.database.sessions() as session:
            source_job = await session.get(Job, job_id)
            assert source_job is not None
            expected = {
                "request_id": source_job.request_id,
                "operation_id": source_job.operation_id,
                "job_id": source_job.id,
                "user_id": source_job.owner_user_id,
                "ai_run_id": None,
                "audience": "client",
            }

        def refuse_notification(session: Session, _context: object, _instances: object) -> None:
            if any(isinstance(item, UserNotification) for item in session.new):
                raise RuntimeError("controlled notification commit failure")

        sql_event.listen(Session, "before_flush", refuse_notification)
        before = current_log_context()
        try:
            with (
                capture_logs(runtime) as capture,
                pytest.raises(RuntimeError, match="controlled notification commit failure"),
            ):
                await consume_event(runtime, row.id)
        finally:
            sql_event.remove(Session, "before_flush", refuse_notification)
        assert current_log_context() == before
        assert len(capture.rows) == 1 and capture.rows[0]["event"] == "notification.delivery.failed"
        assert_safe_log_correlation(capture.rows[0], expected)
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(UserNotification)) == 0
            assert await session.scalar(select(func.count()).select_from(InboxEvent)) == 0
            assert await session.scalar(select(Library.notification_sequence)) == 0
        assert await consume_event(runtime, row.id)
        assert not await consume_event(runtime, row.id)


async def test_history_needs_review_remains_valid_after_same_generation_completion(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(runtime, maintenance, f"history-{run_id}@haruka.example.test"):
        _, job_id = await accepted_source(
            runtime,
            web,
            headers,
            b"A short ambiguous source needing language confirmation.",
            language="en",
        )
        await execute_source_job(runtime, job_id, "history-notification-source")
        original = await source_event(runtime, job_id, "needs_review")
        blocked = (await web.get(f"/api/v1/jobs/{job_id}")).json()["data"]
        confirmation = {
            "expected_revision": blocked["revision"],
            "language_confirmation": {
                "language": "en",
                "input_digest": blocked["language_issue"]["input_digest"],
                "expected_job_generation": blocked["generation"],
                "expected_issue_revision": blocked["language_issue"]["revision"],
            },
        }
        assert (
            await web.post(
                f"/api/v1/jobs/{job_id}/retry",
                json=confirmation,
                headers={**headers, "Idempotency-Key": str(uuid4())},
            )
        ).status_code == 200
        await execute_source_job(runtime, job_id, "history-notification-resumed")
        completed = await source_event(runtime, job_id)
        assert await consume_event(runtime, original.id)
        assert await consume_event(runtime, completed.id)
        async with runtime.resources.database.sessions() as session:
            kinds = list(
                await session.scalars(
                    select(UserNotification.notification_kind).order_by(UserNotification.sequence)
                )
            )
            assert kinds == ["needs_review", "completed"]
            assert (
                await session.scalar(
                    select(Library.notification_sequence).where(
                        Library.id == UUID(str(original.payload["library_id"]))
                    )
                )
                == 2
            )


@pytest.mark.parametrize("stale", ["delete", "generation"])
async def test_stale_outcome_sealed_without_reviving_source(
    source_runtime: tuple[Runtime, MaintenanceSettings, str], stale: str
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(runtime, maintenance, f"stale-{run_id}@haruka.example.test"):
        material_id, job_id = await accepted_source(
            runtime, web, headers, "これは日本語の小説です。".encode()
        )
        await execute_source_job(runtime, job_id, "stale-notification-source")
        row = await source_event(runtime, job_id)
        if stale == "delete":
            metadata = (await web.get(f"/api/v1/materials/{material_id}")).json()["data"]
            assert (
                await web.delete(
                    f"/api/v1/materials/{material_id}?expected_revision={metadata['revision']}",
                    headers=headers,
                )
            ).status_code == 204
        else:
            # Prepare a newer durable execution generation, not a notification result.
            async with runtime.resources.database.sessions() as session, session.begin():
                job = await session.get(Job, job_id, with_for_update=True)
                assert job is not None
                job.generation += 1
                job.updated_at = datetime.now(UTC)
        assert not await consume_event(runtime, row.id)
        assert await recover_notifications(runtime) == 0
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(UserNotification)) == 0
            assert await session.scalar(select(func.count()).select_from(InboxEvent)) == 1
            assert await session.scalar(select(Library.notification_sequence)) == 0


async def test_forged_envelope_and_cross_owner_links_do_not_consume_valid_event(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(runtime, maintenance, f"links-{run_id}@haruka.example.test"):
        _, job_id = await accepted_source(
            runtime, web, headers, "これは日本語の小説です。".encode()
        )
        await execute_source_job(runtime, job_id, "links-notification-source")
        row = await source_event(runtime, job_id)
        wire = canonical_envelope(row)
        with pytest.raises(AppError):
            await consume_event(
                runtime, row.id, {**wire, "payload": {**row.payload, "owner_user_id": str(uuid4())}}
            )
        for key in (
            "actor",
            "library",
            "file",
            "import",
            "revision",
            "asset",
            "version",
            "upload",
            "format",
        ):
            old_file: UUID | None = None
            # Temporary bad logical references exercise validation, never seed a successful result.
            async with runtime.resources.database.sessions() as session, session.begin():
                job = await session.get(Job, job_id, with_for_update=True)
                assert job is not None
                original_refs = dict(job.input_refs)
                actor = job.actor_user_id
                if key == "actor":
                    job.actor_user_id = uuid4()
                else:
                    mapping = {
                        "library": "library_id",
                        "file": "file_object_id",
                        "import": "import_id",
                        "revision": "material_revision_id",
                    }
                    if key in mapping:
                        job.input_refs = {**original_refs, mapping[key]: str(uuid4())}
                    elif key == "asset":
                        asset = await session.scalar(select(MaterialSourceAsset))
                        assert asset is not None
                        old_file = asset.file_object_id
                        asset.file_object_id = uuid4()
                    elif key == "version":
                        revision = await session.get(
                            MaterialRevision, UUID(str(job.input_refs["material_revision_id"]))
                        )
                        assert revision is not None
                        revision.revision_number = 2
                    elif key == "upload":
                        upload = await session.scalar(
                            select(UploadIntent).where(UploadIntent.purpose == "primary_document")
                        )
                        assert upload is not None and upload.file_object_id is not None
                        old_file = upload.file_object_id
                        upload.file_object_id = uuid4()
                    else:
                        material = await session.get(
                            Material, UUID(str(original_refs["material_id"]))
                        )
                        assert material is not None
                        material.source_format = "pdf"
            try:
                with pytest.raises(AppError):
                    await consume_event(runtime, row.id)
            finally:
                async with runtime.resources.database.sessions() as session, session.begin():
                    job = await session.get(Job, job_id, with_for_update=True)
                    assert job is not None
                    job.input_refs, job.actor_user_id = original_refs, actor
                    if key == "asset":
                        assert old_file is not None
                        asset = await session.scalar(select(MaterialSourceAsset))
                        assert asset is not None
                        asset.file_object_id = old_file
                    if key == "version":
                        revision = await session.get(
                            MaterialRevision, UUID(str(original_refs["material_revision_id"]))
                        )
                        assert revision is not None
                        revision.revision_number = 1
                    if key == "upload":
                        upload = await session.scalar(
                            select(UploadIntent).where(UploadIntent.purpose == "primary_document")
                        )
                        assert upload is not None and old_file is not None
                        upload.file_object_id = old_file
                    if key == "format":
                        material = await session.get(
                            Material, UUID(str(original_refs["material_id"]))
                        )
                        assert material is not None
                        material.source_format = "md"
        async with runtime.resources.database.sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InboxEvent)) == 0
            assert await session.scalar(select(Library.notification_sequence)) == 0
        assert await consume_event(runtime, row.id)
        async with runtime.resources.database.sessions() as session:
            material = await session.get(Material, UUID(str(row.payload["material_id"])))
            assert material is not None and material.delete_generation == 0


async def test_committed_failed_source_creates_safe_failure_receipt(
    source_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = source_runtime
    assert runtime.resources is not None
    async for web, headers in _owner(
        runtime, maintenance, f"failed-notification-{run_id}@haruka.example.test"
    ):
        _, job_id = await accepted_source(
            runtime,
            web,
            headers,
            "Это документ на русском языке для проверки границы языка.".encode(),
        )
        await execute_source_job(runtime, job_id, "failed-notification-source")
        failed = await source_event(runtime, job_id, "failed")
        assert await consume_event(runtime, failed.id)
        assert not await consume_event(runtime, failed.id)
        async with runtime.resources.database.sessions() as session:
            job = await session.get(Job, job_id)
            assert job is not None and job.state == "failed"
            row = await session.scalar(
                select(UserNotification).where(UserNotification.job_id == job_id)
            )
            assert row is not None and row.notification_kind == "failed"
            assert row.message_code == "material.import.failed" and row.safe_parameters == {}
            assert row.resource_version == 1
            assert await session.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
