"""Fenced publication leases for durable model events."""
import sqlalchemy as sa
from alembic import op
revision = "0013_outbox_delivery_lease"
down_revision = "0012_model_runtime_grants"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_check_constraint(op.f("ck_model_catalog_entries_capabilities"),"model_catalog_entries", "jsonb_typeof(capabilities)='array' AND capabilities <@ '[\"text\",\"vision\",\"tts\"]'::jsonb")
    op.add_column("outbox_events",sa.Column("delivery_fence",sa.BigInteger(),nullable=False,server_default=sa.text("0"),comment="投递fence"))
    op.add_column("outbox_events",sa.Column("delivery_lease_until",sa.DateTime(timezone=True),nullable=True,comment="投递租约"))

def downgrade() -> None:
    raise RuntimeError("outbox leases require reviewed forward repair")
