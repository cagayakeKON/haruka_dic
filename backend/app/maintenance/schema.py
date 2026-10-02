"""Read-only schema compatibility checks; neither import nor checking can migrate."""

import re
from importlib.resources import files
from typing import Literal

from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from pydantic import BaseModel, ConfigDict, ValidationError
from sqlalchemy import CheckConstraint, Connection, String, column, inspect, select, text
from sqlalchemy import table as sql_table
from sqlalchemy.ext.asyncio import AsyncEngine
from sqlalchemy.schema import SchemaItem

from app.models import Base

EXPECTED_REVISION = "0014_material_sources"


class SchemaMismatchError(RuntimeError):
    """Safe compatibility error, containing no SQL, row data or connection details."""


class ConstraintBaseline(BaseModel):
    """Reviewed PostgreSQL canonical expressions, paired with their exact model sources."""

    model_config = ConfigDict(extra="forbid", frozen=True)
    revision: Literal["0014_material_sources"]
    model_checks: dict[str, dict[str, str]]
    database_checks: dict[str, dict[str, str]]


def load_constraint_baseline() -> ConstraintBaseline:
    try:
        value = (
            files("app.maintenance").joinpath("schema_baseline.json").read_text(encoding="utf-8")
        )
        baseline = ConstraintBaseline.model_validate_json(value)
    except (OSError, ValidationError) as error:
        raise SchemaMismatchError(
            "the packaged database constraint baseline is missing or invalid"
        ) from error
    model_checks = {
        table.name: {
            str(constraint.name): str(constraint.sqltext)
            for constraint in table.constraints
            if isinstance(constraint, CheckConstraint)
        }
        for table in Base.metadata.sorted_tables
    }
    if baseline.model_checks != model_checks or set(baseline.database_checks) != set(model_checks):
        raise SchemaMismatchError("model constraints differ from the reviewed database baseline")
    return baseline


def _include_business_object(
    _object: SchemaItem,
    name: str | None,
    type_: str,
    _reflected: bool,
    _compare_to: SchemaItem | None,
) -> bool:
    # Alembic's version-table exclusion compares literal schemas; a fixed test
    # search_path reflects that internal table with schema=None instead.
    return not (type_ == "table" and name == "alembic_version")


def validate_schema_name(schema: str) -> None:
    if schema != "public" and not re.fullmatch(r"haruka_migration_test_[a-f0-9]{32}", schema):
        raise ValueError("only public or an explicitly isolated migration test schema is allowed")


def current_revision(connection: Connection, schema: str) -> str | None:
    validate_schema_name(schema)
    if not inspect(connection).has_table("alembic_version", schema=schema):
        return None
    version = sql_table("alembic_version", column("version_num", String(32)), schema=schema)
    rows = connection.execute(select(version.c.version_num)).scalars().all()
    if not rows:
        return None
    if len(rows) != 1 or not isinstance(rows[0], str):
        raise SchemaMismatchError("database must contain exactly one migration revision")
    return rows[0]


def check_schema_connection(connection: Connection, schema: str = "public") -> None:
    """Check revision, reflected structure and comments on the already owned connection."""
    validate_schema_name(schema)
    if (
        connection.scalar(text("SELECT current_schema()")) != schema
        or connection.scalar(text("SHOW search_path")) != schema
        or connection.dialect.default_schema_name != schema
    ):
        raise SchemaMismatchError(
            "database connection search path differs from the requested schema"
        )
    if current_revision(connection, schema) != EXPECTED_REVISION:
        raise SchemaMismatchError("database revision is not compatible with this application")
    if not Base.metadata.tables:
        raise SchemaMismatchError("registered model metadata must not be empty")
    baseline = load_constraint_baseline()
    context = MigrationContext.configure(
        connection,
        opts={
            "compare_type": True,
            "compare_server_default": True,
            "version_table_schema": schema,
            "include_object": _include_business_object,
        },
    )
    if compare_metadata(context, Base.metadata):
        raise SchemaMismatchError("database schema differs from registered application models")
    inspector = inspect(connection)
    for table in Base.metadata.sorted_tables:
        if inspector.get_foreign_keys(table.name, schema=schema):
            raise SchemaMismatchError("physical foreign keys are forbidden")
        if inspector.get_table_comment(table.name, schema=schema).get("text") != table.comment:
            raise SchemaMismatchError("database table comments differ from application models")
        columns = {
            column["name"]: column for column in inspector.get_columns(table.name, schema=schema)
        }
        if any(columns[column.name].get("comment") != column.comment for column in table.columns):
            raise SchemaMismatchError("database column comments differ from application models")
        primary_key = inspector.get_pk_constraint(table.name, schema=schema)
        if primary_key.get("name") != table.primary_key.name or primary_key.get(
            "constrained_columns"
        ) != [column.name for column in table.primary_key.columns]:
            raise SchemaMismatchError("database primary key differs from application models")
        actual_checks = {
            check["name"]: check["sqltext"]
            for check in inspector.get_check_constraints(table.name, schema=schema)
        }
        if actual_checks != baseline.database_checks[table.name]:
            raise SchemaMismatchError(
                "database check constraints differ from the reviewed migration"
            )
    invalid_checks = connection.scalar(
        text(
            "SELECT COUNT(*) FROM pg_constraint AS constraint_row "
            "JOIN pg_namespace AS namespace ON namespace.oid=constraint_row.connamespace "
            "WHERE namespace.nspname=:schema AND NOT constraint_row.convalidated"
        ),
        {"schema": schema},
    )
    if invalid_checks != 0:
        raise SchemaMismatchError(
            "database contains constraints whose existing data has not been validated"
        )


async def check_schema(engine: AsyncEngine, *, schema: str = "public") -> None:
    validate_schema_name(schema)
    async with engine.connect() as connection:
        if (
            schema != "public"
            and await connection.scalar(text("SELECT current_database()")) != "haruka_test"
        ):
            raise SchemaMismatchError("migration test schemas require the isolated test database")
        await connection.run_sync(check_schema_connection, schema)


async def check_revision(engine: AsyncEngine, *, schema: str = "public") -> None:
    """Probe the current Alembic head without reflecting application tables.

    This is the per-request readiness path. Startup and maintenance keep the
    complete schema check; this probe only proves the live connection targets
    the expected schema and has exactly one reviewed revision row.
    """
    validate_schema_name(schema)
    async with engine.connect() as connection:
        if (
            schema != "public"
            and await connection.scalar(text("SELECT current_database()")) != "haruka_test"
        ):
            raise SchemaMismatchError("migration test schemas require the isolated test database")
        if (
            await connection.scalar(text("SELECT current_schema()")) != schema
            or await connection.scalar(text("SHOW search_path")) != schema
        ):
            raise SchemaMismatchError(
                "database connection search path differs from the requested schema"
            )
        if (
            await connection.scalar(
                text("SELECT to_regclass(:table_name)"), {"table_name": f"{schema}.alembic_version"}
            )
            is None
        ):
            raise SchemaMismatchError("database migration revision is missing")
        version = sql_table("alembic_version", column("version_num", String(32)), schema=schema)
        rows = (await connection.execute(select(version.c.version_num).limit(2))).scalars().all()
        if len(rows) != 1 or rows[0] != EXPECTED_REVISION:
            raise SchemaMismatchError("database revision is not compatible with this application")
