"""Offline model registration checks and a deterministic, generated data dictionary."""

import hashlib
import json
import re
from typing import TypeGuard

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    DefaultClause,
    MetaData,
    PrimaryKeyConstraint,
    UniqueConstraint,
)
from sqlalchemy.dialects import postgresql
from sqlalchemy.dialects.postgresql import UUID as PgUUID

from app.maintenance.migrations import bundled_migration_head
from app.models import Base


class ModelContractError(ValueError):
    """A registered schema lacks a required invariant or documentation entry."""


def _record(value: object) -> TypeGuard[dict[str, object]]:
    return isinstance(value, dict)


def _records(value: object) -> TypeGuard[list[object]]:
    return isinstance(value, list)


def _validate_relations(metadata: MetaData, table_name: str) -> None:
    table = metadata.tables[table_name]
    relations: object = table.info.get("logical_relations")
    if not _records(relations):
        raise ModelContractError("logical relations must be a registered list")
    registered: set[str] = set()
    for relation in relations:
        if not _record(relation):
            raise ModelContractError("logical relation metadata must be structured")
        column, target = relation.get("column"), relation.get("target")
        if not isinstance(column, str) or column not in table.columns or column in registered:
            raise ModelContractError("logical relation source is missing or duplicated")
        if not isinstance(target, str):
            raise ModelContractError("logical relation target must be registered")
        parent, separator, key = target.partition(".")
        if (
            not separator
            or parent not in metadata.tables
            or key not in metadata.tables[parent].columns
        ):
            raise ModelContractError("logical relation target is absent from the model registry")
        if relation.get("nullable") != table.columns[column].nullable or not all(
            relation.get(field)
            for field in ("scope_rule", "state_rule", "parent_lock", "deletion", "service", "tests")
        ):
            raise ModelContractError(
                "logical relation requires matching NULL rules and complete lifecycle evidence"
            )
        dialect = postgresql.dialect()
        if table.columns[column].type.compile(dialect=dialect) != metadata.tables[parent].columns[
            key
        ].type.compile(dialect=dialect):
            raise ModelContractError("logical relation column types differ")
        alternatives = relation.get("alternative_targets", {})
        if not _record(alternatives):
            raise ModelContractError("alternative relation targets must be structured")
        for discriminator, alternate in alternatives.items():
            if not discriminator or not isinstance(alternate, str):
                raise ModelContractError("alternative relation targets must be registered")
            alternate_parent, separator, alternate_key = alternate.partition(".")
            if (
                not separator
                or alternate_parent not in metadata.tables
                or alternate_key not in metadata.tables[alternate_parent].columns
                or table.columns[column].type.compile(dialect=dialect)
                != metadata.tables[alternate_parent]
                .columns[alternate_key]
                .type.compile(dialect=dialect)
            ):
                raise ModelContractError(
                    "alternative relation target is absent or has a different type"
                )
        registered.add(column)
    implied: set[str] = set()
    for column in table.columns:
        if table_name in {"ai_runs", "external_call_attempts"} and column.name == "model_id":
            # Published supplier model code, not a database entity UUID.
            continue
        marker = column.info.get("non_entity_uuid")
        if marker is not None:
            reviewed = (
                (
                    table_name == "jobs"
                    and column.name in {"operation_id", "request_id"}
                    and marker == "operation_correlation"
                )
                or (
                    table_name == "idempotency_records"
                    and column.name == "operation_id"
                    and marker == "operation_correlation"
                )
                or (
                    table_name == "admin_audit_events"
                    and (
                        (
                            column.name in {"operation_id", "request_id"}
                            and marker == "operation_correlation"
                        )
                        or (column.name == "target_id" and marker == "polymorphic_target")
                    )
                )
            )
            if not reviewed or not isinstance(column.type, PgUUID):
                raise ModelContractError(
                    "non-entity UUID exception is not a reviewed audit/correlation identity"
                )
            continue
        if column.name.endswith("_id") or column.name == "permission_code":
            implied.add(column.name)
    if not implied <= registered:
        raise ModelContractError("reference columns are missing logical relation metadata")


def validate_metadata(metadata: MetaData) -> None:
    """Reject empty registries, physical FKs, incomplete ownership and index duplication."""
    if not metadata.tables:
        raise ModelContractError("model registry must not be empty")
    identifiers: set[str] = set()
    scopes = {
        "identity",
        "user_owned",
        "library_root",
        "library_owned",
        "system_catalog",
        "system_operation",
    }
    for table in metadata.sorted_tables:
        if not re.fullmatch(r"[a-z][a-z0-9_]*", table.name) or not table.comment:
            raise ModelContractError("table requires a snake_case name and a comment")
        if table.foreign_keys:
            raise ModelContractError("physical foreign keys are forbidden")
        if table.info.get("scope_kind") not in scopes:
            raise ModelContractError("table scope must be explicitly registered")
        if not all(
            table.info.get(key)
            for key in ("lifecycle", "allowed_entrances", "deletion_policy", "module")
        ):
            raise ModelContractError("table lifecycle and controlled entrances must be documented")
        if "logical_relations" not in table.info:
            raise ModelContractError("logical relations must be explicitly registered")
        _validate_relations(metadata, table.name)
        for key in ("created_at", "updated_at"):
            if key not in table.columns:
                raise ModelContractError("all business tables require UTC timestamps")
            timestamp = table.columns[key]
            if (
                not isinstance(timestamp.type, DateTime)
                or not timestamp.type.timezone
                or timestamp.nullable
                or timestamp.server_default is None
            ):
                raise ModelContractError(
                    "timestamps require timezone, NOT NULL and a server default"
                )
        owner = table.info.get("owner_column")
        if table.info["scope_kind"] in {"user_owned", "library_root", "library_owned"} and (
            not isinstance(owner, str)
            or owner not in table.columns
            or table.columns[owner].nullable
        ):
            raise ModelContractError("private tables require an authoritative nonnullable owner")
        if table.info["scope_kind"] == "library_owned" and "library_id" not in table.columns:
            raise ModelContractError("library-owned tables require library_id")
        for column in table.columns:
            if (
                not column.comment
                or not column.info.get("source")
                or not column.info.get("sensitivity")
            ):
                raise ModelContractError("every column requires meaning, source and sensitivity")
        signatures: set[tuple[str, ...]] = set()
        for constraint in table.constraints:
            if constraint.name is None:
                raise ModelContractError("constraints must have deterministic names")
            name = str(constraint.name)
            if not name.isascii() or len(name) > 63 or name in identifiers:
                raise ModelContractError(
                    "constraint names must be unique ASCII identifiers of at most 63 bytes"
                )
            identifiers.add(name)
            if isinstance(constraint, (PrimaryKeyConstraint, UniqueConstraint)):
                signatures.add(tuple(column.name for column in constraint.columns))
        for index in table.indexes:
            name = str(index.name)
            if index.name is None or not name.isascii() or len(name) > 63 or name in identifiers:
                raise ModelContractError("index names must be registered and unique")
            identifiers.add(name)
            signature = tuple(column.name for column in index.columns)
            if signature in signatures:
                raise ModelContractError("an index duplicates an existing key or index")
            signatures.add(signature)
            if not index.info.get("purpose"):
                raise ModelContractError("indexes require a documented query purpose")


def database_document(metadata: MetaData | None = None) -> dict[str, object]:
    """Export only registered models; Alembic's internal version table is explicitly excluded."""
    selected = Base.metadata if metadata is None else metadata
    validate_metadata(selected)
    tables: list[dict[str, object]] = []
    dialect = postgresql.dialect()
    for table in selected.sorted_tables:
        tables.append(
            {
                "name": table.name,
                "comment": table.comment,
                "metadata": table.info,
                "columns": [
                    {
                        "name": column.name,
                        "type": column.type.compile(dialect=dialect),
                        "nullable": column.nullable,
                        "primary_key": column.primary_key,
                        "default": str(column.server_default.arg)
                        if isinstance(column.server_default, DefaultClause)
                        else None,
                        "comment": column.comment,
                        "metadata": column.info,
                    }
                    for column in table.columns
                ],
                "constraints": [
                    {
                        "name": str(constraint.name),
                        "kind": "check"
                        if isinstance(constraint, CheckConstraint)
                        else (
                            "primary_key"
                            if isinstance(constraint, PrimaryKeyConstraint)
                            else "unique"
                        ),
                        "definition": str(constraint.sqltext)
                        if isinstance(constraint, CheckConstraint)
                        else [column.name for column in constraint.columns]
                        if isinstance(constraint, (PrimaryKeyConstraint, UniqueConstraint))
                        else [],
                    }
                    for constraint in sorted(table.constraints, key=lambda item: str(item.name))
                ],
                "indexes": [
                    {
                        "name": index.name,
                        "columns": [column.name for column in index.columns],
                        "unique": index.unique,
                        "metadata": index.info,
                    }
                    for index in sorted(table.indexes, key=lambda item: str(item.name))
                ],
            }
        )
    source = json.dumps(tables, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {
        "schema_version": 1,
        "migration_revision": bundled_migration_head(),
        "source": "backend/app/models",
        "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "excluded_internal_tables": ["alembic_version"],
        "tables": tables,
    }
