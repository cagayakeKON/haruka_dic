"""Role inheritance, grant ceilings, menu conditions, and approval status.

Static DDL reviewed from the release model. Run only through controlled maintenance.
No physical foreign keys.
"""

import re

import sqlalchemy as sa
from alembic import op

revision = "0007_authorization_governance"
down_revision = "0006_avatar_assets"
branch_labels = None
depends_on = None

_BOUNDARY_SHAPE = (
    "(boundary_kind IN ('assign_role', 'manage_account_role') "
    "AND target_role_id IS NOT NULL AND permission_code IS NULL AND data_scope IS NULL) "
    "OR (boundary_kind = 'assign_permission' AND target_role_id IS NULL "
    "AND permission_code IS NOT NULL AND data_scope IN ('self', 'platform_metadata')) "
    "OR (boundary_kind = 'manage_unassigned_accounts' AND target_role_id IS NULL "
    "AND permission_code IS NULL AND data_scope IS NULL)"
)


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "approval_status",
            sa.String(16),
            nullable=False,
            server_default=sa.text("'not_required'"),
            comment="审批状态；既有账号回填为不需要审批",
        ),
    )
    op.create_check_constraint(
        op.f("ck_users_approval_status"),
        "users",
        "approval_status IN ('not_required', 'pending', 'approved', 'rejected')",
    )
    op.drop_constraint(op.f("ck_auth_policies_recovery_mode"), "auth_policies", type_="check")
    op.create_check_constraint(
        op.f("ck_auth_policies_recovery_mode"),
        "auth_policies",
        "recovery_mode IN ('disabled', 'email', 'manual', 'email_or_manual')",
    )
    op.drop_constraint(
        op.f("ck_user_auth_challenges_purpose"), "user_auth_challenges", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_user_auth_challenges_purpose"),
        "user_auth_challenges",
        "purpose IN ('email_verify', 'password_recovery', 'reauth', 'manual_recovery')",
    )
    op.drop_constraint(op.f("ck_admin_audit_events_action"), "admin_audit_events", type_="check")
    op.create_check_constraint(
        op.f("ck_admin_audit_events_action"),
        "admin_audit_events",
        "action IN ("
        "'account.registered', 'admin.created', 'auth.login.denied', 'auth_policy.updated', "
        "'authorization.denied', 'email.verified', 'grant_boundary.updated', 'menu.updated', "
        "'password.changed', 'password.recovered', 'recovery.accepted', "
        "'recovery.challenge_issued', 'recovery.completed', 'recovery.rejected', "
        "'recovery.requested', 'recovery.verified', 'refresh.replayed', 'role.created', "
        "'role.deleted', 'role.inheritance_changed', 'role.permission_assigned', "
        "'role.updated', 'seed.applied', 'session.created', 'session.revoked', "
        "'user.approved', 'user.created', 'user.disabled', 'user.enabled', 'user.rejected', "
        "'user.role_assigned', 'user.role_removed', 'user.updated'"
        ")",
    )
    op.add_column(
        "menus",
        sa.Column("parent_menu_id", sa.UUID(), nullable=True, comment="同受众父菜单；空表示顶层"),
    )
    op.add_column(
        "menus",
        sa.Column(
            "component_key",
            sa.String(64),
            nullable=True,
            comment="已发布组件键；分组可为空",
        ),
    )
    op.add_column(
        "menus",
        sa.Column("title", sa.String(100), nullable=True, comment="菜单标题"),
    )
    op.add_column(
        "menus",
        sa.Column("icon_key", sa.String(64), nullable=True, comment="已发布图标键"),
    )
    op.add_column(
        "menus",
        sa.Column(
            "sort_order",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
            comment="同级显示顺序",
        ),
    )
    op.add_column(
        "menus",
        sa.Column(
            "permission_match",
            sa.String(3),
            nullable=False,
            server_default=sa.text("'all'"),
            comment="附加显示条件的all或any匹配",
        ),
    )
    op.execute("UPDATE menus SET title = code, updated_at = now() WHERE title IS NULL")
    op.alter_column("menus", "title", existing_type=sa.String(100), nullable=False)
    op.alter_column(
        "menus",
        "route_key",
        existing_type=sa.String(64),
        nullable=True,
        comment="前端已注册路由键；分组可为空",
    )
    op.create_check_constraint(op.f("ck_menus_sort_order_nonnegative"), "menus", "sort_order >= 0")
    op.create_check_constraint(
        op.f("ck_menus_permission_match"), "menus", "permission_match IN ('all', 'any')"
    )
    op.create_index(
        "ix_menus_audience_parent_sort",
        "menus",
        ["audience", "parent_menu_id", "sort_order", "id"],
    )
    op.create_table(
        "menu_permission_links",
        sa.Column("menu_id", sa.UUID(), nullable=False, comment="已锁定菜单"),
        sa.Column(
            "permission_code",
            sa.String(100),
            nullable=False,
            comment="附加显示所需的已注册权限",
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_menu_permission_links")),
        sa.UniqueConstraint(
            "menu_id",
            "permission_code",
            name=op.f("uq_menu_permission_links_menu_id_permission_code"),
        ),
        comment="菜单附加显示权限；不能降低页面最低权限",
    )
    op.create_index(
        "ix_menu_permission_links_permission_menu",
        "menu_permission_links",
        ["permission_code", "menu_id"],
    )
    op.execute(
        "INSERT INTO menu_permission_links (id, menu_id, permission_code, created_at, updated_at) "
        "SELECT gen_random_uuid(), id, permission_code, now(), now() FROM menus"
    )
    bind = op.get_bind()
    copied = bind.scalar(
        sa.text(
            "SELECT COUNT(*) FROM menus AS menu "
            "JOIN menu_permission_links AS link "
            "ON link.menu_id = menu.id AND link.permission_code = menu.permission_code"
        )
    )
    if copied != bind.scalar(sa.text("SELECT COUNT(*) FROM menus")):
        raise RuntimeError("menu permission links were not copied completely")
    op.drop_column("menus", "permission_code")
    op.create_table(
        "role_inheritance_links",
        sa.Column("child_role_id", sa.UUID(), nullable=False, comment="继承方角色"),
        sa.Column("parent_role_id", sa.UUID(), nullable=False, comment="被继承的父角色"),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_role_inheritance_links")),
        sa.UniqueConstraint(
            "child_role_id",
            "parent_role_id",
            name=op.f("uq_role_inheritance_links_child_role_id_parent_role_id"),
        ),
        sa.CheckConstraint(
            "child_role_id <> parent_role_id",
            name=op.f("ck_role_inheritance_links_distinct_roles"),
        ),
        comment="角色有向继承；无环和深度由授权事务校验",
    )
    op.create_index(
        "ix_role_inheritance_links_parent_child",
        "role_inheritance_links",
        ["parent_role_id", "child_role_id"],
    )
    op.create_table(
        "role_grant_boundaries",
        sa.Column("grantor_role_id", sa.UUID(), nullable=False, comment="形成上限的操作者角色"),
        sa.Column(
            "boundary_kind",
            sa.String(32),
            nullable=False,
            comment="assign_role、assign_permission、manage_account_role或manage_unassigned_accounts",
        ),
        sa.Column(
            "target_role_id",
            sa.UUID(),
            nullable=True,
            comment="可分配或可管理成员的目标角色",
        ),
        sa.Column(
            "permission_code",
            sa.String(100),
            nullable=True,
            comment="可配置到角色上的已注册权限",
        ),
        sa.Column(
            "data_scope",
            sa.String(24),
            nullable=True,
            comment="可配置权限的数据范围",
        ),
        sa.Column(
            "revision",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("1"),
            comment="授予上限并发版本",
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_role_grant_boundaries")),
        sa.CheckConstraint(
            "revision >= 1", name=op.f("ck_role_grant_boundaries_revision_positive")
        ),
        sa.CheckConstraint(_BOUNDARY_SHAPE, name=op.f("ck_role_grant_boundaries_boundary_shape")),
        comment="委派管理员的授予上限；不能借此提高自身权限",
    )
    op.create_index(
        "uq_role_grant_boundaries_role_target",
        "role_grant_boundaries",
        ["grantor_role_id", "boundary_kind", "target_role_id"],
        unique=True,
        postgresql_where=sa.text("target_role_id IS NOT NULL"),
    )
    op.create_index(
        "uq_role_grant_boundaries_permission",
        "role_grant_boundaries",
        ["grantor_role_id", "boundary_kind", "permission_code", "data_scope"],
        unique=True,
        postgresql_where=sa.text("permission_code IS NOT NULL"),
    )
    op.create_index(
        "uq_role_grant_boundaries_unassigned",
        "role_grant_boundaries",
        ["grantor_role_id", "boundary_kind"],
        unique=True,
        postgresql_where=sa.text("boundary_kind = 'manage_unassigned_accounts'"),
    )
    op.create_index(
        "ix_role_grant_boundaries_target_grantor",
        "role_grant_boundaries",
        ["target_role_id", "grantor_role_id"],
    )
    op.create_table(
        "permission_dependency_links",
        sa.Column(
            "permission_code",
            sa.String(100),
            nullable=False,
            comment="依赖其他权限的已注册权限",
        ),
        sa.Column(
            "required_permission_code",
            sa.String(100),
            nullable=False,
            comment="必须同时成立的已注册权限",
        ),
        sa.Column("id", sa.UUID(), nullable=False, comment="服务端生成的稳定标识"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行创建时间，UTC",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
            comment="本行最近一次实际更新的时间，UTC",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_permission_dependency_links")),
        sa.UniqueConstraint(
            "permission_code",
            "required_permission_code",
            name="uq_permission_dependency_links_pair",
        ),
        sa.CheckConstraint(
            "permission_code <> required_permission_code",
            name=op.f("ck_permission_dependency_links_distinct_permissions"),
        ),
        comment="发布注册的静态权限依赖；不表达运行时复合条件",
    )
    op.create_index(
        "ix_permission_dependency_links_required",
        "permission_dependency_links",
        ["required_permission_code", "permission_code"],
    )
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
    raise RuntimeError("authorization governance requires reviewed forward repair")
