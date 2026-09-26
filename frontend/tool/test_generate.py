"""Negative samples for the frontend-owned locator registry validation."""

import copy
import hashlib
import json
import unittest

from generate import unique_object, validate_error_catalog, validate_ids, validate_reviewed_schemas


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


if __name__ == "__main__":
    unittest.main()
