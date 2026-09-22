"""Standard-library development entry point; never claim an unimplemented milestone passed."""

from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import typing
import uuid
import xml.etree.ElementTree as ET
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field
from pathlib import Path

if __package__:
    from .quality.docs import inspect, markdown_files
else:
    from quality.docs import inspect, markdown_files

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP_SCOPES = ("docs", "backend", "web", "android", "windows", "all")
SCOPES = (*BOOTSTRAP_SCOPES[:-1], "infra", "all")
INFRA_ACTIONS = ("init", "up", "status", "down", "smoke")


class DevError(Exception):
    """A safe, actionable development failure with no secret-bearing tool output."""


def redact(value: str) -> str:
    value = value.replace(str(ROOT), "<repository>").replace(str(Path.home()), "<home>")
    value = re.sub(r"(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+:[^\s/@]+@", r"\1[redacted]@", value)
    value = re.sub(
        r"(?i)((?:password|token|secret|api[_-]?key)\s*[=:]\s*)[^\s,;]+",
        r"\1[redacted]",
        value,
    )
    value = re.sub(r"(?i)(authorization\s*[:=]\s*(?:bearer|basic)\s+)\S+", r"\1[redacted]", value)
    return re.sub(r"\bsk-[A-Za-z0-9_-]{12,}\b", "[redacted]", value)


def emit(message: str) -> None:
    sys.stdout.write(redact(message) + "\n")


def configure_console() -> None:
    """Keep piped Windows stdout/stderr Unicode-safe regardless of the host code page."""
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, io.TextIOWrapper):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace", newline="\n")


@dataclass
class Report:
    command: str
    scope: str
    run_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    started_at: str = field(default_factory=lambda: datetime.datetime.now(datetime.UTC).isoformat())
    records: list[dict[str, object]] = field(default_factory=lambda: list[dict[str, object]]())
    result: str = "failed"

    def record(self, name: str, status: str, **details: object) -> None:
        self.records.append({"name": name, "status": status, **details})

    def save(self) -> Path:
        directory = ROOT / "artifacts" / "dev"
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"{self.command}-{self.run_id}.json"
        path.write_text(
            json.dumps(redact_data(asdict(self)), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return path


def is_json_object(value: object) -> typing.TypeGuard[dict[str, object]]:
    # Called on json.loads output: JSON object keys are strings by parser contract.
    return isinstance(value, dict)


def json_object(value: object) -> dict[str, object]:
    if not is_json_object(value):
        raise DevError("Expected a JSON object")
    return value


def string_list(value: object) -> list[str]:
    if not is_json_list(value):
        raise DevError("Expected a JSON string list")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise DevError("Expected a JSON string list")
        result.append(item)
    return result


def is_json_list(value: object) -> typing.TypeGuard[list[object]]:
    return isinstance(value, list)


def redact_data(value: object) -> object:
    """Redact strings before JSON escaping, including nested Windows command paths."""
    if isinstance(value, str):
        return redact(value)
    if is_json_object(value):
        return {key: redact_data(item) for key, item in value.items()}
    if is_json_list(value):
        return [redact_data(item) for item in value]
    return value


def load_toolchain() -> dict[str, object]:
    value = json_object(json.loads((ROOT / "tools" / "toolchain.json").read_text(encoding="utf-8")))
    if value.get("schema_version") != 1:
        raise DevError("tools/toolchain.json has an unsupported schema")
    return value


def tool(name: str) -> list[str]:
    if name == "python":
        return [sys.executable]
    if name == "uv":
        local = ROOT / ".tools" / "uv" / ("uv.exe" if os.name == "nt" else "uv")
        if local.is_file():
            return [str(local)]
    if name in {"flutter", "dart"}:
        candidate = shutil.which("flutter")
        if not candidate:
            raise DevError(
                "Missing Flutter SDK; install the exact revision in tools/toolchain.json"
            )
        sdk = Path(candidate).resolve().parent.parent
        dart = (
            sdk / "bin" / "cache" / "dart-sdk" / "bin" / ("dart.exe" if os.name == "nt" else "dart")
        )
        if not dart.is_file():
            raise DevError("Flutter SDK cache is incomplete; initialize the pinned SDK explicitly")
        if name == "dart":
            return [str(dart)]
        snapshot = sdk / "bin" / "cache" / "flutter_tools.snapshot"
        if not snapshot.is_file():
            raise DevError(
                "Flutter tools snapshot is missing; initialize the pinned SDK explicitly"
            )
        return [str(dart), str(snapshot)]
    if name == "npm" and os.name == "nt":
        candidate = shutil.which("npm.cmd")
        if candidate:
            cli = Path(candidate).parent / "node_modules" / "npm" / "bin" / "npm-cli.js"
            if cli.is_file():
                return [*tool("node"), str(cli)]
        raise DevError("Cannot locate npm's installed CLI; install the pinned Node/npm pair")
    executable = shutil.which(name)
    if not executable:
        raise DevError(f"Missing {name}; install the version in tools/toolchain.json")
    return [executable]


def run(
    report: Report,
    name: str,
    arguments: Sequence[str],
    *,
    cwd: Path = ROOT,
    timeout: int = 180,
    show_output: bool = True,
    environment: dict[str, str] | None = None,
) -> str:
    command = [*tool(name), *arguments]
    started = time.monotonic()
    try:
        completed = subprocess.run(  # noqa: S603 - fixed tools, argument arrays, no shell or arbitrary command input.
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
            env={**os.environ, "PYTHONUTF8": "1", **(environment or {})},
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        report.record(name, "failed", arguments=list(arguments), reason=type(error).__name__)
        raise DevError(f"{name} could not finish ({type(error).__name__})") from error
    output = completed.stdout + completed.stderr
    report.record(
        name,
        "passed" if completed.returncode == 0 else "failed",
        arguments=list(arguments),
        cwd=str(cwd),
        exit_code=completed.returncode,
        duration_seconds=round(time.monotonic() - started, 3),
    )
    if show_output and output.strip():
        emit(output.rstrip())
    if completed.returncode:
        raise DevError(f"{name} failed with exit code {completed.returncode}")
    return output


def require_files(paths: Sequence[str]) -> None:
    missing = [path for path in paths if not (ROOT / path).is_file()]
    if missing:
        raise DevError("Required files are missing: " + ", ".join(missing))


def validate_project_versions(manifest: dict[str, object], scopes: set[str]) -> None:
    """Check duplicated declarations; dependency resolution remains owned by lock-aware tools."""
    if "docs" in scopes:
        package = json_object(
            json.loads((ROOT / "tools/node/package.json").read_text(encoding="utf-8"))
        )
        engines = json_object(package.get("engines"))
        dependencies = json_object(package.get("devDependencies"))
        lock = json_object(
            json.loads((ROOT / "tools/node/package-lock.json").read_text(encoding="utf-8"))
        )
        packages = json_object(lock.get("packages"))
        locked = json_object(packages.get("node_modules/markdownlint-cli2"))
        if any(engines.get(name) != manifest[name] for name in ("node", "npm")) or any(
            version != manifest["markdownlint_cli2"]
            for version in (dependencies.get("markdownlint-cli2"), locked.get("version"))
        ):
            raise DevError(
                "Node/npm/Markdownlint declarations or lock differ from tools/toolchain.json"
            )
    if "backend" in scopes:
        import tomllib

        config = json_object(
            tomllib.loads((ROOT / "backend/pyproject.toml").read_text(encoding="utf-8"))
        )
        build = json_object(config.get("build-system"))
        uv = json_object(json_object(config.get("tool")).get("uv"))
        if (
            string_list(build.get("requires")) != [f"hatchling=={manifest['hatchling']}"]
            or uv.get("required-version") != f"=={manifest['uv']}"
        ):
            raise DevError("Backend builder or uv requirement differs from tools/toolchain.json")
        constraints = uv.get("build-constraint-dependencies")
        if not is_json_list(constraints) or not constraints:
            raise DevError("PEP 517 build constraints are missing")
        for constraint in constraints:
            item = json_object(constraint)
            requirement = item.get("requirement")
            hashes = string_list(item.get("hashes"))
            if (
                not isinstance(requirement, str)
                or not re.fullmatch(r"[A-Za-z0-9_.-]+==[A-Za-z0-9_.+!-]+", requirement)
                or not hashes
                or not all(re.fullmatch(r"sha256:[a-f0-9]{64}", digest) for digest in hashes)
            ):
                raise DevError("Build constraint lacks an exact version or a SHA-256 hash")


def doctor(report: Report, scope: str) -> None:
    manifest = load_toolchain()
    scopes: set[str] = set(SCOPES[:-1]) if scope == "all" else {scope}
    checks: list[tuple[str, list[str], str]] = []
    if "docs" in scopes:
        checks.extend((name, ["--version"], str(manifest[name])) for name in ("node", "npm"))
    if scopes - {"docs"}:
        checks.append(("python", ["--version"], str(manifest["python"])))
    if "backend" in scopes:
        checks.append(("uv", ["--version"], str(manifest["uv"])))
    if "infra" in scopes:
        checks.extend(
            (
                ("docker", ["version", "--format", "{{.Client.Version}}"], str(manifest["docker"])),
                ("docker", ["version", "--format", "{{.Server.Version}}"], str(manifest["docker"])),
                ("docker", ["compose", "version", "--short"], str(manifest["docker_compose"])),
            )
        )
    problems: list[str] = []
    for name, arguments, expected in checks:
        try:
            output = run(report, name, arguments, show_output=False)
            actual = re.search(r"\d+\.\d+\.\d+", output)
            if not actual or actual.group() != expected:
                raise DevError(f"{name}: incompatible; require {expected}")
            report.record(name, "ready", version=actual.group())
            emit(f"ready: {name} {actual.group()}")
        except DevError as error:
            problems.append(str(error))
            report.record(name, "incompatible", remedy=str(error))
    if scopes & {"web", "windows", "android"}:
        try:
            expected = json_object(manifest["flutter"])
            actual = json_object(
                json.loads(run(report, "flutter", ["--version", "--machine"], show_output=False))
            )
            if any(
                actual.get(key) != expected.get(field)
                for key, field in (
                    ("frameworkVersion", "version"),
                    ("frameworkRevision", "revision"),
                    ("dartSdkVersion", "dart"),
                )
            ):
                raise DevError("Flutter/Dart version or revision differs from tools/toolchain.json")
            report.record(
                "flutter",
                "ready",
                version=actual["frameworkVersion"],
                revision=actual["frameworkRevision"],
            )
            emit(f"ready: Flutter {actual['frameworkVersion']} / Dart {actual['dartSdkVersion']}")
            require_files(
                [
                    "frontend/pubspec.yaml",
                    "frontend/pubspec.lock",
                    "frontend/config/build_targets.json",
                ]
            )
        except (DevError, json.JSONDecodeError) as error:
            problems.append(str(error))
    if "android" in scopes:
        try:
            # Flutter can select Android Studio's JBR instead of PATH's java executable.
            output = run(report, "flutter", ["doctor", "-v"], show_output=False)
            java_match = re.search(r"Java version .+\(build ([^)]+)\)", output)
            if not java_match or java_match.group(1) != manifest["java_build"]:
                raise DevError("Flutter-selected Java build differs from tools/toolchain.json")
            report.record("flutter_java", "ready", version=java_match.group(1))
            android = json_object(manifest["android"])
            sdk = Path(
                os.environ.get(
                    "ANDROID_HOME",
                    os.environ.get(
                        "ANDROID_SDK_ROOT", str(Path.home() / "AppData/Local/Android/Sdk")
                    ),
                )
            )
            required = [
                sdk / "platforms" / f"android-{android['compile_sdk']}",
                sdk / "build-tools" / str(android["build_tools"]),
            ]
            if not all(path.is_dir() for path in required):
                raise DevError(
                    "Pinned Android platform/build-tools missing; install the declared versions"
                )
            report.record("android_build_tools", "ready", runtime_acceptance="not_executed")
        except DevError as error:
            problems.append(str(error))
    if "windows" in scopes:
        if os.name != "nt":
            problems.append(
                "Windows target requires a Windows host with pinned Visual Studio C++ tools"
            )
        else:
            vswhere = (
                Path(os.environ.get("PROGRAMFILES(X86)", "C:/Program Files (x86)"))
                / "Microsoft Visual Studio/Installer/vswhere.exe"
            )
            if not vswhere.is_file():
                problems.append("Missing Visual Studio Installer/vswhere.exe")
            else:
                result = subprocess.run(  # noqa: S603 - fixed installed executable and literal arguments.
                    [
                        str(vswhere),
                        "-latest",
                        "-requires",
                        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                        "-property",
                        "installationVersion",
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                expected = json_object(manifest["windows"])
                if result.stdout.strip() != expected["visual_studio"]:
                    problems.append("Missing or incompatible Visual Studio C++ workload")
    files: list[str] = []
    if "docs" in scopes:
        files.extend(
            ["tools/node/package.json", "tools/node/package-lock.json", ".markdownlint-cli2.jsonc"]
        )
    if "backend" in scopes:
        files.extend(
            [
                "backend/pyproject.toml",
                "backend/uv.lock",
                "backend/.python-version",
                "backend/.env.example",
            ]
        )
        version = ROOT / "backend/.python-version"
        if version.is_file() and version.read_text(encoding="utf-8").strip() != manifest["python"]:
            problems.append("backend/.python-version differs from tools/toolchain.json")
    if "infra" in scopes:
        files.extend(["dev/infra.py", "dev/compose.yaml"])
    try:
        require_files(files)
        validate_project_versions(manifest, scopes)
    except DevError as error:
        problems.append(str(error))
    if problems:
        for problem in problems:
            report.record("prerequisite", "missing_or_incompatible", remedy=problem)
        raise DevError("; ".join(problems))
    report.record(
        "scope",
        "ready",
        note="Tool prerequisites and selected Docker daemon only; service readiness, devices, and runtime acceptance are not implied",
    )


def bootstrap(report: Report, scope: str) -> None:
    doctor(report, scope)
    scopes: set[str] = set(BOOTSTRAP_SCOPES[:-1]) if scope == "all" else {scope}
    if "docs" in scopes:
        run(
            report,
            "npm",
            ["ci", "--ignore-scripts", "--no-audit", "--no-fund"],
            cwd=ROOT / "tools/node",
        )
    if "backend" in scopes:
        run(report, "uv", ["sync", "--locked", "--group", "dev"], cwd=ROOT / "backend", timeout=600)
        template = ROOT / "backend/.env.example"
        target = ROOT / "backend/.env"
        if not target.exists():
            with target.open("x", encoding="utf-8") as destination:
                destination.write(template.read_text(encoding="utf-8"))
            report.record(
                "local_config",
                "created",
                note="Copied non-secret template; no existing configuration overwritten",
            )
        else:
            report.record("local_config", "preserved")
    if scopes & {"web", "android", "windows"}:
        run(
            report,
            "flutter",
            ["pub", "get", "--enforce-lockfile"],
            cwd=ROOT / "frontend",
            timeout=600,
        )


def infra(report: Report, action: str) -> None:
    """Delegate all infrastructure configuration and ownership to dev/infra.py."""
    if action not in INFRA_ACTIONS:
        raise DevError("Unknown infrastructure operation")
    require_files(["dev/infra.py", "dev/compose.yaml"])
    if action == "init":
        manifest = load_toolchain()
        if sys.version.split()[0] != manifest["python"]:
            raise DevError(f"python: incompatible; require {manifest['python']}")
    else:
        doctor(report, "infra")
    run(report, "python", [str(ROOT / "dev/infra.py"), action], timeout=900)
    report.record("infrastructure", "passed", action=action, project="haruka-local")


def junit_results(path: Path) -> int:
    if not path.is_file():
        raise DevError("Required JUnit report is missing")
    try:
        content = path.read_bytes()
        if b"<!DOCTYPE" in content.upper() or b"<!ENTITY" in content.upper():
            raise DevError("JUnit DTD/entity declarations are forbidden")
        tests = list(ET.fromstring(content).iter("testcase"))  # noqa: S314 - own local runner output; DTD/entities rejected above.
    except ET.ParseError as error:
        raise DevError("Malformed JUnit report") from error
    if not tests:
        raise DevError("JUnit report contains zero test cases")
    if any(
        test.find(kind) is not None for test in tests for kind in ("failure", "error", "skipped")
    ):
        raise DevError("Required tests contain failed, errored, skipped, or xfailed results")
    return len(tests)


def unittest_results(output: str) -> int:
    match = re.search(r"Ran (\d+) tests? in ", output)
    if not match or int(match.group(1)) == 0 or "OK" not in output:
        raise DevError("Tooling test report is empty or incomplete")
    if re.search(r"(?:skipped|expected failures|unexpected successes)=\d+", output):
        raise DevError("Tooling required tests were skipped or did not pass normally")
    return int(match.group(1))


def flutter_results(output: str) -> int:
    events: list[dict[str, object]] = []
    for line in output.splitlines():
        if line.startswith("{"):
            try:
                events.append(json_object(json.loads(line)))
            except json.JSONDecodeError as error:
                raise DevError("Malformed Flutter test report") from error
    completed = [
        event
        for event in events
        if event.get("type") == "testDone" and not event.get("hidden", False)
    ]
    if not completed or not any(
        event.get("type") == "done" and event.get("success") is True for event in events
    ):
        raise DevError("Flutter test report is empty or incomplete")
    if any(event.get("result") != "success" or event.get("skipped") is True for event in completed):
        raise DevError("Flutter required tests contain failures or skipped results")
    return len(completed)


def check_docs(report: Report) -> None:
    doctor(report, "docs")
    require_files(["tools/node/node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs"])
    output = run(
        report,
        "node",
        [
            str(ROOT / "tools/node/node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs"),
            "--config",
            str(ROOT / ".markdownlint-cli2.jsonc"),
        ],
    )
    linted = re.search(r"Linting: (\d+) files?", output)
    if not linted or int(linted.group(1)) != len(markdown_files(ROOT)):
        raise DevError("Markdownlint did not check the complete declared documentation scope")
    errors, unverified = inspect(ROOT)
    report.record(
        "markdown_links_fences",
        "failed" if errors else "passed",
        checked=len(markdown_files(ROOT)),
        findings=[asdict(item) for item in errors],
        unverified=unverified,
    )
    for item in errors:
        emit(f"{item.path}:{item.line}: {item.code}")
    for item in unverified:
        emit(f"unverified: {item}")
    if errors:
        raise DevError(f"Documentation check failed with {len(errors)} finding(s)")
    emit(
        "Documentation links, anchors, fences, and conflict markers passed; external web links are not checked."
    )


def check_backend(report: Report) -> None:
    backend = ROOT / "backend"
    doctor(report, "backend")
    run(report, "uv", ["run", "--locked", "ruff", "format", "--check", "."], cwd=backend)
    run(report, "uv", ["run", "--locked", "ruff", "check", "."], cwd=backend)
    run(report, "uv", ["run", "--locked", "pyright"], cwd=backend, timeout=300)
    report_path = ROOT / "artifacts/dev" / f"pytest-{report.run_id}.xml"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        report,
        "uv",
        ["run", "--locked", "pytest", "tests/unit", "tests/contract", f"--junitxml={report_path}"],
        cwd=backend,
        timeout=300,
    )
    report.record(
        "backend_test_results",
        "passed",
        passed=junit_results(report_path),
        scope="unit_and_contract_only",
    )


def check_frontend(report: Report) -> None:
    doctor(report, "web")
    doctor(report, "backend")
    frontend = ROOT / "frontend"
    require_files(["frontend/tool/generate.py", "frontend/tool/pyrightconfig.json"])
    run(
        report,
        "uv",
        [
            "run",
            "--project",
            "backend",
            "--locked",
            "ruff",
            "format",
            "--check",
            "--config",
            "backend/pyproject.toml",
            "frontend/tool",
        ],
    )
    run(
        report,
        "uv",
        [
            "run",
            "--project",
            "backend",
            "--locked",
            "ruff",
            "check",
            "--config",
            "backend/pyproject.toml",
            "frontend/tool",
        ],
    )
    run(
        report,
        "uv",
        [
            "run",
            "--project",
            "backend",
            "--locked",
            "pyright",
            "--project",
            "frontend/tool/pyrightconfig.json",
        ],
    )
    output = run(
        report,
        "python",
        ["-m", "unittest", "discover", "-s", "frontend/tool", "-p", "test_generate.py", "-v"],
    )
    report.record("frontend_generator_test_results", "passed", passed=unittest_results(output))
    run(report, "python", [str(frontend / "tool/generate.py"), "--check"])
    targets = [
        str(path.relative_to(frontend))
        for path in sorted(frontend.iterdir())
        if path.is_dir()
        and path.name in {"lib", "test", "integration_test", "test_driver", "patrol_test"}
    ]
    if not {"lib", "test"}.issubset(targets):
        raise DevError("Frontend source and actual tests are required")
    run(
        report, "dart", ["format", "--output=none", "--set-exit-if-changed", *targets], cwd=frontend
    )
    run(
        report,
        "flutter",
        ["analyze", "--fatal-infos", "--fatal-warnings"],
        cwd=frontend,
        timeout=300,
    )
    output = run(
        report,
        "flutter",
        ["test", "test", "--machine", "--no-pub"],
        cwd=frontend,
        timeout=300,
        show_output=False,
    )
    count = flutter_results(output)
    report.record("frontend_test_results", "passed", passed=count, scope="unit_widget_only")
    emit(f"Flutter unit/widget results: {count} passed")


def check_infrastructure(report: Report) -> None:
    """Verify the declared local integration target without starting or migrating services."""
    require_files(
        [
            "dev/infra.py",
            "dev/test_infra.py",
            "dev/pyrightconfig.json",
            "dev/.local/test.env",
            "backend/tests/integration/test_infrastructure.py",
        ]
    )
    doctor(report, "backend")
    for arguments in (
        ["ruff", "format", "--check", "--config", "backend/pyproject.toml", "dev"],
        ["ruff", "check", "--config", "backend/pyproject.toml", "dev"],
        ["pyright", "--project", "dev/pyrightconfig.json"],
    ):
        run(report, "uv", ["run", "--project", "backend", "--locked", *arguments])
    output = run(report, "python", ["-m", "unittest", "dev.test_infra", "-v"])
    report.record("infrastructure_tooling_test_results", "passed", passed=unittest_results(output))
    infra(report, "smoke")
    report_path = ROOT / "artifacts/dev" / f"infrastructure-{report.run_id}.xml"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        report,
        "uv",
        [
            "run",
            "--locked",
            "pytest",
            "tests/integration/test_infrastructure.py",
            f"--junitxml={report_path}",
        ],
        cwd=ROOT / "backend",
        timeout=300,
        environment={"HARUKA_INTEGRATION_CONFIG": str(ROOT / "dev/.local/test.env")},
    )
    report.record(
        "infrastructure_test_results",
        "passed",
        passed=junit_results(report_path),
        scope="isolated_development_infrastructure_only",
    )


def check(report: Report, stage: str) -> None:
    if stage in {"B0", "B1", "B2"}:
        raise DevError(
            f"{stage} is not delivered. B0 still requires real PG migration/seed, complete quality gates, and three-platform runtime evidence. Use an explicit implemented local scope."
        )
    if stage in {"tooling", "infrastructure", "B0-foundation"}:
        doctor(report, "backend")
        run(
            report,
            "uv",
            [
                "run",
                "--project",
                "backend",
                "--locked",
                "ruff",
                "format",
                "--check",
                "--config",
                "backend/pyproject.toml",
                "scripts",
            ],
        )
        run(
            report,
            "uv",
            [
                "run",
                "--project",
                "backend",
                "--locked",
                "ruff",
                "check",
                "--config",
                "backend/pyproject.toml",
                "scripts",
            ],
        )
        run(
            report,
            "uv",
            [
                "run",
                "--project",
                "backend",
                "--locked",
                "pyright",
                "--project",
                "scripts/pyrightconfig.json",
            ],
        )
        output = run(report, "python", ["-m", "unittest", "discover", "-s", "scripts/tests", "-v"])
        report.record("tooling_test_results", "passed", passed=unittest_results(output))
    if stage in {"docs", "B0-foundation"}:
        check_docs(report)
    if stage in {"backend", "B0-foundation"}:
        check_backend(report)
    if stage in {"frontend", "B0-foundation"}:
        check_frontend(report)
    if stage == "infrastructure":
        check_infrastructure(report)
    if stage == "B0-foundation":
        codegen(report, write=False)
    report.record(
        "acceptance_scope", "passed", scope=stage, full_milestone=False, ci_executed=False
    )


def codegen(report: Report, *, write: bool) -> None:
    doctor(report, "backend")
    doctor(report, "web")
    require_files(["tools/codegen/manifest.json", "frontend/tool/generate.py"])
    manifest = json_object(
        json.loads((ROOT / "tools/codegen/manifest.json").read_text(encoding="utf-8"))
    )
    outputs = string_list(manifest.get("backend_outputs"))
    if not outputs or not all(re.fullmatch(r"[a-z][a-z0-9-]*\.json", item) for item in outputs):
        raise DevError(
            "tools/codegen/manifest.json must declare nonempty backend_outputs filenames"
        )
    if len(outputs) != len(set(outputs)):
        raise DevError("Duplicate backend generation output")
    contract_dir = ROOT / "contracts"
    existing = {
        path.relative_to(contract_dir).as_posix()
        for path in contract_dir.rglob("*")
        if path.is_file()
    }
    unknown = existing - set(outputs)
    if unknown:
        raise DevError("Unknown managed contract files: " + ", ".join(sorted(unknown)))
    if contract_dir.is_symlink() or any((contract_dir / name).is_symlink() for name in outputs):
        raise DevError("Managed contract targets must not be symlinks")
    with tempfile.TemporaryDirectory(prefix="haruka-codegen-") as temporary:
        target = Path(temporary)
        run(
            report,
            "uv",
            ["run", "--locked", "python", "-m", "app.contracts.export", "--output", str(target)],
            cwd=ROOT / "backend",
        )
        actual = {path.name for path in target.iterdir() if path.is_file()}
        if actual != set(outputs):
            raise DevError("Exporter output does not match the managed manifest")
        differences = [
            name
            for name in outputs
            if not (contract_dir / name).is_file()
            or (contract_dir / name).read_bytes() != (target / name).read_bytes()
        ]
        if write:
            contract_dir.mkdir(parents=True, exist_ok=True)
            for name in differences:
                shutil.copyfile(target / name, contract_dir / name)
        elif differences:
            raise DevError("Generated contracts drift: " + ", ".join(differences))
    run(
        report,
        "python",
        [str(ROOT / "frontend/tool/generate.py"), "--write" if write else "--check"],
    )
    report.record(
        "codegen",
        "passed",
        mode="write" if write else "check",
        note="API DTO transition and localization are recorded separately in the generation manifest",
    )


def dev(report: Report, arguments: argparse.Namespace) -> None:
    report.record(
        "development_profile", "not_implemented", profile=arguments.profile, target=arguments.target
    )
    raise DevError(
        "core/jobs application orchestration is not implemented: migrations, seeds, and durable workers remain B0/B1/B2 work. Use 'infra up' for isolated infrastructure and the documented per-process API and Flutter shell commands."
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    for name in ("doctor", "bootstrap"):
        command = commands.add_parser(name)
        command.add_argument(
            "--scope", choices=SCOPES if name == "doctor" else BOOTSTRAP_SCOPES, required=True
        )
    command = commands.add_parser("infra")
    command.add_argument("action", choices=INFRA_ACTIONS)
    command = commands.add_parser("check")
    command.add_argument(
        "--stage",
        choices=(
            "docs",
            "tooling",
            "backend",
            "frontend",
            "infrastructure",
            "B0-foundation",
            "B0",
            "B1",
            "B2",
        ),
        required=True,
    )
    command = commands.add_parser("codegen")
    mode = command.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    command = commands.add_parser("dev")
    command.add_argument("--profile", choices=("core", "jobs"), default="core")
    command.add_argument("--target", choices=("web", "windows", "android"), required=True)
    command.add_argument("--device")
    command.add_argument("--config", type=Path, default=ROOT / "backend/.env")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    configure_console()
    if sys.version_info < (3, 13):  # noqa: UP036 - standalone entry diagnoses an unsupported host interpreter.
        emit(
            "Python 3.13 is required. Use the exact tools/toolchain.json Python version; no system SDK will be upgraded."
        )
        return 2
    arguments = parser().parse_args(argv)
    report = Report(
        arguments.command,
        getattr(
            arguments,
            "scope",
            getattr(
                arguments,
                "stage",
                getattr(arguments, "profile", getattr(arguments, "action", "generated")),
            ),
        ),
    )
    try:
        if arguments.command == "doctor":
            doctor(report, arguments.scope)
        elif arguments.command == "bootstrap":
            bootstrap(report, arguments.scope)
        elif arguments.command == "check":
            check(report, arguments.stage)
        elif arguments.command == "codegen":
            codegen(report, write=arguments.write)
        elif arguments.command == "infra":
            infra(report, arguments.action)
        else:
            dev(report, arguments)
        report.result = "passed"
        return 0
    except (DevError, OSError, ValueError) as error:
        report.record("result", "failed", reason=redact(str(error)))
        emit(f"FAILED: {error}")
        return 1
    finally:
        path = report.save()
        emit(f"Report: {path.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    raise SystemExit(main())
