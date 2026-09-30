"""Registered administrative non-model task actions."""
from alembic import op
revision = "0011_model_job_audit"
down_revision = "0010_model_tasks"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.drop_constraint(op.f("ck_admin_audit_events_action"), "admin_audit_events", type_="check")
    op.create_check_constraint(op.f("ck_admin_audit_events_action"), "admin_audit_events", "action IN ('credential.created', 'credential.rotated', 'credential.deleted', 'model_catalog.updated', 'model_limits.updated', 'model_job.cancelled', 'model_job.retried', 'account.registered', 'admin.created', 'auth.login.denied', 'auth_policy.updated', 'authorization.denied', 'email.verified', 'grant_boundary.updated', 'menu.updated', 'password.changed', 'password.recovered', 'recovery.accepted', 'recovery.challenge_issued', 'recovery.completed', 'recovery.rejected', 'recovery.requested', 'recovery.verified', 'refresh.replayed', 'role.created', 'role.deleted', 'role.inheritance_changed', 'role.permission_assigned', 'role.updated', 'seed.applied', 'session.created', 'session.revoked', 'user.approved', 'user.created', 'user.disabled', 'user.enabled', 'user.rejected', 'user.role_assigned', 'user.role_removed', 'user.updated')")

def downgrade() -> None:
    raise RuntimeError("retain registered administrative task audit history")
