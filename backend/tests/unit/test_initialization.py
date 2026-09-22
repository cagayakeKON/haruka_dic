"""Pure seed and CLI boundaries; all transaction effects are tested against real PG."""

import getpass
import sys
import warnings

import pytest

from app.cli import manage
from app.contracts.permissions import ADMIN_CODES, CLIENT_CODES, ROLE_TEMPLATES, permission_document
from app.services.initialization import InitializationError, normalize_email

pytestmark = pytest.mark.unit


def test_password_terminal_fallback_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    def echoing_fallback(_prompt: str) -> str:
        warnings.warn("Cannot control echo", getpass.GetPassWarning, stacklevel=2)
        pytest.fail("echoing fallback must not continue reading a password")

    monkeypatch.setattr(getpass, "getpass", echoing_fallback)
    with pytest.raises(InitializationError, match="hidden"):
        manage.read_password()


def test_catalog_templates_are_explicit_and_keep_private_data_boundary() -> None:
    document = permission_document()
    assert document["implemented_business_routes"] == []
    assert set(ROLE_TEMPLATES["super_admin"]) == set(ADMIN_CODES)
    assert not set(ADMIN_CODES) & set(CLIENT_CODES)
    assert "client.vocabulary.csv.export" in ROLE_TEMPLATES["client_readonly"]
    assert "client.vocabulary_notebook.read" in ROLE_TEMPLATES["client_readonly"]
    assert "client.vocabulary_notebook.update" not in ROLE_TEMPLATES["client_readonly"]
    assert not any(
        "generate" in code or "import" in code for code in ROLE_TEMPLATES["client_readonly"]
    )


def test_email_normalization_and_invalid_identity() -> None:
    assert normalize_email(" Admin@Example.test ") == ("Admin@Example.test", "admin@example.test")
    for value in ("", "invalid", "user\n@example.test", "a" * 255 + "@example.test"):
        with pytest.raises(InitializationError):
            normalize_email(value)


@pytest.mark.parametrize(
    "arguments",
    [
        ["db", "upgrade"],
        ["seed", "apply"],
        ["admin", "init"],
        ["admin", "init", "--password", "not-a-real-secret"],
    ],
)
def test_cli_requires_explicit_maintenance_boundary(
    arguments: list[str], monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(sys, "argv", ["haruka-manage", *arguments])
    with pytest.raises(SystemExit) as result:
        manage.main()
    assert result.value.code == 2
    # argparse may echo unknown input, so password is not an accepted command option.
    assert "usage:" in capsys.readouterr().err
