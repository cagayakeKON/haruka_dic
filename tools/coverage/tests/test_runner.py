"""Offline collection guards; no Flutter SDK or browser is executed."""

import json
import signal
import sys
from pathlib import Path

import pytest
from scripts.processes import ProcessOwner
from tools.coverage import runner
from tools.coverage.runner import CollectionError, fresh_output, native_json_result, owned_command


@pytest.mark.parametrize(
    "events",
    [
        [],
        [
            {"type": "testDone", "result": "success"},
            {"type": "testDone", "result": "success", "skipped": True},
            {"type": "done", "success": True},
        ],
        [{"type": "done", "success": True}],
        [{"type": "testDone", "result": "failure"}, {"type": "done", "success": True}],
        [
            {"type": "testDone", "result": "success", "skipped": True},
            {"type": "done", "success": True},
        ],
        [{"type": "testDone", "result": "success"}, {"type": "done", "success": False}],
    ],
)
def test_native_completion_required(tmp_path: Path, events: list[dict[str, object]]) -> None:
    source = tmp_path / "output.txt"
    source.write_text("\n".join(json.dumps(e) for e in events))
    with pytest.raises(CollectionError):
        native_json_result(source, tmp_path / "native.jsonl")
    if not (tmp_path / "native.jsonl").exists():
        pytest.fail("Native failure evidence missing")


def test_native_counts_exclude_hidden(tmp_path: Path) -> None:
    source = tmp_path / "output.txt"
    source.write_text(
        "compiler text\n"
        + "\n".join(
            json.dumps(e)
            for e in [
                {"type": "testDone", "result": "success"},
                {"type": "testDone", "result": "success", "hidden": True},
                {"type": "done", "success": True},
            ]
        )
    )
    if native_json_result(source, tmp_path / "native.jsonl")["passed"] != 1:
        pytest.fail("Hidden tests counted")


def test_prior_evidence_never_overwritten(tmp_path: Path) -> None:
    evidence = tmp_path / "existing"
    evidence.mkdir()
    (evidence / "proof").write_bytes(b"original")
    with pytest.raises(FileExistsError):
        fresh_output(evidence)
    if (evidence / "proof").read_bytes() != b"original":
        pytest.fail("Evidence overwritten")


@pytest.mark.parametrize(
    "body,timeout", [("import time; time.sleep(60)", 0.3), ("raise SystemExit(7)", 10)]
)
def test_owned_failure_preserved_and_tree_cleaned(
    tmp_path: Path, body: str, timeout: float, monkeypatch: pytest.MonkeyPatch
) -> None:
    owner = ProcessOwner("offline-test", "haruka-web-coverage-test")

    def owned_factory(*_args: object) -> ProcessOwner:
        return owner

    monkeypatch.setattr(runner, "ProcessOwner", owned_factory)
    with pytest.raises(CollectionError):
        owned_command([sys.executable, "-c", body], cwd=tmp_path, output=tmp_path, timeout=timeout)
    facts = json.loads((tmp_path / "process-result.json").read_text())
    if not facts["owned_cleanup"]:
        pytest.fail("Missing owned cleanup")
    if not all(child.process.poll() is not None for child in owner.children):
        pytest.fail("Owned supervisor survived")


@pytest.mark.parametrize("failure", ["native", "missing-source", "concurrent-sdk", "interrupt"])
def test_failed_capture_restores_only_unchanged_owned_sdk(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, failure: str
) -> None:
    root = tmp_path / "repo"
    for name in (
        "frontend/lib/app.dart",
        "frontend/test/test.dart",
        "frontend/pubspec.lock",
        "frontend/.dart_tool/package_config.json",
    ):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("original")
    sdk = tmp_path / "sdk"
    source = sdk / "packages/flutter_tools/lib/src/test/flutter_web_platform.dart"
    source.parent.mkdir(parents=True)
    original = b"original\r\n"
    source.write_bytes(original)
    executable = tmp_path / "unused"
    executable.write_bytes(b"test")

    def inputs(_sdk: Path) -> tuple[Path, Path, Path]:
        return executable, executable, executable

    def patch(_original: bytes, _helper: Path) -> bytes:
        return b"patched"

    def command(*_args: object, **_kwargs: object) -> dict[str, object]:
        if failure == "missing-source":
            (root / "frontend/pubspec.lock").unlink()
        if failure == "concurrent-sdk":
            source.write_bytes(b"external-edit")
        if failure == "interrupt":
            signal.raise_signal(signal.SIGINT)
        raise CollectionError("native failed")

    monkeypatch.setattr(runner, "sdk_inputs", inputs)
    monkeypatch.setattr(runner, "SDK_SHA256", runner.digest(original))
    monkeypatch.setattr(runner, "patched_source", patch)
    monkeypatch.setattr(runner, "owned_command", command)
    import subprocess

    wasm = root / "frontend/web/sqlite3.wasm"
    wasm.parent.mkdir(parents=True)
    wasm.write_bytes(b"test wasm")
    monkeypatch.setattr(runner, "SQLITE_WASM_SHA256", runner.digest(wasm.read_bytes()))

    def tracked_git(*_args: object, **_kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess([], 0, "frontend/web/sqlite3.wasm\n")

    monkeypatch.setattr(runner.subprocess, "run", tracked_git)
    output = tmp_path / "capture"
    with pytest.raises(KeyboardInterrupt if failure == "interrupt" else CollectionError):
        runner.capture(sdk=sdk, output=output, tests=["test/test.dart"], timeout=1, root=root)
    expected = b"external-edit" if failure == "concurrent-sdk" else original
    if source.read_bytes() != expected:
        pytest.fail("SDK restoration overwrote unrelated modification or lost original bytes")
    if source.with_name(source.name + ".haruka-coverage.lock").exists():
        pytest.fail("Owned lock leaked")
    facts = json.loads((output / "freeze.json").read_text())
    if facts["sqlite_asset"]["state"] != "cleaned":
        pytest.fail("SQLite owned asset invariant failed")
    if (root / "frontend/test/support/assets/sqlite3.wasm").exists():
        pytest.fail("SQLite owned asset invariant failed")
    if facts["status"] != "failed-not-coverage-gate":
        pytest.fail("Failed native result promoted")


def test_timeout_keeps_unrelated_owned_tree(tmp_path: Path) -> None:
    outsider = ProcessOwner("outside-run", "haruka-unrelated-test")
    child = outsider.start(
        "outside", [sys.executable, "-c", "import time; time.sleep(60)"], cwd=tmp_path
    )
    try:
        destination = tmp_path / "collector"
        destination.mkdir()
        with pytest.raises(CollectionError):
            owned_command(
                [sys.executable, "-c", "import time; time.sleep(60)"],
                cwd=tmp_path,
                output=destination,
                timeout=0.3,
            )
        if child.process.poll() is not None:
            pytest.fail("Collector cleanup killed unrelated supervisor")
    finally:
        outsider.stop(grace_seconds=0.2)


def test_converter_uses_locked_sdk_tools_packages(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sdk = tmp_path / "sdk"
    dart = sdk / "dart.exe"
    packages = sdk / "packages/flutter_tools/.dart_tool/package_config.json"
    commands: list[list[str]] = []

    def inputs(_sdk: Path) -> tuple[Path, Path, Path]:
        return dart, packages, sdk / "flutter_tools.dart"

    def command(args: list[str], *, cwd: Path, output: Path, timeout: float) -> dict[str, object]:
        commands.append(args)
        (output / "converted").mkdir()
        (output / "converted/conversion-result.json").write_text("{}")
        return {"native_exit_code": 0}

    monkeypatch.setattr(runner, "sdk_inputs", inputs)
    monkeypatch.setattr(runner, "owned_command", command)
    runner.convert(
        sdk=sdk,
        raw=tmp_path / "raw.json",
        freeze=tmp_path / "freeze.json",
        output=tmp_path / "output",
        timeout=1,
        root=tmp_path,
    )
    if commands[0][1] != "--packages=" + str(packages):
        pytest.fail("Converter dependencies must come from SDK Flutter tools lock")


@pytest.fixture
def sqlite_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    import subprocess

    source = tmp_path / "frontend/web/sqlite3.wasm"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"pinned wasm")
    monkeypatch.setattr(runner, "SQLITE_WASM_SHA256", runner.digest(source.read_bytes()))

    def tracked_git(*_args: object, **_kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess([], 0, "frontend/web/sqlite3.wasm\n")

    monkeypatch.setattr(runner.subprocess, "run", tracked_git)
    return tmp_path


def test_sqlite_owned_asset_cleaned_without_touching_source(sqlite_root: Path) -> None:
    source = sqlite_root / "frontend/web/sqlite3.wasm"
    original = source.read_bytes()
    receipt = runner.stage_sqlite_asset(sqlite_root)
    target = sqlite_root / str(receipt["target"])
    if target.read_bytes() != original:
        pytest.fail("SQLite owned asset invariant failed")
    runner.clean_sqlite_asset(sqlite_root, receipt)
    if target.exists():
        pytest.fail("SQLite owned asset invariant failed")
    if source.read_bytes() != original:
        pytest.fail("SQLite owned asset invariant failed")
    if receipt["state"] != "cleaned":
        pytest.fail("SQLite owned asset invariant failed")


def test_sqlite_existing_asset_never_adopted(sqlite_root: Path) -> None:
    target = sqlite_root / "frontend/test/support/assets/sqlite3.wasm"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"foreign")
    with pytest.raises(FileExistsError):
        runner.stage_sqlite_asset(sqlite_root)
    if target.read_bytes() != b"foreign":
        pytest.fail("SQLite owned asset invariant failed")


@pytest.mark.parametrize("changed", ["source", "target"])
def test_sqlite_cleanup_preserves_concurrent_modification(sqlite_root: Path, changed: str) -> None:
    receipt = runner.stage_sqlite_asset(sqlite_root)
    selected = sqlite_root / str(receipt[changed])
    selected.write_bytes(b"external edit")
    with pytest.raises(CollectionError):
        runner.clean_sqlite_asset(sqlite_root, receipt)
    if selected.read_bytes() != b"external edit":
        pytest.fail("SQLite owned asset invariant failed")
    if not ((sqlite_root / str(receipt["target"])).exists()):
        pytest.fail("SQLite owned asset invariant failed")


def test_sqlite_unpinned_source_refused_before_stage(sqlite_root: Path) -> None:
    (sqlite_root / "frontend/web/sqlite3.wasm").write_bytes(b"unexpected")
    with pytest.raises(CollectionError, match="fingerprint"):
        runner.stage_sqlite_asset(sqlite_root)
    if (sqlite_root / "frontend/test/support/assets/sqlite3.wasm").exists():
        pytest.fail("SQLite owned asset invariant failed")


def test_sqlite_symlink_refused(sqlite_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    original = Path.is_symlink

    def is_symlink(path: Path) -> bool:
        return path.name == "assets" or original(path)

    monkeypatch.setattr(Path, "is_symlink", is_symlink)
    with pytest.raises(CollectionError, match="symlink"):
        runner.stage_sqlite_asset(sqlite_root)
    if (sqlite_root / "frontend/test/support/assets/sqlite3.wasm").exists():
        pytest.fail("SQLite owned asset invariant failed")
