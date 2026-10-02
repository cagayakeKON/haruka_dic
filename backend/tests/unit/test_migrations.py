"""Maintenance rejects ambiguous credentials and unreviewed migration resources before I/O."""

import hashlib
import json
from pathlib import Path

import pytest
from pydantic import SecretStr, ValidationError

from app.maintenance import migrations
from app.maintenance.migrations import (
    MigrationError,
    bundled_migration_head,
    load_migration_resources,
)
from app.maintenance.schema import (
    EXPECTED_REVISION,
    SchemaMismatchError,
    load_constraint_baseline,
    validate_schema_name,
)
from app.maintenance.settings import MaintenanceSettings, load_maintenance_settings

pytestmark = pytest.mark.unit

TEST_URL = "postgresql+asyncpg://haruka_test_maintenance:fake-value@127.0.0.1:15432/haruka_test"


def resource_directory(root: Path) -> Path:
    root.mkdir()
    (root / "versions").mkdir()
    (root / "env.py").write_text('"""Fixture migration environment."""\n', encoding="utf-8")
    (root / "versions/0001_fixture.py").write_text(
        f'revision = "{EXPECTED_REVISION}"\ndown_revision = None\n', encoding="utf-8"
    )
    files = {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in root.rglob("*.py")
    }
    (root / "manifest.json").write_text(
        json.dumps({"schema_version": 1, "head": EXPECTED_REVISION, "files": files}),
        encoding="utf-8",
    )
    return root


@pytest.mark.parametrize(
    "address",
    [
        TEST_URL.replace("127.0.0.1", "production.example"),
        TEST_URL.replace("haruka_test_maintenance", "haruka_test_runtime"),
        TEST_URL.replace("haruka_test_maintenance", "postgres"),
        TEST_URL.replace("/haruka_test", "/myhome"),
        TEST_URL.replace("postgresql+asyncpg", "postgresql"),
        TEST_URL.replace(":fake-value", ""),
        TEST_URL + "?options=-csearch_path=public",
    ],
)
def test_maintenance_target_rejects_runtime_or_unrelated_databases(address: str) -> None:
    with pytest.raises(ValidationError):
        MaintenanceSettings(database_url=SecretStr(address))


def test_maintenance_file_is_explicit_and_credentials_are_redacted(tmp_path: Path) -> None:
    path = tmp_path / "maintenance.env"
    path.write_text(f"HARUKA_DATABASE_URL={TEST_URL}\n", encoding="utf-8")
    settings = load_maintenance_settings(path)
    assert settings.app_env == "test"
    assert settings.database_schema == "public"
    assert "fake-value" not in repr(settings)
    with pytest.raises(ValueError, match="does not exist"):
        load_maintenance_settings(tmp_path / "absent.env")


@pytest.mark.parametrize("environment", ["production", "staging", "dev", "unknown"])
def test_ambient_environment_must_match_the_explicit_maintenance_target(
    environment: str, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    path = tmp_path / "maintenance.env"
    path.write_text(f"HARUKA_DATABASE_URL={TEST_URL}\n", encoding="utf-8")
    monkeypatch.setenv("HARUKA_APP_ENV", environment)
    with pytest.raises(ValidationError):
        load_maintenance_settings(path)


def test_matching_declared_environment_remains_compatible(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("HARUKA_APP_ENV", "test")
    assert MaintenanceSettings(database_url=SecretStr(TEST_URL)).app_env == "test"


def test_test_schema_requires_explicit_test_database_configuration(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema = "haruka_migration_test_" + "a" * 32
    with pytest.raises(ValidationError):
        MaintenanceSettings(
            database_url=SecretStr(TEST_URL.replace("haruka_test", "haruka_dev")),
            test_schema=schema,
        )
    monkeypatch.setenv("HARUKA_TEST_SCHEMA", schema)
    with pytest.raises(ValueError, match="programmatic"):
        MaintenanceSettings(database_url=SecretStr(TEST_URL))
    settings = MaintenanceSettings(database_url=SecretStr(TEST_URL), test_schema=schema)
    assert settings.database_schema == schema


@pytest.mark.parametrize(
    "schema", ["public,other", "private", "haruka_migration_test_", 'public";']
)
def test_arbitrary_schema_identifiers_fail_closed(schema: str) -> None:
    with pytest.raises(ValueError):
        validate_schema_name(schema)


def test_manifest_rejects_changed_missing_and_extra_migrations(tmp_path: Path) -> None:
    root = resource_directory(tmp_path / "migration")
    assert load_migration_resources(root).head == EXPECTED_REVISION
    env = root / "env.py"
    original = env.read_bytes()
    env.write_bytes(original + b"# drift\n")
    with pytest.raises(MigrationError, match="hash"):
        load_migration_resources(root)
    env.write_bytes(original)
    extra = root / "versions/unregistered.py"
    extra.write_text("", encoding="utf-8")
    with pytest.raises(MigrationError, match="unregistered"):
        load_migration_resources(root)
    extra.unlink()
    env.unlink()
    with pytest.raises(MigrationError, match="unregistered"):
        load_migration_resources(root)


def test_manifest_requires_absolute_explicit_resources(tmp_path: Path) -> None:
    with pytest.raises(MigrationError, match="absolute"):
        load_migration_resources(Path("alembic"))
    with pytest.raises(MigrationError, match="manifest"):
        load_migration_resources(tmp_path)


def test_manifest_rejects_multiple_heads(tmp_path: Path) -> None:
    root = resource_directory(tmp_path / "migration")
    second = root / "versions/0002_fixture.py"
    second.write_text('revision = "other_head"\ndown_revision = None\n', encoding="utf-8")
    manifest = root / "manifest.json"
    document = {
        "schema_version": 1,
        "head": EXPECTED_REVISION,
        "files": {
            path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*.py")
        },
    }
    manifest.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(MigrationError, match="exactly"):
        load_migration_resources(root)


def test_bundled_head_is_verified_and_independent_of_working_directory(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(tmp_path)
    assert bundled_migration_head() == EXPECTED_REVISION


def test_packaged_head_uses_manifest_inside_resource_context(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    package = tmp_path / "package"
    package.mkdir()
    resource_directory(package / "migration_bundle")

    def package_files(anchor: str) -> Path:
        assert anchor == "app.maintenance"
        return package

    monkeypatch.setattr("importlib.resources.files", package_files)
    monkeypatch.chdir(tmp_path)
    assert bundled_migration_head() == EXPECTED_REVISION


def test_invalid_packaged_bundle_never_falls_back_to_valid_checkout(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    package = tmp_path / "package"
    package.mkdir()
    bundle = resource_directory(package / "migration_bundle")
    (bundle / "env.py").write_text("# unreviewed drift\n", encoding="utf-8")

    def package_files(anchor: str) -> Path:
        assert anchor == "app.maintenance"
        return package

    monkeypatch.setattr("importlib.resources.files", package_files)
    with pytest.raises(MigrationError, match="hash"):
        bundled_migration_head()


def test_missing_editable_bundle_fails_closed_without_cwd_fallback(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    resource_directory(tmp_path / "alembic")

    def package_files(anchor: str) -> Path:
        assert anchor == "app.maintenance"
        return tmp_path / "absent_package"

    monkeypatch.setattr("importlib.resources.files", package_files)
    monkeypatch.setattr(
        migrations, "__file__", str(tmp_path / "absent_backend/app/maintenance/migrations.py")
    )
    monkeypatch.chdir(tmp_path)
    with pytest.raises(MigrationError, match="absolute"):
        bundled_migration_head()


def test_constraint_baseline_rejects_missing_and_changed_model_pairing(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    baseline = load_constraint_baseline()

    def package_files(_package: str) -> Path:
        return tmp_path

    monkeypatch.setattr("app.maintenance.schema.files", package_files)
    with pytest.raises(SchemaMismatchError, match="missing or invalid"):
        load_constraint_baseline()
    content = baseline.model_dump()
    content["model_checks"] = {}
    (tmp_path / "schema_baseline.json").write_text(json.dumps(content), encoding="utf-8")
    with pytest.raises(SchemaMismatchError, match="model constraints"):
        load_constraint_baseline()
