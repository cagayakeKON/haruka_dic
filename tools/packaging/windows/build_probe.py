"""Build only the no-network Windows installation-identity prototype packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import TypeGuard

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "frontend/config/build_targets.json"
ARTIFACT_ROOT = ROOT / "artifacts/windows-installer"
WIX_NAMESPACE = "http://wixtoolset.org/schemas/v4/wxs"


def is_object(value: object) -> TypeGuard[dict[str, object]]:
    # All callers pass JSON-decoded values, whose object keys are strings.
    return isinstance(value, dict)


def object_value(value: object) -> dict[str, object]:
    if not is_object(value):
        raise ValueError("Expected a JSON object")
    return value


def string_value(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError("Expected a non-empty string")
    return value


def stable_guid(value: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "urn:haruka:windows-installer:" + value)).upper()


@dataclass(frozen=True)
class Identity:
    environment: str
    application_id: str
    installer_id: str
    product_directory: str
    credential_service: str
    display_name: str
    upgrade_code: str


def identities(document: object) -> dict[str, Identity]:
    targets = object_value(document)
    environments = object_value(targets["environments"])
    windows = object_value(object_value(targets["platforms"])["windows"])
    if set(windows) != {"dev", "production"}:
        raise ValueError("Exactly dev and production Windows identities are required")
    result: dict[str, Identity] = {}
    for environment, value in windows.items():
        entry = object_value(value)
        application_id = string_value(entry["application_id"])
        installer_id = string_value(entry["installer_id"])
        credential_service = string_value(entry["credential_service"])
        product_directory = string_value(entry["product_directory"])
        if not re.fullmatch(r"haruka\.dictionary(?:\.dev)?", application_id):
            raise ValueError("Unexpected Windows application identity")
        expected = "haruka.dictionary.dev" if environment == "dev" else "haruka.dictionary"
        if (
            application_id != expected
            or installer_id != application_id
            or credential_service != application_id
        ):
            raise ValueError(
                "Installer and credential identities must match their application identity"
            )
        if not re.fullmatch(r"Haruka(?: Dev)?", product_directory):
            raise ValueError("Product directory must be a single supported path component")
        expected_directory = "Haruka Dev" if environment == "dev" else "Haruka"
        if product_directory != expected_directory:
            raise ValueError("Product directory does not match the environment")
        display_name = string_value(object_value(environments[environment])["display_name"])
        result[environment] = Identity(
            environment,
            application_id,
            installer_id,
            product_directory,
            credential_service,
            display_name,
            stable_guid(installer_id),
        )
    for field in (
        "application_id",
        "installer_id",
        "product_directory",
        "credential_service",
        "upgrade_code",
    ):
        if len({str(asdict(item)[field]).casefold() for item in result.values()}) != 2:
            raise ValueError(f"Windows environments share {field}")
    return result


def package_document(identity: Identity, version: str, payload: Path) -> ET.ElementTree:
    if not re.fullmatch(r"\d{1,3}\.\d{1,3}\.\d{1,5}", version):
        raise ValueError("Expected an MSI three-part numeric version")
    major, minor, build = (int(part) for part in version.split("."))
    if major > 255 or minor > 255 or build > 65535:
        raise ValueError("MSI version component exceeds its supported range")
    root = ET.Element("Wix", {"xmlns": WIX_NAMESPACE})
    package = ET.SubElement(
        root,
        "Package",
        {
            "Name": identity.display_name + " — installation identity prototype",
            "Manufacturer": "Haruka",
            "Version": version,
            "Language": "1033",
            "Scope": "perUser",
            "UpgradeCode": identity.upgrade_code,
            "ProductCode": stable_guid(identity.installer_id + ":" + version),
        },
    )
    ET.SubElement(
        package,
        "MajorUpgrade",
        {"DowngradeErrorMessage": "A newer prototype is already installed."},
    )
    ET.SubElement(package, "MediaTemplate", {"EmbedCab": "yes"})
    ET.SubElement(package, "Property", {"Id": "ARPNOMODIFY", "Value": "1"})
    ET.SubElement(package, "Property", {"Id": "MSIRESTARTMANAGERCONTROL", "Value": "Disable"})
    local = ET.SubElement(package, "StandardDirectory", {"Id": "LocalAppDataFolder"})
    programs = ET.SubElement(local, "Directory", {"Id": "ProgramsFolder", "Name": "Programs"})
    install = ET.SubElement(
        programs, "Directory", {"Id": "INSTALLFOLDER", "Name": identity.product_directory}
    )
    component = ET.SubElement(
        install,
        "Component",
        {
            "Id": "IdentityPrototype",
            "Guid": stable_guid(identity.installer_id + ":prototype-files"),
        },
    )
    for filename in ("haruka-installation.json", "identity-probe.ps1"):
        raw_source = payload / filename
        source = raw_source.resolve()
        if source.parent != payload.resolve() or raw_source.is_symlink() or not source.is_file():
            raise ValueError("Prototype payload is missing or not a regular owned file")
        ET.SubElement(component, "File", {"Source": str(source)})
    ET.SubElement(
        component,
        "RegistryValue",
        {
            "Root": "HKCU",
            "Key": "Software\\Haruka\\Installations\\" + identity.installer_id,
            "Name": "PrototypeVersion",
            "Value": version,
            "Type": "string",
            "KeyPath": "yes",
        },
    )
    ET.SubElement(
        component, "RemoveFolder", {"Id": "RemoveEmptyProductDirectory", "On": "uninstall"}
    )
    feature = ET.SubElement(
        package, "Feature", {"Id": "IdentityPrototype", "Title": "Installation identity"}
    )
    ET.SubElement(feature, "ComponentRef", {"Id": "IdentityPrototype"})
    ET.indent(root)
    return ET.ElementTree(root)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def build(output: Path, wix: Path) -> Path:
    if os.name != "nt":
        raise ValueError("The Windows packaging prototype requires Windows")
    if not output.resolve().is_relative_to(ARTIFACT_ROOT.resolve()):
        raise ValueError("Prototype output must remain inside artifacts/windows-installer")
    tool_lock: object = json.loads(
        (Path(__file__).parent / "toolchain.json").read_text(encoding="utf-8")
    )
    version_lock = string_value(object_value(object_value(tool_lock)["wix"])["version"])
    expected_wix = ROOT / f".tools/wix-{version_lock}/tool/wix.exe"
    if wix.resolve() != expected_wix.resolve():
        raise ValueError("Only the workspace-local locked compiler can build this prototype")
    # Explicit locked executable and fixed arguments, without a shell.
    compiler = subprocess.run(  # noqa: S603
        [str(wix), "--version"], check=True, capture_output=True, text=True, timeout=30
    )
    if not compiler.stdout.strip().startswith(version_lock + "+"):
        raise ValueError("Compiler does not match the locked WiX version")
    output.mkdir(parents=True, exist_ok=False)
    parsed: object = json.loads(SOURCE.read_text(encoding="utf-8"))
    mapped = identities(parsed)
    records: list[dict[str, object]] = []
    for environment, version in (("dev", "0.1.0"), ("production", "0.1.0"), ("dev", "0.1.1")):
        identity = mapped[environment]
        package_root = output / (environment + "-" + version)
        package_root.mkdir()
        metadata = {
            **asdict(identity),
            "version": version,
            "payload_kind": "no-network-identity-probe",
        }
        (package_root / "haruka-installation.json").write_text(
            json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
        )
        (package_root / "identity-probe.ps1").write_text(
            (Path(__file__).parent / "identity-probe.ps1").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        source = package_root / "package.wxs"
        package_document(identity, version, package_root).write(
            source, encoding="utf-8", xml_declaration=True
        )
        package = package_root / "haruka-identity-prototype.msi"
        # Compiler path is explicit; arguments are fixed and no shell executes generated input.
        subprocess.run(  # noqa: S603
            [str(wix), "build", "-arch", "x64", str(source), "-o", str(package)],
            check=True,
            timeout=120,
        )
        records.append(
            {
                **metadata,
                "package": str(package.relative_to(output)),
                "product_code": stable_guid(identity.installer_id + ":" + version),
                "package_sha256": sha256(package),
            }
        )
    manifest = output / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "build_targets_sha256": sha256(SOURCE),
                "compiler": compiler.stdout.strip(),
                "packages": records,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return manifest


class Arguments(argparse.Namespace):
    output: Path
    wix: Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--wix", type=Path, default=ROOT / ".tools/wix-5.0.2/tool/wix.exe")
    arguments = parser.parse_args(namespace=Arguments())
    manifest = build(arguments.output, arguments.wix.resolve())
    sys.stdout.write(f"Prototype manifest: {manifest}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
