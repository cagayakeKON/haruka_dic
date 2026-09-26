"""Launch local Linux acceptance from committed source with explicit read-only config files."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

from json_boundary import obj

ROOT = Path(__file__).resolve().parents[2]


def validate_docker_context(name: str, endpoint: str) -> None:
    if name != "desktop-linux" or endpoint != "npipe:////./pipe/dockerDesktopLinuxEngine":
        raise ValueError("Linux acceptance requires the local Docker Desktop Linux engine")


def capture(command: list[str]) -> str:
    return subprocess.run(
        command, cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8"
    ).stdout.strip()


def mount(source: Path, target: str, *, readonly: bool = True) -> list[str]:
    if "," in str(source):
        raise ValueError("Docker bind paths cannot contain commas")
    return [
        "--mount",
        f"type=bind,source={source},target={target}" + (",readonly" if readonly else ""),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--image", required=True, help="immutable local image sha256 ID")
    parser.add_argument("--test-config", required=True, type=Path)
    parser.add_argument("--dev-config", required=True, type=Path)
    parser.add_argument("--maintenance-config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if any(
        os.environ.get(key)
        for key in ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH")
    ):
        raise ValueError("Docker environment overrides are not allowed for local acceptance")
    context = capture(["docker", "context", "show"])
    endpoint = obj(
        json.loads(
            capture(
                ["docker", "context", "inspect", context, "--format", "{{json .Endpoints.docker}}"]
            )
        )
    )
    validate_docker_context(context, str(endpoint.get("Host")))
    commit = capture(["git", "rev-parse", args.commit + "^{commit}"])
    if capture(["git", "rev-parse", "HEAD"]) != commit:
        raise ValueError("Select the current committed HEAD for a complete Git bundle")
    if not args.image.startswith("sha256:") or len(args.image) != 71:
        raise ValueError("Pin the local image by immutable sha256 ID")
    image = capture(
        [
            "docker",
            "--context",
            "desktop-linux",
            "image",
            "inspect",
            args.image,
            "--format",
            "{{.Id}}",
        ]
    )
    paths = [
        path.resolve(strict=True)
        for path in (args.test_config, args.dev_config, args.maintenance_config)
    ]
    if any(not path.is_file() for path in paths):
        raise ValueError("Each configuration must be an explicit regular file")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    bundle = output / "source.bundle"
    capture(["git", "bundle", "create", str(bundle), "HEAD"])
    metadata: dict[str, object] = {
        "commit": commit,
        "docker_context": context,
        "docker_endpoint": endpoint["Host"],
        "image_id": image,
        "bundle_sha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
        "source": "git bundle of committed HEAD; uncommitted files excluded",
        "remote_ci_executed": False,
    }
    (output / "host.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    command = [
        "docker",
        "--context",
        "desktop-linux",
        "run",
        "--rm",
        "--init",
        "--name",
        "haruka-ci-linux-" + uuid.uuid4().hex[:12],
        "--platform",
        "linux/amd64",
        "--cap-drop",
        "ALL",
        "--security-opt",
        "no-new-privileges:true",
    ]
    command += mount(bundle, "/input/source.bundle")
    for path, target in zip(
        paths, ("/input/test.env", "/input/dev.env", "/input/maintenance.env"), strict=True
    ):
        command += mount(path, target)
    command += mount(output, "/evidence", readonly=False)
    command += [
        image,
        "/bin/bash",
        "-euc",
        (
            "git clone --no-checkout /input/source.bundle /work/checkout; "
            'git -C /work/checkout checkout --detach "$1"; '
            'exec python /work/checkout/dev/ci/linux_runner.py --commit "$1"'
        ),
        "haruka-linux",
        commit,
    ]
    with (output / "container.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8"
        )
        if process.stdout is None:
            raise RuntimeError("Docker output unavailable")
        try:
            for line in process.stdout:
                log.write(line)
                log.flush()
                sys.stdout.write(line)
                sys.stdout.flush()
            code = process.wait()
        except BaseException:
            # Only stop the temporary container whose generated name we own.
            capture(
                [
                    "docker",
                    "--context",
                    "desktop-linux",
                    "stop",
                    "--time",
                    "30",
                    command[command.index("--name") + 1],
                ]
            )
            process.wait(timeout=40)
            raise
    metadata["exit_code"] = code
    (output / "host.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(code)


if __name__ == "__main__":
    main()
