"""Source protocol admission and model-worker separation, without supplier calls."""

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.domain.errors import AppError
from app.models.model_tasks import Job
from app.schemas.material_imports import (
    MaterialImportCreate,
    MaterialImportRead,
    MaterialTitlePatch,
)
from app.schemas.model_settings import JobRead, JobRetry
from app.services.model_tasks import model_references

pytestmark = pytest.mark.unit


def test_mixed_jobs_require_distinct_source_or_model_references() -> None:
    now = datetime.now(UTC)
    common = {
        "id": uuid4(),
        "state": "queued",
        "revision": 1,
        "generation": 1,
        "sequence": 0,
        "can_cancel": True,
        "can_retry": False,
        "requires_new_attempt_confirmation": False,
        "created_at": now,
        "updated_at": now,
    }
    model = JobRead.model_validate({**common, "run_id": uuid4(), "credential_id": uuid4()})
    source = {
        **common,
        "operation_kind": "material_import",
        "material_id": uuid4(),
        "material_revision_id": uuid4(),
        "source_status": "parsing",
    }
    assert model.operation_kind == "credential_test"
    assert JobRead.model_validate(source).run_id is None
    for invalid in (
        {**source, "credential_id": uuid4()},
        {**source, "material_revision_id": None},
        {**source, "requires_new_attempt_confirmation": True},
        {**common, "run_id": None, "credential_id": None},
    ):
        with pytest.raises(ValidationError):
            JobRead.model_validate(invalid)
    confirmation = {
        "language": "en",
        "input_digest": "a" * 64,
        "expected_job_generation": 1,
        "expected_issue_revision": 1,
    }
    assert JobRetry.model_validate(
        {"expected_revision": 1, "language_confirmation": confirmation}
    ).language_confirmation
    for extra in (
        {"credential_id": uuid4()},
        {"confirm_new_attempt": True},
        {"provider": "openrouter"},
    ):
        with pytest.raises(ValidationError):
            JobRetry.model_validate(
                {"expected_revision": 1, "language_confirmation": confirmation, **extra}
            )


def file_request() -> dict[str, object]:
    return {
        "schema_version": 1,
        "material_type": "novel",
        "language": "ja",
        "file": {"filename": "source.md", "format": "md", "size_bytes": 20, "sha256": "a" * 64},
        "requested_stages": {"extract": True, "analyze": False},
    }


@pytest.mark.parametrize(
    "material_type,format_code",
    [
        ("novel", "md"),
        ("novel", "epub"),
        ("novel", "pdf"),
        ("textbook", "md"),
        ("textbook", "epub"),
        ("textbook", "pdf"),
        ("exam", "md"),
        ("exam", "epub"),
        ("exam", "pdf"),
        ("exam", "png"),
        ("exam", "jpeg"),
        ("exam", "webp"),
    ],
)
def test_supported_source_contract_and_owned_reuse(material_type: str, format_code: str) -> None:
    payload = file_request()
    payload.update(
        material_type=material_type,
        file={"filename": "source", "format": format_code, "size_bytes": 20, "sha256": "a" * 64},
    )
    result = MaterialImportCreate.model_validate(payload)
    assert result.file is not None and result.file.format == format_code
    assert result.requested_stages.extract and not result.requested_stages.analyze
    payload.pop("file")
    payload["source_material_id"] = str(uuid4())
    result = MaterialImportCreate.model_validate(payload)
    assert result.file is None and result.source_material_id is not None


@pytest.mark.parametrize(
    "patch",
    [
        {"user_id": str(uuid4())},
        {"material_type": "other"},
        {"language": "zh"},
        {"file": None},
        {"source_material_id": str(uuid4())},
        {"file_object_id": str(uuid4())},
        {"requested_stages": {"extract": True, "analyze": True}},
        {"requested_stages": {"extract": False, "analyze": False}},
        {"file": {"filename": "../source.md", "format": "md", "size_bytes": 1, "sha256": "a" * 64}},
        {"file": {"filename": "source.png", "format": "png", "size_bytes": 1, "sha256": "a" * 64}},
        {"file": {"filename": "source.md", "format": "md", "size_bytes": 0, "sha256": "a" * 64}},
        {
            "file": {
                "filename": "source.md",
                "format": "md",
                "size_bytes": 1,
                "sha256": "not-a-digest",
            }
        },
        {"requested_stages": {"extract": 1, "analyze": False}},
        {"schema_version": 2},
        {"title": "   "},
    ],
)
def test_untrusted_source_shapes_are_rejected(patch: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        MaterialImportCreate.model_validate(file_request() | patch)


def test_import_acceptance_does_not_claim_body_ready_and_title_cas() -> None:
    accepted = MaterialImportRead(
        id=uuid4(),
        revision=2,
        material_type="exam",
        language="en",
        status="accepted",
        material_id=uuid4(),
        job_id=uuid4(),
        expires_at=datetime.now(UTC),
    )
    assert "readable" not in accepted.model_dump() and "exam_ready" not in accepted.model_dump()
    with pytest.raises(ValidationError):
        MaterialImportRead.model_validate(accepted.model_dump() | {"status": "source_accepted"})
    with pytest.raises(ValidationError):
        MaterialTitlePatch(expected_revision=0, title="Title")


def test_deterministic_job_cannot_enter_model_executor() -> None:
    job = Job(operation_kind="material_import", credential_id=None, run_id=None)
    with pytest.raises(AppError):
        model_references(job)
    job.operation_kind = "credential_test"
    with pytest.raises(AppError):
        model_references(job)
    job.credential_id, job.run_id = uuid4(), uuid4()
    assert model_references(job) == (job.credential_id, job.run_id)


@pytest.mark.parametrize(
    "status,material_present,job_present",
    [("accepted", False, False), ("accepted", True, False), ("verifying", True, True)],
)
def test_import_result_requires_committed_reference_pair(
    status: str, material_present: bool, job_present: bool
) -> None:
    with pytest.raises(ValidationError):
        MaterialImportRead.model_validate(
            {
                "id": str(uuid4()),
                "revision": 1,
                "material_type": "novel",
                "language": "ja",
                "status": status,
                "material_id": str(uuid4()) if material_present else None,
                "job_id": str(uuid4()) if job_present else None,
                "expires_at": datetime.now(UTC),
            }
        )
