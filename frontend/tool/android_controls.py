"""Verify the isolated control fixture through Android's real semantic/input boundary."""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections.abc import Callable
from pathlib import Path

Command = Callable[..., str]


class Arguments(argparse.Namespace):
    device: str
    output: Path


def verify_controls(command: Command, ids: dict[str, str], device: str, output: Path) -> int:
    """Claim fresh evidence, verify controls, then publish only after both cleanup steps."""
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation prevents a retry from replacing any earlier pass or failure.
    with output.open("x", encoding="utf-8", newline="\n") as evidence:
        report: dict[str, object] = {
            "case_id": "UIE-04-ANDROID",
            "device": device,
            "status": "running",
        }
        cleanup: dict[str, str] = {"restore_ime": "not_needed", "remove_xml": "not_needed"}
        report["cleanup"] = cleanup

        def write_evidence() -> None:
            evidence.seek(0)
            evidence.truncate()
            evidence.write(json.dumps(report, indent=2) + "\n")
            evidence.flush()

        write_evidence()
        previous: str | None = None
        ime_change_attempted = False
        xml_attempted = False
        interaction_passed = False

        def snapshot() -> ET.Element:
            nonlocal xml_attempted
            xml_attempted = True
            command("shell", "uiautomator", "dump", "/sdcard/haruka-controls.xml")
            # Local isolated fixture, with no external DTD or private application input.
            return ET.fromstring(command("shell", "cat", "/sdcard/haruka-controls.xml"))  # noqa: S314

        def node(key: str) -> ET.Element:
            matches = [
                item for item in snapshot().iter("node") if item.get("resource-id") == ids[key]
            ]
            if len(matches) != 1 or matches[0].get("package") != "app.haruka.dictionary.dev":
                raise RuntimeError("Expected one active Haruka fixture semantic identifier")
            return matches[0]

        def tap(key: str) -> None:
            match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node(key).get("bounds", ""))
            if match is None:
                raise RuntimeError("Missing semantic bounds")
            left, top, right, bottom = map(int, match.groups())
            command("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))

        def keyboard_visible(expected: bool) -> None:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                shown = "mInputShown=true" in command("shell", "dumpsys", "input_method")
                if shown == expected:
                    return
                time.sleep(0.2)
            raise RuntimeError("Android keyboard state did not reach the expected value")

        try:
            node("fixturePage")
            previous = command(
                "shell", "settings", "get", "secure", "show_ime_with_hard_keyboard"
            ).strip()
            if previous not in {"null", "0", "1"}:
                raise RuntimeError("Unexpected IME configuration")
            ime_change_attempted = True
            command("shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1")
            tap("fixtureInput")
            keyboard_visible(True)
            report["real_soft_keyboard"] = "passed"
            command("shell", "input", "text", "HarukaNative")
            if not any(item.get("text") == "HarukaNative" for item in snapshot().iter("node")):
                raise RuntimeError("Native input did not reach the editable semantic control")
            report["semantic_input"] = "passed"
            command("shell", "input", "keyevent", "KEYCODE_BACK")
            keyboard_visible(False)
            node("fixturePage")
            report["back_closes_keyboard_before_page"] = "passed"
            tap("fixtureSubmit")
            node("fixtureDialog")
            command("shell", "input", "keyevent", "KEYCODE_BACK")
            node("fixturePage")
            if any(
                item.get("resource-id") == ids["fixtureDialog"] for item in snapshot().iter("node")
            ):
                raise RuntimeError("Back did not close the current dialog")
            report["back_closes_dialog_before_page"] = "passed"
            report["api_level"] = command("shell", "getprop", "ro.build.version.sdk").strip()
            interaction_passed = True
        except Exception:
            # Do not retain adb output, filesystem paths, or raw exception contents.
            report["failure"] = "interaction_failed"
        finally:
            if ime_change_attempted:
                try:
                    if previous == "null":
                        command(
                            "shell", "settings", "delete", "secure", "show_ime_with_hard_keyboard"
                        )
                    else:
                        if previous is None:
                            raise RuntimeError("Missing original IME configuration")
                        command(
                            "shell",
                            "settings",
                            "put",
                            "secure",
                            "show_ime_with_hard_keyboard",
                            previous,
                        )
                    cleanup["restore_ime"] = "passed"
                except Exception:
                    cleanup["restore_ime"] = "failed"
            if xml_attempted:
                try:
                    command("shell", "rm", "-f", "/sdcard/haruka-controls.xml")
                    cleanup["remove_xml"] = "passed"
                except Exception:
                    cleanup["remove_xml"] = "failed"

        cleanup_passed = "failed" not in cleanup.values()
        if not cleanup_passed:
            report["failure"] = "cleanup_failed"
        passed = interaction_passed and cleanup_passed
        report["status"] = "passed" if passed else "failed"
        write_evidence()
        return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(namespace=Arguments())
    if not re.fullmatch(r"emulator-\d+", args.device):
        raise SystemExit("This prototype requires an explicitly selected emulator")
    adb = shutil.which("adb")
    if adb is None:
        raise SystemExit("Android platform-tools must be installed")

    def command(*arguments: str) -> str:
        # Fixed arrays; no shell text. Device is explicit and validated above.
        return subprocess.run(  # noqa: S603
            [adb, "-s", args.device, *arguments],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=30,
        ).stdout

    registry = json.loads(
        (Path(__file__).resolve().parents[1] / "config/ui_test_ids.json").read_text("utf-8")
    )
    try:
        result = verify_controls(command, registry["static"], args.device, args.output)
    except FileExistsError:
        sys.stderr.write("Evidence already exists; choose a new report path.\n")
        return 1
    sys.stdout.write(
        "Android controls verified with cleanup.\n"
        if result == 0
        else "Android verification failed; inspect the safe evidence report.\n"
    )
    return result


if __name__ == "__main__":
    raise SystemExit(main())
