"""Complete nonempty model registry, imported offline without creating connections."""

from app.models.authorization import (
    AdminAuditEvent,
    AuthorizationRevision,
    AuthPolicy,
    Menu,
    OutboxEvent,
    PermissionCatalog,
    Role,
    RolePermission,
    SeedVersion,
    UserRole,
)
from app.models.base import Base, TimestampMixin
from app.models.identity import Library, User

__all__ = [
    "AdminAuditEvent",
    "AuthPolicy",
    "AuthorizationRevision",
    "Base",
    "Library",
    "Menu",
    "OutboxEvent",
    "PermissionCatalog",
    "Role",
    "RolePermission",
    "SeedVersion",
    "TimestampMixin",
    "User",
    "UserRole",
]
