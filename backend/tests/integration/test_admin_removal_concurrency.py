"""Real global authorization lock orders removal of the final two administrators."""

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from pydantic import SecretStr
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import (
    AdminAuditEvent,
    AuthorizationRevision,
    AuthSession,
    ExternalCallAttempt,
    Role,
    User,
)
from app.schemas.role_governance import GrantBoundaryWrite
from app.services.auth_context import verify_scope_in_transaction
from app.services.authorization import count_login_capable_super_admins
from app.services.initialization import apply_seed, initialize_admin
from app.services.role_governance import create_role, replace_grant_boundaries, replace_role_grants
from app.services.user_governance import create_account, set_account_status

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_user_governance",)


async def test_two_connections_cannot_disable_both_remaining_super_admins(
    target: MaintenanceSettings,
) -> None:
    await apply_seed(target)
    initialized = await initialize_admin(
        target,
        email="race-admin@haruka.example.test",
        password=SecretStr("synthetic-race-admin-password-2026"),
    )
    assert initialized.user_id is not None
    first_admin_id = initialized.user_id
    engine = create_maintenance_engine(target)
    contender: asyncio.Task[None] | None = None
    try:
        async with AsyncSession(engine) as setup, setup.begin():
            super_role = await setup.scalar(select(Role).where(Role.code == "super_admin"))
            assert super_role is not None
            delegate_role = await create_role(
                setup,
                actor_id=first_admin_id,
                code="removal_delegate",
                name="Removal",
                description=None,
            )
            delegated_codes = ("admin.login", "admin.user.disable", "admin.protected_role.manage")
            await replace_grant_boundaries(
                setup,
                actor_id=first_admin_id,
                role_id=super_role.id,
                expected_revision=super_role.revision,
                boundaries=tuple(
                    GrantBoundaryWrite(
                        boundary_kind="assign_permission",
                        permission_code=code,
                        data_scope="platform_metadata",
                    )
                    for code in delegated_codes
                )
                + tuple(
                    GrantBoundaryWrite(boundary_kind=kind, target_role_id=role_id)
                    for kind in ("assign_role", "manage_account_role")
                    for role_id in (super_role.id, delegate_role.role_id)
                ),
            )
            granted = await replace_role_grants(
                setup,
                actor_id=first_admin_id,
                role_id=delegate_role.role_id,
                expected_revision=delegate_role.revision,
                grants=tuple((code, "allow", "platform_metadata") for code in delegated_codes),
            )
            await replace_grant_boundaries(
                setup,
                actor_id=first_admin_id,
                role_id=delegate_role.role_id,
                expected_revision=granted.revision,
                boundaries=(
                    GrantBoundaryWrite(
                        boundary_kind="manage_account_role",
                        target_role_id=super_role.id,
                    ),
                ),
            )
            second_admin = await create_account(
                setup,
                actor_id=first_admin_id,
                email="race-second@haruka.example.test",
                display_name=None,
                role_ids=(super_role.id,),
            )
            activated = await set_account_status(
                setup,
                actor_id=first_admin_id,
                user_id=second_admin.user_id,
                expected_revision=second_admin.revision,
                status="active",
            )
            delegate = await create_account(
                setup,
                actor_id=first_admin_id,
                email="race-delegate@haruka.example.test",
                display_name=None,
                role_ids=(delegate_role.role_id,),
            )
            await set_account_status(
                setup,
                actor_id=first_admin_id,
                user_id=delegate.user_id,
                expected_revision=delegate.revision,
                status="active",
            )
            admin = await setup.get(User, first_admin_id)
            delegate_user = await setup.get(User, delegate.user_id)
            assert admin is not None and delegate_user is not None
            first_revision = admin.revision
            second_revision = activated.revision
            second_admin_id = second_admin.user_id
            actor_id = delegate.user_id
            now = datetime.now(UTC)
            actor_session = AuthSession(
                user_id=actor_id,
                audience="admin",
                transport="web",
                platform="web",
                absolute_expires_at=now + timedelta(hours=1),
                revoked_at=None,
                revoke_reason_code=None,
                security_epoch=delegate_user.security_epoch,
                audience_security_epoch=delegate_user.admin_security_epoch,
                reauthenticated_at=now,
                device_summary="synthetic-admin-web",
                last_seen_at=now,
            )
            setup.add(actor_session)
            await setup.flush()
            actor_session_id = actor_session.id
            revision = await setup.get(AuthorizationRevision, "global")
            assert revision is not None
            global_before = revision.revision
            assert await count_login_capable_super_admins(setup, now=now) == 2
            audit_before = await setup.scalar(select(func.count()).select_from(AdminAuditEvent))
            assert audit_before is not None

        async def remove(session: AsyncSession, user_id: UUID, expected: int) -> None:
            scope = await verify_scope_in_transaction(
                session,
                user_id=actor_id,
                session_id=actor_session_id,
                audience="admin",
                transport="web",
                permissions=("admin.user.disable", "admin.protected_role.manage"),
            )
            await set_account_status(
                session,
                actor_id=scope.user_id,
                user_id=user_id,
                expected_revision=expected,
                status="disabled",
            )

        async with AsyncSession(engine) as first, AsyncSession(engine) as second:
            async with first.begin():
                first_pid = await first.scalar(text("SELECT pg_backend_pid()"))
                await remove(first, first_admin_id, first_revision)
                entered = asyncio.Event()

                async def competing() -> None:
                    async with second.begin():
                        second_pid = await second.scalar(text("SELECT pg_backend_pid()"))
                        assert second_pid != first_pid
                        entered.set()
                        await remove(second, second_admin_id, second_revision)

                contender = asyncio.create_task(competing())
                await asyncio.wait_for(entered.wait(), 5)
                async with AsyncSession(engine) as observer:
                    blocked = 0
                    for _ in range(100):
                        blocked = await observer.scalar(
                            text(
                                "SELECT count(*) FROM pg_stat_activity "
                                "WHERE :pid = ANY(pg_blocking_pids(pid))"
                                " AND position('authorization_revisions' in query) > 0"
                            ),
                            {"pid": first_pid},
                        )
                        if blocked:
                            break
                        await asyncio.sleep(0.02)
                    assert blocked and not contender.done(), (
                        "Second connection must wait on the global authorization fence"
                    )
            with pytest.raises(AppError) as protected:
                await asyncio.wait_for(contender, 5)
            assert protected.value.code == ErrorCode.STATE_CONFLICT

        async with AsyncSession(engine) as check:
            first_row = await check.get(User, first_admin_id)
            second_row = await check.get(User, second_admin_id)
            assert first_row is not None and second_row is not None
            assert first_row.status == "disabled" and first_row.revision == first_revision + 1
            assert second_row.status == "active" and second_row.revision == second_revision
            revision = await check.get(AuthorizationRevision, "global")
            assert revision is not None and revision.revision == global_before + 1
            assert (
                await check.scalar(select(func.count()).select_from(AdminAuditEvent))
                == audit_before + 1
            )
            committed = (
                await check.scalars(
                    select(AdminAuditEvent).where(
                        AdminAuditEvent.action == "user.disabled",
                    )
                )
            ).all()
            assert len(committed) == 1 and committed[0].target_user_id == first_admin_id
            assert await count_login_capable_super_admins(check, now=datetime.now(UTC)) == 1
            assert await check.scalar(select(func.count()).select_from(ExternalCallAttempt)) == 0
    finally:
        if contender is not None and not contender.done():
            contender.cancel()
            await asyncio.gather(contender, return_exceptions=True)
        await engine.dispose()
