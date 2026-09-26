"""Prove durable mail retry and worker restart in a private PostgreSQL run.

The registration goes through the formal ASGI routes. The SMTP endpoint is an
ephemeral loopback capture owned by this probe; no message reaches an external
relay. The report contains only statuses, counts, and safe fixed event names.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import socket
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx2 as httpx
from app.bootstrap import bootstrap
from app.core.settings import Settings, load_settings
from app.main import create_app
from app.models import AuthChallengeDelivery, User
from sqlalchemy import select

from dev.infra import is_object
from dev.isolated_app_run import cleanup, prepare, run_root, write_private
from dev.local_smtp_capture import message_link, serve_client
from dev.observability_proof import LOG_ROOT, PROOF_ROOT

ROOT = Path(__file__).resolve().parent.parent
PYTHON = ROOT / "backend/.venv/Scripts/python.exe"
ORIGIN = "https://localhost:18443"


class MailProbeError(Exception):
    """Safe failure without SMTP payload or credential details."""


def _unused_loopback_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _worker_config(root: Path, port: int) -> Path:
    source = root / "runtime.env"
    lines = source.read_text(encoding="utf-8").splitlines()
    old = [line for line in lines if line.startswith("HARUKA_SMTP_PORT=")]
    if len(old) != 1 or not 1 <= port <= 65535:
        raise MailProbeError("isolated SMTP configuration is invalid")
    updated = [
        f"HARUKA_SMTP_PORT={port}" if line.startswith("HARUKA_SMTP_PORT=") else line
        for line in lines
    ]
    destination = root / "mail-probe.env"
    write_private(destination, "\n".join(updated) + "\n")
    return destination


async def _worker_once(config: Path) -> dict[str, object]:
    if not PYTHON.is_file() or any(key.startswith("HARUKA_") for key in os.environ):
        raise MailProbeError("worker environment is not isolated")
    process = await asyncio.create_subprocess_exec(
        str(PYTHON),
        "-m",
        "app.cli.mail",
        "--config",
        str(config),
        "--once",
        cwd=ROOT / "backend",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=40)
    except TimeoutError:
        process.kill()
        await process.communicate()
        raise MailProbeError("mail worker exceeded its bounded run") from None
    if process.returncode != 0:
        raise MailProbeError(f"formal mail worker exited {process.returncode}")
    if stderr:
        raise MailProbeError(f"formal mail worker emitted {len(stderr)} stderr bytes")
    if len(stdout) > 2_000_000:
        raise MailProbeError("formal mail worker output exceeded its bound")
    readiness = 0
    for line in stdout.splitlines():
        try:
            document: object = json.loads(line)
        except ValueError as error:
            raise MailProbeError("mail worker output was not structured") from error
        if document == {"mail_worker_ready": True}:
            readiness += 1
            continue
        if not is_object(document) or not isinstance(document.get("event"), str):
            raise MailProbeError("mail worker output contained an unknown record")
    if readiness != 1:
        raise MailProbeError("mail worker readiness was not confirmed")
    return {"exit_code": process.returncode, "ready": True, "pid": process.pid}


async def _delivery(runtime_settings: Settings, email: str) -> dict[str, object]:
    async with bootstrap(runtime_settings) as runtime:
        if runtime.resources is None:
            raise MailProbeError("isolated PostgreSQL resources are unavailable")
        async with runtime.resources.database.sessions() as session:
            user = await session.scalar(
                select(User).where(User.email_normalized == email)
            )
            if user is None:
                raise MailProbeError("registered synthetic account was not persisted")
            rows = (
                await session.scalars(
                    select(AuthChallengeDelivery).where(
                        AuthChallengeDelivery.user_id == user.id
                    )
                )
            ).all()
            if len(rows) != 1:
                raise MailProbeError("expected one durable mail delivery")
            row = rows[0]
            return {
                "status": row.status,
                "attempt_count": row.attempt_count,
                "last_error_code": row.last_error_code,
                "envelope_erased": row.encrypted_payload is None,
                "lease_cleared": row.lease_owner is None and row.lease_until is None,
                "next_attempt_at": row.next_attempt_at,
            }


async def _register(settings: Settings, root: Path, run_id: str) -> str:
    async with bootstrap(settings) as runtime:
        app = create_app(settings)
        app.state.runtime = runtime
        headers = {"Origin": ORIGIN, "Content-Type": "application/json"}
        admin_password = (root / "admin.secret").read_text(encoding="utf-8").strip()
        email = f"mail-probe-{run_id}@haruka.example.test"
        password = "Aa9" + secrets.token_urlsafe(36)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url=ORIGIN
        ) as client:
            login = await client.post(
                "/api/v1/admin/auth/login",
                json={
                    "email": f"admin-{run_id}@haruka.example.test",
                    "password": admin_password,
                },
                headers=headers,
            )
            if login.status_code != 200:
                raise MailProbeError("formal administrator login failed")
            csrf = await client.get("/api/v1/admin/auth/csrf")
            policy = await client.get("/api/v1/admin/auth-policy")
            if csrf.status_code != 200 or policy.status_code != 200:
                raise MailProbeError("formal policy read failed")
            token = csrf.json()["data"]["csrf_token"]
            revision = policy.json()["data"]["revision"]
            opened = await client.patch(
                "/api/v1/admin/auth-policy",
                json={"registration_mode": "open", "expected_revision": revision},
                headers={**headers, "X-CSRF-Token": token},
            )
            if opened.status_code != 200:
                raise MailProbeError("formal registration policy update failed")
            registered = await client.post(
                "/api/v1/auth/register",
                json={"email": email, "password": password},
                headers=headers,
            )
            if registered.status_code != 202:
                raise MailProbeError("formal registration acceptance failed")
        return email


def _captured_message_count(spool: Path, recipient: str) -> tuple[int, bool]:
    metadata = sorted(spool.glob("*.json"))
    if len(metadata) > 2:
        raise MailProbeError("isolated SMTP capture exceeded the expected count")
    recognized = False
    for path in metadata:
        if path.is_symlink() or path.resolve().parent != spool:
            raise MailProbeError("captured message escaped the private spool")
        document: object = json.loads(path.read_text(encoding="utf-8"))
        if not is_object(document) or document.get("recipient") != recipient:
            raise MailProbeError("SMTP capture recipient did not match this run")
        recognized = (
            message_link(path.with_suffix(".eml").read_bytes(), "verify") is not None
        )
    return len(metadata), recognized


def _mail_events(run_id: str) -> dict[str, int]:
    files = sorted(LOG_ROOT.glob(f"test.isolated.{run_id}.mail.*.jsonl"))
    counts: dict[str, int] = {}
    for path in files:
        if path.is_symlink() or path.resolve().parent != LOG_ROOT.resolve():
            raise MailProbeError("worker log escaped the isolated log directory")
        for line in path.read_text(encoding="utf-8").splitlines():
            document: object = json.loads(line)
            if (
                not is_object(document)
                or document.get("instance_id") != f"haruka-test-{run_id}"
            ):
                raise MailProbeError("worker log has another instance")
            name = document.get("event")
            if name in {"mail.delivery.retry_or_failed", "mail.delivery.sent"}:
                assert isinstance(name, str)
                counts[name] = counts.get(name, 0) + 1
    return counts


async def probe() -> dict[str, object]:
    run_id = await prepare()
    root = run_root(run_id)
    config: Path | None = None
    server: asyncio.AbstractServer | None = None
    report: dict[str, object] = {"run_id": run_id, "status": "failed"}
    stage = "configure"
    try:
        spool = root / "mail"
        port = _unused_loopback_port()
        config = _worker_config(root, port)
        settings = load_settings(config)
        if (
            settings.app_env != "test"
            or settings.instance_id != f"haruka-test-{run_id}"
            or settings.smtp_host != "127.0.0.1"
            or settings.smtp_port != port
            or settings.test_schema != f"haruka_migration_test_{run_id}"
        ):
            raise MailProbeError("worker runtime escaped this isolated run")
        stage = "register"
        email = await _register(settings, root, run_id)
        stage = "pending_delivery"
        before = await _delivery(settings, email)
        if before["status"] != "pending" or before["attempt_count"] != 0:
            raise MailProbeError(
                "formal registration did not persist a pending delivery"
            )
        stage = "first_worker"
        first = await _worker_once(config)
        stage = "failed_delivery"
        failed = await _delivery(settings, email)
        if (
            failed["status"] != "pending"
            or failed["attempt_count"] != 1
            or failed["last_error_code"] != "smtp_result_unknown"
            or not failed["lease_cleared"]
            or failed["envelope_erased"]
        ):
            raise MailProbeError("SMTP failure was not durably classified for retry")
        next_attempt = failed["next_attempt_at"]
        if not isinstance(next_attempt, datetime) or next_attempt.tzinfo is None:
            raise MailProbeError("SMTP retry time was not persisted")
        server = await asyncio.start_server(
            lambda reader, writer: serve_client(reader, writer, spool),
            host="127.0.0.1",
            port=port,
        )
        delay = max(0.0, (next_attempt - datetime.now(UTC)).total_seconds())
        if delay > 30.0:
            raise MailProbeError("persisted retry window exceeds probe support")
        await asyncio.sleep(delay + 0.2)
        stage = "second_worker"
        second = await _worker_once(config)
        stage = "sent_delivery"
        sent = await _delivery(settings, email)
        count, link_recognized = _captured_message_count(spool, email)
        if (
            sent["status"] != "sent"
            or sent["attempt_count"] != 2
            or sent["last_error_code"] is not None
            or not sent["envelope_erased"]
            or not sent["lease_cleared"]
            or count != 1
            or not link_recognized
        ):
            raise MailProbeError(
                "worker restart did not deliver one valid local message"
            )
        stage = "third_worker"
        third = await _worker_once(config)
        stage = "completed_delivery"
        after = await _delivery(settings, email)
        final_count, _ = _captured_message_count(spool, email)
        if after["attempt_count"] != 2 or after["status"] != "sent" or final_count != 1:
            raise MailProbeError("restarted worker duplicated a completed delivery")
        stage = "worker_events"
        events = _mail_events(run_id)
        if (
            events.get("mail.delivery.retry_or_failed") != 1
            or events.get("mail.delivery.sent") != 1
        ):
            raise MailProbeError("worker success and retry logs were not both observed")
        report = {
            "run_id": run_id,
            "status": "passed",
            "scope": "formal admin policy and registration HTTP, durable mail row, separate worker CLI processes, private loopback SMTP",
            "before": {
                "status": before["status"],
                "attempt_count": before["attempt_count"],
            },
            "after_first_worker": {
                "status": failed["status"],
                "attempt_count": failed["attempt_count"],
                "last_error_code": failed["last_error_code"],
                "lease_cleared": failed["lease_cleared"],
            },
            "after_restart": {
                "status": sent["status"],
                "attempt_count": sent["attempt_count"],
                "envelope_erased": sent["envelope_erased"],
                "lease_cleared": sent["lease_cleared"],
            },
            "worker_processes": [first, second, third],
            "worker_process_count": 3,
            "smtp_messages_captured": final_count,
            "verification_link_recognized": link_recognized,
            "worker_event_counts": events,
        }
    except Exception as error:  # noqa: BLE001 - report only safe stage and error class.
        report["failure_stage"] = stage
        report["failure_kind"] = (
            str(error) if isinstance(error, MailProbeError) else type(error).__name__
        )
    finally:
        if server is not None:
            server.close()
            await server.wait_closed()
        if config is not None:
            config.unlink(missing_ok=True)
        try:
            await cleanup(run_id)
        except Exception as error:  # noqa: BLE001 - no dependency exception text.
            report["status"] = "failed_cleanup"
            report["cleanup_failure_kind"] = type(error).__name__
            report["cleaned"] = False
            report["checked_utc"] = datetime.now(UTC).isoformat()
            return report
    report["cleaned"] = True
    report["checked_utc"] = datetime.now(UTC).isoformat()
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    destination = args.output.resolve()
    if (
        destination.parent != PROOF_ROOT.resolve()
        or destination.exists()
        or destination.is_symlink()
    ):
        print("mail probe requires a new safe report path", file=sys.stderr)
        return 2
    try:
        report = asyncio.run(probe())
        with destination.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, sort_keys=True)
            stream.write("\n")
    except Exception:  # noqa: BLE001 - no dependency exception may print SMTP content.
        print(
            "mail worker lifecycle probe failed; inspect isolated logs", file=sys.stderr
        )
        return 1
    if report["status"] != "passed":
        print("mail worker lifecycle failure report saved", file=sys.stderr)
        return 1
    print("mail worker lifecycle proof saved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
