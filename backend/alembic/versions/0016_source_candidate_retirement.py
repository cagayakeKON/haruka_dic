"""Retain owner-scoped retired source candidates across late writer completion."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0016_source_candidate_retirement"
down_revision = "0015_material_source_events"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "upload_intents",
        sa.Column(
            "retired_final_candidates",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
            comment="服务端退休候选键账本，持续可复查，不含已发布副本",
        ),
    )
    op.add_column(
        "upload_intents",
        sa.Column(
            "candidate_cleanup_due_at",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="退休副本下一次有界复查UTC时间",
        ),
    )
    op.create_check_constraint(
        op.f("ck_upload_intents_candidate_retirement"),
        "upload_intents",
        "jsonb_typeof(retired_final_candidates) = 'array' AND jsonb_array_length(retired_final_candidates) <= 16 AND (purpose = 'primary_document' OR (retired_final_candidates = '[]'::jsonb AND candidate_cleanup_due_at IS NULL))",
    )
    op.execute(
        "UPDATE upload_intents SET retired_final_candidates = jsonb_build_array(candidate_final_object_key), candidate_cleanup_due_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE purpose = 'primary_document' AND status IN ('failed','cancelled','expired') AND candidate_final_object_key IS NOT NULL"
    )


def downgrade() -> None:
    raise RuntimeError("Retired source candidates require an explicit forward repair")
