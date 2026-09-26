"""Build and run an installed wheel outside the checkout, without editable dependencies.

Run with the pinned Python: backend/tools/verify_distribution.py --uv <pinned-uv>.
Evidence remains in ignored artifacts/package-check; no existing files are deleted.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(args: list[str], cwd: Path, env: dict[str, str], *, expected: int = 0) -> str:
    result = subprocess.run(  # noqa: S603 - fixed argument arrays; no shell or user-provided command text.
        args,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=180,
    )
    if result.returncode != expected:
        sys.stderr.write(f"Package check failed: {Path(args[0]).name}; exit={result.returncode}\n")
        raise RuntimeError("installed artifact verification failed")
    return result.stdout + result.stderr


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uv", required=True, type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        help="explicit local infrastructure config for installed lifecycle checks",
    )
    parser.add_argument(
        "--maintenance-config",
        type=Path,
        help="isolated maintenance target for installed read-only status check",
    )
    args = parser.parse_args()
    uv = str(args.uv.resolve(strict=True))
    infrastructure_config = args.config.resolve(strict=True) if args.config is not None else None
    maintenance_config = (
        args.maintenance_config.resolve(strict=True)
        if args.maintenance_config is not None
        else None
    )
    run_id = uuid.uuid4().hex
    work = Path(tempfile.gettempdir()) / "haruka-package-check" / run_id
    work.mkdir(parents=True)
    outside = work / "outside"
    outside.mkdir()
    # Installed code runs in a directory without a source tree or PYTHONPATH.
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("HARUKA_") and key not in {"PYTHONPATH", "UV_PROJECT_ENVIRONMENT"}
    }
    env["UV_CACHE_DIR"] = str(work / "cache")
    backend = ROOT / "backend"
    run(
        [uv, "build", "--no-cache", "--require-hashes", "--out-dir", str(work / "dist")],
        backend,
        env,
    )
    wheel = next((work / "dist").glob("*.whl"))
    # The migration bundle is a same-version sdist attachment, not a checkout path.
    with tarfile.open(next((work / "dist").glob("*.tar.gz"))) as source:
        source.extractall(work / "source-bundle", filter="data")
    migration_bundle = next((work / "source-bundle").glob("*/alembic"))
    requirements = work / "requirements.txt"
    run(
        [
            uv,
            "export",
            "--locked",
            "--no-dev",
            "--no-emit-project",
            "--format",
            "requirements-txt",
            "--output-file",
            str(requirements),
        ],
        backend,
        env,
    )
    run([uv, "venv", "--python", "3.13.6", str(work / "runtime")], outside, env)
    binaries = work / "runtime" / ("Scripts" if os.name == "nt" else "bin")
    python = binaries / ("python.exe" if os.name == "nt" else "python")
    run(
        [
            uv,
            "pip",
            "sync",
            "--no-build",
            "--python",
            str(python),
            "--require-hashes",
            str(requirements),
        ],
        outside,
        env,
    )
    run(
        [uv, "pip", "install", "--no-build", "--python", str(python), "--no-deps", str(wheel)],
        outside,
        env,
    )
    location = run(
        [str(python), "-I", "-c", "import app; print(app.__file__)"], outside, env
    ).strip()
    if not Path(location).resolve().is_relative_to((work / "runtime").resolve()):
        raise RuntimeError("application imported from outside installed environment")
    run(
        [
            str(python),
            "-I",
            "-c",
            "from app.maintenance.schema import load_constraint_baseline; "
            "from app.maintenance.migrations import load_migration_resources; "
            "from pathlib import Path; import sys; "
            "load_constraint_baseline(); load_migration_resources(Path(sys.argv[1]))",
            str(migration_bundle),
        ],
        outside,
        env,
    )
    if maintenance_config is not None:
        manage = str(binaries / ("haruka-manage.exe" if os.name == "nt" else "haruka-manage"))
        run(
            [
                manage,
                "db",
                "status",
                "--maintenance-config",
                str(maintenance_config),
                "--migrations-dir",
                str(migration_bundle),
            ],
            outside,
            env,
        )
    config = outside / "shell.env"
    config.write_text(
        "HARUKA_APP_ENV=test\nHARUKA_INSTANCE_ID=haruka-test-wheel\n"
        "HARUKA_PUBLIC_BASE_URL=http://localhost:8000\n",
        encoding="utf-8",
    )
    for name in (
        "haruka-api",
        "haruka-worker",
        "haruka-outbox",
        "haruka-mail-worker",
        "haruka-manage",
    ):
        cli = str(binaries / (name + ".exe" if os.name == "nt" else name))
        run([cli, "--help"], outside, env)
        run([cli, "--config", str(config), "--check-config"], outside, env)
        if name in {"haruka-worker", "haruka-outbox", "haruka-mail-worker"}:
            run([cli, "--config", str(config)], outside, env, expected=2)
        if name == "haruka-manage":
            run([cli, "--config", str(config), "db"], outside, env, expected=2)
        if name == "haruka-api":
            output = run([cli, "--config", str(config), "--check-startup"], outside, env)
            if (
                '"event": "process.started"' not in output
                or '"event": "process.stopped"' not in output
            ):
                raise RuntimeError("installed process lifecycle did not run and close")
        if infrastructure_config is not None and name != "haruka-mail-worker":
            arguments = [cli, "--config", str(infrastructure_config)]
            arguments += (
                ["check-infrastructure"] if name == "haruka-manage" else ["--check-startup"]
            )
            output = run(arguments, outside, env)
            if (
                '"event": "infrastructure.connected"' not in output
                or '"event": "process.stopped"' not in output
            ):
                raise RuntimeError("installed infrastructure did not connect and close")
    run(
        [str(python), "-I", "-m", "app.contracts.export", "--output", str(work / "contracts")],
        outside,
        env,
    )
    # A fresh cache with a deliberately wrong build hash must reject the build.
    invalid = work / "invalid-build"
    invalid.mkdir()
    shutil.copytree(backend / "app", invalid / "app", ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(backend / "README.md", invalid / "README.md")
    original = (backend / "pyproject.toml").read_text(encoding="utf-8")
    import tomllib

    configuration = tomllib.loads(original)
    good_hash = configuration["tool"]["uv"]["build-constraint-dependencies"][0]["hashes"][0]
    (invalid / "pyproject.toml").write_text(
        original.replace(good_hash, "sha256:" + "0" * 64), encoding="utf-8"
    )
    result = subprocess.run(  # noqa: S603 - fixed command against this invocation's synthetic build directory.
        [uv, "build", "--no-cache", "--require-hashes", "--out-dir", str(work / "rejected")],
        cwd=invalid,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=180,
    )
    if result.returncode == 0 or "hash" not in result.stderr.lower():
        raise RuntimeError("incorrect build hash did not reject the build")
    report = {
        "scope": "infrastructure-package" if infrastructure_config else "foundation-package",
        "platform": sys.platform,
        "wheel": wheel.name,
        "sha256": hashlib.sha256(wheel.read_bytes()).hexdigest(),
        "runtime": "non-editable; runtime-only locked dependencies; isolated cwd and Python import",
        "entries": 5,
        "lifespan": "started-and-stopped",
        "wrong_build_hash": "rejected",
        "infrastructure_lifespans": 4 if infrastructure_config else 0,
        "migration_bundle": "validated from built sdist, outside checkout",
        "packaged_constraint_baseline": "validated",
        "installed_database_status": maintenance_config is not None,
        "limitations": [
            "Schema readiness validated only when explicit infrastructure configuration was supplied",
            "No worker/outbox/mail business execution or SMTP delivery",
            "Results apply only to the recorded execution platform",
        ],
    }
    evidence = ROOT / "artifacts" / "package-check" / run_id
    evidence.mkdir(parents=True)
    (evidence / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    sys.stdout.write(f"Package check passed; evidence: {evidence.relative_to(ROOT)}/report.json\n")


if __name__ == "__main__":
    main()
