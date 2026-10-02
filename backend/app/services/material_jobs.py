"""Fenced deterministic source jobs in the existing durable worker lifecycle."""

import hashlib
import json
import logging
from datetime import UTC, datetime, timedelta
from typing import Literal, cast
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.source_validation import validate_bounded
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import (
    ai_run_id_context,
    audience_context,
    current_correlation,
    job_id_context,
    operation_id_context,
    request_id_context,
    user_id_context,
)
from app.domain.errors import AppError
from app.domain.material_sources import MAX_SOURCE_BYTES
from app.domain.scope import ScopeContext
from app.models import FileObject, MaterialImportIssue, MaterialRevision, OutboxEvent
from app.models.learning_reference import IdempotencyRecord, Material
from app.models.material_imports import MaterialImport
from app.models.model_tasks import Job, JobStage
from app.repositories import material_imports as repository
from app.schemas.model_settings import JobRead, LanguageConfirmation
from app.services import material_imports as sources
from app.services.model_tasks import commit_inbox, load_job

logger = logging.getLogger(__name__)
TERMINAL = {"succeeded", "failed", "cancelled"}


async def parents(
    session: AsyncSession, scope: ScopeContext, job: Job, *, lock: bool = False
) -> tuple[Material, MaterialRevision, FileObject, MaterialImport]:
    try:
        material_id = UUID(str(job.input_refs["material_id"]))
        revision_id = UUID(str(job.input_refs["material_revision_id"]))
        file_id = UUID(str(job.input_refs["file_object_id"]))
        import_id = UUID(str(job.input_refs["import_id"]))
    except (KeyError, ValueError):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    library = await repository.library(session, scope, lock=lock)
    row = await repository.owned(session, scope, MaterialImport, import_id, lock=lock)
    material = await repository.owned(session, scope, Material, material_id, lock=lock)
    query = select(MaterialRevision).where(
        MaterialRevision.id == revision_id,
        MaterialRevision.owner_user_id == scope.user_id,
        MaterialRevision.library_id == library.id,
        MaterialRevision.material_id == material.id,
        MaterialRevision.origin_job_id == job.id,
    )
    revision = await session.scalar(query.with_for_update() if lock else query)
    file_query = select(FileObject).where(
        FileObject.id == file_id,
        FileObject.user_id == scope.user_id,
        FileObject.purpose == "primary_document",
        FileObject.retention_state == "referenced",
    )
    file = await session.scalar(file_query.with_for_update() if lock else file_query)
    if (
        revision is None
        or file is None
        or material.library_id != library.id
        or row.library_id != library.id
        or row.material_id != material.id
        or row.initial_job_id != job.id
        or row.status != "accepted"
        or material.primary_file_object_id != file.id
        or revision.input_delete_generation != material.delete_generation
        or job.input_refs.get("delete_generation") != material.delete_generation
        or job.input_digest != file.sha256
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return material, revision, file, row


async def read_job(session: AsyncSession, scope: ScopeContext, identifier: UUID) -> JobRead:
    await sources.verify(session, scope, ("client.job.read", "client.material.read"))
    job = await load_job(session, scope.user_id, identifier)
    material, revision, _file, _row = await parents(session, scope, job)
    await sources.type_permission(session, scope, material.material_type, "read")
    issue = await session.scalar(
        select(MaterialImportIssue)
        .where(
            MaterialImportIssue.owner_user_id == scope.user_id,
            MaterialImportIssue.job_id == job.id,
            MaterialImportIssue.job_generation == job.generation,
            MaterialImportIssue.status == "open",
        )
        .order_by(MaterialImportIssue.id)
        .limit(1)
    )
    return JobRead.model_validate(
        {
            "id": job.id,
            "run_id": None,
            "credential_id": None,
            "operation_kind": "material_import",
            "material_id": material.id,
            "material_revision_id": revision.id,
            "source_status": material.source_status,
            "language_issue": None
            if issue is None
            else {
                "id": issue.id,
                "revision": issue.revision,
                "input_digest": issue.input_digest.hex(),
                "material_revision_id": revision.id,
                "declared_language": material.language,
            },
            "state": job.state,
            "revision": job.revision,
            "generation": job.generation,
            "sequence": job.progress_seq,
            "stage": "language_assessment"
            if job.state == "blocked"
            else "source_dispatch"
            if job.state == "succeeded"
            else "source_validation",
            "progress_percent": 100
            if job.state == "succeeded"
            else 50
            if job.state == "blocked"
            else 0,
            "error_code": job.error_code,
            "can_cancel": job.state not in TERMINAL,
            "can_retry": job.state in {"blocked", "failed"},
            "requires_new_attempt_confirmation": False,
            "created_at": job.created_at,
            "updated_at": job.updated_at,
        }
    )


def emit(
    session: AsyncSession, job: Job, material: Material, revision: MaterialRevision, kind: str
) -> None:
    session.add(
        OutboxEvent(
            event_type=kind,
            status="pending",
            audit_event_id=None,
            authorization_revision=None,
            payload={
                "schema_version": 1,
                "job_id": str(job.id),
                "material_id": str(material.id),
                "material_revision_id": str(revision.id),
                "resource_version": revision.revision_number,
                "owner_user_id": str(job.owner_user_id),
                "library_id": str(material.library_id),
                "job_generation": job.generation,
                "delete_generation": material.delete_generation,
            },
        )
    )


async def execute_source_job(
    runtime: Runtime, identifier: UUID, worker: str, *, inbox: tuple[UUID, bytes] | None = None
) -> None:
    resources = sources.source_resources(runtime)
    async with resources.database.sessions() as session:
        job = await session.get(Job, identifier)
        if job is None or job.operation_kind != "material_import":
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    request_token = request_id_context.set(job.request_id)
    operation_token = operation_id_context.set(job.operation_id)
    job_token = job_id_context.set(job.id)
    user_token = user_id_context.set(job.owner_user_id)
    audience_token = audience_context.set("client")
    run_token = ai_run_id_context.set(None)
    try:
        await _execute_source_job(runtime, identifier, worker, inbox=inbox)
    finally:
        request_id_context.reset(request_token)
        operation_id_context.reset(operation_token)
        job_id_context.reset(job_token)
        user_id_context.reset(user_token)
        audience_context.reset(audience_token)
        ai_run_id_context.reset(run_token)


async def worker_scope(session: AsyncSession, job: Job) -> ScopeContext:
    from app.models import User
    from app.services.auth_context import require_permissions

    user = await session.scalar(select(User).where(User.id == job.actor_user_id).with_for_update())
    now = datetime.now(UTC)
    if (
        user is None
        or user.id != job.owner_user_id
        or user.status != "active"
        or (user.locked_until is not None and user.locked_until > now)
    ):
        raise AppError(ErrorCode.PERMISSION_DENIED)
    await require_permissions(
        session,
        user_id=user.id,
        audience="client",
        codes=("client.login", "client.material.import"),
    )
    return ScopeContext(
        user.id,
        job.session_id,
        "client",
        cast(Literal["web", "native"], job.transport),
        user.authz_version,
        0,
        user.security_epoch,
        now,
    )


async def _execute_source_job(
    runtime: Runtime, identifier: UUID, worker: str, *, inbox: tuple[UUID, bytes] | None = None
) -> None:
    resources = sources.source_resources(runtime)
    async with resources.database.sessions() as session:
        candidate = await session.get(Job, identifier)
        if candidate is None or candidate.operation_kind != "material_import":
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        scope = ScopeContext(
            candidate.owner_user_id,
            candidate.session_id,
            "client",
            cast(Literal["web", "native"], candidate.transport),
            0,
            0,
            0,
            datetime.now(UTC),
        )
    claim: tuple[int, int] | None = None
    try:
        async with resources.database.sessions() as session, session.begin():
            job = await load_job(session, scope.user_id, identifier)
            scope = await worker_scope(session, job)
            material, revision, file, row = await parents(session, scope, job, lock=True)
            await sources.type_permission(session, scope, material.material_type, "import")
            await sources.check_reuse(session, scope, row)
            job = await load_job(session, scope.user_id, identifier, lock=True)
            now = datetime.now(UTC)
            if job.state in TERMINAL or job.state == "blocked":
                await commit_inbox(session, inbox)
                return
            if job.lease_expires_at is not None and job.lease_expires_at > now:
                return
            if job.state == "cancel_requested":
                job.state, job.finished_at = "cancelled", now
                job.fence += 1
                job.revision += 1
                job.progress_seq += 1
                job.lease_owner = job.lease_expires_at = None
                job.updated_at = now
                await commit_inbox(session, inbox)
                return
            job.state, job.lease_owner = "running", worker
            job.fence += 1
            job.revision += 1
            job.progress_seq += 1
            job.lease_expires_at = now + timedelta(seconds=120)
            job.heartbeat_at = job.updated_at = now
            fence, generation, key, declared, kind = (
                job.fence,
                job.generation,
                file.object_key,
                file.format_code,
                material.material_type,
            )
            digest = file.sha256
            claim = (fence, generation)
        storage = resources.storage
        if storage is None or key is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        raw = await storage.get_bounded(key, MAX_SOURCE_BYTES)
        if hashlib.sha256(raw).digest() != digest:
            raise AppError(ErrorCode.INPUT_INVALID)
        evidence = await validate_bounded(raw, declared, kind)
        if evidence.language == "unsupported":
            raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
        async with resources.database.sessions() as session, session.begin():
            job = await load_job(session, scope.user_id, identifier)
            scope = await worker_scope(session, job)
            material, revision, file, row = await parents(session, scope, job, lock=True)
            await sources.type_permission(session, scope, material.material_type, "import")
            await sources.check_reuse(session, scope, row)
            job = await load_job(session, scope.user_id, identifier, lock=True)
            now = datetime.now(UTC)
            if (
                job.fence != fence
                or job.generation != generation
                or job.state != "running"
                or job.lease_owner != worker
                or job.lease_expires_at is None
                or job.lease_expires_at <= now
            ):
                return
            resolution = await session.scalar(
                select(JobStage).where(
                    JobStage.job_id == job.id,
                    JobStage.job_generation == job.generation,
                    JobStage.stage_key == "language_resolution",
                )
            )
            confirmed = (
                resolution is not None
                and resolution.result_refs is not None
                and resolution.result_refs.get("input_digest") == digest.hex()
                and resolution.result_refs.get("language") == material.language
                and isinstance(resolution.result_refs.get("idempotency_digest"), str)
            )
            uncertain = evidence.language != material.language and not confirmed
            assessment = await session.scalar(
                select(JobStage).where(
                    JobStage.job_id == job.id,
                    JobStage.job_generation == job.generation,
                    JobStage.stage_key == "language_assessment",
                )
            )
            if assessment is None:
                session.add(
                    JobStage(
                        id=uuid4(),
                        owner_user_id=job.owner_user_id,
                        job_id=job.id,
                        job_generation=job.generation,
                        stage_key="language_assessment",
                        state="blocked" if uncertain else "succeeded",
                        fence=fence,
                        result_refs={"input_digest": digest.hex(), "language": evidence.language},
                    )
                )
            if uncertain:
                job.state, job.error_code = "blocked", ErrorCode.INPUT_INVALID.value
                session.add(
                    MaterialImportIssue(
                        id=uuid4(),
                        owner_user_id=scope.user_id,
                        library_id=material.library_id,
                        material_id=material.id,
                        material_revision_id=revision.id,
                        file_object_id=file.id,
                        job_id=job.id,
                        job_generation=job.generation,
                        input_delete_generation=material.delete_generation,
                        input_digest=digest,
                        stage_code="language_assessment",
                        kind="language_confirmation_required",
                        severity="blocking",
                        status="open",
                        source_refs={"material_revision_id": str(revision.id)},
                        schema_version=1,
                        revision=1,
                    )
                )
                emit(session, job, material, revision, "material.import.needs_review")
            else:
                revision.status, revision.published_at, revision.content_digest = (
                    "published",
                    now,
                    digest,
                )
                revision.updated_at = now
                material.current_revision_id = revision.id
                material.revision += 1
                material.updated_at = now
                # Source publication does not publish a reading/assessment structure.
                job.state, job.finished_at, job.error_code = "succeeded", now, None
                emit(session, job, material, revision, "material.import.completed")
            job.revision += 1
            job.progress_seq += 1
            job.lease_owner = job.lease_expires_at = None
            job.updated_at = now
            await commit_inbox(session, inbox)
        logger.info(
            "material.import.needs_review" if uncertain else "material.import.completed",
            extra={
                "job_id": identifier,
                "operation_id": candidate.operation_id,
                "request_id": candidate.request_id,
                "user_id": scope.user_id,
            },
        )
    except AppError as error:
        if error.code == ErrorCode.SERVICE_UNAVAILABLE:
            raise
        # No supplier or private publishing occurs after lost scope. Fail only
        # this committed job under the same user/library/material lock order.
        await fail_source_job(runtime, scope, identifier, error.code, inbox, claim=claim)


async def fail_source_job(
    runtime: Runtime,
    scope: ScopeContext,
    identifier: UUID,
    code: ErrorCode,
    inbox: tuple[UUID, bytes] | None,
    *,
    claim: tuple[int, int] | None = None,
) -> None:
    resources = sources.source_resources(runtime)
    from app.models.identity import User

    async with resources.database.sessions() as session, session.begin():
        await session.scalar(select(User).where(User.id == scope.user_id).with_for_update())
        await repository.library(session, scope, lock=True)
        job = await load_job(session, scope.user_id, identifier)
        material_id = UUID(str(job.input_refs["material_id"]))
        material = await session.scalar(
            select(Material)
            .where(Material.id == material_id, Material.owner_user_id == scope.user_id)
            .with_for_update()
        )
        revision = await session.scalar(
            select(MaterialRevision)
            .where(
                MaterialRevision.id == UUID(str(job.input_refs["material_revision_id"])),
                MaterialRevision.owner_user_id == scope.user_id,
                MaterialRevision.material_id == material_id,
            )
            .with_for_update()
        )
        job = await load_job(session, scope.user_id, identifier, lock=True)
        if claim is not None and (job.fence, job.generation) != claim:
            return
        if job.state in TERMINAL:
            await commit_inbox(session, inbox)
            return
        if job.state == "cancel_requested":
            # Fixed owner maintenance may seal an already authorized cancellation
            # even after the import permission or originating session is revoked.
            now = datetime.now(UTC)
            job.state, job.finished_at, job.updated_at = "cancelled", now, now
            job.fence += 1
            job.revision += 1
            job.progress_seq += 1
            job.lease_owner = job.lease_expires_at = None
            await commit_inbox(session, inbox)
            return
        job.state, job.error_code, job.finished_at = "failed", code.value, datetime.now(UTC)
        job.fence += 1
        job.revision += 1
        job.progress_seq += 1
        job.updated_at = datetime.now(UTC)
        job.lease_owner = job.lease_expires_at = None
        if (
            material is not None
            and revision is not None
            and material.deleted_at is None
            and revision.status == "building"
        ):
            revision.status = "failed"
            revision.structure_status = None if material.material_type == "exam" else "failed"
            revision.updated_at = datetime.now(UTC)
            material.source_status, material.updated_at = "failed", datetime.now(UTC)
            material.revision += 1
            emit(session, job, material, revision, "material.import.failed")
        await commit_inbox(session, inbox)
    logger.info("material.import.failed", extra={"job_id": identifier, "user_id": scope.user_id})


async def change_job(
    session: AsyncSession,
    scope: ScopeContext,
    identifier: UUID,
    expected_revision: int,
    *,
    retry: bool,
    confirmation: LanguageConfirmation | None = None,
    idempotency_digest: bytes | None = None,
) -> JobRead:
    await sources.verify(
        session,
        scope,
        ("client.job.retry", "client.material.import") if retry else ("client.job.cancel",),
        lock=True,
    )
    job = await load_job(session, scope.user_id, identifier)
    material, revision, _file, row = await parents(session, scope, job, lock=True)
    if retry:
        await sources.type_permission(session, scope, material.material_type, "import")
        await sources.check_reuse(session, scope, row)
    job = await load_job(session, scope.user_id, identifier, lock=True)
    now = datetime.now(UTC)
    request_digest: bytes | None = None
    if retry and confirmation is not None:
        if idempotency_digest is None:
            raise AppError(ErrorCode.INPUT_INVALID)
        request_digest = hashlib.sha256(
            json.dumps(
                {
                    "job_id": str(job.id),
                    "expected_revision": expected_revision,
                    "confirmation": confirmation.model_dump(mode="json"),
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
        ).digest()
        receipt = await session.scalar(
            select(IdempotencyRecord)
            .where(
                IdempotencyRecord.owner_user_id == scope.user_id,
                IdempotencyRecord.audience == "client",
                IdempotencyRecord.action_code == "client.job.retry.language_confirmation",
                IdempotencyRecord.key_digest == idempotency_digest,
            )
            .with_for_update()
        )
        if receipt is not None:
            if receipt.request_digest != request_digest or receipt.result_id != row.id:
                raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
            return await read_job(session, scope, identifier)
        prior = await session.scalar(
            select(JobStage)
            .where(
                JobStage.job_id == job.id,
                JobStage.job_generation == confirmation.expected_job_generation,
                JobStage.stage_key == "language_resolution",
            )
            .with_for_update()
        )
        expected_refs = {
            "input_digest": confirmation.input_digest,
            "language": confirmation.language,
            "idempotency_digest": idempotency_digest.hex(),
        }
        if prior is not None:
            if (
                prior.result_refs != expected_refs
                or job.generation != confirmation.expected_job_generation
            ):
                raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
            return await read_job(session, scope, identifier)
    if job.revision != expected_revision:
        raise AppError(ErrorCode.REVISION_CONFLICT)
    if not retry:
        if job.state not in TERMINAL:
            job.state, job.finished_at = "cancelled", now
            job.fence += 1
    elif confirmation is not None:
        assessment = await session.scalar(
            select(JobStage).where(
                JobStage.job_id == job.id,
                JobStage.job_generation == job.generation,
                JobStage.stage_key == "language_assessment",
            )
        )
        if (
            assessment is not None
            and assessment.result_refs is not None
            and assessment.result_refs.get("language") not in {None, confirmation.language}
        ):
            raise AppError(ErrorCode.INPUT_INVALID)
        issue = await session.scalar(
            select(MaterialImportIssue)
            .where(
                MaterialImportIssue.owner_user_id == scope.user_id,
                MaterialImportIssue.job_id == job.id,
                MaterialImportIssue.job_generation == job.generation,
                MaterialImportIssue.status == "open",
            )
            .with_for_update()
        )
        if (
            job.state != "blocked"
            or issue is None
            or job.generation != confirmation.expected_job_generation
            or issue.revision != confirmation.expected_issue_revision
            or confirmation.input_digest != job.input_digest.hex()
            or issue.input_digest != job.input_digest
            or issue.material_revision_id != revision.id
            or idempotency_digest is None
            or request_digest is None
        ):
            raise AppError(ErrorCode.REVISION_CONFLICT)
        issue.status, issue.resolution_code, issue.resolved_by_user_id, issue.resolved_at = (
            "resolved",
            "user_confirmed_language",
            scope.user_id,
            now,
        )
        issue.revision += 1
        issue.updated_at = now
        if material.language != confirmation.language:
            material.language = confirmation.language
            material.revision += 1
            material.updated_at = now
        session.add(
            JobStage(
                id=uuid4(),
                owner_user_id=scope.user_id,
                job_id=job.id,
                job_generation=job.generation,
                stage_key="language_resolution",
                state="succeeded",
                fence=job.fence,
                result_refs={
                    "input_digest": job.input_digest.hex(),
                    "language": confirmation.language,
                    "idempotency_digest": idempotency_digest.hex(),
                },
            )
        )
        session.add(
            IdempotencyRecord(
                id=uuid4(),
                owner_user_id=scope.user_id,
                library_id=material.library_id,
                audience="client",
                revision=1,
                action_code="client.job.retry.language_confirmation",
                key_digest=idempotency_digest,
                request_digest=request_digest,
                state="committed",
                result_kind="material_import",
                result_id=row.id,
                response_schema_version=1,
                safe_response={"job_id": str(job.id)},
                http_status=200,
                expires_at=now + timedelta(days=30),
                operation_id=current_correlation()[1] or job.operation_id,
            )
        )
        job.state, job.error_code = "queued", None
    else:
        if job.state != "failed" or revision.status != "failed":
            raise AppError(ErrorCode.STATE_CONFLICT)
        job.generation += 1
        revision.status, revision.structure_status = (
            "building",
            None if material.material_type == "exam" else "building",
        )
        revision.updated_at = now
        material.source_status, material.updated_at = "parsing", now
        material.revision += 1
        job.state, job.error_code, job.finished_at = "queued", None, None
    job.revision += 1
    job.progress_seq += 1
    job.lease_owner = job.lease_expires_at = None
    job.updated_at = now
    emit(
        session,
        job,
        material,
        revision,
        "material.job.accepted" if retry else "material.job.updated",
    )
    await session.flush()
    # Cancelling requires no remaining import/read permission; projection uses
    # already-authorized owned parents rather than imposing another action.
    return JobRead.model_validate(
        {
            "id": job.id,
            "operation_kind": "material_import",
            "material_id": material.id,
            "material_revision_id": revision.id,
            "source_status": material.source_status,
            "state": job.state,
            "revision": job.revision,
            "generation": job.generation,
            "sequence": job.progress_seq,
            "can_cancel": job.state not in TERMINAL,
            "can_retry": job.state in {"blocked", "failed"},
            "requires_new_attempt_confirmation": False,
            "error_code": job.error_code,
            "created_at": job.created_at,
            "updated_at": job.updated_at,
        }
    )
