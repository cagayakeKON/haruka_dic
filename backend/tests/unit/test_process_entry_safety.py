"""Process entries keep checks side-effect free and redact startup failures."""

import asyncio
import importlib
import sys
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from types import ModuleType

import pytest
import uvicorn

from app.bootstrap import InfrastructureUnavailable, Runtime
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError

pytestmark = pytest.mark.unit


@pytest.fixture
def process_settings() -> Settings:
    return Settings(
        app_env="test", instance_id="haruka-test-process", public_base_url="http://localhost:8000"
    )


def entry(monkeypatch: pytest.MonkeyPatch, name: str, arguments: list[str]) -> ModuleType:
    module = importlib.import_module(f"app.cli.{name}")
    monkeypatch.setattr(sys, "argv", [f"haruka-{name}", *arguments])
    return module


def configure_entry(
    monkeypatch: pytest.MonkeyPatch, module: ModuleType, settings: Settings
) -> None:
    def checked(_config: object) -> Settings:
        return settings

    def no_logging(*args: object) -> None:
        pass

    monkeypatch.setattr(module, "checked_settings", checked)
    monkeypatch.setattr(module, "configure_logging", no_logging)


@pytest.mark.parametrize("name", ["api", "worker", "outbox", "mail"])
def test_config_check_never_starts_resources(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    process_settings: Settings,
    name: str,
) -> None:
    module = entry(monkeypatch, name, ["--check-config"])
    configure_entry(monkeypatch, module, process_settings)

    def forbidden(*args: object, **kwargs: object) -> None:
        pytest.fail("configuration-only command started runtime work")

    monkeypatch.setattr(module, "configure_logging", forbidden)
    module.main()
    assert "Configuration valid" in capsys.readouterr().out


@pytest.mark.parametrize("name", ["worker", "outbox"])
def test_startup_check_never_enters_business_loop(
    monkeypatch: pytest.MonkeyPatch, process_settings: Settings, name: str
) -> None:
    module = entry(monkeypatch, name, ["--check-startup"])
    checked: list[str] = []
    configure_entry(monkeypatch, module, process_settings)

    def check(_settings: Settings, role: str) -> None:
        checked.append(role)

    monkeypatch.setattr(module, "check_resources", check)
    module.main()
    assert checked == [name]


@pytest.mark.parametrize("name", ["worker", "outbox"])
def test_lifecycle_failure_is_safe_and_exits_nonzero(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    process_settings: Settings,
    name: str,
) -> None:
    module = entry(monkeypatch, name, ["--lifecycle-only"])
    configure_entry(monkeypatch, module, process_settings)

    async def failed(*args: object) -> None:
        raise InfrastructureUnavailable("private dependency details must not escape")

    monkeypatch.setattr(module, "run_lifecycle", failed)
    with pytest.raises(SystemExit) as raised:
        module.main()
    assert raised.value.code == 2
    output = capsys.readouterr()
    assert "lifecycle failed" in output.err
    assert "private dependency" not in output.err


@pytest.mark.parametrize("port", ["0", "65536"])
def test_api_rejects_port_before_loading_configuration(
    monkeypatch: pytest.MonkeyPatch, port: str
) -> None:
    module = entry(monkeypatch, "api", ["--port", port])

    def forbidden(*args: object) -> None:
        pytest.fail("invalid port caused configuration access")

    monkeypatch.setattr(module, "checked_settings", forbidden)
    with pytest.raises(SystemExit) as raised:
        module.main()
    assert raised.value.code == 2


@pytest.mark.parametrize("name", ["api", "worker", "outbox", "mail"])
def test_runtime_failure_is_redacted_and_nonzero(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    process_settings: Settings,
    name: str,
) -> None:
    module = entry(monkeypatch, name, [])
    configure_entry(monkeypatch, module, process_settings)

    async def failed(*args: object, **kwargs: object) -> None:
        raise InfrastructureUnavailable("private dependency details must not escape")

    if name == "worker":

        @asynccontextmanager
        async def unavailable(*args: object, **kwargs: object) -> AsyncGenerator[Runtime]:
            raise InfrastructureUnavailable("private dependency details must not escape")
            yield

        monkeypatch.setattr(module, "bootstrap", unavailable)
    else:
        monkeypatch.setattr(
            module, {"api": "serve", "outbox": "run_outbox", "mail": "run_mail"}[name], failed
        )
    with pytest.raises(SystemExit) as raised:
        module.main()
    assert raised.value.code == 2
    assert "private dependency" not in capsys.readouterr().err


@pytest.mark.asyncio
@pytest.mark.parametrize("name", ["mail", "outbox"])
@pytest.mark.parametrize("failing", [False, True])
async def test_delivery_process_is_bounded_and_restores_signal_handler(
    monkeypatch: pytest.MonkeyPatch,
    process_settings: Settings,
    name: str,
    failing: bool,
) -> None:
    module = importlib.import_module(f"app.cli.{name}")
    settings = process_settings.model_copy(
        update={"infrastructure_enabled": True, "resource_profile": "core"}
    )
    runtime = Runtime(settings)
    calls: list[str] = []
    closed: list[bool] = []
    signal_handlers: list[object] = []
    previous = object()

    @asynccontextmanager
    async def resources(_settings: Settings, *, role: str) -> AsyncGenerator[Runtime]:
        assert role == name
        try:
            yield runtime
        finally:
            closed.append(True)

    def signal(_number: int, handler: object) -> object:
        signal_handlers.append(handler)
        return previous

    async def dispatch(_runtime: Runtime) -> bool:
        calls.append(name)
        if failing:
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)
        return True

    async def no_delay(_seconds: float) -> None:
        pass

    monkeypatch.setattr(module, "bootstrap", resources)
    monkeypatch.setattr(module.signal, "signal", signal)
    monkeypatch.setattr(module.asyncio, "sleep", no_delay)
    monkeypatch.setattr(module, "deliver_one" if name == "mail" else "deliver_outbox_one", dispatch)
    if name == "mail":

        def ready(_runtime: Runtime) -> bool:
            return True

        monkeypatch.setattr(module, "mail_ready", ready)
        coroutine = module.run_mail(settings, shutdown_file=None, once=True)
    else:
        coroutine = module.run_outbox(settings, shutdown_file=None, once=True)
    if failing:
        with pytest.raises(InfrastructureUnavailable):
            await coroutine
    else:
        await coroutine
    assert len(calls) == (5 if failing else 1)
    assert closed == [True]
    assert signal_handlers[-1] is previous


@pytest.mark.asyncio
@pytest.mark.parametrize("started", [True, False])
@pytest.mark.parametrize("with_marker", [True, False])
async def test_api_lifecycle_requires_listening_and_honours_owned_stop_marker(
    monkeypatch: pytest.MonkeyPatch,
    process_settings: Settings,
    tmp_path: Path,
    started: bool,
    with_marker: bool,
) -> None:
    from app.cli import api

    observed: list[uvicorn.Config] = []
    marker = tmp_path / "owned-stop.marker" if with_marker else None

    class ServerProbe:
        should_exit = False

        def __init__(self, config: uvicorn.Config) -> None:
            observed.append(config)
            self.started = started

        async def serve(self) -> None:
            await asyncio.sleep(0)
            if with_marker:
                assert self.should_exit

    async def stop_file(path: Path, stop: asyncio.Event) -> None:
        assert path == marker
        stop.set()

    monkeypatch.setattr(api.uvicorn, "Server", ServerProbe)
    monkeypatch.setattr(api, "watch_shutdown_file", stop_file)
    if started:
        await api.serve(process_settings, port=18081, shutdown_file=marker)
    else:
        with pytest.raises(InfrastructureUnavailable):
            await api.serve(process_settings, port=18081, shutdown_file=marker)
    assert len(observed) == 1
    assert observed[0].host == "127.0.0.1" and observed[0].port == 18081
    assert observed[0].access_log is False and observed[0].timeout_graceful_shutdown == 10
