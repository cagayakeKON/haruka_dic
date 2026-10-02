"""Owner-scoped source parents and stable metadata catalog queries."""

from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.avatar import FileObject
from app.models.identity import Library
from app.models.learning_reference import Material, MaterialRevision
from app.models.material_imports import MaterialImport, MaterialSourceAsset
from app.models.model_tasks import Job


async def library(session: AsyncSession, scope: ScopeContext, *, lock: bool = False) -> Library:
    query = select(Library).where(Library.owner_user_id == scope.user_id)
    result = await session.scalar(query.with_for_update() if lock else query)
    if result is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return result


async def owned[T: Material | MaterialImport](
    session: AsyncSession,
    scope: ScopeContext,
    model: type[T],
    identifier: UUID,
    *,
    lock: bool = False,
) -> T:
    query = select(model).where(model.id == identifier, model.owner_user_id == scope.user_id)
    result = await session.scalar(
        query.with_for_update().execution_options(populate_existing=True) if lock else query
    )
    if result is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    if isinstance(result, Material) and result.deleted_at is not None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return result


async def material_page(
    session: AsyncSession,
    scope: ScopeContext,
    *,
    limit: int,
    cursor: UUID | None,
    material_type: str | None,
    language: str | None,
    search: str | None,
) -> list[Material]:
    query = (
        select(Material)
        .join(Library, Library.id == Material.library_id)
        .where(
            Material.owner_user_id == scope.user_id,
            Library.owner_user_id == scope.user_id,
            Material.deleted_at.is_(None),
        )
    )
    if material_type is not None:
        query = query.where(Material.material_type == material_type)
    if language is not None:
        query = query.where(Material.language == language)
    if search:
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        query = query.where(Material.title.ilike("%" + escaped + "%", escape="\\"))
    if cursor is not None:
        # A retained tombstone still anchors ordering after a concurrent delete;
        # only the owner's immutable ordering fields participate in pagination.
        anchor = await session.scalar(
            select(Material)
            .join(Library, Library.id == Material.library_id)
            .where(
                Material.id == cursor,
                Material.owner_user_id == scope.user_id,
                Library.owner_user_id == scope.user_id,
            )
        )
        if anchor is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        query = query.where(
            or_(
                Material.created_at < anchor.created_at,
                (Material.created_at == anchor.created_at) & (Material.id < anchor.id),
            )
        )
    return list(
        await session.scalars(
            query.order_by(Material.created_at.desc(), Material.id.desc()).limit(limit + 1)
        )
    )


async def source_revision(
    session: AsyncSession, scope: ScopeContext, material: Material
) -> MaterialRevision | None:
    """Resolve the owned source version; metadata CAS is never a source version."""
    library_row = await library(session, scope)
    if material.owner_user_id != scope.user_id or material.library_id != library_row.id:
        return None
    if material.current_revision_id is not None:
        current = await session.scalar(
            select(MaterialRevision).where(
                MaterialRevision.id == material.current_revision_id,
                MaterialRevision.owner_user_id == scope.user_id,
                MaterialRevision.library_id == library_row.id,
                MaterialRevision.material_id == material.id,
                MaterialRevision.material_type == material.material_type,
                MaterialRevision.input_delete_generation == material.delete_generation,
                MaterialRevision.status.in_(("published", "sealed")),
            )
        )
        if current is not None:
            return current
    if material.initial_job_id is None or material.primary_file_object_id is None:
        return None
    job = await session.scalar(
        select(Job).where(
            Job.id == material.initial_job_id,
            Job.owner_user_id == scope.user_id,
            Job.actor_user_id == scope.user_id,
            Job.operation_kind == "material_import",
        )
    )
    if job is None or job.input_refs.get("delete_generation") != material.delete_generation:
        return None
    try:
        candidate_id = UUID(str(job.input_refs["material_revision_id"]))
        material_id = UUID(str(job.input_refs["material_id"]))
        file_id = UUID(str(job.input_refs["file_object_id"]))
        import_id = UUID(str(job.input_refs["import_id"]))
    except (KeyError, ValueError):
        return None
    if material_id != material.id or file_id != material.primary_file_object_id:
        return None
    return await session.scalar(
        select(MaterialRevision)
        .join(MaterialSourceAsset, MaterialSourceAsset.material_revision_id == MaterialRevision.id)
        .join(FileObject, FileObject.id == MaterialSourceAsset.file_object_id)
        .join(MaterialImport, MaterialImport.id == import_id)
        .where(
            MaterialRevision.id == candidate_id,
            MaterialRevision.owner_user_id == scope.user_id,
            MaterialRevision.library_id == library_row.id,
            MaterialRevision.material_id == material.id,
            MaterialRevision.material_type == material.material_type,
            MaterialRevision.origin_job_id == job.id,
            MaterialRevision.input_delete_generation == material.delete_generation,
            MaterialSourceAsset.owner_user_id == scope.user_id,
            MaterialSourceAsset.library_id == library_row.id,
            MaterialSourceAsset.material_id == material.id,
            MaterialSourceAsset.file_object_id == file_id,
            MaterialSourceAsset.purpose == "primary_document",
            MaterialSourceAsset.ordinal == 1,
            FileObject.user_id == scope.user_id,
            FileObject.purpose == "primary_document",
            FileObject.retention_state == "referenced",
            FileObject.sha256 == job.input_digest,
            MaterialImport.owner_user_id == scope.user_id,
            MaterialImport.library_id == library_row.id,
            MaterialImport.material_id == material.id,
            MaterialImport.initial_job_id == job.id,
            MaterialImport.material_type == material.material_type,
            MaterialImport.status == "accepted",
        )
    )
