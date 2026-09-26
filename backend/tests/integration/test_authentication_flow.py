"""Authentication routes against owned PostgreSQL and Redis test resources."""

import asyncio
import json
import logging
import os
import secrets
from base64 import urlsafe_b64encode
from collections.abc import AsyncIterator
from datetime import timedelta
from pathlib import Path
from typing import Protocol, cast
from urllib.parse import urlsplit
from uuid import uuid4

import httpx2 as httpx
import pytest
import pytest_asyncio
from pydantic import SecretStr
from sqlalchemy import func, select, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.schema import CreateSchema, DropSchema
from starlette.requests import Request
from starlette.types import ASGIApp

from app.adapters.cache import Cache
from app.adapters.database import Database
from app.api.security_guards import rate_limit
from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.core.logging import SafeJsonFormatter
from app.core.settings import Settings, load_settings
from app.core.sql_telemetry import TelemetryAsyncQueuePool, install_sql_telemetry
from app.domain.errors import AppError
from app.main import create_app
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.models import (
    AdminAuditEvent,
    AuthChallenge,
    AuthChallengeDelivery,
    AuthPolicy,
    Library,
    OutboxEvent,
    Role,
    RolePermission,
    User,
    UserExtension,
    UserRole,
)
from app.services.auth_crypto import AuthCrypto
from app.services.initialization import apply_seed, initialize_admin
from app.services.notifications import claim_due_mail
from app.services.outbox_delivery import deliver_outbox_one
from tests.support.identity_scenarios import prepare_login_only_user

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]
ROOT = Path(__file__).resolve().parents[3]
ORIGIN = "https://localhost:18443"


class _KeyScanner(Protocol):
    def scan_iter(self, *, match: str, count: int) -> AsyncIterator[bytes]: ...


class _DropCommittedPasswordResponse(httpx.ASGITransport):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app=app)
        self.dropped = False

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        response = await super().handle_async_request(request)
        if request.url.path == "/api/v1/admin/auth/password/change" and not self.dropped:
            assert response.status_code == 204
            self.dropped = True
            await response.aclose()
            raise httpx.ReadError("synthetic response lost after commit", request=request)
        return response


@pytest_asyncio.fixture
async def identity_runtime() -> AsyncIterator[tuple[Runtime, MaintenanceSettings, str]]:
    if os.environ.get("HARUKA_MAINTENANCE_TEST_CONFIG") != "dev/.local/test-maintenance.env":
        pytest.fail("explicit Identity isolated test configuration is required")
    maintenance_source = load_maintenance_settings(ROOT / "dev/.local/test-maintenance.env")
    template = load_settings(ROOT / "dev/.local/test.env")
    assert template.database_url is not None and template.redis_url is not None
    run_id = uuid4().hex
    schema = f"haruka_migration_test_{run_id}"
    instance = f"haruka-test-{run_id}"
    maintenance = MaintenanceSettings(
        database_url=maintenance_source.database_url, test_schema=schema
    )
    observer = create_maintenance_engine(maintenance_source)
    database: Database | None = None
    cache: Cache | None = None
    try:
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(CreateSchema(schema))
        await upgrade_database(maintenance, ROOT / "backend/alembic")
        await apply_seed(maintenance)
        await initialize_admin(
            maintenance,
            email=f"admin-{run_id}@haruka.example.test",
            password=SecretStr("synthetic-admin-password-2026"),
        )

        def key() -> SecretStr:
            return SecretStr(urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii"))

        settings = Settings(
            _env_file=ROOT / "dev/.local/test.env",
            app_env="test",
            instance_id=instance,
            public_base_url=ORIGIN,
            allowed_origins=(ORIGIN,),
            infrastructure_enabled=True,
            resource_profile="core",
            database_url=template.database_url,
            redis_url=template.redis_url,
            resource_namespace=instance,
            test_schema=schema,
            auth_signing_key=key(),
            auth_digest_key=key(),
            mail_encryption_key=key(),
            mail_delivery_enabled=True,
            smtp_host="127.0.0.1",
            smtp_port=18025,
            smtp_from="noreply@haruka.example.test",
            smtp_starttls=False,
        )
        database = Database(settings.core_infrastructure())
        cache = Cache(settings.core_infrastructure())
        await database.check()
        await cache.check()
        runtime = Runtime(
            settings=settings,
            resources=Resources(database, cache, None, None, None),
            schema_compatible=True,
        )
        yield runtime, maintenance, run_id
    finally:
        if cache is not None:
            try:
                expected_namespace = f"haruka-test-{run_id}"
                assert cache.namespace == expected_namespace
                batch: list[bytes] = []
                scanner = cast(_KeyScanner, cache.client)
                async for cache_key in scanner.scan_iter(
                    match=f"{expected_namespace}:*", count=100
                ):
                    assert isinstance(cache_key, bytes) and cache_key.startswith(
                        f"{expected_namespace}:".encode("ascii")
                    )
                    batch.append(cache_key)
                    if len(batch) >= 100:
                        await cache.client.delete(*batch)
                        batch.clear()
                if batch:
                    await cache.client.delete(*batch)
            finally:
                await cache.aclose()
        if database is not None:
            await database.aclose()
        async with observer.begin() as connection:
            assert await connection.scalar(text("SELECT current_database()")) == "haruka_test"
            await connection.execute(DropSchema(schema, cascade=True))
        await observer.dispose()


async def _mail_token(maintenance: MaintenanceSettings, runtime: Runtime, email: str) -> str:
    engine = create_maintenance_engine(maintenance)
    try:
        async with engine.connect() as connection:
            row = (
                await connection.execute(
                    select(AuthChallengeDelivery.encrypted_payload)
                    .join(User, User.id == AuthChallengeDelivery.user_id)
                    .where(User.email_normalized == email.lower())
                    .order_by(AuthChallengeDelivery.created_at.desc())
                    .limit(1)
                )
            ).scalar_one()
            assert isinstance(row, bytes)
            _address, link, _purpose = AuthCrypto.from_settings(runtime.settings).decrypt_mail(row)
            fragment = urlsplit(link).fragment
            assert fragment.startswith("token=")
            return fragment.removeprefix("token=")
    finally:
        await engine.dispose()


async def test_pg_sql_diagnostics_are_safe_and_match_connection(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    caplog: pytest.LogCaptureFixture,
) -> None:
    runtime, _maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    formatter = SafeJsonFormatter(runtime.settings, "api")
    caplog.clear()
    with caplog.at_level(logging.INFO, logger="haruka.database"):
        async with runtime.resources.database.engine.connect() as connection:
            backend_pid = await connection.scalar(text("SELECT pg_backend_pid()"))
            assert type(backend_pid) is int and backend_pid > 0
            with pytest.raises(SQLAlchemyError):
                await connection.execute(text("SELECT 1 / 0"))
        assert runtime.settings.database_url is not None
        failing_url = make_url(runtime.settings.database_url.get_secret_value()).set(
            host="127.0.0.1", port=1
        )
        failing_engine = create_async_engine(
            failing_url,
            poolclass=TelemetryAsyncQueuePool,
            connect_args={"timeout": 1},
            pool_pre_ping=False,
        )
        install_sql_telemetry(
            failing_engine,
            database_name="haruka_test",
            application_name=f"haruka-test-{run_id}",
        )
        try:
            with pytest.raises((OSError, SQLAlchemyError)):
                async with failing_engine.connect():
                    pytest.fail("unexpected connection to the deliberately closed test port")
        finally:
            await failing_engine.dispose()

    statement = next(record for record in caplog.records if record.msg == "database.query.failed")
    statement_data = json.loads(formatter.format(statement))
    assert statement_data["database_name"] == "haruka_test"
    assert statement_data["application_name"] == f"haruka-test-{run_id}"
    assert statement_data["backend_pid"] == backend_pid
    assert statement_data["sqlstate"] == "22012"
    assert statement_data["statement_kind"] == "SELECT"
    assert statement_data["duration_ms"] >= 0

    connection = next(
        record for record in caplog.records if record.msg == "database.connection.failed"
    )
    connection_data = json.loads(formatter.format(connection))
    assert connection_data["database_name"] == "haruka_test"
    assert connection_data["application_name"] == f"haruka-test-{run_id}"
    assert "backend_pid" not in connection_data
    for payload in (statement_data, connection_data):
        serialized = json.dumps(payload)
        assert "SELECT 1 / 0" not in serialized
        assert "127.0.0.1" not in serialized
        assert "password" not in serialized


async def test_concurrent_registration_is_unique_and_invalid_role_is_atomic(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, _maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"concurrent-{run_id}@haruka.example.test"
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        responses = await asyncio.gather(
            *(
                web.post(
                    "/api/v1/auth/register",
                    json={"email": email, "password": "synthetic-concurrent-password-2026"},
                    headers=headers,
                )
                for _ in range(2)
            )
        )
        assert [response.status_code for response in responses] == [202, 202]
        assert responses[0].json()["data"] == responses[1].json()["data"]
        async with runtime.resources.database.sessions() as session:
            user = await session.scalar(select(User).where(User.email_normalized == email))
            assert user is not None and user.status == "pending"
            assert (
                await session.scalar(
                    select(func.count()).select_from(User).where(User.email_normalized == email)
                )
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(Library)
                    .where(Library.owner_user_id == user.id)
                )
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(UserExtension)
                    .where(UserExtension.user_id == user.id)
                )
                == 1
            )
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(AuthChallenge)
                    .where(
                        AuthChallenge.user_id == user.id, AuthChallenge.purpose == "email_verify"
                    )
                )
                == 1
            )
            before = [
                await session.scalar(select(func.count()).select_from(model))
                for model in (User, Library, UserExtension, AuthChallenge, AuthChallengeDelivery)
            ]
        blocked_email = f"blocked-{run_id}@haruka.example.test"
        async with runtime.resources.database.sessions() as session, session.begin():
            policy = await session.get(AuthPolicy, "registration", with_for_update=True)
            protected = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert policy is not None and protected is not None
            policy.default_role_id = protected.id
        blocked = await web.post(
            "/api/v1/auth/register",
            json={"email": blocked_email, "password": "synthetic-blocked-password-2026"},
            headers=headers,
        )
        assert blocked.status_code == 503
        async with runtime.resources.database.sessions() as session:
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(User)
                    .where(User.email_normalized == blocked_email)
                )
                == 0
            )
            assert [
                await session.scalar(select(func.count()).select_from(model))
                for model in (User, Library, UserExtension, AuthChallenge, AuthChallengeDelivery)
            ] == before


async def test_login_only_identity_survives_dependency_faults_without_profile_grant(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        role = Role(
            code=f"login_only_{run_id[:12]}",
            name="Isolated login only",
            protected=False,
            enabled=True,
            revision=1,
        )
        session.add(role)
        await session.flush()
        session.add(
            RolePermission(
                role_id=role.id,
                permission_code="client.login",
                effect="allow",
                data_scope="self",
            )
        )
        policy.registration_mode = "open"
        policy.default_role_id = role.id
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"login-only-{run_id}@haruka.example.test"
    password = "synthetic-login-only-password-2026"  # noqa: S105 - isolated test identity
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        registered = await web.post(
            "/api/v1/auth/register", json={"email": email, "password": password}, headers=headers
        )
        assert registered.status_code == 202
        verified = await web.post(
            "/api/v1/auth/email/verify",
            json={"token": await _mail_token(maintenance, runtime, email)},
            headers=headers,
        )
        assert verified.status_code == 204
        logged = await web.post(
            "/api/v1/auth/login", json={"email": email, "password": password}, headers=headers
        )
        assert logged.status_code == 200
        access = await web.get("/api/v1/me/access")
        assert access.status_code == 200
        assert {grant["code"] for grant in access.json()["data"]["permissions"]} == {"client.login"}
        assert (await web.get("/api/v1/users/me/account")).status_code == 200
        assert (await web.get("/api/v1/materials")).status_code == 403

        async def unavailable_get(*_args: object, **_kwargs: object) -> object:
            raise ConnectionError("synthetic isolated cache outage")

        with monkeypatch.context() as patch:
            patch.setattr(runtime.resources.cache.client, "get", unavailable_get)
            assert (await web.get("/api/v1/me/access")).status_code == 503
        assert (await web.get("/api/v1/me/access")).status_code == 200

        def unavailable_sessions() -> object:
            raise ConnectionError("synthetic isolated database outage")

        with monkeypatch.context() as patch:
            patch.setattr(runtime.resources.database, "sessions", unavailable_sessions)
            assert (await web.get("/api/v1/me/access")).status_code == 503
        assert (await web.get("/api/v1/me/access")).status_code == 200
        csrf = (await web.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        changed = await web.post(
            "/api/v1/auth/password/change",
            json={
                "current_password": password,
                "new_password": "synthetic-login-only-changed-2026",
            },
            headers={**headers, "X-CSRF-Token": csrf},
        )
        assert changed.status_code == 204


async def test_existing_verified_account_can_be_prepared_for_login_only_ui_scenario(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    assert maintenance.test_schema == f"haruka_migration_test_{run_id}"
    engine = create_maintenance_engine(maintenance)
    try:
        async with engine.begin() as connection:
            await connection.execute(
                text(
                    f"COMMENT ON SCHEMA {maintenance.test_schema} IS 'haruka-isolated-run:{run_id}'"
                )
            )
    finally:
        await engine.dispose()

    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"scenario-{run_id}@haruka.example.test"
    password = "synthetic-scenario-password-2026"  # noqa: S105 - isolated test identity
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        registered = await web.post(
            "/api/v1/auth/register", json={"email": email, "password": password}, headers=headers
        )
        assert registered.status_code == 202
        with pytest.raises(ValueError, match="verified active user"):
            await prepare_login_only_user(maintenance, email=email)
        verified = await web.post(
            "/api/v1/auth/email/verify",
            json={"token": await _mail_token(maintenance, runtime, email)},
            headers=headers,
        )
        assert verified.status_code == 204

        user_id = await prepare_login_only_user(maintenance, email=email)
        assert await prepare_login_only_user(maintenance, email=email) == user_id
        async with runtime.resources.database.sessions() as session:
            user = await session.get(User, user_id)
            assert user is not None and user.authz_version == 2
            links = (
                await session.scalars(select(UserRole).where(UserRole.user_id == user_id))
            ).all()
            assert len(links) == 1
            role = await session.get(Role, links[0].role_id)
            assert role is not None and role.code == f"scenario_login_only_{run_id}"
            assert (
                await session.scalar(
                    select(func.count())
                    .select_from(AdminAuditEvent)
                    .where(
                        AdminAuditEvent.action == "seed.applied",
                        AdminAuditEvent.target_user_id == user_id,
                    )
                )
                == 1
            )
            outbox_count = await session.scalar(
                select(func.count())
                .select_from(OutboxEvent)
                .join(AdminAuditEvent, OutboxEvent.audit_event_id == AdminAuditEvent.id)
                .where(AdminAuditEvent.target_user_id == user_id)
            )
            assert isinstance(outbox_count, int) and outbox_count >= 1

        logged = await web.post(
            "/api/v1/auth/login", json={"email": email, "password": password}, headers=headers
        )
        assert logged.status_code == 200
        access = await web.get("/api/v1/me/access")
        assert access.status_code == 200
        assert {grant["code"] for grant in access.json()["data"]["permissions"]} == {"client.login"}
        assert (await web.get("/api/v1/materials")).status_code == 403
        with pytest.raises(ValueError, match="before the account signs in"):
            await prepare_login_only_user(maintenance, email=email)


async def test_committed_password_change_with_lost_response_is_not_replayed(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, _maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    transport = _DropCommittedPasswordResponse(app)
    email = f"admin-{run_id}@haruka.example.test"
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    old_password = "synthetic-admin-password-2026"  # noqa: S105 - isolated test identity
    new_password = "synthetic-admin-changed-2026"  # noqa: S105 - isolated test identity
    async with httpx.AsyncClient(transport=transport, base_url=ORIGIN) as web:
        logged = await web.post(
            "/api/v1/admin/auth/login",
            json={"email": email, "password": old_password},
            headers=headers,
        )
        assert logged.status_code == 200
        csrf = (await web.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
        change = {
            "current_password": old_password,
            "new_password": new_password,
        }
        with pytest.raises(httpx.ReadError):
            await web.post(
                "/api/v1/admin/auth/password/change",
                json=change,
                headers={**headers, "X-CSRF-Token": csrf},
            )
        assert transport.dropped
        assert (await web.get("/api/v1/admin/me/access")).status_code == 401
        retry = await web.post(
            "/api/v1/admin/auth/password/change",
            json=change,
            headers={**headers, "X-CSRF-Token": csrf},
        )
        assert retry.status_code == 401
        assert (
            await web.post(
                "/api/v1/admin/auth/login",
                json={"email": email, "password": old_password},
                headers=headers,
            )
        ).status_code == 401
        accepted = await web.post(
            "/api/v1/admin/auth/login",
            json={"email": email, "password": new_password},
            headers=headers,
        )
        assert accepted.status_code == 200
    async with runtime.resources.database.sessions() as session:
        user = await session.scalar(select(User).where(User.email_normalized == email))
        assert user is not None
        assert user.password_version == 2 and user.security_epoch == 1
        assert (
            await session.scalar(
                select(func.count())
                .select_from(AdminAuditEvent)
                .where(
                    AdminAuditEvent.action == "password.changed",
                    AdminAuditEvent.target_user_id == user.id,
                )
            )
            == 1
        )


async def test_password_recovery_revokes_existing_admin_web_cookie(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"admin-{run_id}@haruka.example.test"
    old_password = "synthetic-admin-password-2026"  # noqa: S105 - isolated test identity
    new_password = "synthetic-admin-recovered-2026"  # noqa: S105 - isolated test identity
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    transport = httpx.ASGITransport(app=app)
    async with (
        httpx.AsyncClient(transport=transport, base_url=ORIGIN) as old_admin,
        httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as public,
    ):
        signed_in = await old_admin.post(
            "/api/v1/admin/auth/login",
            json={"email": email, "password": old_password},
            headers=headers,
        )
        assert signed_in.status_code == 200
        assert old_admin.cookies
        assert (await old_admin.get("/api/v1/admin/me/access")).status_code == 200

        requested = await public.post(
            "/api/v1/auth/recovery/request",
            json={"email": email},
            headers=headers,
        )
        assert requested.status_code == 202
        token = await _mail_token(maintenance, runtime, email)
        completed = await public.post(
            "/api/v1/auth/recovery/complete",
            json={"token": token, "new_password": new_password},
            headers=headers,
        )
        assert completed.status_code == 204

        # This client still holds the original admin Cookie; the server must
        # reject it after the recovery transaction commits.
        assert old_admin.cookies
        assert (await old_admin.get("/api/v1/admin/me/access")).status_code == 401
        assert (
            await public.post(
                "/api/v1/admin/auth/login",
                json={"email": email, "password": old_password},
                headers=headers,
            )
        ).status_code == 401
        new_login = await public.post(
            "/api/v1/admin/auth/login",
            json={"email": email, "password": new_password},
            headers=headers,
        )
        assert new_login.status_code == 200
        assert (await public.get("/api/v1/admin/me/access")).status_code == 200

    async with runtime.resources.database.sessions() as session:
        user = await session.scalar(select(User).where(User.email_normalized == email))
        assert user is not None
        assert user.password_version == 2 and user.security_epoch == 1
        assert (
            await session.scalar(
                select(func.count())
                .select_from(AdminAuditEvent)
                .where(
                    AdminAuditEvent.action == "password.recovered",
                    AdminAuditEvent.target_user_id == user.id,
                )
            )
            == 1
        )


@pytest.mark.parametrize("invalidator", ["expired", "wrong_purpose"])
async def test_email_challenges_reject_reuse_expiry_and_wrong_purpose(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    invalidator: str,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"challenge-{run_id}@haruka.example.test"
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        registered = await web.post(
            "/api/v1/auth/register",
            json={"email": email, "password": "synthetic-challenge-password-2026"},
            headers=headers,
        )
        assert registered.status_code == 202
        verify_token = await _mail_token(maintenance, runtime, email)
        verified = await web.post(
            "/api/v1/auth/email/verify", json={"token": verify_token}, headers=headers
        )
        assert verified.status_code == 204
        repeated_verify = await web.post(
            "/api/v1/auth/email/verify", json={"token": verify_token}, headers=headers
        )
        assert repeated_verify.status_code in {404, 410}
        existing = await web.post(
            "/api/v1/auth/recovery/request", json={"email": email}, headers=headers
        )
        unknown = await web.post(
            "/api/v1/auth/recovery/request",
            json={"email": f"missing-{run_id}@haruka.example.test"},
            headers=headers,
        )
        assert existing.status_code == unknown.status_code == 202
        assert existing.json()["data"] == unknown.json()["data"]
        recovery_token = await _mail_token(maintenance, runtime, email)
        wrong_purpose = await web.post(
            "/api/v1/auth/email/verify", json={"token": recovery_token}, headers=headers
        )
        assert wrong_purpose.status_code == 404
        if invalidator == "expired":
            async with runtime.resources.database.sessions() as session, session.begin():
                challenge = await session.scalar(
                    select(AuthChallenge)
                    .where(AuthChallenge.purpose == "password_recovery")
                    .with_for_update()
                )
                assert challenge is not None
                challenge.expires_at = challenge.created_at + timedelta(microseconds=1)
        completed = await web.post(
            "/api/v1/auth/recovery/complete",
            json={
                "token": recovery_token,
                "new_password": "synthetic-challenge-recovered-2026",
            },
            headers=headers,
        )
        if invalidator == "expired":
            assert completed.status_code == 410
        else:
            assert completed.status_code == 204
            reused = await web.post(
                "/api/v1/auth/recovery/complete",
                json={
                    "token": recovery_token,
                    "new_password": "synthetic-challenge-recovered-2026",
                },
                headers=headers,
            )
            assert reused.status_code in {404, 410}


@pytest.mark.parametrize("invalidator", ["password_version", "security_epoch", "email", "status"])
async def test_mail_worker_discards_stale_recovery_challenge(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    invalidator: str,
) -> None:
    runtime, _maintenance, run_id = identity_runtime
    email = f"admin-{run_id}@haruka.example.test"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        response = await web.post(
            "/api/v1/auth/recovery/request",
            json={"email": email},
            headers={"Origin": ORIGIN, "Content-Type": "application/json"},
        )
        assert response.status_code == 202
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        user = await session.scalar(
            select(User).where(User.email_normalized == email).with_for_update()
        )
        assert user is not None
        if invalidator == "password_version":
            user.password_version += 1
        elif invalidator == "security_epoch":
            user.security_epoch += 1
        elif invalidator == "email":
            user.email_normalized = f"new-{run_id}@haruka.example.test"
        else:
            user.status = "disabled"
    assert await claim_due_mail(runtime, uuid4()) is None
    async with runtime.resources.database.sessions() as session:
        delivery = await session.scalar(
            select(AuthChallengeDelivery).where(AuthChallengeDelivery.user_id == user.id)
        )
        assert delivery is not None
        assert delivery.status == "expired"
        assert delivery.encrypted_payload is None


async def test_outbox_retries_redis_failure_without_marking_published(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    runtime, _maintenance, _run_id = identity_runtime
    assert runtime.resources is not None
    cache = runtime.resources.cache

    async def unavailable(*_args: object, **_kwargs: object) -> object:
        raise ConnectionError("synthetic isolated Redis outage")

    with monkeypatch.context() as patch:
        patch.setattr(cache.client, "eval", unavailable)
        with pytest.raises(AppError) as failure:
            await deliver_outbox_one(runtime)
        assert failure.value.code == ErrorCode.SERVICE_UNAVAILABLE
    async with runtime.resources.database.sessions() as session:
        pending = (
            await session.scalars(select(OutboxEvent.status).order_by(OutboxEvent.created_at))
        ).all()
        assert pending and set(pending) == {"pending"}
    count = 0
    while await deliver_outbox_one(runtime):
        count += 1
        assert count < 10
    assert count >= 2
    assert await cache.client.get(cache.key("authz", "revision")) is not None
    async with runtime.resources.database.sessions() as session:
        statuses = (await session.scalars(select(OutboxEvent.status))).all()
        assert statuses and set(statuses) == {"published"}


async def test_password_change_and_recovery_race_has_one_committed_winner(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    caplog: pytest.LogCaptureFixture,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"race-{run_id}@haruka.example.test"
    original_password = "synthetic-race-original-2026"  # noqa: S105 - isolated test identity
    changed_password = "synthetic-race-changed-2026"  # noqa: S105 - isolated test identity
    recovered_password = "synthetic-race-recovered-2026"  # noqa: S105 - isolated test identity
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        registered = await web.post(
            "/api/v1/auth/register",
            json={"email": email, "password": original_password},
            headers=headers,
        )
        assert registered.status_code == 202
        verified = await web.post(
            "/api/v1/auth/email/verify",
            json={"token": await _mail_token(maintenance, runtime, email)},
            headers=headers,
        )
        assert verified.status_code == 204
        logged = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": original_password},
            headers=headers,
        )
        assert logged.status_code == 200
        csrf = (await web.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        requested = await web.post(
            "/api/v1/auth/recovery/request", json={"email": email}, headers=headers
        )
        assert requested.status_code == 202
        recovery_token = await _mail_token(maintenance, runtime, email)
        with caplog.at_level(logging.INFO, logger="app.services"):
            changed, recovered = await asyncio.gather(
                web.post(
                    "/api/v1/auth/password/change",
                    json={"current_password": original_password, "new_password": changed_password},
                    headers={**headers, "X-CSRF-Token": csrf},
                ),
                web.post(
                    "/api/v1/auth/recovery/complete",
                    json={"token": recovery_token, "new_password": recovered_password},
                    headers=headers,
                ),
            )
        assert [changed.status_code, recovered.status_code].count(204) == 1
        assert set((changed.status_code, recovered.status_code)) <= {204, 401, 404, 409, 410}
        winner_password = changed_password if changed.status_code == 204 else recovered_password
        loser_password = recovered_password if changed.status_code == 204 else changed_password
        assert (await web.get("/api/v1/me/access")).status_code == 401
        for refused_password in (original_password, loser_password):
            refused = await web.post(
                "/api/v1/auth/login",
                json={"email": email, "password": refused_password},
                headers=headers,
            )
            assert refused.status_code == 401
        accepted = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": winner_password},
            headers=headers,
        )
        assert accepted.status_code == 200
    async with runtime.resources.database.sessions() as session:
        user = await session.scalar(select(User).where(User.email_normalized == email))
        assert user is not None
        assert user.password_version == 2 and user.security_epoch == 1
        actions = (
            await session.scalars(
                select(AdminAuditEvent.action).where(
                    AdminAuditEvent.target_user_id == user.id,
                    AdminAuditEvent.action.in_(("password.changed", "password.recovered")),
                )
            )
        ).all()
        assert actions == [
            "password.changed" if changed.status_code == 204 else "password.recovered"
        ]
        success_events = [
            record
            for record in caplog.records
            if record.msg in {"auth.password.changed", "auth.password.recovered"}
        ]
        assert [record.msg for record in success_events] == [
            "auth.password.changed" if changed.status_code == 204 else "auth.password.recovered"
        ]
        assert vars(success_events[0])["user_id"] == user.id


@pytest.mark.parametrize("unsafe_role", ["protected", "admin_grant"])
async def test_admin_cannot_open_registration_with_privileged_default_role(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    unsafe_role: str,
) -> None:
    runtime, _maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        if unsafe_role == "protected":
            protected = await session.scalar(select(Role).where(Role.code == "super_admin"))
            assert protected is not None
            policy.default_role_id = protected.id
        else:
            learner = await session.scalar(select(Role).where(Role.code == "learner"))
            assert learner is not None
            session.add(
                RolePermission(
                    role_id=learner.id,
                    permission_code="admin.login",
                    effect="allow",
                    data_scope="platform_metadata",
                )
            )
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as web:
        admin = await web.post(
            "/api/v1/admin/auth/login",
            json={
                "email": f"admin-{run_id}@haruka.example.test",
                "password": "synthetic-admin-password-2026",
            },
            headers=headers,
        )
        assert admin.status_code == 200
        csrf = (await web.get("/api/v1/admin/auth/csrf")).json()["data"]["csrf_token"]
        policy_read = (await web.get("/api/v1/admin/auth-policy")).json()["data"]
        rejected = await web.patch(
            "/api/v1/admin/auth-policy",
            json={"registration_mode": "open", "expected_revision": policy_read["revision"]},
            headers={**headers, "X-CSRF-Token": csrf},
        )
        assert rejected.status_code == 503
        assert (await web.get("/api/v1/auth/policy")).json()["data"][
            "registration_enabled"
        ] is False
        registration = await web.post(
            "/api/v1/auth/register",
            json={
                "email": f"unsafe-{run_id}@haruka.example.test",
                "password": "synthetic-registration-password-2026",
            },
            headers=headers,
        )
        assert registration.status_code == 403


async def test_registration_session_and_native_refresh(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    transport = httpx.ASGITransport(app=app)
    json_headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
    email = f"alice-{run_id}@haruka.example.test"
    password = "synthetic-client-password-2026"  # noqa: S105 - isolated test identity
    admin_email = f"admin-{run_id}@haruka.example.test"
    async with httpx.AsyncClient(transport=transport, base_url=ORIGIN) as web:
        closed = await web.post(
            "/api/v1/auth/register",
            json={"email": email, "password": password},
            headers=json_headers,
        )
        assert closed.status_code == 403
        admin_login = await web.post(
            "/api/v1/admin/auth/login",
            json={"email": admin_email, "password": "synthetic-admin-password-2026"},
            headers=json_headers,
        )
        assert admin_login.status_code == 200
        admin_csrf = await web.get("/api/v1/admin/auth/csrf")
        assert admin_csrf.status_code == 200
        admin_token = admin_csrf.json()["data"]["csrf_token"]
        assert admin_csrf.json()["data"]["session_ref"] == admin_login.json()["data"]["session_ref"]
        policy = await web.get("/api/v1/admin/auth-policy")
        assert policy.status_code == 200
        opened = await web.patch(
            "/api/v1/admin/auth-policy",
            json={
                "registration_mode": "open",
                "expected_revision": policy.json()["data"]["revision"],
            },
            headers={**json_headers, "X-CSRF-Token": admin_token},
        )
        assert opened.status_code == 200
        accepted = await web.post(
            "/api/v1/auth/register",
            json={"email": email, "password": password},
            headers=json_headers,
        )
        assert accepted.status_code == 202
        pending = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
            headers=json_headers,
        )
        assert pending.status_code == 200 and pending.json()["data"]["state"] == "action_required"
        continuation = pending.json()["data"]["continuation_token"]
        progress = await web.get(
            "/api/v1/auth/activation/status", headers={"Authorization": f"Bearer {continuation}"}
        )
        assert progress.status_code == 200 and progress.json()["data"]["state"] == "pending_email"
        token = await _mail_token(maintenance, runtime, email)
        verified = await web.post(
            "/api/v1/auth/email/verify", json={"token": token}, headers=json_headers
        )
        assert verified.status_code == 204
        authenticated = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
            headers=json_headers,
        )
        assert authenticated.status_code == 200
        access = await web.get("/api/v1/me/access")
        assert access.status_code == 200
        csrf_a = await web.get("/api/v1/auth/csrf")
        csrf_b = await web.get("/api/v1/auth/csrf")
        assert csrf_a.status_code == csrf_b.status_code == 200
        assert csrf_a.json()["data"] == csrf_b.json()["data"]
        assert csrf_a.json()["data"]["session_ref"] == access.json()["data"]["session_ref"]
        refreshed = await web.post(
            "/api/v1/auth/refresh",
            json={},
            headers={**json_headers, "X-CSRF-Token": csrf_a.json()["data"]["csrf_token"]},
        )
        assert refreshed.status_code == 200
        page = await web.get("/api/v1/auth/sessions?limit=1")
        assert page.status_code == 200
        second_web_login = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
            headers=json_headers,
        )
        assert second_web_login.status_code == 200
        first_page = await web.get("/api/v1/auth/sessions?limit=1")
        assert first_page.status_code == 200
        first_data = first_page.json()
        assert first_data["meta"]["has_more"] is True
        next_page = await web.get(
            "/api/v1/auth/sessions",
            params={"limit": 1, "cursor": first_data["meta"]["next_cursor"]},
        )
        assert next_page.status_code == 200
        assert first_data["data"][0]["id"] != next_page.json()["data"][0]["id"]
        assert admin_login.json()["data"]["session_ref"] not in {
            first_data["data"][0]["id"],
            next_page.json()["data"][0]["id"],
        }
        current_csrf = (await web.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        foreign_revoke = await web.post(
            f"/api/v1/auth/sessions/{admin_login.json()['data']['session_ref']}/revoke",
            headers={**json_headers, "X-CSRF-Token": current_csrf},
        )
        assert foreign_revoke.status_code == 404
    async with httpx.AsyncClient(transport=transport, base_url="http://127.0.0.1:18081") as native:
        native_login = await native.post(
            "/api/v1/auth/native/login",
            json={"email": email, "password": password, "platform": "windows"},
        )
        assert native_login.status_code == 200
        credentials = native_login.json()["data"]
        request_id = str(uuid4())
        first = await native.post(
            "/api/v1/auth/native/refresh",
            json={"refresh_token": credentials["refresh_token"], "refresh_request_id": request_id},
        )
        assert first.status_code == 200
        replay = await native.post(
            "/api/v1/auth/native/refresh",
            json={"refresh_token": credentials["refresh_token"], "refresh_request_id": request_id},
        )
        assert replay.status_code == 200 and replay.json()["data"] == first.json()["data"]
        old_access = await native.get(
            "/api/v1/me/access", headers={"Authorization": f"Bearer {credentials['access_token']}"}
        )
        assert old_access.status_code == 200
        conflicting = await native.post(
            "/api/v1/auth/native/refresh",
            json={
                "refresh_token": credentials["refresh_token"],
                "refresh_request_id": str(uuid4()),
            },
        )
        assert conflicting.status_code == 409
        assert runtime.resources is not None
        redis_client = runtime.resources.cache.client
        original_eval = redis_client.eval
        reached = asyncio.Event()
        release = asyncio.Event()

        async def gated_eval(script: str, numkeys: int, *args: str | bytes | int | float) -> object:
            if script.startswith("return {redis.call('GET'") and not reached.is_set():
                reached.set()
                await release.wait()
            return await original_eval(script, numkeys, *args)

        with monkeypatch.context() as patch:
            patch.setattr(redis_client, "eval", gated_eval)
            stale_task = asyncio.create_task(
                native.post(
                    "/api/v1/auth/native/refresh",
                    json={
                        "refresh_token": credentials["refresh_token"],
                        "refresh_request_id": request_id,
                    },
                )
            )
            await asyncio.wait_for(reached.wait(), timeout=5)
            second = await native.post(
                "/api/v1/auth/native/refresh",
                json={
                    "refresh_token": first.json()["data"]["refresh_token"],
                    "refresh_request_id": str(uuid4()),
                },
            )
            assert second.status_code == 200
            release.set()
            stale = await stale_task
            assert stale.status_code == 409
        old_access_again = await native.get(
            "/api/v1/me/access", headers={"Authorization": f"Bearer {credentials['access_token']}"}
        )
        assert old_access_again.status_code == 200
    changed_password = "synthetic-client-updated-2026"  # noqa: S105 - isolated test identity
    recovered_password = "synthetic-client-recovered-2026"  # noqa: S105 - isolated test identity
    async with httpx.AsyncClient(transport=transport, base_url=ORIGIN) as web:
        logged = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
            headers=json_headers,
        )
        assert logged.status_code == 200
        csrf = (await web.get("/api/v1/auth/csrf")).json()["data"]["csrf_token"]
        changed = await web.post(
            "/api/v1/auth/password/change",
            json={"current_password": password, "new_password": changed_password},
            headers={**json_headers, "X-CSRF-Token": csrf},
        )
        assert changed.status_code == 204
        assert (await web.get("/api/v1/me/access")).status_code == 401
        assert runtime.resources is not None
        native_alive = runtime.resources.cache.key(
            "auth", access.json()["data"]["user_id"], credentials["session_ref"], "alive"
        )
        await runtime.resources.cache.client.set(native_alive, b"1", ex=30)
        changed_events = 0
        while await deliver_outbox_one(runtime):
            changed_events += 1
            assert changed_events < 30
        assert changed_events > 0
        assert await runtime.resources.cache.client.get(native_alive) is None
        requested = await web.post(
            "/api/v1/auth/recovery/request", json={"email": email}, headers=json_headers
        )
        assert requested.status_code == 202
        recovery_token = await _mail_token(maintenance, runtime, email)
        active_web = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": changed_password},
            headers=json_headers,
        )
        assert active_web.status_code == 200
        assert (await web.get("/api/v1/me/access")).status_code == 200
        async with httpx.AsyncClient(
            transport=transport, base_url="http://127.0.0.1:18081"
        ) as native_after_change:
            active_native = await native_after_change.post(
                "/api/v1/auth/native/login",
                json={"email": email, "password": changed_password, "platform": "android"},
            )
            assert active_native.status_code == 200
            active_token = active_native.json()["data"]["access_token"]
        recovered = await web.post(
            "/api/v1/auth/recovery/complete",
            json={"token": recovery_token, "new_password": recovered_password},
            headers=json_headers,
        )
        assert recovered.status_code == 204
        assert (await web.get("/api/v1/me/access")).status_code == 401
        async with httpx.AsyncClient(
            transport=transport, base_url="http://127.0.0.1:18081"
        ) as native_after_recovery:
            stale_access = await native_after_recovery.get(
                "/api/v1/me/access", headers={"Authorization": f"Bearer {active_token}"}
            )
            assert stale_access.status_code == 401
        old_login = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": changed_password},
            headers=json_headers,
        )
        assert old_login.status_code == 401
        new_login = await web.post(
            "/api/v1/auth/login",
            json={"email": email, "password": recovered_password},
            headers=json_headers,
        )
        assert new_login.status_code == 200
        await runtime.resources.cache.client.set(native_alive, b"1", ex=30)
        delivered = 0
        while await deliver_outbox_one(runtime):
            delivered += 1
            assert delivered < 30
        assert delivered > 0
        assert await runtime.resources.cache.client.get(native_alive) is None
        assert (await web.get("/api/v1/me/access")).status_code == 200
    assert runtime.resources is not None
    purpose = f"ttl-{run_id}"
    digest = (
        AuthCrypto.from_settings(runtime.settings).digest(f"rate-{purpose}-ip", "127.0.0.1").hex()
    )
    rate_key = runtime.resources.cache.key("auth", "rate", purpose, "ip", digest)
    await runtime.resources.cache.client.set(rate_key, b"60")
    request = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/auth/login",
            "headers": [],
            "client": ("127.0.0.1", 18081),
            "server": ("127.0.0.1", 18081),
            "scheme": "http",
        }
    )
    with pytest.raises(AppError) as limited:
        await rate_limit(request, runtime, purpose=purpose)
    assert limited.value.code == ErrorCode.RATE_LIMITED
    assert await runtime.resources.cache.client.ttl(rate_key) > 0
    engine = create_maintenance_engine(maintenance)
    try:
        async with engine.connect() as connection:
            actions = set(
                (
                    await connection.scalars(
                        select(AdminAuditEvent.action).where(
                            AdminAuditEvent.action.in_(
                                (
                                    "auth_policy.updated",
                                    "account.registered",
                                    "email.verified",
                                    "session.created",
                                    "password.changed",
                                    "password.recovered",
                                )
                            )
                        )
                    )
                ).all()
            )
            assert actions == {
                "auth_policy.updated",
                "account.registered",
                "email.verified",
                "session.created",
                "password.changed",
                "password.recovered",
            }
            event_count = await connection.scalar(
                select(OutboxEvent.id).where(OutboxEvent.event_type == "identity.security").limit(1)
            )
            assert event_count is not None
    finally:
        await engine.dispose()
