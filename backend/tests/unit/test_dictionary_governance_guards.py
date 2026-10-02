"""Registered schema guard failures are rejected without touching live metadata/DDL."""

from copy import deepcopy

import pytest
from sqlalchemy import CheckConstraint, DateTime, Index, Integer, MetaData

from app.models import Base
from app.models.dictionary import ModelContractError, validate_metadata

pytestmark = pytest.mark.unit


@pytest.fixture
def metadata() -> MetaData:
    clone = MetaData()
    for table in Base.metadata.tables.values():
        copied = table.to_metadata(clone)
        copied.info = deepcopy(table.info)
        for column in copied.columns:
            column.info = deepcopy(table.c[column.name].info)
        indexes = {index.name: index for index in table.indexes}
        for index in copied.indexes:
            index.info = deepcopy(indexes[index.name].info)
        for constraint in copied.constraints:
            if isinstance(constraint, CheckConstraint):
                original = next(
                    item
                    for item in table.constraints
                    if isinstance(item, CheckConstraint)
                    and str(item.sqltext) == str(constraint.sqltext)
                )
                constraint.name = original.name
    return clone


@pytest.mark.parametrize(
    "fault",
    [
        "unstructured",
        "nonlist",
        "source_absent",
        "duplicate_source",
        "target_not_string",
        "target_absent",
        "target_column_absent",
        "nullable",
        "lifecycle",
        "different_type",
        "unreviewed_uuid",
        "correlation_wrong_type",
    ],
)
def test_logical_reference_guard_requires_registered_ownership_and_lifecycle(
    metadata: MetaData,
    fault: str,
) -> None:
    library = metadata.tables["libraries"]
    relations = deepcopy(library.info["logical_relations"])
    if fault == "nonlist":
        library.info["logical_relations"] = {}
    elif fault == "unstructured":
        library.info["logical_relations"] = ["not structured"]
    elif fault == "unreviewed_uuid":
        library.c.owner_user_id.info["non_entity_uuid"] = "operation_correlation"
    elif fault == "correlation_wrong_type":
        metadata.tables["jobs"].c.operation_id.type = Integer()
    else:
        relation = next(item for item in relations if item["column"] == "owner_user_id")
        if fault == "source_absent":
            relation["column"] = "missing_owner_id"
        elif fault == "duplicate_source":
            relations.append(deepcopy(relation))
        elif fault == "target_not_string":
            relation["target"] = 1
        elif fault == "target_absent":
            relation["target"] = "missing_users.id"
        elif fault == "target_column_absent":
            relation["target"] = "users.missing_id"
        elif fault == "nullable":
            relation["nullable"] = True
        elif fault == "lifecycle":
            relation["parent_lock"] = ""
        else:
            library.c.owner_user_id.type = Integer()
        library.info["logical_relations"] = relations
    with pytest.raises(ModelContractError):
        validate_metadata(metadata)


@pytest.mark.parametrize(
    "fault",
    [
        "table_comment",
        "lifecycle",
        "relations_absent",
        "timezone",
        "nullable_time",
        "default_time",
        "owner_missing",
        "owner_nullable",
        "column_source",
        "column_sensitivity",
        "constraint_missing_name",
        "constraint_long_name",
        "index_missing_purpose",
        "index_long_name",
    ],
)
def test_schema_governance_guard_rejects_incomplete_physical_contract(
    metadata: MetaData,
    fault: str,
) -> None:
    users = metadata.tables["users"]
    library = metadata.tables["libraries"]
    if fault == "table_comment":
        users.comment = None
    elif fault == "lifecycle":
        users.info["allowed_entrances"] = []
    elif fault == "relations_absent":
        users.info.pop("logical_relations")
    elif fault == "timezone":
        users.c.created_at.type = DateTime(timezone=False)
    elif fault == "nullable_time":
        users.c.created_at.nullable = True
    elif fault == "default_time":
        users.c.created_at.server_default = None
    elif fault == "owner_missing":
        library.info["owner_column"] = "missing_owner"
    elif fault == "owner_nullable":
        library.c.owner_user_id.nullable = True
        for relation in library.info["logical_relations"]:
            if relation["column"] == "owner_user_id":
                relation["nullable"] = True
    elif fault == "column_source":
        users.c.email.info.pop("source")
    elif fault == "column_sensitivity":
        users.c.email.info.pop("sensitivity")
    elif fault == "constraint_missing_name":
        users.primary_key.name = None
    elif fault == "constraint_long_name":
        users.primary_key.name = "p" * 64
    elif fault == "index_missing_purpose":
        Index("ix_users_test_guard", users.c.password_version)
    else:
        Index("x" * 64, users.c.password_version, info={"purpose": "fault fixture"})
    with pytest.raises(ModelContractError):
        validate_metadata(metadata)
