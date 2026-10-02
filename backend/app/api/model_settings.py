"""Authorized provider/settings/tests/usage HTTP surfaces and job WebSocket."""

import asyncio
import logging
from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from starlette.requests import Request as StarletteRequest

from app.api.auth_dependencies import require_runtime, require_scope
from app.api.responses import error_responses, get_request_id
from app.api.security_guards import require_authenticated_native_write, require_session_csrf
from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import current_log_context
from app.domain.errors import AppError
from app.models import AuthorizationRevision, User
from app.models.model_tasks import (
    Job,
    JobStage,
    ModelCatalogEntry,
    ModelLimitPolicy,
    ProviderCredential,
    UserRuntimeLimit,
)
from app.schemas.model_settings import (
    AdminJobList,
    AdminJobRead,
    CatalogUpdate,
    CredentialCreate,
    CredentialDelete,
    CredentialImpact,
    CredentialList,
    CredentialRead,
    CredentialRotate,
    CredentialTest,
    JobCancel,
    JobEvent,
    JobList,
    JobRead,
    JobRetry,
    JobSubscription,
    LimitsUpdate,
    ModelCapabilities,
    ModelLimits,
    ModelSettingsRead,
    ModelSettingsUpdate,
    ModelUsage,
    TestAccepted,
    TestResult,
    UserLimitDelete,
    UserLimitList,
    UserLimitRead,
    UserLimitUpdate,
)
from app.schemas.responses import ApiModel, ResponseMeta, SuccessResponse
from app.services import model_configuration as config
from app.services import model_tasks as tasks
from app.services.governance_security import verify_admin_write

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["model-settings"])
COMMON = error_responses(400, 401, 403, 404, 409, 422, 429, 500, 503)


async def context(
    request: Request, codes: tuple[str, ...], *, write: bool = False, admin: bool = False
):
    runtime = require_runtime(request)
    scope = await require_scope(request, audience="admin" if admin else "client", permissions=codes)
    if write:
        if scope.transport == "web":
            await require_session_csrf(request, runtime, scope)
        else:
            require_authenticated_native_write(request)
    return runtime, scope


def response[T: ApiModel](request: Request, value: T) -> SuccessResponse[T]:
    return SuccessResponse[T](data=value, meta=ResponseMeta(request_id=get_request_id(request)))


def resources(runtime: Runtime) -> Resources:
    if runtime.resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return runtime.resources


@router.get(
    "/provider-credentials",
    response_model=SuccessResponse[CredentialList],
    responses=COMMON,
    operation_id="list_provider_credentials",
    openapi_extra={"x-haruka-permissions": ["client.credential.read"]},
)
async def credentials(request: Request):
    runtime, scope = await context(request, ("client.credential.read",))
    async with resources(runtime).database.sessions() as session:
        items = await session.scalars(
            select(ProviderCredential)
            .where(ProviderCredential.owner_user_id == scope.user_id)
            .order_by(
                (ProviderCredential.status == "active").desc(),
                ProviderCredential.created_at.desc(),
                ProviderCredential.id,
            )
            .limit(100)
        )
        return response(
            request, CredentialList(items=[config.credential_read(row) for row in items])
        )


@router.post(
    "/provider-credentials",
    response_model=SuccessResponse[CredentialRead],
    status_code=201,
    responses=COMMON,
    operation_id="create_provider_credential",
    openapi_extra={"x-haruka-permissions": ["client.credential.manage"]},
)
async def create_credential(request: Request, payload: CredentialCreate):
    runtime, scope = await context(request, ("client.credential.manage",), write=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await config.add_credential(session, runtime, scope, payload)
    logger.info("credential.created", extra=current_log_context())
    return response(request, result)


@router.patch(
    "/provider-credentials/{credential_id}",
    response_model=SuccessResponse[CredentialRead],
    responses=COMMON,
    operation_id="rotate_provider_credential",
    openapi_extra={"x-haruka-permissions": ["client.credential.manage"]},
)
async def rotate(request: Request, credential_id: UUID, payload: CredentialRotate):
    runtime, scope = await context(request, ("client.credential.manage",), write=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await config.rotate_credential(session, runtime, scope, credential_id, payload)
    logger.info("credential.rotated", extra=current_log_context())
    return response(request, result)


@router.delete(
    "/provider-credentials/{credential_id}",
    response_model=SuccessResponse[CredentialRead],
    responses=COMMON,
    operation_id="delete_provider_credential",
    openapi_extra={"x-haruka-permissions": ["client.credential.manage"]},
)
async def revoke(request: Request, credential_id: UUID, payload: CredentialDelete):
    runtime, scope = await context(request, ("client.credential.manage",), write=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await config.delete_credential(
            session, scope, credential_id, payload.expected_revision
        )
    logger.info("credential.deleted", extra=current_log_context())
    return response(request, result)


@router.get(
    "/provider-credentials/{credential_id}/deletion-impact",
    response_model=SuccessResponse[CredentialImpact],
    responses=COMMON,
    operation_id="get_credential_deletion_impact",
    openapi_extra={"x-haruka-permissions": ["client.credential.read"]},
)
async def impact(request: Request, credential_id: UUID):
    runtime, scope = await context(request, ("client.credential.read",))
    async with resources(runtime).database.sessions() as session:
        return response(request, await config.deletion_impact(session, scope, credential_id))


@router.post(
    "/provider-credentials/{credential_id}/test",
    response_model=SuccessResponse[TestAccepted],
    status_code=202,
    responses=COMMON,
    operation_id="test_provider_credential",
    openapi_extra={"x-haruka-permissions": ["client.credential.read", "client.credential.test"]},
)
async def test(request: Request, credential_id: UUID, payload: CredentialTest):
    runtime, scope = await context(
        request, ("client.credential.read", "client.credential.test"), write=True
    )
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await tasks.accept_test(
            session,
            runtime,
            scope,
            credential_id,
            payload,
            request.headers.get("idempotency-key", ""),
        )
    return response(request, result)


@router.get(
    "/provider-credentials/{credential_id}/tests/{run_id}",
    response_model=SuccessResponse[TestResult],
    responses=COMMON,
    operation_id="get_credential_test_result",
    openapi_extra={"x-haruka-permissions": ["client.credential.read"]},
)
async def test_result(request: Request, credential_id: UUID, run_id: UUID):
    runtime, scope = await context(request, ("client.credential.read",))
    async with resources(runtime).database.sessions() as session:
        return response(request, await tasks.test_result(session, scope, credential_id, run_id))


@router.get(
    "/model-capabilities",
    response_model=SuccessResponse[ModelCapabilities],
    responses=COMMON,
    operation_id="get_model_capabilities",
    openapi_extra={"x-haruka-permissions": []},
)
async def capabilities(request: Request):
    runtime, _scope = await context(request, ())
    async with resources(runtime).database.sessions() as session:
        return response(request, await config.capabilities(session))


@router.get(
    "/users/me/model-settings",
    response_model=SuccessResponse[ModelSettingsRead],
    responses=COMMON,
    operation_id="get_my_model_settings",
    openapi_extra={"x-haruka-permissions": ["client.profile.read"]},
)
async def model_settings(request: Request):
    runtime, scope = await context(request, ("client.profile.read",))
    async with resources(runtime).database.sessions() as session:
        return response(request, await config.read_model_settings(session, scope))


@router.patch(
    "/users/me/model-settings",
    response_model=SuccessResponse[ModelSettingsRead],
    responses=COMMON,
    operation_id="update_my_model_settings",
    openapi_extra={"x-haruka-permissions": ["client.profile.read", "client.profile.update"]},
)
async def save_settings(request: Request, payload: ModelSettingsUpdate):
    runtime, scope = await context(
        request, ("client.profile.read", "client.profile.update"), write=True
    )
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await config.update_model_settings(session, scope, payload)
    return response(request, result)


@router.get(
    "/users/me/model-usage",
    response_model=SuccessResponse[ModelUsage],
    responses=COMMON,
    operation_id="get_my_model_usage",
    openapi_extra={"x-haruka-permissions": ["client.credential.read"]},
)
async def usage(
    request: Request,
    since: datetime | None = None,
    until: datetime | None = None,
    provider: str | None = None,
    model_id: str | None = None,
    capability: str | None = None,
    operation_kind: str | None = None,
):
    runtime, scope = await context(request, ("client.credential.read",))
    async with resources(runtime).database.sessions() as session:
        return response(
            request,
            await tasks.usage_projection(
                session,
                scope.user_id,
                since=since,
                until=until,
                provider=provider,
                model_id=model_id,
                capability=capability,
                operation_kind=operation_kind,
            ),
        )


@router.get(
    "/jobs",
    response_model=SuccessResponse[JobList],
    responses=COMMON,
    operation_id="list_my_jobs",
    openapi_extra={"x-haruka-permissions": ["client.job.read", "client.credential.read"]},
)
async def jobs(request: Request):
    runtime, scope = await context(request, ("client.job.read", "client.credential.read"))
    async with resources(runtime).database.sessions() as session:
        rows = await session.scalars(
            select(Job)
            .where(Job.owner_user_id == scope.user_id)
            .order_by(Job.created_at.desc())
            .limit(100)
        )
        return response(request, JobList(items=[tasks.snapshot(job) for job in rows]))


@router.get(
    "/jobs/{job_id}",
    response_model=SuccessResponse[JobRead],
    responses=COMMON,
    operation_id="get_my_job",
    openapi_extra={"x-haruka-permissions": ["client.job.read", "client.credential.read"]},
)
async def job(request: Request, job_id: UUID):
    runtime, scope = await context(request, ("client.job.read", "client.credential.read"))
    async with resources(runtime).database.sessions() as session:
        return response(request, await tasks.read_job(session, scope, job_id))


@router.post(
    "/jobs/{job_id}/cancel",
    response_model=SuccessResponse[JobRead],
    responses=COMMON,
    operation_id="cancel_my_job",
    openapi_extra={"x-haruka-permissions": ["client.job.cancel", "client.credential.read"]},
)
async def cancel(request: Request, job_id: UUID, payload: JobCancel):
    runtime, scope = await context(
        request, ("client.job.cancel", "client.credential.read"), write=True
    )
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await tasks.change_job(
            session, scope, job_id, payload.expected_revision, retry=False
        )
    return response(request, result)


@router.post(
    "/jobs/{job_id}/retry",
    response_model=SuccessResponse[JobRead],
    responses=COMMON,
    operation_id="retry_my_job",
    openapi_extra={
        "x-haruka-permissions": [
            "client.job.retry",
            "client.credential.read",
            "client.credential.test",
        ]
    },
)
async def retry(request: Request, job_id: UUID, payload: JobRetry):
    runtime, scope = await context(
        request,
        ("client.job.retry", "client.credential.read", "client.credential.test"),
        write=True,
    )
    async with resources(runtime).database.sessions() as session, session.begin():
        result = await tasks.change_job(
            session,
            scope,
            job_id,
            payload.expected_revision,
            retry=True,
            confirm_new_attempt=payload.confirm_new_attempt,
            credential_id=payload.credential_id,
        )
    return response(request, result)


@router.websocket("/jobs/events")
async def events(socket: WebSocket):
    runtime: Runtime | None = getattr(socket.app.state, "runtime", None)
    if runtime is None or not runtime.ready:
        await socket.close(code=1013)
        return
    browser = "haruka_client_session" in socket.cookies
    if browser and socket.headers.get("origin") not in runtime.settings.allowed_origins:
        await socket.close(code=1008)
        return
    # Use the same current-session transport parser. WS has no custom browser
    # headers: bind expected session from trusted authentication after handshake.
    request_scope = dict(socket.scope)
    request_scope.update(type="http", method="GET", path="/api/v1/me/access")
    request = StarletteRequest(request_scope)
    subscriptions: dict[UUID, tuple[int, int]] = {}

    async def identity():
        return await require_scope(
            request, audience="client", permissions=("client.job.read", "client.credential.read")
        )

    try:
        await identity()
        await socket.accept()
        while True:
            try:
                message = JobSubscription.model_validate(
                    await asyncio.wait_for(socket.receive_json(), timeout=2)
                )
                requested = message.job_ids
                if message.type == "unsubscribe":
                    for identifier in requested:
                        subscriptions.pop(identifier, None)
                else:
                    scope = await identity()
                    async with resources(runtime).database.sessions() as session:
                        limits = await config.effective_limits(session)
                        if len(set(subscriptions) | set(requested)) > limits.websocket_max_jobs:
                            raise AppError(ErrorCode.QUOTA_EXCEEDED)
                        # Whole subscription authorization before delivering any.
                        for identifier in requested:
                            await tasks.load_job(session, scope.user_id, identifier)
                    subscriptions.update({identifier: (-1, -1) for identifier in requested})
            except TimeoutError:
                pass
            for identifier, cursor in list(subscriptions.items()):
                scope = await identity()
                async with resources(runtime).database.sessions() as session:
                    value = await tasks.read_job(session, scope, identifier)
                if (value.generation, value.sequence) != cursor:
                    kind = (
                        "snapshot"
                        if cursor == (-1, -1)
                        else "completed"
                        if value.state == "succeeded"
                        else "failed"
                        if value.state == "failed"
                        else "cancelled"
                        if value.state == "cancelled"
                        else "progress"
                    )
                    await socket.send_json(
                        JobEvent(
                            event_id=uuid4(),
                            job_id=identifier,
                            generation=value.generation,
                            sequence=value.sequence,
                            type=kind,
                            occurred_at=datetime.now(UTC),
                            payload=value,
                        ).model_dump(mode="json")
                    )
                    subscriptions[identifier] = (value.generation, value.sequence)
            await identity()
    except AppError as error:
        await socket.close(code=1013 if error.code == ErrorCode.SERVICE_UNAVAILABLE else 1008)
    except (ValueError, TypeError):
        await socket.close(code=1008)
    except WebSocketDisconnect:
        return


@router.get(
    "/admin/model-catalog",
    response_model=SuccessResponse[ModelCapabilities],
    responses=COMMON,
    operation_id="get_admin_model_catalog",
    openapi_extra={"x-haruka-permissions": ["admin.model_catalog.read"]},
)
async def admin_catalog(request: Request):
    runtime, _scope = await context(request, ("admin.model_catalog.read",), admin=True)
    async with resources(runtime).database.sessions() as session:
        return response(request, await config.capabilities(session))


@router.patch(
    "/admin/model-catalog/{model_id}",
    response_model=SuccessResponse[ModelCapabilities],
    responses=COMMON,
    operation_id="update_admin_model_catalog",
    openapi_extra={"x-haruka-permissions": ["admin.model_catalog.update"]},
)
async def admin_catalog_update(request: Request, model_id: UUID, payload: CatalogUpdate):
    runtime, scope = await context(request, ("admin.model_catalog.update",), write=True, admin=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        await tasks.lock_policy(session)
        await verify_admin_write(session, scope)
        row = await session.scalar(
            select(ModelCatalogEntry).where(ModelCatalogEntry.id == model_id).with_for_update()
        )
        if row is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        config.require_revision(row.revision, payload.expected_revision)
        if payload.enabled and row.provider == "gemini":
            raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
        row.enabled = payload.enabled
        row.revision += 1
        row.updated_at = datetime.now(UTC)
        root = await session.scalar(
            select(AuthorizationRevision)
            .where(AuthorizationRevision.code == "global")
            .with_for_update()
        )
        if root is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        root.revision += 1
        await config.audit(session, scope, "model_catalog.updated", row.id)
        result = await config.capabilities(session)
    return response(request, result)


@router.get(
    "/admin/model-limits",
    response_model=SuccessResponse[ModelLimits],
    responses=COMMON,
    operation_id="get_admin_model_limits",
    openapi_extra={"x-haruka-permissions": ["admin.quota.read"]},
)
async def admin_limits(request: Request):
    runtime, _scope = await context(request, ("admin.quota.read",), admin=True)
    async with resources(runtime).database.sessions() as session:
        return response(request, await config.effective_limits(session))


@router.patch(
    "/admin/model-limits",
    response_model=SuccessResponse[ModelLimits],
    responses=COMMON,
    operation_id="update_admin_model_limits",
    openapi_extra={"x-haruka-permissions": ["admin.quota.update"]},
)
async def admin_limits_update(request: Request, payload: LimitsUpdate):
    runtime, scope = await context(request, ("admin.quota.update",), write=True, admin=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        await tasks.lock_policy(session)
        await verify_admin_write(session, scope)
        rows = list(
            await session.scalars(
                select(ModelLimitPolicy).order_by(ModelLimitPolicy.id).with_for_update()
            )
        )
        old = await config.effective_limits(session)
        config.require_revision(old.revision, payload.expected_revision)
        values = payload.limits.model_dump()
        for row in rows:
            if row.limit_code in values:
                row.value_limit = int(values[row.limit_code])
            row.enabled = payload.limits.enabled
            row.revision = old.revision + 1
            row.updated_at = datetime.now(UTC)
        if rows:
            await config.audit(session, scope, "model_limits.updated", rows[0].id)
        result = await config.effective_limits(session)
    return response(request, result)


@router.get(
    "/admin/user-model-limits",
    response_model=SuccessResponse[UserLimitList],
    responses=COMMON,
    operation_id="list_admin_user_model_limits",
    openapi_extra={"x-haruka-permissions": ["admin.quota.read"]},
)
async def user_limits(request: Request):
    runtime, _scope = await context(request, ("admin.quota.read",), admin=True)
    async with resources(runtime).database.sessions() as session:
        rows = await session.scalars(
            select(UserRuntimeLimit).order_by(UserRuntimeLimit.id).limit(100)
        )
        return response(
            request,
            UserLimitList(
                items=[
                    UserLimitRead(
                        user_id=row.owner_user_id,
                        revision=row.revision,
                        max_concurrent_jobs=row.value_limit,
                    )
                    for row in rows
                ]
            ),
        )


@router.patch(
    "/admin/user-model-limits/{user_id}",
    response_model=SuccessResponse[UserLimitRead],
    responses=COMMON,
    operation_id="update_admin_user_model_limit",
    openapi_extra={"x-haruka-permissions": ["admin.quota.update"]},
)
async def user_limit_update(request: Request, user_id: UUID, payload: UserLimitUpdate):
    runtime, scope = await context(request, ("admin.quota.update",), write=True, admin=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        await tasks.lock_policy(session)
        await verify_admin_write(session, scope)
        user = await session.scalar(select(User).where(User.id == user_id).with_for_update())
        if user is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        row = await session.scalar(
            select(UserRuntimeLimit)
            .where(UserRuntimeLimit.owner_user_id == user_id)
            .with_for_update()
        )
        config.require_revision(row.revision if row else 0, payload.expected_revision)
        if row is None:
            row = UserRuntimeLimit(
                owner_user_id=user_id,
                limit_code="max_concurrent_jobs",
                value_limit=payload.max_concurrent_jobs,
                revision=1,
            )
            session.add(row)
        else:
            row.value_limit = payload.max_concurrent_jobs
            row.revision += 1
        await session.flush()
        await config.audit(session, scope, "model_limits.updated", row.id)
        result = UserLimitRead(
            user_id=user_id, revision=row.revision, max_concurrent_jobs=row.value_limit
        )
    return response(request, result)


@router.delete(
    "/admin/user-model-limits/{user_id}",
    response_model=SuccessResponse[UserLimitList],
    responses=COMMON,
    operation_id="delete_admin_user_model_limit",
    openapi_extra={"x-haruka-permissions": ["admin.quota.update"]},
)
async def user_limit_delete(request: Request, user_id: UUID, payload: UserLimitDelete):
    runtime, scope = await context(request, ("admin.quota.update",), write=True, admin=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        await tasks.lock_policy(session)
        await verify_admin_write(session, scope)
        row = await session.scalar(
            select(UserRuntimeLimit)
            .where(UserRuntimeLimit.owner_user_id == user_id)
            .with_for_update()
        )
        if row is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        config.require_revision(row.revision, payload.expected_revision)
        await config.audit(session, scope, "model_limits.updated", row.id)
        await session.delete(row)
    return response(request, UserLimitList(items=[]))


def admin_snapshot(job: Job) -> AdminJobRead:
    return AdminJobRead(
        id=job.id,
        operation_kind=job.operation_kind,
        state=job.state,
        revision=job.revision,
        generation=job.generation,
        sequence=job.progress_seq,
        error_code=job.error_code,
        can_cancel=job.state in tasks.ACTIVE,
        can_retry=job.state == "blocked",
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


@router.get(
    "/admin/jobs",
    response_model=SuccessResponse[AdminJobList],
    responses=COMMON,
    operation_id="list_admin_jobs",
    openapi_extra={"x-haruka-permissions": ["admin.job.read"]},
)
async def admin_jobs(request: Request):
    runtime, _scope = await context(request, ("admin.job.read",), admin=True)
    async with resources(runtime).database.sessions() as session:
        rows = await session.scalars(select(Job).order_by(Job.created_at.desc()).limit(100))
        return response(request, AdminJobList(items=[admin_snapshot(job) for job in rows]))


@router.get(
    "/admin/model-usage",
    response_model=SuccessResponse[ModelUsage],
    responses=COMMON,
    operation_id="get_admin_model_usage",
    openapi_extra={"x-haruka-permissions": ["admin.dashboard.view"]},
)
async def admin_usage(
    request: Request,
    since: datetime | None = None,
    until: datetime | None = None,
    provider: str | None = None,
    model_id: str | None = None,
    capability: str | None = None,
    operation_kind: str | None = None,
):
    runtime, _scope = await context(request, ("admin.dashboard.view",), admin=True)
    async with resources(runtime).database.sessions() as session:
        return response(
            request,
            await tasks.usage_projection(
                session,
                None,
                since=since,
                until=until,
                provider=provider,
                model_id=model_id,
                capability=capability,
                operation_kind=operation_kind,
            ),
        )


async def admin_job_action(
    request: Request, job_id: UUID, revision: int, *, retry: bool
) -> AdminJobRead:
    code = "admin.job.retry" if retry else "admin.job.cancel"
    runtime, scope = await context(request, (code,), write=True, admin=True)
    async with resources(runtime).database.sessions() as session, session.begin():
        await tasks.lock_policy(session)
        await verify_admin_write(session, scope)
        await tasks.lock_job_owner(session, job_id)
        row = await session.scalar(select(Job).where(Job.id == job_id).with_for_update())
        if row is None:
            raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
        config.require_revision(row.revision, revision)
        if retry:
            stage = await session.scalar(
                select(JobStage).where(
                    JobStage.job_id == job_id, JobStage.job_generation == row.generation
                )
            )
            if (
                row.state != "blocked"
                or stage is None
                or stage.state != "committed"
                or not stage.result_refs
            ):
                raise AppError(ErrorCode.STATE_CONFLICT)
            row.state = "queued"
        else:
            if row.state not in tasks.ACTIVE:
                raise AppError(ErrorCode.STATE_CONFLICT)
            row.state = "cancel_requested" if row.state == "running" else "cancelled"
        row.revision += 1
        row.progress_seq += 1
        row.updated_at = datetime.now(UTC)
        await tasks.emit(session, row, "model.job.accepted" if retry else "model.job.updated")
        await config.audit(
            session, scope, "model_job.retried" if retry else "model_job.cancelled", row.id
        )
        return admin_snapshot(row)


@router.post(
    "/admin/jobs/{job_id}/cancel",
    response_model=SuccessResponse[AdminJobRead],
    responses=COMMON,
    operation_id="cancel_admin_job",
    openapi_extra={"x-haruka-permissions": ["admin.job.cancel"]},
)
async def admin_cancel(request: Request, job_id: UUID, payload: JobCancel):
    return response(
        request, await admin_job_action(request, job_id, payload.expected_revision, retry=False)
    )


@router.post(
    "/admin/jobs/{job_id}/retry",
    response_model=SuccessResponse[AdminJobRead],
    responses=COMMON,
    operation_id="retry_admin_job",
    openapi_extra={"x-haruka-permissions": ["admin.job.retry"]},
)
async def admin_retry(request: Request, job_id: UUID, payload: JobCancel):
    return response(
        request, await admin_job_action(request, job_id, payload.expected_revision, retry=True)
    )
