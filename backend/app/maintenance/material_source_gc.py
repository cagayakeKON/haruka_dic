"""Bounded owner-locked source expiry and final object retirement."""

from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, exists, or_, select
from sqlalchemy.orm import aliased

from app.bootstrap import Runtime
from app.models import FileObject, UploadIntent, UserStorageReservation, UserStorageState
from app.models.identity import Library, User
from app.models.learning_reference import Material, SourceResultBinding
from app.models.material_imports import MaterialImport
from app.services.material_imports import retire_candidate


async def collect_source_garbage(runtime: Runtime, *, limit: int = 20) -> tuple[int, int]:
    resources = runtime.resources
    if resources is None or resources.storage is None:
        return 0, 0
    now = datetime.now(UTC)
    active, dead, retained = aliased(Material), aliased(Material), aliased(Material)
    no_active = ~exists(
        select(active.id).where(
            active.primary_file_object_id == UploadIntent.file_object_id,
            active.owner_user_id == UploadIntent.user_id,
            active.deleted_at.is_(None),
        )
    )
    has_dead = exists(
        select(dead.id).where(
            dead.primary_file_object_id == UploadIntent.file_object_id,
            dead.owner_user_id == UploadIntent.user_id,
            dead.deleted_at.is_not(None),
        )
    )
    no_binding = ~exists(
        select(SourceResultBinding.id)
        .join(retained, retained.id == SourceResultBinding.source_resource_id)
        .where(
            retained.primary_file_object_id == UploadIntent.file_object_id,
            retained.owner_user_id == UploadIntent.user_id,
            SourceResultBinding.owner_user_id == UploadIntent.user_id,
            SourceResultBinding.released_at.is_(None),
        )
    )
    async with resources.database.sessions() as session:
        candidates = list(
            (
                await session.execute(
                    select(UploadIntent.id, UploadIntent.user_id)
                    .join(
                        UserStorageReservation,
                        UserStorageReservation.id == UploadIntent.storage_reservation_id,
                    )
                    .where(
                        UploadIntent.purpose == "primary_document",
                        UserStorageReservation.user_id == UploadIntent.user_id,
                        or_(
                            and_(
                                UploadIntent.retired_final_candidates != [],
                                UploadIntent.candidate_cleanup_due_at <= now,
                            ),
                            and_(
                                UserStorageReservation.status == "reserved",
                                UploadIntent.expires_at <= now,
                            ),
                            and_(
                                UserStorageReservation.status == "released",
                                UploadIntent.status.in_(("cancelled", "failed", "expired")),
                                UploadIntent.expires_at <= now - timedelta(minutes=10),
                                or_(
                                    UploadIntent.failure_code.is_(None),
                                    UploadIntent.failure_code != "SOURCE_CLEANUP_COMPLETE",
                                ),
                            ),
                            and_(
                                UserStorageReservation.status == "committed",
                                no_active,
                                has_dead,
                                no_binding,
                            ),
                        ),
                    )
                    .order_by(
                        UploadIntent.candidate_cleanup_due_at.asc().nulls_last(),
                        UploadIntent.expires_at,
                        UploadIntent.id,
                    )
                    .limit(limit)
                )
            ).all()
        )
    expired = retired = 0
    for identifier, owner in candidates:
        async with resources.database.sessions() as session, session.begin():
            await session.scalar(select(User).where(User.id == owner).with_for_update())
            state = await session.scalar(
                select(UserStorageState).where(UserStorageState.user_id == owner).with_for_update()
            )
            reservation = await session.scalar(
                select(UserStorageReservation)
                .where(
                    UserStorageReservation.user_id == owner,
                    UserStorageReservation.target_resource_id == identifier,
                )
                .with_for_update()
            )
            library = await session.scalar(
                select(Library).where(Library.owner_user_id == owner).with_for_update()
            )
            if state is None or reservation is None or library is None:
                continue
            row = await session.scalar(
                select(MaterialImport)
                .where(
                    MaterialImport.primary_upload_intent_id == identifier,
                    MaterialImport.owner_user_id == owner,
                    MaterialImport.library_id == library.id,
                )
                .with_for_update()
            )
            if row is None:
                continue
            # These common roots serialize every source reference and deletion.
            upload = await session.scalar(
                select(UploadIntent)
                .where(
                    UploadIntent.id == identifier,
                    UploadIntent.user_id == owner,
                    UploadIntent.purpose == "primary_document",
                )
                .with_for_update()
            )
            if upload is None:
                continue
            if (
                row.status in {"awaiting_upload", "verifying"}
                and row.expires_at <= now
                and reservation.status == "reserved"
            ):
                row.status = upload.status = "expired"
                retire_candidate(upload, now)
                upload.completion_lease_token = upload.completion_lease_until_at = None
                row.revision += 1
                upload.revision += 1
                reservation.status = "released"
                reservation.revision += 1
                state.reserved_bytes -= reservation.reserved_bytes
                state.revision += 1
                for item in (row, upload, reservation, state):
                    item.updated_at = now
                expired += 1
            if (
                upload.retired_final_candidates
                and upload.candidate_cleanup_due_at is not None
                and upload.candidate_cleanup_due_at <= now
            ):
                # Keep retired keys discoverable even if a previously paused SDK
                # writer recreates an orphan after an earlier remove succeeded.
                published = await session.scalar(
                    select(FileObject.object_key).where(
                        FileObject.user_id == owner,
                        FileObject.upload_intent_id == identifier,
                        FileObject.purpose == "primary_document",
                        FileObject.retention_state == "referenced",
                        FileObject.bucket_name == resources.storage.bucket,
                    )
                )
                for key in upload.retired_final_candidates:
                    suffix = key.removeprefix(f"material/final/{owner}/")
                    from uuid import UUID

                    try:
                        valid = str(UUID(suffix)) == suffix and key != suffix
                    except (ValueError, TypeError):
                        valid = False
                    if not valid or key == published:
                        continue
                    await resources.storage.remove(key)
                upload.candidate_cleanup_due_at = now + timedelta(minutes=5)
                upload.updated_at = now
            if (
                row.status in {"cancelled", "rejected", "expired"}
                and row.expires_at + timedelta(minutes=10) <= now
            ):
                for key in (upload.staging_object_key,):
                    if key is not None:
                        await resources.storage.remove(key)
                upload.failure_code = "SOURCE_CLEANUP_COMPLETE"
                upload.updated_at = now
            if reservation.status != "committed" or upload.file_object_id is None:
                continue
            file = await session.scalar(
                select(FileObject)
                .where(
                    FileObject.id == upload.file_object_id,
                    FileObject.user_id == owner,
                    FileObject.purpose == "primary_document",
                )
                .with_for_update()
            )
            if file is None or file.bucket_name != resources.storage.bucket or not file.object_key:
                continue
            alive = await session.scalar(
                select(Material.id)
                .where(
                    Material.owner_user_id == owner,
                    Material.library_id == library.id,
                    Material.primary_file_object_id == file.id,
                    Material.deleted_at.is_(None),
                )
                .limit(1)
            )
            binding = await session.scalar(
                select(SourceResultBinding.id)
                .join(Material, Material.id == SourceResultBinding.source_resource_id)
                .where(
                    Material.owner_user_id == owner,
                    Material.library_id == library.id,
                    Material.primary_file_object_id == file.id,
                    SourceResultBinding.owner_user_id == owner,
                    SourceResultBinding.released_at.is_(None),
                )
                .limit(1)
            )
            if alive is not None or binding is not None:
                continue
            await resources.storage.remove(file.object_key)
            file.retention_state, file.gc_not_before_at, file.updated_at = "gc_pending", now, now
            state.used_bytes -= reservation.committed_bytes
            state.revision += 1
            state.updated_at = now
            reservation.status, reservation.committed_bytes = "released", 0
            reservation.revision += 1
            reservation.updated_at = now
            retired += 1
    return expired, retired
