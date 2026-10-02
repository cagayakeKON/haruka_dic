"""Real PG action guard matrix for permissions actually declared by current HTTP routes.
Future catalog vocabulary is reported separately; no getter-only grant projection.
"""

import asyncio
import json
import os
from pathlib import Path
from typing import Literal, cast

import httpx2 as httpx
import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import (
    AuthPolicy,
    AuthSession,
    PermissionCatalog,
    Role,
    RolePermission,
    User,
    UserRole,
)
from app.services.auth_context import require_permissions, verify_scope_in_transaction
from app.services.authorization import require_effective_permissions
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


async def test_every_delivered_route_action_runs_real_pg_allow_deny_unknown_audience_scope_guards(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    sessions = runtime.resources.database.sessions
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    route_actions: dict[str, list[str]] = {}
    paths = cast(dict[str, dict[str, object]], app.openapi()["paths"])
    for path, operations in paths.items():
        for method, operation in operations.items():
            if method.upper() not in {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"}:
                continue
            definition = cast(dict[str, object], operation)
            for code in cast(list[str], definition.get("x-haruka-permissions", [])):
                route_actions.setdefault(code, []).append(method.upper() + " " + path)
    route_actions.setdefault("client.login", []).append("/api/v1/auth/login")
    route_actions.setdefault("admin.login", []).append("/api/v1/admin/auth/login")
    assert route_actions and len(route_actions) > 30
    async with sessions() as setup, setup.begin():
        policy = await setup.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"permission-matrix-{run_id}@haruka.example.test"
    async for _client, _headers in _owner(runtime, maintenance, email):
        async with sessions() as lookup:
            user = await lookup.scalar(select(User).where(User.email_normalized == email))
            assert user is not None
            owner = user.id
            catalogs = list(await lookup.scalars(select(PermissionCatalog)))
            published = {p.code: p for p in catalogs if p.code in route_actions}
            assert set(published) == set(route_actions)
            client_auth = await lookup.scalar(
                select(AuthSession).where(
                    AuthSession.user_id == owner,
                    AuthSession.audience == "client",
                    AuthSession.revoked_at.is_(None),
                )
            )
            assert client_auth is not None
            client_session = client_auth.id
        maintenance_engine = create_maintenance_engine(maintenance)
        try:
            factory = async_sessionmaker(maintenance_engine, expire_on_commit=False)
            async with factory() as setup, setup.begin():
                allow = Role(
                    code="matrix_allow_" + run_id,
                    name="matrix allow",
                    protected=False,
                    enabled=True,
                    revision=1,
                )
                deny = Role(
                    code="matrix_deny_" + run_id,
                    name="matrix deny",
                    protected=False,
                    enabled=True,
                    revision=1,
                )
                setup.add_all([allow, deny])
                await setup.flush()
                allow_id, deny_id = allow.id, deny.id
                setup.add_all(
                    [
                        UserRole(user_id=owner, role_id=allow_id),
                        UserRole(user_id=owner, role_id=deny_id),
                    ]
                )
                setup.add_all(
                    [
                        RolePermission(
                            role_id=allow_id,
                            permission_code=p.code,
                            effect="allow",
                            data_scope=p.data_scope,
                        )
                        for p in published.values()
                    ]
                )
            async with BoundAsyncClient(
                transport=httpx.ASGITransport(app=app), base_url=runtime.settings.public_base_url
            ) as admin:
                login = await admin.post(
                    "/api/v1/admin/auth/login",
                    json={"email": email, "password": "synthetic-profile-password-2026"},
                    headers={"Origin": runtime.settings.public_base_url},
                )
                assert login.status_code == 200
                async with sessions() as lookup:
                    auth = await lookup.scalar(
                        select(AuthSession).where(
                            AuthSession.user_id == owner,
                            AuthSession.audience == "admin",
                            AuthSession.revoked_at.is_(None),
                        )
                    )
                    assert auth is not None
                    admin_session = auth.id
                matrix: list[dict[str, object]] = []
                for code, p in sorted(published.items()):
                    audience = cast('Literal["client", "admin"]', p.audience)
                    session_id = client_session if audience == "client" else admin_session
                    async with sessions() as guard, guard.begin():
                        scope = await verify_scope_in_transaction(
                            guard,
                            user_id=owner,
                            session_id=session_id,
                            audience=audience,
                            transport="web",
                            permissions=(code,),
                        )
                        assert scope.user_id == owner
                        with pytest.raises(AppError) as unknown:
                            await require_permissions(
                                guard,
                                user_id=owner,
                                audience=audience,
                                codes=(audience + ".not_published_matrix",),
                            )
                        assert unknown.value.code == ErrorCode.PERMISSION_DENIED
                        wrong_audience = "admin" if audience == "client" else "client"
                        with pytest.raises(AppError) as wrong:
                            await require_permissions(
                                guard, user_id=owner, audience=wrong_audience, codes=(code,)
                            )
                        assert wrong.value.code == ErrorCode.PERMISSION_DENIED
                        with pytest.raises(AppError) as wrong_scope:
                            await require_effective_permissions(
                                guard, user_id=owner, requirements=((code, "not_registered_scope"),)
                            )
                        assert wrong_scope.value.code == ErrorCode.PERMISSION_DENIED
                    async with factory() as change, change.begin():
                        denied = RolePermission(
                            role_id=deny_id,
                            permission_code=code,
                            effect="deny",
                            data_scope=p.data_scope,
                        )
                        change.add(denied)
                        await change.flush()
                        denied_id = denied.id
                    async with sessions() as guard, guard.begin():
                        with pytest.raises(AppError) as rejected:
                            await verify_scope_in_transaction(
                                guard,
                                user_id=owner,
                                session_id=session_id,
                                audience=audience,
                                transport="web",
                                permissions=(code,),
                            )
                        assert rejected.value.code == ErrorCode.PERMISSION_DENIED
                    async with factory() as change, change.begin():
                        denial = await change.get(RolePermission, denied_id)
                        assert denial is not None
                        await change.delete(denial)
                    matrix.append(
                        {
                            "code": code,
                            "routes": route_actions[code],
                            "checks": [
                                "transaction-allow",
                                "explicit-deny",
                                "unknown-default-deny",
                                "wrong-audience",
                                "wrong-scope",
                            ],
                            "layer": "real PG current-identity/action transaction guard, not full business action response",
                        }
                    )
                target = os.environ.get("HARUKA_PERMISSION_MATRIX_REPORT")
                if target is not None:
                    await asyncio.to_thread(
                        Path(target).write_text,
                        json.dumps(
                            {
                                "scope": "current registered HTTP action closure; no future vocabulary activation",
                                "actions": matrix,
                                "excluded_future_catalog_codes": sorted(
                                    p.code for p in catalogs if p.code not in published
                                ),
                            },
                            indent=2,
                        )
                        + "\n",
                        encoding="utf-8",
                    )
        finally:
            await maintenance_engine.dispose()
