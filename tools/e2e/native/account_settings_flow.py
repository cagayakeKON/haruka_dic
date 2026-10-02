"""Operate the isolated dev Android account UI in resumable, bounded sections."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
from datetime import UTC, datetime
from pathlib import Path

from dev.isolated_app_run import read_ledger, run_root
from tools.e2e.native.android_app_flow import (
    BOUNDS,
    PACKAGE,
    REGISTRY,
    Device,
    FlowError,
    _api_identity,
)
from tools.e2e.native.model_settings_flow import ModelPage


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--adb", required=True, type=Path)
    parser.add_argument("--device", choices=["emulator-5554"], required=True)
    parser.add_argument(
        "--section",
        choices=[
            "bootstrap",
            "current-main",
            "cache-cancel",
            "profile-keyboard",
            "profile-persist",
            "profile-replace",
            "profile-save-draft",
            "profile-retry",
            "avatar-cancel",
            "collection-read",
            "preferences-read",
            "appearance-retry",
            "language-reload-conflict",
        ],
        required=True,
    )
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = run_root(args.run_id)
    if read_ledger(root, args.run_id)["state"] != "serving":
        raise FlowError("account_ui_owned_runtime_not_serving")
    _api_identity(args.run_id)
    ids = json.loads(REGISTRY.read_text(encoding="utf-8"))["static"]
    device = Device(args.adb, args.device, ids, args.run_id)
    page = ModelPage(device)
    steps: list[str] = []
    step_times: list[dict[str, str]] = []
    document: dict[str, object] = {
        "run_id": args.run_id,
        "device": args.device,
        "avd": "Haruka_B0_API34",
        "section": args.section,
        "result": "running",
        "started_at": datetime.now(UTC).isoformat(),
        "steps": steps,
        "step_times": step_times,
        "supplier_actions": "none; this flow contains no model submission action",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save() -> None:
        args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    def passed(name: str) -> None:
        steps.append(name)
        step_times.append({"step": name, "at": datetime.now(UTC).isoformat()})
        save()

    def open_profile() -> None:
        page.node("本机缓存")
        candidates = []
        for node in device.snapshot().iter("node"):
            if node.get("package") != PACKAGE or node.get("clickable") != "true":
                continue
            bounds = BOUNDS.fullmatch(node.get("bounds", ""))
            if bounds:
                left, top, right, bottom = map(int, bounds.groups())
                if 180 < top < 700 and right - left > 700 and bottom - top > 120:
                    candidates.append((top, node))
        if not candidates:
            raise FlowError("account_ui_mobile_profile_header_missing")
        page.tap_node(min(candidates, key=lambda row: row[0])[1])
        page.node("个人资料")

    save()
    try:
        device.enable_ime()
        if args.section == "bootstrap":
            device.wait_node(ids["loginPage"])
            page.tap("服务地址")
            device.wait_node(ids["environmentPage"])
            target = f"haruka-test-{args.run_id}"
            current = device.snapshot()
            if not any(
                target in n.get("text", "") or target in n.get("content-desc", "")
                for n in current.iter("node")
            ):
                fields = [
                    n
                    for n in current.iter("node")
                    if n.get("package") == PACKAGE and n.get("class") == "android.widget.EditText"
                ]
                if len(fields) != 1:
                    raise FlowError("account_ui_service_field_not_unique")
                page.tap_node(fields[0])
                device.command("shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A")
                device.command("shell", "input", "keyevent", "KEYCODE_DEL")
                device.private_input("http://10.0.2.2:18081")
                device.command("shell", "input", "keyevent", "KEYCODE_BACK")
                page.tap("检查地址")
                page.node(target)
                page.tap("退出并使用此服务")
            else:
                page.tap("返回登录")
            device.wait_node(ids["loginPage"])
            passed("same_owned_instance_probe_and_bind_via_ui")
            actor = json.loads((root / "account-ui-actor-a.json").read_text(encoding="utf-8"))
            device.fill(ids["loginEmail"], actor["email"])
            device.fill(ids["loginPassword"], actor["password"])
            device.tap(ids["loginSubmit"])
            page.node("跳过")
            page.tap("跳过")
            page.node("本机缓存")
            passed("existing_actual_ui_actor_login_optional_guide_skip")
        elif args.section == "current-main":
            page.node("我的")
            page.node("本机缓存")
            passed("actual_current_mobile_main_visible_after_original_actor_login")
        elif args.section == "profile-keyboard":
            page.toolbar_back()
            open_profile()
            passed("actual_mobile_profile_header_opens_profile")
            fields = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.EditText"
            ]
            if not fields:
                raise FlowError("account_ui_profile_field_missing")
            passed("loaded_profile_before_keyboard_lifecycle_window")
            page.tap_node(fields[0])
            device.command("shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A")
            device.command("shell", "input", "keyevent", "KEYCODE_DEL")
            device.private_input("Native draft")
            page.node("Native draft")
            if "mInputShown=true" not in device.command("shell", "dumpsys", "input_method"):
                raise FlowError("account_ui_profile_keyboard_missing")
            page.screenshot(args.output.with_name(args.output.stem + "-keyboard.png"))
            passed("actual_keyboard_typing_keeps_profile_draft")
            device.command("shell", "input", "keyevent", "KEYCODE_HOME")
            device.command(
                "shell",
                "am",
                "start",
                "-n",
                f"{PACKAGE}/app.haruka.dictionary.MainActivity",
            )
            page.node("Native draft")
            passed("actual_background_foreground_keeps_unsaved_profile_draft")
            device.command("shell", "input", "keyevent", "KEYCODE_BACK")
        elif args.section == "language-reload-conflict":
            page.toolbar_back()
            page.tap("语言选项")
            page.reveal_id("", label="保存语言选项")
            page.tap("保存语言选项")
            page.node("内容已更新，请重新加载")
            page.screenshot(args.output.with_name(args.output.stem + "-conflict.png"))
            page.tap("重试加载")
            active = page.node("当前学习语言")
            if "日本語" not in (active.get("content-desc", "") + active.get("text", "")):
                raise FlowError("account_ui_current_language_not_web_saved")
            passed("actual_explicit_cas_refresh_reads_saved_active_language")
            page.screenshot(args.output.with_name(args.output.stem + "-active.png"))
            for _ in range(3):
                device.command("shell", "input", "swipe", "540", "650", "540", "1900", "450")
            explanation = page.node("解释语言")
            if "简体中文" not in (
                explanation.get("content-desc", "") + explanation.get("text", "")
            ):
                raise FlowError("account_ui_explanation_language_not_web_saved")
            native = page.node("简体中文")
            if native.get("checked") != "true":
                raise FlowError("account_ui_native_language_not_web_saved")
            passed("native_checked_mother_and_independent_explanation_match_saved_values")
        elif args.section == "appearance-retry":
            page.node("内容已更新，请重新加载")
            page.tap("重试加载")
            page.node("外观设置")
            switches = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.Switch"
            ]
            if len(switches) != 1:
                raise FlowError("account_ui_motion_switch_not_unique")
            original = switches[0].get("checked")
            passed("actual_native_settings_conflict_explicit_retry")
            page.tap_node(switches[0])
            page.node("已保存")
            changed = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.Switch"
            ]
            if len(changed) != 1 or changed[0].get("checked") == original:
                raise FlowError("account_ui_motion_toggle_not_reflected")
            passed("actual_native_motion_toggle_acknowledged")
            page.screenshot(args.output.with_name(args.output.stem + "-motion.png"))
            page.tap_node(changed[0])
            page.node("已保存")
            restored = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.Switch"
            ]
            if len(restored) != 1 or restored[0].get("checked") != original:
                raise FlowError("account_ui_motion_restore_not_reflected")
            passed("native_motion_original_value_restored")
        elif args.section == "preferences-read":
            page.tap("我的")
            page.tap("语言选项")
            page.node("解释语言")
            page.node("简体中文")
            page.node("日本語")
            page.screenshot(args.output.with_name(args.output.stem + "-language.png"))
            passed("native_reads_actual_web_saved_language_fields")
            page.toolbar_back()
            page.tap("外观设置")
            page.node("跟随系统")
            switches = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.Switch"
            ]
            if len(switches) != 1:
                raise FlowError("account_ui_motion_switch_not_unique")
            original = switches[0].get("checked")
            page.tap_node(switches[0])
            page.node("已保存")
            changed = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.Switch"
            ]
            if len(changed) != 1 or changed[0].get("checked") == original:
                raise FlowError("account_ui_motion_toggle_not_reflected")
            passed("actual_native_motion_toggle_acknowledged")
            page.screenshot(args.output.with_name(args.output.stem + "-motion.png"))
            page.tap_node(changed[0])
            page.node("已保存")
            restored = [
                n
                for n in device.snapshot().iter("node")
                if n.get("package") == PACKAGE and n.get("class") == "android.widget.Switch"
            ]
            if len(restored) != 1 or restored[0].get("checked") != original:
                raise FlowError("account_ui_motion_restore_not_reflected")
            passed("native_motion_original_value_restored")
        elif args.section == "collection-read":
            page.node("我的")
            page.tap("词本")
            page.node("空")
            page.screenshot(args.output.with_name(args.output.stem + "-list.png"))
            passed("actual_native_existing_owner_collection_visible")
            page.tap("空")
            page.node("天空")
            page.screenshot(args.output.with_name(args.output.stem + "-dialog.png"))
            passed("actual_native_existing_word_dialog_opened")
            device.command("shell", "input", "keyevent", "KEYCODE_BACK")
            page.node("空")
            passed("dialog_back_preserves_existing_collection")
        elif args.section == "avatar-cancel":
            page.node("个人资料")
            for _ in range(10):
                if "mInputShown=true" not in device.command("shell", "dumpsys", "input_method"):
                    break
                device.command("shell", "input", "keyevent", "KEYCODE_BACK")
                time.sleep(0.4)
            page.node("当前头像")
            page.tap("更换头像")
            picker = device.snapshot()
            if not any(
                n.get("package", "") not in {PACKAGE, "com.android.systemui", ""}
                for n in picker.iter("node")
            ):
                raise FlowError("account_ui_native_avatar_picker_missing")
            page.screenshot(args.output.with_name(args.output.stem + "-picker.png"))
            passed("actual_android_system_photo_picker_opened")
            device.command("shell", "input", "keyevent", "KEYCODE_BACK")
            page.node("个人资料")
            page.node("当前头像")
            page.node("删除头像")
            passed("picker_cancel_keeps_existing_private_avatar")
        elif args.section in {
            "profile-persist",
            "profile-replace",
            "profile-save-draft",
            "profile-retry",
        }:
            if args.section == "profile-persist":
                open_profile()
            else:
                page.node("个人资料")
            fields = [
                node
                for node in device.snapshot().iter("node")
                if node.get("package") == PACKAGE and node.get("class") == "android.widget.EditText"
            ]
            if not fields:
                raise FlowError("account_ui_profile_field_missing")
            preserve_draft = args.section in {"profile-save-draft", "profile-retry"}
            if args.section == "profile-retry":
                page.node("内容已更新，请重新加载")
                page.screenshot(args.output.with_name(args.output.stem + "-conflict.png"))
                page.tap("重试加载")
                passed("visible_revision_conflict_explicit_retry_preserves_draft")
            if not preserve_draft:
                page.tap_node(fields[0])
            if args.section == "profile-replace":
                existing = fields[0].get("text", "")
                device.command("shell", "input", "keyevent", "KEYCODE_MOVE_END")
                device.command(
                    "shell",
                    "input",
                    "keyevent",
                    *(["KEYCODE_DEL"] * (len(existing) + 10)),
                )
            elif not preserve_draft:
                device.command("shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A")
                device.command("shell", "input", "keyevent", "KEYCODE_DEL")
            if not preserve_draft:
                device.private_input("Native persisted")
            page.node("Native persisted")
            if args.section in {
                "profile-replace",
                "profile-save-draft",
                "profile-retry",
            }:
                edited = [
                    n
                    for n in device.snapshot().iter("node")
                    if n.get("package") == PACKAGE and n.get("class") == "android.widget.EditText"
                ]
                if not edited or edited[0].get("text") != "Native persisted":
                    raise FlowError("account_ui_profile_exact_replacement_failed")
                passed("actual_keyboard_exact_name_replacement_before_save")
            for _ in range(10):
                if "mInputShown=true" not in device.command("shell", "dumpsys", "input_method"):
                    break
                device.command("shell", "input", "keyevent", "KEYCODE_BACK")
                time.sleep(0.4)
            else:
                raise FlowError("account_ui_profile_keyboard_did_not_close")
            page.reveal_id("", label="保存资料")
            page.tap("保存资料")
            page.node("已保存")
            passed("actual_native_profile_save_acknowledged")
            page.toolbar_back()
            page.node("Native persisted")
            open_profile()
            page.node("Native persisted")
            passed("native_saved_name_visible_after_return_and_reopen")
        else:
            page.node("我的")
            page.tap("我的")
            page.reveal_id("", label="本机缓存")
            page.tap("本机缓存")
            page.reveal_id("", label="清除此账号本机缓存")
            page.node("清除此账号本机缓存")
            passed("loaded_cache_before_dialog_window")
            page.tap("清除此账号本机缓存")
            page.node("清除此账号本机缓存？")
            passed("existing_cache_dialog_open")
            page.tap("取消")
            page.node("本机可用")
            passed("visible_cache_content_after_cancel")
        screenshot = args.output.with_suffix(".png")
        page.screenshot(screenshot)
        document["screenshot"] = screenshot.name
        document["screenshot_sha256"] = hashlib.sha256(screenshot.read_bytes()).hexdigest()
        document["result"] = "passed"
        document["ended_at"] = datetime.now(UTC).isoformat()
        save()
        return 0
    except FlowError as error:
        document["result"] = "failed"
        document["error_code"] = str(error)
        screenshot = args.output.with_name(args.output.stem + "-failed.png")
        try:
            page.screenshot(screenshot)
            document["screenshot"] = screenshot.name
        except FlowError:
            document["screenshot_failure"] = True
        save()
        return 1
    finally:
        device.restore_ime()


if __name__ == "__main__":
    raise SystemExit(main())
