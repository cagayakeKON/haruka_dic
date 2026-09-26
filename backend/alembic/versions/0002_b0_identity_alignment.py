"""Align B0 identity metadata with the reviewed naming and scope contract.

The maintenance entrypoint owns the advisory lock and one physical connection.
Renames preserve association IDs and grants. The brief table locks and role
backfill are intentional; downgrade is forward-repair only because discarding
new identity/security facts would be destructive.
"""

import sqlalchemy as sa
from alembic import op

from app.maintenance.migrations import MigrationError

revision = "0002_b0_identity_alignment"
down_revision = "0001_b0_identity"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    bad_grants = connection.scalar(
        sa.text(
            "SELECT EXISTS (SELECT 1 FROM role_permissions AS grant_row "
            "LEFT JOIN roles AS role_row ON role_row.id=grant_row.role_id "
            "LEFT JOIN permission_catalog AS permission_row "
            "ON permission_row.code=grant_row.permission_code "
            "WHERE role_row.id IS NULL OR permission_row.code IS NULL "
            "OR permission_row.audience NOT IN ('client', 'admin') "
            "OR permission_row.data_scope <> CASE permission_row.audience "
            "WHEN 'client' THEN 'self' WHEN 'admin' THEN 'platform_metadata' END "
            "OR permission_row.audience <> split_part(grant_row.permission_code, '.', 1))"
        )
    )
    bad_memberships = connection.scalar(
        sa.text(
            "SELECT EXISTS (SELECT 1 FROM user_roles AS link "
            "LEFT JOIN users AS account ON account.id=link.user_id "
            "LEFT JOIN roles AS role_row ON role_row.id=link.role_id "
            "WHERE account.id IS NULL OR role_row.id IS NULL)"
        )
    )
    if bad_grants or bad_memberships:
        raise MigrationError("identity associations differ from the release catalog")

    op.rename_table("user_roles", "user_role_links")
    op.execute("ALTER TABLE user_role_links RENAME CONSTRAINT pk_user_roles TO pk_user_role_links")
    op.execute(
        "ALTER TABLE user_role_links RENAME CONSTRAINT "
        "uq_user_roles_user_id_role_id TO uq_user_role_links_user_id_role_id"
    )
    op.execute(
        "ALTER INDEX ix_user_roles_role_id_user_id RENAME TO ix_user_role_links_role_id_user_id"
    )

    op.rename_table("role_permissions", "role_permission_links")
    op.execute(
        "ALTER TABLE role_permission_links RENAME CONSTRAINT "
        "pk_role_permissions TO pk_role_permission_links"
    )
    op.execute(
        "ALTER TABLE role_permission_links RENAME CONSTRAINT "
        "ck_role_permissions_effect TO ck_role_permission_links_effect"
    )
    op.execute(
        "ALTER INDEX ix_role_permissions_permission_code_role_id "
        "RENAME TO ix_role_permission_links_permission_code_role_id"
    )
    op.add_column(
        "role_permission_links",
        sa.Column("data_scope", sa.String(length=24), nullable=True, comment="授权数据范围"),
    )
    op.execute(
        "UPDATE role_permission_links AS grant_row SET data_scope=permission_row.data_scope, "
        "updated_at=now() FROM permission_catalog AS permission_row "
        "WHERE permission_row.code=grant_row.permission_code"
    )
    op.alter_column("role_permission_links", "data_scope", nullable=False)
    op.create_check_constraint(
        op.f("ck_role_permission_links_data_scope"),
        "role_permission_links",
        "data_scope IN ('self', 'platform_metadata')",
    )
    op.drop_constraint(
        "uq_role_permissions_role_id_permission_code_effect",
        "role_permission_links",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_role_permission_links_role_id_permission_code_e_5e3b7fafe483",
        "role_permission_links",
        ["role_id", "permission_code", "effect", "data_scope"],
    )

    op.add_column(
        "roles", sa.Column("name", sa.String(length=100), nullable=True, comment="角色显示名")
    )
    op.add_column("roles", sa.Column("description", sa.Text(), nullable=True, comment="角色说明"))
    op.execute("UPDATE roles SET name=code, revision=revision+1, updated_at=now()")
    op.alter_column("roles", "name", nullable=False)

    op.add_column(
        "users",
        sa.Column(
            "password_version",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="密码哈希版本",
        ),
    )
    op.add_column(
        "users",
        sa.Column(
            "security_epoch",
            sa.BigInteger(),
            server_default=sa.text("0"),
            nullable=False,
            comment="全局持久撤销代次",
        ),
    )
    op.add_column(
        "users",
        sa.Column(
            "revision",
            sa.BigInteger(),
            server_default=sa.text("1"),
            nullable=False,
            comment="账号资料并发修改版本",
        ),
    )
    op.add_column(
        "users",
        sa.Column(
            "email_verified_at",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="邮箱实际验证时间",
        ),
    )
    op.add_column(
        "users",
        sa.Column(
            "locked_until", sa.DateTime(timezone=True), nullable=True, comment="账号限时锁定截止"
        ),
    )
    op.create_check_constraint(
        op.f("ck_users_password_version_positive"), "users", "password_version >= 1"
    )
    op.create_check_constraint(
        op.f("ck_users_security_epoch_nonnegative"), "users", "security_epoch >= 0"
    )
    op.create_check_constraint(op.f("ck_users_revision_positive"), "users", "revision >= 1")
    op.create_index("ix_users_status_created_at_id", "users", ["status", "created_at", "id"])


def downgrade() -> None:
    raise RuntimeError("identity/security alignment requires reviewed forward repair")
