"""Regression checks for secret-free model evidence output."""

import json
import secrets
import unittest
from datetime import UTC, datetime, timedelta
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from dev.model_log_proof import absence_checks, safe_model_events
from dev.observability_proof import ProofError, read_isolated_loki_lines


class ModelLogProofChecks(unittest.TestCase):
    def test_leak_is_reported_without_copying_secret_or_source_body(self) -> None:
        secret = secrets.token_urlsafe(24)
        checks = absence_checks([secret], ["Hello."], secret)
        self.assertFalse(checks["provider_key"]["absent_local"])
        self.assertFalse(checks["english_speech_sample"]["absent_loki"])
        self.assertNotIn(secret, json.dumps(checks))
        self.assertNotIn("Hello.", json.dumps(checks))

    def test_other_instance_and_library_body_are_not_evidence(self) -> None:
        lines = [
            json.dumps({"instance_id": "other", "event": "model.attempt.completed"}),
            json.dumps({"instance_id": "owned", "event": "private arbitrary body"}),
            json.dumps({"instance_id": "owned", "event": "model.attempt.started"}),
            json.dumps({"instance_id": "owned", "origin": "client", "event": "http.completed"}),
        ]
        self.assertEqual(
            safe_model_events(lines, "owned"),
            {"model.attempt.started": 1, "frontend.http.completed": 1},
        )

    def test_dense_log_windows_are_bounded_and_have_no_gaps(self) -> None:
        response = json.dumps({"status": "success", "data": {"result": []}}).encode()
        with patch("dev.observability_proof._request", return_value=(200, response)) as request:
            status, lines, truncated = read_isolated_loki_lines(
                "owned",
                start_utc=datetime.now(UTC) - timedelta(seconds=121),
                window_seconds=60,
            )
        self.assertEqual((status, lines, truncated), (200, [], False))
        windows: list[dict[str, list[str]]] = []
        for call in request.call_args_list:
            url: object = call.args[0]
            if not isinstance(url, str):
                self.fail("query URL must be text")
            windows.append(parse_qs(urlsplit(url).query))
        self.assertEqual(len(windows), 3)
        for index, window in enumerate(windows):
            self.assertLessEqual(
                int(window["end"][0]) - int(window["start"][0]) + 1, 60_000_000_000
            )
            if index:
                self.assertEqual(int(window["start"][0]), int(windows[index - 1]["end"][0]) + 1)

    def test_invalid_log_window_is_rejected_before_query(self) -> None:
        with (
            patch("dev.observability_proof._request") as request,
            self.assertRaises(ProofError),
        ):
            read_isolated_loki_lines("owned", window_seconds=301)
        request.assert_not_called()

    def test_full_same_timestamp_page_is_incomplete_not_skipped(self) -> None:
        response = json.dumps(
            {
                "status": "success",
                "data": {"result": [{"values": [["1", "bounded fixture"]] * 5000}]},
            }
        ).encode()
        with patch("dev.observability_proof._request", return_value=(200, response)) as request:
            status, lines, truncated = read_isolated_loki_lines(
                "owned",
                start_utc=datetime.now(UTC) - timedelta(seconds=121),
                window_seconds=10,
            )
        self.assertEqual(status, 200)
        self.assertEqual(len(lines), 5000)
        self.assertTrue(truncated)
        self.assertEqual(request.call_count, 1)


if __name__ == "__main__":
    unittest.main()
