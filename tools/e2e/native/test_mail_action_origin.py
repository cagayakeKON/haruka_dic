"""Keep isolated native mail links bound to the configured loopback origin."""

import pytest

from tools.e2e.native.android_app_flow import _mail_action_origin_matches


@pytest.mark.parametrize("scheme", ["http", "https"])
def test_matching_loopback_transport(scheme):
    origin = f"{scheme}://localhost:18443"
    assert _mail_action_origin_matches(f"{origin}/verify-email?token=fixture", origin)


@pytest.mark.parametrize(
    "link,origin",
    [
        ("https://elsewhere.test/verify-email", "https://localhost:18443"),
        ("https://localhost:18443/verify-email", "http://localhost:18443"),
        ("http://localhost:18444/verify-email", "http://localhost:18443"),
        ("http://user@localhost:18443/verify-email", "http://localhost:18443"),
        ("http://localhost:18443/verify-email", "http://elsewhere.test"),
    ],
)
def test_mismatching_origin_rejected(link, origin):
    assert not _mail_action_origin_matches(link, origin)
