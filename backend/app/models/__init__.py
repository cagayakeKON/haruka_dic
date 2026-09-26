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
from app.models.identity_security import (
    AuthChallenge,
    AuthChallengeDelivery,
    AuthSession,
    UserExtension,
)
from app.models.learning_reference import (
    Card,
    CollectionItem,
    IdempotencyRecord,
    Material,
    MaterialContentBlock,
    MaterialRevision,
    MaterialSourceUnit,
    NovelChapter,
    NovelChapterBlock,
    SourceResultBinding,
)

__all__ = [
    "AdminAuditEvent",
    "AuthPolicy",
    "AuthChallenge",
    "AuthChallengeDelivery",
    "AuthSession",
    "AuthorizationRevision",
    "Base",
    "Card",
    "CollectionItem",
    "IdempotencyRecord",
    "Library",
    "Material",
    "MaterialContentBlock",
    "MaterialRevision",
    "MaterialSourceUnit",
    "Menu",
    "NovelChapter",
    "NovelChapterBlock",
    "OutboxEvent",
    "PermissionCatalog",
    "Role",
    "RolePermission",
    "SeedVersion",
    "SourceResultBinding",
    "TimestampMixin",
    "User",
    "UserExtension",
    "UserRole",
]
