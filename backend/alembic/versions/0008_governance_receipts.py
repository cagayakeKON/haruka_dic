"""Compatible admin action receipts; old collection receipts remain constrained."""

from alembic import op

revision = "0008_governance_receipts"
down_revision = "0007_authorization_governance"
branch_labels = None
depends_on = None


def upgrade() -> None:
    checks = {
        "learning_action_state": "audience IN ('client', 'admin') AND state IN ('committed')",
        "learning_result_pair": "(audience = 'admin' AND result_kind = 'governance_result' AND result_id IS NULL) OR (audience = 'client' AND ((result_kind IS NULL AND result_id IS NULL) OR (result_kind IS NOT NULL AND result_id IS NOT NULL)))",
        "learning_committed_result": "safe_response IS NOT NULL AND ((audience = 'client' AND result_kind = 'collection_item' AND result_id IS NOT NULL) OR (audience = 'admin' AND result_kind = 'governance_result' AND result_id IS NULL AND library_id IS NULL))",
    }
    for name, expression in checks.items():
        op.drop_constraint(
            op.f(f"ck_idempotency_records_{name}"), "idempotency_records", type_="check"
        )
        op.create_check_constraint(
            op.f(f"ck_idempotency_records_{name}"), "idempotency_records", expression
        )


def downgrade() -> None:
    # Administrative receipts must not be silently discarded by a downgrade.
    raise RuntimeError("restore a matching backup and application instead of discarding receipts")
