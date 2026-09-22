"""Own only the isolated Haruka development Compose project and its local secrets."""

from __future__ import annotations

import argparse
import base64
import contextlib
import io
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import uuid
from collections.abc import Generator, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TypeGuard
from urllib.parse import urlencode, urlsplit
from urllib.request import ProxyHandler, build_opener

DEV = Path(__file__).resolve().parent
ROOT = DEV.parent
LOCAL = DEV / ".local"
PROJECT = "haruka-local"
PORTS = (15432, 16379, 19092, 19100, 19101, 13100, 13000)
SERVICES = ("postgres", "redis", "kafka", "minio", "socket-proxy", "loki", "alloy", "grafana")
COMPOSE_VARIABLES = frozenset(
    {
        "POSTGRES_IMAGE",
        "REDIS_IMAGE",
        "KAFKA_IMAGE",
        "MINIO_IMAGE",
        "MINIO_MC_IMAGE",
        "SOCKET_PROXY_IMAGE",
        "LOKI_IMAGE",
        "ALLOY_IMAGE",
        "GRAFANA_IMAGE",
        "KAFKA_CLUSTER_ID",
    }
)
SECRET_NAMES = (
    "postgres_password",
    "redis_password",
    "minio_password",
    "grafana_password",
    "dev_database_password",
    "test_database_password",
    "dev_maintenance_password",
    "test_maintenance_password",
    "dev_s3_secret",
    "test_s3_secret",
)


class InfraError(Exception):
    """Safe failure text; raw commands, server errors and credentials stay private."""


@dataclass(frozen=True)
class DockerTarget:
    """Pin the already validated engine selection across every subprocess."""

    arguments: tuple[str, str]


_docker_target: DockerTarget | None = None


def emit(message: str) -> None:
    sys.stdout.write(message + "\n")
    sys.stdout.flush()


def is_object(value: object) -> TypeGuard[dict[str, object]]:
    # All callers inspect json.loads output, whose object keys are strings.
    return isinstance(value, dict)


def read_object(path: Path) -> dict[str, object]:
    value: object = json.loads(path.read_text(encoding="utf-8"))
    if not is_object(value):
        raise InfraError("Expected a JSON object in local configuration.")
    return value


def write_once(path: Path, contents: str) -> None:
    """Create missing local files, and reject edits instead of overwriting them."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_text(encoding="utf-8") != contents:
            raise InfraError(
                f"Local configuration differs: {path.relative_to(DEV)}; kept unchanged."
            )
        return
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        stream.write(contents)


def command(arguments: Sequence[str], *, stdin: str | None = None, timeout: int = 180) -> str:
    executable = shutil.which("docker")
    if executable is None:
        raise InfraError("Docker CLI was not found.")
    target_arguments = _docker_target.arguments if _docker_target else ()
    # Compose's shell environment otherwise overrides --env-file image and cluster locks.
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in COMPOSE_VARIABLES and not key.startswith("COMPOSE_")
    }
    if _docker_target:
        environment.pop("DOCKER_HOST", None)
        environment.pop("DOCKER_CONTEXT", None)
    try:
        # Fixed executable and argument arrays; never invoke a shell or print secret-bearing errors.
        result = subprocess.run(  # noqa: S603
            [executable, *target_arguments, *arguments],
            cwd=DEV,
            input=stdin,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
            env=environment,
        )
    except subprocess.TimeoutExpired as error:
        raise InfraError("Docker operation timed out; inspect the Haruka service state.") from error
    if result.returncode:
        raise InfraError("Docker operation failed; inspect only haruka-local service logs locally.")
    return result.stdout


def compose(*arguments: str, stdin: str | None = None, timeout: int = 180) -> str:
    return command(
        [
            "compose",
            "--project-name",
            PROJECT,
            "--project-directory",
            str(DEV),
            "--env-file",
            str(LOCAL / "compose.env"),
            "--file",
            str(DEV / "compose.yaml"),
            *arguments,
        ],
        stdin=stdin,
        timeout=timeout,
    )


def local_docker_guard() -> None:
    """Refuse remote engines and another checkout's identically named project."""
    global _docker_target
    if _docker_target is None:
        selected_context = os.environ.get("DOCKER_CONTEXT")
        selected_host = os.environ.get("DOCKER_HOST")
        if selected_context or not selected_host:
            selected_context = selected_context or command(["context", "show"]).strip()
            endpoint = command(
                ["context", "inspect", selected_context, "--format", "{{.Endpoints.docker.Host}}"]
            ).strip()
            arguments = ("--context", selected_context)
        else:
            endpoint = selected_host
            arguments = ("--host", selected_host)
        parsed = urlsplit(endpoint)
        if not (
            endpoint.startswith(("npipe:////./pipe/", "unix:///"))
            or (parsed.scheme == "tcp" and parsed.hostname in {"localhost", "127.0.0.1", "::1"})
        ):
            raise InfraError("Development infrastructure requires a local Docker engine.")
        _docker_target = DockerTarget(arguments)
    records = command(
        [
            "ps",
            "-a",
            "--filter",
            f"label=com.docker.compose.project={PROJECT}",
            "--format",
            '{{.Label "com.docker.compose.project.working_dir"}}',
        ]
    )
    for workdir in records.splitlines():
        if not workdir or Path(workdir).resolve() != DEV:
            raise InfraError(
                "The haruka-local project belongs to another checkout; no changes made."
            )


def image_environment() -> dict[str, str]:
    manifest = read_object(ROOT / "tools" / "toolchain.json")
    images = manifest.get("development_images")
    if not is_object(images):
        raise InfraError("Development image locks are missing.")
    result: dict[str, str] = {}
    for name, value in images.items():
        if (
            not isinstance(value, str)
            or not re.fullmatch(r"[a-z0-9./_-]+:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}", value)
            or ":latest@" in value
        ):
            raise InfraError("Each development image requires a release tag and immutable digest.")
        result[f"{name.upper()}_IMAGE"] = value
    return result


def credentials() -> dict[str, str]:
    path = LOCAL / "credentials.json"
    if not path.exists():
        local_docker_guard()
        if command(
            ["volume", "ls", "--filter", f"label=com.docker.compose.project={PROJECT}", "-q"]
        ).strip():
            raise InfraError("Existing Haruka volumes require their original .local credentials.")
        generated = {name: secrets.token_hex(24) for name in SECRET_NAMES}
        generated["kafka_cluster_id"] = (
            base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("=")
        )
        write_once(path, json.dumps(generated, indent=2) + "\n")
    data = read_object(path)
    result: dict[str, str] = {}
    for name in (*SECRET_NAMES, "kafka_cluster_id"):
        value = data.get(name)
        pattern = r"[A-Za-z0-9_-]{22}" if name == "kafka_cluster_id" else r"[a-f0-9]{48}"
        if not isinstance(value, str) or not re.fullmatch(pattern, value):
            raise InfraError("Local credential manifest is invalid; it was not replaced.")
        result[name] = value
    return result


def initialize() -> dict[str, str]:
    values = credentials()
    image_vars = image_environment()
    image_vars["KAFKA_CLUSTER_ID"] = values["kafka_cluster_id"]
    write_once(
        LOCAL / "compose.env", "".join(f"{key}={value}\n" for key, value in image_vars.items())
    )
    for name in SECRET_NAMES[:4]:
        write_once(LOCAL / "secrets" / name, values[name] + "\n")
    write_once(
        LOCAL / "redis.conf",
        "\n".join(
            [
                "bind 0.0.0.0",
                "protected-mode yes",
                "appendonly yes",
                "dir /data",
                f"requirepass {values['redis_password']}",
                "save 60 1",
                "",
            ]
        ),
    )
    write_once(LOCAL / "minio" / "root_password", values["minio_password"] + "\n")
    (LOCAL / "logs").mkdir(exist_ok=True)
    for environment in ("dev", "test"):
        namespace = "haruka-local-dev" if environment == "dev" else "haruka-test-integration"
        access_key = f"haruka_{environment}_app"
        database = f"haruka_{environment}"
        runtime_user = f"haruka_{environment}_runtime"
        maintenance_user = f"haruka_{environment}_maintenance"
        fields = {
            "HARUKA_APP_ENV": environment,
            "HARUKA_INSTANCE_ID": namespace,
            "HARUKA_PUBLIC_BASE_URL": "http://127.0.0.1:8000",
            "HARUKA_ALLOWED_ORIGINS": '["http://localhost:5173","http://127.0.0.1:5173"]',
            "HARUKA_RELEASE": "0.1.0",
            "HARUKA_INFRASTRUCTURE_ENABLED": "true",
            "HARUKA_DATABASE_URL": f"postgresql+asyncpg://{runtime_user}:{values[f'{environment}_database_password']}@127.0.0.1:15432/{database}",
            "HARUKA_REDIS_URL": f"redis://:{values['redis_password']}@127.0.0.1:16379/{0 if environment == 'dev' else 1}",
            "HARUKA_RESOURCE_NAMESPACE": namespace,
            "HARUKA_KAFKA_BOOTSTRAP_SERVERS": "127.0.0.1:19092",
            "HARUKA_S3_ENDPOINT": "http://127.0.0.1:19100",
            "HARUKA_S3_ACCESS_KEY": access_key,
            "HARUKA_S3_SECRET_KEY": values[f"{environment}_s3_secret"],
            "HARUKA_S3_BUCKET": namespace,
            "HARUKA_LOG_FILE": (LOCAL / "logs" / f"{environment}.jsonl").as_posix(),
        }
        filename = "backend.env" if environment == "dev" else "test.env"
        write_once(LOCAL / filename, "".join(f"{key}={value}\n" for key, value in fields.items()))
        write_once(
            LOCAL / f"{environment}-maintenance.env",
            f"HARUKA_DATABASE_URL=postgresql+asyncpg://{maintenance_user}:{values[f'{environment}_maintenance_password']}@127.0.0.1:15432/{database}\n",
        )
        write_once(LOCAL / "minio" / f"{environment}_access_key", access_key + "\n")
        write_once(
            LOCAL / "minio" / f"{environment}_secret_key", values[f"{environment}_s3_secret"] + "\n"
        )
        policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetBucketLocation",
                        "s3:ListBucket",
                        "s3:ListBucketMultipartUploads",
                    ],
                    "Resource": [f"arn:aws:s3:::{namespace}"],
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:AbortMultipartUpload",
                        "s3:ListMultipartUploadParts",
                    ],
                    "Resource": [f"arn:aws:s3:::{namespace}/*"],
                },
            ],
        }
        write_once(
            LOCAL / "minio" / f"{environment}-policy.json", json.dumps(policy, indent=2) + "\n"
        )
    emit("Local development configuration initialized (existing files preserved).")
    return values


def provision_postgres(values: Mapping[str, str]) -> None:
    for environment in ("dev", "test"):
        database = f"haruka_{environment}"
        runtime = f"{database}_runtime"
        maintenance = f"{database}_maintenance"
        # Identifiers are fixed above; credentials() accepts only 48 hexadecimal characters.
        sql = ["\\set ON_ERROR_STOP on"]
        for role, password in (
            (runtime, values[f"{environment}_database_password"]),
            (maintenance, values[f"{environment}_maintenance_password"]),
        ):
            sql.append(
                f"SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION', '{role}', '{password}') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='{role}') \\gexec"  # noqa: S608
            )
        sql += [
            f"SELECT 'CREATE DATABASE {database} OWNER {maintenance}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='{database}') \\gexec",  # noqa: S608
            f"REVOKE ALL ON DATABASE {database} FROM PUBLIC;",
            f"GRANT CONNECT ON DATABASE {database} TO {runtime};",
            f"ALTER ROLE {runtime} IN DATABASE {database} SET search_path = public;",
            f"ALTER ROLE {runtime} IN DATABASE {database} SET timezone = 'UTC';",
            f"\\connect {database}",
            "REVOKE CREATE ON SCHEMA public FROM PUBLIC;",
            f"REVOKE ALL ON SCHEMA public FROM {runtime};",
            f"GRANT USAGE ON SCHEMA public TO {runtime};",
            f"ALTER DEFAULT PRIVILEGES FOR ROLE {maintenance} IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO {runtime};",
            f"ALTER DEFAULT PRIVILEGES FOR ROLE {maintenance} IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO {runtime};",
        ]
        compose(
            "exec",
            "-T",
            "postgres",
            "psql",
            "-X",
            "-q",
            "-U",
            "haruka_bootstrap",
            "-d",
            "postgres",
            stdin="\n".join(sql) + "\n",
        )
    emit("PostgreSQL dev/test databases and separate runtime/maintenance roles provisioned.")


def provision() -> None:
    provision_postgres(credentials())
    compose("run", "--rm", "--no-deps", "minio-init")
    emit("MinIO private dev/test buckets and scoped application credentials provisioned.")
    for namespace in ("haruka-local-dev", "haruka-test-integration"):
        compose(
            "exec",
            "-T",
            "kafka",
            "/opt/kafka/bin/kafka-topics.sh",
            "--bootstrap-server",
            "kafka:9092",
            "--create",
            "--if-not-exists",
            "--topic",
            f"{namespace}.smoke",
            "--partitions",
            "1",
            "--replication-factor",
            "1",
            "--config",
            "retention.ms=3600000",
        )
    emit("Kafka dev/test smoke topics provisioned; automatic topic creation is disabled.")


def request_local(url: str) -> bytes:
    parsed = urlsplit(url)
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.port not in {13100, 13000, 19100}
    ):
        raise InfraError("Infrastructure HTTP checks must target the fixed loopback services.")
    # The URL is validated above and callers provide only fixed local service endpoints.
    with build_opener(ProxyHandler({})).open(url, timeout=4) as response:
        return response.read()


def loki_contains(query: str) -> bool:
    parameters = urlencode({"query": query, "limit": "1"})
    response: object = json.loads(
        request_local(f"http://127.0.0.1:13100/loki/api/v1/query_range?{parameters}")
    )
    if not is_object(response):
        return False
    data = response.get("data")
    return is_object(data) and bool(data.get("result"))


def smoke() -> None:
    """Check real services and normal file/container ingestion without business data."""
    result = compose(
        "exec",
        "-T",
        "postgres",
        "psql",
        "-X",
        "-qAt",
        "-U",
        "haruka_bootstrap",
        "-d",
        "haruka_dev",
        "-c",
        "SELECT 1",
    )
    if result.strip() != "1":
        raise InfraError("PostgreSQL did not return the expected probe result.")
    result = compose(
        "exec",
        "-T",
        "redis",
        "sh",
        "-c",
        'REDISCLI_AUTH="$(cat /run/secrets/redis_password)" redis-cli ping',
    )
    if result.strip() != "PONG":
        raise InfraError("Redis did not return the expected probe result.")
    for namespace in ("haruka-local-dev", "haruka-test-integration"):
        compose(
            "exec",
            "-T",
            "kafka",
            "/opt/kafka/bin/kafka-topics.sh",
            "--bootstrap-server",
            "kafka:9092",
            "--describe",
            "--topic",
            f"{namespace}.smoke",
        )
    request_local("http://127.0.0.1:19100/minio/health/ready")
    request_local("http://127.0.0.1:13000/api/health")
    marker = uuid.uuid4().hex
    event = {
        "event": "infrastructure.smoke",
        "level": "info",
        "service": "infra-smoke",
        "probe_id": marker,
    }
    with (LOCAL / "logs" / "infra.jsonl").open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(event) + "\n")
    with (LOCAL / "logs" / "test.infra-smoke.jsonl").open(
        "a", encoding="utf-8", newline="\n"
    ) as stream:
        stream.write(json.dumps(event) + "\n")
    deadline = time.monotonic() + 50
    while time.monotonic() < deadline:
        try:
            if all(
                loki_contains(
                    f'{{project="haruka",service="infra-smoke",environment="{environment}"}} |= "{marker}"'
                )
                for environment in ("dev", "test")
            ):
                break
        except (OSError, ValueError):
            pass
        time.sleep(2)
    else:
        raise InfraError(
            "Normal dev/test events did not reach their correct Loki streams within 50 seconds."
        )
    if not loki_contains('{project="haruka",service="postgres"}'):
        raise InfraError("PostgreSQL container logs have not reached Loki.")
    emit(
        "Infrastructure smoke passed: PostgreSQL, Redis, Kafka topics, MinIO, Grafana, dev/test file logs and container logs in Loki."
    )


def status() -> None:
    output = compose("ps", "--all", "--format", "{{.Service}} | {{.State}} | {{.Health}}")
    emit(output.strip() or "No Haruka development containers are running.")


@contextlib.contextmanager
def operation_lock() -> Generator[None]:
    LOCAL.mkdir(exist_ok=True)
    path = LOCAL / "operation.lock"
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as error:
        raise InfraError(
            "Another infrastructure operation is active; check .local/operation.lock."
        ) from error
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        path.unlink(missing_ok=True)


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, io.TextIOWrapper):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace", newline="\n")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("init", "up", "status", "down", "smoke"))
    action: str = parser.parse_args().action
    try:
        with operation_lock():
            local_docker_guard()
            if action == "init":
                initialize()
            elif action == "up":
                initialize()
                compose("config", "--quiet")
                existing = compose("ps", "--all", "-q").strip()
                if not existing:
                    for port in PORTS:
                        with socket.socket() as connection:
                            try:
                                connection.bind(("127.0.0.1", port))
                            except OSError as error:
                                raise InfraError(
                                    f"Development port {port} is occupied; no services were started."
                                ) from error
                emit("Starting the isolated haruka-local infrastructure stack...")
                compose("up", "-d", "--wait", "--wait-timeout", "180", *SERVICES, timeout=240)
                provision()
                smoke()
                status()
            elif action == "status":
                status()
            elif action == "smoke":
                smoke()
            elif action == "down":
                compose("down", "--timeout", "20")
                emit("Haruka development containers stopped; all data volumes were retained.")
    except (InfraError, OSError, ValueError) as error:
        message = (
            str(error)
            if isinstance(error, InfraError)
            else "Local infrastructure operation failed; configuration was preserved."
        )
        emit(message)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
