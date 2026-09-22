"""Controlled metadata initialization, with atomic version/audit/outbox changes.

This is a maintenance-only boundary. It neither authenticates HTTP callers nor
offers arbitrary user access. No public registration or recovery endpoint exists.
"""

import asyncio
import hashlib
import re
import unicodedata
from dataclasses import dataclass
from uuid import UUID

from argon2 import PasswordHasher
from pydantic import SecretStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.export import canonical_json
from app.contracts.permissions import ADMIN_CODES, CLIENT_CODES, ROLE_TEMPLATES, permission_document
from app.maintenance.migrations import locked_connection
from app.maintenance.schema import check_schema_connection
from app.maintenance.settings import MaintenanceSettings
from app.models import (
    AdminAuditEvent,
    AuthorizationRevision,
    AuthPolicy,
    Library,
    Menu,
    OutboxEvent,
    PermissionCatalog,
    Role,
    RolePermission,
    SeedVersion,
    User,
    UserRole,
)

SEED_CODE = "b0-identity-v2"
SEED_VERSION = 2


class InitializationError(RuntimeError):
    """Safe maintenance refusal; contains neither credentials nor private row values."""


@dataclass(frozen=True)
class InitializationResult:
    changed: bool
    authorization_revision: int
    user_id: UUID | None = None


def _seed_digest() -> str:
    return hashlib.sha256(canonical_json(permission_document()).encode()).hexdigest()


def _validate_seed(version: SeedVersion | None) -> None:
    if version is None:
        raise InitializationError(
            "apply the reviewed permission seed before administrator initialization"
        )
    if version.version != SEED_VERSION or version.payload_sha256 != _seed_digest():
        raise InitializationError("seed version or payload differs from the applied release")


async def _revision(session: AsyncSession) -> AuthorizationRevision:
    revision = await session.scalar(
        select(AuthorizationRevision)
        .where(AuthorizationRevision.code == "global")
        .with_for_update()
    )
    if revision is None:
        # The same migration advisory lock protects the initially absent parent row.
        revision = AuthorizationRevision(code="global", revision=1)
        session.add(revision)
        await session.flush()
    return revision


async def _record_change(
    session: AsyncSession, revision: AuthorizationRevision, action: str, user_id: UUID | None = None
) -> None:
    revision.revision += 1
    audit = AdminAuditEvent(
        action=action,
        actor="controlled-maintenance",
        target_user_id=user_id,
        authorization_revision=revision.revision,
    )
    session.add(audit)
    await session.flush()
    session.add(
        OutboxEvent(
            event_type="authorization.changed",
            audit_event_id=audit.id,
            authorization_revision=revision.revision,
            status="pending",
        )
    )


async def apply_seed(settings: MaintenanceSettings) -> InitializationResult:
    """Create absent release templates without rewriting existing grants or policies.

    The lock, schema validation and transaction use one physical connection. A
    same-version payload change is rejected; upgrades require a reviewed new seed.
    """
    digest = _seed_digest()
    async with locked_connection(settings) as (connection, _ownership):
        await connection.run_sync(check_schema_connection, settings.database_schema)
        await connection.commit()
        async with (
            AsyncSession(bind=connection, expire_on_commit=False) as session,
            session.begin(),
        ):
            revision = await _revision(session)
            previous = await session.get(SeedVersion, SEED_CODE)
            if previous is not None:
                _validate_seed(previous)
                return InitializationResult(False, revision.revision)
            await _create_catalogs(session)
            await _record_change(session, revision, "seed.applied")
            session.add(SeedVersion(code=SEED_CODE, version=SEED_VERSION, payload_sha256=digest))
            return InitializationResult(True, revision.revision)


async def _create_catalogs(session: AsyncSession) -> None:
    for code in sorted((*CLIENT_CODES, *ADMIN_CODES)):
        permission = await session.get(PermissionCatalog, code, with_for_update=True)
        audience = code.split(".", 1)[0]
        scope = "self" if audience == "client" else "platform_metadata"
        if permission is None:
            session.add(
                PermissionCatalog(code=code, audience=audience, data_scope=scope, enabled=True)
            )
        elif permission.audience != audience or permission.data_scope != scope:
            raise InitializationError("registered permission semantics differ from the release")
    await session.flush()
    roles: dict[str, Role] = {}
    for code, grants in sorted(ROLE_TEMPLATES.items()):
        role = await session.scalar(select(Role).where(Role.code == code).with_for_update())
        if role is None:
            role = Role(code=code, protected=code == "super_admin", enabled=True, revision=1)
            session.add(role)
            await session.flush()
            for permission_code in sorted(grants):
                session.add(
                    RolePermission(role_id=role.id, permission_code=permission_code, effect="allow")
                )
        roles[code] = role
    await session.flush()
    if await session.get(AuthPolicy, "registration", with_for_update=True) is None:
        learner = roles["learner"]
        if learner.protected or not learner.enabled:
            raise InitializationError("default registration role is not publicly assignable")
        session.add(
            AuthPolicy(
                code="registration",
                registration_mode="closed",
                default_role_id=learner.id,
                revision=1,
            )
        )
    menu = await session.scalar(select(Menu).where(Menu.code == "administration").with_for_update())
    if menu is None:
        session.add(
            Menu(
                code="administration",
                route_key="/admin",
                audience="admin",
                permission_code="admin.login",
                enabled=False,
                revision=1,
            )
        )


def normalize_email(email: str) -> tuple[str, str]:
    """Preserve display spelling; canonical identity is trimmed NFKC and casefold."""
    display = unicodedata.normalize("NFKC", email.strip())
    if (
        len(display) > 254
        or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", display)
        or any(unicodedata.category(character).startswith("C") for character in display)
    ):
        raise InitializationError("a valid administrator email is required")
    normalized = display.casefold()
    if len(normalized) > 254:
        raise InitializationError("normalized administrator email exceeds the supported length")
    return display, normalized


def _password_hash(password: SecretStr) -> str:
    value = password.get_secret_value()
    if not 12 <= len(value) <= 128:
        raise InitializationError("administrator password must contain 12 to 128 characters")
    # Pin the RFC 9106 low-memory profile explicitly; do not depend on future defaults.
    return PasswordHasher(
        time_cost=3, memory_cost=65536, parallelism=4, hash_len=32, salt_len=16
    ).hash(value)


async def initialize_admin(
    settings: MaintenanceSettings, *, email: str, password: SecretStr
) -> InitializationResult:
    """Create the first protected admin and private library, or return its exact replay.

    Refuse existing ordinary accounts and any second protected administrator.
    Recovery, role editing and last-administrator removal are not B0 capabilities.
    Password hashing happens before locks; the plaintext never enters SQL/audit/logs.
    """
    display, normalized = normalize_email(email)
    password_hash = await asyncio.to_thread(_password_hash, password)
    async with locked_connection(settings) as (connection, _ownership):
        await connection.run_sync(check_schema_connection, settings.database_schema)
        await connection.commit()
        async with (
            AsyncSession(bind=connection, expire_on_commit=False) as session,
            session.begin(),
        ):
            _validate_seed(await session.get(SeedVersion, SEED_CODE))
            revision = await _revision(session)
            role = await session.scalar(
                select(Role).where(Role.code == "super_admin").with_for_update()
            )
            if role is None or not role.protected or not role.enabled:
                raise InitializationError("the protected administrator template is unavailable")
            login = await session.get(PermissionCatalog, "admin.login", with_for_update=True)
            effects = set(
                (
                    await session.scalars(
                        select(RolePermission.effect).where(
                            RolePermission.role_id == role.id,
                            RolePermission.permission_code == "admin.login",
                        )
                    )
                ).all()
            )
            if login is None or not login.enabled or "deny" in effects or "allow" not in effects:
                raise InitializationError("the administrator template cannot log in")
            user = await session.scalar(
                select(User).where(User.email_normalized == normalized).with_for_update()
            )
            bindings = (
                await session.scalars(
                    select(UserRole).where(UserRole.role_id == role.id).with_for_update()
                )
            ).all()
            if user is not None:
                if (
                    user.status == "active"
                    and any(binding.user_id == user.id for binding in bindings)
                    and await session.scalar(
                        select(Library.id).where(Library.owner_user_id == user.id)
                    )
                    is not None
                ):
                    return InitializationResult(False, revision.revision, user.id)
                raise InitializationError(
                    "administrator initialization cannot modify an existing account"
                )
            if bindings:
                raise InitializationError("a protected administrator has already been initialized")
            user = User(
                email=display,
                email_normalized=normalized,
                password_hash=password_hash,
                status="active",
                authz_version=1,
                client_security_epoch=0,
                admin_security_epoch=0,
            )
            session.add(user)
            await session.flush()
            session.add_all(
                [Library(owner_user_id=user.id), UserRole(user_id=user.id, role_id=role.id)]
            )
            await _record_change(session, revision, "admin.created", user.id)
            return InitializationResult(True, revision.revision, user.id)
