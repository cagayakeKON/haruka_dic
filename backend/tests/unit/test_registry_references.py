"""Release catalogs reject unknown permission references and application log events."""

import pytest
from tools.check_registries import validate_events

from app.contracts import permissions

pytestmark = pytest.mark.unit


def test_unknown_permission_template_cannot_export(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(permissions, "ROLE_TEMPLATES", {"learner": ("client.not_registered.read",)})
    with pytest.raises(ValueError, match="unknown codes"):
        permissions.permission_document()


@pytest.mark.parametrize(
    "source",
    [
        'import logging; log = logging.getLogger(__name__); log.info("unknown.event")',
        'import logging as lg; lg.getLogger(__name__).warning("unknown.event")',
        'from logging import getLogger as factory; log = factory(__name__); log.error(msg="unknown.event")',
        "import logging; logger = logging.getLogger(__name__); logger.log(20, event)",
    ],
)
def test_unknown_or_dynamic_application_event_fails(source: str) -> None:
    with pytest.raises(ValueError, match="Unregistered or dynamic application log event"):
        validate_events(source, "probe.py")


def test_registered_events_and_nonlogging_errors_are_valid() -> None:
    validate_events(
        'import logging; logger = logging.getLogger(__name__); logger.info("process.started"); '
        'logging.getLogger(__name__).error("process.unavailable"); parser.error("invalid option")',
        "probe.py",
    )
