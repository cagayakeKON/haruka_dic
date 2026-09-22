"""Only the controlled maintenance entry point may supply the already locked connection."""

from alembic import context
from sqlalchemy import Connection

from app.maintenance.migrations import MigrationError, verify_lock_owner
from app.models import Base


def run_migrations() -> None:
    if context.is_offline_mode():
        raise MigrationError("offline and bare Alembic operations cannot bypass the migration lock")
    connection: object = context.config.attributes.get("connection")
    if not isinstance(connection, Connection):
        raise MigrationError("use haruka-manage db upgrade with explicit maintenance configuration")
    ownership = verify_lock_owner(connection, context.config.attributes.get("lock_ownership"))
    connection.commit()
    context.configure(
        connection=connection,
        target_metadata=Base.metadata,
        version_table_schema=ownership.schema,
        transaction_per_migration=True,
        compare_type=True,
        compare_server_default=True,
    )
    with context.begin_transaction():
        context.run_migrations()


run_migrations()
