"""Drive the installed Android app through its public UI and isolated mailbox."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import hashlib
import json
import re
import secrets
import shlex
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import TypeGuard
from urllib.parse import urlsplit
from uuid import UUID as ParsedUUID
from uuid import uuid4

from app.core.settings import load_settings
from app.maintenance.settings import create_maintenance_engine
from sqlalchemy import text

from dev import local_api_fault_proxy
from dev.infra import is_object
from dev.isolated_app_run import (
    isolated_maintenance,
    read_ledger,
    run_root,
    seed_source,
    write_private,
)
from dev.local_smtp_capture import extract_link, guarded_spool

ROOT = Path(__file__).resolve().parents[3]
REGISTRY = ROOT / "frontend/config/ui_test_ids.json"
REPORTS = ROOT / "artifacts/dev"
APK_ROOT = (ROOT / "frontend/build/app/outputs/flutter-apk").resolve()
RELEASE_METADATA = (
    ROOT / "frontend/build/app/outputs/apk/dev/release/output-metadata.json"
)
PACKAGE = "app.haruka.dictionary.dev"
ACTIVITY = "app.haruka.dictionary.MainActivity"
UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")
RUN = re.compile(r"[0-9a-f]{32}\Z")
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\Z")


def _string_map(value: object) -> TypeGuard[dict[str, str]]:
    return is_object(value) and all(isinstance(item, str) for item in value.values())


def _is_array(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


class FlowError(Exception):
    """A fixed diagnostic code; never includes UI text or secrets."""


class Device:
    def __init__(self, adb: Path, serial: str, ids: dict[str, str], run_id: str):
        self.adb = adb
        self.serial = serial
        self.ids = ids
        self.remote_xml = f"/sdcard/haruka-ui-{run_id[:12]}.xml"
        self.previous_ime: str | None = None

    def command(self, *arguments: str, timeout: int = 30) -> str:
        try:
            return subprocess.run(
                [str(self.adb), "-s", self.serial, *arguments],
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=timeout,
            ).stdout
        except (OSError, subprocess.SubprocessError) as error:
            # Only fixed command names are diagnostic; arguments can contain
            # private paths or UI input and must never enter the report.
            operation = arguments[0] if arguments else "unknown"
            if operation == "shell" and len(arguments) > 1:
                operation = {
                    "uiautomator": "semantics_dump",
                    "cat": "semantics_read",
                    "rm": "semantics_cleanup",
                    "input": "system_input",
                    "dumpsys": "ime_state",
                    "am": "activity",
                    "settings": "ime_settings",
                }.get(arguments[1], "shell")
            if operation not in {
                "install",
                "semantics_dump",
                "semantics_read",
                "semantics_cleanup",
                "system_input",
                "ime_state",
                "activity",
                "ime_settings",
                "shell",
            }:
                operation = "other"
            raise FlowError(f"android_command_failed_{operation}") from error

    def private_input(self, value: str) -> None:
        # The synthetic credential or captured action link is supplied on stdin;
        # neither host argv, report, nor ordinary stdout receives its contents.
        if not value.isascii() or "\n" in value or "\r" in value:
            raise FlowError("unsupported_android_input")
        process = subprocess.Popen(
            [str(self.adb), "-s", self.serial, "shell"],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
        )
        try:
            process.communicate(
                "set -e\ninput text "
                + shlex.quote(value.replace(" ", "%s"))
                + "\nexit\n",
                timeout=30,
            )
        except subprocess.TimeoutExpired as error:
            process.kill()
            process.communicate()
            raise FlowError("android_input_timeout") from error
        if process.returncode != 0:
            raise FlowError("android_input_failed")

    def snapshot(self) -> ET.Element:
        for attempt in range(3):
            try:
                self.command("shell", "uiautomator", "dump", self.remote_xml)
                contents = self.command("shell", "cat", self.remote_xml)
                return ET.fromstring(contents)
            except ET.ParseError as error:
                if attempt == 2:
                    raise FlowError("android_semantics_unavailable") from error
            except FlowError as error:
                if (
                    str(error)
                    not in {
                        "android_command_failed_semantics_dump",
                        "android_command_failed_semantics_read",
                    }
                    or attempt == 2
                ):
                    raise
            finally:
                self.command("shell", "rm", "-f", self.remote_xml)
            time.sleep(0.3)
        raise AssertionError("bounded Android UI snapshot did not complete")

    def nodes(self, identifier: str) -> list[ET.Element]:
        return [
            node
            for node in self.snapshot().iter("node")
            if node.get("resource-id") == identifier and node.get("package") == PACKAGE
        ]

    def wait_node(self, identifier: str, *, timeout: float = 30) -> ET.Element:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            matches = self.nodes(identifier)
            if len(matches) == 1:
                return matches[0]
            if len(matches) > 1:
                raise FlowError("android_semantics_not_unique")
            time.sleep(0.4)
        raise FlowError("android_semantics_missing")

    def wait_any(self, identifiers: tuple[str, ...], *, timeout: float = 40) -> str:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = {
                identifier
                for node in self.snapshot().iter("node")
                for identifier in identifiers
                if node.get("resource-id") == identifier
                and node.get("package") == PACKAGE
            }
            if len(found) == 1:
                return next(iter(found))
            if len(found) > 1:
                raise FlowError("android_page_ambiguous")
            time.sleep(0.4)
        raise FlowError("android_page_missing")

    def tap(self, identifier: str) -> None:
        node = self.wait_node(identifier)
        if node.get("enabled") == "false":
            raise FlowError("android_control_disabled")
        bounds = BOUNDS.fullmatch(node.get("bounds", ""))
        if bounds is None:
            raise FlowError("android_semantics_bounds_missing")
        left, top, right, bottom = map(int, bounds.groups())
        if left >= right or top >= bottom:
            raise FlowError("android_semantics_bounds_invalid")
        self.command(
            "shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2)
        )

    def fill(self, identifier: str, value: str) -> None:
        self.tap(identifier)
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if "mInputShown=true" in self.command("shell", "dumpsys", "input_method"):
                break
            time.sleep(0.2)
        else:
            raise FlowError("android_soft_keyboard_missing")
        self.command(
            "shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A"
        )
        self.command("shell", "input", "keyevent", "KEYCODE_DEL")
        self.private_input(value)
        self.command("shell", "input", "keyevent", "KEYCODE_BACK")

    def enable_ime(self) -> None:
        previous = self.command(
            "shell", "settings", "get", "secure", "show_ime_with_hard_keyboard"
        ).strip()
        if previous not in {"null", "0", "1"}:
            raise FlowError("android_ime_setting_unknown")
        self.previous_ime = previous
        self.command(
            "shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1"
        )

    def restore_ime(self) -> None:
        if self.previous_ime is None:
            return
        if self.previous_ime == "null":
            self.command(
                "shell", "settings", "delete", "secure", "show_ime_with_hard_keyboard"
            )
        else:
            self.command(
                "shell",
                "settings",
                "put",
                "secure",
                "show_ime_with_hard_keyboard",
                self.previous_ime,
            )
        self.previous_ime = None

    def dynamic(self, template: str) -> str:
        if template.count("{") != 1 or template.count("}") != 1:
            raise FlowError("android_ui_template_invalid")
        prefix, suffix = template.split("{", 1)
        _, end = suffix.split("}", 1)
        candidates = {
            value
            for node in self.snapshot().iter("node")
            if node.get("package") == PACKAGE
            if (value := node.get("resource-id", "")).startswith(prefix)
            and value.endswith(end)
            and UUID.fullmatch(
                value[len(prefix) : len(value) - len(end) if end else None]
            )
        }
        if len(candidates) != 1:
            raise FlowError("android_dynamic_source_ambiguous")
        return next(iter(candidates))

    def wait_dynamic(self, template: str, *, timeout: float = 30) -> str:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                return self.dynamic(template)
            except FlowError as error:
                if str(error) != "android_dynamic_source_ambiguous":
                    raise
            time.sleep(0.4)
        raise FlowError("android_dynamic_source_missing")

    def launch(self) -> None:
        self.command("shell", "am", "start", "-n", f"{PACKAGE}/{ACTIVITY}")

    def restart(self) -> None:
        self.command("shell", "am", "force-stop", PACKAGE)
        self.launch()


class Report:
    def __init__(self, path: Path, run_id: str, serial: str, apk: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = path.open("x", encoding="utf-8", newline="\n")
        self.document: dict[str, object] = {
            "runner": "android-ui-automator",
            "run_id": run_id,
            "serial": serial,
            "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
            "driver_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "ui_registry_sha256": hashlib.sha256(REGISTRY.read_bytes()).hexdigest(),
            "build_variant": "devRelease",
            "variant": "android-release-ui-real-api",
            "case_refs": ["SCF-B1-01", "SCF-B1-02", "SCF-B1-04", "SCF-B1-06"],
            "required_node_status": "not_evaluated_by_this_driver",
            "status": "running",
            "steps": {},
        }
        self.write()

    def write(self) -> None:
        self.stream.seek(0)
        self.stream.truncate()
        json.dump(self.document, self.stream, indent=2, sort_keys=True)
        self.stream.write("\n")
        self.stream.flush()

    def step(self, name: str) -> None:
        steps = self.document["steps"]
        assert isinstance(steps, dict)
        steps[name] = "passed"
        self.write()

    def finish(self, *, passed: bool, failed_step: str | None = None) -> None:
        self.document["status"] = "passed" if passed else "failed"
        if failed_step is not None:
            self.document["failed_step"] = failed_step
        self.write()

    def close(self) -> None:
        self.stream.close()


def _mail_action_origin_matches(link: str, public_origin: str) -> bool:
    if public_origin not in {"http://localhost:18443", "https://localhost:18443"}:
        return False
    parsed = urlsplit(link)
    return (
        f"{parsed.scheme}://{parsed.netloc}" == public_origin
        and parsed.username is None
        and parsed.password is None
        and parsed.path.startswith("/")
    )


def _captured_link(run_id: str, recipient: str, purpose: str) -> str:
    spool = guarded_spool(run_root(run_id) / "mail")
    path = spool / f"android-action-{uuid4().hex}.secret"
    try:
        extract_link(spool, recipient, purpose, path, 90)
        link = path.read_text(encoding="utf-8").strip()
        public_origin = str(
            load_settings(run_root(run_id) / "runtime.env").public_base_url
        ).rstrip("/")
        if not _mail_action_origin_matches(link, public_origin):
            raise FlowError("mail_action_origin_invalid")
        return link
    finally:
        if path.exists():
            path.unlink()


def _api_identity(run_id: str) -> None:
    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:18081/api/v1/meta", timeout=5
        ) as response:
            payload: object = json.load(response)
    except (OSError, ValueError) as error:
        raise FlowError("isolated_api_unavailable") from error
    if not is_object(payload):
        raise FlowError("isolated_api_identity_invalid")
    data = payload.get("data")
    if not is_object(data) or data.get("instance_id") != f"haruka-test-{run_id}":
        raise FlowError("isolated_api_identity_mismatch")


def _fault_receipt(run_id: str, rule_id: str, *, timeout: float = 30) -> None:
    root = run_root(run_id)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for path in root.glob("fault.receipt.*.json"):
            if path.is_symlink() or path.resolve().parent != root:
                raise FlowError("android_fault_receipt_unowned")
            try:
                document: object = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            if (
                is_object(document)
                and document.get("run_id") == run_id
                and document.get("rule_id") == rule_id
            ):
                status = document.get("upstream_status")
                if (
                    document.get("injected") is not True
                    or type(status) is not int
                    or not 200 <= status < 300
                ):
                    raise FlowError("android_collection_fault_not_committed")
                return
        time.sleep(0.2)
    raise FlowError("android_collection_fault_receipt_missing")


async def _single_persisted_collection(run_id: str, email: str) -> str:
    ledger = read_ledger(run_root(run_id), run_id)
    if ledger["state"] != "serving":
        raise FlowError("android_collection_inspection_run_stopped")
    schema = ledger["schema"]
    engine = create_maintenance_engine(isolated_maintenance(schema))
    try:
        async with engine.connect() as connection:
            identity = (
                await connection.execute(
                    text("SELECT current_database(), current_user, current_schema()")
                )
            ).one()
            if identity != ("haruka_test", "haruka_test_maintenance", schema):
                raise FlowError("android_collection_inspection_target_mismatch")
            marker = await connection.scalar(
                text(
                    "SELECT obj_description(oid, 'pg_namespace') "
                    "FROM pg_namespace WHERE nspname=:schema"
                ),
                {"schema": schema},
            )
            if marker not in {
                f"haruka-b1-run:{run_id}",
                f"haruka-isolated-run:{run_id}",
            }:
                raise FlowError("android_collection_inspection_marker_mismatch")
            rows = (
                (
                    await connection.execute(
                        text(
                            "SELECT c.id FROM collection_items AS c "
                            "JOIN users AS u ON u.id = c.owner_user_id "
                            "WHERE u.email_normalized = :email AND u.status = 'active' "
                            "AND c.deleted_at IS NULL"
                        ),
                        {"email": email.lower()},
                    )
                )
                .scalars()
                .all()
            )
            if len(rows) != 1 or not isinstance(rows[0], ParsedUUID):
                raise FlowError("android_collection_commit_count_mismatch")
            return str(rows[0])
    finally:
        await engine.dispose()


def _release_apk(apk: Path) -> bool:
    if apk.name != "app-dev-release.apk" or not RELEASE_METADATA.is_file():
        return False
    try:
        metadata: object = json.loads(RELEASE_METADATA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not is_object(metadata):
        return False
    elements = metadata.get("elements")
    gradle_apk = RELEASE_METADATA.parent / apk.name
    if not gradle_apk.is_file() or gradle_apk.is_symlink():
        return False
    try:
        with apk.open("rb") as flutter_output, gradle_apk.open("rb") as gradle_output:
            matching_outputs = (
                hashlib.file_digest(flutter_output, "sha256").digest()
                == hashlib.file_digest(gradle_output, "sha256").digest()
            )
    except OSError:
        return False
    element = elements[0] if _is_array(elements) and len(elements) == 1 else None
    return matching_outputs and (
        metadata.get("applicationId") == PACKAGE
        and metadata.get("variantName") == "devRelease"
        and is_object(element)
        and element.get("outputFile") == apk.name
    )


def _login_page(device: Device, ids: dict[str, str]) -> None:
    current = device.wait_any(
        (ids["homePage"], ids["loginPage"], ids["accountPage"]), timeout=60
    )
    if current == ids["homePage"]:
        device.tap(ids["accountNavigation"])
        current = device.wait_any((ids["loginPage"], ids["accountPage"]))
    if current == ids["accountPage"]:
        device.tap(ids["accountSignOut"])
        device.wait_node(ids["loginPage"])


def _select_published_word(device: Device, block_id: str, query_id: str) -> None:
    # Long-press the real SelectableText at the published word in the
    # synthetic "青い空を見上げた。" source. The point is derived from the
    # current text node bounds and line height, never a fixed screen pixel or
    # an injected selection state. Android presents its normal text handles.
    node = device.wait_node(block_id)
    bounds = BOUNDS.fullmatch(node.get("bounds", ""))
    if bounds is None:
        raise FlowError("android_text_bounds_missing")
    left, top, right, bottom = map(int, bounds.groups())
    height = bottom - top
    if height < 20 or right - left < height * 4:
        raise FlowError("android_text_bounds_invalid")
    word_x = left + round(height * 1.25)
    if word_x >= right:
        raise FlowError("android_text_target_outside_node")
    word_y = (top + bottom) // 2
    device.command(
        "shell",
        "input",
        "swipe",
        str(word_x),
        str(word_y),
        str(word_x),
        str(word_y),
        "900",
    )
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        if device.wait_node(query_id).get("enabled") == "true":
            return
        time.sleep(0.25)
    raise FlowError("android_real_text_selection_failed")


def _visible_after_scroll(
    device: Device,
    page_id: str,
    target_id: str,
    *,
    toward_start: bool = False,
    timeout: float = 60,
) -> None:
    """Reveal a normal off-screen control by dragging the current page."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        matches = device.nodes(target_id)
        if len(matches) == 1:
            return
        if len(matches) > 1:
            raise FlowError("android_control_not_unique")
        page = device.wait_node(page_id, timeout=5)
        bounds = BOUNDS.fullmatch(page.get("bounds", ""))
        if bounds is None:
            raise FlowError("android_page_bounds_missing")
        left, top, right, bottom = map(int, bounds.groups())
        if right <= left or bottom - top < 100:
            raise FlowError("android_page_bounds_invalid")
        x = (left + right) // 2
        start_y = top + (bottom - top) * (1 if toward_start else 3) // 4
        end_y = top + (bottom - top) * (3 if toward_start else 1) // 4
        device.command(
            "shell",
            "input",
            "swipe",
            str(x),
            str(start_y),
            str(x),
            str(end_y),
            "500",
        )
        time.sleep(0.25)
    raise FlowError("android_offscreen_control_missing")


def run_flow(
    device: Device,
    ids: dict[str, str],
    templates: dict[str, str],
    run_id: str,
    apk: Path,
    report: Report,
    *,
    collection_drop_once: bool,
) -> None:
    email = f"android-{secrets.token_hex(8)}@haruka.example.test"
    password = "Aa9" + secrets.token_hex(18)
    changed_password = "Bb8" + secrets.token_hex(18)
    recovered_password = "Cc7" + secrets.token_hex(18)
    stage = "install"
    fault_rule_id: str | None = None
    try:
        _api_identity(run_id)
        report.step("isolated_api_identity")
        device.command("install", "-r", str(apk), timeout=120)
        if not device.command("shell", "pm", "path", PACKAGE).startswith("package:"):
            raise FlowError("android_package_not_installed")
        device.restart()
        report.step("installed_release_app")
        stage = "registration"
        _login_page(device, ids)
        device.tap(ids["loginRegisterLink"])
        device.wait_node(ids["registerPage"])
        device.fill(ids["registerEmail"], email)
        device.fill(ids["registerPassword"], password)
        device.fill(ids["registerConfirm"], password)
        device.tap(ids["registerSubmit"])
        device.wait_node(ids["registrationAcceptedVerifyLink"], timeout=60)
        report.step("ui_registration_accepted")
        stage = "verification"
        link = _captured_link(run_id, email, "verify")
        device.tap(ids["registrationAcceptedVerifyLink"])
        device.wait_node(ids["verificationPage"])
        device.fill(ids["verificationToken"], link)
        device.tap(ids["verificationSubmit"])
        device.wait_node(ids["authResultPage"], timeout=60)
        report.step("ui_email_verified")
        stage = "login"
        device.tap(ids["authBackLogin"])
        device.wait_node(ids["loginPage"])
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], password)
        device.tap(ids["loginSubmit"])
        device.wait_node(ids["accountPage"], timeout=60)
        report.step("ui_login")
        stage = "restart"
        device.restart()
        current = device.wait_any(
            (ids["homePage"], ids["accountPage"], ids["loginPage"]), timeout=60
        )
        if current == ids["homePage"]:
            device.tap(ids["accountNavigation"])
            current = device.wait_any((ids["accountPage"], ids["loginPage"]))
        if current != ids["accountPage"]:
            raise FlowError("android_credential_restore_failed")
        report.step("native_credential_restored")
        stage = "password_change"
        device.tap(ids["accountChangePassword"])
        device.fill(ids["accountCurrentPassword"], password)
        device.fill(ids["accountNewPassword"], changed_password)
        device.fill(ids["accountConfirmPassword"], changed_password)
        device.tap(ids["accountChangePassword"])
        device.wait_node(ids["authResultPage"], timeout=60)
        device.tap(ids["authBackLogin"])
        device.wait_node(ids["loginPage"])
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], changed_password)
        device.tap(ids["loginSubmit"])
        device.wait_node(ids["accountPage"], timeout=60)
        report.step("ui_password_change_and_new_login")
        stage = "sessions"
        device.tap(ids["accountSessions"])
        device.wait_node(ids["sessionRevokeAll"], timeout=60)
        session_action = device.wait_dynamic(templates["sessionRevoke"], timeout=60)
        report.step("ui_sessions_viewed")
        device.tap(session_action)
        device.wait_node(ids["loginPage"], timeout=60)
        report.step("ui_session_revoked")
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], changed_password)
        device.tap(ids["loginSubmit"])
        device.wait_node(ids["accountPage"], timeout=60)
        device.tap(ids["accountSessions"])
        device.wait_node(ids["sessionRevokeAll"], timeout=60)
        device.tap(ids["sessionRevokeAll"])
        device.wait_node(ids["loginPage"], timeout=60)
        report.step("ui_all_sessions_revoked")
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], changed_password)
        device.tap(ids["loginSubmit"])
        device.wait_node(ids["accountPage"], timeout=60)
        stage = "learning"
        asyncio.run(seed_source(run_id, email))
        device.tap(ids["referenceMaterialsNav"])
        device.wait_node(ids["referenceMaterialsPage"])
        material_id = device.wait_dynamic(templates["referenceMaterialRow"], timeout=60)
        device.tap(material_id)
        block_id = device.wait_dynamic(templates["referenceBlock"], timeout=60)
        report.step("ui_reference_block_visible")
        report.document["material_id"] = material_id.rsplit(".", 1)[-1]
        report.document["chapter_block_id"] = block_id.rsplit(".", 1)[-1]
        report.write()
        _select_published_word(device, block_id, ids["referenceQuery"])
        report.step("ui_reference_selection_query_visible")
        device.tap(ids["referenceQuery"])
        _visible_after_scroll(device, ids["referenceWordDialog"], ids["referenceSave"])
        report.step("ui_reference_result_save_visible")
        if collection_drop_once:
            if not (run_root(run_id) / "fault-proxy.enabled").is_file():
                raise FlowError("android_collection_fault_proxy_not_enabled")
            fault_rule_id = local_api_fault_proxy.arm(
                run_id,
                mode="after_response_drop",
                method="POST",
                path="/api/v1/collections",
                duration_seconds=120,
            )
        device.tap(ids["referenceSave"])
        committed_id: str | None = None
        if collection_drop_once:
            assert fault_rule_id is not None
            _fault_receipt(run_id, fault_rule_id)
            committed_id = asyncio.run(_single_persisted_collection(run_id, email))
            report.document["collection_first_committed_id"] = committed_id
            report.document["collection_fault_rule_id"] = fault_rule_id
            report.step("ui_collection_response_lost_after_commit")
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                save_node = device.wait_node(ids["referenceSave"], timeout=5)
                if save_node.get("enabled") == "true":
                    break
                time.sleep(0.2)
            else:
                raise FlowError("android_collection_retry_unavailable")
            if device.nodes(ids["referenceSavedState"]):
                raise FlowError("android_collection_unknown_result_false_success")
            device.tap(ids["referenceSave"])
        _visible_after_scroll(
            device, ids["referenceWordDialog"], ids["referenceSavedState"]
        )
        report.step("ui_collection_saved_state_visible")
        device.command("shell", "input", "keyevent", "4")
        device.tap(ids["referenceReaderBack"])
        device.wait_node(ids["referenceMaterialsPage"], timeout=60)
        report.step("ui_collections_navigation_visible")
        device.tap(ids["referenceCollectionsNav"])
        device.wait_node(ids["referenceCollectionsPage"], timeout=60)
        collection_id = device.wait_dynamic(
            templates["referenceCollectionRow"], timeout=60
        )
        report.document["collection_id"] = collection_id.rsplit(".", 1)[-1]
        if committed_id is not None:
            if report.document["collection_id"] != committed_id:
                raise FlowError("android_collection_retry_changed_id")
            if asyncio.run(_single_persisted_collection(run_id, email)) != committed_id:
                raise FlowError("android_collection_retry_created_duplicate")
            report.step("ui_collection_unknown_result_retry_same_id")
        report.write()
        report.step("ui_source_resolve_and_collection")
        stage = "collection_restart"
        device.restart()
        current = device.wait_any(
            (ids["homePage"], ids["accountPage"], ids["loginPage"]), timeout=60
        )
        if current == ids["homePage"]:
            device.tap(ids["accountNavigation"])
            current = device.wait_any((ids["accountPage"], ids["loginPage"]))
        if current != ids["accountPage"]:
            raise FlowError("android_collection_session_not_restored")
        device.tap(ids["referenceMaterialsNav"])
        device.wait_node(ids["referenceMaterialsPage"])
        device.tap(ids["referenceCollectionsNav"])
        device.wait_node(ids["referenceCollectionsPage"], timeout=60)
        if (
            device.wait_dynamic(templates["referenceCollectionRow"], timeout=60)
            != collection_id
        ):
            raise FlowError("android_collection_id_changed_after_restart")
        report.step("ui_collection_same_id_after_restart")
        stage = "recovery"
        device.restart()
        current = device.wait_any((ids["homePage"], ids["accountPage"]), timeout=60)
        if current == ids["homePage"]:
            device.tap(ids["accountNavigation"])
        device.wait_node(ids["accountPage"])
        device.tap(ids["accountSignOut"])
        device.wait_node(ids["loginPage"])
        device.tap(ids["loginRecoveryLink"])
        device.wait_node(ids["recoveryRequestPage"])
        device.fill(ids["recoveryRequestEmail"], email)
        device.tap(ids["recoveryRequestSubmit"])
        device.wait_node(ids["recoveryAcceptedResetLink"], timeout=60)
        reset_link = _captured_link(run_id, email, "reset")
        device.tap(ids["recoveryAcceptedResetLink"])
        device.wait_node(ids["recoveryCompletePage"])
        device.fill(ids["recoveryCompleteToken"], reset_link)
        device.fill(ids["recoveryCompletePassword"], recovered_password)
        device.fill(ids["recoveryCompleteConfirm"], recovered_password)
        device.tap(ids["recoveryCompleteSubmit"])
        device.wait_node(ids["authResultPage"], timeout=60)
        report.step("ui_recovery_completed")
        stage = "new_password"
        device.tap(ids["authBackLogin"])
        device.wait_node(ids["loginPage"])
        device.fill(ids["loginEmail"], email)
        device.fill(ids["loginPassword"], recovered_password)
        device.tap(ids["loginSubmit"])
        device.wait_node(ids["accountPage"], timeout=60)
        device.tap(ids["accountSignOut"])
        device.wait_node(ids["loginPage"])
        report.step("ui_new_password_login_and_signout")
        write_private(
            run_root(run_id) / "android-actor.secret",
            json.dumps(
                {
                    "run_id": run_id,
                    "email": email,
                    "password": recovered_password,
                    "collection_id": report.document["collection_id"],
                }
            )
            + "\n",
        )
        report.step("private_cross_platform_actor_ready")
    except Exception as error:
        if fault_rule_id is not None:
            with contextlib.suppress(local_api_fault_proxy.FaultProxyError):
                local_api_fault_proxy.disarm(run_id, fault_rule_id)
        if isinstance(error, FlowError):
            report.document["error_code"] = str(error)
        report.finish(passed=False, failed_step=stage)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--adb", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--collection-drop-once", action="store_true")
    args = parser.parse_args()
    if not RUN.fullmatch(args.run_id) or not re.fullmatch(r"emulator-\d+", args.device):
        raise SystemExit("An owned run and an explicit emulator are required.")
    root = run_root(args.run_id)
    if read_ledger(root, args.run_id)["state"] != "serving":
        raise SystemExit("The isolated app must be serving.")
    apk = args.apk.resolve()
    output = args.output.resolve()
    if (
        apk.parent != APK_ROOT
        or not apk.is_file()
        or apk.is_symlink()
        or not _release_apk(apk)
    ):
        raise SystemExit("A release APK in the controlled Flutter output is required.")
    if output.parent != REPORTS.resolve() or output.exists() or not args.adb.is_file():
        raise SystemExit("Choose a new safe report path and installed adb.")
    registry: object = json.loads(REGISTRY.read_text(encoding="utf-8"))
    if not is_object(registry):
        raise SystemExit("The UI identifier registry is invalid.")
    ids = registry.get("static")
    templates = registry.get("templates")
    if not _string_map(ids) or not _string_map(templates):
        raise SystemExit("The UI identifier registry is incomplete.")
    required = (
        "homePage",
        "loginPage",
        "accountPage",
        "accountNavigation",
        "accountSignOut",
        "loginRegisterLink",
        "registerPage",
        "registerEmail",
        "registerPassword",
        "registerConfirm",
        "registerSubmit",
        "registrationAcceptedVerifyLink",
        "verificationPage",
        "verificationToken",
        "verificationSubmit",
        "authResultPage",
        "authBackLogin",
        "loginEmail",
        "loginPassword",
        "loginSubmit",
        "accountChangePassword",
        "accountCurrentPassword",
        "accountNewPassword",
        "accountConfirmPassword",
        "accountSessions",
        "sessionRevokeAll",
        "referenceMaterialsNav",
        "referenceCollectionsNav",
        "referenceReaderBack",
        "referenceWordDialog",
        "referenceMaterialsPage",
        "referenceQuery",
        "referenceSave",
        "referenceSavedState",
        "referenceCollectionsPage",
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
    )
    if any(not isinstance(ids.get(key), str) for key in required) or any(
        not isinstance(templates.get(key), str)
        for key in (
            "referenceMaterialRow",
            "referenceBlock",
            "referenceCollectionRow",
            "sessionRevoke",
        )
    ):
        raise SystemExit("The Android flow requires registered semantics controls.")
    device = Device(args.adb, args.device, ids, args.run_id)
    report = Report(output, args.run_id, args.device, apk)
    passed = False
    try:
        report.document["device_fingerprint"] = device.command(
            "shell", "getprop", "ro.build.fingerprint"
        ).strip()
        report.write()
        device.enable_ime()
        run_flow(
            device,
            ids,
            templates,
            args.run_id,
            apk,
            report,
            collection_drop_once=args.collection_drop_once,
        )
        passed = True
    except (FlowError, OSError, ValueError):
        if report.document["status"] == "running":
            report.finish(passed=False, failed_step="setup")
        sys.stderr.write("Android UI flow failed; inspect the safe report.\n")
        return 1
    except Exception:  # noqa: BLE001 - CLI boundary must not print secret-bearing errors.
        if report.document["status"] == "running":
            report.finish(passed=False, failed_step="unexpected")
        sys.stderr.write("Android UI flow failed; inspect the safe report.\n")
        return 1
    finally:
        cleanup_ok = True
        try:
            device.command("shell", "rm", "-f", device.remote_xml)
        except FlowError:
            cleanup_ok = False
        try:
            device.restore_ime()
        except FlowError:
            cleanup_ok = False
        report.document["device_cleanup"] = "passed" if cleanup_ok else "failed"
        if not cleanup_ok:
            passed = False
        report.finish(
            passed=passed,
            failed_step="device_cleanup" if not cleanup_ok else None,
        )
        report.close()
    if not passed:
        sys.stderr.write("Android device cleanup failed; inspect the safe report.\n")
        return 1
    sys.stdout.write("Android UI flow passed.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
