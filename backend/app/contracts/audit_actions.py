"""Published admin audit actions. The database check and writers share this list."""

AUDIT_ACTIONS: tuple[str, ...] = (
    "account.registered",
    "admin.created",
    "auth.login.denied",
    "auth_policy.updated",
    "authorization.denied",
    "email.verified",
    "grant_boundary.updated",
    "menu.updated",
    "password.changed",
    "password.recovered",
    "recovery.accepted",
    "recovery.challenge_issued",
    "recovery.completed",
    "recovery.rejected",
    "recovery.requested",
    "recovery.verified",
    "refresh.replayed",
    "role.created",
    "role.deleted",
    "role.inheritance_changed",
    "role.permission_assigned",
    "role.updated",
    "seed.applied",
    "session.created",
    "session.revoked",
    "user.approved",
    "user.created",
    "user.disabled",
    "user.enabled",
    "user.rejected",
    "user.role_assigned",
    "user.role_removed",
    "user.updated",
)


def audit_action_check_sql() -> str:
    quoted = ", ".join(f"'{action}'" for action in AUDIT_ACTIONS)
    return f"action IN ({quoted})"
