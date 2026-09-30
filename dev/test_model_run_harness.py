"""Local model-task runner ownership guards at the Kafka mutation boundary."""

import asyncio
import json
import secrets
import tempfile
import unittest
from pathlib import Path
from typing import Literal, cast
from unittest.mock import patch

from dev import infra, isolated_app_run


class ModelRunOwnershipChecks(unittest.TestCase):
    def test_mail_keeps_identity_and_smtp_in_core_profile(self) -> None:
        contents = (
            "HARUKA_RESOURCE_PROFILE=jobs\r\nHARUKA_MODEL_EXECUTION_MODE=fake\r\n"
            "HARUKA_INSTANCE_ID=haruka-test-owned\r\n"
            "HARUKA_SMTP_HOST=127.0.0.1\r\nHARUKA_MAIL_ENCRYPTION_KEY=fictional\r\n"
        )
        result = isolated_app_run.core_mail_configuration(contents)
        self.assertIn("HARUKA_RESOURCE_PROFILE=core\n", result)
        self.assertIn("HARUKA_MODEL_EXECUTION_MODE=disabled\n", result)
        for line in contents.splitlines()[2:]:
            self.assertIn(line + "\n", result)
        with self.assertRaises(isolated_app_run.IsolatedRunError):
            isolated_app_run.core_mail_configuration(contents + "HARUKA_RESOURCE_PROFILE=core")

    def owned_run(self, root: Path, state: str) -> str:
        run_id = "a" * 32
        directory = root / run_id
        directory.mkdir()
        (directory / "ledger.json").write_text(
            json.dumps(
                {
                    "version": 1,
                    "run_id": run_id,
                    "schema": f"haruka_migration_test_{run_id}",
                    "state": state,
                }
            ),
            encoding="utf-8",
        )
        return run_id

    def test_active_or_unowned_topic_cannot_be_deleted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run_id = self.owned_run(root, "serving")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(isolated_app_run, "compose") as broker,
            ):
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.configure_owned_job_topic(run_id, delete=True)
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.configure_owned_job_topic("haruka-local-dev", delete=True)
                broker.assert_not_called()

    def test_failed_preparation_only_deletes_ledger_owned_exact_topic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run_id = self.owned_run(root, "cleaning_schema_only")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(isolated_app_run, "compose") as broker,
                patch.object(isolated_app_run, "local_docker_guard"),
            ):
                isolated_app_run.configure_owned_job_topic(run_id, delete=True)
                arguments = broker.call_args.args
                self.assertEqual(
                    arguments[arguments.index("--topic") + 1],
                    f"haruka-test-{run_id}.jobs",
                )
                self.assertIn("--delete", arguments)
                self.assertNotIn("--create", arguments)

    def test_topic_mutation_rejects_remote_docker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run_id = self.owned_run(root, "created")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(infra, "_docker_target", None),
                patch.dict(
                    "os.environ",
                    {"DOCKER_HOST": "tcp://remote.invalid:2376"},
                    clear=True,
                ),
                patch.object(isolated_app_run, "compose") as broker,
                self.assertRaises(infra.InfraError),
            ):
                isolated_app_run.configure_owned_job_topic(run_id)
            broker.assert_not_called()

    def test_invalid_execution_mode_does_not_create_a_run(self) -> None:
        with patch.object(isolated_app_run, "create_owned_schema") as schema:
            with self.assertRaises(isolated_app_run.IsolatedRunError):
                invalid_mode = cast("Literal['disabled', 'fake', 'live']", "production")
                asyncio.run(isolated_app_run.prepare(model_mode=invalid_mode))
            schema.assert_not_called()

    def test_provider_mode_cannot_change_while_processes_are_active(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run_id = self.owned_run(root, "serving")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(isolated_app_run, "create_maintenance_engine") as database,
                self.assertRaises(isolated_app_run.IsolatedRunError),
            ):
                asyncio.run(isolated_app_run.set_model_mode(run_id, "live"))
            database.assert_not_called()

    def test_object_provisioning_cannot_mutate_an_active_run(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run_id = self.owned_run(root, "serving")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(isolated_app_run, "Minio") as storage,
                self.assertRaises(isolated_app_run.IsolatedRunError),
            ):
                isolated_app_run.configure_owned_object_storage(run_id, delete=True)
            storage.assert_not_called()

    def test_bucket_without_server_ownership_tag_cannot_be_deleted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            root = workspace / "runs"
            root.mkdir()
            run_id = self.owned_run(root, "cleaning")
            secret_file = workspace / "dev/.local/minio/root_password"
            secret_file.parent.mkdir(parents=True)
            secret_file.write_text(secrets.token_hex(24), encoding="utf-8")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(isolated_app_run, "ROOT", workspace),
                patch.object(isolated_app_run, "local_docker_guard"),
                patch.object(isolated_app_run, "Minio") as storage,
                patch.object(isolated_app_run, "compose") as provision,
            ):
                storage.return_value.bucket_exists.return_value = True
                storage.return_value.get_bucket_tags.return_value = {"haruka-run": "other"}
                with self.assertRaises(isolated_app_run.IsolatedRunError):
                    isolated_app_run.configure_owned_object_storage(run_id, delete=True)
                storage.return_value.remove_bucket.assert_not_called()
                storage.return_value.remove_object.assert_not_called()
                provision.assert_not_called()

    def test_stopped_storage_repair_trims_file_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            root = workspace / "runs"
            root.mkdir()
            run_id = self.owned_run(root, "stopped")
            secret_file = workspace / "dev/.local/minio/root_password"
            secret_file.parent.mkdir(parents=True)
            secret_file.write_text(secrets.token_hex(24), encoding="utf-8")
            (root / run_id / "storage.secret").write_bytes(b"fictional-secret\r\n")
            with (
                patch.object(isolated_app_run, "LOCAL_ROOT", root),
                patch.object(isolated_app_run, "ROOT", workspace),
                patch.object(isolated_app_run, "local_docker_guard"),
                patch.object(isolated_app_run, "Minio") as storage,
                patch.object(isolated_app_run, "compose") as provision,
            ):
                storage.return_value.bucket_exists.return_value = True
                storage.return_value.get_bucket_tags.return_value = {"haruka-run": run_id}
                isolated_app_run.configure_owned_object_storage(run_id)
                self.assertIn("tr -d '\\r\\n'", provision.call_args.args[-1])
                storage.return_value.make_bucket.assert_not_called()


if __name__ == "__main__":
    unittest.main()
