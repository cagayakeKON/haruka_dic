"""Negative samples for the frontend-owned locator registry validation."""

import copy
import unittest

from generate import unique_object, validate_ids


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


if __name__ == "__main__":
    unittest.main()
