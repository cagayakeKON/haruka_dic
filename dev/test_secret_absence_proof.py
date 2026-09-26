"""Bounded evidence checks for long-lived isolated runs."""

from __future__ import annotations

import json
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlsplit
from uuid import UUID

from dev.observability_proof import (
    ProofError,
    read_isolated_local_lines,
    read_isolated_loki_lines,
)
from dev.secret_absence_proof import SecretProofError, full_run_start, loki_has_event


class SecretAbsenceWindowChecks(unittest.TestCase):
    def test_run_older_than_six_hours_queries_from_creation(self) -> None:
        now = datetime.now(UTC)
        created = now - timedelta(hours=9)
        oldest = created + timedelta(minutes=3)
        event_id = str(UUID(int=1))
        root = Mock(spec=Path)
        root.stat.return_value = SimpleNamespace(st_birthtime=created.timestamp())
        instance_id = "haruka-test-" + "a" * 32
        local = [
            json.dumps(
                {
                    "occurred_at": oldest.isoformat(),
                    "event_id": event_id,
                    "instance_id": instance_id,
                }
            )
        ]

        start, anchor, unbound = full_run_start(root, local, instance_id)

        self.assertLess(start, created)
        self.assertLess(start, now - timedelta(hours=6))
        self.assertEqual(anchor, event_id)
        self.assertEqual(unbound, 0)

    def test_unbound_startup_events_do_not_break_instance_anchor(self) -> None:
        now = datetime.now(UTC)
        root = Mock(spec=Path)
        root.stat.return_value = SimpleNamespace(
            st_birthtime=(now - timedelta(hours=1)).timestamp()
        )
        instance_id = "haruka-test-" + "a" * 32
        event_id = str(UUID(int=1))
        local = [
            json.dumps({"event_id": str(UUID(int=2)), "occurred_at": now.isoformat()}),
            json.dumps(
                {
                    "event_id": event_id,
                    "occurred_at": now.isoformat(),
                    "instance_id": instance_id,
                }
            ),
        ]
        _start, anchor, unbound = full_run_start(root, local, instance_id)
        self.assertEqual(anchor, event_id)
        self.assertEqual(unbound, 1)

    def test_oldest_event_must_be_present_in_loki_result(self) -> None:
        event_id = str(UUID(int=1))
        other = str(UUID(int=2))
        self.assertFalse(loki_has_event([json.dumps({"event_id": other})], event_id))
        self.assertTrue(loki_has_event([json.dumps({"event_id": event_id})], event_id))

    def test_loki_reader_uses_old_run_start_instead_of_recent_default(self) -> None:
        start = datetime.now(UTC) - timedelta(hours=9)
        response = json.dumps({"status": "success", "data": {"result": []}}).encode()
        with patch(
            "dev.observability_proof._request", return_value=(200, response)
        ) as request:
            status, lines, truncated = read_isolated_loki_lines(
                "haruka-test-" + "a" * 32, start_utc=start
            )
        url: object = request.call_args_list[0].args[0]
        self.assertIsInstance(url, str)
        assert isinstance(url, str)
        queried_start = int(parse_qs(urlsplit(url).query)["start"][0])
        self.assertEqual(status, 200)
        self.assertFalse(lines)
        self.assertFalse(truncated)
        self.assertGreater(len(request.call_args_list), 1)
        self.assertEqual(queried_start, int(start.timestamp() * 1_000_000_000))

    def test_full_loki_window_is_reported_truncated(self) -> None:
        start = datetime.now(UTC) - timedelta(minutes=1)
        rows = [[str(int(start.timestamp() * 1_000_000_000)), "{}"]] * 5000
        response = json.dumps(
            {"status": "success", "data": {"result": [{"values": rows}]}}
        ).encode()
        with patch("dev.observability_proof._request", return_value=(200, response)):
            status, lines, truncated = read_isolated_loki_lines(
                "haruka-test-" + "a" * 32, start_utc=start
            )
        self.assertEqual(status, 200)
        self.assertEqual(len(lines), 5000)
        self.assertTrue(truncated)

    def test_run_older_than_query_budget_fails_closed(self) -> None:
        with self.assertRaises(ProofError):
            read_isolated_loki_lines(
                "haruka-test-" + "a" * 32,
                start_utc=datetime.now(UTC) - timedelta(hours=25),
            )

    def test_missing_run_birth_time_fails_closed(self) -> None:
        root = Mock(spec=Path)
        root.stat.return_value = SimpleNamespace()
        with self.assertRaises(SecretProofError):
            full_run_start(root, [], "haruka-test-" + "a" * 32)

    def test_local_reader_accepts_exact_bounds_and_rejects_excess(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            local_root = Path(directory) / "runs"
            log_root = Path(directory) / "logs"
            run_id = "a" * 32
            run = local_root / run_id
            run.mkdir(parents=True)
            log_root.mkdir()
            (run / "runtime.env").write_text("placeholder", encoding="utf-8")
            base = log_root / f"test.{run_id}.jsonl"
            log = log_root / f"test.{run_id}.api.1.jsonl"
            settings = SimpleNamespace(
                instance_id=f"haruka-test-{run_id}", log_file=base
            )
            with (
                patch("dev.observability_proof.LOCAL_ROOT", local_root),
                patch("dev.observability_proof.LOG_ROOT", log_root),
                patch("dev.observability_proof.load_settings", return_value=settings),
                patch("dev.observability_proof.MAX_LINES", 2),
                patch("dev.observability_proof.MAX_TOTAL_BYTES", 6),
            ):
                log.write_text("ab\ncd\n", encoding="utf-8")
                self.assertEqual(read_isolated_local_lines(run_id)[0], ["ab\n", "cd\n"])
                log.write_text("abc\ncd\n", encoding="utf-8")
                with self.assertRaises(ProofError):
                    read_isolated_local_lines(run_id)
                log.write_text("a\nb\nc\n", encoding="utf-8")
                with self.assertRaises(ProofError):
                    read_isolated_local_lines(run_id)
                log.write_bytes(b"valid\n\xff\n")
                with self.assertRaises(ProofError):
                    read_isolated_local_lines(run_id)

    def test_loki_reader_accepts_exact_bounds_and_flags_excess(self) -> None:
        start = datetime.now(UTC) - timedelta(minutes=1)
        timestamp = str(int(start.timestamp() * 1_000_000_000))

        def result(lines: list[str]) -> bytes:
            return json.dumps(
                {
                    "status": "success",
                    "data": {
                        "result": [{"values": [[timestamp, line] for line in lines]}]
                    },
                }
            ).encode()

        with (
            patch("dev.observability_proof.MAX_LINES", 2),
            patch("dev.observability_proof.MAX_TOTAL_BYTES", 6),
        ):
            for lines, expected_truncated in (
                (["ab\n", "cd\n"], False),
                (["abc\n", "cd\n"], True),
                (["a\n", "b\n", "c\n"], True),
            ):
                with patch(
                    "dev.observability_proof._request",
                    return_value=(200, result(lines)),
                ):
                    status, actual, truncated = read_isolated_loki_lines(
                        "haruka-test-" + "a" * 32, start_utc=start
                    )
                self.assertEqual(status, 200)
                self.assertEqual(actual, lines)
                self.assertEqual(truncated, expected_truncated)


if __name__ == "__main__":
    unittest.main()
