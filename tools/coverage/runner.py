"""Repeatable owned Chrome collection; never an acceptance or coverage-gate receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import cast
from uuid import uuid4

from scripts.processes import ProcessOwner
from tools.coverage.adapter import SDK_SHA256, SDK_VERSION, patched_source

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


class CollectionError(RuntimeError):
    """Bounded failure; details remain in the owned output rather than stdout."""


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


SQLITE_WASM_SHA256 = "13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4"


def stage_sqlite_asset(root: Path) -> dict[str, object]:
    """Stage only the pinned tracked asset; never adopt a pre-existing copy."""
    source = root / "frontend/web/sqlite3.wasm"
    target = root / "frontend/test/support/assets/sqlite3.wasm"
    for path in (source, target):
        if not path.resolve().is_relative_to(root.resolve()):
            raise CollectionError("SQLite asset path escapes repository")
        if any(parent.is_symlink() for parent in (path, *path.parents)):
            raise CollectionError("SQLite asset symlink refused")
    git = shutil.which("git")
    if git is None:
        raise CollectionError("Git is required to verify the tracked SQLite asset")
    tracked = subprocess.run(  # noqa: S603 -- resolved Git; constant read-only arguments
        [git, "ls-files", "--error-unmatch", "frontend/web/sqlite3.wasm"],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    )
    if tracked.stdout.strip() != "frontend/web/sqlite3.wasm":
        raise CollectionError("SQLite source is not the tracked asset")
    content = source.read_bytes()
    if digest(content) != SQLITE_WASM_SHA256:
        raise CollectionError("SQLite source fingerprint mismatch")
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as destination:
        destination.write(content)
    return {
        "source": source.relative_to(root).as_posix(),
        "target": target.relative_to(root).as_posix(),
        "source_sha256": digest(content),
        "target_sha256": digest(content),
        "bytes": len(content),
        "state": "staged",
    }


def clean_sqlite_asset(root: Path, receipt: dict[str, object]) -> None:
    """Delete only this run's unchanged owned copy; preserve unexpected edits."""
    source = root / "frontend/web/sqlite3.wasm"
    target = root / "frontend/test/support/assets/sqlite3.wasm"
    if (
        receipt.get("state") != "staged"
        or receipt.get("target") != target.relative_to(root).as_posix()
        or any(parent.is_symlink() for path in (source, target) for parent in (path, *path.parents))
        or not source.resolve().is_relative_to(root.resolve())
        or not target.resolve().is_relative_to(root.resolve())
        or digest(source.read_bytes()) != receipt["source_sha256"]
        or digest(target.read_bytes()) != receipt["target_sha256"]
    ):
        receipt["state"] = "cleanup-refused-modification"
        raise CollectionError("SQLite asset changed; cleanup refused")
    target.unlink()
    receipt["state"] = "cleaned"
    receipt["source_sha256_after_cleanup"] = digest(source.read_bytes())


def freeze_sources(root: Path) -> dict[str, str]:
    paths = [
        *root.joinpath("frontend/lib").rglob("*.dart"),
        *root.joinpath("frontend/test").rglob("*.dart"),
        root / "frontend/pubspec.lock",
        root / "frontend/.dart_tool/package_config.json",
    ]
    if not paths or not any(root.joinpath("frontend/lib").rglob("*.dart")):
        raise CollectionError("Frontend source inventory is missing")
    if any(not path.resolve().is_relative_to(root.resolve()) for path in paths):
        raise CollectionError("Source inventory escapes repository")
    return {path.relative_to(root).as_posix(): digest(path.read_bytes()) for path in sorted(paths)}


def fresh_output(path: Path) -> Path:
    selected = path.resolve()
    selected.mkdir(parents=True, exist_ok=False)
    return selected


def owned_command(
    command: list[str],
    *,
    cwd: Path,
    output: Path,
    timeout: float,
    environment: dict[str, str] | None = None,
) -> dict[str, object]:
    """Always stop the strictly owned tree, including timeout/start/error paths."""
    if not 0 < timeout <= 7200:
        raise CollectionError("Timeout must be between zero and 7200 seconds")
    owner = ProcessOwner(uuid4().hex, "haruka-web-coverage")
    record: dict[str, object] = {"command": command, "timeout_seconds": timeout}
    deadline = time.monotonic() + timeout
    try:
        child = owner.start("collector", command, cwd=cwd, environment=environment)
        with (output / "process-output.txt").open("x", encoding="utf-8") as transcript:
            while child.target_exit is None:
                for line in child.collect():
                    transcript.write(line + "\n")
                if time.monotonic() >= deadline:
                    raise CollectionError("Owned collector timed out")
                if child.process.poll() is not None and child.target_exit is None:
                    raise CollectionError("Supervisor exited without a native target result")
                time.sleep(0.02)
            for line in child.collect():
                transcript.write(line + "\n")
        record["native_exit_code"] = child.target_exit
        if child.target_exit != 0:
            raise CollectionError("Native collector failed")
        return record
    finally:
        record["owned_cleanup"] = owner.stop(grace_seconds=1)
        write_json(output / "process-result.json", record)


def native_json_result(transcript: Path, destination: Path) -> dict[str, int]:
    events: list[dict[str, object]] = []
    for line in transcript.read_text(encoding="utf-8").splitlines():
        try:
            event: object = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict) and isinstance(cast(dict[str, object], event).get("type"), str):
            events.append(cast(dict[str, object], event))
    done = [event for event in events if event["type"] == "done"]
    tests = [
        event for event in events if event["type"] == "testDone" and event.get("hidden") is not True
    ]
    successful = [
        event
        for event in tests
        if event.get("result") == "success" and event.get("skipped") is not True
    ]
    failed = [
        event
        for event in tests
        if event.get("result") != "success" and event.get("skipped") is not True
    ]
    destination.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")
    if (
        len(done) != 1
        or done[0].get("success") is not True
        or not successful
        or failed
        or any(event.get("skipped") is True for event in tests)
    ):
        raise CollectionError("Native JSON contains no verified successful test completion")
    return {
        "tests": len(tests),
        "passed": len(successful),
        "failed": len(failed),
        "skipped": sum(event.get("skipped") is True for event in tests),
    }


def sdk_inputs(sdk: Path) -> tuple[Path, Path, Path]:
    sdk = sdk.resolve()
    dart = sdk / "bin/cache/dart-sdk/bin" / ("dart.exe" if os.name == "nt" else "dart")
    packages = sdk / "packages/flutter_tools/.dart_tool/package_config.json"
    entry = sdk / "packages/flutter_tools/bin/flutter_tools.dart"
    version_file = sdk / "bin/cache/flutter.version.json"
    version: object = json.loads(version_file.read_text(encoding="utf-8"))
    if (
        not isinstance(version, dict)
        or cast(dict[str, object], version).get("frameworkVersion") != SDK_VERSION
    ):
        raise CollectionError("Unsupported Flutter SDK version; no SDK mutation")
    if not all(path.is_file() for path in (dart, packages, entry)):
        raise CollectionError("Explicit SDK Dart/tool/package configuration is missing")
    return dart, packages, entry


def capture(
    *,
    sdk: Path,
    output: Path,
    tests: list[str],
    timeout: float,
    root: Path = ROOT,
    plain_name: str | None = None,
) -> dict[str, object]:
    root = root.resolve()
    output = fresh_output(output)
    dart, packages, entry = sdk_inputs(sdk)
    source = sdk.resolve() / "packages/flutter_tools/lib/src/test/flutter_web_platform.dart"
    original = source.read_bytes()
    record: dict[str, object] = {
        "schema_version": 1,
        "status": "capturing-not-coverage-gate",
        "sdk_version": SDK_VERSION,
        "sdk_original_sha256": digest(original),
        "original_sha256": digest(original),
        "helper_sha256": digest((HERE / "capture.dart").read_bytes()),
        "converter_sha256": digest((HERE / "convert.dart").read_bytes()),
        "runner_sha256": digest(Path(__file__).read_bytes()),
        "adapter_source_sha256": digest((HERE / "adapter.py").read_bytes()),
        "sdk_dart_sha256": digest(dart.read_bytes()),
        "sdk_package_config_sha256": digest(packages.read_bytes()),
        "tests": tests,
        "plain_name": plain_name,
        "subset": plain_name is not None,
    }
    if digest(original) != SDK_SHA256:
        write_json(output / "freeze.json", {**record, "status": "unsupported-sdk-no-mutation"})
        raise CollectionError("Unsupported SDK fingerprint; no SDK mutation")
    for test in tests:
        candidate = (root / "frontend" / test).resolve()
        if not candidate.is_relative_to(root / "frontend/test") or not candidate.is_file():
            raise CollectionError("Test must be an existing frontend/test source")
    if not tests:
        raise CollectionError("At least one explicit test is required")
    patched = patched_source(original, HERE / "capture.dart")
    record["adapter_sha256"] = digest(patched)
    record["source_before"] = freeze_sources(root)
    lock = source.with_name(source.name + ".haruka-coverage.lock")
    token = json.dumps({"run_id": uuid4().hex, "output": str(output)}).encode()
    descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.write(descriptor, token)
    os.close(descriptor)
    changed = False
    asset: dict[str, object] | None = None
    try:
        asset = stage_sqlite_asset(root)
        record["sqlite_asset"] = asset
        (output / "sdk-original.bin").write_bytes(original)
        if source.read_bytes() != original:
            raise CollectionError("SDK changed before patch; mutation refused")
        source.write_bytes(patched)
        changed = True
        write_json(output / "freeze.json", record)
        process = owned_command(
            [
                str(dart),
                "--packages=" + str(packages),
                str(entry),
                "test",
                "--platform",
                "chrome",
                "--reporter",
                "json",
                *(["--plain-name", plain_name] if plain_name is not None else []),
                *tests,
            ],
            cwd=root / "frontend",
            output=output,
            timeout=timeout,
            environment={**os.environ, "HARUKA_WEB_COVERAGE_RAW": str(output / "raw")},
        )
        record.update(process)
        record["native_counts"] = native_json_result(
            output / "process-output.txt", output / "native.jsonl"
        )
        raw_files = sorted((output / "raw").rglob("raw.json"))
        if not raw_files:
            raise CollectionError("Native tests produced no coverage capture")
        record["raw_files"] = {path.as_uri(): digest(path.read_bytes()) for path in raw_files}
        record["status"] = "captured-not-coverage-gate"
    except BaseException:
        record["status"] = "failed-not-coverage-gate"
        raise
    finally:
        asset_failure = False
        if asset is not None:
            try:
                clean_sqlite_asset(root, asset)
            except (OSError, CollectionError):
                asset_failure = True
                record["status"] = "failed-not-coverage-gate"
                asset["state"] = "cleanup-refused-modification"
        try:
            record["source_after"] = freeze_sources(root)
            record["source_unchanged"] = record["source_before"] == record["source_after"]
        except (OSError, CollectionError):
            record["source_unchanged"] = False
        process_record = output / "process-result.json"
        if process_record.is_file():
            record.update(json.loads(process_record.read_text(encoding="utf-8")))
        tool_hashes = {
            "helper_sha256": "capture.dart",
            "converter_sha256": "convert.dart",
            "runner_sha256": "runner.py",
            "adapter_source_sha256": "adapter.py",
        }
        try:
            record["tool_source_unchanged"] = all(
                record[key] == digest((HERE / name).read_bytes())
                for key, name in tool_hashes.items()
            )
        except OSError:
            record["tool_source_unchanged"] = False
        restore_failure = False
        if changed:
            if not source.is_file() or source.read_bytes() != patched:
                record["restore_status"] = "refused-concurrent-modification"
                restore_failure = True
            else:
                source.write_bytes(original)
                record["restored_sha256"] = digest(source.read_bytes())
                record["restore_status"] = "original-bytes-restored"
        if lock.is_file() and lock.read_bytes() == token:
            lock.unlink()
        write_json(output / "freeze.json", record)
        if (
            restore_failure
            or asset_failure
            or record["source_unchanged"] is not True
            or record["tool_source_unchanged"] is not True
        ):
            raise CollectionError("SDK/source freeze changed; evidence is invalid")
    return record


def convert(
    *, sdk: Path, raw: Path, freeze: Path, output: Path, timeout: float, root: Path = ROOT
) -> dict[str, object]:
    output = fresh_output(output)
    dart, packages, _ = sdk_inputs(sdk)
    process = owned_command(
        [
            str(dart),
            "--packages=" + str(packages),
            str(HERE / "convert.dart"),
            str(raw.resolve()),
            str(freeze.resolve()),
            str(root.resolve()),
            str(output / "converted"),
        ],
        cwd=root.resolve(),
        output=output,
        timeout=timeout,
    )
    facts = output / "converted/conversion-result.json"
    if not facts.is_file():
        raise CollectionError("Converter produced no provenance")
    return process


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="operation", required=True)
    for name in ("capture", "convert"):
        command = subcommands.add_parser(name)
        command.add_argument("--sdk", required=True, type=Path)
        command.add_argument("--output", required=True, type=Path)
        command.add_argument("--timeout", type=float, default=900)
        command.add_argument("--root", type=Path, default=ROOT)
        if name == "capture":
            command.add_argument("--test", action="append", required=True)
            command.add_argument("--plain-name")
        else:
            command.add_argument("--raw", type=Path, required=True)
            command.add_argument("--freeze", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.operation == "capture":
            result = capture(
                sdk=args.sdk,
                output=args.output,
                tests=args.test,
                plain_name=args.plain_name,
                timeout=args.timeout,
                root=args.root,
            )
            sys.stdout.write(
                json.dumps({"status": result["status"], "native_counts": result["native_counts"]})
                + "\n"
            )
        else:
            convert(
                sdk=args.sdk,
                raw=args.raw,
                freeze=args.freeze,
                output=args.output,
                timeout=args.timeout,
                root=args.root,
            )
            sys.stdout.write(json.dumps({"status": "converted-not-coverage-gate"}) + "\n")
    except (CollectionError, OSError, ValueError) as error:
        parser.exit(1, type(error).__name__ + ": collector failed; inspect owned output\n")


if __name__ == "__main__":
    main()
