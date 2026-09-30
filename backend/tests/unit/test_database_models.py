"""DB-01/11: incomplete model metadata must fail before migration or generation."""

from copy import deepcopy

import pytest
from sqlalchemy import Column, ForeignKeyConstraint, Index, Integer, MetaData, Table

from app.models import Base
from app.models.base import identifier
from app.models.dictionary import ModelContractError, database_document, validate_metadata

pytestmark = pytest.mark.unit


def test_dictionary_is_nonempty_deterministic_and_has_no_foreign_keys() -> None:
    first = database_document()
    assert first == database_document()
    assert len(Base.metadata.tables) == 33
    assert all(not table.foreign_keys for table in Base.metadata.tables.values())
    assert first["source_sha256"]
    name = "ix_" + "column_" * 20
    assert len(identifier(name)) <= 63
    assert identifier(name) == identifier(name)
    assert identifier(name) != identifier(name + "other")


@pytest.mark.parametrize(
    "failure",
    [
        "empty",
        "timestamp",
        "scope",
        "comment",
        "foreign_key",
        "duplicate_index",
        "missing_relation",
    ],
)
def test_bad_model_registry_is_rejected(failure: str) -> None:
    metadata = MetaData(naming_convention=Base.metadata.naming_convention)
    for registered in Base.metadata.tables.values():
        copied = registered.to_metadata(metadata)
        copied.info = deepcopy(registered.info)
    users = metadata.tables["users"]
    if failure == "empty":
        metadata.clear()
    elif failure == "timestamp":
        metadata.clear()
        Table(
            "users",
            metadata,
            Column("id", Integer, primary_key=True),
            comment=users.comment,
            info=deepcopy(users.info),
        )
    elif failure == "scope":
        users.info.pop("scope_kind")
    elif failure == "comment":
        users.c.email.comment = None
    elif failure == "foreign_key":
        metadata.tables["libraries"].append_constraint(
            ForeignKeyConstraint(["owner_user_id"], ["users.id"], name="fk_forbidden")
        )
    elif failure == "missing_relation":
        metadata.tables["libraries"].info["logical_relations"] = []
    else:
        Index(
            "ix_users_duplicate_email", users.c.email_normalized, info={"purpose": "bad duplicate"}
        )
    with pytest.raises(ModelContractError):
        validate_metadata(metadata)


def test_dictionary_changes_when_authoritative_field_changes() -> None:
    metadata = MetaData(naming_convention=Base.metadata.naming_convention)
    for table in Base.metadata.tables.values():
        copied = table.to_metadata(metadata)
        original_indexes = {index.name: index for index in table.indexes}
        for index in copied.indexes:
            index.info = deepcopy(original_indexes[index.name].info)
    metadata.tables["users"].c.email.comment = "修改后的显示邮箱含义"
    assert database_document(metadata)["source_sha256"] != database_document()["source_sha256"]
