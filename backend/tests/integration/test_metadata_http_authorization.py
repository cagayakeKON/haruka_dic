"""Delivered metadata HTTP routes use actual PG identity, deny and CAS boundaries."""

import asyncio
import json
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

import httpx2 as httpx
import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.bootstrap import Runtime
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings, create_maintenance_engine
from app.models import (
    AuthorizationRevision,
    AuthPolicy,
    AuthSession,
    PermissionCatalog,
    Role,
    RolePermission,
    User,
    UserRole,
)
from app.models.model_tasks import ExternalCallAttempt
from app.schemas.audit_governance import AuditEventRead, GovernanceSummaryRead
from app.schemas.model_settings import ModelCapabilities, ModelLimits, ModelUsage, UserLimitList
from app.schemas.profile import StudyProfileRead
from tests.integration.test_profile_avatar import _owner  # pyright: ignore[reportPrivateUsage]
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
pytest_plugins = ("tests.integration.test_authentication_flow",)


async def test_metadata_http_permissions_owner_cas_and_recent_auth(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    sessions = runtime.resources.database.sessions
    async with sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    origin = runtime.settings.public_base_url
    transport = httpx.ASGITransport(app=app)
    evidence: list[dict[str, object]] = []
    engine = create_maintenance_engine(maintenance)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async for client_a, headers_a in _owner(
            runtime, maintenance, f"metadata-a-{run_id}@haruka.example.test"
        ):
            async for client_b, _headers_b in _owner(
                runtime, maintenance, f"metadata-b-{run_id}@haruka.example.test"
            ):
                async with sessions() as session:
                    actor = await session.scalar(
                        select(User).where(
                            User.email_normalized == f"metadata-a-{run_id}@haruka.example.test"
                        )
                    )
                    assert actor is not None
                    actor_id = actor.id
                    catalog = {
                        row.code: row for row in await session.scalars(select(PermissionCatalog))
                    }
                async with factory() as session, session.begin():
                    allow = Role(
                        code="http_allow_" + run_id,
                        name="HTTP allow",
                        enabled=True,
                        protected=False,
                    )
                    deny = Role(
                        code="http_deny_" + run_id, name="HTTP deny", enabled=True, protected=False
                    )
                    session.add_all([allow, deny])
                    await session.flush()
                    deny_id = deny.id
                    session.add_all(
                        [
                            UserRole(user_id=actor_id, role_id=allow.id),
                            UserRole(user_id=actor_id, role_id=deny.id),
                        ]
                    )
                    session.add_all(
                        [
                            RolePermission(
                                role_id=allow.id,
                                permission_code=row.code,
                                effect="allow",
                                data_scope=row.data_scope,
                            )
                            for row in catalog.values()
                        ]
                    )
                    root = await session.get(AuthorizationRevision, "global", with_for_update=True)
                    assert root is not None
                    root.revision += 1

                async def denial(
                    code: str,
                    enabled: bool,
                    role_id: UUID = deny_id,
                    permission_catalog: dict[str, PermissionCatalog] = catalog,
                ) -> None:
                    async with factory() as session, session.begin():
                        root = await session.get(
                            AuthorizationRevision, "global", with_for_update=True
                        )
                        assert root is not None
                        row = await session.scalar(
                            select(RolePermission).where(
                                RolePermission.role_id == role_id,
                                RolePermission.permission_code == code,
                            )
                        )
                        if enabled:
                            assert row is None
                            session.add(
                                RolePermission(
                                    role_id=role_id,
                                    permission_code=code,
                                    effect="deny",
                                    data_scope=permission_catalog[code].data_scope,
                                )
                            )
                        else:
                            assert row is not None
                            await session.delete(row)
                        root.revision += 1

                async with (
                    BoundAsyncClient(transport=transport, base_url=origin) as admin,
                    httpx.AsyncClient(transport=transport, base_url=origin) as anonymous,
                ):
                    login = await admin.post(
                        "/api/v1/admin/auth/login",
                        json={
                            "email": f"metadata-a-{run_id}@haruka.example.test",
                            "password": "synthetic-profile-password-2026",
                        },
                        headers={"Origin": origin},
                    )
                    assert login.status_code == 200
                    csrf = (await admin.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
                    admin_headers = {"Origin": origin, "X-CSRF-Token": csrf}

                    async def request_check(
                        method: str,
                        path: str,
                        code: str,
                        client: BoundAsyncClient,
                        headers: dict[str, str],
                        payload: dict[str, object] | None = None,
                        bound_actor: UUID = actor_id,
                    ) -> httpx.Response:
                        missing = await anonymous.request(
                            method, path, headers=headers, json=payload
                        )
                        assert missing.status_code == 401
                        await denial(code, True)
                        rejected = await client.request(method, path, headers=headers, json=payload)
                        assert rejected.status_code == 403
                        assert rejected.json()["error"]["code"] == "PERMISSION_DENIED"
                        await denial(code, False)
                        allowed = await client.request(method, path, headers=headers, json=payload)
                        assert allowed.status_code == 200
                        evidence.append(
                            {
                                "method": method,
                                "path": path.replace(str(bound_actor), "{user_id}"),
                                "permission": code,
                                "anonymous": 401,
                                "explicit_deny": 403,
                                "allow": 200,
                            }
                        )
                        return allowed

                    for path, code in [
                        ("/api/v1/admin/audit-events", "admin.audit.read"),
                        ("/api/v1/admin/governance-summary", "admin.dashboard.view"),
                        ("/api/v1/admin/model-usage", "admin.dashboard.view"),
                        ("/api/v1/admin/menus", "admin.menu.read"),
                        ("/api/v1/admin/model-catalog", "admin.model_catalog.read"),
                    ]:
                        reply = await request_check("GET", path, code, admin, admin_headers)
                        data = reply.json()["data"]
                        if path.endswith("audit-events"):
                            for row in data:
                                AuditEventRead.model_validate(row)
                        elif path.endswith("governance-summary"):
                            GovernanceSummaryRead.model_validate(data)
                        elif path.endswith("model-usage"):
                            ModelUsage.model_validate(data)
                        elif path.endswith("model-catalog"):
                            ModelCapabilities.model_validate(data)
                        assert not any(
                            name in reply.text
                            for name in [
                                '"encrypted_key"',
                                '"input_refs"',
                                '"password_hash"',
                                '"prompt"',
                            ]
                        )

                    for path in ["study-profile", "settings", "model-settings", "model-usage"]:
                        permission = (
                            "client.profile.read"
                            if path in {"study-profile", "settings", "model-settings"}
                            else "client.credential.read"
                        )
                        reply = await request_check(
                            "GET", "/api/v1/users/me/" + path, permission, client_a, headers_a
                        )
                        if path == "study-profile":
                            before = StudyProfileRead.model_validate(reply.json()["data"])
                            changed = await client_a.patch(
                                "/api/v1/users/me/study-profile",
                                headers=headers_a,
                                json={
                                    "expected_revision": before.revision,
                                    "fields": {"target_languages": [{"language_tag": "ja"}]},
                                },
                            )
                            assert changed.status_code == 200
                            other = await client_b.get("/api/v1/users/me/study-profile")
                            own = await client_a.get("/api/v1/users/me/study-profile")
                            assert other.status_code == own.status_code == 200
                            assert other.json()["data"]["target_languages"] == []
                            assert own.json()["data"]["target_languages"][0]["language_tag"] == "ja"
                            await denial(permission, True)
                            assert (
                                await client_a.get("/api/v1/users/me/study-profile")
                            ).status_code == 403
                            assert (
                                await client_b.get("/api/v1/users/me/study-profile")
                            ).status_code == 200
                            await denial(permission, False)

                    limits_reply = await admin.get("/api/v1/admin/model-limits")
                    assert limits_reply.status_code == 200
                    limits = ModelLimits.model_validate(limits_reply.json()["data"])
                    payload: dict[str, object] = {
                        "expected_revision": limits.revision,
                        "limits": limits.model_dump(mode="json"),
                    }
                    global_reply = await request_check(
                        "PATCH",
                        "/api/v1/admin/model-limits",
                        "admin.quota.update",
                        admin,
                        admin_headers,
                        payload,
                    )
                    assert global_reply.json()["data"]["revision"] == limits.revision + 1
                    assert (
                        await admin.patch(
                            "/api/v1/admin/model-limits", json=payload, headers=admin_headers
                        )
                    ).status_code == 409
                    override_path = f"/api/v1/admin/user-model-limits/{actor_id}"
                    override = await request_check(
                        "PATCH",
                        override_path,
                        "admin.quota.update",
                        admin,
                        admin_headers,
                        {"expected_revision": 0, "max_concurrent_jobs": 0},
                    )
                    assert override.json()["data"]["revision"] == 1
                    assert override.json()["data"]["max_concurrent_jobs"] == 0
                    assert (
                        await admin.patch(
                            override_path,
                            json={"expected_revision": 0, "max_concurrent_jobs": 1},
                            headers=admin_headers,
                        )
                    ).status_code == 409
                    async with factory() as session, session.begin():
                        auth = await session.scalar(
                            select(AuthSession)
                            .where(
                                AuthSession.user_id == actor_id,
                                AuthSession.audience == "admin",
                                AuthSession.revoked_at.is_(None),
                            )
                            .with_for_update()
                        )
                        assert auth is not None
                        auth_id: UUID = auth.id
                        auth.reauthenticated_at = datetime.now(UTC) - timedelta(minutes=6)
                    for method, path, body in [
                        (
                            "PATCH",
                            "/api/v1/admin/model-limits",
                            {
                                "expected_revision": limits.revision + 1,
                                "limits": limits.model_dump(mode="json"),
                            },
                        ),
                        (
                            "PATCH",
                            override_path,
                            {"expected_revision": 1, "max_concurrent_jobs": 1},
                        ),
                        ("DELETE", override_path, {"expected_revision": 1}),
                    ]:
                        expired = await admin.request(
                            method, path, json=body, headers=admin_headers
                        )
                        assert expired.status_code == 401
                        assert expired.json()["error"]["code"] == "SESSION_INVALID"
                    async with factory() as session, session.begin():
                        auth = await session.get(AuthSession, auth_id, with_for_update=True)
                        assert auth is not None
                        auth.reauthenticated_at = datetime.now(UTC)
                    assert (
                        await admin.request(
                            "DELETE",
                            override_path,
                            json={"expected_revision": 2},
                            headers=admin_headers,
                        )
                    ).status_code == 409
                    deleted = await request_check(
                        "DELETE",
                        override_path,
                        "admin.quota.update",
                        admin,
                        admin_headers,
                        {"expected_revision": 1},
                    )
                    assert UserLimitList.model_validate(deleted.json()["data"]).items == []
                    async with sessions() as session:
                        assert (
                            await session.scalar(
                                select(func.count()).select_from(ExternalCallAttempt)
                            )
                            == 0
                        )
    finally:
        await engine.dispose()
    target = os.environ.get("HARUKA_HTTP_METADATA_REPORT")
    if target:
        await asyncio.to_thread(
            Path(target).write_text,
            json.dumps(
                {
                    "run_id": run_id,
                    "layer": "actual HTTP and isolated PG/Redis current identity",
                    "routes": evidence,
                    "provider_attempt_count": 0,
                    "owner_isolation": True,
                    "write_cas": True,
                    "recent_auth": True,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
