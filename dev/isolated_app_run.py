"""Own a single isolated current slice database/configuration and local process session.

Run with the backend's locked Python environment. This harness never updates
public or deletes a schema without its own persisted ownership marker.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from collections.abc import AsyncIterator
from itertools import islice
from pathlib import Path
from typing import Literal, Protocol, cast
from uuid import uuid4

from dev.infra import compose, local_docker_guard
from dev.local_smtp_capture import (
    LOCAL_ROOT,
    guarded_spool,
    private_directory,
    restrict_private_file,
)
from dev.local_web_static import validate_web_root
from minio import Minio
from minio.commonconfig import Tags
from pydantic import SecretStr
from scripts import development, processes
from scripts.dev import DevError, tool
from sqlalchemy import text
from sqlalchemy.schema import CreateSchema, DropSchema
from urllib3 import PoolManager, Retry, Timeout

from app.adapters.cache import Cache
from app.core.settings import load_settings
from app.maintenance.migrations import upgrade_database
from app.maintenance.settings import (
    MaintenanceSettings,
    create_maintenance_engine,
    load_maintenance_settings,
)
from app.services.initialization import apply_seed, initialize_admin

ROOT = Path(__file__).resolve().parent.parent
TEST_RUNTIME = ROOT / "dev/.local/test.env"
TEST_MAINTENANCE = ROOT / "dev/.local/test-maintenance.env"
MIGRATIONS = ROOT / "backend/alembic"
API_PORT = 18081
FAULT_UPSTREAM_PORT = 18082
WEB_PORT = 15173
HTTPS_PORT = 18443
SMTP_PORT = 18025
RUN_PATTERN = re.compile(r"[a-f0-9]{32}\Z")


class IsolatedRunError(Exception):
    """Safe failure description without configuration values or credentials."""


class _OwnedRedis(Protocol):
    def scan_iter(self, *, match: str, count: int) -> AsyncIterator[bytes]: ...

    async def delete(self, *names: bytes) -> int: ...


class _OwnedCache(Protocol):
    client: _OwnedRedis

    async def aclose(self) -> None: ...


def run_root(run_id: str) -> Path:
    if not RUN_PATTERN.fullmatch(run_id):
        raise IsolatedRunError(
            "current slice run identity must be a random 32-character lowercase hex value"
        )
    root = (LOCAL_ROOT / run_id).resolve()
    if root.parent != LOCAL_ROOT.resolve():
        raise IsolatedRunError("current slice run directory is outside the isolated local root")
    return root


def write_private(path: Path, contents: str) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        stream.write(contents)
    restrict_private_file(path)


def write_ledger(root: Path, *, run_id: str, state: str, schema: str) -> None:
    ledger = root / "ledger.json"
    temporary = root / "ledger.next"
    if temporary.exists():
        raise IsolatedRunError("unfinished ledger update requires manual inspection")
    write_private(
        temporary,
        json.dumps({"version": 1, "run_id": run_id, "schema": schema, "state": state}) + "\n",
    )
    os.replace(temporary, ledger)


def read_ledger(root: Path, run_id: str) -> dict[str, str]:
    try:
        document: object = json.loads((root / "ledger.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise IsolatedRunError("current slice run ledger is missing or invalid") from error
    if not isinstance(document, dict):
        raise IsolatedRunError("current slice run ledger is invalid")
    data = cast("dict[str, object]", document)
    schema = data.get("schema")
    state = data.get("state")
    if (
        data.get("version") != 1
        or data.get("run_id") != run_id
        or not isinstance(schema, str)
        or schema != f"haruka_migration_test_{run_id}"
        or not isinstance(state, str)
        or state
        not in {
            "planned",
            "created",
            "prepared",
            "serving",
            "stopped",
            "cleaning",
            "cleaning_schema_only",
            "resources_cleaned",
            "cleaned",
        }
    ):
        raise IsolatedRunError(
            "current slice run ledger does not match the requested isolated target"
        )
    return {"schema": schema, "state": state}


def test_maintenance() -> MaintenanceSettings:
    if not TEST_MAINTENANCE.is_file() or TEST_MAINTENANCE.is_symlink():
        raise IsolatedRunError("dedicated local test maintenance configuration is missing")
    settings = load_maintenance_settings(TEST_MAINTENANCE)
    if settings.app_env != "test" or settings.database != "haruka_test":
        raise IsolatedRunError("maintenance configuration must target haruka_test")
    return settings


def isolated_maintenance(schema: str) -> MaintenanceSettings:
    source = test_maintenance()
    return MaintenanceSettings(database_url=source.database_url, test_schema=schema)


def read_runtime_template() -> dict[str, str]:
    if not TEST_RUNTIME.is_file() or TEST_RUNTIME.is_symlink():
        raise IsolatedRunError("dedicated local test runtime configuration is missing")
    values: dict[str, str] = {}
    for line in TEST_RUNTIME.read_text(encoding="utf-8-sig").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(r"HARUKA_[A-Z0-9_]+", key) or key in values:
            raise IsolatedRunError("test runtime template contains invalid or duplicate keys")
        values[key] = value
    if (
        values.get("HARUKA_APP_ENV") != "test"
        or values.get("HARUKA_INSTANCE_ID") != "haruka-test-integration"
        or values.get("HARUKA_RESOURCE_NAMESPACE") != "haruka-test-integration"
    ):
        raise IsolatedRunError("test runtime template has unexpected instance identity")
    return values


async def create_owned_schema(schema: str, run_id: str) -> None:
    if not RUN_PATTERN.fullmatch(run_id) or schema != f"haruka_migration_test_{run_id}":
        raise IsolatedRunError("schema is not derived from this run identity")
    observer = create_maintenance_engine(test_maintenance())
    try:
        async with observer.begin() as connection:
            identity = (
                await connection.execute(text("SELECT current_database(), current_user"))
            ).one()
            if identity != ("haruka_test", "haruka_test_maintenance"):
                raise IsolatedRunError(
                    "database identity differs from isolated test maintenance target"
                )
            await connection.execute(CreateSchema(schema))
            # PostgreSQL utility COMMENT does not accept bind parameters; both
            # interpolated values are fully constrained lowercase hex literals.
            await connection.execute(
                text(f"COMMENT ON SCHEMA {schema} IS 'haruka-b1-run:{run_id}'")
            )
    finally:
        await observer.dispose()


async def remove_owned_schema(schema: str, run_id: str, *, allow_missing: bool = False) -> None:
    if not RUN_PATTERN.fullmatch(run_id) or schema != f"haruka_migration_test_{run_id}":
        raise IsolatedRunError("schema is not derived from this run identity")
    observer = create_maintenance_engine(test_maintenance())
    try:
        async with observer.begin() as connection:
            identity = (
                await connection.execute(text("SELECT current_database(), current_user"))
            ).one()
            if identity != ("haruka_test", "haruka_test_maintenance"):
                raise IsolatedRunError("test database identity differs")
            rows = (
                await connection.execute(
                    text(
                        "SELECT obj_description(oid, 'pg_namespace') FROM pg_namespace WHERE nspname=:schema"
                    ),
                    {"schema": schema},
                )
            ).all()
            if not rows and allow_missing:
                return
            if len(rows) != 1 or rows[0][0] != f"haruka-b1-run:{run_id}":
                raise IsolatedRunError("schema ownership marker or test database identity differs")
            await connection.execute(DropSchema(schema, cascade=True))
    finally:
        await observer.dispose()


async def remove_owned_cache_namespace(config: Path, run_id: str) -> None:
    if not RUN_PATTERN.fullmatch(run_id) or config != run_root(run_id) / "runtime.env":
        raise IsolatedRunError("cache cleanup target differs from this run")
    settings = load_settings(config)
    namespace = f"haruka-test-{run_id}"
    if (
        settings.app_env != "test"
        or settings.instance_id != namespace
        or settings.resource_namespace != namespace
        or settings.test_schema != f"haruka_migration_test_{run_id}"
    ):
        raise IsolatedRunError("cache cleanup identity differs from this run")
    cache = cast("_OwnedCache", Cache(settings.core_infrastructure()))
    redis = cache.client
    prefix = f"{namespace}:".encode("ascii")
    try:
        batch: list[bytes] = []
        async for key in redis.scan_iter(match=f"{namespace}:*", count=100):
            if not key.startswith(prefix):
                raise IsolatedRunError("cache key escaped the owned namespace")
            batch.append(key)
            if len(batch) == 100:
                await redis.delete(*batch)
                batch.clear()
        if batch:
            await redis.delete(*batch)
    finally:
        await cache.aclose()


def configure_owned_job_topic(run_id: str, *, delete: bool = False) -> None:
    """Only provision/remove this ledger-owned run's isolated Kafka topic."""
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if delete and ledger["state"] not in {
        "cleaning",
        "cleaning_schema_only",
        "resources_cleaned",
    }:
        raise IsolatedRunError("topic cleanup requires an owned stopped run")
    if not delete and ledger["state"] != "created":
        raise IsolatedRunError("topic creation requires a newly owned run")
    local_docker_guard()
    arguments = [
        "exec",
        "-T",
        "kafka",
        "/opt/kafka/bin/kafka-topics.sh",
        "--bootstrap-server",
        "kafka:9092",
        "--delete" if delete else "--create",
        "--if-exists" if delete else "--if-not-exists",
        "--topic",
        f"haruka-test-{run_id}.jobs",
    ]
    if not delete:
        arguments.extend(
            (
                "--partitions",
                "1",
                "--replication-factor",
                "1",
                "--config",
                "retention.ms=86400000",
            )
        )
    compose(*arguments, timeout=30)


def configure_owned_object_storage(run_id: str, *, delete: bool = False) -> None:
    """Provision an exact run bucket and an account unable to leave that bucket."""
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    allowed = (
        {"cleaning", "cleaning_schema_only", "resources_cleaned"}
        if delete
        else {"created", "prepared", "stopped"}
    )
    if ledger["state"] not in allowed:
        raise IsolatedRunError("object provisioning requires an owned inactive run")
    local_docker_guard()
    bucket = f"haruka-test-{run_id}"
    account = f"hkt{run_id[:17]}"
    policy_name = f"haruka-run-{run_id}"
    secret_file = root / "storage.secret"
    policy_file = root / "storage-policy.json"
    root_secret = ROOT / "dev/.local/minio/root_password"
    if root_secret.is_symlink() or not root_secret.is_file():
        raise IsolatedRunError("local object provisioning credentials are unavailable")
    pool = PoolManager(timeout=Timeout(connect=3, read=5), retries=Retry(total=0))
    client = Minio(
        "127.0.0.1:19100",
        access_key="haruka_local_root",
        secret_key=root_secret.read_text(encoding="utf-8").strip(),
        secure=False,
        region="us-east-1",
        http_client=pool,
    )
    try:
        exists = client.bucket_exists(bucket)
        if exists:
            tags = client.get_bucket_tags(bucket)
            if tags is None or cast("dict[str, str]", tags).get("haruka-run") != run_id:
                raise IsolatedRunError("object bucket lacks this run's ownership tag")
        if not delete and not exists:
            if secret_file.exists() or policy_file.exists():
                raise IsolatedRunError("object provisioning requires fresh owned files")
            write_private(secret_file, secrets.token_hex(24) + "\n")
            statements = [
                {
                    "Effect": "Allow",
                    "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
                    "Resource": [f"arn:aws:s3:::{bucket}"],
                },
                {
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
                    "Resource": [f"arn:aws:s3:::{bucket}/*"],
                },
            ]
            write_private(
                policy_file, json.dumps({"Version": "2012-10-17", "Statement": statements})
            )
            write_private(root / "storage.enabled", "owned\n")
            client.make_bucket(bucket)
            tags = Tags.new_bucket_tags()
            tags["haruka-run"] = run_id
            client.set_bucket_tags(bucket, tags)
        if not delete and (secret_file.is_symlink() or not secret_file.is_file()):
            raise IsolatedRunError("object account secret is unavailable or linked")
        action = (
            f'if mc admin user info local "{account}" >/dev/null 2>&1; then '
            f'mc admin user rm local "{account}" >/dev/null 2>&1; fi\n'
            f'if mc admin policy info local "{policy_name}" >/dev/null 2>&1; then '
            f'mc admin policy rm local "{policy_name}" >/dev/null 2>&1; fi'
            if delete
            else (
                f'mc admin user add local "{account}" "$(tr -d \'\\r\\n\' < /run/model/storage.secret)" >/dev/null 2>&1\n'
                f'mc admin policy create local "{policy_name}" /run/model/storage-policy.json >/dev/null 2>&1\n'
                f'mc admin policy attach local "{policy_name}" --user "{account}" >/dev/null 2>&1'
            )
        )
        script = (
            "set -eu\nmc alias set local http://minio:9000 haruka_local_root "
            "\"$(tr -d '\\r\\n' < /provision/config/root_password)\" >/dev/null 2>&1\n"
            + action
            + "\n"
        )
        compose(
            "run",
            "--rm",
            "--no-deps",
            "-T",
            "--entrypoint",
            "/bin/sh",
            "--volume",
            f"{root}:/run/model:ro",
            "minio-init",
            "-c",
            script,
            timeout=30,
        )
        if delete and exists:
            # Only this tagged run bucket is eligible; enumerate bounded test objects.
            objects = list(islice(client.list_objects(bucket, recursive=True), 1001))
            if len(objects) > 1000:
                raise IsolatedRunError("owned object cleanup exceeds its bounded test scope")
            for item in objects:
                if item.object_name is not None:
                    client.remove_object(bucket, item.object_name)
            client.remove_bucket(bucket)
    finally:
        pool.clear()


async def prepare(*, model_mode: Literal["disabled", "fake", "live"] = "disabled") -> str:
    if model_mode not in {"disabled", "fake", "live"}:
        raise IsolatedRunError("model execution mode must be explicitly registered")
    run_id = uuid4().hex
    root = run_root(run_id)
    root.mkdir(parents=True, exist_ok=False)
    private_directory(root)
    schema = f"haruka_migration_test_{run_id}"
    write_ledger(root, run_id=run_id, state="planned", schema=schema)
    await create_owned_schema(schema, run_id)
    write_ledger(root, run_id=run_id, state="created", schema=schema)
    if model_mode != "disabled":
        write_private(root / "jobs-topic.enabled", "owned\n")
        configure_owned_job_topic(run_id)
        configure_owned_object_storage(run_id)
    settings = isolated_maintenance(schema)
    await upgrade_database(settings, MIGRATIONS)
    await apply_seed(settings)
    admin_password = secrets.token_urlsafe(36)
    admin_email = f"admin-{run_id}@haruka.example.test"
    await initialize_admin(settings, email=admin_email, password=SecretStr(admin_password))
    write_private(root / "admin.secret", admin_password + "\n")
    values = read_runtime_template()
    namespace = f"haruka-test-{run_id}"
    values.update(
        {
            "HARUKA_INSTANCE_ID": namespace,
            "HARUKA_RESOURCE_NAMESPACE": namespace,
            "HARUKA_RESOURCE_PROFILE": "core",
            "HARUKA_TEST_SCHEMA": schema,
            "HARUKA_PUBLIC_BASE_URL": f"https://localhost:{HTTPS_PORT}",
            "HARUKA_ALLOWED_ORIGINS": json.dumps([f"https://localhost:{HTTPS_PORT}"]),
            "HARUKA_SMTP_HOST": "127.0.0.1",
            "HARUKA_SMTP_PORT": str(SMTP_PORT),
            "HARUKA_SMTP_FROM": "noreply@haruka.example.test",
            "HARUKA_SMTP_STARTTLS": "false",
            "HARUKA_MAIL_DELIVERY_ENABLED": "true",
            "HARUKA_AUTH_SIGNING_KEY": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(
                "ascii"
            ),
            "HARUKA_AUTH_DIGEST_KEY": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(
                "ascii"
            ),
            "HARUKA_MAIL_ENCRYPTION_KEY": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(
                "ascii"
            ),
            "HARUKA_LOG_FILE": str(
                (ROOT / "dev/.local/logs" / f"test.isolated.{run_id}.jsonl").resolve()
            ),
        }
    )
    if model_mode != "disabled":
        values.update(
            {
                "HARUKA_RESOURCE_PROFILE": "jobs",
                "HARUKA_MODEL_EXECUTION_MODE": model_mode,
                "HARUKA_CREDENTIAL_ENCRYPTION_KEY_VERSION": "v1",
                "HARUKA_CREDENTIAL_KEYRING": json.dumps(
                    {"v1": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii")}
                ),
                "HARUKA_S3_BUCKET": namespace,
                "HARUKA_S3_ACCESS_KEY": f"hkt{run_id[:17]}",
                "HARUKA_S3_SECRET_KEY": (root / "storage.secret")
                .read_text(encoding="utf-8")
                .strip(),
            }
        )
    write_private(
        root / "runtime.env",
        "".join(f"{key}={value}\n" for key, value in values.items()),
    )
    load_settings(root / "runtime.env")
    guarded_spool(root / "mail")
    private_directory(root / "mail")
    write_ledger(root, run_id=run_id, state="prepared", schema=schema)
    return run_id


async def set_model_mode(run_id: str, mode: Literal["fake", "live"]) -> None:
    """Explicitly change provider assembly only while the owned run is quiescent."""
    if mode not in {"fake", "live"}:
        raise IsolatedRunError("model execution mode must be explicitly registered")
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] not in {"prepared", "stopped"}:
        raise IsolatedRunError("model mode changes require a stopped owned run")
    config = root / "runtime.env"
    if config.is_symlink() or not config.is_file() or not (root / "jobs-topic.enabled").is_file():
        raise IsolatedRunError("model mode changes require an owned jobs configuration")
    settings = load_settings(config)
    if (
        settings.app_env != "test"
        or settings.resource_profile != "jobs"
        or settings.instance_id != f"haruka-test-{run_id}"
        or settings.test_schema != ledger["schema"]
    ):
        raise IsolatedRunError("model mode target differs from this run ledger")
    observer = create_maintenance_engine(isolated_maintenance(ledger["schema"]))
    try:
        async with observer.connect() as connection:
            unfinished = await connection.scalar(
                text(
                    "SELECT count(*) FROM jobs WHERE state NOT IN ('succeeded','failed','cancelled')"
                )
            )
            if unfinished != 0:
                raise IsolatedRunError(
                    "finish or cancel all jobs before changing provider assembly"
                )
    finally:
        await observer.dispose()
    lines = config.read_text(encoding="utf-8").splitlines()
    matches = sum(line.startswith("HARUKA_MODEL_EXECUTION_MODE=") for line in lines)
    if matches != 1:
        raise IsolatedRunError("model execution configuration is ambiguous")
    temporary = root / "runtime.model.next"
    write_private(
        temporary,
        "\n".join(
            f"HARUKA_MODEL_EXECUTION_MODE={mode}"
            if line.startswith("HARUKA_MODEL_EXECUTION_MODE=")
            else line
            for line in lines
        )
        + "\n",
    )
    try:
        load_settings(temporary)
        os.replace(temporary, config)
    finally:
        temporary.unlink(missing_ok=True)


def endpoint_ready(origin: str, path: str) -> bool:
    return development.endpoint_ready(origin, path)


def set_web_transport(run_id: str, transport: Literal["http", "https"]) -> None:
    """Select the named run's same-origin loopback transport while it is stopped."""
    if transport not in {"http", "https"}:
        raise IsolatedRunError("unsupported local Web transport")
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] not in {"prepared", "stopped"}:
        raise IsolatedRunError("Web transport changes require a stopped owned run")
    config = root / "runtime.env"
    settings = load_settings(config)
    if (
        settings.app_env != "test"
        or settings.instance_id != f"haruka-test-{run_id}"
        or settings.test_schema != ledger["schema"]
    ):
        raise IsolatedRunError("Web transport target differs from this test run")
    replacements = {
        "HARUKA_PUBLIC_BASE_URL": f"{transport}://localhost:{HTTPS_PORT}",
        "HARUKA_ALLOWED_ORIGINS": json.dumps([f"{transport}://localhost:{HTTPS_PORT}"]),
    }
    lines = config.read_text(encoding="utf-8").splitlines()
    if any(sum(line.startswith(f"{key}=") for line in lines) != 1 for key in replacements):
        raise IsolatedRunError("Web origin configuration is ambiguous")
    temporary = root / "runtime.web.next"
    write_private(
        temporary,
        "\n".join(
            f"{line.partition('=')[0]}={replacements[line.partition('=')[0]]}"
            if line.partition("=")[0] in replacements
            else line
            for line in lines
        )
        + "\n",
    )
    try:
        load_settings(temporary)
        os.replace(temporary, config)
    finally:
        temporary.unlink(missing_ok=True)


def confirmed_processes_absent(results: list[dict[str, object]]) -> bool:
    """Confirm target and supervisor PIDs after Windows Job closure."""
    pids: list[int] = []
    for result in results:
        for field in ("pid", "target_pid"):
            pid = result.get(field)
            if type(pid) is not int or pid <= 0:
                return False
            pids.append(pid)
    if not pids:
        return True
    if os.name == "nt":
        ids = ",".join(str(pid) for pid in sorted(set(pids)))
        script = (
            "$ErrorActionPreference='Stop'; "
            f"try {{ foreach ($targetPid in @({ids})) {{ "
            'if (Get-CimInstance Win32_Process -Filter "ProcessId = $targetPid" -ErrorAction Stop) { exit 1 } '
            "} exit 0 } catch { exit 2 }"
        )
        try:
            completed = subprocess.run(  # noqa: S603 - fixed local command and validated owned paths.
                ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],  # noqa: S607 - Windows system shell, no user command selection.
                capture_output=True,
                check=False,
                timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        return completed.returncode == 0
    for pid in pids:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        except PermissionError:
            return False
        return False
    return True


def _rename_web_directory(source: Path, destination: Path) -> None:
    """Retry a transient Windows directory lock without accepting a partial move."""
    for attempt in range(20):
        try:
            source.rename(destination)
            return
        except OSError as error:
            if attempt == 19 or not source.is_dir() or destination.exists():
                raise IsolatedRunError("isolated Web directory move failed") from error
            time.sleep(0.1)
    raise AssertionError("bounded Web directory move did not finish")


def publish_web_stage(target: Path, staging: Path) -> None:
    """Keep the old release recoverable until the complete stage is published."""
    if staging.is_symlink() or not all(
        (staging / name).is_file() for name in ("index.html", "main.dart.js")
    ):
        raise IsolatedRunError("isolated Web staging is incomplete")
    if any(path.is_symlink() for path in staging.rglob("*")):
        raise IsolatedRunError("isolated Web staging contains a symbolic link")
    previous: Path | None = None
    if target.exists():
        previous = target.with_name(f"web.previous.{uuid4().hex[:12]}")
        _rename_web_directory(target, previous)
    try:
        _rename_web_directory(staging, target)
    except IsolatedRunError as error:
        if previous is not None:
            try:
                _rename_web_directory(previous, target)
            except IsolatedRunError:
                raise IsolatedRunError(
                    "Web publish and rollback failed; staged and previous releases remain"
                ) from error
            raise IsolatedRunError("Web publish failed; previous release restored") from error
        raise IsolatedRunError("Web publish failed; staged release retained") from error
    validate_web_root(target)


def _release_hashes(path: Path) -> dict[str, str]:
    if not path.is_dir() or path.is_symlink():
        raise IsolatedRunError("Web release directory is missing or linked")
    hashes: dict[str, str] = {}
    total_bytes = 0
    for child in path.rglob("*"):
        if child.is_symlink():
            raise IsolatedRunError("Web release contains a symbolic link")
        if not child.is_file():
            continue
        total_bytes += child.stat().st_size
        if len(hashes) >= 10_000 or total_bytes > 256_000_000:
            raise IsolatedRunError("Web release exceeds recovery bounds")
        hashes[child.relative_to(path).as_posix()] = hashlib.sha256(child.read_bytes()).hexdigest()
    if not {"index.html", "main.dart.js"}.issubset(hashes):
        raise IsolatedRunError("Web release is incomplete")
    return hashes


def recover_web(run_id: str, *, expected_main_sha: str, replace: bool = False) -> None:
    """Publish a complete stage left by a stopped run's interrupted move."""
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] != "stopped":
        raise IsolatedRunError("isolated run must be stopped for Web recovery")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_main_sha):
        raise IsolatedRunError("expected Web program digest is invalid")
    settings = load_settings(root / "runtime.env")
    if settings.instance_id != f"haruka-test-{run_id}" or settings.test_schema != ledger["schema"]:
        raise IsolatedRunError("runtime configuration differs from this run ledger")
    target = root / "web"
    staging = root / "web.next"
    if target.exists():
        if not replace:
            raise IsolatedRunError("existing Web release requires --replace")
        validate_web_root(target)
    stage_hashes = _release_hashes(staging)
    source_hashes = _release_hashes(ROOT / "frontend/build/web")
    if (
        stage_hashes.get("main.dart.js") != expected_main_sha
        or source_hashes.get("main.dart.js") != expected_main_sha
        or stage_hashes.keys() != source_hashes.keys()
        or any(
            digest != source_hashes[name]
            for name, digest in stage_hashes.items()
            if name != "flutter_bootstrap.js"
        )
    ):
        raise IsolatedRunError("staged Web release differs from the verified build")
    program = (staging / "main.dart.js").read_bytes()
    if (
        settings.instance_id.encode("ascii") not in program
        or f"https://localhost:{HTTPS_PORT}".encode("ascii") not in program
    ):
        raise IsolatedRunError("staged Web release has another runtime identity")
    publish_web_stage(target, staging)


def build_web(run_id: str, *, replace: bool = False) -> None:
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] not in {"prepared", "stopped"}:
        raise IsolatedRunError("isolated run must be stopped before building Web release")
    target = root / "web"
    staging = root / "web.next"
    if staging.exists():
        raise IsolatedRunError("this run has an unfinished Web release build")
    if target.exists():
        if not replace:
            raise IsolatedRunError(
                "this run already has a Web release; use --replace while stopped"
            )
        validate_web_root(target)
    settings = load_settings(root / "runtime.env")
    if settings.instance_id != f"haruka-test-{run_id}" or settings.test_schema != ledger["schema"]:
        raise IsolatedRunError("runtime configuration differs from this run ledger")
    try:
        flutter = tool("flutter")
    except DevError as error:
        raise IsolatedRunError("Flutter toolchain is unavailable") from error
    environment = {key: value for key, value in os.environ.items() if not key.startswith("HARUKA_")}
    result = subprocess.run(  # noqa: S603 - resolved locked Flutter tool and validated build arguments.
        [
            *flutter,
            "build",
            "web",
            "--release",
            "--no-pub",
            "--dart-define=HARUKA_ENV=dev",
            f"--dart-define=HARUKA_INSTANCE_ID={settings.instance_id}",
            f"--dart-define=HARUKA_API_BASE_URL={settings.public_base_url}",
        ],
        cwd=ROOT / "frontend",
        env=environment,
        capture_output=True,
        timeout=900,
        check=False,
    )
    source = ROOT / "frontend/build/web"
    if result.returncode != 0 or not (source / "index.html").is_file():
        raise IsolatedRunError("isolated Flutter Web release build failed")
    private_directory(staging)
    shutil.copytree(source, staging, dirs_exist_ok=True)
    publish_web_stage(target, staging)


def core_mail_configuration(contents: str) -> str:
    """Keep the owned identity/SMTP secrets while limiting mail to core resources."""
    lines = contents.splitlines()
    if sum(line.startswith("HARUKA_RESOURCE_PROFILE=") for line in lines) != 1:
        raise IsolatedRunError("owned configuration needs one explicit resource profile")
    return (
        "\n".join(
            "HARUKA_RESOURCE_PROFILE=core"
            if line.startswith("HARUKA_RESOURCE_PROFILE=")
            else "HARUKA_MODEL_EXECUTION_MODE=disabled"
            if line.startswith("HARUKA_MODEL_EXECUTION_MODE=")
            else line
            for line in lines
        )
        + "\n"
    )


def serve(run_id: str, *, web: bool, fault_proxy: bool, stop_file: Path, timeout: float) -> None:
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] not in {"prepared", "stopped"}:
        raise IsolatedRunError(
            "current slice run is not prepared or a previous service session remains active"
        )
    if stop_file.resolve().parent != root or stop_file.exists():
        raise IsolatedRunError("stop marker must be a new file in this run directory")
    if not 0 < timeout <= 300:
        raise IsolatedRunError("startup timeout must be within five minutes")
    if web:
        validate_web_root(root / "web")
    ports = [API_PORT, SMTP_PORT]
    if web:
        ports.extend((HTTPS_PORT, WEB_PORT))
    if fault_proxy:
        ports.append(FAULT_UPSTREAM_PORT)
    for port in ports:
        development.require_free_port(port)
    config = root / "runtime.env"
    settings = load_settings(config)
    if settings.instance_id != f"haruka-test-{run_id}" or settings.test_schema != ledger["schema"]:
        raise IsolatedRunError("runtime configuration differs from this run ledger")
    environment = {key: value for key, value in os.environ.items() if not key.startswith("HARUKA_")}
    owner = processes.ProcessOwner(run_id, settings.instance_id)
    session_id = uuid4().hex[:12]
    mail_config = root / f"mail.{session_id}.env"
    # Preserve exact private values without serializing SecretStr representations.
    write_private(
        mail_config,
        core_mail_configuration(config.read_text(encoding="utf-8")),
    )
    mailbox_stop = root / f"mailbox.{session_id}.stop"
    api_stop = root / f"api.{session_id}.stop"
    fault_stop = root / f"fault-proxy.{session_id}.stop"
    mail_worker_stop = root / f"mail-worker.{session_id}.stop"
    model_worker_stop = root / f"model-worker.{session_id}.stop"
    outbox_stop = root / f"outbox.{session_id}.stop"
    proxy_stop = root / f"proxy.{session_id}.stop"
    web_stop = root / f"web.{session_id}.stop"
    stop_report = root / "stop-report.json"
    if stop_report.is_file():
        stop_report.unlink()
    if fault_proxy:
        for stale in (root / "fault.pending.json", root / "fault.active.json"):
            if stale.is_symlink():
                raise IsolatedRunError("stale isolated fault control is linked")
            stale.unlink(missing_ok=True)
    write_ledger(root, run_id=run_id, state="serving", schema=ledger["schema"])
    try:
        if fault_proxy:
            write_private(root / "fault-proxy.enabled", json.dumps({"run_id": run_id}) + "\n")
        owner.start(
            "mailbox",
            [
                sys.executable,
                "-m",
                "dev.local_smtp_capture",
                "serve",
                "--spool",
                str(root / "mail"),
                "--shutdown-file",
                str(mailbox_stop),
            ],
            cwd=ROOT,
            environment=environment,
            shutdown_file=mailbox_stop,
        )
        owner.start(
            "api",
            [
                str(ROOT / "backend/.venv/Scripts/haruka-api.exe"),
                "--config",
                str(config),
                "--port",
                str(FAULT_UPSTREAM_PORT if fault_proxy else API_PORT),
                "--shutdown-file",
                str(api_stop),
            ],
            cwd=ROOT / "backend",
            environment=environment,
            shutdown_file=api_stop,
        )
        owner.start(
            "mail-worker",
            [
                str(ROOT / "backend/.venv/Scripts/python.exe"),
                "-m",
                "app.cli.mail",
                "--config",
                str(mail_config),
                "--shutdown-file",
                str(mail_worker_stop),
            ],
            cwd=ROOT / "backend",
            environment=environment,
            shutdown_file=mail_worker_stop,
        )
        if settings.resource_profile == "jobs":
            for service, entrypoint, marker in (
                ("outbox", "haruka-outbox.exe", outbox_stop),
                ("model-worker", "haruka-worker.exe", model_worker_stop),
            ):
                owner.start(
                    service,
                    [
                        str(ROOT / "backend/.venv/Scripts" / entrypoint),
                        "--config",
                        str(config),
                        "--shutdown-file",
                        str(marker),
                    ],
                    cwd=ROOT / "backend",
                    environment=environment,
                    shutdown_file=marker,
                )
        deadline = time.monotonic() + timeout
        if fault_proxy:
            while not endpoint_ready(f"http://127.0.0.1:{FAULT_UPSTREAM_PORT}", "/health/ready"):
                owner.require_running()
                if time.monotonic() >= deadline:
                    raise IsolatedRunError("isolated upstream API did not become ready")
                time.sleep(0.1)
            owner.start(
                "fault-proxy",
                [
                    sys.executable,
                    "-m",
                    "dev.local_api_fault_proxy",
                    "serve",
                    "--run-id",
                    run_id,
                    "--port",
                    str(API_PORT),
                    "--upstream-port",
                    str(FAULT_UPSTREAM_PORT),
                    "--shutdown-file",
                    str(fault_stop),
                ],
                cwd=ROOT,
                environment=environment,
                shutdown_file=fault_stop,
            )
        while not endpoint_ready(f"http://127.0.0.1:{API_PORT}", "/health/ready"):
            owner.require_running()
            if time.monotonic() >= deadline:
                raise IsolatedRunError("isolated API did not become ready")
            time.sleep(0.1)
        if web:
            owner.start(
                "frontend",
                [
                    sys.executable,
                    "-m",
                    "dev.local_web_static",
                    "--web-root",
                    str(root / "web"),
                    "--port",
                    str(WEB_PORT),
                    "--shutdown-file",
                    str(web_stop),
                ],
                cwd=ROOT,
                environment=environment,
                shutdown_file=web_stop,
            )
            while not endpoint_ready(f"http://127.0.0.1:{WEB_PORT}", "/"):
                owner.require_running()
                if time.monotonic() >= deadline:
                    raise IsolatedRunError("isolated Flutter Web server did not become ready")
                time.sleep(0.1)
            owner.start(
                "https-proxy",
                [
                    sys.executable,
                    "-m",
                    "dev.local_https_gateway",
                    "--spool",
                    str(root / "mail"),
                    "--shutdown-file",
                    str(proxy_stop),
                    *(["--http"] if settings.public_base_url.startswith("http://") else []),
                ],
                cwd=ROOT,
                environment=environment,
                shutdown_file=proxy_stop,
            )
        while not stop_file.exists():
            owner.require_running()
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    finally:
        results = owner.stop(grace_seconds=20)
        if fault_proxy:
            (root / "fault-proxy.enabled").unlink(missing_ok=True)
            for pending in (root / "fault.pending.json", root / "fault.active.json"):
                if pending.is_symlink():
                    raise IsolatedRunError("isolated fault control became linked")
                pending.unlink(missing_ok=True)
        write_private(
            stop_report,
            json.dumps(
                [
                    {
                        field: result.get(field)
                        for field in (
                            "name",
                            "pid",
                            "target_pid",
                            "exit_code",
                            "remaining_app_processes",
                            "forced",
                        )
                    }
                    for result in results
                ]
            )
            + "\n",
        )
        if confirmed_processes_absent(results):
            write_ledger(root, run_id=run_id, state="stopped", schema=ledger["schema"])
            mail_config.unlink(missing_ok=True)


async def cleanup(run_id: str) -> None:
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] == "serving":
        report = root / "stop-report.json"
        if not report.is_file() or report.is_symlink():
            raise IsolatedRunError("serving run has no owned stop report")
        try:
            rows: object = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raise IsolatedRunError("owned stop report is invalid") from None
        if not isinstance(rows, list):
            raise IsolatedRunError("owned stop report is invalid")
        if not all(isinstance(row, dict) for row in cast("list[object]", rows)):
            raise IsolatedRunError("owned stop report is invalid")
        if not confirmed_processes_absent(cast("list[dict[str, object]]", rows)):
            raise IsolatedRunError("owned current slice processes have not been confirmed stopped")
        write_ledger(root, run_id=run_id, state="stopped", schema=ledger["schema"])
        ledger = read_ledger(root, run_id)
    if ledger["state"] not in {
        "created",
        "prepared",
        "stopped",
        "cleaning",
        "cleaning_schema_only",
        "resources_cleaned",
    }:
        raise IsolatedRunError(
            "current slice run is active or incomplete; cleanup requires verified stop"
        )
    if ledger["state"] not in {"cleaning", "cleaning_schema_only", "resources_cleaned"}:
        next_state = "cleaning_schema_only" if ledger["state"] == "created" else "cleaning"
        write_ledger(root, run_id=run_id, state=next_state, schema=ledger["schema"])
    if ledger["state"] != "resources_cleaned":
        if ledger["state"] not in {"created", "cleaning_schema_only"}:
            await remove_owned_cache_namespace(root / "runtime.env", run_id)
        if (root / "jobs-topic.enabled").is_file():
            configure_owned_job_topic(run_id, delete=True)
        if (root / "storage.enabled").is_file():
            configure_owned_object_storage(run_id, delete=True)
        await remove_owned_schema(ledger["schema"], run_id, allow_missing=True)
        write_ledger(root, run_id=run_id, state="resources_cleaned", schema=ledger["schema"])
    spool = guarded_spool(root / "mail")
    if spool.exists() and spool.resolve().parent == root:
        shutil.rmtree(spool)
    for name in (
        "admin.secret",
        "android-actor.secret",
        "runtime.env",
        "localhost.key",
        "localhost.crt",
        "fault-proxy.enabled",
        "fault.pending.json",
        "fault.active.json",
        "fault-control.lock",
        "jobs-topic.enabled",
        "storage.secret",
        "storage-policy.json",
        "storage.enabled",
    ):
        path = root / name
        if path.is_file() and path.resolve().parent == root:
            path.unlink()
    for path in root.glob("fault.cancel.*"):
        if path.is_file() and not path.is_symlink() and path.resolve().parent == root:
            path.unlink()
    for path in root.glob("fault.receipt.*.json"):
        if path.is_file() and not path.is_symlink() and path.resolve().parent == root:
            path.unlink()
    for path in root.glob("fault.next.*.json"):
        if path.is_file() and not path.is_symlink() and path.resolve().parent == root:
            path.unlink()
    for path in root.glob("mail.*.env"):
        if re.fullmatch(r"mail\.[a-f0-9]{12}\.env", path.name) and not path.is_symlink():
            path.unlink(missing_ok=True)
    write_ledger(root, run_id=run_id, state="cleaned", schema=ledger["schema"])


async def seed_source(run_id: str, owner_email: str) -> None:
    from tests.support.learning_reference_scenarios import prepare_learning_source

    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] != "serving":
        raise IsolatedRunError("current slice synthetic source requires a running isolated API")
    settings = load_settings(root / "runtime.env")
    if settings.instance_id != f"haruka-test-{run_id}" or settings.test_schema != ledger["schema"]:
        raise IsolatedRunError("current slice source configuration differs from its run")
    await prepare_learning_source(
        isolated_maintenance(ledger["schema"]),
        owner_email=owner_email,
        instance_id=settings.instance_id,
    )


async def prepare_login_only(run_id: str, email: str) -> str:
    from tests.support.identity_scenarios import prepare_login_only_user

    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] != "serving":
        raise IsolatedRunError("login-only scenario requires a running isolated API")
    settings = load_settings(root / "runtime.env")
    if (
        settings.app_env != "test"
        or settings.instance_id != f"haruka-test-{run_id}"
        or settings.test_schema != ledger["schema"]
    ):
        raise IsolatedRunError("login-only scenario differs from its isolated run")
    user_id = await prepare_login_only_user(isolated_maintenance(ledger["schema"]), email=email)
    return str(user_id)


def main() -> int:
    parser = argparse.ArgumentParser(description="Isolated current slice test environment owner")
    subcommands = parser.add_subparsers(dest="command", required=True)
    preparing = subcommands.add_parser("prepare")
    preparing.add_argument("--model-mode", choices=("disabled", "fake", "live"), default="disabled")
    model_mode = subcommands.add_parser("set-model-mode")
    model_mode.add_argument("--run-id", required=True)
    model_mode.add_argument("--mode", choices=("fake", "live"), required=True)
    web_transport = subcommands.add_parser("set-web-transport")
    web_transport.add_argument("--run-id", required=True)
    web_transport.add_argument("--transport", choices=("http", "https"), required=True)
    building = subcommands.add_parser("build-web")
    building.add_argument("--run-id", required=True)
    building.add_argument("--replace", action="store_true")
    recovering = subcommands.add_parser("recover-web")
    recovering.add_argument("--run-id", required=True)
    recovering.add_argument("--expected-main-sha", required=True)
    recovering.add_argument("--replace", action="store_true")
    serving = subcommands.add_parser("serve")
    serving.add_argument("--run-id", required=True)
    serving.add_argument("--web", action="store_true")
    serving.add_argument("--fault-proxy", action="store_true")
    serving.add_argument("--stop-file", type=Path, required=True)
    serving.add_argument("--startup-timeout", type=float, default=180)
    cleaning = subcommands.add_parser("cleanup")
    cleaning.add_argument("--run-id", required=True)
    seeding = subcommands.add_parser("seed-source")
    seeding.add_argument("--run-id", required=True)
    seeding.add_argument("--owner-email", required=True)
    login_only = subcommands.add_parser("prepare-login-only")
    login_only.add_argument("--run-id", required=True)
    login_only.add_argument("--email", required=True)
    args = parser.parse_args()
    try:
        if any(key.startswith("HARUKA_") for key in os.environ):
            raise IsolatedRunError(
                "current slice runner requires explicit files without inherited HARUKA overrides"
            )
        if args.command == "prepare":
            sys.stdout.write(f"{asyncio.run(prepare(model_mode=args.model_mode))}\n")
        elif args.command == "set-model-mode":
            asyncio.run(set_model_mode(args.run_id, args.mode))
        elif args.command == "set-web-transport":
            set_web_transport(args.run_id, args.transport)
        elif args.command == "build-web":
            build_web(args.run_id, replace=args.replace)
        elif args.command == "recover-web":
            recover_web(
                args.run_id,
                expected_main_sha=args.expected_main_sha,
                replace=args.replace,
            )
        elif args.command == "serve":
            serve(
                args.run_id,
                web=args.web,
                fault_proxy=args.fault_proxy,
                stop_file=args.stop_file,
                timeout=args.startup_timeout,
            )
        elif args.command == "seed-source":
            asyncio.run(seed_source(args.run_id, args.owner_email))
        elif args.command == "prepare-login-only":
            sys.stdout.write(f"{asyncio.run(prepare_login_only(args.run_id, args.email))}\n")
        else:
            asyncio.run(cleanup(args.run_id))
        return 0
    except IsolatedRunError as error:
        # Every runner-owned error is a fixed safe message without private values.
        sys.stderr.write(f"isolated run failed: {error}\n")
        return 1
    except Exception as error:  # Never expose secret-bearing dependency messages.
        sys.stderr.write(
            f"current slice run failed ({type(error).__name__}); "
            "inspect the owned run ledger and isolated service logs.\n"
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
