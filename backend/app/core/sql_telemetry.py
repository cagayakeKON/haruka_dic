"""Parameter-free SQL timing and failure events for an application engine."""

import hashlib
import logging
import re
import threading
import time
from weakref import WeakKeyDictionary

from sqlalchemy import event
from sqlalchemy.engine import (
    Connection,
    Engine,
    ExceptionContext,
    ExecutionContext,
)
from sqlalchemy.engine.interfaces import DBAPICursor
from sqlalchemy.exc import TimeoutError as PoolTimeoutError
from sqlalchemy.ext.asyncio import AsyncEngine
from sqlalchemy.pool import AsyncAdaptedQueuePool, ConnectionPoolEntry

from app.domain.correlation import (
    audience_context,
    current_correlation,
    user_id_context,
)

_LOG = logging.getLogger("haruka.database")
_KIND = re.compile(r"^\s*([A-Za-z]+)")
_SQLSTATE = re.compile(r"[0-9A-Z]{5}\Z")
_ALLOWED_KINDS = frozenset(
    {"SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "CREATE", "ALTER", "DROP", "COMMENT"}
)


def _server_pid(connection: Connection | None) -> int | None:
    if connection is None:
        return None
    try:
        # SQLAlchemy's public proxied DBAPI connection exposes the original
        # asyncpg connection. get_server_pid is a public, query-free API.
        driver = connection.connection.driver_connection
        if driver is None:
            return None
        pid: object = driver.get_server_pid()
    except Exception:  # An invalidated connection must not break logging.
        return None
    return pid if type(pid) is int and 0 < pid <= 2_147_483_647 else None


def _sqlstate(error: BaseException) -> str | None:
    current: BaseException | None = error
    seen: set[int] = set()
    for _ in range(4):
        if current is None or id(current) in seen:
            break
        seen.add(id(current))
        value: object = getattr(current, "sqlstate", None)
        if isinstance(value, str) and _SQLSTATE.fullmatch(value):
            return value
        current = current.__cause__ or current.__context__
    return None


def _metadata(
    statement: str | None,
    *,
    database_name: str | None = None,
    application_name: str | None = None,
    connection: Connection | None = None,
    sqlstate: str | None = None,
) -> dict[str, object]:
    metadata: dict[str, object] = {}
    if database_name is not None:
        metadata["database_name"] = database_name
    if application_name is not None:
        metadata["application_name"] = application_name
    pid = _server_pid(connection)
    if pid is not None:
        metadata["backend_pid"] = pid
    if sqlstate is not None:
        metadata["sqlstate"] = sqlstate
    if statement is not None:
        # The statement, its values and the driver exception never enter a log record.
        metadata["sql_fingerprint"] = hashlib.sha256(
            statement.encode("utf-8", errors="replace")
        ).hexdigest()[:32]
        match = _KIND.match(statement)
        metadata["statement_kind"] = (
            match.group(1).upper()
            if match is not None and match.group(1).upper() in _ALLOWED_KINDS
            else "OTHER"
        )
    request_id, operation_id = current_correlation()
    if request_id is not None:
        metadata["request_id"] = request_id
    if operation_id is not None:
        metadata["operation_id"] = operation_id
    user_id = user_id_context.get()
    if user_id is not None:
        metadata["user_id"] = user_id
    audience = audience_context.get()
    if audience in {"client", "admin"}:
        metadata["audience"] = audience
    return metadata


class TelemetryAsyncQueuePool(AsyncAdaptedQueuePool):
    """Classify exhausted pool waits that never reach engine error events."""

    telemetry_database_name: str | None = None
    telemetry_application_name: str | None = None

    def _do_get(self) -> ConnectionPoolEntry:
        try:
            return super()._do_get()
        except PoolTimeoutError:
            _LOG.warning(
                "database.connection.failed",
                extra=_metadata(
                    None,
                    database_name=self.telemetry_database_name,
                    application_name=self.telemetry_application_name,
                ),
            )
            raise
        except Exception as error:
            # Async driver connection failures can occur before SQLAlchemy
            # creates an ExceptionContext, so handle_error never sees them.
            _LOG.warning(
                "database.connection.failed",
                extra=_metadata(
                    None,
                    database_name=self.telemetry_database_name,
                    application_name=self.telemetry_application_name,
                    sqlstate=_sqlstate(error),
                ),
            )
            raise


def install_sql_telemetry(
    engine: AsyncEngine | Engine,
    *,
    database_name: str | None = None,
    application_name: str | None = None,
) -> None:
    """Attach safe listeners once to the actual engine used by API and workers."""
    sync_engine = engine.sync_engine if isinstance(engine, AsyncEngine) else engine
    if isinstance(sync_engine.pool, TelemetryAsyncQueuePool):
        sync_engine.pool.telemetry_database_name = database_name
        sync_engine.pool.telemetry_application_name = application_name
    starts: WeakKeyDictionary[ExecutionContext, float] = WeakKeyDictionary()
    starts_lock = threading.Lock()

    @event.listens_for(sync_engine, "before_cursor_execute")
    def before_execute(
        conn: Connection,
        cursor: DBAPICursor,
        statement: str,
        parameters: object,
        context: ExecutionContext,
        executemany: bool,
    ) -> None:
        with starts_lock:
            starts[context] = time.monotonic()

    @event.listens_for(sync_engine, "after_cursor_execute")
    def after_execute(
        conn: Connection,
        cursor: DBAPICursor,
        statement: str,
        parameters: object,
        context: ExecutionContext,
        executemany: bool,
    ) -> None:
        with starts_lock:
            started = starts.pop(context, None)
        if not isinstance(started, float):
            return
        _LOG.info(
            "database.query.completed",
            extra={
                **_metadata(
                    statement,
                    database_name=database_name,
                    application_name=application_name,
                    connection=conn,
                ),
                "duration_ms": (time.monotonic() - started) * 1000,
            },
        )

    @event.listens_for(sync_engine, "handle_error")
    def failed_execute(exception_context: ExceptionContext) -> None:
        execution_context = exception_context.execution_context
        with starts_lock:
            started = starts.pop(execution_context, None) if execution_context is not None else None
        extra = _metadata(
            exception_context.statement,
            database_name=database_name,
            application_name=application_name,
            connection=exception_context.connection,
            sqlstate=_sqlstate(exception_context.original_exception),
        )
        if isinstance(started, float):
            extra["duration_ms"] = (time.monotonic() - started) * 1000
        if exception_context.statement is not None:
            _LOG.warning("database.query.failed", extra=extra)
        else:
            _LOG.warning("database.connection.failed", extra=extra)

    @event.listens_for(sync_engine, "rollback")
    def transaction_rolled_back(connection: Connection) -> None:
        _LOG.info(
            "database.transaction.rolled_back",
            extra=_metadata(
                None,
                database_name=database_name,
                application_name=application_name,
                connection=connection,
            ),
        )
