"""Controlled authorization prerequisite for a real registered test account."""

import re
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import (
    AdminAuditEvent,
    AuthorizationRevision,
    AuthSession,
    OutboxEvent,
    PermissionCatalog,
    Role,
    RolePermission,
    User,
    UserRole,
)


async def prepare_login_only_user(settings: MaintenanceSettings, *, email: str) -> UUID:
    """Limit an already verified synthetic account to client.login in its owned test schema.

    Registration and verification must happen through the real UI/API first. The
    factory creates no identity, session, content, or successful business result.
    """
    schema = settings.test_schema
    if (
        settings.app_env != "test"
        or schema is None
        or re.fullmatch(r"haruka_migration_test_[a-f0-9]{32}", schema) is None
        or re.fullmatch(r"[a-z0-9._+-]+@haruka\.example\.test", email) is None
    ):
        raise ValueError("login-only scenario requires an owned synthetic test account")
    run_id = schema.removeprefix("haruka_migration_test_")
    role_code = f"scenario_login_only_{run_id}"
    engine = create_maintenance_engine(settings)
    try:
        sessions = async_sessionmaker(engine, expire_on_commit=False)
        async with sessions() as session, session.begin():
            identity = (
                await session.execute(text("SELECT current_database(), current_user"))
            ).one()
            marker = await session.scalar(
                text(
                    "SELECT obj_description(oid, 'pg_namespace') FROM pg_namespace WHERE nspname=:schema"
                ),
                {"schema": schema},
            )
            # The first isolated run used the former marker. Only that exact
            # run-bound value and its successor are accepted during transition.
            if identity != ("haruka_test", "haruka_test_maintenance") or marker not in {
                f"haruka-b1-run:{run_id}",
                f"haruka-isolated-run:{run_id}",
            }:
                raise ValueError("login-only scenario schema ownership differs")

            global_revision = await session.scalar(
                select(AuthorizationRevision)
                .where(AuthorizationRevision.code == "global")
                .with_for_update()
            )
            user = await session.scalar(
                select(User).where(User.email_normalized == email).with_for_update()
            )
            if (
                global_revision is None
                or user is None
                or user.status != "active"
                or user.email_verified_at is None
            ):
                raise ValueError("login-only scenario needs an existing verified active user")
            if (
                await session.scalar(
                    select(AuthSession.id).where(AuthSession.user_id == user.id).limit(1)
                )
                is not None
            ):
                raise ValueError("login-only scenario must run before the account signs in")
            permission = await session.scalar(
                select(PermissionCatalog)
                .where(PermissionCatalog.code == "client.login")
                .with_for_update()
            )
            if (
                permission is None
                or not permission.enabled
                or permission.audience != "client"
                or permission.data_scope != "self"
            ):
                raise ValueError("login-only scenario permission catalog differs")

            links = (
                await session.scalars(
                    select(UserRole)
                    .where(UserRole.user_id == user.id)
                    .order_by(UserRole.role_id)
                    .with_for_update()
                )
            ).all()
            if not links:
                raise ValueError("login-only scenario has no registration role")
            roles = (
                await session.scalars(
                    select(Role)
                    .where(Role.id.in_([link.role_id for link in links]))
                    .order_by(Role.id)
                    .with_for_update()
                )
            ).all()
            if len(roles) != len(links) or any(role.protected for role in roles):
                raise ValueError("login-only scenario cannot replace protected or missing roles")

            role = await session.scalar(
                select(Role).where(Role.code == role_code).with_for_update()
            )
            if role is None:
                role = Role(
                    code=role_code,
                    name="Isolated login-only scenario",
                    description="Controlled authorization prerequisite for a synthetic test account",
                    protected=False,
                    enabled=True,
                    revision=1,
                )
                session.add(role)
                await session.flush()
                session.add(
                    RolePermission(
                        role_id=role.id,
                        permission_code="client.login",
                        effect="allow",
                        data_scope="self",
                    )
                )
                await session.flush()
            else:
                grants = (
                    await session.scalars(
                        select(RolePermission).where(RolePermission.role_id == role.id)
                    )
                ).all()
                if (
                    role.protected
                    or not role.enabled
                    or [(grant.permission_code, grant.effect, grant.data_scope) for grant in grants]
                    != [("client.login", "allow", "self")]
                ):
                    raise ValueError("login-only scenario role has unexpected grants")

            if len(links) == 1 and links[0].role_id == role.id:
                return user.id
            for link in links:
                await session.delete(link)
            session.add(UserRole(user_id=user.id, role_id=role.id))
            user.authz_version += 1
            user.updated_at = datetime.now(UTC)
            global_revision.revision += 1
            global_revision.updated_at = datetime.now(UTC)
            audit = AdminAuditEvent(
                action="seed.applied",
                actor="isolated-test-factory",
                target_type="user",
                target_id=user.id,
                target_user_id=user.id,
                target_code="login-only",
                result="committed",
                payload_schema_version=1,
                authorization_revision=global_revision.revision,
                change_summary={"scenario": "login-only"},
            )
            session.add(audit)
            await session.flush()
            session.add(
                OutboxEvent(
                    event_type="authorization.changed",
                    audit_event_id=audit.id,
                    authorization_revision=global_revision.revision,
                    status="pending",
                )
            )
            return user.id
    finally:
        await engine.dispose()
