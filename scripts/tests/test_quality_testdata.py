"""Static asset and recipe rejection at the earliest offline boundary."""

from __future__ import annotations

import copy
import shutil
import tempfile
import unittest
from pathlib import Path

from scripts.quality.common import GateError, array, obj, read_json, write_json
from scripts.quality.testdata import inspect, validate_assets, validate_scenario

ROOT = Path(__file__).resolve().parents[2]


class TestDataChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        shutil.copytree(ROOT / "testdata", self.root / "testdata")

    def test_original_fixture_hashes_and_scenario_bindings_are_valid(self) -> None:
        result = inspect(self.root)
        self.assertTrue(result["passed"])
        self.assertEqual(result["asset_count"], 2)

    def test_missing_changed_or_extra_asset_is_rejected(self) -> None:
        path = self.root / "testdata/assets/text/english-unicode-v1.txt"
        original = path.read_bytes()
        path.write_bytes(original + b"changed")
        with self.assertRaises(GateError):
            inspect(self.root)
        path.write_bytes(original)
        path.unlink()
        with self.assertRaises(GateError):
            inspect(self.root)
        path.write_bytes(original)
        (path.parent / "unregistered-copy.txt").write_bytes(original)
        with self.assertRaises(GateError):
            inspect(self.root)

    def test_license_language_version_and_path_boundary_are_required(self) -> None:
        path = self.root / "testdata/assets/manifest.json"
        original = read_json(path)
        invalid: tuple[tuple[str, object], ...] = (
            ("license", "unknown"),
            ("languages", []),
            ("version", 2),
            ("path", "../escape.txt"),
            ("path", "https://example.invalid/file"),
        )
        for key, value in invalid:
            with self.subTest(key=key, value=value):
                data = copy.deepcopy(original)
                obj(array(data["assets"])[0])[key] = value
                write_json(path, data)
                with self.assertRaises(GateError):
                    inspect(self.root)

    def test_recipe_schema_unknown_fields_and_secret_parameters_fail(self) -> None:
        assets = validate_assets(self.root)
        original = read_json(self.root / "testdata/scenarios/b0-static-assets.json")
        for key, value in (
            ("schema_version", 2),
            ("setup_recipe", "run_sql"),
            ("password", "SYNTHETIC_REJECTED_SENTINEL"),
            ("provider_profile", "live"),
            ("actors_profile", "admin"),
        ):
            with self.subTest(key=key):
                data = copy.deepcopy(original)
                data[key] = value
                with self.assertRaises(GateError):
                    validate_scenario(data, assets)
        data = copy.deepcopy(original)
        obj(data["recipe_params"])["token"] = "SYNTHETIC_REJECTED_SENTINEL"  # noqa: S105 - deliberately invalid fake credential
        with self.assertRaises(GateError):
            validate_scenario(data, assets)

    def test_unknown_missing_or_cross_scope_aliases_fail(self) -> None:
        assets = validate_assets(self.root)
        original = read_json(self.root / "testdata/scenarios/b0-static-assets.json")
        for value in ([], ["users.admin"], ["assets.english", "assets.english"]):
            with self.subTest(value=value):
                data = copy.deepcopy(original)
                data["expected_aliases"] = value
                with self.assertRaises(GateError):
                    validate_scenario(data, assets)
        data = copy.deepcopy(original)
        data["asset_refs"] = ["unknown"]
        with self.assertRaises(GateError):
            validate_scenario(data, assets)

    def test_executable_yaml_and_duplicate_json_keys_are_rejected(self) -> None:
        path = self.root / "testdata/scenarios/injected.yaml"
        path.write_text("!!python/object/apply:os.system [not-executed]", encoding="utf-8")
        with self.assertRaises(GateError):
            inspect(self.root)
        path.unlink()
        path = self.root / "testdata/scenarios/b0-static-assets.json"
        path.write_text('{"schema_version": 1, "schema_version": 1}', encoding="utf-8")
        with self.assertRaisesRegex(GateError, "duplicate"):
            inspect(self.root)


if __name__ == "__main__":
    unittest.main()
