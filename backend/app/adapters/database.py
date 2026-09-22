"""Process-owned SQLAlchemy pool; every use case opens its own short session."""

from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.settings import CoreInfrastructureSettings


class Database:
    def __init__(self, settings: CoreInfrastructureSettings) -> None:
        address = make_url(settings.database_url.get_secret_value())
        self.expected_database = address.database
        self.expected_user = address.username
        self.engine = create_async_engine(
            settings.database_url.get_secret_value(),
            pool_size=5,
            max_overflow=5,
            pool_timeout=5,
            pool_pre_ping=True,
            echo=False,
            hide_parameters=True,
            connect_args={
                "timeout": 5,
                "command_timeout": 5,
                "server_settings": {
                    "application_name": settings.namespace,
                    "timezone": "UTC",
                    "search_path": "public",
                    "statement_timeout": "5000",
                    "idle_in_transaction_session_timeout": "10000",
                },
            },
        )
        self.sessions = async_sessionmaker[AsyncSession](self.engine, expire_on_commit=False)

    async def check(self) -> None:
        async with self.engine.connect() as connection:
            identity = (
                await connection.execute(
                    text(
                        "SELECT current_database(), current_user, "
                        "(SELECT rolsuper OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname=current_user), "
                        "has_schema_privilege(current_user, 'public', 'CREATE')"
                    )
                )
            ).one()
            if (
                identity[0] != self.expected_database
                or identity[1] != self.expected_user
                or identity[2] is not False
                or identity[3] is not False
                or identity[1] != f"{identity[0]}_runtime"
            ):
                raise RuntimeError("database runtime identity or privileges are unsafe")
            audit = await connection.scalar(text("SELECT to_regclass('public.admin_audit_events')"))
            if audit is not None and await connection.scalar(
                text(
                    "SELECT has_table_privilege(current_user, 'public.admin_audit_events', 'UPDATE,DELETE,TRUNCATE')"
                )
            ):
                raise RuntimeError("runtime database role must not modify audit history")

    async def aclose(self) -> None:
        await self.engine.dispose()
