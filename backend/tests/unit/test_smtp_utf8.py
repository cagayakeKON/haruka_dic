"""Mail construction keeps exactly one address and honors SMTPUTF8 support."""

import smtplib
from collections.abc import Sequence
from email.message import EmailMessage
from typing import cast

import pytest

from app.adapters import mail
from app.core.settings import Settings

_SEND_MESSAGE = smtplib.SMTP.send_message


class CapturingSMTP:
    def __init__(self, *args: object, supported: bool, **kwargs: object) -> None:
        self.supported = supported
        self.envelope: tuple[str, tuple[str, ...], tuple[str, ...]] | None = None

    def __enter__(self) -> "CapturingSMTP":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def ehlo_or_helo_if_needed(self) -> None:
        return None

    def has_extn(self, extension: str) -> bool:
        return self.supported and extension.lower() == "smtputf8"

    def sendmail(
        self,
        from_addr: str,
        to_addrs: Sequence[str],
        message: bytes,
        mail_options: Sequence[str] = (),
        rcpt_options: Sequence[str] = (),
    ) -> dict[str, object]:
        self.envelope = from_addr, tuple(to_addrs), tuple(mail_options)
        assert b"Subject:" in message
        return {}

    def send_message(self, message: EmailMessage, from_addr: str, to_addrs: list[str]) -> object:
        return _SEND_MESSAGE(cast(smtplib.SMTP, self), message, from_addr, to_addrs)


@pytest.mark.unit
@pytest.mark.parametrize("supported", [False, True])
def test_unicode_mailbox_requires_smtputf8(
    settings: Settings, monkeypatch: pytest.MonkeyPatch, supported: bool
) -> None:
    captured = CapturingSMTP(supported=supported)

    def fake_smtp(*args: object, **kwargs: object) -> CapturingSMTP:
        return captured

    monkeypatch.setattr(mail.smtplib, "SMTP", fake_smtp)
    configured = settings.model_copy(
        update={
            "smtp_host": "127.0.0.1",
            "smtp_port": 18025,
            "smtp_from": "noreply@haruka.example.test",
            "smtp_starttls": False,
        }
    )
    if not supported:
        with pytest.raises(smtplib.SMTPNotSupportedError):
            mail.send_smtp_message(
                configured,
                "café@haruka.example.test",
                "https://localhost/verify-email#token=synthetic",
                "email_verify",
            )
        assert captured.envelope is None
    else:
        mail.send_smtp_message(
            configured,
            "café@haruka.example.test",
            "https://localhost/verify-email#token=synthetic",
            "email_verify",
        )
        assert captured.envelope == (
            "noreply@haruka.example.test",
            ("café@haruka.example.test",),
            ("SMTPUTF8", "BODY=8BITMIME"),
        )
