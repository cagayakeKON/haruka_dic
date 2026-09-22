"""Fail closed when native verification or its cleanup fails; never replace evidence."""

import json
import tempfile
import unittest
from pathlib import Path

from android_controls import verify_controls

IDS = {key: key for key in ("fixturePage", "fixtureInput", "fixtureSubmit", "fixtureDialog")}


class Device:
    def __init__(self, report: Path, failure: str = "") -> None:
        self.report = report
        self.failure = failure
        self.keyboard = False
        self.dialog = False
        self.text = ""
        self.cleanup: list[str] = []
        self.calls: list[tuple[str, ...]] = []

    def command(self, *args: str) -> str:
        self.calls.append(args)
        if args[:2] == ("shell", "rm"):
            self.cleanup.append("remove_xml")
            if json.loads(self.report.read_text("utf-8"))["status"] != "running":
                raise AssertionError("Passed report published before cleanup")
            if self.failure == "xml":
                raise OSError("private cleanup sentinel")
        if args[:3] == ("shell", "settings", "delete"):
            self.cleanup.append("restore_ime")
            if self.failure == "ime":
                raise OSError("private cleanup sentinel")
        if args[:3] == ("shell", "settings", "get"):
            return "null"
        if args[:2] == ("shell", "cat"):
            nodes = [
                f'<node resource-id="{key}" package="app.haruka.dictionary.dev" bounds="[{index},0][{index + 1},2]"/>'
                for index, key in enumerate(("fixturePage", "fixtureInput", "fixtureSubmit"))
            ]
            if self.dialog:
                nodes.append(
                    '<node resource-id="fixtureDialog" package="app.haruka.dictionary.dev"/>'
                )
            nodes.append(f'<node text="{self.text}"/>')
            return "<hierarchy>" + "".join(nodes) + "</hierarchy>"
        if args[:3] == ("shell", "input", "tap"):
            if args[3] == "1":
                self.keyboard = True
            else:
                self.dialog = True
        if args[:3] == ("shell", "input", "text"):
            if self.failure == "input":
                raise OSError("private interaction sentinel")
            self.text = args[3]
        if args[:3] == ("shell", "input", "keyevent"):
            self.keyboard = False
            self.dialog = False
        if args[:3] == ("shell", "dumpsys", "input_method"):
            return "mInputShown=" + str(self.keyboard).lower()
        if args[:2] == ("shell", "getprop"):
            return "34"
        return ""


class EvidenceTests(unittest.TestCase):
    def test_existing_failure_report_is_refused_before_any_device_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            original = '{"status":"failed","failure":"earlier_attempt"}\n'
            output.write_text(original, encoding="utf-8")
            device = Device(output)
            with self.assertRaises(FileExistsError):
                verify_controls(device.command, IDS, "emulator-5556", output)
            self.assertEqual(output.read_text("utf-8"), original)
            self.assertEqual(device.calls, [])

    def test_cleanup_failure_never_publishes_pass_and_attempts_both_steps(self) -> None:
        for failure in ("xml", "ime", "input"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "result.json"
                device = Device(output, failure)
                self.assertEqual(verify_controls(device.command, IDS, "emulator-5556", output), 1)
                contents = output.read_text("utf-8")
                report = json.loads(contents)
                self.assertEqual(report["status"], "failed")
                self.assertEqual(device.cleanup, ["restore_ime", "remove_xml"])
                self.assertNotIn("private", contents)
                self.assertEqual(
                    report["failure"],
                    "interaction_failed" if failure == "input" else "cleanup_failed",
                )

    def test_success_only_after_cleanup_and_existing_output_never_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            device = Device(output)
            self.assertEqual(verify_controls(device.command, IDS, "emulator-5556", output), 0)
            evidence = output.read_bytes()
            self.assertEqual(
                json.loads(evidence)["cleanup"], {"restore_ime": "passed", "remove_xml": "passed"}
            )
            previous_calls = len(device.calls)
            with self.assertRaises(FileExistsError):
                verify_controls(device.command, IDS, "emulator-5556", output)
            self.assertEqual(output.read_bytes(), evidence)
            self.assertEqual(len(device.calls), previous_calls)


if __name__ == "__main__":
    unittest.main()
