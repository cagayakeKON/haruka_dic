"""Runtime role rights for model-task tables in isolated Haruka schemas."""
import re

import sqlalchemy as sa
from alembic import op

revision = "0012_model_runtime_grants"
down_revision = "0011_model_job_audit"
branch_labels = None
depends_on = None


def upgrade() -> None:
    _grant_runtime()


def _grant_runtime() -> None:
    bind = op.get_bind()
    database = bind.scalar(sa.text("SELECT current_database()"))
    schema = bind.scalar(sa.text("SELECT current_schema()"))
    if (
        database not in {"haruka_test", "haruka_dev"}
        or not isinstance(schema, str)
        or (schema != "public" and not re.fullmatch(r"haruka_migration_test_[a-f0-9]{32}", schema))
    ):
        raise RuntimeError("migration target is not an isolated Haruka schema")
    role = f"{database}_runtime"
    quoted_schema = bind.dialect.identifier_preparer.quote_schema(schema)
    op.execute(f"GRANT USAGE ON SCHEMA {quoted_schema} TO {role}")
    op.execute(
        f"GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {quoted_schema} TO {role}"
    )
    op.execute(f"REVOKE UPDATE, DELETE ON {quoted_schema}.admin_audit_events FROM {role}")
    op.execute(f"REVOKE INSERT, UPDATE, DELETE ON {quoted_schema}.alembic_version FROM {role}")


def downgrade() -> None:
    raise RuntimeError("runtime grants require reviewed forward repair")
