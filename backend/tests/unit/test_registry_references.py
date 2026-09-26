"""Release catalogs reject unknown permission references and application log events."""

import pytest
from tools.check_registries import validate_events

from app.contracts import permissions

pytestmark = pytest.mark.unit


def test_unknown_permission_template_cannot_export(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(permissions, "ROLE_TEMPLATES", {"learner": ("client.not_registered.read",)})
    with pytest.raises(ValueError, match="unknown codes"):
        permissions.permission_document()


def test_mistake_and_avatar_permissions_keep_self_scope_and_template_boundaries() -> None:
    newly_registered = {
        "client.practice.mistake.read",
        "client.practice.mistake.favorite",
        "client.profile.avatar.update",
    }
    document = permissions.permission_document()
    assert document["catalog_version"] == "b0-identity-v3"
    catalog = document["permissions"]
    assert isinstance(catalog, list)
    for code in newly_registered:
        assert {"code": code, "audience": "client", "data_scope": "self"} in catalog
    assert newly_registered <= set(permissions.ROLE_TEMPLATES["learner"])
    # Publishing vocabulary never grants private client actions to administrators,
    # or expands the explicit read-only role into avatar/mistake mutation paths.
    assert not newly_registered & set(permissions.ROLE_TEMPLATES["super_admin"])
    assert not newly_registered & set(permissions.ROLE_TEMPLATES["client_readonly"])


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
