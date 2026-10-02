"""CLI dispatch and redaction boundaries; PG effects remain in integration proofs."""

import getpass
import sys
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from pydantic import SecretStr

from app.cli import manage
from app.core.settings import Settings
from app.maintenance.migrations import MigrationError, MigrationStatus
from app.maintenance.settings import MaintenanceSettings
from app.services.initialization import InitializationError, InitializationResult

pytestmark = pytest.mark.unit


@pytest.mark.parametrize(
    "args",
    [
        [],
        ["db", "apply", "--maintenance-config", "owned.env"],
        ["db", "status", "--maintenance-config", "owned.env"],
        ["admin", "init", "--maintenance-config", "owned.env"],
    ],
)
def test_invalid_maintenance_action_never_loads_or_prompts(
    monkeypatch: pytest.MonkeyPatch, args: list[str]
) -> None:
    def forbidden(*args: object, **kwargs: object) -> None:
        pytest.fail("invalid maintenance command reached target or password")

    monkeypatch.setattr(sys, "argv", ["haruka-manage", *args])
    monkeypatch.setattr(manage, "load_maintenance_settings", forbidden)
    monkeypatch.setattr(manage, "read_password", forbidden)
    with pytest.raises(SystemExit) as rejected:
        manage.main()
    assert rejected.value.code == 2


@pytest.mark.parametrize(
    "operation", ["status", "upgrade", "incompatible", "seed", "admin", "avatar", "failure"]
)
def test_maintenance_dispatch_keeps_explicit_target_and_safe_result(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path: Path,
    operation: str,
) -> None:
    target = MaintenanceSettings(
        database_url=SecretStr(
            "postgresql+asyncpg://haruka_test_maintenance:fake@127.0.0.1:15432/haruka_test"
        )
    )
    config = tmp_path / "maintenance.env"
    migrations = tmp_path / "migration-bundle"
    command = (
        "db"
        if operation in {"status", "upgrade", "incompatible", "failure"}
        else {"seed": "seed", "admin": "admin", "avatar": "avatar-gc"}[operation]
    )
    action = (
        ("upgrade" if operation == "upgrade" else "status")
        if command == "db"
        else ("init" if command == "admin" else "apply")
    )
    argv = [
        "haruka-manage",
        command,
        action,
        "--maintenance-config",
        str(config),
        "--migrations-dir",
        str(migrations),
        "--email",
        "synthetic-admin@example.test",
    ]
    monkeypatch.setattr(sys, "argv", argv)
    calls: list[str] = []

    def load(path: Path) -> MaintenanceSettings:
        assert path == config
        return target

    def logging(_settings: Settings, role: str) -> None:
        assert role == "manage"

    async def status(selected: MaintenanceSettings, bundle: Path) -> MigrationStatus:
        assert selected is target and bundle == migrations
        calls.append("db")
        if operation == "failure":
            raise MigrationError("private driver details must not escape")
        return MigrationStatus(
            "0013_outbox_delivery_lease",
            "0013_outbox_delivery_lease",
            operation != "incompatible",
            "public",
            (),
            1,
        )

    async def seed(selected: MaintenanceSettings) -> InitializationResult:
        assert selected is target
        calls.append("seed")
        return InitializationResult(True, 2)

    async def administrator(
        selected: MaintenanceSettings, *, email: str, password: SecretStr
    ) -> InitializationResult:
        assert selected is target and email == "synthetic-admin@example.test"
        assert password.get_secret_value() == "synthetic-hidden-password-2026"
        calls.append("admin")
        return InitializationResult(True, 2)

    async def avatars(selected: MaintenanceSettings) -> tuple[int, int]:
        assert selected is target
        calls.append("avatar")
        return 2, 3

    def hidden_password() -> SecretStr:
        return SecretStr("synthetic-hidden-password-2026")

    monkeypatch.setattr(manage, "load_maintenance_settings", load)
    monkeypatch.setattr(manage, "configure_logging", logging)
    monkeypatch.setattr(manage, "database_status", status)
    monkeypatch.setattr(manage, "upgrade_database", status)
    monkeypatch.setattr(manage, "apply_seed", seed)
    monkeypatch.setattr(manage, "initialize_admin", administrator)
    monkeypatch.setattr(manage, "_collect_avatars", avatars)
    monkeypatch.setattr(manage, "read_password", hidden_password)
    if operation in {"failure", "incompatible"}:
        with pytest.raises(SystemExit) as failed:
            manage.main()
        assert failed.value.code == 2
    else:
        manage.main()
    assert len(calls) == 1
    output = capsys.readouterr()
    assert "private driver" not in output.err and "synthetic-hidden-password" not in output.out
    if operation == "failure":
        assert "Maintenance failed" in output.err


@pytest.mark.parametrize("second", ["synthetic-hidden-password-2026", "mismatch", "eof"])
def test_password_confirmation_never_uses_echoing_fallback(
    monkeypatch: pytest.MonkeyPatch, second: str
) -> None:
    values = iter(["synthetic-hidden-password-2026", second])

    def prompt(_message: str) -> str:
        value = next(values)
        if value == "eof":
            raise EOFError
        return value

    monkeypatch.setattr(getpass, "getpass", prompt)
    if second == "synthetic-hidden-password-2026":
        assert manage.read_password().get_secret_value() == second
    else:
        with pytest.raises(InitializationError):
            manage.read_password()


@pytest.mark.parametrize("command", ["check-config", "check-infrastructure"])
def test_maintenance_checks_cannot_dispatch_write_actions(
    monkeypatch: pytest.MonkeyPatch, command: str
) -> None:
    settings = Settings(
        app_env="test", instance_id="haruka-test-manage", public_base_url="http://localhost:8000"
    )
    calls: list[str] = []

    def checked(_path: Path | None) -> Settings:
        return settings

    def resources(selected: Settings, role: str) -> None:
        assert selected is settings and role == "manage"
        calls.append(role)

    def forbidden(*args: object) -> None:
        pytest.fail("read-only maintenance check entered write dispatch")

    monkeypatch.setattr(sys, "argv", ["haruka-manage", command])
    monkeypatch.setattr(manage, "checked_settings", checked)
    monkeypatch.setattr(manage, "check_resources", resources)
    monkeypatch.setattr(manage, "load_maintenance_settings", forbidden)
    manage.main()
    assert calls == (["manage"] if command == "check-infrastructure" else [])


@pytest.mark.asyncio
@pytest.mark.parametrize("fault", ["none", "schema", "collection"])
async def test_avatar_gc_entry_always_disposes_engine_before_propagating_failure(
    monkeypatch: pytest.MonkeyPatch, fault: str
) -> None:
    target = MaintenanceSettings(
        database_url=SecretStr(
            "postgresql+asyncpg://haruka_test_maintenance:fake@127.0.0.1:15432/haruka_test"
        )
    )
    engine = AsyncMock()
    sessions = object()

    def create(selected: MaintenanceSettings) -> object:
        assert selected is target
        return engine

    def factory(selected: object, *, expire_on_commit: bool) -> object:
        assert selected is engine and expire_on_commit is False
        return sessions

    async def schema(selected: object, *, schema: str) -> None:
        assert selected is engine and schema == target.database_schema
        if fault == "schema":
            raise MigrationError("synthetic schema mismatch")

    async def collect(selected: object) -> tuple[int, int]:
        assert selected is sessions
        if fault == "collection":
            raise MigrationError("synthetic collection failure")
        return 1, 2

    monkeypatch.setattr(manage, "create_maintenance_engine", create)
    monkeypatch.setattr(manage, "async_sessionmaker", factory)
    monkeypatch.setattr(manage, "check_schema", schema)
    monkeypatch.setattr(manage, "collect_avatar_garbage", collect)
    if fault == "none":
        assert await manage._collect_avatars(target) == (1, 2)  # pyright: ignore[reportPrivateUsage]
    else:
        with pytest.raises(MigrationError):
            await manage._collect_avatars(target)  # pyright: ignore[reportPrivateUsage]
    engine.dispose.assert_awaited_once()
