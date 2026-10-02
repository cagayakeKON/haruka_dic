"""Actual ASGI governance routing with identity and persistence at explicit test boundaries."""

from base64 import urlsafe_b64encode
from collections.abc import Awaitable, Callable, Iterator
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from typing import cast
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from pydantic import BaseModel, SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import governance_writes
from app.api import menu_governance as menus
from app.api import role_governance as roles
from app.api import user_governance as users
from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.core.logging import SafeJsonFormatter
from app.core.settings import Settings
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.main import create_app
from app.schemas.auth import NavigationRead
from app.schemas.menu_governance import MenuCatalogRead, MenuWriteResult
from app.schemas.role_governance import AuthorizationWriteResult, RoleRead
from app.schemas.user_governance import AccountRead, AccountWriteResult
from app.services.auth_crypto import AuthCrypto
from app.services.governance_receipts import GovernanceReceiptContext


@pytest.fixture
def receipts(harness: "Harness") -> Iterator[list[GovernanceReceiptContext]]:
    contexts: list[GovernanceReceiptContext] = []

    async def commit(
        session: AsyncSession,
        scope: ScopeContext,
        context: GovernanceReceiptContext,
        crypto: AuthCrypto,
        result_type: type[BaseModel],
        operation: Callable[[], Awaitable[BaseModel]],
    ) -> BaseModel:
        assert scope == harness.scope
        contexts.append(context)
        value = await operation()
        return result_type.model_validate(value.model_dump())

    with patch.object(governance_writes, "commit_governance_receipt", new=commit):
        yield contexts


@dataclass
class Harness:
    client: TestClient
    runtime: Runtime
    scope: ScopeContext
    session: AsyncMock
    csrf: str

    def headers(self) -> dict[str, str]:
        return {
            "origin": self.runtime.settings.public_base_url,
            "x-csrf-token": self.csrf,
            "idempotency-key": "synthetic-intent-key-0001",
        }


@pytest.fixture
def harness() -> Iterator[Harness]:
    secret = SecretStr(urlsafe_b64encode(b"k" * 32).decode())
    settings = Settings(
        app_env="test",
        instance_id="haruka-test-routes",
        public_base_url="http://127.0.0.1:8080",
        auth_signing_key=secret,
        auth_digest_key=secret,
    )
    session = AsyncMock(spec=AsyncSession)
    session.__aenter__.return_value = session
    resources = MagicMock(spec=Resources)
    resources.database = MagicMock()
    resources.database.sessions.return_value = session
    resources.cache = MagicMock()
    resources.cache.client.get = AsyncMock()
    current = ScopeContext(
        uuid4(), uuid4(), "admin", "web", 1, 1, 1, datetime.now(UTC) + timedelta(hours=1)
    )
    csrf = "a" * 43
    resources.cache.client.get.return_value = AuthCrypto.from_settings(settings).digest(
        "csrf", csrf
    )
    runtime = Runtime(settings, resources=cast(Resources, resources), schema_compatible=True)
    app = create_app(settings)
    app.state.runtime = runtime
    client = TestClient(app, raise_server_exceptions=False)
    try:
        yield Harness(client, runtime, current, session, csrf)
    finally:
        client.close()


def role_read(identifier: UUID) -> RoleRead:
    return RoleRead(
        id=identifier,
        code="operator",
        name="Operator",
        description=None,
        protected=False,
        enabled=True,
        revision=3,
        grants=[],
        parents=[],
        member_count=2,
    )


@pytest.mark.parametrize(
    "header,code",
    [
        ({}, "AUTH_REQUIRED"),
        ({"authorization": "Bearer synthetic-native-token"}, "SESSION_INVALID"),
        ({"cookie": "haruka_client_session=" + "a" * 43}, "AUTH_REQUIRED"),
    ],
)
def test_admin_role_reads_reject_anonymous_native_and_client_cookie_before_service(
    harness: Harness, header: dict[str, str], code: str
) -> None:
    with patch.object(roles.role_governance, "list_roles", new_callable=AsyncMock) as service:
        reply = harness.client.get("/api/v1/admin/roles", headers=header)
    assert reply.json()["error"]["code"] == code
    service.assert_not_awaited()


@pytest.mark.parametrize("failure", ["origin", "token", "csrf-store", "native"])
def test_role_creation_csrf_failures_never_open_governance_write(
    harness: Harness, failure: str
) -> None:
    headers = harness.headers()
    if failure == "origin":
        headers["origin"] = "https://untrusted.example"
    if failure == "token":
        headers["x-csrf-token"] = "invalid"
    if failure == "csrf-store":
        assert harness.runtime.resources is not None
        cast(AsyncMock, harness.runtime.resources.cache.client.get).return_value = b"mismatch"
    scope = (
        harness.scope
        if failure != "native"
        else ScopeContext(
            harness.scope.user_id,
            harness.scope.session_id,
            "admin",
            "native",
            1,
            1,
            1,
            harness.scope.absolute_expires_at,
        )
    )
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=scope),
        patch.object(roles, "governance_write", new_callable=AsyncMock) as write,
        patch.object(roles.role_governance, "create_role", new_callable=AsyncMock) as service,
    ):
        reply = harness.client.post(
            "/api/v1/admin/roles", json={"code": "operator", "name": "Operator"}, headers=headers
        )
    assert reply.status_code == 403 and reply.json()["error"]["code"] == "CSRF_FAILED"
    write.assert_not_awaited()
    service.assert_not_awaited()


@pytest.mark.parametrize("cursor", ["BAD", "a/b", "x" * 65])
def test_role_page_cursor_rejects_invalid_codes_before_identity_and_service(
    harness: Harness, cursor: str
) -> None:
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock) as identity,
        patch.object(roles.role_governance, "list_roles", new_callable=AsyncMock) as service,
    ):
        reply = harness.client.get("/api/v1/admin/roles", params={"cursor": cursor})
    assert reply.status_code == 422 and reply.json()["error"]["code"] == "INPUT_INVALID"
    identity.assert_not_awaited()
    service.assert_not_awaited()


def test_role_page_cursor_and_metadata_are_bound_to_current_admin(harness: Harness) -> None:
    value = role_read(uuid4())
    with (
        patch.object(
            roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope
        ) as identity,
        patch.object(
            roles.role_governance,
            "list_roles",
            new_callable=AsyncMock,
            return_value=([value], True),
        ) as service,
    ):
        reply = harness.client.get("/api/v1/admin/roles", params={"cursor": "alpha", "limit": 1})
    assert reply.status_code == 200 and reply.json()["meta"]["next_cursor"] == "operator"
    assert reply.json()["data"][0]["id"] == str(value.id)
    assert identity.await_args is not None and identity.await_args.kwargs == {
        "audience": "admin",
        "permissions": ("admin.role.read",),
    }
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "limit": 1,
        "after_code": "alpha",
    }


def test_account_page_normalizes_email_cursor_and_preserves_query(harness: Harness) -> None:
    value = AccountRead(
        user_id=uuid4(),
        email="visible@example.com",
        display_name=None,
        status="active",
        email_verified=True,
        locked=False,
        approval_status="approved",
        audiences=["client"],
        roles=[],
        live_session_count=1,
        revision=3,
    )
    with (
        patch.object(users, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            users.user_governance,
            "list_accounts",
            new_callable=AsyncMock,
            return_value=([value], "visible@example.com"),
        ) as service,
    ):
        reply = harness.client.get(
            "/api/v1/admin/users",
            params={"cursor": "START@example.com", "limit": 1, "query": "Visible"},
        )
    assert reply.status_code == 200 and reply.json()["meta"]["has_more"] is True
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "limit": 1,
        "after_email": "start@example.com",
        "query": "Visible",
    }
    assert "password" not in reply.text and "security_epoch" not in reply.text


@pytest.mark.parametrize("family", ["role", "account", "menu"])
def test_resource_loss_after_identity_never_reads_business_data(
    harness: Harness, family: str
) -> None:
    module = {"role": roles, "account": users, "menu": menus}[family]
    paths = {
        "role": "/api/v1/admin/roles",
        "account": "/api/v1/admin/users",
        "menu": "/api/v1/admin/menus",
    }

    async def identity(*args: object, **kwargs: object) -> ScopeContext:
        harness.runtime.resources = None
        return harness.scope

    with (
        patch.object(module, "require_scope", new=identity),
        patch.object(roles.role_governance, "list_roles", new_callable=AsyncMock) as role_service,
        patch.object(
            users.user_governance, "list_accounts", new_callable=AsyncMock
        ) as account_service,
        patch.object(menus.menu_governance, "list_menus", new_callable=AsyncMock) as menu_service,
    ):
        reply = harness.client.get(paths[family])
    assert reply.status_code == 503 and reply.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    role_service.assert_not_awaited()
    account_service.assert_not_awaited()
    menu_service.assert_not_awaited()


@pytest.mark.parametrize("status", ["active", "disabled"])
def test_status_action_selects_exact_permission_and_current_actor(
    harness: Harness, status: str
) -> None:
    target = uuid4()
    value = AccountWriteResult(
        user_id=target, revision=4, authorization_revision=8, audit_id=uuid4(), affected_count=1
    )
    contexts: list[GovernanceReceiptContext] = []

    async def receipt(
        session: AsyncSession,
        scope: ScopeContext,
        context: GovernanceReceiptContext,
        crypto: AuthCrypto,
        result_type: type[BaseModel],
        operation: Callable[[], Awaitable[BaseModel]],
    ) -> BaseModel:
        contexts.append(context)
        assert scope == harness.scope
        return await operation()

    with (
        patch.object(users, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(governance_writes, "commit_governance_receipt", new=receipt),
        patch.object(
            users.user_governance, "set_account_status", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/users/{target}/status",
            json={"expected_revision": 3, "status": status},
            headers=harness.headers(),
        )
    assert reply.status_code == 200 and reply.json()["data"]["revision"] == 4
    assert contexts[0].permissions == (
        "admin.user.enable" if status == "active" else "admin.user.disable",
    )
    assert contexts[0].user_id == target
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "user_id": target,
        "expected_revision": 3,
        "status": status,
    }


def test_invalid_idempotency_key_blocks_role_write_after_valid_csrf(harness: Harness) -> None:
    headers = harness.headers()
    headers["idempotency-key"] = "short"
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(roles.role_governance, "create_role", new_callable=AsyncMock) as service,
        patch.object(
            governance_writes, "commit_governance_receipt", new_callable=AsyncMock
        ) as receipt,
    ):
        reply = harness.client.post(
            "/api/v1/admin/roles", json={"code": "operator", "name": "Operator"}, headers=headers
        )
    assert reply.json()["error"]["code"] == "INPUT_INVALID"
    service.assert_not_awaited()
    receipt.assert_not_awaited()


def test_menu_preview_requires_both_actions_and_preserves_target_audience(harness: Harness) -> None:
    target = uuid4()
    navigation = [NavigationRead(key="client_library", route_key="library", title="Library")]
    with (
        patch.object(
            menus, "require_scope", new_callable=AsyncMock, return_value=harness.scope
        ) as identity,
        patch.object(
            menus.menu_governance,
            "preview_navigation",
            new_callable=AsyncMock,
            return_value=navigation,
        ) as service,
    ):
        reply = harness.client.post(
            "/api/v1/admin/menus/preview", json={"user_id": str(target), "audience": "client"}
        )
    assert (
        reply.status_code == 200 and reply.json()["data"]["navigation"][0]["route_key"] == "library"
    )
    assert identity.await_args is not None and identity.await_args.kwargs["permissions"] == (
        "admin.menu.read",
        "admin.user.read",
    )
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "user_id": target,
        "audience": "client",
    }


def test_menu_preview_permission_denial_never_invokes_target_service(harness: Harness) -> None:
    with (
        patch.object(
            menus,
            "require_scope",
            new_callable=AsyncMock,
            side_effect=AppError(ErrorCode.PERMISSION_DENIED),
        ),
        patch.object(
            menus.menu_governance, "preview_navigation", new_callable=AsyncMock
        ) as service,
    ):
        reply = harness.client.post(
            "/api/v1/admin/menus/preview", json={"user_id": str(uuid4()), "audience": "admin"}
        )
    assert reply.status_code == 403 and reply.json()["error"]["code"] == "PERMISSION_DENIED"
    service.assert_not_awaited()


def test_create_role_receipt_binds_admin_actor_and_role_metadata(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    value = AuthorizationWriteResult(
        role_id=uuid4(), revision=1, authorization_revision=8, audit_id=uuid4(), affected_count=0
    )
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            roles.role_governance, "create_role", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            "/api/v1/admin/roles",
            json={"code": "operator", "name": "Operator", "description": "synthetic description"},
            headers=harness.headers(),
        )
    assert reply.status_code == 200 and reply.json()["data"]["role_id"] == str(value.role_id)
    assert receipts[0].permissions == ("admin.role.create",) and receipts[0].role_id is None
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "code": "operator",
        "name": "Operator",
        "description": "synthetic description",
    }


@pytest.mark.parametrize("kind", ["grants", "inheritance", "grant-boundaries"])
def test_role_relation_write_preserves_exact_effect_parent_and_scope_contract(
    harness: Harness, receipts: list[GovernanceReceiptContext], kind: str
) -> None:
    target, parent = uuid4(), uuid4()
    value = AuthorizationWriteResult(
        role_id=target, revision=4, authorization_revision=8, audit_id=uuid4(), affected_count=1
    )
    bodies: dict[str, dict[str, object]] = {
        "grants": {
            "expected_revision": 3,
            "grants": [{"permission_code": "client.login", "effect": "deny", "data_scope": "self"}],
        },
        "inheritance": {"expected_revision": 3, "parent_role_ids": [str(parent)]},
        "grant-boundaries": {
            "expected_revision": 3,
            "boundaries": [
                {
                    "boundary_kind": "assign_permission",
                    "permission_code": "client.login",
                    "data_scope": "self",
                }
            ],
        },
    }
    names = {
        "grants": "replace_role_grants",
        "inheritance": "replace_role_parents",
        "grant-boundaries": "replace_grant_boundaries",
    }
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            roles.role_governance, names[kind], new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/roles/{target}/{kind}", json=bodies[kind], headers=harness.headers()
        )
    assert reply.status_code == 200 and receipts[0].role_id == target
    assert service.await_args is not None
    args = service.await_args.kwargs
    assert (
        args["actor_id"] == harness.scope.user_id
        and args["expected_revision"] == 3
        and args["role_id"] == target
    )
    if kind == "grants":
        assert args["grants"] == (("client.login", "deny", "self"),)
    elif kind == "inheritance":
        assert args["parent_role_ids"] == (parent,)
    else:
        assert args["boundaries"][0].model_dump() == {
            "boundary_kind": "assign_permission",
            "target_role_id": None,
            "permission_code": "client.login",
            "data_scope": "self",
        }


def test_role_delete_receipt_marks_deleted_target_for_safe_replay(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    target = uuid4()
    value = AuthorizationWriteResult(
        role_id=target, revision=3, authorization_revision=8, audit_id=uuid4(), affected_count=0
    )
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            roles.role_governance, "delete_role", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/roles/{target}/deletion",
            json={"expected_revision": 3},
            headers=harness.headers(),
        )
    assert reply.status_code == 200 and receipts[0].deleted_role and receipts[0].role_id == target
    assert (
        service.await_args is not None
        and service.await_args.kwargs["actor_id"] == harness.scope.user_id
    )


def test_account_create_passes_optional_profile_and_tuple_role_ids_without_password(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    target, parent = uuid4(), uuid4()
    value = AccountWriteResult(
        user_id=target, revision=1, authorization_revision=8, audit_id=uuid4(), affected_count=1
    )
    with (
        patch.object(users, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            users.user_governance, "create_account", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            "/api/v1/admin/users",
            json={
                "email": "synthetic@example.com",
                "display_name": "  Visible  ",
                "role_ids": [str(parent)],
            },
            headers=harness.headers(),
        )
    assert reply.status_code == 200 and "password" not in reply.text
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "email": "synthetic@example.com",
        "display_name": "Visible",
        "role_ids": (parent,),
    }
    assert receipts[0].permissions == ("admin.user.create",)


def test_account_role_replacement_binds_target_current_actor_and_revision(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    target, parent = uuid4(), uuid4()
    value = AccountWriteResult(
        user_id=target, revision=4, authorization_revision=8, audit_id=uuid4(), affected_count=1
    )
    with (
        patch.object(users, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            users.user_governance,
            "replace_account_roles",
            new_callable=AsyncMock,
            return_value=value,
        ) as service,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/users/{target}/roles",
            json={"expected_revision": 3, "role_ids": [str(parent)]},
            headers=harness.headers(),
        )
    assert (
        reply.status_code == 200
        and receipts[0].user_id == target
        and receipts[0].permissions == ("admin.user.role.assign",)
    )
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "user_id": target,
        "expected_revision": 3,
        "role_ids": (parent,),
    }


def test_menu_create_dto_cannot_introduce_route_key_and_binds_command(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    value = MenuWriteResult(authorization_revision=8, audit_id=uuid4(), affected_count=1, menus=[])
    with (
        patch.object(menus, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            menus.menu_governance, "create_group", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        denied = harness.client.post(
            "/api/v1/admin/menus",
            json={"code": "group", "audience": "client", "title": "Group", "route_key": "admin"},
            headers=harness.headers(),
        )
        assert denied.status_code == 422
        service.assert_not_awaited()
        reply = harness.client.post(
            "/api/v1/admin/menus",
            json={"code": "group", "audience": "client", "title": "  Group  "},
            headers=harness.headers(),
        )
    assert reply.status_code == 200 and receipts[0].permissions == ("admin.menu.update",)
    assert (
        service.await_args is not None
        and service.await_args.kwargs["actor_id"] == harness.scope.user_id
        and service.await_args.kwargs["command"].title == "Group"
    )


def test_menu_layout_preserves_any_permission_mode_and_revision(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    target = uuid4()
    value = MenuWriteResult(authorization_revision=8, audit_id=uuid4(), affected_count=1, menus=[])
    body = {
        "items": [
            {
                "menu_id": str(target),
                "expected_revision": 3,
                "title": "Group",
                "sort_order": 2,
                "enabled": False,
                "permission_match": "any",
                "permission_codes": ["client.login"],
            }
        ]
    }
    with (
        patch.object(menus, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            menus.menu_governance, "replace_layout", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            "/api/v1/admin/menus/layout", json=body, headers=harness.headers()
        )
    assert reply.status_code == 200 and receipts[0].permissions == ("admin.menu.update",)
    assert service.await_args is not None
    item = service.await_args.kwargs["items"][0]
    assert (
        item.menu_id == target
        and item.expected_revision == 3
        and item.permission_match == "any"
        and item.enabled is False
    )


def test_menu_delete_cannot_confuse_menu_target_with_role_target(
    harness: Harness, receipts: list[GovernanceReceiptContext]
) -> None:
    target = uuid4()
    value = MenuWriteResult(authorization_revision=8, audit_id=uuid4(), affected_count=1, menus=[])
    with (
        patch.object(menus, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            menus.menu_governance, "delete_group", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/menus/{target}/deletion",
            json={"expected_revision": 3},
            headers=harness.headers(),
        )
    assert (
        reply.status_code == 200
        and receipts[0].role_id is None
        and receipts[0].deleted_role is False
    )
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id,
        "menu_id": target,
        "expected_revision": 3,
    }


def test_menu_catalog_read_returns_registered_choices_and_requires_current_action(
    harness: Harness,
) -> None:
    value = MenuCatalogRead(pages=[], icons=["book"], permission_codes=[])
    with (
        patch.object(
            menus, "require_scope", new_callable=AsyncMock, return_value=harness.scope
        ) as identity,
        patch.object(
            menus.menu_governance, "read_catalog", new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.get("/api/v1/admin/menu-catalog")
    assert reply.status_code == 200 and reply.json()["data"]["icons"] == ["book"]
    assert identity.await_args is not None and identity.await_args.kwargs["permissions"] == (
        "admin.menu.read",
    )
    assert service.await_args is not None and service.await_args.kwargs == {
        "actor_id": harness.scope.user_id
    }


def test_invalid_role_service_return_is_rejected_and_formatted_logs_hide_body(
    harness: Harness,
    caplog: pytest.LogCaptureFixture,
) -> None:
    identifier = uuid4()
    body = role_read(identifier).model_dump() | {"provider_key": "synthetic-sensitive-value"}
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(roles.role_governance, "read_role", new_callable=AsyncMock, return_value=body),
    ):
        reply = harness.client.get(f"/api/v1/admin/roles/{identifier}")
    assert reply.status_code == 500 and reply.json()["error"]["code"] == "INTERNAL_ERROR"
    assert "synthetic-sensitive-value" not in reply.text
    formatter = SafeJsonFormatter(harness.runtime.settings, "api")
    assert caplog.records
    assert all(
        "synthetic-sensitive-value" not in formatter.format(record) for record in caplog.records
    )


@pytest.mark.parametrize(
    "failure",
    ["runtime-not-ready", "cross-origin", "invalid-schema", "quota", "foreign-job", "revoked"],
)
def test_job_events_reject_before_delivering_any_unauthorized_snapshot(
    harness: Harness, failure: str
) -> None:
    from starlette.websockets import WebSocketDisconnect

    from app.api import model_settings as models
    from app.schemas.model_settings import ModelLimits

    harness.scope = replace(harness.scope, audience="client")
    identifier = uuid4()
    if failure == "runtime-not-ready":
        harness.runtime.schema_compatible = False
    denial = AppError(ErrorCode.PERMISSION_DENIED)
    with (
        patch.object(
            models,
            "require_scope",
            new_callable=AsyncMock,
            return_value=harness.scope,
            side_effect=denial if failure == "revoked" else None,
        ),
        patch.object(
            models.config,
            "effective_limits",
            new_callable=AsyncMock,
            return_value=ModelLimits(websocket_max_jobs=0 if failure == "quota" else 100),
        ),
        patch.object(
            models.tasks,
            "load_job",
            new_callable=AsyncMock,
            side_effect=AppError(ErrorCode.RESOURCE_NOT_FOUND)
            if failure == "foreign-job"
            else None,
        ) as load,
        patch.object(models.tasks, "read_job", new_callable=AsyncMock) as read,
        pytest.raises(WebSocketDisconnect) as closed,
    ):
        headers = {
            "cookie": "haruka_client_session=" + "a" * 43,
            "origin": "https://foreign.invalid"
            if failure == "cross-origin"
            else harness.runtime.settings.public_base_url,
        }
        with harness.client.websocket_connect("/api/v1/jobs/events", headers=headers) as socket:
            socket.send_json(
                {
                    "schema_version": True if failure == "invalid-schema" else 1,
                    "type": "subscribe",
                    "job_ids": [str(identifier)],
                }
            )
            socket.receive_json()
    assert closed.value.code == (1013 if failure == "runtime-not-ready" else 1008)
    read.assert_not_awaited()
    if failure in {"runtime-not-ready", "cross-origin", "invalid-schema", "quota", "revoked"}:
        load.assert_not_awaited()


@pytest.mark.parametrize("terminal", ["succeeded", "failed", "cancelled"])
def test_job_events_emit_typed_terminal_delta_after_current_permission_recheck(
    harness: Harness, terminal: str
) -> None:
    from app.api import model_settings as models
    from app.schemas.model_settings import JobRead, ModelLimits

    harness.scope = replace(harness.scope, audience="client")
    identifier = uuid4()
    initial = JobRead(
        id=identifier,
        run_id=uuid4(),
        credential_id=uuid4(),
        state="running",
        revision=1,
        generation=1,
        sequence=1,
        can_cancel=True,
        can_retry=False,
        requires_new_attempt_confirmation=False,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    final = initial.model_copy(
        update={"state": terminal, "revision": 2, "sequence": 2, "can_cancel": False}
    )
    with (
        patch.object(
            models, "require_scope", new_callable=AsyncMock, return_value=harness.scope
        ) as identity,
        patch.object(
            models.config, "effective_limits", new_callable=AsyncMock, return_value=ModelLimits()
        ),
        patch.object(models.tasks, "load_job", new_callable=AsyncMock) as load,
        patch.object(
            models.tasks, "read_job", new_callable=AsyncMock, side_effect=[initial, final]
        ) as read,
        harness.client.websocket_connect("/api/v1/jobs/events") as socket,
    ):
        socket.send_json({"schema_version": 1, "type": "subscribe", "job_ids": [str(identifier)]})
        first = socket.receive_json()
        socket.send_json({"schema_version": 1, "type": "subscribe", "job_ids": []})
        second = socket.receive_json()
    assert first["type"] == "snapshot" and first["payload"]["state"] == "running"
    assert (
        second["type"] == ("completed" if terminal == "succeeded" else terminal)
        and second["sequence"] == 2
    )
    assert second["payload"]["state"] == terminal
    assert read.await_count == 2 and load.await_count == 1
    assert identity.await_count >= 6
    for call in identity.await_args_list:
        assert call.kwargs == {
            "audience": "client",
            "permissions": ("client.job.read", "client.credential.read"),
        }


@pytest.mark.parametrize("kind", ["account", "ceilings", "recoveries", "sessions"])
@pytest.mark.parametrize("outcome", ["success", "permission", "resource-loss", "invalid-return"])
def test_account_metadata_reads_enforce_action_and_strict_private_projection(
    harness: Harness, kind: str, outcome: str
) -> None:
    from app.schemas.user_governance import (
        AccountCeilingsRead,
        AccountSessionRead,
        ManualRecoveryRead,
    )

    target = uuid4()
    now = datetime.now(UTC)
    path = {
        "account": f"/api/v1/admin/users/{target}",
        "ceilings": "/api/v1/admin/account-ceilings",
        "recoveries": f"/api/v1/admin/users/{target}/recovery-requests",
        "sessions": f"/api/v1/admin/users/{target}/sessions",
    }[kind]
    function = {
        "account": "read_account",
        "ceilings": "read_account_ceilings",
        "recoveries": "list_manual_recoveries",
        "sessions": "list_account_sessions",
    }[kind]
    value: BaseModel | list[BaseModel]
    if kind == "account":
        value = AccountRead(
            user_id=target,
            email="visible@example.com",
            display_name=None,
            status="active",
            email_verified=True,
            locked=False,
            approval_status="approved",
            audiences=["client"],
            roles=[],
            live_session_count=1,
            revision=2,
        )
    elif kind == "ceilings":
        value = AccountCeilingsRead(
            assign_role_ids=[target], manage_account_role_ids=[], manage_unassigned_accounts=False
        )
    elif kind == "recoveries":
        value = [
            ManualRecoveryRead(
                challenge_id=uuid4(),
                status="requested",
                created_at=now,
                expires_at=now + timedelta(hours=1),
            )
        ]
    else:
        value = [
            AccountSessionRead(
                session_id=uuid4(),
                audience="client",
                transport="web",
                platform="web",
                device_summary=None,
                created_at=now,
                last_seen_at=now,
                absolute_expires_at=now + timedelta(hours=1),
                revoked_at=None,
            )
        ]
    returned: object = value
    if outcome == "invalid-return":
        returned = (
            [item.model_dump() | {"refresh_token": "synthetic-sensitive-value"} for item in value]
            if isinstance(value, list)
            else value.model_dump() | {"password_hash": "synthetic-sensitive-value"}
        )

    async def identity(*_args: object, **_kwargs: object) -> ScopeContext:
        if outcome == "permission":
            raise AppError(ErrorCode.PERMISSION_DENIED)
        if outcome == "resource-loss":
            harness.runtime.resources = None
        return harness.scope

    with (
        patch.object(
            users, "require_scope", new_callable=AsyncMock, side_effect=identity
        ) as authorization,
        patch.object(
            users.user_governance, function, new_callable=AsyncMock, return_value=returned
        ) as service,
    ):
        reply = harness.client.get(path)
    assert authorization.await_args is not None
    assert authorization.await_args.kwargs == {
        "audience": "admin",
        "permissions": ("admin.session.read" if kind == "sessions" else "admin.user.read",),
    }
    if outcome in {"permission", "resource-loss"}:
        assert reply.status_code == (403 if outcome == "permission" else 503)
        assert reply.json()["error"]["code"] == (
            "PERMISSION_DENIED" if outcome == "permission" else "SERVICE_UNAVAILABLE"
        )
        service.assert_not_awaited()
    else:
        assert reply.status_code == (200 if outcome == "success" else 500)
        assert service.await_args is not None
        assert service.await_args.kwargs == (
            {"actor_id": harness.scope.user_id}
            if kind == "ceilings"
            else {"actor_id": harness.scope.user_id, "user_id": target}
        )
        if outcome == "success":
            assert reply.json()["data"] == (
                [item.model_dump(mode="json") for item in value]
                if isinstance(value, list)
                else value.model_dump(mode="json")
            )
        else:
            assert reply.json()["error"]["code"] == "INTERNAL_ERROR"
    assert (
        "synthetic-sensitive-value" not in reply.text
        and "password_hash" not in reply.text
        and "refresh_token" not in reply.text
    )
    harness.session.add.assert_not_called()


@pytest.mark.parametrize(
    "action", ["approval", "recovery-decisions", "roles", "session-revocations"]
)
@pytest.mark.parametrize("outcome", ["success", "permission", "revision-conflict"])
def test_account_actions_execute_real_receipt_authorization_and_publish_only_committed_dto(
    harness: Harness, action: str, outcome: str
) -> None:
    from app.models import IdempotencyRecord
    from app.schemas.user_governance import ManualRecoveryDecisionResult
    from app.services import governance_receipts

    target = uuid4()
    challenge = uuid4()
    selected_role = uuid4()
    selected_session = uuid4()
    names = {
        "approval": "decide_account_approval",
        "recovery-decisions": "decide_manual_recovery",
        "roles": "replace_account_roles",
        "session-revocations": "revoke_account_sessions",
    }
    codes = {
        "approval": "admin.user.approve",
        "recovery-decisions": "admin.user.update",
        "roles": "admin.user.role.assign",
        "session-revocations": "admin.session.revoke",
    }
    payloads = {
        "approval": {"expected_revision": 3, "decision": "approve"},
        "recovery-decisions": {
            "challenge_id": str(challenge),
            "expected_revision": 3,
            "decision": "reject",
        },
        "roles": {"expected_revision": 3, "role_ids": [str(selected_role)]},
        "session-revocations": {"expected_revision": 3, "session_id": str(selected_session)},
    }
    result: BaseModel = (
        ManualRecoveryDecisionResult(
            challenge_id=challenge,
            status="rejected",
            revision=4,
            authorization_revision=9,
            expires_at=datetime.now(UTC) + timedelta(hours=1),
        )
        if action == "recovery-decisions"
        else AccountWriteResult(
            user_id=target, revision=4, authorization_revision=9, audit_id=uuid4(), affected_count=1
        )
    )
    harness.session.scalar.return_value = None
    with (
        patch.object(users, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(governance_receipts, "verify_admin_write", new_callable=AsyncMock) as verify,
        patch.object(
            governance_receipts,
            "require_permissions",
            new_callable=AsyncMock,
            side_effect=AppError(ErrorCode.PERMISSION_DENIED) if outcome == "permission" else None,
        ) as authorize,
        patch.object(
            users.user_governance,
            names[action],
            new_callable=AsyncMock,
            return_value=result,
            side_effect=AppError(ErrorCode.REVISION_CONFLICT)
            if outcome == "revision-conflict"
            else None,
        ) as service,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/users/{target}/{action}",
            headers=harness.headers(),
            json=payloads[action],
        )
    verify.assert_awaited_once_with(harness.session, harness.scope)
    authorize.assert_awaited_once_with(
        harness.session, user_id=harness.scope.user_id, audience="admin", codes=(codes[action],)
    )
    if outcome == "permission":
        service.assert_not_awaited()
    else:
        assert service.await_args is not None
        arguments = service.await_args.kwargs
        assert (
            arguments["actor_id"] == harness.scope.user_id
            and arguments["user_id"] == target
            and arguments["expected_revision"] == 3
        )
        if action == "recovery-decisions":
            assert (
                arguments["challenge_id"] == challenge and arguments["verification_method"] is None
            )
        elif action == "roles":
            assert arguments["role_ids"] == (selected_role,)
        elif action == "session-revocations":
            assert (
                arguments["session_id"] == selected_session
                and arguments["audience"] is None
                and arguments["all_sessions"] is False
            )
        else:
            assert arguments["decision"] == "approve"
    if outcome == "success":
        assert reply.status_code == 200 and reply.json()["data"] == result.model_dump(mode="json")
        receipt = harness.session.add.call_args.args[0]
        assert (
            isinstance(receipt, IdempotencyRecord)
            and receipt.owner_user_id == harness.scope.user_id
        )
        assert receipt.audience == "admin" and receipt.state == "committed"
        assert receipt.action_code == f"POST:/api/v1/admin/users/{{user_id}}/{action}"
        assert receipt.safe_response is not None and "ciphertext" in receipt.safe_response
        ciphertext = receipt.safe_response["ciphertext"]
        assert isinstance(ciphertext, str) and str(target) not in ciphertext
    else:
        assert reply.status_code == (403 if outcome == "permission" else 409)
        assert reply.json()["error"]["code"] == (
            "PERMISSION_DENIED" if outcome == "permission" else "REVISION_CONFLICT"
        )
        harness.session.add.assert_not_called()
        harness.session.flush.assert_not_awaited()


@pytest.mark.parametrize("action", ["metadata", "enabled", "grant-boundaries"])
@pytest.mark.parametrize("outcome", ["success", "permission", "recent-auth-lost"])
def test_role_mutations_run_receipt_guards_before_service_and_store_encrypted_result(
    harness: Harness, action: str, outcome: str
) -> None:
    from app.models import IdempotencyRecord
    from app.services import governance_receipts

    target = uuid4()
    assigned = uuid4()
    path = f"/api/v1/admin/roles/{target}" + ("" if action == "metadata" else f"/{action}")
    names = {
        "metadata": "update_role_metadata",
        "enabled": "set_role_enabled",
        "grant-boundaries": "replace_grant_boundaries",
    }
    code = "admin.grant_boundary.update" if action == "grant-boundaries" else "admin.role.update"
    body = {"expected_revision": 3} | (
        {"name": "Visible operator", "description": "Metadata only"}
        if action == "metadata"
        else {"enabled": False}
        if action == "enabled"
        else {"boundaries": [{"boundary_kind": "assign_role", "target_role_id": str(assigned)}]}
    )
    value = AuthorizationWriteResult(
        role_id=target, revision=4, authorization_revision=8, audit_id=uuid4(), affected_count=1
    )
    harness.session.scalar.return_value = None
    with (
        patch.object(roles, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(
            governance_receipts,
            "verify_admin_write",
            new_callable=AsyncMock,
            side_effect=AppError(ErrorCode.AUTH_REQUIRED)
            if outcome == "recent-auth-lost"
            else None,
        ) as verify,
        patch.object(
            governance_receipts,
            "require_permissions",
            new_callable=AsyncMock,
            side_effect=AppError(ErrorCode.PERMISSION_DENIED) if outcome == "permission" else None,
        ) as authorize,
        patch.object(
            roles.role_governance, names[action], new_callable=AsyncMock, return_value=value
        ) as service,
    ):
        reply = harness.client.request(
            "PATCH" if action == "metadata" else "POST", path, headers=harness.headers(), json=body
        )
    verify.assert_awaited_once_with(harness.session, harness.scope)
    if outcome == "recent-auth-lost":
        authorize.assert_not_awaited()
    else:
        authorize.assert_awaited_once_with(
            harness.session, user_id=harness.scope.user_id, audience="admin", codes=(code,)
        )
    if outcome == "success":
        assert reply.status_code == 200 and reply.json()["data"] == value.model_dump(mode="json")
        assert service.await_args is not None
        args = service.await_args.kwargs
        assert (
            args["actor_id"] == harness.scope.user_id
            and args["role_id"] == target
            and args["expected_revision"] == 3
        )
        if action == "metadata":
            assert args["name"] == "Visible operator" and args["description"] == "Metadata only"
        elif action == "enabled":
            assert args["enabled"] is False
        else:
            boundaries = cast(tuple[BaseModel, ...], args["boundaries"])
            assert len(boundaries) == 1 and boundaries[0].model_dump(mode="json")[
                "target_role_id"
            ] == str(assigned)
        receipt = harness.session.add.call_args.args[0]
        assert (
            isinstance(receipt, IdempotencyRecord)
            and receipt.owner_user_id == harness.scope.user_id
            and receipt.state == "committed"
        )
        assert receipt.safe_response is not None and isinstance(
            receipt.safe_response["ciphertext"], str
        )
    else:
        assert reply.status_code == (401 if outcome == "recent-auth-lost" else 403)
        service.assert_not_awaited()
        harness.session.add.assert_not_called()
        harness.session.flush.assert_not_awaited()


@pytest.mark.parametrize("kind", ["permissions", "boundaries"])
@pytest.mark.parametrize("outcome", ["success", "permission", "resource-loss"])
def test_registered_permission_and_grant_boundary_reads_guard_current_admin_scope(
    harness: Harness, kind: str, outcome: str
) -> None:
    from app.schemas.role_governance import GrantBoundaryRead, PermissionCatalogRead

    target = uuid4()
    code = "admin.permission.read" if kind == "permissions" else "admin.grant_boundary.read"
    value: list[BaseModel] = (
        [
            PermissionCatalogRead(
                code="client.material.read", audience="client", data_scope="self", enabled=True
            )
        ]
        if kind == "permissions"
        else [
            GrantBoundaryRead(
                boundary_kind="assign_role",
                target_role_id=target,
                permission_code=None,
                data_scope=None,
                revision=3,
            )
        ]
    )

    async def identity(*_args: object, **kwargs: object) -> ScopeContext:
        assert kwargs == {"audience": "admin", "permissions": (code,)}
        if outcome == "permission":
            raise AppError(ErrorCode.PERMISSION_DENIED)
        if outcome == "resource-loss":
            harness.runtime.resources = None
        return harness.scope

    with (
        patch.object(roles, "require_scope", new=identity),
        patch.object(
            roles.role_governance,
            "list_permissions" if kind == "permissions" else "read_grant_boundaries",
            new_callable=AsyncMock,
            return_value=value,
        ) as service,
    ):
        reply = harness.client.get(
            "/api/v1/admin/permissions"
            if kind == "permissions"
            else f"/api/v1/admin/roles/{target}/grant-boundaries"
        )
    if outcome == "success":
        assert reply.status_code == 200 and reply.json()["data"] == [
            item.model_dump(mode="json") for item in value
        ]
        assert service.await_args is not None and service.await_args.kwargs == (
            {"actor_id": harness.scope.user_id}
            if kind == "permissions"
            else {"actor_id": harness.scope.user_id, "role_id": target}
        )
    else:
        assert reply.status_code == (403 if outcome == "permission" else 503)
        service.assert_not_awaited()
    harness.session.add.assert_not_called()


@pytest.mark.parametrize(
    "kind", ["client-jobs", "admin-jobs", "user-limits", "instance-limits", "capabilities"]
)
@pytest.mark.parametrize("outcome", ["success", "revoked", "resource-loss"])
def test_model_metadata_reads_recheck_audience_action_and_do_not_expose_private_job_inputs(
    harness: Harness, kind: str, outcome: str
) -> None:
    from app.api import model_settings as models
    from app.models.model_tasks import Job, UserRuntimeLimit
    from app.schemas.model_settings import ModelCapabilities, ModelLimits

    if kind in {"client-jobs", "capabilities"}:
        harness.scope = replace(harness.scope, audience="client")
    now = datetime.now(UTC)
    job = Job(
        id=uuid4(),
        owner_user_id=harness.scope.user_id,
        run_id=uuid4(),
        credential_id=uuid4(),
        operation_kind="credential_test",
        state="blocked",
        revision=4,
        generation=2,
        progress_seq=3,
        fence=1,
        error_code="KEY_REQUIRED",
        created_at=now,
        updated_at=now,
        input_refs={"prompt": "synthetic-sensitive-value"},
    )
    override = UserRuntimeLimit(id=uuid4(), owner_user_id=uuid4(), revision=3, value_limit=0)
    harness.session.scalars.return_value = [override] if kind == "user-limits" else [job]
    paths = {
        "client-jobs": "/api/v1/jobs",
        "admin-jobs": "/api/v1/admin/jobs",
        "user-limits": "/api/v1/admin/user-model-limits",
        "instance-limits": "/api/v1/admin/model-limits",
        "capabilities": "/api/v1/model-capabilities",
    }
    codes = {
        "client-jobs": ("client.job.read", "client.credential.read"),
        "admin-jobs": ("admin.job.read",),
        "user-limits": ("admin.quota.read",),
        "instance-limits": ("admin.quota.read",),
        "capabilities": (),
    }

    async def identity(*_args: object, **kwargs: object) -> ScopeContext:
        assert kwargs == {"audience": harness.scope.audience, "permissions": codes[kind]}
        if outcome == "revoked":
            raise AppError(ErrorCode.PERMISSION_DENIED)
        if outcome == "resource-loss":
            harness.runtime.resources = None
        return harness.scope

    limits = ModelLimits()
    with (
        patch.object(models, "require_scope", new=identity),
        patch.object(
            models.config, "effective_limits", new_callable=AsyncMock, return_value=limits
        ) as effective,
        patch.object(
            models.config,
            "capabilities",
            new_callable=AsyncMock,
            return_value=ModelCapabilities(revision=1, models=[], voices=[], limits=limits),
        ) as capabilities,
    ):
        reply = harness.client.get(paths[kind])
    if outcome == "success":
        assert reply.status_code == 200
        body = reply.json()["data"]
        if kind in {"client-jobs", "admin-jobs"}:
            assert body["items"][0]["id"] == str(job.id) and body["items"][0]["generation"] == 2
            assert body["items"][0]["can_retry"] is True
            assert "owner_user_id" not in body["items"][0] and "input_refs" not in body["items"][0]
            if kind == "client-jobs":
                statement = harness.session.scalars.await_args.args[0]
                assert harness.scope.user_id in statement.compile().params.values()
        elif kind == "user-limits":
            assert (
                body["items"][0]["user_id"] == str(override.owner_user_id)
                and body["items"][0]["max_concurrent_jobs"] == 0
            )
        elif kind == "instance-limits":
            assert body == limits.model_dump(mode="json")
        else:
            assert body["models"] == [] and body["voices"] == []
    else:
        assert reply.status_code == (403 if outcome == "revoked" else 503)
        harness.session.scalars.assert_not_awaited()
        effective.assert_not_awaited()
        capabilities.assert_not_awaited()
    assert "synthetic-sensitive-value" not in reply.text
    harness.session.add.assert_not_called()


@pytest.mark.parametrize(
    "family,action",
    [
        ("account", "approval"),
        ("account", "recovery-decisions"),
        ("account", "roles"),
        ("account", "session-revocations"),
        ("role", "metadata"),
        ("role", "enabled"),
        ("role", "grant-boundaries"),
    ],
)
def test_governance_resources_lost_after_valid_csrf_do_not_start_transaction_or_action(
    harness: Harness, family: str, action: str
) -> None:
    target = uuid4()
    module = users if family == "account" else roles
    original = module.require_session_csrf
    body: dict[str, object] = {"expected_revision": 3}
    if action == "approval":
        body["decision"] = "approve"
    elif action == "recovery-decisions":
        body.update(challenge_id=str(uuid4()), decision="reject")
    elif action == "roles":
        body["role_ids"] = []
    elif action == "session-revocations":
        body["all_sessions"] = True
    elif action == "metadata":
        body["name"] = "Operator"
    elif action == "enabled":
        body["enabled"] = False
    else:
        body["boundaries"] = []
    methods = {
        "approval": "decide_account_approval",
        "recovery-decisions": "decide_manual_recovery",
        "roles": "replace_account_roles",
        "session-revocations": "revoke_account_sessions",
        "metadata": "update_role_metadata",
        "enabled": "set_role_enabled",
        "grant-boundaries": "replace_grant_boundaries",
    }
    service_module = users.user_governance if family == "account" else roles.role_governance

    async def valid_csrf_then_loss(
        request: object, runtime: Runtime, current: ScopeContext
    ) -> None:
        from fastapi import Request

        await original(cast(Request, request), runtime, current)
        harness.runtime.resources = None

    with (
        patch.object(module, "require_scope", new_callable=AsyncMock, return_value=harness.scope),
        patch.object(module, "require_session_csrf", new=valid_csrf_then_loss),
        patch.object(service_module, methods[action], new_callable=AsyncMock) as service,
        patch.object(
            governance_writes, "commit_governance_receipt", new_callable=AsyncMock
        ) as receipt,
    ):
        path = (
            f"/api/v1/admin/users/{target}/{action}"
            if family == "account"
            else f"/api/v1/admin/roles/{target}" + ("" if action == "metadata" else f"/{action}")
        )
        reply = harness.client.request(
            "PATCH" if action == "metadata" else "POST", path, headers=harness.headers(), json=body
        )
    assert reply.status_code == 503 and reply.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    service.assert_not_awaited()
    receipt.assert_not_awaited()
    harness.session.begin.assert_not_called()
    harness.session.add.assert_not_called()


@pytest.mark.parametrize(
    "failure", ["valid", "origin", "cookie", "browser-fetch", "missing-bearer"]
)
def test_authenticated_native_model_write_rejects_browser_transport_confusion(
    harness: Harness, failure: str
) -> None:
    from app.api import model_settings as models
    from app.schemas.model_settings import CredentialRead

    harness.scope = replace(harness.scope, audience="client", transport="native")
    identifier = uuid4()
    headers = {"authorization": "Bearer synthetic-native-token"}
    if failure == "origin":
        headers["origin"] = harness.runtime.settings.public_base_url
    elif failure == "cookie":
        headers["cookie"] = "haruka_client_session=" + "a" * 43
    elif failure == "browser-fetch":
        headers["sec-fetch-site"] = "same-origin"
    elif failure == "missing-bearer":
        headers = {}
    now = datetime.now(UTC)
    value = CredentialRead(
        id=identifier,
        provider="openrouter",
        label="Personal",
        masked_key="••••1234",
        revision=4,
        credential_version=1,
        status="revoked",
        created_at=now,
        updated_at=now,
    )
    with (
        patch.object(
            models, "require_scope", new_callable=AsyncMock, return_value=harness.scope
        ) as identity,
        patch.object(
            models.config, "delete_credential", new_callable=AsyncMock, return_value=value
        ) as service,
        patch.object(models, "require_session_csrf", new_callable=AsyncMock) as browser_csrf,
    ):
        reply = harness.client.request(
            "DELETE",
            f"/api/v1/provider-credentials/{identifier}",
            headers=headers,
            json={"expected_revision": 3},
        )
    identity.assert_awaited_once()
    assert identity.await_args is not None and identity.await_args.kwargs == {
        "audience": "client",
        "permissions": ("client.credential.manage",),
    }
    browser_csrf.assert_not_awaited()
    if failure == "valid":
        assert reply.status_code == 200 and reply.json()["data"] == value.model_dump(mode="json")
        service.assert_awaited_once_with(harness.session, harness.scope, identifier, 3)
    else:
        assert reply.status_code == 401 and reply.json()["error"]["code"] == "SESSION_INVALID"
        service.assert_not_awaited()
        harness.session.begin.assert_not_called()


@pytest.mark.parametrize(
    "state,action",
    [("missing", "cancel"), ("queued", "cancel"), ("running", "cancel"), ("blocked", "retry")],
)
def test_admin_job_action_preserves_attempt_generation_and_emits_only_safe_metadata(
    harness: Harness, state: str, action: str
) -> None:
    from app.api import model_settings as models
    from app.models import AuthorizationRevision, OutboxEvent
    from app.models.model_tasks import Job, JobStage

    now = datetime.now(UTC)
    job = Job(
        id=uuid4(),
        owner_user_id=uuid4(),
        operation_kind="credential_test",
        state=state,
        revision=4,
        generation=2,
        progress_seq=3,
        fence=1,
        error_code=None,
        created_at=now,
        updated_at=now,
        input_refs={"prompt": "synthetic-sensitive-value"},
    )
    stage = JobStage(state="committed", result_refs={"attempt_id": str(uuid4())})
    harness.session.scalar.side_effect = (
        [None]
        if state == "missing"
        else [job, stage, AuthorizationRevision(revision=9)]
        if action == "retry"
        else [job, AuthorizationRevision(revision=9)]
    )
    with (
        patch.object(
            models, "require_scope", new_callable=AsyncMock, return_value=harness.scope
        ) as identity,
        patch.object(models, "verify_admin_write", new_callable=AsyncMock) as verify,
        patch.object(models.tasks, "lock_policy", new_callable=AsyncMock),
        patch.object(models.tasks, "lock_job_owner", new_callable=AsyncMock),
        patch.object(models.tasks, "execute_probe", new_callable=AsyncMock) as probe,
    ):
        reply = harness.client.post(
            f"/api/v1/admin/jobs/{job.id}/{action}",
            headers=harness.headers(),
            json={"expected_revision": 4},
        )
    verify.assert_awaited_once_with(harness.session, harness.scope)
    assert identity.await_args is not None and identity.await_args.kwargs == {
        "audience": "admin",
        "permissions": (f"admin.job.{action}",),
    }
    probe.assert_not_awaited()
    if state == "missing":
        assert reply.status_code == 404 and reply.json()["error"]["code"] == "RESOURCE_NOT_FOUND"
        harness.session.add.assert_not_called()
    else:
        expected = (
            "queued"
            if action == "retry"
            else "cancel_requested"
            if state == "running"
            else "cancelled"
        )
        assert reply.status_code == 200 and job.state == expected
        assert (
            job.generation == 2 and job.fence == 1 and job.revision == 5 and job.progress_seq == 4
        )
        assert (
            reply.json()["data"]["generation"] == 2 and "owner_user_id" not in reply.json()["data"]
        )
        event = harness.session.add.call_args_list[0].args[0]
        assert isinstance(event, OutboxEvent) and event.payload == {
            "schema_version": 1,
            "job_id": str(job.id),
            "generation": 2,
            "sequence": 4,
        }
        assert event.event_type == (
            "model.job.accepted" if action == "retry" else "model.job.updated"
        )
        audit = harness.session.add.call_args_list[1].args[0]
        assert audit.actor_user_id == harness.scope.user_id and audit.target_id == job.id
    assert "synthetic-sensitive-value" not in reply.text
