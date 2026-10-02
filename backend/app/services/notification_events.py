"""Seal safe committed source outcomes with an independent persistent Inbox."""

import hashlib
import json
import logging
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import (
    ai_run_id_context,
    audience_context,
    current_log_context,
    job_id_context,
    operation_id_context,
    request_id_context,
    user_id_context,
)
from app.domain.errors import AppError
from app.models import (
    FileObject,
    Library,
    MaterialImport,
    MaterialRevision,
    OutboxEvent,
    UploadIntent,
    User,
)
from app.models.learning_reference import Material
from app.models.material_imports import MaterialSourceAsset
from app.models.model_tasks import InboxEvent, Job
from app.models.user_notifications import UserNotification

logger = logging.getLogger(__name__)
CONSUMER_NAME = "user-notifications"
EVENT_TYPES = (
    "material.import.completed",
    "material.import.failed",
    "material.import.needs_review",
)


class SourceOutcome(BaseModel):
    """Exact source producer payload; no supplied text, storage keys or secrets."""

    model_config = ConfigDict(extra="forbid", strict=True)
    schema_version: Annotated[int, Field(ge=1, le=1)]
    job_id: UUID
    material_id: UUID
    material_revision_id: UUID
    resource_version: Annotated[int, Field(ge=1)]
    owner_user_id: UUID
    library_id: UUID
    job_generation: Annotated[int, Field(ge=1)]
    delete_generation: Annotated[int, Field(ge=0)]

    @field_validator(
        "job_id",
        "material_id",
        "material_revision_id",
        "owner_user_id",
        "library_id",
        mode="before",
    )
    @classmethod
    def canonical_uuid(cls, value: object) -> UUID:
        if not isinstance(value, str):
            raise ValueError("source reference must be a canonical UUID string")
        identifier = UUID(value)
        if str(identifier) != value:
            raise ValueError("source reference must be a canonical UUID string")
        return identifier


def canonical_envelope(event: OutboxEvent) -> dict[str, object]:
    return {"event_id": str(event.id), "event_type": event.event_type, "payload": event.payload}


def envelope_bytes(envelope: dict[str, object]) -> bytes:
    try:
        return json.dumps(envelope, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    except (ValueError, TypeError):
        raise AppError(ErrorCode.INPUT_INVALID) from None


def source_outcome(event: OutboxEvent, envelope: dict[str, object] | None) -> SourceOutcome:
    if event.event_type not in EVENT_TYPES or event.status not in {"pending", "published"}:
        raise AppError(ErrorCode.INPUT_INVALID)
    if envelope is not None and envelope_bytes(envelope) != envelope_bytes(
        canonical_envelope(event)
    ):
        raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
    try:
        return SourceOutcome.model_validate(event.payload)
    except ValidationError:
        raise AppError(ErrorCode.INPUT_INVALID) from None


async def consume_event(
    runtime: Runtime, event_id: UUID, envelope: dict[str, object] | None = None
) -> bool:
    """Return new creation; any normal return has committed its consumer receipt."""
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session:
        event = await session.get(OutboxEvent, event_id)
        if event is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        payload = source_outcome(event, None)
        candidate = await session.get(Job, payload.job_id)
        if candidate is None or candidate.owner_user_id != payload.owner_user_id:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    request_token = request_id_context.set(candidate.request_id)
    operation_token = operation_id_context.set(candidate.operation_id)
    job_token = job_id_context.set(candidate.id)
    user_token = user_id_context.set(candidate.owner_user_id)
    audience_token = audience_context.set("client")
    run_token = ai_run_id_context.set(None)
    try:
        created = await _consume_event(runtime, event_id, envelope)
        if created:
            logger.info("notification.created", extra=current_log_context())
        return created
    except Exception:
        # No exception/body/SQL parameters are included in the normal logging lane.
        logger.warning("notification.delivery.failed", extra=current_log_context())
        raise
    finally:
        request_id_context.reset(request_token)
        operation_id_context.reset(operation_token)
        job_id_context.reset(job_token)
        user_id_context.reset(user_token)
        audience_context.reset(audience_token)
        ai_run_id_context.reset(run_token)


async def _consume_event(
    runtime: Runtime, event_id: UUID, envelope: dict[str, object] | None
) -> bool:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session, session.begin():
        event = await session.get(OutboxEvent, event_id)
        if event is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        payload = source_outcome(event, envelope)
        digest = hashlib.sha256(envelope_bytes(canonical_envelope(event))).digest()
        user = await session.scalar(
            select(User).where(User.id == payload.owner_user_id).with_for_update()
        )
        library = await session.scalar(
            select(Library)
            .where(Library.id == payload.library_id, Library.owner_user_id == payload.owner_user_id)
            .with_for_update()
        )
        if user is None or library is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        material = await session.scalar(
            select(Material)
            .where(
                Material.id == payload.material_id,
                Material.owner_user_id == user.id,
                Material.library_id == library.id,
            )
            .with_for_update()
        )
        job = await session.scalar(
            select(Job)
            .where(Job.id == payload.job_id, Job.owner_user_id == user.id)
            .with_for_update()
        )
        if (
            job is None
            or job.actor_user_id != user.id
            or job.operation_kind != "material_import"
            or job.audience != "client"
            or job.credential_id is not None
            or job.run_id is not None
            or job.input_refs.get("material_id") != str(payload.material_id)
            or job.input_refs.get("material_revision_id") != str(payload.material_revision_id)
            or job.input_refs.get("library_id") != str(library.id)
            or type(job.input_refs.get("delete_generation")) is not int
            or job.input_refs.get("delete_generation") != payload.delete_generation
        ):
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        old = await session.scalar(
            select(InboxEvent).where(
                InboxEvent.consumer_name == CONSUMER_NAME, InboxEvent.event_id == event.id
            )
        )
        if old is not None:
            if old.payload_digest != digest:
                raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
            return False
        if job.generation < payload.job_generation or (
            material is not None and material.delete_generation < payload.delete_generation
        ):
            raise AppError(ErrorCode.INPUT_INVALID)
        now = datetime.now(UTC)
        # These already committed outcomes have become obsolete. Preserve the
        # independent receipt so recovery cannot revive their resource or loop.
        stale = (
            job.generation > payload.job_generation
            or material is None
            or material.deleted_at is not None
            or material.delete_generation > payload.delete_generation
        )
        created = False
        if not stale:
            if material is None:
                raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
            await verify_source(session, payload, job, material)
            kind: Literal["completed", "failed", "needs_review"] = (
                "completed"
                if event.event_type == EVENT_TYPES[0]
                else "failed"
                if event.event_type == EVENT_TYPES[1]
                else "needs_review"
            )
            existing = await session.scalar(
                select(UserNotification).where(
                    UserNotification.owner_user_id == user.id,
                    UserNotification.source_event_id == event.id,
                    UserNotification.notification_kind == kind,
                )
            )
            if existing is None:
                created = True
                library.notification_sequence += 1
                library.updated_at = now
                session.add(
                    UserNotification(
                        owner_user_id=user.id,
                        library_id=library.id,
                        source_event_id=event.id,
                        job_id=job.id,
                        notification_kind=kind,
                        resource_kind="material",
                        resource_id=material.id,
                        resource_version=payload.resource_version,
                        message_code=event.event_type,
                        schema_version=1,
                        safe_parameters={},
                        sequence=library.notification_sequence,
                        revision=1,
                    )
                )
        session.add(
            InboxEvent(
                consumer_name=CONSUMER_NAME,
                event_id=event.id,
                payload_digest=digest,
                processed_at=now,
            )
        )
        return created


async def verify_source(
    session: AsyncSession, payload: SourceOutcome, job: Job, material: Material
) -> None:
    """Read only safe references under the shared owner/library/material roots."""
    try:
        import_id = UUID(str(job.input_refs["import_id"]))
        file_id = UUID(str(job.input_refs["file_object_id"]))
    except (KeyError, ValueError):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND) from None
    intent = await session.get(MaterialImport, import_id)
    revision = await session.get(MaterialRevision, payload.material_revision_id)
    file = await session.get(FileObject, file_id)
    asset = await session.scalar(
        select(MaterialSourceAsset).where(
            MaterialSourceAsset.owner_user_id == payload.owner_user_id,
            MaterialSourceAsset.library_id == payload.library_id,
            MaterialSourceAsset.material_id == material.id,
            MaterialSourceAsset.material_revision_id == payload.material_revision_id,
            MaterialSourceAsset.file_object_id == file_id,
            MaterialSourceAsset.purpose == "primary_document",
            MaterialSourceAsset.ordinal == 1,
        )
    )
    if (
        intent is None
        or revision is None
        or file is None
        or asset is None
        or intent.owner_user_id != payload.owner_user_id
        or intent.library_id != payload.library_id
        or intent.status != "accepted"
        or intent.initial_job_id != job.id
        or intent.material_id != material.id
        or intent.material_type != material.material_type
        or revision.owner_user_id != payload.owner_user_id
        or revision.library_id != payload.library_id
        or revision.material_id != material.id
        or revision.origin_job_id != job.id
        or revision.revision_number != payload.resource_version
        or revision.material_type != material.material_type
        or revision.input_delete_generation != payload.delete_generation
        or material.initial_job_id != job.id
        or material.primary_file_object_id != file.id
        or file.user_id != payload.owner_user_id
        or file.purpose != "primary_document"
        or file.retention_state != "referenced"
        or file.sha256 != job.input_digest
        or file.format_code != material.source_format
    ):
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if intent.primary_upload_intent_id is None:
        if intent.reused_file_object_id != file.id or intent.reused_material_id is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    else:
        upload = await session.get(UploadIntent, intent.primary_upload_intent_id)
        if (
            upload is None
            or upload.user_id != payload.owner_user_id
            or upload.purpose != "primary_document"
            or upload.target_kind != "material_import"
            or upload.target_resource_id != intent.id
            or upload.status != "completed"
            or upload.file_object_id != file.id
            or file.upload_intent_id != upload.id
        ):
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
