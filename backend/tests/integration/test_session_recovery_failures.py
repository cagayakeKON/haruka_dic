"""Real Redis refresh corruption and lost cache fail closed without rotating PG identity."""

import json
from datetime import UTC, datetime, timedelta, tzinfo
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from pydantic import SecretStr
from sqlalchemy import select

from app.bootstrap import Runtime
from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.main import create_app
from app.maintenance.settings import MaintenanceSettings
from app.models import AuthChallenge, AuthPolicy, AuthSession, User
from app.schemas.auth import ActivationRequired, NativeAuthenticated, WebAuthenticated
from app.services import registration, sessions
from app.services.auth_context import verify_scope_in_transaction
from app.services.auth_crypto import AuthCrypto
from tests.integration.test_authentication_flow import (
    ORIGIN,
    _mail_token,  # pyright: ignore[reportPrivateUsage]
)
from tests.integration.test_authentication_flow import (
    identity_runtime as identity_runtime,
)
from tests.support.bound_client import BoundAsyncClient

pytestmark = [pytest.mark.integration, pytest.mark.asyncio]


async def test_refresh_corrupt_cache_never_rotates_or_discloses_identity(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    email = f"refresh-fault-{run_id}@haruka.example.test"
    password = "synthetic-refresh-fault-password-2026"  # noqa: S105 - isolated test identity
    transport = httpx.ASGITransport(app=app)
    async with BoundAsyncClient(transport=transport, base_url=ORIGIN) as web:
        headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
        created = await web.post(
            "/api/v1/auth/register", json={"email": email, "password": password}, headers=headers
        )
        assert created.status_code == 202
        token = await _mail_token(maintenance, runtime, email)
        verified = await web.post(
            "/api/v1/auth/email/verify", json={"token": token}, headers=headers
        )
        assert verified.status_code == 204
    async with BoundAsyncClient(transport=transport, base_url="http://127.0.0.1:18081") as native:
        login = await native.post(
            "/api/v1/auth/native/login",
            json={"email": email, "password": password, "platform": "android"},
        )
        assert login.status_code == 200
        credentials = login.json()["data"]
        crypto = AuthCrypto.from_settings(runtime.settings)
        user_id, session_id, _ = crypto.decode_access(credentials["access_token"])
        cache = runtime.resources.cache
        digest = crypto.digest("native-refresh", credentials["refresh_token"]).hex()
        index = cache.key("auth", "refresh", "index", digest)
        state = cache.key("auth", str(user_id), str(session_id), "refresh")
        alive = cache.key("auth", str(user_id), str(session_id), "alive")
        snapshots = {key: await cache.client.get(key) for key in (index, state, alive)}
        assert all(isinstance(value, bytes) for value in snapshots.values())
        faults = [
            (index, None, 401),
            (index, b"bad-index", 401),
            (index, b"\xff", 503),
            (index, f"{user_id}:{session_id}:0".encode(), 401),
            (alive, None, 401),
            (state, None, 401),
            (state, b"not-json", 503),
            (state, b"{}", 401),
            (state, json.dumps({"digest": digest, "generation": 99}).encode(), 401),
        ]
        for key, invalid, expected in faults:
            if invalid is None:
                await cache.client.delete(key)
            else:
                await cache.client.set(key, invalid, ex=60)
            rejected = await native.post(
                "/api/v1/auth/native/refresh",
                json={
                    "refresh_token": credentials["refresh_token"],
                    "refresh_request_id": str(uuid4()),
                },
            )
            assert rejected.status_code == expected
            assert credentials["refresh_token"] not in rejected.text and email not in rejected.text
            for original_key, value in snapshots.items():
                assert isinstance(value, bytes)
                await cache.client.set(original_key, value, ex=3600)
        async with runtime.resources.database.sessions() as session:
            persisted = await session.scalar(
                select(AuthSession).where(AuthSession.id == UUID(credentials["session_ref"]))
            )
            assert (
                persisted is not None
                and persisted.revoked_at is None
                and persisted.security_epoch == 0
            )
        successful = await native.post(
            "/api/v1/auth/native/refresh",
            json={
                "refresh_token": credentials["refresh_token"],
                "refresh_request_id": str(uuid4()),
            },
        )
        assert (
            successful.status_code == 200 and successful.json()["data"]["session_generation"] == 2
        )


async def test_activation_cache_corruption_never_exposes_account(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, _, _ = identity_runtime
    assert runtime.resources is not None
    crypto = AuthCrypto.from_settings(runtime.settings)
    continuation = "synthetic-continuation"
    key = runtime.resources.cache.key(
        "auth", "continuation", crypto.digest("continuation", continuation).hex()
    )
    for binding, expected in [
        (None, ErrorCode.RESOURCE_EXPIRED),
        (b"invalid-uuid", ErrorCode.SERVICE_UNAVAILABLE),
        (b"\xff", ErrorCode.SERVICE_UNAVAILABLE),
        (str(uuid4()).encode(), ErrorCode.RESOURCE_EXPIRED),
    ]:
        if binding is not None:
            await runtime.resources.cache.client.set(key, binding, ex=60)
        else:
            await runtime.resources.cache.client.delete(key)
        with pytest.raises(AppError) as rejected:
            await registration.activation_status(runtime, continuation=continuation)
        assert rejected.value.code == expected
        assert continuation not in str(rejected.value)


async def test_registration_dependency_failure_rolls_back_and_preserves_safe_errors(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, _, run_id = identity_runtime

    async def unavailable(*args: object, **kwargs: object) -> None:
        raise RuntimeError("private dependency failure")

    async def forbidden(*args: object, **kwargs: object) -> None:
        raise AppError(ErrorCode.PERMISSION_DENIED)

    for injected, expected in [
        (unavailable, ErrorCode.SERVICE_UNAVAILABLE),
        (forbidden, ErrorCode.PERMISSION_DENIED),
    ]:
        with monkeypatch.context() as patch:
            patch.setattr(registration, "_policy", injected)
            with pytest.raises(AppError) as failed:
                await registration.register(
                    runtime,
                    email=f"fault-{run_id}@haruka.example.test",
                    password=SecretStr("synthetic-password-2026"),
                )
            assert failed.value.code == expected
            with pytest.raises(AppError) as failed:
                await registration.request_challenge(
                    runtime,
                    email=f"fault-{run_id}@haruka.example.test",
                    purpose="password_recovery",
                )
            assert failed.value.code == expected
        for operation in ("verify", "recover", "manual"):
            with monkeypatch.context() as patch:
                patch.setattr(
                    registration,
                    "challenge_identity_by_digest"
                    if operation != "manual"
                    else "open_manual_recovery",
                    injected,
                )
                with pytest.raises(AppError) as failed:
                    if operation == "verify":
                        await registration.verify_email(runtime, token=SecretStr("synthetic-token"))
                    elif operation == "recover":
                        await registration.complete_recovery(
                            runtime,
                            token=SecretStr("synthetic-token"),
                            new_password=SecretStr("synthetic-password-2026"),
                        )
                    else:
                        await registration.request_manual_recovery(
                            runtime, email=f"fault-{run_id}@haruka.example.test"
                        )
                assert failed.value.code == expected
                assert "private dependency" not in str(failed.value)
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session:
        assert (
            await session.scalar(
                select(User.id).where(
                    User.email_normalized == f"fault-{run_id}@haruka.example.test"
                )
            )
            is None
        )


async def test_email_verification_rechecks_every_persistent_challenge_fence(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"verify-fence-{run_id}@haruka.example.test"
    await registration.register(runtime, email=email, password=SecretStr("synthetic-password-2026"))
    token = SecretStr(await _mail_token(maintenance, runtime, email))
    async with runtime.resources.database.sessions() as session:
        holder = await session.scalar(select(User).where(User.email_normalized == email))
        assert holder is not None
        challenge = await session.scalar(
            select(AuthChallenge).where(AuthChallenge.user_id == holder.id)
        )
        assert challenge is not None
        user_id, challenge_id = holder.id, challenge.id
        original = {
            name: getattr(challenge, name)
            for name in (
                "consumed_at",
                "revoked_at",
                "expires_at",
                "security_epoch",
                "password_version",
                "target_email_digest",
            )
        }
    faults = {
        "consumed_at": datetime.now(UTC),
        "revoked_at": datetime.now(UTC),
        "expires_at": datetime.now(UTC) - timedelta(seconds=1),
        "security_epoch": 99,
        "password_version": 99,
        "target_email_digest": b"x" * 32,
    }
    for field, invalid in faults.items():
        async with runtime.resources.database.sessions() as session, session.begin():
            await session.get(User, user_id, with_for_update=True)
            row = await session.get(AuthChallenge, challenge_id, with_for_update=True)
            assert row is not None
            if field != "expires_at":
                setattr(row, field, invalid)
        with monkeypatch.context() as patch:
            if field == "expires_at":

                class FutureClock(datetime):
                    @classmethod
                    def now(cls, tz: tzinfo | None = None) -> datetime:
                        return datetime.now(tz) + timedelta(days=2)

                patch.setattr(registration, "datetime", FutureClock)
            with pytest.raises(AppError) as rejected:
                await registration.verify_email(runtime, token=token)
        assert rejected.value.code == ErrorCode.RESOURCE_EXPIRED
        async with runtime.resources.database.sessions() as session, session.begin():
            user = await session.get(User, user_id, with_for_update=True)
            row = await session.get(AuthChallenge, challenge_id, with_for_update=True)
            assert user is not None and user.status == "pending" and user.email_verified_at is None
            assert row is not None
            setattr(row, field, original[field])
    await registration.verify_email(runtime, token=token)
    async with runtime.resources.database.sessions() as session:
        user = await session.get(User, user_id)
        assert user is not None and user.status == "active" and user.email_verified_at is not None


@pytest.mark.parametrize("cache_delete_fault", [False, True])
async def test_expired_refresh_receipt_replay_revokes_pg_even_if_cache_delete_fails(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    cache_delete_fault: bool,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"refresh-replay-{run_id}@haruka.example.test"
    password = SecretStr("synthetic-refresh-replay-password-2026")
    await registration.register(runtime, email=email, password=password)
    await registration.verify_email(
        runtime, token=SecretStr(await _mail_token(maintenance, runtime, email))
    )
    authenticated = await sessions.login(
        runtime,
        email=email,
        password=password,
        audience="client",
        transport="native",
        platform="android",
    )
    original = authenticated.response
    assert isinstance(original, NativeAuthenticated)
    crypto = AuthCrypto.from_settings(runtime.settings)
    digest = crypto.digest("native-refresh", original.refresh_token).hex()
    receipt = runtime.resources.cache.key("auth", "refresh", "receipt", digest)
    advanced = await sessions.refresh_native(
        runtime, refresh_token=SecretStr(original.refresh_token), refresh_request_id=uuid4()
    )
    assert advanced.session_generation == 2
    await runtime.resources.cache.client.delete(receipt)

    async def unavailable(*keys: object) -> int:
        raise OSError("synthetic cache delete outage")

    with monkeypatch.context() as patch:
        if cache_delete_fault:
            patch.setattr(runtime.resources.cache.client, "delete", unavailable)
        with pytest.raises(AppError) as rejected:
            await sessions.refresh_native(
                runtime, refresh_token=SecretStr(original.refresh_token), refresh_request_id=uuid4()
            )
        assert rejected.value.code == ErrorCode.SESSION_REVOKED
    async with runtime.resources.database.sessions() as session:
        persisted = await session.get(AuthSession, original.session_ref)
        assert persisted is not None and persisted.revoked_at is not None
        assert persisted.revoke_reason_code == "refresh_replay"
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with BoundAsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://127.0.0.1:18081"
    ) as native:
        revoked = await native.get(
            "/api/v1/me/access", headers={"Authorization": f"Bearer {advanced.access_token}"}
        )
        assert revoked.status_code == 401
        assert email not in revoked.text and advanced.refresh_token not in revoked.text


async def test_refresh_receipt_binds_request_generation_and_issued_tokens(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"receipt-fence-{run_id}@haruka.example.test"
    password = SecretStr("synthetic-receipt-fence-password-2026")
    await registration.register(runtime, email=email, password=password)
    await registration.verify_email(
        runtime, token=SecretStr(await _mail_token(maintenance, runtime, email))
    )
    login = await sessions.login(
        runtime,
        email=email,
        password=password,
        audience="client",
        transport="native",
        platform="android",
    )
    original = login.response
    assert isinstance(original, NativeAuthenticated)
    request_id = uuid4()
    advanced = await sessions.refresh_native(
        runtime, refresh_token=SecretStr(original.refresh_token), refresh_request_id=request_id
    )
    crypto = AuthCrypto.from_settings(runtime.settings)
    digest = crypto.digest("native-refresh", original.refresh_token).hex()
    key = runtime.resources.cache.key("auth", "refresh", "receipt", digest)
    baseline = {
        "request_id": str(request_id),
        "generation": 2,
        "response": advanced.model_dump(mode="json"),
    }
    for fault in (
        "invalid_cipher",
        "invalid_json",
        "response_missing",
        "request",
        "generation",
        "issued_generation",
        "issued_digest",
    ):
        response = advanced.model_dump(mode="json")
        payload: dict[str, object] = {
            "request_id": str(request_id),
            "generation": 2,
            "response": response,
        }
        expected = ErrorCode.REFRESH_SUPERSEDED
        if fault == "request":
            payload["request_id"] = str(uuid4())
        elif fault == "generation":
            payload["generation"] = 3
        elif fault == "issued_generation":
            response["session_generation"] = 3
        elif fault == "issued_digest":
            response["refresh_token"] = "x" * 43
        elif fault == "response_missing":
            payload["response"] = None
            expected = ErrorCode.SERVICE_UNAVAILABLE
        encrypted = crypto.encrypt_refresh_receipt(json.dumps(payload).encode())
        if fault == "invalid_cipher":
            encrypted = b"corrupt-cipher"
            expected = ErrorCode.SESSION_INVALID
        elif fault == "invalid_json":
            encrypted = crypto.encrypt_refresh_receipt(b"not-json")
            expected = ErrorCode.SERVICE_UNAVAILABLE
        await runtime.resources.cache.client.set(key, encrypted, ex=60)
        with pytest.raises(AppError) as rejected:
            await sessions.refresh_native(
                runtime,
                refresh_token=SecretStr(original.refresh_token),
                refresh_request_id=request_id,
            )
        assert rejected.value.code == expected
        assert original.refresh_token not in str(rejected.value)
    await runtime.resources.cache.client.set(
        key, crypto.encrypt_refresh_receipt(json.dumps(baseline).encode()), ex=60
    )
    assert (
        await sessions.refresh_native(
            runtime, refresh_token=SecretStr(original.refresh_token), refresh_request_id=request_id
        )
        == advanced
    )
    async with runtime.resources.database.sessions() as session:
        persisted = await session.get(AuthSession, original.session_ref)
        assert persisted is not None and persisted.revoked_at is None


async def test_partial_cache_issuance_never_leaves_a_live_pg_session(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"issuance-fence-{run_id}@haruka.example.test"
    password = SecretStr("synthetic-issuance-fence-password-2026")
    await registration.register(runtime, email=email, password=password)
    await registration.verify_email(
        runtime, token=SecretStr(await _mail_token(maintenance, runtime, email))
    )
    original_set = runtime.resources.cache.client.set
    for transport in ("web", "native"):
        for fail_at in (1, 2, 3):
            count = 0

            async def fail_set(
                name: str, value: str | bytes, *, ex: int, fail_point: int = fail_at
            ) -> object:
                nonlocal count
                count += 1
                if count == fail_point:
                    raise OSError("synthetic cache issuance outage")
                return await original_set(name, value, ex=ex)

            with monkeypatch.context() as patch:
                patch.setattr(runtime.resources.cache.client, "set", fail_set)
                with pytest.raises(AppError) as rejected:
                    await sessions.login(
                        runtime,
                        email=email,
                        password=password,
                        audience="client",
                        transport="web" if transport == "web" else "native",
                        platform="web" if transport == "web" else "android",
                    )
                assert rejected.value.code == ErrorCode.SERVICE_UNAVAILABLE
                assert count == fail_at
            async with runtime.resources.database.sessions() as session:
                rows = (
                    await session.scalars(
                        select(AuthSession)
                        .join(User, AuthSession.user_id == User.id)
                        .where(User.email_normalized == email)
                    )
                ).all()
                assert len(rows) == (fail_at if transport == "web" else 3 + fail_at)
                assert all(
                    row.revoked_at is not None and row.revoke_reason_code == "issuance_failed"
                    for row in rows
                )
    successful = await sessions.login(
        runtime,
        email=email,
        password=password,
        audience="client",
        transport="native",
        platform="android",
    )
    assert isinstance(successful.response, NativeAuthenticated)


@pytest.mark.parametrize("audience", ["client", "admin"])
async def test_revoke_all_is_audience_scoped_and_pg_authoritative_during_cache_outage(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    audience: str,
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    chosen = "client" if audience == "client" else "admin"
    email = f"admin-{run_id}@haruka.example.test"
    password = SecretStr("synthetic-admin-password-2026")
    if chosen == "client":
        async with runtime.resources.database.sessions() as session, session.begin():
            policy = await session.get(AuthPolicy, "registration", with_for_update=True)
            assert policy is not None
            policy.registration_mode = "open"
        email = f"revoke-all-{run_id}@haruka.example.test"
        password = SecretStr("synthetic-revoke-all-password-2026")
        await registration.register(runtime, email=email, password=password)
        await registration.verify_email(
            runtime, token=SecretStr(await _mail_token(maintenance, runtime, email))
        )
    first = await sessions.login(
        runtime, email=email, password=password, audience=chosen, transport="web", platform="web"
    )
    second = await sessions.login(
        runtime, email=email, password=password, audience=chosen, transport="web", platform="web"
    )
    assert isinstance(first.response, WebAuthenticated)
    assert isinstance(second.response, WebAuthenticated)
    async with runtime.resources.database.sessions() as session:
        user_id = await session.scalar(
            select(AuthSession.user_id).where(AuthSession.id == first.response.session_ref)
        )
        assert user_id is not None
        scope = await verify_scope_in_transaction(
            session,
            user_id=user_id,
            session_id=first.response.session_ref,
            audience=chosen,
            transport="web",
        )

    async def unavailable(*keys: object) -> int:
        raise OSError("synthetic cache delete outage")

    with monkeypatch.context() as patch:
        patch.setattr(runtime.resources.cache.client, "delete", unavailable)
        await sessions.revoke_session(runtime, scope, target_id=scope.user_id, all_audience=True)
    async with runtime.resources.database.sessions() as session:
        user = await session.get(User, user_id)
        assert user is not None and user.security_epoch == 0 and user.password_version == 1
        assert user.client_security_epoch == (1 if chosen == "client" else 0)
        assert user.admin_security_epoch == (1 if chosen == "admin" else 0)
        for identifier in (first.response.session_ref, second.response.session_ref):
            row = await session.get(AuthSession, identifier)
            assert (
                row is not None
                and row.revoked_at is not None
                and row.revoke_reason_code == "user_requested"
            )
    app = create_app(runtime.settings)
    app.state.runtime = runtime
    async with BoundAsyncClient(transport=httpx.ASGITransport(app=app), base_url=ORIGIN) as client:
        assert first.web_cookie is not None
        client.cookies.set(f"haruka_{chosen}_session", first.web_cookie)
        response = await client.get(
            "/api/v1/me/access" if chosen == "client" else "/api/v1/admin/me/access"
        )
        assert response.status_code == 401


async def test_email_resend_cooldown_and_supersession_preserve_single_account(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"resend-fence-{run_id}@haruka.example.test"
    password = SecretStr("synthetic-resend-fence-password-2026")
    assert (
        await registration.register(runtime, email=email, password=password)
    ).next_step == "verify_email"
    old_token = SecretStr(await _mail_token(maintenance, runtime, email))
    assert (
        await registration.register(runtime, email=email, password=password)
    ).next_step == "verify_email"
    await registration.request_challenge(runtime, email=email, purpose="email_verify")
    async with runtime.resources.database.sessions() as session:
        user_ids = (
            await session.scalars(select(User.id).where(User.email_normalized == email))
        ).all()
        assert len(user_ids) == 1
        user_id = user_ids[0]
        challenges = (
            await session.scalars(select(AuthChallenge).where(AuthChallenge.user_id == user_id))
        ).all()
        assert len(challenges) == 1 and challenges[0].revoked_at is None

    class LaterClock(datetime):
        @classmethod
        def now(cls, tz: tzinfo | None = None) -> datetime:
            return datetime.now(tz) + timedelta(seconds=61)

    with monkeypatch.context() as patch:
        patch.setattr(registration, "datetime", LaterClock)
        await registration.request_challenge(runtime, email=email, purpose="email_verify")
    async with runtime.resources.database.sessions() as session:
        challenges = (
            await session.scalars(select(AuthChallenge).where(AuthChallenge.user_id == user_id))
        ).all()
        assert len(challenges) == 2 and sum(row.revoked_at is not None for row in challenges) == 1
    with pytest.raises(AppError) as superseded:
        await registration.verify_email(runtime, token=old_token)
    assert superseded.value.code == ErrorCode.RESOURCE_EXPIRED
    await registration.verify_email(
        runtime, token=SecretStr(await _mail_token(maintenance, runtime, email))
    )


async def test_manual_recovery_is_indistinguishable_and_deduplicates_open_request(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
) -> None:
    runtime, _, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.recovery_mode = "manual"
    email = f"admin-{run_id}@haruka.example.test"
    first = await registration.request_manual_recovery(runtime, email=email)
    repeated = await registration.request_manual_recovery(runtime, email=email)
    unknown = await registration.request_manual_recovery(
        runtime, email=f"missing-{run_id}@haruka.example.test"
    )
    assert first == repeated == unknown
    async with runtime.resources.database.sessions() as session:
        rows = (
            await session.scalars(
                select(AuthChallenge).where(AuthChallenge.purpose == "manual_recovery")
            )
        ).all()
        assert len(rows) == 1 and rows[0].consumed_at is None and rows[0].revoked_at is None


@pytest.mark.parametrize("changed_field", ["password_version", "security_epoch"])
async def test_password_observation_cas_cannot_overwrite_intervening_security_commit(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str],
    monkeypatch: pytest.MonkeyPatch,
    changed_field: str,
) -> None:
    runtime, _, run_id = identity_runtime
    assert runtime.resources is not None
    current_password = SecretStr("synthetic-admin-password-2026")
    login = await sessions.login(
        runtime,
        email=f"admin-{run_id}@haruka.example.test",
        password=current_password,
        audience="admin",
        transport="web",
        platform="web",
    )
    assert isinstance(login.response, WebAuthenticated)
    async with runtime.resources.database.sessions() as session:
        user_id = await session.scalar(
            select(AuthSession.user_id).where(AuthSession.id == login.response.session_ref)
        )
        assert user_id is not None
        scope = await verify_scope_in_transaction(
            session,
            user_id=user_id,
            session_id=login.response.session_ref,
            audience="admin",
            transport="web",
        )
    original_hash = sessions.hash_password
    competing_hash = await original_hash(SecretStr("synthetic-competing-password-2026"))
    calls = 0

    async def intervening(password: SecretStr) -> str:
        nonlocal calls
        calls += 1
        replacement = await original_hash(password)
        assert runtime.resources is not None
        async with runtime.resources.database.sessions() as session, session.begin():
            await sessions.global_revision_for_update(session)
            user = await session.get(User, user_id, with_for_update=True)
            assert user is not None
            if changed_field == "password_version":
                user.password_hash = competing_hash
                user.password_version += 1
            else:
                user.security_epoch += 1
            user.revision += 1
        return replacement

    with monkeypatch.context() as patch:
        patch.setattr(sessions, "hash_password", intervening)
        with pytest.raises(AppError) as conflicted:
            await sessions.change_password(
                runtime,
                scope,
                current_password=current_password,
                new_password=SecretStr("synthetic-requested-password-2026"),
            )
        assert conflicted.value.code == ErrorCode.REVISION_CONFLICT
    assert calls == 1
    async with runtime.resources.database.sessions() as session:
        user = await session.get(User, user_id)
        assert user is not None
        assert user.password_version == (2 if changed_field == "password_version" else 1)
        assert user.security_epoch == (1 if changed_field == "security_epoch" else 0)
        if changed_field == "password_version":
            assert user.password_hash == competing_hash
        actor = await session.get(AuthSession, login.response.session_ref)
        assert actor is not None and actor.revoked_at is None


async def test_pending_login_continuation_rechecks_persistent_activation_state(
    identity_runtime: tuple[Runtime, MaintenanceSettings, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    runtime, maintenance, run_id = identity_runtime
    assert runtime.resources is not None
    async with runtime.resources.database.sessions() as session, session.begin():
        policy = await session.get(AuthPolicy, "registration", with_for_update=True)
        assert policy is not None
        policy.registration_mode = "open"
    email = f"continuation-fence-{run_id}@haruka.example.test"
    password = SecretStr("synthetic-continuation-fence-password-2026")
    await registration.register(runtime, email=email, password=password)

    async def unavailable(*args: object, **kwargs: object) -> None:
        raise OSError("synthetic continuation cache outage")

    with monkeypatch.context() as patch:
        patch.setattr(runtime.resources.cache.client, "set", unavailable)
        with pytest.raises(AppError) as rejected:
            await sessions.login(
                runtime,
                email=email,
                password=password,
                audience="client",
                transport="web",
                platform="web",
            )
        assert rejected.value.code == ErrorCode.SERVICE_UNAVAILABLE
    login = await sessions.login(
        runtime, email=email, password=password, audience="client", transport="web", platform="web"
    )
    continuation = login.response
    assert (
        isinstance(continuation, ActivationRequired)
        and continuation.action_required == "verify_email"
    )
    assert (
        await registration.activation_status(runtime, continuation=continuation.continuation_token)
    ).state == "pending_email"
    for status in ("disabled", "active"):
        async with runtime.resources.database.sessions() as session, session.begin():
            user = await session.scalar(
                select(User).where(User.email_normalized == email).with_for_update()
            )
            assert user is not None and user.email_verified_at is None
            user.status = status
        with pytest.raises(AppError) as rejected:
            await registration.activation_status(
                runtime, continuation=continuation.continuation_token
            )
        assert rejected.value.code == ErrorCode.RESOURCE_EXPIRED
    async with runtime.resources.database.sessions() as session, session.begin():
        user = await session.scalar(
            select(User).where(User.email_normalized == email).with_for_update()
        )
        assert user is not None
        user.status = "pending"
    await registration.verify_email(
        runtime, token=SecretStr(await _mail_token(maintenance, runtime, email))
    )
    assert (
        await registration.activation_status(runtime, continuation=continuation.continuation_token)
    ).state == "active"
