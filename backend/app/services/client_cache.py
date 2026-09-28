"""Closed cache projection registry; no business projection is registered in B2a."""

from collections.abc import Awaitable, Callable
from typing import cast
from uuid import UUID

from pydantic import ValidationError

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.schemas.client_cache import CacheValidationItem, CacheValidationResult

type CacheHandler = Callable[[ScopeContext, CacheValidationItem], Awaitable[CacheValidationResult]]


class CacheRegistry:
    def __init__(self) -> None:
        self._entries: dict[
            tuple[str, str, str], tuple[type[CacheValidationItem], CacheHandler]
        ] = {}

    def register(
        self,
        *,
        kind: str,
        projection: str,
        action: str,
        schema: type[CacheValidationItem],
        handler: CacheHandler,
    ) -> None:
        key = (kind, projection, action)
        if key in self._entries or not all(key):
            raise ValueError("cache projection registration is duplicate or incomplete")
        self._entries[key] = (schema, handler)

    async def validate(
        self, scope: ScopeContext, raw_items: list[object]
    ) -> list[CacheValidationResult]:
        if len(raw_items) > 50:
            raise AppError(ErrorCode.INPUT_INVALID)
        parsed: list[tuple[CacheValidationItem, CacheHandler]] = []
        seen: set[UUID] = set()
        for raw in raw_items:
            if not isinstance(raw, dict):
                raise AppError(ErrorCode.INPUT_INVALID)
            untyped_fields = cast(dict[object, object], raw)
            if any(not isinstance(key, str) for key in untyped_fields):
                raise AppError(ErrorCode.INPUT_INVALID)
            fields = cast(dict[str, object], raw)
            kind = fields.get("kind")
            projection = fields.get("projection")
            action = fields.get("action")
            if (
                not isinstance(kind, str)
                or not isinstance(projection, str)
                or not isinstance(action, str)
            ):
                raise AppError(ErrorCode.INPUT_INVALID)
            entry = self._entries.get((kind, projection, action))
            if entry is None:
                raise AppError(ErrorCode.INPUT_INVALID)
            schema, handler = entry
            try:
                item = schema.model_validate(raw)
            except ValidationError:
                raise AppError(ErrorCode.INPUT_INVALID) from None
            if item.request_ref in seen or (item.kind, item.projection, item.action) != (
                kind,
                projection,
                action,
            ):
                raise AppError(ErrorCode.INPUT_INVALID)
            seen.add(item.request_ref)
            parsed.append((item, handler))
        results: list[CacheValidationResult] = []
        for item, handler in parsed:
            result = await handler(scope, item)
            if result.request_ref != item.request_ref:
                raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
            results.append(result)
        return results


CLIENT_CACHE_REGISTRY = CacheRegistry()
