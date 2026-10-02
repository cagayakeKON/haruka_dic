"""Negative samples for the frontend-owned locator registry validation."""

import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from generate import (
    generate_error_catalog,
    generate_selection,
    unique_object,
    validate_error_catalog,
    validate_ids,
    validate_reviewed_schemas,
)


class RegistryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.identifiers: dict[str, str] = {"home": "client.shell.home.page"}
        self.registry: dict[str, object] = {
            "schema_version": 1,
            "static": self.identifiers,
            "templates": {},
        }

    def test_valid_registry(self) -> None:
        validate_ids(self.registry)

    def test_duplicate_json_keys(self) -> None:
        with self.assertRaises(ValueError):
            unique_object([("home", 1), ("home", 2)])

    def test_duplicate_id(self) -> None:
        self.identifiers["duplicate"] = "client.shell.home.page"
        with self.assertRaises(ValueError):
            validate_ids(self.registry)

    def test_invalid_id_and_identifier(self) -> None:
        for key, value in (("bad-key", "client.shell.home.page"), ("home", "private@example.com")):
            registry = copy.deepcopy(self.registry)
            registry["static"] = {key: value}
            with self.assertRaises(ValueError):
                validate_ids(registry)

    def test_unknown_template(self) -> None:
        self.registry["templates"] = {"row": "client.shell.row.{unknown}"}
        with self.assertRaises(ValueError):
            validate_ids(self.registry)

    def test_registered_resource_templates(self) -> None:
        self.registry["templates"] = {
            "referenceMaterialRow": "client.reference.materials.row.{materialId}",
            "referenceBlock": "client.reference.chapter.block.{blockId}",
            "referenceCollectionRow": "client.reference.collections.row.{collectionId}",
            "sessionRevoke": "client.account.sessions.revoke.{sessionId}",
            "notificationRow": "client.notifications.row.{notificationId}",
        }
        validate_ids(self.registry)
        self.registry["templates"]["referenceBlock"] = "client.reference.chapter.block.{index}"
        with self.assertRaises(ValueError):
            validate_ids(self.registry)

    def test_missing_translation_and_unreviewed_parameters_fail(self) -> None:
        error: dict[str, object] = {"code": "BAD_REQUEST", "message_args": {}}
        catalog: dict[str, object] = {"errors": [error], "field_errors": []}
        with self.assertRaises(ValueError):
            validate_error_catalog(catalog, {})
        locale: dict[str, object] = {"apiBadRequest": "错误"}
        self.assertEqual(validate_error_catalog(catalog, locale)[0], ["BAD_REQUEST"])
        error["message_args"] = {"unknown": "string"}
        with self.assertRaises(ValueError):
            validate_error_catalog(catalog, locale)
        error["message_args"] = {}
        locale["@apiBadRequest"] = {"placeholders": {"unknown": {"type": "String"}}}
        with self.assertRaises(ValueError):
            validate_error_catalog(catalog, locale)

    def test_schema_addition_deletion_and_type_changes_require_review(self) -> None:
        schemas: dict[str, object] = {"HealthRead": {"status": "string"}}
        digest = hashlib.sha256(
            json.dumps(schemas, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        validate_reviewed_schemas(schemas, digest)
        changes: list[dict[str, object]] = [
            {},
            {"HealthRead": {"status": "integer"}},
            {**schemas, "New": {}},
        ]
        for changed in changes:
            with self.assertRaises(ValueError):
                validate_reviewed_schemas(changed, digest)

    def test_identifier_generation_needs_no_api_inputs_and_writes_no_api_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "config").mkdir()
            (root / "config/ui_test_ids.json").write_text(json.dumps(self.registry))
            output = root / "output"
            with patch("generate.ROOT", root), patch("generate.run"):
                generate_selection(output, "ui-identifiers")
            generated = output / "lib/generated/ui_test_ids.dart"
            self.assertIn('static const home = "client.shell.home.page";', generated.read_text())
            self.assertEqual(list((output / "lib/generated").iterdir()), [generated])
            self.assertFalse((output / "lib/generated/api_catalog.dart").exists())

    def test_independent_identifier_selection_still_rejects_duplicate_registry(self) -> None:
        self.identifiers["duplicate"] = "client.shell.home.page"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "config").mkdir()
            (root / "config/ui_test_ids.json").write_text(json.dumps(self.registry))
            with patch("generate.ROOT", root), patch("generate.run"), self.assertRaises(ValueError):
                generate_selection(root / "output", "ui-identifiers")
            self.assertFalse((root / "output/lib/generated/ui_test_ids.dart").exists())

    def test_error_catalog_is_generated_only_from_catalog_and_matching_locale(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            root = workspace / "frontend"
            (workspace / "contracts").mkdir()
            (root / "lib/l10n").mkdir(parents=True)
            (workspace / "contracts/errors.json").write_text(
                json.dumps(
                    {"errors": [{"code": "BAD_REQUEST", "message_args": {}}], "field_errors": []}
                )
            )
            locale = root / "lib/l10n/app_zh.arb"
            locale.write_text(json.dumps({"apiBadRequest": "错误"}))
            with patch("generate.ROOT", root):
                generate_error_catalog(workspace / "output")
                generated = workspace / "output/lib/generated/api_catalog.dart"
                self.assertIn('"BAD_REQUEST" => strings.apiBadRequest', generated.read_text())
                locale.write_text("{}")
                with self.assertRaises(ValueError):
                    generate_error_catalog(workspace / "missing-locale")
                self.assertFalse(
                    (workspace / "missing-locale/lib/generated/api_catalog.dart").exists()
                )

    def test_public_targets_generate_without_api_and_keep_production_identity(self) -> None:
        registry = Path(__file__).resolve().parents[1] / "config/build_targets.json"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "config").mkdir()
            (root / "config/build_targets.json").write_text(registry.read_text())
            with patch("generate.ROOT", root), patch("generate.run"):
                generate_selection(root / "output", "build-targets")
            generated = root / "output/lib/generated/build_targets.dart"
            self.assertIn("http://localhost:18443", generated.read_text())
            self.assertIn("app.haruka.dictionary", generated.read_text())
            self.assertFalse((root / "output/lib/generated/api_catalog.dart").exists())


if __name__ == "__main__":
    unittest.main()
