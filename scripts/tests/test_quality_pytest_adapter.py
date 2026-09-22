"""Run the real pytest adapter against synthetic pass/failure/selection outcomes."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.quality.common import read_json, write_json
from scripts.tests.test_quality_cases import IDENTITY

ROOT = Path(__file__).resolve().parents[2]


class PytestAdapterChecks(unittest.TestCase):
    def test_real_pytest_adapter_preserves_selection_layers_and_outcomes(self) -> None:
        sources = {
            "pass": "import pytest\npytestmark=pytest.mark.unit\ndef test_probe():\n    assert True\n",
            "skip": "import pytest\npytestmark=pytest.mark.unit\ndef test_probe():\n    pytest.skip('synthetic negative')\n",
            "xfail": "import pytest\npytestmark=[pytest.mark.unit,pytest.mark.xfail]\ndef test_probe():\n    assert False\n",
            "layer": "def test_probe():\n    assert True\n",
            "deselect": "import pytest\npytestmark=pytest.mark.unit\ndef test_probe():\n    assert True\n",
            "collection-error": "import pytest\npytestmark=pytest.mark.unit\ndef test_probe():\n    assert True\n",
        }
        for variant, source in sources.items():
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / "test_probe.py").write_text(source, encoding="utf-8")
                if variant == "collection-error":
                    (root / "test_import_failure.py").write_text(
                        "raise RuntimeError('synthetic collection error')\n", encoding="utf-8"
                    )
                manifest: dict[str, object] = {
                    "schema_version": 1,
                    "cases": [
                        {
                            "case_id": "ADAPTER-PROBE",
                            "acceptance_refs": ["SCF-B0-07"],
                            "layer": "unit",
                            "runner": "pytest",
                            "platform": "host",
                            "audience": "harness",
                            "transport": "local",
                            "parameters": {},
                            "shard": "probe",
                            "nodes": ["test_probe.py::test_probe"],
                            "source": "scripts/tests/test_quality_pytest_adapter.py",
                        }
                    ],
                    "scopes": {"probe": ["ADAPTER-PROBE"]},
                }
                write_json(root / "manifest.json", manifest)
                write_json(root / "identity.json", IDENTITY)
                environment = os.environ.copy()
                environment["PYTHONPATH"] = str(ROOT)
                command = [
                    sys.executable,
                    "-m",
                    "pytest",
                    "-q",
                    "--rootdir",
                    str(root),
                    "--confcutdir",
                    str(root),
                    "-o",
                    "markers=unit: isolated test",
                    "-p",
                    "scripts.quality.pytest_plugin",
                    "--quality-manifest",
                    str(root / "manifest.json"),
                    "--quality-identity",
                    str(root / "identity.json"),
                    "--quality-shard",
                    "probe",
                    "--quality-scope",
                    "probe",
                    "--quality-output",
                    str(root / "reports"),
                ]
                if variant == "deselect":
                    command.extend(["-k", "not probe"])
                if variant == "collection-error":
                    command.append("--continue-on-collection-errors")
                process = subprocess.run(  # noqa: S603 - fixed interpreter and synthetic local test arguments
                    command, cwd=root, env=environment, capture_output=True, timeout=30, check=False
                )
                if variant == "pass":
                    self.assertEqual(
                        process.returncode,
                        0,
                        process.stdout.decode(errors="replace")
                        + process.stderr.decode(errors="replace"),
                    )
                    self.assertTrue(read_json(root / "reports/probe-summary.json")["passed"])
                else:
                    self.assertNotEqual(process.returncode, 0)
                    self.assertTrue((root / "reports/probe-collection.json").is_file())
                    self.assertTrue((root / "reports/probe-result.json").is_file())
                    if variant == "collection-error":
                        self.assertFalse(read_json(root / "reports/probe-summary.json")["passed"])
                        self.assertEqual(
                            read_json(root / "reports/probe-result.json")["session_status"],
                            "failed",
                        )


if __name__ == "__main__":
    unittest.main()
