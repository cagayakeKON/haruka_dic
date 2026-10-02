"""Transactional model-test acceptance, fenced stages and attempt-based usage."""

import asyncio
import hashlib
import json
import logging
import re
from datetime import UTC, datetime, timedelta
from typing import Literal, cast
from uuid import UUID, uuid4

from pydantic_ai.exceptions import UnexpectedModelBehavior, UsageLimitExceeded
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.models import ProviderFailure, execute_probe, http_error_code, test_image
from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.correlation import (
    ai_run_id_context,
    audience_context,
    current_correlation,
    current_log_context,
    job_id_context,
    operation_id_context,
    request_id_context,
    user_id_context,
)
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import OutboxEvent
from app.models.model_tasks import (
    AiRun,
    ExternalCallAttempt,
    InboxEvent,
    Job,
    JobStage,
    ModelLimitPolicy,
    UserRuntimeLimit,
)
from app.schemas.model_settings import (
    Capability,
    CredentialTest,
    JobRead,
    ModelLimits,
    ModelUsage,
    Provider,
    TestAccepted,
    TestResult,
    UsageGroup,
    UsageMetric,
)
from app.services import model_configuration as configuration
from app.services.credential_crypto import CredentialCrypto

logger = logging.getLogger(__name__)
TERMINAL = ("succeeded", "failed", "cancelled")
ACTIVE = ("queued", "running", "retry_wait", "cancel_requested")
USAGE_METRICS = (
    "input_tokens",
    "output_tokens",
    "total_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
    "reasoning_tokens",
    "input_audio_tokens",
    "output_audio_tokens",
    "input_images",
    "input_characters",
)


def digest(value: object) -> bytes:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).digest()


def model_references(job: Job) -> tuple[UUID, UUID]:
    """The model executor never accepts a deterministic job or invented credential."""
    if job.operation_kind != "credential_test" or job.credential_id is None or job.run_id is None:
        raise AppError(ErrorCode.STATE_CONFLICT)
    return job.credential_id, job.run_id


def snapshot(job: Job) -> JobRead:
    credential_id, run_id = model_references(job)
    return JobRead(
        id=job.id,
        run_id=run_id,
        credential_id=credential_id,
        state=job.state,
        revision=job.revision,
        generation=job.generation,
        sequence=job.progress_seq,
        stage="provider_call"
        if job.state == "running"
        else "result"
        if job.state in TERMINAL
        else None,
        progress_percent=100 if job.state == "succeeded" else None,
        error_code=job.error_code,
        can_cancel=job.state in ACTIVE,
        can_retry=job.state in ("blocked", "failed"),
        requires_new_attempt_confirmation=job.fence > 0,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


async def load_job(
    session: AsyncSession, owner: UUID, identifier: UUID, *, lock: bool = False
) -> Job:
    query = select(Job).where(Job.id == identifier, Job.owner_user_id == owner)
    row = await session.scalar(query.with_for_update() if lock else query)
    if row is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return row


async def emit(session: AsyncSession, job: Job, event_type: str = "model.job.updated") -> None:
    session.add(
        OutboxEvent(
            event_type=event_type,
            audit_event_id=None,
            authorization_revision=None,
            status="pending",
            payload={
                "schema_version": 1,
                "job_id": str(job.id),
                "generation": job.generation,
                "sequence": job.progress_seq,
            },
        )
    )


async def check_capacity(session: AsyncSession, owner: UUID) -> None:
    # One persistent policy root serializes instance reservation counts; user
    # roots already serialize credential tests for the owner.
    root = await session.scalar(
        select(ModelLimitPolicy)
        .where(
            ModelLimitPolicy.subject_kind == "instance",
            ModelLimitPolicy.limit_code == "instance_concurrent_jobs",
        )
        .with_for_update()
    )
    if root is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    limits = await configuration.effective_limits(session)
    override = await session.scalar(
        select(UserRuntimeLimit).where(UserRuntimeLimit.owner_user_id == owner)
    )
    user_limit = min(
        limits.max_concurrent_jobs, override.value_limit if override else limits.max_concurrent_jobs
    )
    own_count = await session.scalar(
        select(func.count())
        .select_from(Job)
        .where(Job.owner_user_id == owner, Job.state.in_(ACTIVE))
    )
    all_count = await session.scalar(
        select(func.count()).select_from(Job).where(Job.state.in_(ACTIVE))
    )
    if (
        not limits.enabled
        or (own_count or 0) >= user_limit
        or (all_count or 0) >= limits.instance_concurrent_jobs
    ):
        raise AppError(ErrorCode.QUOTA_EXCEEDED)


async def accept_test(
    session: AsyncSession,
    runtime: Runtime,
    scope: ScopeContext,
    identifier: UUID,
    payload: CredentialTest,
    key: str,
) -> TestAccepted:
    await lock_policy(session)
    await configuration.authorize(
        session, scope, ("client.credential.read", "client.credential.test")
    )
    if runtime.settings.model_execution_mode == "disabled":
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if re.fullmatch(r"[A-Za-z0-9._:-]{16,128}", key) is None:
        raise AppError(ErrorCode.INPUT_INVALID)
    intended = payload.model_dump(mode="json") | {
        "credential_id": str(identifier),
        "required_permissions": [
            "client.login",
            "client.credential.read",
            "client.credential.test",
        ],
        "input_schema_version": 1,
    }
    key_digest = digest([str(scope.user_id), "credential_test", key])
    old = await session.scalar(
        select(Job).where(Job.owner_user_id == scope.user_id, Job.idempotency_digest == key_digest)
    )
    if old:
        if old.input_digest != digest(intended):
            raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
        return TestAccepted(
            job_id=old.id,
            run_id=model_references(old)[1],
            generation=old.generation,
            state=old.state,
        )
    await check_capacity(session, scope.user_id)
    credential = await configuration.credential(
        session, scope.user_id, identifier, lock=True, active=True
    )
    configuration.require_revision(credential.revision, payload.expected_revision)
    model = await configuration.require_model(
        session, credential.provider, payload.model_id, payload.capability, payload.voice_id
    )
    accepted_limits = await configuration.effective_limits(session)
    require_probe_limits(accepted_limits, payload)
    limits_snapshot = accepted_limits.model_dump(mode="json")
    job_id, run_id = uuid4(), uuid4()
    request_id, operation_id = current_correlation()
    job = Job(
        id=job_id,
        owner_user_id=scope.user_id,
        actor_user_id=scope.user_id,
        session_id=scope.session_id,
        transport=scope.transport,
        audience="client",
        credential_id=identifier,
        run_id=run_id,
        operation_kind="credential_test",
        operation_id=operation_id or uuid4(),
        request_id=request_id or uuid4(),
        input_refs=intended,
        input_digest=digest(intended),
        idempotency_digest=key_digest,
        state="queued",
        revision=1,
        generation=1,
        progress_seq=1,
        fence=0,
    )
    session.add(job)
    session.add(
        AiRun(
            id=run_id,
            owner_user_id=scope.user_id,
            job_id=job_id,
            credential_id=identifier,
            credential_version=credential.credential_version,
            provider=credential.provider,
            model_id=payload.model_id,
            capability=payload.capability,
            state="accepted",
            generation=1,
            generation_config=payload.model_dump(mode="json")
            | {
                "model_call_limit": 1,
                "tool_call_limit": 0,
                "limit_snapshot": limits_snapshot,
                "config_schema_version": 1,
                "catalog_revision": model.revision,
            },
        )
    )
    session.add(
        JobStage(
            owner_user_id=scope.user_id,
            job_id=job_id,
            job_generation=1,
            stage_key="provider_call",
            state="pending",
            fence=0,
        )
    )
    await emit(session, job, "model.job.accepted")
    await session.flush()
    logger.info(
        "credential.test.accepted",
        extra={**current_log_context(), "job_id": job.id, "ai_run_id": run_id},
    )
    return TestAccepted(job_id=job_id, run_id=run_id, generation=1, state="queued")


async def read_job(session: AsyncSession, scope: ScopeContext, identifier: UUID) -> JobRead:
    await configuration.authorize(session, scope, ("client.job.read", "client.credential.read"))
    return snapshot(await load_job(session, scope.user_id, identifier))


async def change_job(
    session: AsyncSession,
    scope: ScopeContext,
    identifier: UUID,
    revision: int,
    *,
    retry: bool,
    confirm_new_attempt: bool = False,
    credential_id: UUID | None = None,
) -> JobRead:
    await lock_policy(session)
    permissions = (
        ("client.job.retry", "client.credential.read", "client.credential.test")
        if retry
        else ("client.job.cancel", "client.credential.read")
    )
    await configuration.authorize(session, scope, permissions)
    job = await load_job(session, scope.user_id, identifier, lock=True)
    configuration.require_revision(job.revision, revision)
    run = await session.get(AiRun, job.run_id)
    if run is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    if retry:
        if job.state not in ("blocked", "failed"):
            raise AppError(ErrorCode.STATE_CONFLICT)
        calls = await session.scalar(
            select(func.count())
            .select_from(ExternalCallAttempt)
            .where(ExternalCallAttempt.job_id == job.id)
        )
        if calls and not confirm_new_attempt:
            raise AppError(ErrorCode.STATE_CONFLICT)
        await check_capacity(session, scope.user_id)
        secret = await configuration.credential(
            session,
            scope.user_id,
            credential_id or model_references(job)[0],
            lock=True,
            active=True,
        )
        model = await configuration.require_model(
            session,
            secret.provider,
            run.model_id,
            run.capability,
            str(job.input_refs.get("voice_id")) if job.input_refs.get("voice_id") else None,
        )
        if secret.provider != run.provider:
            raise AppError(ErrorCode.CAPABILITY_UNSUPPORTED)
        job.credential_id = secret.id
        job.generation += 1
        job.state = "queued"
        job.error_code = None
        job.finished_at = None
        run_id = uuid4()
        job.run_id = run_id
        config = dict(run.generation_config)
        config["expected_revision"] = secret.revision
        config["catalog_revision"] = model.revision
        session.add(
            AiRun(
                id=run_id,
                owner_user_id=scope.user_id,
                job_id=job.id,
                credential_id=secret.id,
                credential_version=secret.credential_version,
                provider=secret.provider,
                model_id=run.model_id,
                capability=run.capability,
                state="accepted",
                generation=job.generation,
                generation_config=config,
            )
        )
        session.add(
            JobStage(
                owner_user_id=scope.user_id,
                job_id=job.id,
                job_generation=job.generation,
                stage_key="provider_call",
                state="pending",
                fence=0,
            )
        )
        logger.info("model.job.retry.accepted", extra=current_log_context())
    else:
        if job.state not in ACTIVE:
            raise AppError(ErrorCode.STATE_CONFLICT)
        job.state = "cancel_requested" if job.state == "running" else "cancelled"
        if job.state == "cancelled":
            run.state = "cancelled"
            run.finished_at = datetime.now(UTC)
            job.finished_at = datetime.now(UTC)
        logger.info("model.job.cancelled", extra=current_log_context())
    job.revision += 1
    job.progress_seq += 1
    job.updated_at = datetime.now(UTC)
    await emit(session, job, "model.job.accepted" if retry else "model.job.updated")
    return snapshot(job)


async def usage_projection(
    session: AsyncSession,
    owner: UUID | None,
    *,
    run_id: UUID | None = None,
    provider: str | None = None,
    model_id: str | None = None,
    capability: str | None = None,
    operation_kind: str | None = None,
    since: datetime | None = None,
    until: datetime | None = None,
) -> ModelUsage:
    as_of = until or datetime.now(UTC)
    if as_of.tzinfo is None or (since is not None and (since.tzinfo is None or since > as_of)):
        raise AppError(ErrorCode.INPUT_INVALID)
    query = select(ExternalCallAttempt).where(ExternalCallAttempt.started_at <= as_of)
    if owner is not None:
        query = query.where(ExternalCallAttempt.owner_user_id == owner)
    if run_id:
        query = query.where(ExternalCallAttempt.ai_run_id == run_id)
    for column, value in (
        (ExternalCallAttempt.provider, provider),
        (ExternalCallAttempt.model_id, model_id),
        (ExternalCallAttempt.capability, capability),
        (ExternalCallAttempt.operation_kind, operation_kind),
    ):
        if value:
            query = query.where(column == value)
    if since is not None or run_id is None:
        query = query.where(ExternalCallAttempt.started_at >= (since or as_of - timedelta(days=30)))
    columns = [
        ExternalCallAttempt.provider,
        ExternalCallAttempt.model_id,
        ExternalCallAttempt.capability,
        ExternalCallAttempt.operation_kind,
        ExternalCallAttempt.simulated,
    ]
    aggregated = query.with_only_columns(
        *columns,
        func.count().label("attempt_count"),
        func.sum(ExternalCallAttempt.aggregation_revision).label("aggregation_revision"),
        *[
            func.sum(case((ExternalCallAttempt.status == status, 1), else_=0)).label(
                status + "_count"
            )
            for status in ("started", "succeeded", "failed", "unknown")
        ],
        *[
            expression
            for name in USAGE_METRICS
            for expression in (
                func.sum(getattr(ExternalCallAttempt, name)).label(name + "_sum"),
                func.count(getattr(ExternalCallAttempt, name)).label(name + "_known"),
            )
        ],
    ).group_by(*columns)
    groups: list[UsageGroup] = []
    revision = 0
    for values in (await session.execute(aggregated)).mappings():
        count = int(values["attempt_count"])
        revision += int(values["aggregation_revision"])
        metrics: dict[str, UsageMetric] = {}
        for name in USAGE_METRICS:
            known_count = int(values[name + "_known"])
            known_sum = values[name + "_sum"]
            metrics[name] = UsageMetric(
                known_sum=int(known_sum) if known_sum is not None else None,
                known_attempt_count=known_count,
                unknown_attempt_count=count - known_count,
                completeness="complete"
                if known_count == count
                else "partial"
                if known_count
                else "unavailable",
            )
        groups.append(
            UsageGroup(
                simulated=values["simulated"],
                provider=values["provider"],
                model_id=values["model_id"],
                capability=values["capability"],
                operation_kind=values["operation_kind"],
                attempt_count=count,
                started_count=values["started_count"],
                succeeded_count=values["succeeded_count"],
                failed_count=values["failed_count"],
                unknown_count=values["unknown_count"],
                metrics=metrics,
            )
        )
    return ModelUsage(as_of=as_of, aggregation_revision=revision, groups=groups)


async def test_result(
    session: AsyncSession, scope: ScopeContext, credential_id: UUID, run_id: UUID
) -> TestResult:
    await configuration.authorize(session, scope, ("client.credential.read",))
    run = await session.scalar(
        select(AiRun).where(
            AiRun.id == run_id,
            AiRun.owner_user_id == scope.user_id,
            AiRun.credential_id == credential_id,
        )
    )
    if run is None:
        raise AppError(ErrorCode.RESOURCE_NOT_FOUND)
    return TestResult(
        run_id=run.id,
        job_id=run.job_id,
        credential_id=run.credential_id,
        credential_version=run.credential_version,
        provider=cast(Provider, run.provider),
        model_id=run.model_id,
        model_revision=run.model_revision,
        capability=cast(Capability, run.capability),
        state=run.state,
        tested_at=run.finished_at,
        error_code=run.error_code,
        usage=await usage_projection(session, scope.user_id, run_id=run.id),
    )


async def worker_scope(session: AsyncSession, runtime: Runtime, job: Job) -> ScopeContext:
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
        codes=("client.login", "client.credential.read", "client.credential.test"),
    )
    return ScopeContext(
        user_id=user.id,
        session_id=job.session_id,
        audience="client",
        transport=cast(Literal["web", "native"], job.transport),
        user_authz_version=user.authz_version,
        policy_authz_version=0,
        security_epoch=user.security_epoch,
        absolute_expires_at=now,
    )


async def execute_job(
    runtime: Runtime, identifier: UUID, worker: str, *, inbox: tuple[UUID, bytes] | None = None
) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session:
        job = await session.get(Job, identifier)
        if job is None:
            return
    model_references(job)
    request_token = request_id_context.set(job.request_id)
    operation_token = operation_id_context.set(job.operation_id)
    user_token = user_id_context.set(job.owner_user_id)
    audience_token = audience_context.set("client")
    job_token = job_id_context.set(job.id)
    run_token = ai_run_id_context.set(job.run_id)
    try:
        await _execute_job(runtime, identifier, worker, inbox=inbox)
    finally:
        request_id_context.reset(request_token)
        operation_id_context.reset(operation_token)
        user_id_context.reset(user_token)
        audience_context.reset(audience_token)
        job_id_context.reset(job_token)
        ai_run_id_context.reset(run_token)


async def _execute_job(
    runtime: Runtime, identifier: UUID, worker: str, *, inbox: tuple[UUID, bytes] | None = None
) -> None:
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session:
        existing_job = await session.get(Job, identifier)
        completed = (
            await session.scalar(
                select(ExternalCallAttempt).where(
                    ExternalCallAttempt.ai_run_id == existing_job.run_id,
                    ExternalCallAttempt.status.in_(("succeeded", "failed")),
                )
            )
            if existing_job
            else None
        )
    if completed is not None:
        await publish_recorded(runtime, identifier, inbox=inbox)
        return
    now = datetime.now(UTC)
    async with resources.database.sessions() as session, session.begin():
        await lock_job_owner(session, identifier)
        job = await session.scalar(select(Job).where(Job.id == identifier).with_for_update())
        if job is None or job.state not in ("queued", "running", "cancel_requested"):
            return
        if (
            job.state in ("running", "cancel_requested")
            and job.lease_expires_at
            and job.lease_expires_at > now
        ):
            return
        run = await session.scalar(select(AiRun).where(AiRun.id == job.run_id).with_for_update())
        if run is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        stage = await session.scalar(
            select(JobStage)
            .where(JobStage.job_id == job.id, JobStage.job_generation == job.generation)
            .with_for_update()
        )
        if stage is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        existing = await session.scalar(
            select(ExternalCallAttempt).where(ExternalCallAttempt.ai_run_id == run.id)
        )
        cancelling = job.state == "cancel_requested"
        if existing:
            # No automatic reissue after provider execution might have started.
            if existing.status == "started":
                existing.status = "unknown"
                existing.error_code = "EXTERNAL_RESULT_UNKNOWN"
                existing.aggregation_revision += 1
                existing.finished_at = now
            job.fence += 1
            job.lease_owner = None
            job.lease_expires_at = None
            job.state = "cancelled" if cancelling else "blocked"
            job.error_code = "EXTERNAL_RESULT_UNKNOWN"
            run.state = "unknown_outcome"
            run.error_code = job.error_code
            job.finished_at = run.finished_at = now
            job.revision += 1
            job.progress_seq += 1
            await emit(session, job)
            await commit_inbox(session, inbox)
            return
        if cancelling:
            job.fence += 1
            job.state = run.state = "cancelled"
            job.finished_at = run.finished_at = now
            job.lease_owner = None
            job.lease_expires_at = None
            job.revision += 1
            job.progress_seq += 1
            await emit(session, job)
            await commit_inbox(session, inbox)
            return
        try:
            await worker_scope(session, runtime, job)
            secret = await configuration.credential(
                session, job.owner_user_id, model_references(job)[0], lock=True, active=True
            )
            if secret.credential_version != run.credential_version:
                raise AppError(ErrorCode.KEY_REQUIRED)
            config = CredentialTest.model_validate(
                {
                    name: value
                    for name, value in run.generation_config.items()
                    if name in CredentialTest.model_fields
                }
            )
            model = await configuration.require_model(
                session, run.provider, run.model_id, run.capability, config.voice_id
            )
            frozen_revision = run.generation_config.get("catalog_revision")
            if type(frozen_revision) is not int or frozen_revision != model.revision:
                raise AppError(ErrorCode.STATE_CONFLICT)
            limits = await configuration.effective_limits(session)
            frozen_limits = ModelLimits.model_validate(
                run.generation_config.get("limit_snapshot", limits.model_dump())
            )
            limits = ModelLimits.model_validate(
                {
                    name: min(value, getattr(frozen_limits, name))
                    if isinstance(value, int) and not isinstance(value, bool) and name != "revision"
                    else value
                    for name, value in limits.model_dump().items()
                }
            )
            require_probe_limits(limits, config)
            if secret.encrypted_key is None:
                raise AppError(ErrorCode.KEY_REQUIRED)
            key = CredentialCrypto(runtime.settings).decrypt(
                secret.owner_user_id,
                secret.id,
                secret.credential_version,
                secret.encryption_key_version,
                secret.encrypted_key,
            )
        except AppError as error:
            job.state = "blocked"
            job.error_code = error.code.value
            run.state = "interrupted"
            run.error_code = job.error_code
            job.revision += 1
            job.progress_seq += 1
            await emit(session, job)
            return
        job.state = "running"
        job.fence += 1
        job.lease_owner = worker
        job.lease_expires_at = now + timedelta(seconds=120)
        job.heartbeat_at = now
        job.revision += 1
        job.progress_seq += 1
        run.state = "running"
        stage.state = "running"
        stage.fence = job.fence
        fence, generation, owner, provider = (
            job.fence,
            job.generation,
            job.owner_user_id,
            run.provider,
        )
        attempt_id = uuid4()
        session.add(
            ExternalCallAttempt(
                id=attempt_id,
                owner_user_id=owner,
                job_id=job.id,
                ai_run_id=run.id,
                credential_id=model_references(job)[0],
                credential_version=run.credential_version,
                provider=provider,
                model_id=run.model_id,
                capability=run.capability,
                operation_kind="credential_test",
                attempt_no=1,
                status="started",
                usage_status="unavailable",
                usage={},
                simulated=runtime.settings.model_execution_mode == "fake",
                started_at=now,
                aggregation_revision=0,
            )
        )
        await emit(session, job)
    logger.info("model.job.claimed", extra=current_log_context())
    logger.info("model.attempt.started", extra=current_log_context())
    outcome = None
    failure = None
    stopped = asyncio.Event()
    heartbeat = asyncio.create_task(
        heartbeat_lease(runtime, identifier, worker, fence, generation, stopped)
    )
    try:
        async with asyncio.timeout(
            limits.tts_timeout_seconds if config.capability == "tts" else limits.timeout_seconds
        ):
            outcome = await execute_probe(runtime.settings, provider, key, config, limits)
    except ProviderFailure as error:
        failure = error
    except (UnexpectedModelBehavior, UsageLimitExceeded):
        failure = ProviderFailure("OUTPUT_INVALID")
    except Exception as error:
        status = getattr(error, "status_code", None)
        failure = ProviderFailure(
            http_error_code(status) if isinstance(status, int) else "EXTERNAL_RESULT_UNKNOWN",
            unknown=not isinstance(status, int),
        )
    finally:
        stopped.set()
        await heartbeat
    facts = outcome or (failure.facts if failure else None)
    # Seal safe provider facts independently before the authorized business
    # publication. A publish failure resumes this committed non-model stage.
    async with resources.database.sessions() as session, session.begin():
        await lock_job_owner(session, identifier)
        attempt = await session.scalar(
            select(ExternalCallAttempt)
            .where(ExternalCallAttempt.id == attempt_id)
            .with_for_update()
        )
        if attempt is None:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        attempt.finished_at = datetime.now(UTC)
        attempt.status = (
            "succeeded" if outcome else "unknown" if failure and failure.unknown else "failed"
        )
        attempt.error_code = failure.code if failure else None
        if facts:
            attempt.usage = {
                name: value
                for name, value in facts.usage.items()
                if name in USAGE_METRICS and (value is None or value >= 0)
            }

            for name, value in attempt.usage.items():
                if value is not None:
                    setattr(attempt, name, value)
            attempt.provider_usage_schema = facts.usage_schema
            attempt.usage_status = (
                "partial"
                if any(value is not None for value in attempt.usage.values())
                else "unavailable"
            )
        attempt.aggregation_revision += 1
        stage = await session.scalar(
            select(JobStage)
            .where(JobStage.job_id == identifier, JobStage.job_generation == generation)
            .with_for_update()
        )
        current_job = await session.scalar(
            select(Job).where(Job.id == identifier).with_for_update()
        )
        if (
            stage
            and stage.fence == fence
            and current_job
            and current_job.fence == fence
            and current_job.generation == generation
        ):
            stage.state = "committed"
            stage.result_refs = {"attempt_id": str(attempt_id), "status": attempt.status}
    await publish_recorded(runtime, identifier, inbox=inbox)
    if outcome:
        logger.info("credential.test.completed", extra=current_log_context())
    else:
        logger.info("credential.test.failed", extra=current_log_context())


async def publish_recorded(
    runtime: Runtime, identifier: UUID, *, inbox: tuple[UUID, bytes] | None = None
) -> None:
    """Recover only committed safe provider facts; never issues a model call."""
    resources = runtime.resources
    if resources is None:
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
    async with resources.database.sessions() as session, session.begin():
        await lock_job_owner(session, identifier)
        job = await session.scalar(select(Job).where(Job.id == identifier).with_for_update())
        if job is None or job.state in TERMINAL:
            await commit_inbox(session, inbox)
            return
        run = await session.scalar(select(AiRun).where(AiRun.id == job.run_id).with_for_update())
        stage = await session.scalar(
            select(JobStage)
            .where(JobStage.job_id == identifier, JobStage.job_generation == job.generation)
            .with_for_update()
        )
        attempt = await session.scalar(
            select(ExternalCallAttempt)
            .where(ExternalCallAttempt.ai_run_id == job.run_id)
            .with_for_update()
        )
        if stage is not None and stage.fence != job.fence:
            return
        if (
            run is None
            or stage is None
            or attempt is None
            or stage.state != "committed"
            or not stage.result_refs
            or stage.result_refs.get("attempt_id") != str(attempt.id)
        ):
            raise AppError(ErrorCode.STATE_CONFLICT)
        try:
            await worker_scope(session, runtime, job)
            secret = await configuration.credential(
                session, job.owner_user_id, model_references(job)[0], lock=True, active=True
            )
            if secret.credential_version != run.credential_version:
                raise AppError(ErrorCode.KEY_REQUIRED)
            model = await configuration.require_model(
                session,
                run.provider,
                run.model_id,
                run.capability,
                cast(str | None, run.generation_config.get("voice_id")),
            )
            frozen_revision = run.generation_config.get("catalog_revision")
            if type(frozen_revision) is not int or frozen_revision != model.revision:
                raise AppError(ErrorCode.STATE_CONFLICT)
            job.state = (
                "cancelled"
                if job.state == "cancel_requested"
                else "succeeded"
                if attempt.status == "succeeded"
                else "blocked"
                if attempt.status == "unknown"
                else "failed"
            )
            run.state = "unknown_outcome" if attempt.status == "unknown" else job.state
            job.error_code = run.error_code = attempt.error_code
        except AppError as error:
            job.state = "blocked"
            run.state = "interrupted"
            job.error_code = run.error_code = error.code.value
        job.finished_at = run.finished_at = datetime.now(UTC)
        job.revision += 1
        job.progress_seq += 1
        job.lease_owner = None
        job.lease_expires_at = None
        await emit(session, job)
        await commit_inbox(session, inbox)


async def lock_policy(session: AsyncSession) -> None:
    await session.scalar(
        select(ModelLimitPolicy)
        .where(
            ModelLimitPolicy.subject_kind == "instance",
            ModelLimitPolicy.limit_code == "instance_concurrent_jobs",
        )
        .with_for_update()
    )


async def lock_job_owner(session: AsyncSession, identifier: UUID) -> None:
    from app.models import User

    await lock_policy(session)
    owner = await session.scalar(select(Job.owner_user_id).where(Job.id == identifier))
    if owner:
        await session.scalar(select(User).where(User.id == owner).with_for_update())


async def heartbeat_lease(
    runtime: Runtime,
    identifier: UUID,
    worker: str,
    fence: int,
    generation: int,
    stopped: asyncio.Event,
) -> None:
    """Lease renewals require the same persisted generation and fencing owner."""
    resources = runtime.resources
    if resources is None:
        return
    while not stopped.is_set():
        try:
            await asyncio.wait_for(stopped.wait(), timeout=15)
            return
        except TimeoutError:
            pass
        async with resources.database.sessions() as session, session.begin():
            await lock_job_owner(session, identifier)
            job = await session.scalar(select(Job).where(Job.id == identifier).with_for_update())
            if (
                job is None
                or job.fence != fence
                or job.generation != generation
                or job.lease_owner != worker
                or job.state not in ("running", "cancel_requested")
            ):
                return
            now = datetime.now(UTC)
            job.heartbeat_at = now
            job.lease_expires_at = now + timedelta(seconds=120)
            job.updated_at = now


async def commit_inbox(session: AsyncSession, inbox: tuple[UUID, bytes] | None) -> None:
    if inbox is None:
        return
    event_id, payload_digest = inbox
    old = await session.scalar(
        select(InboxEvent)
        .where(InboxEvent.consumer_name == "model-worker", InboxEvent.event_id == event_id)
        .with_for_update()
    )
    if old is not None:
        if old.payload_digest != payload_digest:
            raise AppError(ErrorCode.IDEMPOTENCY_CONFLICT)
        return
    session.add(
        InboxEvent(
            consumer_name="model-worker",
            event_id=event_id,
            payload_digest=payload_digest,
            processed_at=datetime.now(UTC),
        )
    )


def require_probe_limits(limits: ModelLimits, config: CredentialTest) -> None:
    if not limits.enabled or limits.max_model_calls == 0 or limits.max_output_tokens == 0:
        raise AppError(ErrorCode.QUOTA_EXCEEDED)
    if config.capability == "tts":
        sample = "こんにちは。" if config.language_tag == "ja" else "Hello."
        if limits.tts_timeout_seconds == 0 or limits.max_tts_characters < len(sample):
            raise AppError(ErrorCode.QUOTA_EXCEEDED)
    elif limits.timeout_seconds == 0 or (
        config.capability == "vision" and limits.max_test_image_bytes < len(test_image())
    ):
        raise AppError(ErrorCode.QUOTA_EXCEEDED)
