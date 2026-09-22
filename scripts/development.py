"""Public configuration and endpoint checks for isolated development orchestration."""

from __future__ import annotations

import json
import os
import socket
import typing
from dataclasses import dataclass
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, build_opener


class DevelopmentError(Exception):
    """Safe diagnostic; private configuration values are never part of messages."""


def json_list(value: object) -> typing.TypeGuard[list[object]]:
    return isinstance(value, list)


@dataclass(frozen=True)
class DevelopmentConfig:
    path: Path
    environment: str
    namespace: str
    api_origin: str
    allowed_origins: tuple[str, ...]

    @property
    def api_port(self) -> int:
        port = urlsplit(self.api_origin).port
        if port is None:
            raise DevelopmentError("Development API origin requires an explicit port")
        return port


def read_public_config(path: Path) -> DevelopmentConfig:
    """Read the documented dotenv subset; the backend still validates the full schema.

    Inherited HARUKA_* overrides are rejected so validation and all child processes
    use the same explicit file instead of an accidentally inherited environment.
    """
    if not path.is_absolute() or not path.is_file():
        raise DevelopmentError("Use an existing absolute --config path")
    if any(key.startswith("HARUKA_") for key in os.environ):
        raise DevelopmentError(
            "Development orchestration requires an explicit file without inherited HARUKA_* overrides"
        )
    public_keys = {
        "HARUKA_APP_ENV",
        "HARUKA_INSTANCE_ID",
        "HARUKA_RESOURCE_NAMESPACE",
        "HARUKA_PUBLIC_BASE_URL",
        "HARUKA_ALLOWED_ORIGINS",
        "HARUKA_INFRASTRUCTURE_ENABLED",
    }
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, separator, value = stripped.partition("=")
        key = key.strip()
        if key not in public_keys:
            continue
        if not separator or key in values:
            raise DevelopmentError(
                "Public development configuration has duplicate or malformed keys"
            )
        value = value.strip()
        if value.startswith("'") and value.endswith("'"):
            value = value[1:-1]
        elif value.startswith('"') and value.endswith('"'):
            decoded: object = json.loads(value)
            if not isinstance(decoded, str):
                raise DevelopmentError("Invalid quoted public development value")
            value = decoded
        values[key] = value
    environment = values.get("HARUKA_APP_ENV", "")
    namespace = values.get("HARUKA_INSTANCE_ID", "")
    if environment not in {"dev", "test"} or namespace != (
        "haruka-local-dev" if environment == "dev" else "haruka-test-integration"
    ):
        raise DevelopmentError(
            "Development configuration must target the declared dev/test instance"
        )
    if (
        values.get("HARUKA_RESOURCE_NAMESPACE") != namespace
        or values.get("HARUKA_INFRASTRUCTURE_ENABLED", "").lower() != "true"
    ):
        raise DevelopmentError(
            "Development requires enabled isolated infrastructure with matching namespace"
        )
    origin = values.get("HARUKA_PUBLIC_BASE_URL", "")
    parsed = urlsplit(origin)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "localhost"}
        or parsed.port is None
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise DevelopmentError("Development API origin must use an explicit loopback HTTP port")
    raw_origins: object = json.loads(values.get("HARUKA_ALLOWED_ORIGINS", "[]"))
    if not json_list(raw_origins):
        raise DevelopmentError("Allowed origins must be a JSON list")
    origins: list[str] = []
    for item in raw_origins:
        if not isinstance(item, str):
            raise DevelopmentError("Allowed origins must contain strings")
        origins.append(item)
    return DevelopmentConfig(
        path.resolve(), environment, namespace, origin.rstrip("/"), tuple(origins)
    )


def require_free_port(port: int) -> None:
    """Probe service-compatible binding without terminating or sharing port holders."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as candidate:
            if os.name == "nt":
                candidate.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            else:
                # Match service rebinding after orderly shutdown. SO_REUSEADDR
                # permits TIME_WAIT reuse, but never shares an active listener.
                candidate.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            candidate.bind(("127.0.0.1", port))
            if os.name != "nt":
                # A bind alone can coexist with another reusable unlistened bind;
                # listen exercises the same exclusivity boundary as the service.
                candidate.listen(1)
    except OSError as error:
        if isinstance(error, PermissionError):
            raise DevelopmentError(
                f"Loopback port {port} is denied or reserved by the OS; choose another declared target without changing system exclusions"
            ) from error
        raise DevelopmentError(
            f"Loopback port {port} is occupied or unavailable; stop its owner explicitly or use another declared target"
        ) from error


def endpoint_ready(origin: str, path: str) -> bool:
    """A loopback health probe bypasses proxies and never transmits credentials."""
    parsed = urlsplit(origin)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise DevelopmentError("Health probes require a loopback HTTP origin")
    opener = build_opener(ProxyHandler({}))
    try:
        with opener.open(origin + path, timeout=1) as response:
            return response.status == 200
    except (OSError, URLError):
        return False
