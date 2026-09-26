"""Controlled metadata initialization, with atomic version/audit/outbox changes.

This is a maintenance-only boundary. It neither authenticates HTTP callers nor
offers arbitrary user access. No public registration or recovery endpoint exists.
"""

import asyncio
import hashlib
from dataclasses import dataclass
from uuid import UUID

from argon2 import PasswordHasher
from pydantic import SecretStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.export import canonical_json
from app.contracts.permissions import ADMIN_CODES, CLIENT_CODES, ROLE_TEMPLATES, permission_document
from app.domain.email_address import normalize_email as normalize_single_email
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

# Existing seed ledger keys are immutable compatibility data from earlier releases.
LEGACY_SEED_CODE = "b0-identity-v3"
LEGACY_SEED_DIGEST = "c34e28e2cb38b82eb6238479b63d8680a53cb97f0c06206bde99ffba2212918c"
SEED_CODE = "identity-permissions-v3"
SEED_VERSION = 3


class InitializationError(RuntimeError):
    """Safe maintenance refusal; contains neither credentials nor private row values."""


@dataclass(frozen=True)
class InitializationResult:
    changed: bool
    authorization_revision: int
    user_id: UUID | None = None


def _seed_digest() -> str:
    return hashlib.sha256(canonical_json(permission_document()).encode()).hexdigest()


def _legacy_current_digest() -> str:
    document = {**permission_document(), "catalog_version": LEGACY_SEED_CODE}
    return hashlib.sha256(canonical_json(document).encode()).hexdigest()


def _validate_seed(version: SeedVersion | None) -> None:
    if version is None:
        raise InitializationError(
            "apply the reviewed permission seed before administrator initialization"
        )
    if version.code == LEGACY_SEED_CODE and _legacy_current_digest() != LEGACY_SEED_DIGEST:
        raise InitializationError("current permission seed differs from the legacy release")
    expected_digest = LEGACY_SEED_DIGEST if version.code == LEGACY_SEED_CODE else _seed_digest()
    if version.version != SEED_VERSION or version.payload_sha256 != expected_digest:
        raise InitializationError("seed version or payload differs from the applied release")


async def _applied_seed(session: AsyncSession) -> SeedVersion | None:
    current = await session.get(SeedVersion, SEED_CODE)
    legacy = await session.get(SeedVersion, LEGACY_SEED_CODE)
    if current is not None and legacy is not None:
        raise InitializationError("duplicate seed ledgers require reviewed repair")
    return current or legacy


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
            previous = await _applied_seed(session)
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
            role = Role(
                code=code, name=code, protected=code == "super_admin", enabled=True, revision=1
            )
            session.add(role)
            await session.flush()
            for permission_code in sorted(grants):
                session.add(
                    RolePermission(
                        role_id=role.id,
                        permission_code=permission_code,
                        effect="allow",
                        data_scope="self"
                        if permission_code.startswith("client.")
                        else "platform_metadata",
                    )
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
    """Preserve display spelling; reject mailbox/header ambiguities before identity use."""
    try:
        return normalize_single_email(email)
    except ValueError:
        raise InitializationError("a valid administrator email is required") from None


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
    This entrypoint only creates the first administrator; account changes use authenticated services.
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
            _validate_seed(await _applied_seed(session))
            revision = await _revision(session)
            role = await session.scalar(
                select(Role).where(Role.code == "super_admin").with_for_update()
            )
            if role is None or not role.protected or not role.enabled:
                raise InitializationError("the protected administrator template is unavailable")
            login = await session.get(PermissionCatalog, "admin.login", with_for_update=True)
            effects = set(
                (
                    await session.execute(
                        select(RolePermission.effect, RolePermission.data_scope).where(
                            RolePermission.role_id == role.id,
                            RolePermission.permission_code == "admin.login",
                        )
                    )
                ).all()
            )
            if (
                login is None
                or not login.enabled
                or login.audience != "admin"
                or login.data_scope != "platform_metadata"
                or ("deny", "platform_metadata") in effects
                or ("allow", "platform_metadata") not in effects
                or any(scope != "platform_metadata" for _, scope in effects)
            ):
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
                password_version=1,
                security_epoch=0,
                revision=1,
                email_verified_at=None,
                locked_until=None,
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
