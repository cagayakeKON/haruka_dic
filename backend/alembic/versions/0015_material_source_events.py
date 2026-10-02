"""Register deterministic source jobs and committed source outcome events."""

from alembic import op

revision = "0015_material_source_events"
down_revision = "0014_material_sources"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint(op.f("ck_outbox_events_event_type"), "outbox_events", type_="check")
    op.create_check_constraint(
        op.f("ck_outbox_events_event_type"),
        "outbox_events",
        "event_type IN ('authorization.changed', 'identity.security', 'model.job.accepted', 'model.job.updated', 'model.usage.updated', 'material.job.accepted', 'material.job.updated', 'material.import.completed', 'material.import.failed', 'material.import.needs_review')",
    )
    op.drop_constraint(
        op.f("ck_outbox_events_authorization_revision_positive"), "outbox_events", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_outbox_events_authorization_revision_positive"),
        "outbox_events",
        "(event_type IN ('authorization.changed','identity.security') AND authorization_revision >= 1 AND audit_event_id IS NOT NULL) OR ((event_type LIKE 'model.%' OR event_type LIKE 'material.%') AND authorization_revision IS NULL AND audit_event_id IS NULL)",
    )


def downgrade() -> None:
    raise RuntimeError("Published source events require an explicit forward repair")
