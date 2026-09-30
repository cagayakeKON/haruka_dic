"""Approval progress is a snapshot on the account, not the current policy switch."""

from datetime import UTC, datetime

from app.models import User
from app.services.registration import (
    activation_progress,
    pending_login_action,
    record_email_verification,
)


def _user(**changes: object) -> User:
    values: dict[str, object] = {
        "email": "learner@example.test",
        "email_normalized": "learner@example.test",
        "password_hash": "stored",
        "status": "pending",
        "approval_status": "not_required",
        "email_verified_at": None,
    }
    values.update(changes)
    return User(**values)


def test_email_verification_waits_for_an_approval_snapshot() -> None:
    now = datetime(2026, 9, 29, tzinfo=UTC)
    waiting = _user(approval_status="pending")
    record_email_verification(waiting, now)
    assert waiting.email_verified_at == now
    assert waiting.status == "pending"
    assert activation_progress(waiting) == ("pending_approval", None)
    assert pending_login_action(waiting) == "await_approval"

    open_account = _user()
    record_email_verification(open_account, now)
    assert open_account.status == "active"
    assert activation_progress(open_account) == ("active", None)

    refused = _user(approval_status="rejected")
    record_email_verification(refused, now)
    assert refused.status == "pending"
    assert activation_progress(refused) == ("rejected", None)
    assert pending_login_action(refused) == "rejected"


def test_unverified_approval_account_still_asks_for_email() -> None:
    account = _user(approval_status="pending")
    assert activation_progress(account) == ("pending_email", "verify_email")
    assert pending_login_action(account) == "verify_email"
