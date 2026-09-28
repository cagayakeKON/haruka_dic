"""Only registered cache resources may be validated; language choices match profile rules."""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.client_cache import (
    CacheValidationItem,
    CacheValidationRequest,
    CacheValidationResult,
)
from app.services.client_cache import CacheRegistry
from app.services.language_capabilities import read_catalogue

pytestmark = pytest.mark.unit


def test_empty_cache_batch_has_a_bounded_protocol_version() -> None:
    assert CacheValidationRequest.model_validate({"protocol_version": 1, "items": []}).items == []
    with pytest.raises(ValidationError):
        CacheValidationRequest.model_validate({"protocol_version": 2, "items": []})


class _SyntheticItem(CacheValidationItem):
    resource_id: UUID


@pytest.mark.asyncio
async def test_registry_dispatches_only_an_exact_schema_and_rejects_unknown_kind() -> None:
    registry = CacheRegistry()
    account = uuid4()
    scope = ScopeContext(
        user_id=account,
        session_id=uuid4(),
        audience="client",
        transport="native",
        user_authz_version=1,
        policy_authz_version=1,
        security_epoch=0,
        absolute_expires_at=datetime.now(UTC) + timedelta(hours=1),
    )
    called: list[UUID] = []

    async def synthetic_handler(
        current: ScopeContext, item: CacheValidationItem
    ) -> CacheValidationResult:
        assert isinstance(item, _SyntheticItem)
        assert current.user_id == account
        called.append(item.resource_id)
        return CacheValidationResult(request_ref=item.request_ref, state="unavailable")

    registry.register(
        kind="synthetic",
        projection="summary.v1",
        action="read",
        schema=_SyntheticItem,
        handler=synthetic_handler,
    )
    reference = str(uuid4())
    resource = str(uuid4())
    item = {
        "request_ref": reference,
        "kind": "synthetic",
        "projection": "summary.v1",
        "action": "read",
        "resource_id": resource,
    }
    result = await registry.validate(scope, [item])
    assert result[0].state == "unavailable" and result[0].offline_grant is None
    assert called == [UUID(resource)]
    with pytest.raises(AppError) as unknown:
        await registry.validate(scope, [{**item, "kind": "unregistered"}])
    assert unknown.value.code == ErrorCode.INPUT_INVALID
    with pytest.raises(AppError):
        await registry.validate(scope, [{**item, "user_id": str(account)}])
    with pytest.raises(AppError):
        await registry.validate(scope, [item, item])
    assert called == [UUID(resource)]


def test_language_catalogue_advertises_only_published_capabilities() -> None:
    catalogue = read_catalogue()
    assert catalogue.version == 1
    assert {entry.code for entry in catalogue.languages if entry.learning_supported} == {"ja", "en"}
    assert {entry.code for entry in catalogue.languages if entry.explanation_supported} == {
        "zh-Hans",
        "ja",
        "en",
    }
