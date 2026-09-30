"""Real PG regressions for governance commit identity and indirect grants."""

import asyncio
import os
from collections.abc import AsyncIterator
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
import pytest_asyncio
from pydantic import SecretStr
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.schema import CreateSchema, DropSchema

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import (
    AdminAuditEvent,
    AuthChallenge,
    AuthorizationRevision,
    AuthPolicy,
    AuthSession,
    IdempotencyRecord,
    OutboxEvent,
    Role,
    RoleGrantBoundary,
    RoleInheritance,
    RolePermission,
    User,
    UserRole,
)
from app.schemas.role_governance import AuthorizationWriteResult
from app.schemas.user_governance import ManualRecoveryDecisionResult
from app.services.auth_context import verify_scope_in_transaction
from app.services.auth_crypto import AuthCrypto, hash_password
from app.services.governance_receipts import GovernanceReceiptContext, commit_governance_receipt
from app.services.governance_security import verify_admin_write
from app.services.initialization import apply_seed, initialize_admin
from app.services.registration import consume_recovery, open_manual_recovery
from app.services.role_governance import (
    create_role,
    replace_role_grants,
    replace_role_parents,
    set_role_enabled,
)
from app.services.user_governance import decide_manual_recovery, replace_account_roles

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    source = load_maintenance_settings(Path(os.environ["HARUKA_MAINTENANCE_TEST_CONFIG"]))
    assert source.app_env == "test"
    schema = f"haruka_migration_test_{uuid4().hex}"
    settings = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        await upgrade_database(settings, MIGRATIONS)
        await apply_seed(settings)
        yield settings
    finally:
        async with observer.begin() as connection:
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


def auth_session(user: User, audience: str = "admin") -> AuthSession:
    now = datetime.now(UTC)
    return AuthSession(
        user_id=user.id,
        audience=audience,
        transport="web",
        platform="web",
        security_epoch=user.security_epoch,
        audience_security_epoch=(
            user.admin_security_epoch if audience == "admin" else user.client_security_epoch
        ),
        absolute_expires_at=now + timedelta(hours=1),
        reauthenticated_at=now,
    )


@pytest.mark.parametrize("invalidation", ["revoke", "disable", "stale_reauth"])
async def test_waiting_write_rechecks_identity_before_any_commit(
    target: MaintenanceSettings, invalidation: str
) -> None:
    admin = await initialize_admin(
        target, email="guard@haruka.example.test", password=SecretStr("synthetic-password-2026")
    )
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            user = await session.get(User, admin.user_id)
            assert user is not None
            live = auth_session(user)
            session.add(live)
            await session.flush()
            session_id = live.id
        async with AsyncSession(engine, expire_on_commit=False) as session:
            scope = await verify_scope_in_transaction(
                session, user_id=user.id, session_id=session_id, audience="admin", transport="web"
            )
            initial = (
                await session.scalar(select(func.count()).select_from(AdminAuditEvent)),
                await session.scalar(select(func.count()).select_from(OutboxEvent)),
            )
        entered = asyncio.Event()

        async def attempt() -> None:
            async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
                entered.set()
                await verify_admin_write(session, scope)
                await create_role(
                    session, actor_id=user.id, code="must_not_commit", name="No", description=None
                )

        async with AsyncSession(engine, expire_on_commit=False) as blocker, blocker.begin():
            await blocker.scalar(
                select(AuthorizationRevision)
                .where(AuthorizationRevision.code == "global")
                .with_for_update()
            )
            task = asyncio.create_task(attempt())
            await entered.wait()
            current_user = await blocker.get(User, user.id, with_for_update=True)
            current_session = await blocker.get(AuthSession, session_id, with_for_update=True)
            assert current_user is not None and current_session is not None
            if invalidation == "disable":
                current_user.status = "disabled"
            elif invalidation == "revoke":
                current_session.revoked_at = datetime.now(UTC)
            else:
                current_session.reauthenticated_at = datetime.now(UTC) - timedelta(minutes=6)
        with pytest.raises(AppError) as rejected:
            await task
        assert rejected.value.code == ErrorCode.SESSION_INVALID
        async with AsyncSession(engine, expire_on_commit=False) as session:
            assert (
                await session.scalar(select(Role.id).where(Role.code == "must_not_commit")) is None
            )
            assert initial == (
                await session.scalar(select(func.count()).select_from(AdminAuditEvent)),
                await session.scalar(select(func.count()).select_from(OutboxEvent)),
            )
    finally:
        await engine.dispose()


@pytest.mark.parametrize("operation", ["remove_deny", "disable_deny", "protected_ancestor"])
async def test_indirect_expansion_cannot_escape_actor_ceiling(
    target: MaintenanceSettings, operation: str
) -> None:
    await initialize_admin(
        target, email="root@haruka.example.test", password=SecretStr("synthetic-password-2026")
    )
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            actor_role = Role(code="delegate", name="Delegate", protected=False, enabled=True)
            allow = Role(code="high", name="High", protected=False, enabled=True)
            deny = Role(code="denier", name="Deny", protected=False, enabled=True)
            parent = Role(code="parent", name="Parent", protected=False, enabled=True)
            session.add_all([actor_role, allow, deny, parent])
            await session.flush()
            digest = await hash_password(SecretStr("synthetic-password-2026"))
            actor = User(
                email="delegate@haruka.example.test",
                email_normalized="delegate@haruka.example.test",
                password_hash=digest,
                status="active",
            )
            holder = User(
                email="holder@haruka.example.test",
                email_normalized="holder@haruka.example.test",
                password_hash=digest,
                status="active",
            )
            session.add_all([actor, holder])
            await session.flush()
            session.add_all(
                [
                    UserRole(user_id=actor.id, role_id=actor_role.id),
                    UserRole(user_id=holder.id, role_id=allow.id),
                    UserRole(user_id=holder.id, role_id=deny.id),
                    RolePermission(
                        role_id=actor_role.id,
                        permission_code="admin.login",
                        effect="allow",
                        data_scope="platform_metadata",
                    ),
                    RolePermission(
                        role_id=actor_role.id,
                        permission_code="admin.role.update",
                        effect="allow",
                        data_scope="platform_metadata",
                    ),
                    RolePermission(
                        role_id=actor_role.id,
                        permission_code="admin.role.permission.assign",
                        effect="allow",
                        data_scope="platform_metadata",
                    ),
                    RolePermission(
                        role_id=allow.id,
                        permission_code="admin.audit.read",
                        effect="allow",
                        data_scope="platform_metadata",
                    ),
                    RolePermission(
                        role_id=deny.id,
                        permission_code="admin.audit.read",
                        effect="deny",
                        data_scope="platform_metadata",
                    ),
                    RoleGrantBoundary(
                        grantor_role_id=actor_role.id,
                        boundary_kind="assign_role",
                        target_role_id=parent.id,
                    ),
                ]
            )
            root = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert root is not None
            session.add(RoleInheritance(child_role_id=parent.id, parent_role_id=root.id))
        with pytest.raises(AppError) as rejected:
            async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
                if operation == "remove_deny":
                    await replace_role_grants(
                        session, actor_id=actor.id, role_id=deny.id, expected_revision=1, grants=()
                    )
                elif operation == "disable_deny":
                    await set_role_enabled(
                        session,
                        actor_id=actor.id,
                        role_id=deny.id,
                        expected_revision=1,
                        enabled=False,
                    )
                else:
                    await replace_role_parents(
                        session,
                        actor_id=actor.id,
                        role_id=deny.id,
                        expected_revision=1,
                        parent_role_ids=(parent.id,),
                    )
        assert rejected.value.code == ErrorCode.PERMISSION_DENIED
        async with AsyncSession(engine, expire_on_commit=False) as session:
            unchanged = await session.get(Role, deny.id)
            assert unchanged is not None and unchanged.enabled and unchanged.revision == 1
            assert (
                await session.scalar(
                    select(RolePermission.id).where(RolePermission.role_id == deny.id)
                )
                is not None
            )
            assert (
                await session.scalar(
                    select(RoleInheritance.id).where(RoleInheritance.child_role_id == deny.id)
                )
                is None
            )
    finally:
        await engine.dispose()


@pytest.mark.parametrize("change", ["grants", "enabled", "bindings"])
async def test_regrant_login_never_revives_old_session(
    target: MaintenanceSettings, change: str
) -> None:
    admin = await initialize_admin(
        target, email="revoker@haruka.example.test", password=SecretStr("synthetic-password-2026")
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            holder = User(
                email="regrant@haruka.example.test",
                email_normalized="regrant@haruka.example.test",
                password_hash=await hash_password(SecretStr("synthetic-password-2026")),
                status="active",
            )
            login = Role(code="session_login", name="Login", protected=False, enabled=True)
            client = Role(code="session_client", name="Client", protected=False, enabled=True)
            session.add_all([holder, login, client])
            await session.flush()
            root = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert root is not None
            session.add(
                RoleGrantBoundary(
                    grantor_role_id=root.id,
                    boundary_kind="assign_permission",
                    permission_code="admin.login",
                    data_scope="platform_metadata",
                )
            )
            session.add_all(
                [
                    RolePermission(
                        role_id=login.id,
                        permission_code="admin.login",
                        effect="allow",
                        data_scope="platform_metadata",
                    ),
                    RolePermission(
                        role_id=client.id,
                        permission_code="client.login",
                        effect="allow",
                        data_scope="self",
                    ),
                    UserRole(user_id=holder.id, role_id=login.id),
                    UserRole(user_id=holder.id, role_id=client.id),
                ]
            )
            for role in (login, client):
                session.add_all(
                    [
                        RoleGrantBoundary(
                            grantor_role_id=root.id,
                            boundary_kind="assign_role",
                            target_role_id=role.id,
                        ),
                        RoleGrantBoundary(
                            grantor_role_id=root.id,
                            boundary_kind="manage_account_role",
                            target_role_id=role.id,
                        ),
                    ]
                )
            await session.flush()
            holder = await session.get(User, holder.id, populate_existing=True)
            assert holder is not None
            old_admin, old_client = auth_session(holder), auth_session(holder, "client")
            session.add_all([old_admin, old_client])
            await session.flush()
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            if change == "grants":
                changed = await replace_role_grants(
                    session,
                    actor_id=admin.user_id,
                    role_id=login.id,
                    expected_revision=1,
                    grants=(),
                )
                await replace_role_grants(
                    session,
                    actor_id=admin.user_id,
                    role_id=login.id,
                    expected_revision=changed.revision,
                    grants=(("admin.login", "allow", "platform_metadata"),),
                )
            elif change == "enabled":
                changed = await set_role_enabled(
                    session,
                    actor_id=admin.user_id,
                    role_id=login.id,
                    expected_revision=1,
                    enabled=False,
                )
                await set_role_enabled(
                    session,
                    actor_id=admin.user_id,
                    role_id=login.id,
                    expected_revision=changed.revision,
                    enabled=True,
                )
            else:
                changed_user = await replace_account_roles(
                    session,
                    actor_id=admin.user_id,
                    user_id=holder.id,
                    expected_revision=1,
                    role_ids=(client.id,),
                )
                await replace_account_roles(
                    session,
                    actor_id=admin.user_id,
                    user_id=holder.id,
                    expected_revision=changed_user.revision,
                    role_ids=(login.id, client.id),
                )
        async with AsyncSession(engine) as session:
            persisted = await session.get(User, holder.id)
            revoked = await session.get(AuthSession, old_admin.id)
            preserved = await session.get(AuthSession, old_client.id)
            assert persisted is not None and persisted.admin_security_epoch == 1
            assert persisted.client_security_epoch == 0
            assert revoked is not None and revoked.revoked_at is not None
            assert preserved is not None and preserved.revoked_at is None
            with pytest.raises(AppError) as old:
                await verify_scope_in_transaction(
                    session,
                    user_id=holder.id,
                    session_id=old_admin.id,
                    audience="admin",
                    transport="web",
                )
            assert old.value.code == ErrorCode.SESSION_INVALID
            await verify_scope_in_transaction(
                session,
                user_id=holder.id,
                session_id=old_client.id,
                audience="client",
                transport="web",
            )
    finally:
        await engine.dispose()


async def test_receipt_replay_conflict_and_key_rotations_never_reexecute(
    target: MaintenanceSettings,
) -> None:
    admin = await initialize_admin(
        target, email="receipt@haruka.example.test", password=SecretStr("synthetic-password-2026")
    )
    assert admin.user_id is not None
    admin_id = admin.user_id
    engine = create_maintenance_engine(target)
    crypto = AuthCrypto(
        signing_key=b"s" * 32,
        digest_key=b"d" * 32,
        issuer="test",
        signing_key_version="v1",
        digest_key_version="v1",
        mail_key=None,
        mail_key_version="v1",
    )
    context = GovernanceReceiptContext(
        action="POST:/api/v1/admin/roles",
        key="synthetic-stable-key-2026",
        request_text='{"code":"receipt_created"}',
        permissions=("admin.role.create",),
    )
    calls = 0
    try:
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            user = await session.get(User, admin.user_id)
            assert user is not None
            live = auth_session(user)
            session.add(live)
            await session.flush()
        async with AsyncSession(engine) as session:
            scope = await verify_scope_in_transaction(
                session,
                user_id=admin.user_id,
                session_id=live.id,
                audience="admin",
                transport="web",
            )

        async def perform(session: AsyncSession) -> AuthorizationWriteResult:
            nonlocal calls
            calls += 1
            return await create_role(
                session,
                actor_id=admin_id,
                code="receipt_created",
                name="Receipt",
                description=None,
            )

        async with AsyncSession(engine) as session, session.begin():
            original = await commit_governance_receipt(
                session, scope, context, crypto, AuthorizationWriteResult, lambda: perform(session)
            )
        async with AsyncSession(engine) as session, session.begin():
            repeated = await commit_governance_receipt(
                session, scope, context, crypto, AuthorizationWriteResult, lambda: perform(session)
            )
            assert repeated == original
            row = await session.scalar(
                select(IdempotencyRecord).where(IdempotencyRecord.audience == "admin")
            )
            assert (
                row is not None and row.safe_response is not None and row.lookup_digest is not None
            )
            assert "receipt_created" not in str(row.safe_response)
            assert row.expires_at >= row.created_at + timedelta(days=7) - timedelta(seconds=1)
        for changed_context, changed_crypto, expected in [
            (
                replace(context, request_text='{"code":"other"}'),
                crypto,
                ErrorCode.IDEMPOTENCY_CONFLICT,
            ),
            (
                context,
                replace(crypto, signing_key=b"x" * 32, signing_key_version="v2"),
                ErrorCode.SERVICE_UNAVAILABLE,
            ),
            (
                context,
                replace(crypto, digest_key=b"y" * 32, digest_key_version="v2"),
                ErrorCode.SERVICE_UNAVAILABLE,
            ),
        ]:
            with pytest.raises(AppError) as rejected:
                async with AsyncSession(engine) as session, session.begin():
                    await commit_governance_receipt(
                        session,
                        scope,
                        changed_context,
                        changed_crypto,
                        AuthorizationWriteResult,
                        lambda: perform(session),
                    )
            assert rejected.value.code == expected
        assert calls == 1
    finally:
        await engine.dispose()


@pytest.mark.parametrize("invalidation", ["epoch", "password", "consumed", "expired", "revoked"])
async def test_manual_receipt_never_rediscloses_invalid_challenge(
    target: MaintenanceSettings, invalidation: str
) -> None:
    admin = await initialize_admin(
        target,
        email="manual-admin@haruka.example.test",
        password=SecretStr("synthetic-password-2026"),
    )
    assert admin.user_id is not None
    admin_id = admin.user_id
    engine = create_maintenance_engine(target)
    crypto = AuthCrypto(
        signing_key=b"s" * 32,
        digest_key=b"d" * 32,
        issuer="test",
        signing_key_version="v1",
        digest_key_version="v1",
        mail_key=None,
        mail_key_version="v1",
    )
    calls = 0
    try:
        async with AsyncSession(engine, expire_on_commit=False) as session, session.begin():
            root = await session.scalar(select(Role).where(Role.code == "super_admin"))
            actor = await session.get(User, admin_id)
            assert root is not None and actor is not None
            session.add(
                RoleGrantBoundary(
                    grantor_role_id=root.id, boundary_kind="manage_unassigned_accounts"
                )
            )
            holder = User(
                email="manual-holder@haruka.example.test",
                email_normalized="manual-holder@haruka.example.test",
                status="active",
                password_hash=await hash_password(SecretStr("synthetic-holder-password")),
            )
            live = auth_session(actor)
            session.add_all([holder, live])
            await session.flush()
            holder_id, session_id = holder.id, live.id
            policy = await session.get(AuthPolicy, "registration")
            assert policy is not None
            policy.recovery_mode = "manual"
            await open_manual_recovery(
                session, crypto=crypto, email=holder.email_normalized, now=datetime.now(UTC)
            )
            challenge = await session.scalar(
                select(AuthChallenge).where(
                    AuthChallenge.user_id == holder_id, AuthChallenge.purpose == "manual_recovery"
                )
            )
            assert challenge is not None
            challenge_id = challenge.id
        async with AsyncSession(engine) as session:
            scope = await verify_scope_in_transaction(
                session, user_id=admin_id, session_id=session_id, audience="admin", transport="web"
            )
        context = GovernanceReceiptContext(
            action="POST:/manual-recovery/decision",
            key="manual-receipt-stable-key",
            request_text="issue",
            permissions=("admin.user.update",),
            user_id=holder_id,
            challenge_id=challenge_id,
        )

        async def perform(session: AsyncSession) -> ManualRecoveryDecisionResult:
            nonlocal calls
            calls += 1
            return await decide_manual_recovery(
                session,
                actor_id=admin_id,
                user_id=holder_id,
                challenge_id=challenge_id,
                expected_revision=1,
                decision="issue",
                verification_method="in_person",
                crypto=crypto,
            )

        async with AsyncSession(engine) as session, session.begin():
            original = await commit_governance_receipt(
                session,
                scope,
                context,
                crypto,
                ManualRecoveryDecisionResult,
                lambda: perform(session),
            )
            assert original.token is not None
        async with AsyncSession(engine) as session, session.begin():
            repeated = await commit_governance_receipt(
                session,
                scope,
                context,
                crypto,
                ManualRecoveryDecisionResult,
                lambda: perform(session),
            )
            assert repeated == original
            row = await session.scalar(
                select(IdempotencyRecord).where(IdempotencyRecord.audience == "admin")
            )
            assert row is not None and original.token not in str(row.safe_response)
        async with AsyncSession(engine) as session, session.begin():
            holder = await session.get(User, holder_id)
            challenge = await session.get(AuthChallenge, challenge_id)
            assert holder is not None and challenge is not None
            if invalidation == "epoch":
                holder.security_epoch += 1
            elif invalidation == "password":
                holder.password_version += 1
            elif invalidation == "consumed":
                await consume_recovery(
                    session,
                    crypto=crypto,
                    token=original.token,
                    password_hash=await hash_password(SecretStr("synthetic-replaced-password")),
                    now=datetime.now(UTC),
                )
            elif invalidation == "expired":
                challenge.created_at = datetime.now(UTC) - timedelta(hours=1)
                challenge.expires_at = datetime.now(UTC) - timedelta(seconds=1)
            else:
                challenge.revoked_at = datetime.now(UTC)
        with pytest.raises(AppError) as denied:
            async with AsyncSession(engine) as session, session.begin():
                await commit_governance_receipt(
                    session,
                    scope,
                    context,
                    crypto,
                    ManualRecoveryDecisionResult,
                    lambda: perform(session),
                )
        assert denied.value.code == ErrorCode.RESOURCE_EXPIRED
        assert calls == 1
    finally:
        await engine.dispose()
