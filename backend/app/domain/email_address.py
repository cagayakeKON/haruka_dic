"""Canonical one-mailbox identity; never accept header/display/group syntax."""

import unicodedata

_LOCAL_SYMBOLS = frozenset("!#$%&'*+-/=?^_`{|}~.")


def normalize_email(email: str) -> tuple[str, str]:
    display = unicodedata.normalize("NFKC", email.strip())
    if len(display) > 254 or display.count("@") != 1:
        raise ValueError("email address is invalid")
    local, domain = display.split("@", 1)
    if (
        not local
        or len(local) > 64
        or local.startswith(".")
        or local.endswith(".")
        or ".." in local
        or not all(character.isalnum() or character in _LOCAL_SYMBOLS for character in local)
    ):
        raise ValueError("email address is invalid")
    labels = domain.split(".")
    if len(labels) < 2 or any(
        not label
        or len(label) > 63
        or label.startswith("-")
        or label.endswith("-")
        or not all(character.isalnum() or character == "-" for character in label)
        for label in labels
    ):
        raise ValueError("email address is invalid")
    if any(unicodedata.category(character).startswith("C") for character in display):
        raise ValueError("email address is invalid")
    normalized = display.casefold()
    if len(normalized) > 254:
        raise ValueError("email address is invalid")
    return display, normalized


def normalize_existing_login_email(email: str) -> tuple[str, str]:
    """Read historical identities without creating a new undeliverable mailbox."""
    display = unicodedata.normalize("NFKC", email.strip())
    if (
        len(display) > 254
        or display.count("@") != 1
        or any(
            unicodedata.category(character).startswith("C") or character.isspace()
            for character in display
        )
    ):
        raise ValueError("email address is invalid")
    normalized = display.casefold()
    if len(normalized) > 254:
        raise ValueError("email address is invalid")
    return display, normalized
