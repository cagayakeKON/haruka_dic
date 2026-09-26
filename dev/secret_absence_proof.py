"""Check actual synthetic UI credentials and captured mail tokens against run logs.

The probe reads secrets only from ACL-restricted run files, keeps them in memory,
and writes counts and absence booleans. It never reports secret text or hashes.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from uuid import UUID

from dev.infra import is_object
from dev.isolated_app_run import IsolatedRunError, read_ledger, run_root
from dev.local_smtp_capture import (
    MAX_MESSAGE_BYTES,
    MailboxError,
    guarded_spool,
    message_link,
)
from dev.observability_proof import (
    PROOF_ROOT,
    ProofError,
    read_isolated_local_lines,
    read_isolated_loki_lines,
)


class SecretProofError(Exception):
    """Safe failure code without secret content or source body."""


def _actor_password(root: Path, actor_file: Path, run_id: str) -> bytes:
    if (
        not actor_file.is_file()
        or actor_file.is_symlink()
        or actor_file.resolve().parent != root
        or actor_file.stat().st_size > 4096
    ):
        raise SecretProofError("private actor file is unavailable or unowned")
    try:
        value: object = json.loads(actor_file.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SecretProofError("private actor file is invalid") from error
    if not is_object(value) or value.get("run_id") != run_id:
        raise SecretProofError("private actor identity differs from run")
    password = value.get("password")
    if (
        not isinstance(password, str)
        or not 12 <= len(password) <= 200
        or not password.isascii()
    ):
        raise SecretProofError("private actor password is invalid")
    return password.encode("ascii")


def _captured_tokens(root: Path) -> set[bytes]:
    spool = guarded_spool(root / "mail")
    if not spool.is_dir() or spool.is_symlink():
        raise SecretProofError("private captured mailbox is unavailable")
    messages = sorted(spool.glob("*.eml"))
    if not 1 <= len(messages) <= 100:
        raise SecretProofError("captured mail sample count is outside bound")
    tokens: set[bytes] = set()
    for path in messages:
        if (
            path.is_symlink()
            or path.resolve().parent != spool
            or path.stat().st_size > MAX_MESSAGE_BYTES
        ):
            raise SecretProofError(
                "captured mail sample escaped size or ownership bound"
            )
        payload = path.read_bytes()
        for purpose in ("verify", "reset"):
            link = message_link(payload, purpose)
            if link is None:
                continue
            for token in parse_qs(urlsplit(link).fragment).get("token", []):
                if 20 <= len(token) <= 1000:
                    tokens.add(token.encode("utf-8"))
    if not tokens:
        raise SecretProofError("captured mail has no action tokens")
    return tokens


def full_run_start(
    root: Path, local_lines: list[str], instance_id: str
) -> tuple[datetime, str, int]:
    """Start before creation and anchor the oldest instance-bound event.

    Windows exposes the directory birth time separately from last metadata
    change. Refuse platforms lacking that fact rather than silently querying
    only a recent slice of a long-lived run.
    """
    birth_time = getattr(root.stat(), "st_birthtime", None)
    if isinstance(birth_time, bool) or not isinstance(birth_time, (int, float)):
        raise SecretProofError("run creation time is unavailable")
    try:
        created = datetime.fromtimestamp(birth_time, UTC)
    except (OverflowError, OSError, ValueError) as error:
        raise SecretProofError("run creation time is invalid") from error
    now = datetime.now(UTC)
    if created > now or created.year < 2020:
        raise SecretProofError("run creation time is outside proof bounds")
    oldest: tuple[datetime, str] | None = None
    unbound_count = 0
    for line in local_lines:
        try:
            document: object = json.loads(line)
        except ValueError:
            continue
        if not is_object(document):
            continue
        if document.get("instance_id") != instance_id:
            unbound_count += 1
            continue
        occurred_at = document.get("occurred_at")
        event_id = document.get("event_id")
        if not isinstance(occurred_at, str) or not isinstance(event_id, str):
            continue
        try:
            occurred = datetime.fromisoformat(occurred_at)
            event = UUID(event_id)
        except ValueError:
            continue
        if occurred.tzinfo is None or str(event) != event_id:
            continue
        if oldest is None or occurred < oldest[0]:
            oldest = (occurred, event_id)
    if oldest is None:
        raise SecretProofError("run has no timestamped local event anchor")
    if oldest[0] > now:
        raise SecretProofError("local event anchor is in the future")
    return min(created, oldest[0]) - timedelta(minutes=2), oldest[1], unbound_count


def loki_has_event(lines: list[str], event_id: str) -> bool:
    for line in lines:
        try:
            document: object = json.loads(line)
        except ValueError:
            continue
        if is_object(document) and document.get("event_id") == event_id:
            return True
    return False


def collect(run_id: str, actor_file: Path) -> dict[str, object]:
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] not in {"serving", "stopped"}:
        raise SecretProofError("isolated run is not available for log inspection")
    password = _actor_password(root, actor_file, run_id)
    tokens = _captured_tokens(root)
    local_lines, file_count = read_isolated_local_lines(run_id)
    instance_id = f"haruka-test-{run_id}"
    start_utc, anchor_event_id, unbound_count = full_run_start(
        root, local_lines, instance_id
    )
    status, loki_lines, truncated = read_isolated_loki_lines(
        instance_id, start_utc=start_utc
    )
    if status != 200 or truncated or not local_lines or not loki_lines:
        raise SecretProofError("run logs or Loki evidence is unavailable or truncated")
    if not loki_has_event(loki_lines, anchor_event_id):
        raise SecretProofError("oldest local event is missing from Loki proof window")
    local = "".join(local_lines).encode("utf-8")
    loki = "".join(loki_lines).encode("utf-8")
    sources = {"latest_actor_password": (password,), "mail_action_token": tuple(tokens)}
    checks: dict[str, dict[str, object]] = {}
    for kind, values in sources.items():
        checks[kind] = {
            "sample_count": len(values),
            "absent_local": all(value not in local for value in values),
            "absent_loki": all(value not in loki for value in values),
        }
    passed = all(
        result["absent_local"] is True and result["absent_loki"] is True
        for result in checks.values()
    )
    return {
        "run_id": run_id,
        "status": "passed" if passed else "failed",
        "scope": "current synthetic actor password and captured mail action tokens in all run app JSONL and instance-bound Loki records",
        "loki_from_utc": start_utc.isoformat(),
        "oldest_instance_bound_local_event_present_in_loki": True,
        "local_lines_without_instance_id": unbound_count,
        "local_log_files": file_count,
        "local_lines": len(local_lines),
        "loki_lines": len(loki_lines),
        "loki_status": status,
        "loki_truncated": truncated,
        "checks": checks,
        "checked_utc": datetime.now(UTC).isoformat(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--actor-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        root = run_root(args.run_id)
        if args.actor_file.is_symlink():
            raise SecretProofError("private actor file is linked")
        actor_file = args.actor_file.resolve()
        output = args.output.resolve()
        if (
            actor_file.parent != root
            or output.parent != PROOF_ROOT.resolve()
            or output.exists()
            or output.is_symlink()
        ):
            raise SecretProofError("secret proof paths must be owned and new")
        report = collect(args.run_id, actor_file)
        with output.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(output)
        return 0 if report["status"] == "passed" else 1
    except (
        OSError,
        ValueError,
        SecretProofError,
        ProofError,
        IsolatedRunError,
        MailboxError,
    ):
        print("actual synthetic secret absence proof failed safely", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
