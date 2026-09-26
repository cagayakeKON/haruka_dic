"""Registration and SMTP envelopes share one unambiguous mailbox grammar."""

from email.headerregistry import Address

import pytest

from app.contracts.errors import ErrorCode
from app.domain.email_address import normalize_email, normalize_existing_login_email
from app.domain.errors import AppError
from app.services.registration import email_identity

pytestmark = pytest.mark.unit


@pytest.mark.parametrize(
    "value",
    [
        "a,b@example.test",
        "a;b@example.test",
        "a(comment)@example.test",
        "Name <a@example.test>",
        "a@example.test,b@example.test",
        "a..b@example.test",
        "a@example..test",
        "a@example.test\r\nBcc:other@example.test",
    ],
)
def test_mailbox_header_ambiguity_is_rejected(value: str) -> None:
    with pytest.raises(ValueError, match="email address is invalid"):
        normalize_email(value)
    with pytest.raises(AppError) as refused:
        email_identity(value)
    assert refused.value.code == ErrorCode.INPUT_INVALID


def test_nfkc_casefold_identity_preserves_exact_single_smtp_envelope() -> None:
    display, normalized = normalize_email("  Ａlice+Study@Example.TEST  ")
    assert display == "Alice+Study@Example.TEST"
    assert normalized == "alice+study@example.test"
    local, domain = display.split("@", 1)
    assert Address(username=local, domain=domain).addr_spec == display


def test_existing_unicode_identity_remains_login_resolvable() -> None:
    assert normalize_existing_login_email(" Café@Example.TEST ") == (
        "Café@Example.TEST",
        "café@example.test",
    )
    display, normalized = normalize_email(" Café@Example.TEST ")
    assert (display, normalized) == ("Café@Example.TEST", "café@example.test")
    local, domain = display.split("@", 1)
    assert Address(username=local, domain=domain).addr_spec == display
