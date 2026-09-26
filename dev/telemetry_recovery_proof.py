"""Prove one isolated client event survived an injected receiver 503.

Only UUIDs, fixed event names, trusted owner binding, and timestamps appear in
the report. The fault receipt stores no telemetry body or authentication data.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

from dev.infra import is_object
from dev.isolated_app_run import IsolatedRunError, read_ledger, run_root
from dev.local_api_fault_proxy import RUN_ID, canonical_uuid
from dev.observability_proof import (
    PROOF_ROOT,
    ProofError,
    read_isolated_local_lines,
    read_isolated_loki_lines,
)


class RecoveryProofError(Exception):
    """Failure without untrusted telemetry content."""


SERVER_BUSINESS_EVENTS = frozenset(
    {
        "auth.registration.accepted",
        "auth.email.verified",
        "auth.login.succeeded",
        "auth.login.rejected",
        "auth.login.action_required",
        "auth.session.revoked",
        "auth.password.changed",
        "auth.password.recovered",
        "auth.policy.updated",
        "auth.verification.request.accepted",
        "auth.recovery.request.accepted",
        "collection.saved",
        "mail.delivery.sent",
        "mail.delivery.retry_or_failed",
    }
)


def _time(value: object) -> datetime:
    if not isinstance(value, str):
        raise RecoveryProofError("proof timestamp is missing")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as error:
        raise RecoveryProofError("proof timestamp is invalid") from error
    if parsed.tzinfo is None:
        raise RecoveryProofError("proof timestamp lacks timezone")
    return parsed.astimezone(UTC)


def _events(lines: list[str], instance_id: str) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for line in lines:
        try:
            document: object = json.loads(line)
        except ValueError:
            continue
        if is_object(document) and document.get("instance_id") == instance_id:
            result.append(document)
    return result


def failed_upload_receipt(
    root: Path, run_id: str, rule_id: str, event_id: str, *, audience: str
) -> dict[str, object]:
    matches: list[dict[str, object]] = []
    paths = list(root.glob("fault.receipt.*.json"))
    if len(paths) > 200:
        raise RecoveryProofError("fault receipts exceed the bounded proof input")
    for path in paths:
        if path.is_symlink() or path.resolve().parent != root:
            raise RecoveryProofError("fault receipt escaped the isolated run")
        try:
            document: object = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise RecoveryProofError("fault receipt is unreadable") from error
        if not is_object(document) or document.get("run_id") != run_id:
            raise RecoveryProofError("fault receipt has another run identity")
        ids = document.get("event_ids")
        if not isinstance(ids, list):
            continue
        if (
            document.get("rule_id") == rule_id
            and document.get("mode") == "before_503"
            and document.get("method") == "POST"
            and document.get("path")
            == (
                "/api/v1/frontend-logs"
                if audience == "client"
                else "/api/v1/admin/frontend-logs"
            )
            and document.get("injected") is True
            and document.get("upstream_status") is None
            and event_id in ids
        ):
            _time(document.get("at"))
            matches.append(document)
    if not matches:
        raise RecoveryProofError("target event has no injected 503 receipt")
    return min(matches, key=lambda item: _time(item["at"]))


def correlate(
    *,
    receipt: dict[str, object],
    event_id: str,
    expected_user_id: str,
    audience: str,
    local: list[dict[str, object]],
    loki: list[dict[str, object]],
) -> dict[str, object]:
    """Require the same event in the 503 batch and accepted local/Loki logs."""
    failed_at = _time(receipt.get("at"))
    ids = receipt.get("event_ids")
    if not isinstance(ids, list) or event_id not in ids:
        raise RecoveryProofError("target event was absent from the failed upload")
    local_matches = [
        item
        for item in local
        if item.get("event_id") == event_id
        and item.get("origin") == "client"
        and item.get("user_id") == expected_user_id
        and item.get("audience") == audience
    ]
    loki_matches = [
        item
        for item in loki
        if item.get("event_id") == event_id
        and item.get("origin") == "client"
        and item.get("user_id") == expected_user_id
        and item.get("audience") == audience
    ]
    if len(local_matches) != 1 or len(loki_matches) != 1:
        raise RecoveryProofError("same bound client event is absent or repeated")
    accepted = local_matches[0]
    indexed = loki_matches[0]
    fields = (
        "event",
        "operation_id",
        "user_id",
        "audience",
        "occurred_at",
        "received_at",
    )
    if any(accepted.get(field) != indexed.get(field) for field in fields):
        raise RecoveryProofError("local and Loki event bindings disagree")
    occurred = _time(accepted.get("occurred_at"))
    received = _time(accepted.get("received_at"))
    # The receipt's event ID proves the event was in the failed batch. The
    # client clock is not authoritative for ordering the subsequent receive.
    if not failed_at < received:
        raise RecoveryProofError("event timing does not prove recovery after 503")
    name = accepted.get("event")
    operation = accepted.get("operation_id")
    if (
        not isinstance(name, str)
        or canonical_uuid(operation if isinstance(operation, str) else None) is None
    ):
        raise RecoveryProofError(
            "accepted client event has no safe operation correlation"
        )
    business_matches = [
        item
        for item in local
        if item.get("origin") == "server"
        and item.get("event") in SERVER_BUSINESS_EVENTS
        and item.get("operation_id") == operation
        and item.get("user_id") == expected_user_id
        and item.get("audience") == audience
    ]
    if (
        name == "collection.saved"
        and audience == "client"
        and not any(
            item.get("event") == "collection.saved" for item in business_matches
        )
    ):
        raise RecoveryProofError(
            "saved collection lacks matching committed service event"
        )

    def chain_counts(events: list[dict[str, object]]) -> dict[str, int]:
        owned = [
            item
            for item in events
            if item.get("operation_id") == operation
            and item.get("user_id") == expected_user_id
            and item.get("audience") == audience
        ]
        return {
            "client": sum(
                item.get("event_id") == event_id and item.get("origin") == "client"
                for item in owned
            ),
            "http": sum(item.get("event") == "http.completed" for item in owned),
            "business": sum(
                item.get("event") in SERVER_BUSINESS_EVENTS
                and item.get("origin") == "server"
                for item in owned
            ),
            "database": sum(
                isinstance(item.get("event"), str)
                and str(item["event"]).startswith("database.")
                for item in owned
            ),
        }

    local_chain = chain_counts(local)
    loki_chain = chain_counts(loki)
    return {
        "event_id": event_id,
        "event": name,
        "operation_id": operation,
        "bound_user_id": expected_user_id,
        "bound_audience": audience,
        "failed_upload_at": failed_at.isoformat(),
        "client_occurred_at": occurred.isoformat(),
        "receiver_accepted_at": received.isoformat(),
        "same_event_in_local_and_loki": True,
        "matching_committed_business_events": len(business_matches),
        "operation_chain_local_counts": local_chain,
        "operation_chain_loki_counts": loki_chain,
        "operation_chain_complete": all(local_chain.values())
        and all(loki_chain.values()),
    }


def collect(
    run_id: str, rule_id: str, event_id: str, expected_user_id: str, *, audience: str
) -> dict[str, object]:
    root = run_root(run_id)
    ledger = read_ledger(root, run_id)
    if ledger["state"] not in {"serving", "stopped"}:
        raise RecoveryProofError("isolated run is unavailable")
    receipt = failed_upload_receipt(root, run_id, rule_id, event_id, audience=audience)
    local_lines, local_files = read_isolated_local_lines(run_id)
    instance_id = f"haruka-test-{run_id}"
    status, loki_lines, truncated = read_isolated_loki_lines(
        instance_id, start_utc=_time(receipt["at"]) - timedelta(minutes=2)
    )
    if status != 200 or truncated:
        raise RecoveryProofError("Loki proof is unavailable or truncated")
    summary = correlate(
        receipt=receipt,
        event_id=event_id,
        expected_user_id=expected_user_id,
        audience=audience,
        local=_events(local_lines, instance_id),
        loki=_events(loki_lines, instance_id),
    )
    return {
        "run_id": run_id,
        "rule_id": rule_id,
        "status": "passed_receiver_recovery",
        "scope": "one event in an injected 503 batch, later bound and accepted by the formal receiver, then present in Loki",
        "local_log_files": local_files,
        "loki_status": status,
        "loki_truncated": truncated,
        "event": summary,
        "checked_utc": datetime.now(UTC).isoformat(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--rule-id", required=True)
    parser.add_argument("--event-id", required=True)
    parser.add_argument("--expected-user-id", required=True)
    parser.add_argument("--audience", choices=("client", "admin"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if RUN_ID.fullmatch(args.rule_id) is None or UUID(args.rule_id).version != 4:
            raise RecoveryProofError("fault rule is not a canonical v4 hex UUID")
        for value in (args.event_id, args.expected_user_id):
            if canonical_uuid(value) != value or UUID(value).version != 4:
                raise RecoveryProofError("proof identity is not a canonical v4 UUID")
        output = args.output.resolve()
        if (
            output.parent != PROOF_ROOT.resolve()
            or output.exists()
            or output.is_symlink()
        ):
            raise RecoveryProofError("proof output must be a new artifact file")
        report = collect(
            args.run_id,
            args.rule_id,
            args.event_id,
            args.expected_user_id,
            audience=args.audience,
        )
        with output.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, sort_keys=True)
            stream.write("\n")
    except (IsolatedRunError, ProofError, RecoveryProofError, OSError) as error:
        print(
            f"receiver recovery proof failed: {type(error).__name__}", file=sys.stderr
        )
        return 1
    print("receiver recovery proof saved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
