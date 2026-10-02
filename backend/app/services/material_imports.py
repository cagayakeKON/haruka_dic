"""Purpose-bound staging, capacity reservations and fenced immutable source acceptance."""

import base64
import hashlib
import hmac
import json
import logging
from datetime import UTC, datetime, timedelta
from typing import cast
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.source_validation import validate_bounded
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.material_sources import (
    FORMAT_MAX_BYTES,
    FORMATS,
    MAX_SOURCE_BYTES,
    MEDIA_TYPES,
    QUOTA_BYTES,
    UPLOAD_TTL_SECONDS,
)
from app.domain.scope import ScopeContext
from app.models import FileObject, OutboxEvent, UploadIntent
from app.models.learning_reference import (
    IdempotencyRecord,
    Material,
    MaterialRevision,
    NovelChapter,
)
from app.models.material_imports import (
    MaterialImport,
    MaterialSourceAsset,
    UserStorageReservation,
    UserStorageState,
)
from app.models.model_tasks import Job
from app.repositories import material_imports as repository
from app.schemas.material_imports import (
    MaterialImportCreate,
    MaterialImportRead,
    MaterialMetadataRead,
)
from app.services.auth_context import require_permissions, verify_scope_in_transaction
from app.services.auth_crypto import AuthCrypto

logger = logging.getLogger(__name__)


def retire_candidate(upload: UploadIntent, now: datetime) -> None:
    key = upload.candidate_final_object_key
    if key is not None and key not in upload.retired_final_candidates:
        if len(upload.retired_final_candidates) >= 16:
            raise AppError(ErrorCode.QUOTA_EXCEEDED)
        upload.retired_final_candidates = [*upload.retired_final_candidates, key]
        upload.candidate_cleanup_due_at = now


async def change_material(
    runtime: Runtime, scope: ScopeContext, identifier: UUID, expected: int, *, title: str | None
) -> MaterialMetadataRead | None:
    resources = source_resources(runtime)
    async with resources.database.sessions() as session, session.begin():
        action = "update" if title is not None else "delete"
        await verify(session, scope, (f"client.material.{action}",), lock=True)
        await repository.library(session, scope, lock=True)
        row = await repository.owned(session, scope, Material, identifier, lock=True)
        await type_permission(session, scope, row.material_type, action)
        if row.revision != expected:
            raise AppError(ErrorCode.REVISION_CONFLICT)
        now = datetime.now(UTC)
        if title is not None:
            row.title, row.title_origin = title, "user"
        else:
            row.deleted_at = now
            row.delete_generation += 1
            jobs = await session.scalars(
                select(Job)
                .where(
                    Job.owner_user_id == scope.user_id,
                    Job.operation_kind == "material_import",
                    Job.input_refs["material_id"].astext == str(row.id),
                )
                .order_by(Job.id)
                .with_for_update()
            )
            for job in jobs:
                if job.state not in {"succeeded", "failed", "cancelled"}:
                    job.state = "cancelled"
                    job.fence += 1
                    job.progress_seq += 1
                    job.revision += 1
                    job.finished_at = now
                    job.lease_owner = job.lease_expires_at = None
                    job.updated_at = now
        row.revision += 1
        row.updated_at = now
        result = await metadata(session, scope, row) if title is not None else None
    logger.info(
        "material.metadata.updated" if title is not None else "material.deleted",
        extra={"user_id": scope.user_id},
    )
    return result


def source_resources(runtime: Runtime):
    if runtime.resources is None or runtime.resources.storage is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return runtime.resources


async def verify(
    session: AsyncSession, scope: ScopeContext, codes: tuple[str, ...], *, lock: bool = False
) -> ScopeContext:
    return await verify_scope_in_transaction(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience="client",
        transport=scope.transport,
        permissions=codes,
        lock_user=lock,
    )


async def type_permission(
    session: AsyncSession, scope: ScopeContext, material_type: str, action: str
) -> None:
    if material_type == "exam":
        code = {
            "read": "client.exam.read",
            "import": "client.exam.import",
            "update": "client.exam.edit",
            "delete": "client.exam.edit",
        }[action]
        await require_permissions(session, user_id=scope.user_id, audience="client", codes=(code,))


async def capacity(session: AsyncSession, scope: ScopeContext) -> UserStorageState:
    row = await session.scalar(
        select(UserStorageState).where(UserStorageState.user_id == scope.user_id).with_for_update()
    )
    if row is None:
        row = UserStorageState(
            id=uuid4(), user_id=scope.user_id, used_bytes=0, reserved_bytes=0, revision=1
        )
        session.add(row)
        await session.flush()
    return row


def _capability(runtime: Runtime, scope: ScopeContext, upload: UploadIntent) -> str:
    payload = (
        base64.urlsafe_b64encode(
            json.dumps(
                {
                    "id": str(upload.id),
                    "user": str(scope.user_id),
                    "session": str(scope.session_id),
                    "transport": scope.transport,
                    "expires": int(upload.expires_at.timestamp()),
                },
                separators=(",", ":"),
            ).encode()
        )
        .decode()
        .rstrip("=")
    )
    signature = AuthCrypto.from_settings(runtime.settings).digest("material-staging", payload).hex()
    return payload + "." + signature


def capability_scope(runtime: Runtime, identifier: UUID, token: str) -> ScopeContext:
    try:
        if len(token) > 1024:
            raise ValueError("bounded capability")
        payload, signature = token.split(".")
        expected = (
            AuthCrypto.from_settings(runtime.settings).digest("material-staging", payload).hex()
        )
        if not hmac.compare_digest(signature, expected):
            raise ValueError("invalid capability")
        decoded = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        expiry = datetime.fromtimestamp(decoded["expires"], UTC)
        if (
            UUID(decoded["id"]) != identifier
            or expiry <= datetime.now(UTC)
            or decoded["transport"] not in {"web", "native"}
        ):
            raise ValueError("expired capability")
        return ScopeContext(
            UUID(decoded["user"]),
            UUID(decoded["session"]),
            "client",
            decoded["transport"],
            0,
            0,
            0,
            expiry,
        )
    except Exception:
        raise AppError(ErrorCode.SESSION_INVALID) from None


async def read_intent(
    session: AsyncSession, runtime: Runtime, scope: ScopeContext, row: MaterialImport
) -> MaterialImportRead:
    await type_permission(session, scope, row.material_type, "import")
    upload = None
    if row.status == "awaiting_upload" and row.primary_upload_intent_id is not None:
        intent = await session.scalar(
            select(UploadIntent).where(
                UploadIntent.id == row.primary_upload_intent_id,
                UploadIntent.user_id == scope.user_id,
                UploadIntent.purpose == "primary_document",
                UploadIntent.target_resource_id == row.id,
            )
        )
        if intent is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        if row.expires_at > datetime.now(UTC):
            upload = {
                "id": intent.id,
                "method": "PUT",
                "url": f"/api/v1/uploads/{intent.id}/content",
                "headers": {
                    "X-Haruka-Upload-Capability": _capability(runtime, scope, intent),
                    "Content-Type": "application/octet-stream",
                },
                "expires_at": row.expires_at,
            }
    return MaterialImportRead.model_validate(
        {
            "id": row.id,
            "revision": row.revision,
            "material_type": row.material_type,
            "language": row.target_language,
            "status": row.status,
            "upload": upload,
            "material_id": row.material_id,
            "job_id": row.initial_job_id,
            "expires_at": row.expires_at,
        }
    )


async def create_import(
    runtime: Runtime,
    scope: ScopeContext,
    payload: MaterialImportCreate,
    key: str,
    operation_id: UUID,
    request_id: UUID,
) -> MaterialImportRead:
    resources = source_resources(runtime)
    crypto = AuthCrypto.from_settings(runtime.settings)
    key_digest = crypto.digest("material-import-idempotency", key)
    request_digest = hashlib.sha256(payload.model_dump_json().encode()).digest()
    async with resources.database.sessions() as session, session.begin():
        await verify(session, scope, ("client.material.import",), lock=True)
        await type_permission(session, scope, payload.material_type, "import")
        state = await capacity(session, scope)
        library = await repository.library(session, scope, lock=True)
        receipt = await session.scalar(
            select(IdempotencyRecord).where(
                IdempotencyRecord.owner_user_id == scope.user_id,
                IdempotencyRecord.action_code == "client.material.import",
                IdempotencyRecord.key_digest == key_digest,
            )
        )
        if receipt is not None:
            if receipt.request_digest != request_digest or receipt.result_id is None:
                raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
            row = await repository.owned(
                session, scope, MaterialImport, receipt.result_id, lock=True
            )
            await check_reuse(session, scope, row)
            return await read_intent(session, runtime, scope, row)
        now = datetime.now(UTC)
        row = MaterialImport(
            id=uuid4(),
            owner_user_id=scope.user_id,
            library_id=library.id,
            material_type=payload.material_type,
            target_language=payload.language,
            requested_title=payload.title,
            schema_version=1,
            requested_stages={"extract": True, "analyze": False},
            status="awaiting_upload",
            revision=1,
            idempotency_record_id=uuid4(),
            expires_at=now + timedelta(seconds=UPLOAD_TTL_SECONDS),
        )
        if payload.file is not None:
            source = payload.file
            maximum = FORMAT_MAX_BYTES[source.format]
            if source.size_bytes > maximum:
                raise AppError(ErrorCode.PAYLOAD_TOO_LARGE)
            if state.used_bytes + state.reserved_bytes + source.size_bytes > QUOTA_BYTES:
                raise AppError(ErrorCode.QUOTA_EXCEEDED)
            upload_id, reservation_id = uuid4(), uuid4()
            row.primary_upload_intent_id = upload_id
            session.add(
                UserStorageReservation(
                    id=reservation_id,
                    user_id=scope.user_id,
                    target_kind="upload_intent",
                    target_resource_id=upload_id,
                    reserved_bytes=source.size_bytes,
                    committed_bytes=0,
                    status="reserved",
                    revision=1,
                    expires_at=row.expires_at,
                )
            )
            session.add(
                UploadIntent(
                    id=upload_id,
                    user_id=scope.user_id,
                    purpose="primary_document",
                    target_kind="material_import",
                    target_resource_id=row.id,
                    declared_format=source.format,
                    expected_size_bytes=source.size_bytes,
                    expected_sha256=bytes.fromhex(source.sha256),
                    status="awaiting_upload",
                    expires_at=row.expires_at,
                    material_type=row.material_type,
                    original_filename=source.filename,
                    storage_reservation_id=reservation_id,
                    staging_object_key=f"material/staging/{scope.user_id}/{upload_id}",
                    revision=1,
                    completion_generation=0,
                )
            )
            state.reserved_bytes += source.size_bytes
            state.revision += 1
            state.updated_at = now
        else:
            row.reused_material_id = payload.source_material_id
            source_material = await repository.owned(
                session, scope, Material, cast(UUID, payload.source_material_id), lock=True
            )
            row.reused_file_object_id = source_material.primary_file_object_id
            file = await check_reuse(session, scope, row)
            if file is None:
                raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
            await _accept(session, scope, row, file, operation_id, request_id)
        session.add(row)
        session.add(
            IdempotencyRecord(
                id=row.idempotency_record_id,
                owner_user_id=scope.user_id,
                library_id=library.id,
                audience="client",
                revision=1,
                action_code="client.material.import",
                key_digest=key_digest,
                request_digest=request_digest,
                state="committed",
                result_kind="material_import",
                result_id=row.id,
                response_schema_version=1,
                safe_response={"import_id": str(row.id)},
                http_status=201,
                expires_at=now + timedelta(days=30),
                operation_id=operation_id,
            )
        )
        await session.flush()
        result = await read_intent(session, runtime, scope, row)
    logger.info(
        "material.import.accepted" if result.status == "accepted" else "material.import.created",
        extra={"user_id": scope.user_id, "operation_id": operation_id, "request_id": request_id},
    )
    return result


async def check_reuse(
    session: AsyncSession, scope: ScopeContext, row: MaterialImport
) -> FileObject | None:
    if row.reused_material_id is None:
        return None
    await require_permissions(
        session, user_id=scope.user_id, audience="client", codes=("client.material.read",)
    )
    source = await repository.owned(session, scope, Material, row.reused_material_id, lock=True)
    await type_permission(session, scope, source.material_type, "read")
    await type_permission(session, scope, source.material_type, "update")
    file = await session.scalar(
        select(FileObject)
        .where(
            FileObject.id == row.reused_file_object_id,
            FileObject.user_id == scope.user_id,
            FileObject.purpose == "primary_document",
        )
        .with_for_update()
    )
    if (
        file is None
        or source.primary_file_object_id != file.id
        or file.retention_state != "referenced"
        or file.format_code not in FORMATS[row.material_type]
    ):
        raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
    if source.library_id != row.library_id or not file.object_key or not file.bucket_name:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return file


async def _accept(
    session: AsyncSession,
    scope: ScopeContext,
    row: MaterialImport,
    file: FileObject,
    operation_id: UUID,
    request_id: UUID,
) -> None:
    material_id, revision_id, job_id = uuid4(), uuid4(), uuid4()
    row.status, row.material_id, row.initial_job_id = "accepted", material_id, job_id
    row.revision += 1
    row.updated_at = datetime.now(UTC)
    material = Material(
        id=material_id,
        owner_user_id=scope.user_id,
        library_id=row.library_id,
        material_type=row.material_type,
        title=row.requested_title or "未命名材料",
        language=row.target_language,
        current_revision_id=None,
        source_status="parsing",
        title_origin="user" if row.requested_title else "filename",
        source_format=file.format_code,
        primary_file_object_id=file.id,
        initial_job_id=job_id,
        analysis_status="not_requested",
        revision=1,
        delete_generation=0,
    )
    refs = {
        "material_id": str(material_id),
        "material_revision_id": str(revision_id),
        "file_object_id": str(file.id),
        "import_id": str(row.id),
        "library_id": str(row.library_id),
        "delete_generation": 0,
    }
    session.add(material)
    session.add(
        MaterialRevision(
            id=revision_id,
            owner_user_id=scope.user_id,
            library_id=row.library_id,
            material_id=material_id,
            revision_number=1,
            status="building",
            text_protocol_version="unicode-scalar-v1",
            structure_status=None if row.material_type == "exam" else "building",
            input_delete_generation=0,
            source_schema_version=1,
            processor_version="material-source-v1",
            material_type=row.material_type,
            origin_job_id=job_id,
            published_at=None,
            structure_published_at=None,
        )
    )
    session.add(
        MaterialSourceAsset(
            id=uuid4(),
            owner_user_id=scope.user_id,
            library_id=row.library_id,
            material_id=material_id,
            material_revision_id=revision_id,
            file_object_id=file.id,
            purpose="primary_document",
            ordinal=1,
            pixel_width=file.pixel_width,
            pixel_height=file.pixel_height,
        )
    )
    session.add(
        Job(
            id=job_id,
            owner_user_id=scope.user_id,
            actor_user_id=scope.user_id,
            session_id=scope.session_id,
            transport=scope.transport,
            audience="client",
            credential_id=None,
            run_id=None,
            operation_kind="material_import",
            operation_id=operation_id,
            request_id=request_id,
            input_refs=refs,
            input_digest=file.sha256,
            idempotency_digest=hashlib.sha256(("material-import:" + str(row.id)).encode()).digest(),
            state="queued",
            revision=1,
            generation=1,
            progress_seq=0,
            fence=0,
        )
    )
    session.add(
        OutboxEvent(
            event_type="material.job.accepted",
            audit_event_id=None,
            authorization_revision=None,
            status="pending",
            payload={"schema_version": 1, "job_id": str(job_id), "generation": 1, "sequence": 0},
        )
    )


async def upload_allowance(runtime: Runtime, scope: ScopeContext, identifier: UUID) -> int:
    """Fail closed on the current owner/session before allocating a request body."""
    resources = source_resources(runtime)
    if (
        await resources.cache.client.get(
            resources.cache.key("auth", str(scope.user_id), str(scope.session_id), "alive")
        )
        != b"1"
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    async with resources.database.sessions() as session:
        await verify(session, scope, ("client.material.import",))
        upload = await session.scalar(
            select(UploadIntent).where(
                UploadIntent.id == identifier,
                UploadIntent.user_id == scope.user_id,
                UploadIntent.purpose == "primary_document",
            )
        )
        if upload is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        row = await repository.owned(session, scope, MaterialImport, upload.target_resource_id)
        await type_permission(session, scope, row.material_type, "import")
        if row.primary_upload_intent_id != identifier:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        if upload.expires_at <= datetime.now(UTC):
            raise AppError(ErrorCode.RESOURCE_EXPIRED)
        if upload.status != "awaiting_upload" or row.status != "awaiting_upload":
            raise AppError(ErrorCode.STATE_CONFLICT)
        return upload.expected_size_bytes


async def upload_content(
    runtime: Runtime, scope: ScopeContext, identifier: UUID, raw: bytes
) -> None:
    resources = source_resources(runtime)
    if (
        await resources.cache.client.get(
            resources.cache.key("auth", str(scope.user_id), str(scope.session_id), "alive")
        )
        != b"1"
    ):
        raise AppError(ErrorCode.SESSION_INVALID)
    async with resources.database.sessions() as session, session.begin():
        await verify(session, scope, ("client.material.import",), lock=True)
        await capacity(session, scope)
        library = await repository.library(session, scope, lock=True)
        upload = await session.scalar(
            select(UploadIntent).where(
                UploadIntent.id == identifier,
                UploadIntent.user_id == scope.user_id,
                UploadIntent.purpose == "primary_document",
            )
        )
        if upload is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        row = await repository.owned(
            session, scope, MaterialImport, upload.target_resource_id, lock=True
        )
        await type_permission(session, scope, row.material_type, "import")
        upload = await session.get(
            UploadIntent, identifier, with_for_update=True, populate_existing=True
        )
        if (
            upload is None
            or row.library_id != library.id
            or row.primary_upload_intent_id != identifier
        ):
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        if upload.expires_at <= datetime.now(UTC):
            raise AppError(ErrorCode.RESOURCE_EXPIRED)
        if upload.status != "awaiting_upload" or row.status != "awaiting_upload":
            raise AppError(ErrorCode.STATE_CONFLICT)
        if len(raw) != upload.expected_size_bytes or len(raw) > MAX_SOURCE_BYTES:
            raise AppError(ErrorCode.INPUT_INVALID)
        storage = resources.storage
        if storage is None or upload.staging_object_key is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        await storage.put(upload.staging_object_key, raw)
    logger.info("material.upload.staged", extra={"user_id": scope.user_id})


async def complete_upload(
    runtime: Runtime,
    scope: ScopeContext,
    identifier: UUID,
    expected_revision: int,
    operation_id: UUID,
    request_id: UUID,
) -> MaterialImportRead:
    resources = source_resources(runtime)
    async with resources.database.sessions() as session, session.begin():
        await verify(session, scope, ("client.material.import",), lock=True)
        await capacity(session, scope)
        await repository.library(session, scope, lock=True)
        upload = await session.scalar(
            select(UploadIntent).where(
                UploadIntent.id == identifier,
                UploadIntent.user_id == scope.user_id,
                UploadIntent.purpose == "primary_document",
            )
        )
        if upload is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        row = await repository.owned(
            session, scope, MaterialImport, upload.target_resource_id, lock=True
        )
        await type_permission(session, scope, row.material_type, "import")
        upload = await session.get(
            UploadIntent, identifier, with_for_update=True, populate_existing=True
        )
        if upload is None or row.primary_upload_intent_id != upload.id:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        if row.status == "accepted":
            return await read_intent(session, runtime, scope, row)
        now = datetime.now(UTC)
        if row.status not in {"awaiting_upload", "verifying"}:
            raise AppError(ErrorCode.STATE_CONFLICT)
        if row.expires_at <= now:
            raise AppError(ErrorCode.RESOURCE_EXPIRED)
        if row.status == "awaiting_upload" and row.revision != expected_revision:
            raise AppError(ErrorCode.REVISION_CONFLICT)
        if (
            row.status == "verifying"
            and upload.completion_lease_until_at is not None
            and upload.completion_lease_until_at > now
        ):
            raise AppError(ErrorCode.STATE_CONFLICT)
        if len(upload.retired_final_candidates) >= 15:
            raise AppError(ErrorCode.QUOTA_EXCEEDED)
        retire_candidate(upload, now)
        upload.candidate_final_object_key = f"material/final/{scope.user_id}/{uuid4()}"
        upload.completion_generation += 1
        token = uuid4()
        upload.status = row.status = "verifying"
        upload.completion_lease_token = token
        upload.completion_lease_until_at = now + timedelta(seconds=120)
        upload.revision += 1
        row.revision += 1
        row.updated_at = upload.updated_at = now
        staging, final = upload.staging_object_key, upload.candidate_final_object_key
        expected_size, expected_sha, format_code, material_type = (
            upload.expected_size_bytes,
            upload.expected_sha256,
            upload.declared_format,
            row.material_type,
        )
    storage = resources.storage
    if storage is None or staging is None or final is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    try:
        raw = await storage.get_bounded(staging, expected_size)
        if len(raw) != expected_size or hashlib.sha256(raw).digest() != expected_sha:
            raise AppError(ErrorCode.INPUT_INVALID)
        validated = await validate_bounded(raw, format_code, material_type)
        await storage.put(final, raw)
        immutable = await storage.get_bounded(final, expected_size)
        if hashlib.sha256(immutable).digest() != expected_sha:
            raise AppError(ErrorCode.INPUT_INVALID)
    except AppError as error:
        await _reject_upload(runtime, scope, identifier, token, error.code)
        raise
    except Exception:
        # Unknown infrastructure outcomes preserve the claimed candidate for replay.
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None
    async with resources.database.sessions() as session, session.begin():
        await verify(session, scope, ("client.material.import",), lock=True)
        state = await capacity(session, scope)
        reservation = await session.scalar(
            select(UserStorageReservation)
            .where(
                UserStorageReservation.target_resource_id == identifier,
                UserStorageReservation.user_id == scope.user_id,
            )
            .with_for_update()
        )
        library = await repository.library(session, scope, lock=True)
        row = await repository.owned(session, scope, MaterialImport, row.id, lock=True)
        await type_permission(session, scope, row.material_type, "import")
        upload = await session.get(
            UploadIntent, identifier, with_for_update=True, populate_existing=True
        )
        if upload is None or reservation is None or row.library_id != library.id:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        if row.status == "accepted":
            return await read_intent(session, runtime, scope, row)
        now = datetime.now(UTC)
        if (
            upload.completion_lease_token != token
            or upload.status != "verifying"
            or row.status != "verifying"
            or row.expires_at <= now
        ):
            raise AppError(ErrorCode.STATE_CONFLICT)
        if (
            upload.completion_lease_until_at is None
            or upload.completion_lease_until_at <= now
            or reservation.status != "reserved"
        ):
            raise AppError(ErrorCode.STATE_CONFLICT)
        file = FileObject(
            id=uuid4(),
            user_id=scope.user_id,
            upload_intent_id=identifier,
            purpose="primary_document",
            media_type=MEDIA_TYPES[format_code],
            format_code=format_code,
            size_bytes=expected_size,
            sha256=expected_sha,
            validation_profile="material-source-v1",
            processor_version="immutable-source-v1",
            validated_at=now,
            pixel_width=validated.width,
            pixel_height=validated.height,
            retention_state="referenced",
            content=None,
            bucket_name=storage.bucket,
            object_key=final,
        )
        session.add(file)
        upload.status, upload.file_object_id = "completed", file.id
        upload.completion_lease_token = upload.completion_lease_until_at = None
        upload.revision += 1
        upload.updated_at = now
        reservation.status, reservation.committed_bytes = "committed", expected_size
        reservation.revision += 1
        reservation.updated_at = now
        state.reserved_bytes -= reservation.reserved_bytes
        state.used_bytes += expected_size
        state.revision += 1
        state.updated_at = now
        await _accept(session, scope, row, file, operation_id, request_id)
        if row.requested_title is None:
            material = await session.get(Material, row.material_id)
            if material is not None:
                material.title = (upload.original_filename or "未命名材料")[:200]
        await session.flush()
        result = await read_intent(session, runtime, scope, row)
    # Staging cleanup is optional after durable acceptance; final is never exposed.
    try:
        await storage.remove(staging)
    except Exception:
        logger.warning("material.staging.cleanup_pending")
    logger.info(
        "material.source.accepted",
        extra={
            "job_id": result.job_id,
            "user_id": scope.user_id,
            "operation_id": operation_id,
            "request_id": request_id,
        },
    )
    return result


async def _reject_upload(
    runtime: Runtime, scope: ScopeContext, identifier: UUID, token: UUID, code: ErrorCode
) -> None:
    resources = source_resources(runtime)
    async with resources.database.sessions() as session, session.begin():
        # Settlement is owner maintenance and remains safe after permissions change.
        await verify(session, scope, (), lock=True)
        state = await capacity(session, scope)
        reservation = await session.scalar(
            select(UserStorageReservation)
            .where(
                UserStorageReservation.user_id == scope.user_id,
                UserStorageReservation.target_resource_id == identifier,
            )
            .with_for_update()
        )
        await repository.library(session, scope, lock=True)
        upload = await session.get(UploadIntent, identifier)
        if (
            upload is None
            or upload.user_id != scope.user_id
            or upload.purpose != "primary_document"
        ):
            return
        row = await repository.owned(
            session, scope, MaterialImport, upload.target_resource_id, lock=True
        )
        upload = await session.get(
            UploadIntent, identifier, with_for_update=True, populate_existing=True
        )
        if (
            upload is None
            or upload.completion_lease_token != token
            or reservation is None
            or reservation.status != "reserved"
        ):
            return
        row.status = "rejected"
        retire_candidate(upload, datetime.now(UTC))
        upload.status, upload.failure_code = "failed", code.value
        upload.completion_lease_token = upload.completion_lease_until_at = None
        row.revision += 1
        upload.revision += 1
        reservation.status = "released"
        reservation.revision += 1
        state.reserved_bytes -= reservation.reserved_bytes
        state.revision += 1
        for item in (row, upload, reservation, state):
            item.updated_at = datetime.now(UTC)


async def metadata(
    session: AsyncSession, scope: ScopeContext, material: Material
) -> MaterialMetadataRead:
    # This projection contains common metadata only. Exam content remains under
    # its dedicated exam.read contract; catalog listing does not read a paper.
    revision = None
    chapter_id = None
    if material.current_revision_id is not None:
        revision = await session.scalar(
            select(MaterialRevision).where(
                MaterialRevision.id == material.current_revision_id,
                MaterialRevision.owner_user_id == scope.user_id,
                MaterialRevision.library_id == material.library_id,
                MaterialRevision.material_id == material.id,
                MaterialRevision.input_delete_generation == material.delete_generation,
            )
        )
        if (
            revision is not None
            and revision.status == "published"
            and revision.structure_status == "readable"
            and material.material_type == "novel"
        ):
            chapter_id = await session.scalar(
                select(NovelChapter.id)
                .where(
                    NovelChapter.owner_user_id == scope.user_id,
                    NovelChapter.library_id == material.library_id,
                    NovelChapter.material_id == material.id,
                    NovelChapter.material_revision_id == revision.id,
                )
                .order_by(NovelChapter.ordinal)
                .limit(1)
            )
    readable = (
        revision is not None and revision.structure_status == "readable" and chapter_id is not None
    )
    source = await repository.source_revision(session, scope, material)
    return MaterialMetadataRead.model_validate(
        {
            "id": material.id,
            "library_id": material.library_id,
            "material_type": material.material_type,
            "title": material.title,
            "language": material.language,
            "source_format": material.source_format,
            "source_status": "readable"
            if readable
            else "parsing"
            if material.source_status in {"published", "sealed"}
            else material.source_status,
            "analysis_status": material.analysis_status,
            "revision": material.revision,
            "delete_generation": material.delete_generation,
            "revision_id": revision.id
            if revision is not None and revision.status == "published"
            else None,
            "source_revision_number": source.revision_number if source is not None else None,
            "first_chapter_id": chapter_id,
            "job_id": material.initial_job_id,
            "readable": readable,
            "created_at": material.created_at,
            "updated_at": material.updated_at,
        }
    )


async def cancel_import(
    runtime: Runtime, scope: ScopeContext, identifier: UUID, expected: int
) -> None:
    resources = source_resources(runtime)
    async with resources.database.sessions() as session, session.begin():
        await verify(session, scope, ("client.material.import",), lock=True)
        state = await capacity(session, scope)
        initial = await repository.owned(session, scope, MaterialImport, identifier)
        reservation = await session.scalar(
            select(UserStorageReservation)
            .where(
                UserStorageReservation.user_id == scope.user_id,
                UserStorageReservation.target_resource_id == initial.primary_upload_intent_id,
            )
            .with_for_update()
        )
        await repository.library(session, scope, lock=True)
        row = await repository.owned(session, scope, MaterialImport, identifier, lock=True)
        if row.status == "cancelled":
            return
        if row.revision != expected:
            raise AppError(ErrorCode.REVISION_CONFLICT)
        if row.status not in {"awaiting_upload", "verifying"}:
            raise AppError(ErrorCode.STATE_CONFLICT)
        upload = await session.get(UploadIntent, row.primary_upload_intent_id, with_for_update=True)
        if upload is None or reservation is None or reservation.status != "reserved":
            raise AppError(ErrorCode.STATE_CONFLICT)
        row.status = upload.status = "cancelled"
        retire_candidate(upload, datetime.now(UTC))
        upload.completion_generation += 1
        upload.completion_lease_token = upload.completion_lease_until_at = None
        row.revision += 1
        upload.revision += 1
        reservation.status = "released"
        reservation.revision += 1
        state.reserved_bytes -= reservation.reserved_bytes
        state.revision += 1
        for item in (row, upload, reservation, state):
            item.updated_at = datetime.now(UTC)
