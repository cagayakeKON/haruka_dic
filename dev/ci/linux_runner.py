"""Linux SCF-B0-01/02/03 evidence, run only in a fresh container from a Git bundle.

This writes raw evidence, never an independently reviewed procedure receipt.
No Docker socket, host packages, application checkout, or secret directory is mounted.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.request import ProxyHandler, build_opener

from json_boundary import obj, objects, read_object, string, strings
from proxy import Proxies


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def validate_lock(root: Path, image_lock: Path) -> None:
    lock = read_object(root / "dev/ci/toolchain.lock.json")
    main = read_object(root / "tools/toolchain.json")
    if lock != read_object(image_lock):
        raise ValueError("Image SDK lock differs from committed SDK lock")
    for artifact in objects(lock["artifacts"]):
        declared = main[string(artifact["name"])]
        if artifact["name"] == "flutter":
            if (artifact["version"], artifact["revision"]) != (
                obj(declared)["version"],
                obj(declared)["revision"],
            ):
                raise ValueError("Flutter lock disagrees with project toolchain")
        elif artifact["version"] != declared:
            raise ValueError("SDK lock disagrees with project toolchain")
    if sys.version.split()[0] != main["python"]:
        raise ValueError("Container Python disagrees with project toolchain")
    for key in ("base_image", "debian_snapshot", "platform"):
        if lock[key] != obj(main["linux_validation"])[key]:
            raise ValueError("Container base lock disagrees with project toolchain")


def private_config(source: Path, target: Path, log: Path) -> None:
    """Retain all identity/credential values; redirect only the private log destination."""
    lines = source.read_text(encoding="utf-8-sig").splitlines()
    keys = [line.partition("=")[0].strip() for line in lines if "=" in line]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate configuration keys")
    if not log.is_absolute() or target.exists():
        raise ValueError("Private configuration destination must be new and logs absolute")
    lines = [line for line in lines if line.partition("=")[0].strip() != "HARUKA_LOG_FILE"]
    lines.append("HARUKA_LOG_FILE=" + str(log))
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    target.chmod(0o600)


def junit(path: Path, expected: list[str]) -> int:
    tree = ET.parse(path).getroot()  # noqa: S314 - locally generated test evidence.
    cases = list(tree.iter("testcase"))
    actual = [(node.get("classname"), node.get("name")) for node in cases]
    required = [
        (node.split("::")[0].removesuffix(".py").replace("/", "."), node.split("::")[1])
        for node in expected
    ]
    if sorted(actual) != sorted(required) or any(
        list(node.iter(tag)) for node in cases for tag in ("failure", "error", "skipped")
    ):
        raise ValueError("Required test evidence is empty, incomplete, skipped or failed")
    return len(cases)


def free_ports() -> None:
    for port in (18080, 5173):
        with socket.socket() as candidate:
            candidate.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            candidate.bind(("127.0.0.1", port))
            candidate.listen(1)


def api_ready() -> bool:
    try:
        with build_opener(ProxyHandler({})).open(
            "http://127.0.0.1:18080/health/ready", timeout=2
        ) as response:
            value = obj(json.loads(response.read()))
            return response.status == 200 and obj(value.get("data")).get("status") == "ok"
    except OSError:
        return False


def require_graceful_signal_exit(role: str, code: int, output: str) -> None:
    # Uvicorn restores and re-raises SIGTERM after its lifespan has completed.
    expected = -signal.SIGTERM if role == "api" else 0
    if code != expected or '"event": "process.stopped"' not in output:
        raise RuntimeError("Lifecycle failed graceful SIGTERM: " + role)


FAILURE_REASONS = {
    "missing-runtime-lock": "Required files are missing: backend/uv.lock",
    "missing-required-script": "Required files are missing: dev/infra.py",
    "builder-version-drift": "Backend builder or uv requirement differs from tools/toolchain.json",
    "missing-build-hash": "Build constraint lacks an exact version or a SHA-256 hash",
    "runtime-lock-drift": "uv failed with exit code 1",
    "missing-flutter": "Missing Flutter SDK; install the exact revision in tools/toolchain.json",
    "invalid-config": "Development configuration must target the declared dev/test instance",
    "occupied-port": "Loopback port 18080 is occupied or unavailable; stop its owner explicitly or use another declared target",
    "unreachable-service-doctor": "haruka-manage failed with exit code 2",
}


def require_failure_evidence(name: str, report: dict[str, object], output: str) -> None:
    """A matching exit code alone never establishes the intended negative assertion."""
    records = objects(report.get("records"))
    reasons = [
        record.get("reason")
        for record in records
        if record.get("name") == "result" and record.get("status") == "failed"
    ]
    if report.get("result") != "failed" or reasons != [FAILURE_REASONS[name]]:
        raise RuntimeError("Unexpected or missing negative diagnostic: " + name)
    if name == "runtime-lock-drift":
        if not any(
            record.get("name") == "uv"
            and record.get("status") == "failed"
            and record.get("exit_code") == 1
            and record.get("arguments") == ["sync", "--locked", "--group", "dev"]
            for record in records
        ):
            raise RuntimeError("Runtime lock failure did not originate from locked sync")
        if "--locked" not in output or "needs to be updated" not in output:
            raise RuntimeError("Runtime lock rejection diagnostic missing")
    if name == "unreachable-service-doctor":
        if not any(
            record.get("name") == "runtime_configuration" and record.get("status") == "ready"
            for record in records
        ):
            raise RuntimeError("Dependency failure occurred before valid configuration")
        if not any(
            record.get("name") == "haruka-manage"
            and record.get("status") == "failed"
            and record.get("exit_code") == 2
            and strings(record.get("arguments"))[-1] == "check-infrastructure"
            for record in records
        ):
            raise RuntimeError("Dependency failure did not originate from infrastructure check")


class Run:
    def __init__(self, root: Path, output: Path, commit: str) -> None:
        self.root = root
        self.output = output
        self.private = Path("/work/private")
        self.private.mkdir(mode=0o700)
        self.records: list[dict[str, object]] = []
        self.summary: dict[str, object] = {
            "schema_version": 1,
            "scope": ["SCF-B0-01:linux", "SCF-B0-02:linux", "SCF-B0-03:linux"],
            "commit": commit,
            "platform": sys.platform,
            "remote_ci_executed": False,
            "reviewed": False,
            "passed": False,
            "commands": self.records,
        }

    def command(
        self,
        name: str,
        arguments: list[str],
        *,
        expected: int = 0,
        timeout: int = 900,
        cwd: Path | None = None,
        environment: dict[str, str] | None = None,
    ) -> str:
        """Capture authorized CLI diagnostics to unique files, never config contents."""
        if any(record["name"] == name for record in self.records):
            raise ValueError("Repeated command evidence name")
        started = time.monotonic()
        result = subprocess.run(  # noqa: S603 - literal argv; no shell interpolation.
            arguments,
            cwd=cwd or self.root,
            env=environment or dict(os.environ),
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=timeout,
            check=False,
        )
        output = result.stdout + result.stderr
        (self.output / f"{name}.log").write_text(output, encoding="utf-8")
        self.records.append(
            {
                "name": name,
                "arguments": arguments,
                "exit_code": result.returncode,
                "expected_exit_code": expected,
                "seconds": round(time.monotonic() - started, 3),
            }
        )
        write_json(self.output / "summary.json", self.summary)
        sys.stdout.write(f"{name}: exit={result.returncode}, expected={expected}\n")
        sys.stdout.flush()
        if result.returncode != expected:
            raise RuntimeError("Command failed: " + name)
        return output

    def dev(
        self,
        name: str,
        *arguments: str,
        expected: int = 0,
        timeout: int = 900,
        environment: dict[str, str] | None = None,
    ) -> str:
        return self.command(
            name,
            [sys.executable, "scripts/dev.py", *arguments],
            expected=expected,
            timeout=timeout,
            environment=environment,
        )

    def failure_samples(self, config: Path) -> None:
        # Mutations are restored even on failure; the final tracked-tree check is mandatory.
        samples = (
            ("missing-runtime-lock", "backend/uv.lock", None),
            ("missing-required-script", "dev/infra.py", None),
            ("builder-version-drift", "backend/pyproject.toml", "builder"),
            ("missing-build-hash", "backend/pyproject.toml", "hash"),
            ("runtime-lock-drift", "backend/pyproject.toml", "runtime"),
        )
        for name, relative, mutation in samples:
            path = self.root / relative
            original = path.read_bytes()
            try:
                if mutation is None:
                    path.unlink()
                elif mutation == "builder":
                    content = original.decode().replace("hatchling==1.32.4", "hatchling==0.0.0")
                    path.write_text(content)
                elif mutation == "runtime":
                    content = original.decode().replace('version = "0.1.0"', 'version = "0.1.1"', 1)
                    path.write_text(content)
                else:
                    content = re.sub(
                        r'hashes = \["sha256:[a-f0-9]{64}"\]',
                        "hashes = []",
                        original.decode(),
                        count=1,
                    )
                    path.write_text(content)
                arguments = ("doctor", "--scope", "backend")
                if name == "missing-required-script":
                    arguments = ("infra", "init")
                elif name == "runtime-lock-drift":
                    arguments = ("bootstrap", "--scope", "backend")
                # Re-resolving an intentionally changed project needs index metadata;
                # a locked sync downloads wheels without warming that metadata cache.
                environment = dict(os.environ)
                if mutation != "runtime":
                    environment["UV_OFFLINE"] = "true"
                self.negative(name, *arguments, environment=environment)
            finally:
                path.write_bytes(original)
        environment = {**os.environ, "PATH": "/usr/local/bin:/usr/bin:/bin"}
        self.negative("missing-flutter", "doctor", "--scope", "web", environment=environment)
        broken = self.private / "invalid.env"
        broken.write_text("HARUKA_APP_ENV=production\n", encoding="utf-8")
        self.negative("invalid-config", "doctor", "--scope", "backend", "--config", str(broken))
        with socket.socket() as holder:
            holder.bind(("127.0.0.1", 18080))
            holder.listen()
            self.negative(
                "occupied-port",
                "doctor",
                "--scope",
                "backend",
                "--config",
                str(config),
                "--target",
                "web",
                "--api-port",
                "18080",
            )
            if holder.getsockname()[1] != 18080:
                raise RuntimeError("Port holder was disturbed")

    def negative(
        self, name: str, *arguments: str, environment: dict[str, str] | None = None
    ) -> None:
        previous = set((self.root / "artifacts/dev").glob("*.json"))
        output = self.dev(name, *arguments, expected=1, environment=environment)
        reports = set((self.root / "artifacts/dev").glob("*.json")) - previous
        if len(reports) != 1:
            raise RuntimeError("Negative sample structured report missing or ambiguous")
        require_failure_evidence(name, read_object(next(iter(reports))), output)
        self.records[-1]["expected_diagnostic_verified"] = FAILURE_REASONS[name]

    def execute(self) -> None:
        commit = self.command("commit", ["git", "rev-parse", "HEAD"]).strip()
        if commit != self.summary["commit"]:
            raise ValueError("Checkout is not the requested commit")
        if self.command("initial-status", ["git", "status", "--porcelain"]).strip():
            raise ValueError("Checkout must start clean")
        if any(
            (self.root / path).exists()
            for path in (
                "backend/.venv",
                ".tools",
                "tools/node/node_modules",
                "frontend/.dart_tool",
            )
        ):
            raise ValueError("Checkout includes a preexisting dependency environment")
        validate_lock(self.root, Path("/opt/haruka-ci/toolchain.lock.json"))
        self.summary["toolchain_sha256"] = digest(self.root / "tools/toolchain.json")
        self.summary["image_lock_sha256"] = digest(Path("/opt/haruka-ci/toolchain.lock.json"))
        shutil.copyfile("/opt/haruka-ci/debian-packages.txt", self.output / "debian-packages.txt")
        locks = [
            "backend/uv.lock",
            "backend/pyproject.toml",
            "frontend/pubspec.lock",
            "tools/node/package-lock.json",
        ]
        before = {path: digest(self.root / path) for path in locks}
        self.summary["initial_lock_hashes"] = before
        for scope in ("backend", "docs", "web"):
            self.dev(f"doctor-{scope}", "doctor", "--scope", scope)
            self.dev(f"bootstrap-{scope}-1", "bootstrap", "--scope", scope)
        user_config = self.root / "backend/.env"
        with user_config.open("a", encoding="utf-8") as config:
            config.write("\n# preserved-local-user-setting\n")
        user_hash = digest(user_config)
        for scope in ("backend", "docs", "web"):
            self.dev(f"bootstrap-{scope}-2", "bootstrap", "--scope", scope)
        if before != {path: digest(self.root / path) for path in locks} or user_hash != digest(
            user_config
        ):
            raise RuntimeError("Bootstrap changed locks or user configuration")
        self.summary["bootstrap_idempotent"] = True
        self.dev("check-docs", "check", "--stage", "docs")
        self.dev("codegen-check-1", "codegen", "--check")
        self.dev("codegen-check-2", "codegen", "--check")
        # These selected tests cover the command/lifecycle implementation, not the quality32 suite.
        matrix = read_object(self.root / "dev/ci/execution_matrix.json")
        self.command(
            "development-tests",
            [
                sys.executable,
                "dev/ci/selected_unittest.py",
                "--output",
                str(self.output / "development-tests.json"),
            ],
        )
        self.summary["development_test_count"] = len(strings(matrix["unittest"]))
        test_config, dev_config = self.private / "test.env", self.private / "dev.env"
        private_config(Path("/input/test.env"), test_config, self.output / "runtime-test.jsonl")
        private_config(Path("/input/dev.env"), dev_config, self.output / "runtime-dev.jsonl")
        self.failure_samples(dev_config)
        self.negative(
            "unreachable-service-doctor",
            "doctor",
            "--scope",
            "backend",
            "--config",
            str(test_config),
        )
        python = str(self.root / "backend/.venv/bin/python")
        self.command(
            "editable-install",
            [
                python,
                "-c",
                "import importlib.metadata as m,json; d=m.distribution('haruka-backend'); u=json.loads(d.read_text('direct_url.json')); assert u['dir_info']['editable'] is True; print(json.dumps({'editable':True,'packages':sorted((x.metadata['Name'],x.version) for x in m.distributions())}))",
            ],
        )
        self.command(
            "clean-build-closure",
            [
                "uv",
                "build",
                "--no-cache",
                "--require-hashes",
                "--verbose",
                "--out-dir",
                str(self.private / "audit-dist"),
            ],
            cwd=self.root / "backend",
        )
        selection = strings(matrix["pytest"])
        junit_path = self.output / "backend-lifecycle.xml"
        with Proxies() as proxies:
            self.command(
                "backend-lifecycle-tests",
                [
                    python,
                    "-m",
                    "pytest",
                    "-o",
                    "xfail_strict=true",
                    *selection,
                    f"--junitxml={junit_path}",
                ],
                cwd=self.root / "backend",
                environment={**os.environ, "HARUKA_INTEGRATION_CONFIG": str(test_config)},
            )
            self.summary["backend_test_count"] = junit(junit_path, selection)
            self.dev(
                "runtime-doctor",
                "doctor",
                "--scope",
                "backend",
                "--config",
                str(test_config),
                "--profile",
                "jobs",
            )
            self.command(
                "installed-distribution",
                [
                    python,
                    "backend/tools/verify_distribution.py",
                    "--uv",
                    "/usr/local/bin/uv",
                    "--config",
                    str(test_config),
                    "--maintenance-config",
                    "/input/maintenance.env",
                ],
                timeout=1800,
            )
            for repeat in (1, 2):
                for profile in ("core", "jobs"):
                    name = f"development-{profile}-{repeat}"
                    previous = set((self.root / "artifacts/dev").glob("dev-*.json"))
                    self.dev(
                        name,
                        "dev",
                        "--profile",
                        profile,
                        "--target",
                        "web",
                        "--config",
                        str(dev_config),
                        "--api-port",
                        "18080",
                        "--startup-timeout",
                        "300",
                        "--shutdown-timeout",
                        "20",
                        "--run-seconds",
                        "2",
                        timeout=420,
                    )
                    free_ports()
                    reports = set((self.root / "artifacts/dev").glob("dev-*.json")) - previous
                    if len(reports) != 1:
                        raise RuntimeError("Development report missing or ambiguous")
                    report = read_object(next(iter(reports)))
                    shutdowns = [
                        record
                        for record in objects(report["records"])
                        if record["name"] == "owned_process_shutdown"
                    ]
                    if (
                        report["result"] != "passed"
                        or len(shutdowns) != (4 if profile == "jobs" else 2)
                        or any(record["status"] != "passed" for record in shutdowns)
                    ):
                        raise RuntimeError("Development structured lifecycle evidence failed")
                    self.wait_idle(proxies)
            self.signal_lifecycles(test_config)
            self.wait_idle(proxies)
        free_ports()
        self.command("final-tracked-tree", ["git", "diff", "--exit-code"])
        if before != {path: digest(self.root / path) for path in locks} or user_hash != digest(
            user_config
        ):
            raise RuntimeError("Validation changed locks or user configuration")
        self.summary["passed"] = True

    @staticmethod
    def wait_idle(proxies: Proxies) -> None:
        deadline = time.monotonic() + 5
        while True:
            try:
                proxies.require_idle()
                return
            except RuntimeError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.1)

    def signal_lifecycles(self, config: Path) -> None:
        """Exercise actual POSIX SIGTERM, in addition to development marker shutdown."""
        for role in ("api", "worker", "outbox"):
            cli = self.root / "backend/.venv/bin" / ("haruka-" + role)
            command = [str(cli), "--config", str(config)]
            command.extend(["--port", "18080"] if role == "api" else ["--lifecycle-only"])
            path = self.output / f"sigterm-{role}.log"
            with path.open("w", encoding="utf-8") as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)  # noqa: S603 - installed owned CLI.
                try:
                    deadline = time.monotonic() + 45
                    while True:
                        output = path.read_text(encoding="utf-8")
                        ready = (
                            api_ready() if role == "api" else '"lifecycle_ready": true' in output
                        )
                        if ready:
                            break
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError("Lifecycle did not become ready: " + role)
                        time.sleep(0.1)
                    started = time.monotonic()
                    process.terminate()
                    code = process.wait(timeout=20)
                    output = path.read_text(encoding="utf-8")
                    require_graceful_signal_exit(role, code, output)
                    self.records.append(
                        {
                            "name": "sigterm-" + role,
                            "exit_code": code,
                            "expected_exit_code": -signal.SIGTERM if role == "api" else 0,
                            "signal": "SIGTERM",
                            "seconds": round(time.monotonic() - started, 3),
                        }
                    )
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)

    def finish(self) -> None:
        artifacts = self.root / "artifacts"
        if artifacts.exists():
            shutil.copytree(artifacts, self.output / "application-artifacts")
        write_json(self.output / "summary.json", self.summary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("/work/checkout"))
    parser.add_argument("--output", type=Path, default=Path("/evidence"))
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    run = Run(args.root, args.output, args.commit)
    try:
        run.execute()
    except Exception as error:
        run.summary["failure"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        run.finish()


if __name__ == "__main__":
    main()
