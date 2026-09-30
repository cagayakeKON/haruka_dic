"""Audit summaries keep only short scalar differences."""

from app.services.audit_governance import public_summary


def test_public_summary_drops_secrets_and_long_values() -> None:
    clean = public_summary(
        {
            "status": "disabled",
            "enabled": False,
            "count": 2,
            "token": "secret-token",
            "password_version": "9",
            "api_key": "hidden",
            "note": "x" * 201,
            "nested": {"status": "active"},
            "Email": "person@example.test",
        }
    )
    assert clean == {"status": "disabled", "enabled": "false", "count": "2"}
