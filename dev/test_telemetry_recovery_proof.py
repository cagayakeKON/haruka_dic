"""Direct correlation boundaries for a receiver outage proof."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

from dev.telemetry_recovery_proof import (
    RecoveryProofError,
    correlate,
    failed_upload_receipt,
)


class TelemetryRecoveryProofChecks(unittest.TestCase):
    def test_same_event_recovers_with_bound_owner_and_business_operation(self) -> None:
        event_id = str(uuid4())
        user_id = str(uuid4())
        operation_id = str(uuid4())
        receipt: dict[str, object] = {
            "at": "2026-09-26T10:00:00+00:00",
            "event_ids": [event_id],
        }
        client: dict[str, object] = {
            "event_id": event_id,
            "event": "collection.saved",
            "origin": "client",
            "operation_id": operation_id,
            "user_id": user_id,
            "audience": "client",
            "occurred_at": "2026-09-26T09:59:59+00:00",
            "received_at": "2026-09-26T10:00:02+00:00",
        }
        committed: dict[str, object] = {
            "event": "collection.saved",
            "origin": "server",
            "operation_id": operation_id,
            "user_id": user_id,
            "audience": "client",
        }
        http: dict[str, object] = {
            "event": "http.completed",
            "operation_id": operation_id,
            "user_id": user_id,
            "audience": "client",
        }
        database: dict[str, object] = {
            "event": "database.query.completed",
            "operation_id": operation_id,
            "user_id": user_id,
            "audience": "client",
        }
        summary = correlate(
            receipt=receipt,
            event_id=event_id,
            expected_user_id=user_id,
            audience="client",
            local=[client, committed, http, database],
            loki=[client, committed, http, database],
        )
        self.assertTrue(summary["same_event_in_local_and_loki"])
        self.assertEqual(summary["matching_committed_business_events"], 1)
        self.assertTrue(summary["operation_chain_complete"])
        partial = correlate(
            receipt=receipt,
            event_id=event_id,
            expected_user_id=user_id,
            audience="client",
            local=[client, committed, http, database],
            loki=[client],
        )
        self.assertFalse(partial["operation_chain_complete"])
        skewed_client = {**client, "occurred_at": "2026-09-26T10:00:30+00:00"}
        self.assertTrue(
            correlate(
                receipt=receipt,
                event_id=event_id,
                expected_user_id=user_id,
                audience="client",
                local=[skewed_client, committed, http, database],
                loki=[skewed_client, committed, http, database],
            )["same_event_in_local_and_loki"]
        )
        for changed in (
            {**receipt, "event_ids": [str(uuid4())]},
            {**receipt, "at": "2026-09-26T10:00:03+00:00"},
        ):
            with self.assertRaises(RecoveryProofError):
                correlate(
                    receipt=changed,
                    event_id=event_id,
                    expected_user_id=user_id,
                    audience="client",
                    local=[client, committed, http, database],
                    loki=[client],
                )
        with self.assertRaises(RecoveryProofError):
            correlate(
                receipt=receipt,
                event_id=event_id,
                expected_user_id=str(uuid4()),
                audience="client",
                local=[client, committed, http, database],
                loki=[client],
            )
        with self.assertRaises(RecoveryProofError):
            correlate(
                receipt=receipt,
                event_id=event_id,
                expected_user_id=user_id,
                audience="client",
                local=[client, committed, http, database],
                loki=[],
            )
        with self.assertRaises(RecoveryProofError):
            correlate(
                receipt=receipt,
                event_id=event_id,
                expected_user_id=user_id,
                audience="client",
                local=[client],
                loki=[client],
            )
        admin_event = {**client, "event": "auth.policy.updated", "audience": "admin"}
        self.assertEqual(
            correlate(
                receipt=receipt,
                event_id=event_id,
                expected_user_id=user_id,
                audience="admin",
                local=[admin_event],
                loki=[admin_event],
            )["bound_audience"],
            "admin",
        )

    def test_receipt_must_contain_exact_injected_event_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run_id = uuid4().hex
            rule_id = uuid4().hex
            event_id = str(uuid4())
            other_event = str(uuid4())
            (root / "fault.receipt.one.json").write_text(
                "{"
                f'"run_id":"{run_id}","rule_id":"{rule_id}",'
                '"mode":"before_503","method":"POST",'
                '"path":"/api/v1/frontend-logs","injected":true,'
                '"upstream_status":null,"at":"2026-09-26T10:00:00+00:00",'
                f'"event_ids":["{event_id}"]'
                "}",
                encoding="utf-8",
            )
            self.assertEqual(
                failed_upload_receipt(
                    root, run_id, rule_id, event_id, audience="client"
                )["event_ids"],
                [event_id],
            )
            with self.assertRaises(RecoveryProofError):
                failed_upload_receipt(
                    root, run_id, rule_id, other_event, audience="client"
                )
            with self.assertRaises(RecoveryProofError):
                failed_upload_receipt(root, run_id, rule_id, event_id, audience="admin")
            (root / "fault.receipt.two.json").write_text(
                "{"
                f'"run_id":"{run_id}","rule_id":"{rule_id}",'
                '"mode":"before_503","method":"POST",'
                '"path":"/api/v1/admin/frontend-logs","injected":true,'
                '"upstream_status":null,"at":"2026-09-26T10:01:00+00:00",'
                f'"event_ids":["{event_id}"]'
                "}",
                encoding="utf-8",
            )
            self.assertEqual(
                failed_upload_receipt(
                    root, run_id, rule_id, event_id, audience="admin"
                )["path"],
                "/api/v1/admin/frontend-logs",
            )


if __name__ == "__main__":
    unittest.main()
