"""Owner avatar edges with repository/auth substitutes, not PostgreSQL evidence."""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.scope import ScopeContext
from app.models.avatar import FileObject
from app.models.identity_security import UserExtension
from app.services import avatar as service
from app.services.avatar import _release  # pyright: ignore[reportPrivateUsage]

pytestmark = [pytest.mark.unit, pytest.mark.asyncio]


async def test_published_avatar_read_returns_only_bound_owner_bytes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    scope = ScopeContext(
        user_id=uuid4(),
        session_id=uuid4(),
        audience="client",
        transport="web",
        user_authz_version=1,
        policy_authz_version=1,
        security_epoch=0,
        absolute_expires_at=datetime.now(UTC) + timedelta(hours=1),
    )
    session = MagicMock(spec=AsyncSession)
    extension = UserExtension(user_id=scope.user_id, avatar_asset_id=uuid4())
    asset = FileObject(
        id=extension.avatar_asset_id,
        user_id=scope.user_id,
        purpose="avatar",
        retention_state="referenced",
        content=b"published JPEG",
    )
    verify = AsyncMock()
    get_extension = AsyncMock(return_value=extension)
    get_asset = AsyncMock(return_value=asset)
    monkeypatch.setattr(service, "verify_scope_in_transaction", verify)
    monkeypatch.setattr(service.profile_repository, "extension", get_extension)
    monkeypatch.setattr(service.avatar_repository, "file_object", get_asset)
    assert await service.read_avatar(session, scope) == b"published JPEG"
    verify.assert_awaited_once_with(
        session,
        user_id=scope.user_id,
        session_id=scope.session_id,
        audience="client",
        transport="web",
        permissions=("client.profile.read",),
        lock_user=False,
    )
    get_asset.assert_awaited_once_with(session, scope.user_id, asset.id, lock=False)


async def test_releasing_unbound_avatar_does_not_query_private_asset(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    get_asset = AsyncMock()
    monkeypatch.setattr(service.avatar_repository, "file_object", get_asset)
    await _release(MagicMock(spec=AsyncSession), uuid4(), None)
    get_asset.assert_not_awaited()
