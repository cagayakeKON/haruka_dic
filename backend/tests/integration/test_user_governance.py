"""Account writes stay inside the actor ceiling and do not mint a password."""

import os
from collections.abc import AsyncIterator
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
    AuthChallengeDelivery,
    AuthPolicy,
    AuthSession,
    Library,
    Role,
    User,
    UserExtension,
)
from app.repositories.identity import global_revision_for_update
from app.schemas.role_governance import GrantBoundaryWrite
from app.services.auth_crypto import AuthCrypto, hash_password, verify_password
from app.services.initialization import apply_seed, initialize_admin
from app.services.registration import consume_recovery, open_manual_recovery
from app.services.role_governance import (
    create_role,
    replace_grant_boundaries,
    replace_role_grants,
)
from app.services.user_governance import (
    create_account,
    decide_account_approval,
    decide_manual_recovery,
    list_account_sessions,
    list_manual_recoveries,
    read_account,
    replace_account_roles,
    revoke_account_sessions,
    set_account_status,
)

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
MIGRATIONS = Path(__file__).resolve().parents[2] / "alembic"


@pytest_asyncio.fixture
async def target() -> AsyncIterator[MaintenanceSettings]:
    configuration = os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG")
    if configuration is None:
        pytest.fail("HARUKA_MAINTENANCE_TEST_CONFIG must select the test maintenance file")
    source = load_maintenance_settings(Path(configuration))
    if source.app_env != "test":
        pytest.fail("user governance tests require haruka_test")
    schema = f"haruka_migration_test_{uuid4().hex}"
    settings = MaintenanceSettings(database_url=source.database_url, test_schema=schema)
    observer = create_maintenance_engine(source)
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        await upgrade_database(settings, MIGRATIONS)
        yield settings
    finally:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


async def test_account_ceiling_blocks_self_and_last_admin_changes(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="users-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            created = await create_account(
                session,
                actor_id=admin.user_id,
                email="Desk.User@haruka.example.test",
                display_name="服务台",
                role_ids=(),
            )
            stored = await session.get(User, created.user_id)
            assert stored is not None
            assert stored.status == "pending"
            assert stored.password_hash.startswith("$argon2")
            assert await session.scalar(
                select(Library.id).where(Library.owner_user_id == stored.id)
            )
            extension = await session.scalar(
                select(UserExtension).where(UserExtension.user_id == stored.id)
            )
            assert extension is not None and extension.display_name == "服务台"
            account_id = stored.id
            account_revision = created.revision
        with pytest.raises(AppError) as blocked_enable:
            async with AsyncSession(engine) as session, session.begin():
                await set_account_status(
                    session,
                    actor_id=admin.user_id,
                    user_id=account_id,
                    expected_revision=account_revision,
                    status="active",
                )
        assert blocked_enable.value.code == ErrorCode.PERMISSION_DENIED
        async with AsyncSession(engine) as session, session.begin():
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_admin is not None
            desk = await create_role(
                session, actor_id=admin.user_id, code="desk", name="Desk", description=None
            )
            delegate_role = await create_role(
                session,
                actor_id=admin.user_id,
                code="delegate",
                name="Delegate",
                description=None,
            )
            permission_codes = (
                "admin.user.create",
                "admin.user.enable",
                "admin.user.disable",
                "admin.user.role.assign",
                "admin.session.read",
                "admin.session.revoke",
                "admin.protected_role.manage",
            )
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=tuple(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code=code,
                        data_scope="platform_metadata",
                    )
                    for code in permission_codes
                )
                + (
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=desk.role_id),
                    GrantBoundaryWrite(
                        boundary_kind="assign_role", target_role_id=delegate_role.role_id
                    ),
                    GrantBoundaryWrite(boundary_kind="assign_role", target_role_id=super_admin.id),
                    GrantBoundaryWrite(
                        boundary_kind="manage_account_role", target_role_id=desk.role_id
                    ),
                    GrantBoundaryWrite(
                        boundary_kind="manage_account_role", target_role_id=delegate_role.role_id
                    ),
                    GrantBoundaryWrite(
                        boundary_kind="manage_account_role", target_role_id=super_admin.id
                    ),
                    GrantBoundaryWrite(boundary_kind="manage_unassigned_accounts"),
                ),
            )
            granted = await replace_role_grants(
                session,
                actor_id=admin.user_id,
                role_id=delegate_role.role_id,
                expected_revision=delegate_role.revision,
                grants=(
                    ("admin.user.disable", "allow", "platform_metadata"),
                    ("admin.protected_role.manage", "allow", "platform_metadata"),
                ),
            )
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=delegate_role.role_id,
                expected_revision=granted.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="manage_account_role", target_role_id=super_admin.id
                    ),
                ),
            )
            delegate = await create_account(
                session,
                actor_id=admin.user_id,
                email="delegate@haruka.example.test",
                display_name=None,
                role_ids=(delegate_role.role_id,),
            )
            enabled = await set_account_status(
                session,
                actor_id=admin.user_id,
                user_id=delegate.user_id,
                expected_revision=delegate.revision,
                status="active",
            )
            delegate_id = delegate.user_id
            assert enabled.revision == delegate.revision + 1
            admin_user = await session.get(User, admin.user_id)
            assert admin_user is not None
            admin_revision = admin_user.revision
        with pytest.raises(AppError) as last_admin:
            async with AsyncSession(engine) as session, session.begin():
                await set_account_status(
                    session,
                    actor_id=delegate_id,
                    user_id=admin.user_id,
                    expected_revision=admin_revision,
                    status="disabled",
                )
        assert last_admin.value.code == ErrorCode.STATE_CONFLICT
        async with AsyncSession(engine) as session, session.begin():
            admin_user = await session.get(User, admin.user_id)
            assert admin_user is not None and admin_user.status == "active"
            with pytest.raises(AppError) as self_roles:
                await replace_account_roles(
                    session,
                    actor_id=admin.user_id,
                    user_id=admin.user_id,
                    expected_revision=admin_user.revision,
                    role_ids=(),
                )
            assert self_roles.value.code == ErrorCode.PERMISSION_DENIED
            opened = await set_account_status(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=account_revision,
                status="active",
            )
            assigned = await replace_account_roles(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=opened.revision,
                role_ids=(desk.role_id,),
            )
            now = datetime.now(UTC)
            client_session = AuthSession(
                user_id=account_id,
                audience="client",
                transport="web",
                platform="web",
                absolute_expires_at=now + timedelta(hours=1),
                revoked_at=None,
                revoke_reason_code=None,
                security_epoch=0,
                audience_security_epoch=0,
                reauthenticated_at=now,
                device_summary="web",
                last_seen_at=now,
            )
            admin_session = AuthSession(
                user_id=account_id,
                audience="admin",
                transport="web",
                platform="web",
                absolute_expires_at=now + timedelta(hours=1),
                revoked_at=None,
                revoke_reason_code=None,
                security_epoch=0,
                audience_security_epoch=0,
                reauthenticated_at=now,
                device_summary="admin-web",
                last_seen_at=now,
            )
            session.add(client_session)
            session.add(admin_session)
            await session.flush()
            client_session_id = client_session.id
            admin_session_id = admin_session.id
            role_revision = assigned.revision
        async with AsyncSession(engine) as session, session.begin():
            revoked = await revoke_account_sessions(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=role_revision,
                session_id=None,
                audience="client",
                all_sessions=False,
            )
            holder = await session.get(User, account_id)
            assert holder is not None
            assert holder.client_security_epoch == 1
            assert holder.admin_security_epoch == 0
            client_row = await session.get(AuthSession, client_session_id)
            admin_row = await session.get(AuthSession, admin_session_id)
            assert client_row is not None and client_row.revoked_at is not None
            assert admin_row is not None and admin_row.revoked_at is None
            one = await revoke_account_sessions(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=revoked.revision,
                session_id=admin_session_id,
                audience=None,
                all_sessions=False,
            )
            await session.refresh(admin_row)
            assert admin_row.revoked_at is not None
            assert holder.admin_security_epoch == 0
            again = await revoke_account_sessions(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=one.revision,
                session_id=admin_session_id,
                audience=None,
                all_sessions=False,
            )
            assert again.audit_id is None
            disabled = await set_account_status(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=again.revision,
                status="disabled",
            )
            await session.refresh(holder)
            assert holder.status == "disabled"
            assert holder.security_epoch == 1
            assert disabled.audit_id is not None
            visible = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            assert visible.display_name == "服务台"
            assert visible.roles[0].code == "desk"
            sessions = await list_account_sessions(
                session, actor_id=admin.user_id, user_id=account_id
            )
            assert len(sessions) == 2
            assert all(row.revoked_at is not None for row in sessions)
            client_again = await revoke_account_sessions(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=disabled.revision,
                session_id=None,
                audience="client",
                all_sessions=False,
            )
            await session.refresh(holder)
            assert client_again.audit_id is not None
            assert client_again.affected_count == 0
            assert holder.security_epoch == 1
            assert holder.client_security_epoch == 3
            assert holder.admin_security_epoch == 1
            quiet = await revoke_account_sessions(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=client_again.revision,
                session_id=None,
                audience=None,
                all_sessions=True,
            )
            await session.refresh(holder)
            assert quiet.audit_id is not None
            assert quiet.affected_count == 0
            assert holder.security_epoch == 2
            assert holder.client_security_epoch == 4
            assert holder.admin_security_epoch == 2
    finally:
        await engine.dispose()


async def test_approval_decision_keeps_the_account_snapshot(target: MaintenanceSettings) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="approval-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_admin is not None
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=(GrantBoundaryWrite(boundary_kind="manage_unassigned_accounts"),),
            )
            created = await create_account(
                session,
                actor_id=admin.user_id,
                email="applicant@haruka.example.test",
                display_name=None,
                role_ids=(),
            )
            with pytest.raises(AppError) as ordinary:
                await decide_account_approval(
                    session,
                    actor_id=admin.user_id,
                    user_id=created.user_id,
                    expected_revision=created.revision,
                    decision="approve",
                )
            assert ordinary.value.code == ErrorCode.STATE_CONFLICT
            applicant = await session.get(User, created.user_id)
            assert applicant is not None
            applicant.approval_status = "pending"
            with pytest.raises(AppError) as skipped:
                await set_account_status(
                    session,
                    actor_id=admin.user_id,
                    user_id=created.user_id,
                    expected_revision=created.revision,
                    status="active",
                )
            assert skipped.value.code == ErrorCode.STATE_CONFLICT
            policy = await session.get(AuthPolicy, "registration")
            assert policy is not None
            policy.registration_mode = "closed"
            account_id = created.user_id
        async with AsyncSession(engine) as session, session.begin():
            current = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            assert current.approval_status == "pending" and current.status == "pending"
            held = await decide_account_approval(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=current.revision,
                decision="approve",
            )
            assert held.audit_id is not None
            waiting = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            assert waiting.approval_status == "approved" and waiting.status == "pending"
            stored = await session.get(User, account_id)
            assert stored is not None
            stored.email_verified_at = datetime.now(UTC)
            activated = await decide_account_approval(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=waiting.revision,
                decision="approve",
            )
            assert activated.audit_id is not None
            live = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            assert live.status == "active" and live.approval_status == "approved"
            policy = await session.get(AuthPolicy, "registration")
            assert policy is not None
            policy.registration_mode = "approval"
            rejected = await decide_account_approval(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                expected_revision=live.revision,
                decision="reject",
            )
            assert rejected.audit_id is not None
            policy.registration_mode = "closed"
        async with AsyncSession(engine) as session, session.begin():
            finished = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            policy = await session.get(AuthPolicy, "registration")
            assert finished.approval_status == "rejected" and finished.status == "pending"
            assert policy is not None and policy.registration_mode == "closed"
            with pytest.raises(AppError) as still_blocked:
                await set_account_status(
                    session,
                    actor_id=admin.user_id,
                    user_id=account_id,
                    expected_revision=finished.revision,
                    status="active",
                )
            assert still_blocked.value.code == ErrorCode.STATE_CONFLICT
    finally:
        await engine.dispose()


def _test_crypto() -> AuthCrypto:
    return AuthCrypto(
        signing_key=b"s" * 32,
        digest_key=b"d" * 32,
        issuer="haruka-test",
        signing_key_version="v1",
        digest_key_version="v1",
        mail_key=None,
        mail_key_version="v1",
    )


async def test_manual_recovery_issues_one_token_and_revokes_sessions(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    admin = await initialize_admin(
        target,
        email="recovery-admin@haruka.example.test",
        password=SecretStr("synthetic-admin-password-2026"),
    )
    assert admin.user_id is not None
    crypto = _test_crypto()
    engine = create_maintenance_engine(target)
    try:
        async with AsyncSession(engine) as session, session.begin():
            super_admin = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_admin is not None
            await replace_grant_boundaries(
                session,
                actor_id=admin.user_id,
                role_id=super_admin.id,
                expected_revision=super_admin.revision,
                boundaries=(GrantBoundaryWrite(boundary_kind="manage_unassigned_accounts"),),
            )
            created = await create_account(
                session,
                actor_id=admin.user_id,
                email="recover@haruka.example.test",
                display_name=None,
                role_ids=(),
            )
            account_id = created.user_id
        async with AsyncSession(engine) as session, session.begin():
            assert await global_revision_for_update(session) is not None
            policy = await session.get(AuthPolicy, "registration", with_for_update=True)
            holder = await session.get(User, account_id, with_for_update=True)
            assert holder is not None and policy is not None
            holder.status = "active"
            holder.email_verified_at = datetime.now(UTC)
            policy.recovery_mode = "manual"
            now = datetime.now(UTC)
            await open_manual_recovery(
                session, crypto=crypto, email="recover@haruka.example.test", now=now
            )
            await open_manual_recovery(
                session, crypto=crypto, email="recover@haruka.example.test", now=now
            )
            await open_manual_recovery(
                session, crypto=crypto, email="missing@haruka.example.test", now=now
            )
            count = await session.scalar(
                select(func.count())
                .select_from(AuthChallenge)
                .where(
                    AuthChallenge.user_id == account_id,
                    AuthChallenge.purpose == "manual_recovery",
                )
            )
            assert count == 1
        async with AsyncSession(engine) as session, session.begin():
            stale = await session.scalar(
                select(AuthChallenge).where(
                    AuthChallenge.user_id == account_id,
                    AuthChallenge.purpose == "manual_recovery",
                )
            )
            assert stale is not None and stale.revoked_at is None
            moment = datetime.now(UTC)
            stale.created_at = moment - timedelta(hours=2)
            stale.expires_at = moment - timedelta(minutes=1)
            await open_manual_recovery(
                session, crypto=crypto, email="recover@haruka.example.test", now=moment
            )
            replaced = (
                await session.scalars(
                    select(AuthChallenge)
                    .where(
                        AuthChallenge.user_id == account_id,
                        AuthChallenge.purpose == "manual_recovery",
                    )
                    .order_by(AuthChallenge.created_at)
                )
            ).all()
            assert len(replaced) == 2
            assert replaced[0].revoked_at is None and replaced[0].expires_at < moment
        async with AsyncSession(engine) as session, session.begin():
            current = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            listed = await list_manual_recoveries(
                session, actor_id=admin.user_id, user_id=account_id
            )
            assert [item.status for item in listed] == ["requested", "expired"]
            issued = await decide_manual_recovery(
                session,
                actor_id=admin.user_id,
                user_id=account_id,
                challenge_id=listed[0].challenge_id,
                expected_revision=current.revision,
                decision="issue",
                verification_method="in_person",
                crypto=crypto,
            )
            assert issued.token is not None and issued.status == "issued"
            token = issued.token
            with pytest.raises(AppError) as repeated:
                await decide_manual_recovery(
                    session,
                    actor_id=admin.user_id,
                    user_id=account_id,
                    challenge_id=listed[0].challenge_id,
                    expected_revision=issued.revision,
                    decision="issue",
                    verification_method="known_channel",
                    crypto=crypto,
                )
            assert repeated.value.code == ErrorCode.STATE_CONFLICT
            audits = (
                await session.scalars(
                    select(AdminAuditEvent).where(
                        AdminAuditEvent.target_id == listed[0].challenge_id
                    )
                )
            ).all()
            assert {row.action for row in audits} >= {
                "recovery.verified",
                "recovery.challenge_issued",
            }
            assert all(token not in str(row.change_summary) for row in audits)
            delivery = await session.scalar(
                select(AuthChallengeDelivery).where(
                    AuthChallengeDelivery.challenge_id == listed[0].challenge_id
                )
            )
            assert delivery is None
            now = datetime.now(UTC)
            live = AuthSession(
                user_id=account_id,
                audience="client",
                transport="web",
                platform="web",
                absolute_expires_at=now + timedelta(hours=1),
                revoked_at=None,
                revoke_reason_code=None,
                security_epoch=0,
                audience_security_epoch=0,
                reauthenticated_at=now,
                device_summary="web",
                last_seen_at=now,
            )
            session.add(live)
            await session.flush()
            password = SecretStr("replacement-password-2026")
            await consume_recovery(
                session,
                crypto=crypto,
                token=token,
                password_hash=await hash_password(password),
                now=now,
            )
            await session.refresh(live)
            stored = await session.get(User, account_id)
            assert stored is not None
            assert live.revoked_at is not None
            assert await verify_password(stored.password_hash, password)
            with pytest.raises(AppError) as spent:
                await consume_recovery(
                    session,
                    crypto=crypto,
                    token=token,
                    password_hash=await hash_password(password),
                    now=now,
                )
            assert spent.value.code == ErrorCode.RESOURCE_EXPIRED
            policy = await session.get(AuthPolicy, "registration")
            assert policy is not None
            policy.recovery_mode = "email"
        async with AsyncSession(engine) as session, session.begin():
            finished = await read_account(session, actor_id=admin.user_id, user_id=account_id)
            policy = await session.get(AuthPolicy, "registration")
            consumed = await session.scalar(
                select(func.count())
                .select_from(AuthChallenge)
                .where(
                    AuthChallenge.user_id == account_id,
                    AuthChallenge.consumed_at.is_not(None),
                )
            )
            assert finished.approval_status == "not_required"
            assert policy is not None and policy.recovery_mode == "email"
            assert consumed == 1
    finally:
        await engine.dispose()
