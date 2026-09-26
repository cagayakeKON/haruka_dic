"""Verify password recovery through the installed Android app and local mail."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import time
import urllib.error
import urllib.request
from pathlib import Path

from dev.infra import is_object
from dev.isolated_app_run import read_ledger, run_root, write_private
from dev.local_smtp_capture import (
    ALLOWED_RECIPIENT,
    MailboxError,
    guarded_spool,
    message_link,
)
from tools.e2e.native.android_app_flow import (
    REGISTRY,
    Device,
    FlowError,
    _string_map,
)

ROOT = Path(__file__).resolve().parents[3]
RELEASE_RECORD = ROOT / "frontend/build/android-release-record.json"
RUN = re.compile(r"[0-9a-f]{32}\Z")


def _read_actor(run_id: str) -> tuple[str, str]:
    path = run_root(run_id) / "windows-actor.secret"
    if path.is_symlink() or not path.is_file():
        raise FlowError("android_recovery_actor_missing")
    value: object = json.loads(path.read_text(encoding="utf-8"))
    if not is_object(value):
        raise FlowError("android_recovery_actor_invalid")
    email = value.get("email")
    password = value.get("password")
    if (
        value.get("run_id") != run_id
        or not isinstance(email, str)
        or ALLOWED_RECIPIENT.fullmatch(email) is None
        or not isinstance(password, str)
        or not password.isascii()
    ):
        raise FlowError("android_recovery_actor_invalid")
    return email, password


def _verify_apk(run_id: str, apk: Path) -> str:
    if apk.is_symlink() or not apk.is_file() or not RELEASE_RECORD.is_file():
        raise FlowError("android_recovery_apk_missing")
    record: object = json.loads(RELEASE_RECORD.read_text(encoding="utf-8"))
    if not is_object(record):
        raise FlowError("android_recovery_build_record_invalid")
    hasher = hashlib.sha256()
    with apk.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    if (
        record.get("run_id") != run_id
        or record.get("instance_id") != f"haruka-test-{run_id}"
        or record.get("api_base_url") != "http://10.0.2.2:18081"
        or record.get("exit_code") != 0
        or record.get("apk_sha256") != digest
    ):
        raise FlowError("android_recovery_apk_identity_mismatch")
    return digest


def _save_report(path: Path, document: dict[str, object]) -> None:
    # This report contains only fixed status codes and artifact hashes.
    path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _new_reset_link(run_id: str, email: str, previous_names: set[str]) -> str:
    spool = guarded_spool(run_root(run_id) / "mail")
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        for path in sorted(spool.glob("*.json"), reverse=True):
            if path.name in previous_names or path.is_symlink():
                continue
            message = path.with_suffix(".eml")
            if message.is_symlink():
                continue
            try:
                metadata: object = json.loads(path.read_text(encoding="utf-8"))
                if (
                    not is_object(metadata)
                    or metadata.get("recipient") != email.lower()
                ):
                    continue
                link = message_link(message.read_bytes(), "reset")
                if link is not None:
                    return link
            except (OSError, ValueError):
                continue
        time.sleep(0.2)
    raise FlowError("android_new_reset_mail_not_captured")


def _old_password_http_status(email: str, password: str) -> int:
    request = urllib.request.Request(
        "http://127.0.0.1:18081/api/v1/auth/native/login",
        data=json.dumps(
            {"email": email, "password": password, "platform": "android"}
        ).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--adb", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not RUN.fullmatch(args.run_id) or not re.fullmatch(r"emulator-\d+", args.device):
        raise SystemExit("An isolated run and explicit emulator are required.")
    if read_ledger(run_root(args.run_id), args.run_id)["state"] != "serving":
        raise SystemExit("The isolated run is not serving.")
    apk = args.apk.resolve()
    digest = _verify_apk(args.run_id, apk)
    email, old_password = _read_actor(args.run_id)
    registry: object = json.loads(REGISTRY.read_text(encoding="utf-8"))
    if not is_object(registry) or not _string_map(registry.get("static")):
        raise SystemExit("The UI identifier registry is invalid.")
    ids = registry["static"]
    assert isinstance(ids, dict)
    required = (
        "homePage",
        "loginPage",
        "accountPage",
        "accountNavigation",
        "accountSignOut",
        "loginRecoveryLink",
        "recoveryRequestPage",
        "recoveryRequestEmail",
        "recoveryRequestSubmit",
        "recoveryAcceptedResetLink",
        "recoveryCompletePage",
        "recoveryCompleteToken",
        "recoveryCompletePassword",
        "recoveryCompleteConfirm",
        "recoveryCompleteSubmit",
        "authResultPage",
        "authBackLogin",
        "loginEmail",
        "loginPassword",
        "loginSubmit",
        "authFormError",
    )
    if any(not isinstance(ids.get(name), str) for name in required):
        raise SystemExit("The recovery controls are not registered.")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise SystemExit("The report already exists.")
    report: dict[str, object] = {
        "status": "running",
        "run_id": args.run_id,
        "device": args.device,
        "apk_sha256": digest,
        "driver_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "ui_registry_sha256": hashlib.sha256(REGISTRY.read_bytes()).hexdigest(),
        "scope": "android-password-recovery-only",
        "steps": {},
        "old_password_rejected": False,
        "new_password_login_succeeded": False,
    }
    with output.open("x", encoding="utf-8"):
        pass
    _save_report(output, report)
    steps = report["steps"]
    assert isinstance(steps, dict)
    device = Device(args.adb, args.device, ids, args.run_id)
    stage = "install"
    try:
        device.command("install", "-r", str(apk), timeout=120)
        steps["installed_final_release"] = "passed"
        _save_report(output, report)
        device.enable_ime()
        device.launch()
        stage = "login_start"
        current = device.wait_any(
            (ids["homePage"], ids["accountPage"], ids["loginPage"]), timeout=60
        )
        if current == ids["homePage"]:
            device.tap(ids["accountNavigation"])
            device.wait_node(ids["accountPage"])
            current = ids["accountPage"]
        if current == ids["accountPage"]:
            device.tap(ids["accountSignOut"])
        device.wait_node(ids["loginPage"], timeout=60)
        steps["started_from_login"] = "passed"
        _save_report(output, report)

        stage = "recovery_request"
        spool = guarded_spool(run_root(args.run_id) / "mail")
        previous_mail_names = {path.name for path in spool.glob("*.json")}
        device.tap(ids["loginRecoveryLink"])
        device.wait_node(ids["recoveryRequestPage"])
        device.fill(ids["recoveryRequestEmail"], email)
        device.tap(ids["recoveryRequestSubmit"])
        device.wait_node(ids["recoveryAcceptedResetLink"], timeout=60)
        steps["recovery_request_accepted"] = "passed"
        _save_report(output, report)

        stage = "recovery_reset"
        reset_link = _new_reset_link(args.run_id, email, previous_mail_names)
        new_password = "Dd6" + secrets.token_hex(18)
        device.tap(ids["recoveryAcceptedResetLink"])
        device.wait_node(ids["recoveryCompletePage"])
        device.fill(ids["recoveryCompleteToken"], reset_link)
        device.fill(ids["recoveryCompletePassword"], new_password)
        device.fill(ids["recoveryCompleteConfirm"], new_password)
        write_private(
            run_root(args.run_id) / "recovered-actor.secret",
            json.dumps(
                {"run_id": args.run_id, "email": email, "password": new_password}
            )
            + "\n",
        )
        report["recovered_actor_written_before_submission"] = True
        _save_report(output, report)
        device.tap(ids["recoveryCompleteSubmit"])
        device.wait_node(ids["authResultPage"], timeout=60)
        steps["reset_completed"] = "passed"
        _save_report(output, report)

        stage = "old_password_rejection"
        device.tap(ids["authBackLogin"])
        device.wait_node(ids["loginPage"])
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], old_password)
        device.tap(ids["loginSubmit"])
        try:
            outcome = device.wait_any(
                (ids["authFormError"], ids["accountPage"]), timeout=20
            )
        except FlowError as error:
            if str(error) != "android_page_missing":
                raise
            device.wait_node(ids["loginPage"])
            http_status = _old_password_http_status(email, old_password)
            report["old_password_host_http_status"] = http_status
            if http_status == 401:
                report["old_password_rejected"] = True
                steps["old_password_rejected"] = (
                    "passed_host_native_http_401_and_android_login_page"
                )
            else:
                steps["old_password_rejected"] = "unverified_ui_error_not_located"
        else:
            if outcome != ids["authFormError"]:
                raise FlowError("android_old_password_was_accepted")
            report["old_password_rejected"] = True
            steps["old_password_rejected"] = "passed"
        _save_report(output, report)

        stage = "new_password_login"
        device.fill(ids["loginPassword"], new_password)
        device.tap(ids["loginSubmit"])
        device.wait_node(ids["accountPage"], timeout=60)
        report["new_password_login_succeeded"] = True
        steps["new_password_login"] = "passed"
        _save_report(output, report)
        report["status"] = "passed" if report["old_password_rejected"] else "partial"
    except (FlowError, MailboxError, OSError, ValueError, KeyError) as error:
        report["status"] = "failed"
        report["failed_stage"] = stage
        report["error_code"] = (
            str(error)
            if isinstance(error, FlowError)
            else "android_recovery_unexpected"
        )
    finally:
        try:
            device.restore_ime()
            device.command("shell", "am", "force-stop", "app.haruka.dictionary.dev")
            report["device_cleanup"] = "passed"
        except FlowError:
            report["device_cleanup"] = "failed"
        _save_report(output, report)
    print(json.dumps({"status": report["status"], "report": str(output)}))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
