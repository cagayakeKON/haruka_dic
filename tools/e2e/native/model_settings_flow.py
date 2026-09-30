"""Exercise the dev release model settings through Android UI in a fake run."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path
from uuid import UUID

from app.core.settings import load_settings

from dev.isolated_app_run import read_ledger, run_root
from tools.e2e.native.android_app_flow import (
    ACTIVITY,
    APK_ROOT,
    BOUNDS,
    PACKAGE,
    REGISTRY,
    Device,
    FlowError,
    _api_identity,
    _login_page,
    _release_apk,
)


class ModelPage:
    def __init__(self, device: Device):
        self.device = device

    def node(self, label: str, *, timeout: float = 30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            matches = [
                node
                for node in self.device.snapshot().iter("node")
                if node.get("package") == PACKAGE
                and node.get("enabled") != "false"
                and (
                    label in node.get("text", "")
                    or label in node.get("content-desc", "")
                )
            ]
            exact = [
                node
                for node in matches
                if label in (node.get("text"), node.get("content-desc"))
            ]
            candidates = exact or matches
            if candidates:
                return min(
                    candidates, key=lambda node: self.area(node.get("bounds", ""))
                )
            time.sleep(0.4)
        raise FlowError("android_model_label_missing")

    @staticmethod
    def area(bounds: str) -> int:
        match = BOUNDS.fullmatch(bounds)
        if match is None:
            return sys.maxsize
        left, top, right, bottom = map(int, match.groups())
        return (right - left) * (bottom - top)

    def tap(self, label: str) -> None:
        node = self.node(label)
        self.tap_node(node)

    def tap_node(self, node) -> None:
        match = BOUNDS.fullmatch(node.get("bounds", ""))
        if match is None:
            raise FlowError("android_model_bounds_missing")
        left, top, right, bottom = map(int, match.groups())
        self.device.command(
            "shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2)
        )

    def toolbar_back(self) -> None:
        nodes = [
            node
            for node in self.device.snapshot().iter("node")
            if node.get("package") == PACKAGE
        ]
        buttons = []
        for node in nodes:
            bounds = BOUNDS.fullmatch(node.get("bounds", ""))
            if bounds and node.get("clickable") == "true":
                left, top, right, bottom = map(int, bounds.groups())
                if (
                    left < 160
                    and 80 <= top < 300
                    and right - left < 220
                    and bottom - top < 220
                ):
                    buttons.append(node)
        if not buttons:
            raise FlowError("android_toolbar_back_missing")
        self.tap_node(
            min(
                buttons,
                key=lambda node: int(BOUNDS.fullmatch(node.get("bounds", "")).group(2)),
            )
        )

    def reveal_id(self, identifier: str, *, label: str | None = None) -> None:
        for _ in range(12):
            if label is None and self.device.nodes(identifier):
                return
            nodes = [
                node
                for node in self.device.snapshot().iter("node")
                if node.get("package") == PACKAGE
            ]
            if not nodes:
                raise FlowError("android_model_app_not_foreground")
            if label is not None and any(
                label in node.get("text", "") or label in node.get("content-desc", "")
                for node in nodes
            ):
                return
            bounds = BOUNDS.fullmatch(
                max(nodes, key=lambda node: self.area(node.get("bounds", ""))).get(
                    "bounds", ""
                )
            )
            if bounds is None:
                raise FlowError("android_model_bounds_missing")
            left, top, right, bottom = map(int, bounds.groups())
            x = str((left + right) // 2)
            self.device.command(
                "shell",
                "input",
                "swipe",
                x,
                str(top + (bottom - top) * 4 // 5),
                x,
                str(top + (bottom - top) // 3),
                "350",
            )
        raise FlowError("android_model_control_offscreen")

    def screenshot(self, path: Path) -> None:
        # Screenshots are requested only after key/password dialogs have closed.
        with path.open("wb") as output:
            result = subprocess.run(
                [
                    str(self.device.adb),
                    "-s",
                    self.device.serial,
                    "exec-out",
                    "screencap",
                    "-p",
                ],
                stdout=output,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=30,
            )
        if result.returncode or path.stat().st_size < 100:
            raise FlowError("android_model_screenshot_failed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--adb", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--read-only", action="store_true")
    parser.add_argument("--expected-job-id", action="append", default=[])
    args = parser.parse_args()
    expected_job_ids = {str(UUID(value)) for value in args.expected_job_id}
    if expected_job_ids and not args.read_only:
        raise SystemExit(
            "Expected job references are only supported in read-only mode."
        )
    apk = args.apk.resolve()
    root = run_root(args.run_id)
    ledger = read_ledger(root, args.run_id)
    settings = load_settings(root / "runtime.env")
    if (not args.read_only and settings.model_execution_mode != "fake") or ledger[
        "state"
    ] != "serving":
        raise SystemExit("A running isolated fake model run is required.")
    if apk.parent != APK_ROOT or not _release_apk(apk) or not args.adb.is_file():
        raise SystemExit("The controlled dev release APK and adb are required.")
    output = args.output.resolve()
    evidence_root = (
        Path(__file__).resolve().parents[3] / "artifacts/model-settings-ui"
    ).resolve()
    if output.parent != evidence_root or output.exists():
        raise SystemExit("Choose a new safe model UI report path.")
    ids = json.loads(REGISTRY.read_text(encoding="utf-8"))["static"]
    device = Device(args.adb.resolve(), args.device, ids, args.run_id)
    page = ModelPage(device)
    steps: dict[str, str] = {}
    stage = "setup"
    document = {
        "run_id": args.run_id,
        "device": args.device,
        "variant": "dev-release-read-only-real-api"
        if args.read_only
        else "dev-release-fake-provider-real-api",
        "status": "running",
        "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "steps": steps,
    }
    output.parent.mkdir(parents=True, exist_ok=True)

    def step(name: str):
        steps[name] = "passed"
        output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    try:
        _api_identity(args.run_id)
        device.command("install", "-r", str(apk), timeout=120)
        device.command("shell", "am", "force-stop", PACKAGE)
        device.command("shell", "am", "start", "-n", f"{PACKAGE}/{ACTIVITY}")
        device.enable_ime()
        _login_page(device, ids)
        stage = "service_identity"
        page.tap("服务地址")
        device.wait_node(ids["environmentPage"])
        target = f"haruka-test-{args.run_id}"
        current = device.snapshot()
        if not any(
            target in node.get("text", "") or target in node.get("content-desc", "")
            for node in current.iter("node")
        ):
            addresses = [
                node
                for node in current.iter("node")
                if node.get("class") == "android.widget.EditText"
                and node.get("package") == PACKAGE
            ]
            if len(addresses) != 1:
                raise FlowError("android_model_service_address_missing")
            page.tap_node(addresses[0])
            device.command(
                "shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A"
            )
            device.command("shell", "input", "keyevent", "KEYCODE_DEL")
            device.private_input("http://10.0.2.2:18081")
            device.command("shell", "input", "keyevent", "KEYCODE_BACK")
            page.tap("检查地址")
            page.node(target)
            page.tap("退出并使用此服务")
        else:
            page.tap("返回登录")
        if not device.nodes(ids["loginPage"]):
            page.tap("我的")
            page.reveal_id("", label="安全与账号")
            page.tap("安全与账号")
            page.reveal_id("", label="退出登录")
            page.tap("退出登录")
        device.wait_node(ids["loginPage"])
        step("bound_fake_run_instance_via_ui")
        stage = "owned_actor_login"
        actor = json.loads((root / "model-ui-actor.json").read_text(encoding="utf-8"))
        email, password = actor["email"], actor["password"]
        stage = "login"
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], password)
        device.tap(ids["loginSubmit"])
        page.tap("跳过")
        page.tap("我的")
        page.reveal_id("", label="个人模型")
        step("owned_actor_login_ui")
        stage = "credential_dialog"
        page.tap("个人模型")
        device.wait_node(ids["modelCredentialAdd"])
        if args.read_only:
            page.toolbar_back()
            page.reveal_id("", label="任务进度")
            page.tap("任务进度")
            if expected_job_ids:
                page.node("刷新任务状态")
                time.sleep(1)
            else:
                page.reveal_id("", label="已完成")
                page.node("已完成", timeout=60)
            page.screenshot(evidence_root / "formal-android-read-results.png")
            matched: set[str] = set()
            for index in range(16):
                snapshot = device.snapshot()
                visible = {
                    reference
                    for reference in expected_job_ids
                    if any(
                        reference in node.get("text", "")
                        or reference in node.get("content-desc", "")
                        for node in snapshot.iter("node")
                    )
                }
                if visible - matched:
                    page.screenshot(
                        evidence_root / f"formal-android-job-results-{index}.png"
                    )
                matched.update(visible)
                if matched == expected_job_ids:
                    break
                device.command(
                    "shell", "input", "swipe", "540", "1950", "540", "850", "350"
                )
                time.sleep(0.4)
            if matched != expected_job_ids:
                raise FlowError("android_expected_job_result_not_visible")
            document["read_job_ids"] = sorted(matched)
            step("existing_persisted_results_read_no_submission")
            page.toolbar_back()
            page.reveal_id("", label="模型用量")
            page.tap("模型用量")
            page.reveal_id(ids["modelUsageModelFilter"])
            device.fill(ids["modelUsageModelFilter"], "google/gemini-2.5-flash")
            device.command("shell", "input", "keyevent", "KEYCODE_HOME")
            device.command("shell", "am", "start", "-n", f"{PACKAGE}/{ACTIVITY}")
            device.wait_node(ids["modelUsageModelFilter"])
            if (
                device.nodes(ids["modelUsageModelFilter"])[0].get("text")
                != "google/gemini-2.5-flash"
            ):
                raise FlowError("android_usage_draft_changed")
            device.tap(ids["modelUsageApply"])
            page.node("供应商调用")
            page.screenshot(evidence_root / "formal-android-read-usage.png")
            step("usage_keyboard_foreground_draft_preserved")
            document["status"] = "passed"
            return 0
        device.tap(ids["modelCredentialAdd"])
        device.fill(ids["modelCredentialKey"], "fake-model-fixture-only")
        page.tap("取消")
        device.wait_node(ids["modelCredentialAdd"])
        step("key_dialog_input_cancel")
        device.tap(ids["modelCredentialAdd"])
        device.fill(ids["modelCredentialKey"], "fake-model-fixture-only")
        device.tap(ids["modelCredentialSave"])
        page.node("已保存")
        page.screenshot(evidence_root / "formal-android-model.png")
        step("credential_saved_without_test")
        for capability in ("文本", "视觉", "朗读"):
            stage = f"capability_{capability}"
            page.reveal_id(ids["modelTestOpen"])
            device.tap(ids["modelTestOpen"])
            page.node("确认单项能力测试")
            if capability != "文本":
                device.tap(ids["modelTestCapability"])
                page.tap(capability)
                page.tap("取消")
                step(f"select_{capability}_cancel_without_call")
                continue
            device.tap(ids["modelTestConfirm"])
            page.node("已持久受理")
            page.reveal_id("", label=f"{capability} · openrouter")
            page.node(f"{capability} · openrouter", timeout=60)
            page.node("已完成", timeout=60)
            step(f"explicit_{capability}_fake_test_result")
        page.screenshot(evidence_root / "formal-android-test-result.png")
        stage = "usage"
        page.toolbar_back()
        page.reveal_id("", label="模型用量")
        page.tap("模型用量")
        page.reveal_id(ids["modelUsageModelFilter"])
        device.fill(ids["modelUsageModelFilter"], "google/gemini-2.5-flash")
        device.command("shell", "input", "keyevent", "KEYCODE_HOME")
        device.command("shell", "am", "start", "-n", f"{PACKAGE}/{ACTIVITY}")
        device.wait_node(ids["modelUsageModelFilter"])
        device.tap(ids["modelUsageApply"])
        page.node("模型用量")
        page.node("供应商调用")
        page.screenshot(evidence_root / "formal-android-usage.png")
        step("usage_filter_keyboard")
        document["status"] = "passed"
        return 0
    except Exception as error:  # noqa: BLE001 - safe CLI boundary prevents printing private UI values
        document["status"] = "failed"
        document["failed_step"] = stage
        if isinstance(error, FlowError):
            document["error_code"] = str(error)
        sys.stderr.write("Android model flow failed; inspect safe report.\n")
        return 1
    finally:
        device.command("shell", "rm", "-f", device.remote_xml)
        device.restore_ime()
        output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
