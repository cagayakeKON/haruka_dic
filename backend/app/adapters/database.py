"""Process-owned SQLAlchemy pool; every use case opens its own short session."""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.settings import InfrastructureSettings


class Database:
    def __init__(self, settings: InfrastructureSettings) -> None:
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
            if await connection.scalar(text("SELECT 1")) != 1:
                raise RuntimeError("database probe failed")

    async def aclose(self) -> None:
        await self.engine.dispose()
