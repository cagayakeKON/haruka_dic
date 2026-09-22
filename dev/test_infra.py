"""Regression checks for development infrastructure safety boundaries, without Docker."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from dev import infra


class InfrastructureSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.target_patch = patch.object(infra, "_docker_target", None)
        self.target_patch.start()
        self.addCleanup(self.target_patch.stop)

    def test_remote_docker_host_is_rejected_before_mutation(self) -> None:
        with (
            patch.dict("os.environ", {"DOCKER_HOST": "tcp://production.example:2376"}, clear=True),
            patch.object(infra, "command") as command,
            self.assertRaisesRegex(infra.InfraError, "local Docker"),
        ):
            infra.local_docker_guard()
        command.assert_not_called()

    def test_docker_context_takes_precedence_over_host(self) -> None:
        with (
            patch.dict(
                "os.environ",
                {"DOCKER_HOST": "tcp://127.0.0.1:2375", "DOCKER_CONTEXT": "remote"},
                clear=True,
            ),
            patch.object(infra, "command", return_value="ssh://remote.example") as command,
            self.assertRaisesRegex(infra.InfraError, "local Docker"),
        ):
            infra.local_docker_guard()
        self.assertEqual(command.call_count, 1)

    def test_same_project_from_another_checkout_is_rejected(self) -> None:
        with (
            patch.dict("os.environ", {"DOCKER_HOST": "unix:///var/run/docker.sock"}, clear=True),
            patch.object(infra, "command", return_value=str(infra.DEV.parent / "another-checkout")),
            self.assertRaisesRegex(infra.InfraError, "another checkout"),
        ):
            infra.local_docker_guard()

    def test_validated_target_remains_pinned_after_environment_changes(self) -> None:
        with (
            patch.dict("os.environ", {"DOCKER_HOST": "unix:///var/run/docker.sock"}, clear=True),
            patch.object(infra, "command", return_value=""),
        ):
            infra.local_docker_guard()
        with (
            patch.dict("os.environ", {"DOCKER_CONTEXT": "remote"}, clear=True),
            patch.object(infra.shutil, "which", return_value="docker"),
            patch.object(
                infra.subprocess, "run", return_value=infra.subprocess.CompletedProcess([], 0, "")
            ) as run,
        ):
            infra.command(["ps"])
        self.assertEqual(
            run.call_args.args[0], ["docker", "--host", "unix:///var/run/docker.sock", "ps"]
        )
        self.assertNotIn("DOCKER_CONTEXT", run.call_args.kwargs["env"])
        self.assertNotIn("DOCKER_HOST", run.call_args.kwargs["env"])

    def test_ambient_compose_variables_cannot_override_image_or_cluster_locks(self) -> None:
        with (
            patch.dict(
                "os.environ",
                {
                    "POSTGRES_IMAGE": "postgres:17.6",
                    "KAFKA_CLUSTER_ID": "ambient",
                    "COMPOSE_PROFILES": "provision",
                },
            ),
            patch.object(infra.shutil, "which", return_value="docker"),
            patch.object(
                infra.subprocess, "run", return_value=infra.subprocess.CompletedProcess([], 0, "")
            ) as run,
        ):
            infra.compose("config", "--images")
        environment = run.call_args.kwargs["env"]
        self.assertNotIn("POSTGRES_IMAGE", environment)
        self.assertNotIn("KAFKA_CLUSTER_ID", environment)
        self.assertNotIn("COMPOSE_PROFILES", environment)

    def test_existing_configuration_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(infra, "DEV", root):
                path = root / "config.env"
                infra.write_once(path, "existing-value\n")
                infra.write_once(path, "existing-value\n")
                with self.assertRaisesRegex(infra.InfraError, "kept unchanged"):
                    infra.write_once(path, "replacement\n")
                self.assertEqual(path.read_text(), "existing-value\n")

    def test_missing_credentials_do_not_reset_existing_volumes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with (
                patch.object(infra, "LOCAL", root),
                patch.object(infra, "local_docker_guard"),
                patch.object(infra, "command", return_value="haruka-local_postgres-data\n"),
                self.assertRaisesRegex(infra.InfraError, "original .local credentials"),
            ):
                infra.credentials()
            self.assertFalse((root / "credentials.json").exists())

    def test_invalid_credential_value_is_not_accepted_as_sql(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "credentials.json").write_text(json.dumps({"postgres_password": "not-hex'"}))
            with (
                patch.object(infra, "LOCAL", root),
                self.assertRaisesRegex(infra.InfraError, "invalid"),
            ):
                infra.credentials()

    def test_compose_always_uses_project_and_explicit_configuration(self) -> None:
        with patch.object(infra, "command", return_value="") as command:
            infra.compose("down", "--timeout", "20")
        arguments = command.call_args.args[0]
        self.assertIn("haruka-local", arguments)
        self.assertIn(str(infra.DEV / "compose.yaml"), arguments)
        self.assertIn(str(infra.LOCAL / "compose.env"), arguments)
        self.assertNotIn("--volumes", arguments)

    def test_smoke_rejects_zero_exit_without_valid_database_result(self) -> None:
        with (
            patch.object(infra, "compose", return_value=""),
            self.assertRaisesRegex(infra.InfraError, "expected probe"),
        ):
            infra.smoke()

    def test_smoke_rejects_redis_noauth_even_with_zero_exit(self) -> None:
        with (
            patch.object(
                infra, "compose", side_effect=["1\n", "NOAUTH Authentication required.\n"]
            ),
            self.assertRaisesRegex(infra.InfraError, "Redis did not return"),
        ):
            infra.smoke()


if __name__ == "__main__":
    unittest.main()
