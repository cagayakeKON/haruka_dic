"""Boundary checks for the isolated Windows installer prototype."""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from build_probe import SOURCE, identities, object_value, package_document, stable_guid


class IdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        parsed: object = json.loads(SOURCE.read_text(encoding="utf-8"))
        self.source = object_value(parsed)

    def windows_entry(self, source: dict[str, object], environment: str) -> dict[str, object]:
        return object_value(object_value(object_value(source["platforms"])["windows"])[environment])

    def test_stable_upgrade_identity_and_distinct_environments(self) -> None:
        mapped = identities(self.source)
        self.assertEqual(mapped["dev"].upgrade_code, stable_guid("haruka.dictionary.dev"))
        self.assertNotEqual(mapped["dev"].upgrade_code, mapped["production"].upgrade_code)
        self.assertNotEqual(mapped["dev"].product_directory, mapped["production"].product_directory)
        self.assertNotEqual(
            mapped["dev"].credential_service, mapped["production"].credential_service
        )

    def test_missing_identity_field_fails(self) -> None:
        source = copy.deepcopy(self.source)
        del self.windows_entry(source, "dev")["installer_id"]
        with self.assertRaises(KeyError):
            identities(source)

    def test_environment_alias_and_credential_alias_fail(self) -> None:
        for key in ("application_id", "installer_id", "credential_service"):
            source = copy.deepcopy(self.source)
            self.windows_entry(source, "dev")[key] = "haruka.dictionary"
            with self.assertRaises(ValueError):
                identities(source)

    def test_product_directory_traversal_and_duplicate_fail(self) -> None:
        for directory in ("..", "..\\Haruka", "C:\\Haruka", "Haruka/Dev", "Haruka", "Haruka Dev "):
            source = copy.deepcopy(self.source)
            self.windows_entry(source, "dev")["product_directory"] = directory
            with self.assertRaises(ValueError):
                identities(source)

    def test_wxs_is_per_user_and_has_no_launch_or_custom_actions(self) -> None:
        identity = identities(self.source)["dev"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in ("haruka-installation.json", "identity-probe.ps1"):
                (root / filename).write_text("probe", encoding="utf-8")
            tree = package_document(identity, "0.1.0", root)
            element = tree.getroot()
            if element is None:
                self.fail("Missing Wix root")
            package = element.find("Package")
            self.assertIsNotNone(package)
            if package is None:
                self.fail("Missing Package")
            self.assertEqual(package.attrib["Scope"], "perUser")
            self.assertEqual(package.attrib["UpgradeCode"], identity.upgrade_code)
            self.assertEqual(tree.findall(".//CustomAction"), [])
            self.assertEqual(tree.findall(".//ServiceInstall"), [])
            self.assertEqual(tree.findall(".//Shortcut"), [])

    def test_invalid_msi_version_and_missing_payload_fail(self) -> None:
        identity = identities(self.source)["dev"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for version in ("next", "1.0.0.0", "999.0.0", "1.0.99999"):
                with self.assertRaises(ValueError):
                    package_document(identity, version, root)
            with self.assertRaises(ValueError):
                package_document(identity, "0.1.0", root)


if __name__ == "__main__":
    unittest.main()
