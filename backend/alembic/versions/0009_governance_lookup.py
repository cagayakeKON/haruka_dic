"""Stable receipt lookup identity survives cryptographic key version changes."""

import sqlalchemy as sa
from alembic import op

revision = "0009_governance_lookup"
down_revision = "0008_governance_receipts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "idempotency_records",
        sa.Column(
            "lookup_digest",
            sa.LargeBinary(),
            nullable=True,
            comment="治理客户端键稳定查询摘要；旧client为空",
        ),
    )
    op.create_unique_constraint(
        "uq_governance_idempotency_lookup",
        "idempotency_records",
        [
            "owner_user_id",
            "audience",
            "action_code",
            "lookup_digest",
        ],
    )
    op.create_check_constraint(
        op.f("ck_idempotency_records_governance_lookup_length"),
        "idempotency_records",
        "lookup_digest IS NULL OR octet_length(lookup_digest) = 32",
    )


def downgrade() -> None:
    raise RuntimeError("restore a matching backup rather than discard stable receipt lookup")
