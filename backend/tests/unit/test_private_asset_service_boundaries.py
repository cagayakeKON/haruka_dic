"""Owner avatar publication and saved-source integrity rules with isolated repositories.

Repository fixtures prove service decisions; real PG ownership/locks remain integration evidence.
The bounded image processor is replaced here because byte processing has separate tests.
"""

from datetime import UTC, datetime, timedelta
from hashlib import sha256
from typing import cast
from unittest.mock import AsyncMock, patch
from uuid import UUID, uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models.avatar import FileObject, UploadIntent
from app.models.identity_security import UserExtension
from app.schemas.avatar import AvatarUploadIntentCreate
from app.schemas.profile import ProfileCompleteness, ProfileRead
from app.services import avatar
from app.services.avatar_image import PublishedAvatar


def database() -> tuple[AsyncSession, AsyncMock]:
    mock = AsyncMock(spec=AsyncSession)

    async def flush() -> None:
        for call in mock.add.call_args_list:
            entity = call.args[0]
            if entity.id is None:
                entity.id = uuid4()

    mock.flush.side_effect = flush
    return cast(AsyncSession, mock), mock


def scope() -> ScopeContext:
    return ScopeContext(
        uuid4(), uuid4(), "client", "web", 1, 1, 1, datetime.now(UTC) + timedelta(hours=1)
    )


def intent(raw: bytes = b"original-upload") -> UploadIntent:
    return UploadIntent(
        id=uuid4(),
        status="pending",
        declared_format="png",
        expected_size_bytes=len(raw),
        expected_sha256=sha256(raw).digest(),
        expires_at=datetime.now(UTC) + timedelta(minutes=1),
    )


def profile() -> ProfileRead:
    return ProfileRead(
        revision=4,
        use_optional_demographics_for_ai=False,
        avatar_revision=2,
        profile_completeness=ProfileCompleteness(
            display_name=False, explanation_language=False, target_language=False, timezone=False
        ),
    )


@pytest.mark.asyncio
async def test_avatar_intent_binds_current_owner_target_and_exact_update_actions() -> None:
    session, mock = database()
    current = scope()
    extension = UserExtension(user_id=current.user_id)
    payload = AvatarUploadIntentCreate(
        declared_format="png", expected_size_bytes=15, expected_sha256="a" * 64
    )
    with (
        patch.object(avatar, "verify_scope_in_transaction", new_callable=AsyncMock) as verify,
        patch.object(
            avatar.profile_repository, "extension", new_callable=AsyncMock, return_value=extension
        ),
    ):
        value = await avatar.create_intent(session, current, payload)
    row = mock.add.call_args.args[0]
    assert row.user_id == current.user_id and row.target_resource_id == current.user_id
    assert row.expected_sha256 == bytes.fromhex("a" * 64) and row.purpose == "avatar"
    assert value.id == row.id and value.max_size_bytes == avatar.MAX_INPUT_BYTES
    assert verify.await_args is not None and verify.await_args.kwargs["permissions"] == (
        "client.profile.read",
        "client.profile.avatar.update",
    )
    assert verify.await_args.kwargs["lock_user"] is True


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    [
        "missing-intent",
        "digest",
        "size",
        "oversize-declaration",
        "expired",
        "state",
        "missing-profile",
        "stale",
    ],
)
async def test_avatar_complete_rejects_invalid_declaration_before_processing(failure: str) -> None:
    session, mock = database()
    current = scope()
    row = intent()
    raw = b"original-upload"
    extension = UserExtension(profile_revision=4)
    if failure == "digest":
        row.expected_sha256 = b"x" * 32
    if failure == "size":
        row.expected_size_bytes += 1
    if failure == "oversize-declaration":
        row.expected_size_bytes = avatar.MAX_INPUT_BYTES + 1
    if failure == "expired":
        row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    if failure == "state":
        row.status = "rejected"
    with (
        patch.object(avatar, "verify_scope_in_transaction", new_callable=AsyncMock),
        patch.object(
            avatar.avatar_repository,
            "intent",
            new_callable=AsyncMock,
            return_value=None if failure == "missing-intent" else row,
        ),
        patch.object(
            avatar.profile_repository,
            "extension",
            new_callable=AsyncMock,
            return_value=None if failure == "missing-profile" else extension,
        ),
        patch.object(avatar, "publish_avatar_bounded", new_callable=AsyncMock) as processor,
        pytest.raises(AppError) as error,
    ):
        await avatar.complete_intent(session, current, row.id, 3 if failure == "stale" else 4, raw)
    expected = {
        "missing-intent": ErrorCode.RESOURCE_NOT_FOUND,
        "digest": ErrorCode.INPUT_INVALID,
        "size": ErrorCode.INPUT_INVALID,
        "oversize-declaration": ErrorCode.PAYLOAD_TOO_LARGE,
        "expired": ErrorCode.STATE_CONFLICT,
        "state": ErrorCode.STATE_CONFLICT,
        "missing-profile": ErrorCode.SERVICE_UNAVAILABLE,
        "stale": ErrorCode.REVISION_CONFLICT,
    }
    assert error.value.code == expected[failure]
    processor.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("phase", ["before-processing", "after-processing"])
async def test_completed_upload_replay_never_replaces_final_object(phase: str) -> None:
    session, mock = database()
    current = scope()
    first = intent()
    completed = intent()
    completed.status = "completed"
    extension = UserExtension(profile_revision=4)
    rows = [completed] if phase == "before-processing" else [first, completed]
    with (
        patch.object(avatar, "verify_scope_in_transaction", new_callable=AsyncMock),
        patch.object(avatar.avatar_repository, "intent", new_callable=AsyncMock, side_effect=rows),
        patch.object(
            avatar.profile_repository, "extension", new_callable=AsyncMock, return_value=extension
        ),
        patch.object(
            avatar,
            "publish_avatar_bounded",
            new_callable=AsyncMock,
            return_value=PublishedAvatar(b"safe-final", 512, sha256(b"safe-final").digest()),
        ) as processor,
        patch.object(avatar, "read_profile", new_callable=AsyncMock, return_value=profile()),
    ):
        value = await avatar.complete_intent(session, current, first.id, 4, b"original-upload")
    assert value.revision == 4 and extension.profile_revision == 4
    assert processor.await_count == (0 if phase == "before-processing" else 1)
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["authority", "cas"])
async def test_avatar_second_publication_phase_revalidates_authority_and_cas(failure: str) -> None:
    session, mock = database()
    current = scope()
    row = intent()
    first = UserExtension(profile_revision=4)
    second = UserExtension(profile_revision=5 if failure == "cas" else 4)
    verifier = AsyncMock(
        side_effect=[None, AppError(ErrorCode.PERMISSION_DENIED)]
        if failure == "authority"
        else None
    )
    with (
        patch.object(avatar, "verify_scope_in_transaction", new=verifier),
        patch.object(avatar.avatar_repository, "intent", new_callable=AsyncMock, return_value=row),
        patch.object(
            avatar.profile_repository,
            "extension",
            new_callable=AsyncMock,
            side_effect=[first, second],
        ),
        patch.object(
            avatar,
            "publish_avatar_bounded",
            new_callable=AsyncMock,
            return_value=PublishedAvatar(b"safe-final", 512, sha256(b"safe-final").digest()),
        ),
        pytest.raises(AppError) as error,
    ):
        await avatar.complete_intent(session, current, row.id, 4, b"original-upload")
    assert error.value.code == (
        ErrorCode.PERMISSION_DENIED if failure == "authority" else ErrorCode.REVISION_CONFLICT
    )
    assert row.status == "pending"
    mock.add.assert_not_called()


@pytest.mark.asyncio
async def test_avatar_publishes_only_validated_immutable_bytes_and_releases_old_reference() -> None:
    session, mock = database()
    current = scope()
    row = intent()
    old = FileObject(id=uuid4(), retention_state="referenced", content=b"old-final")
    extension = UserExtension(profile_revision=4, avatar_revision=2, avatar_asset_id=old.id)
    final = b"validated-final"
    with (
        patch.object(avatar, "verify_scope_in_transaction", new_callable=AsyncMock),
        patch.object(
            avatar.avatar_repository, "intent", new_callable=AsyncMock, return_value=row
        ) as repo_intent,
        patch.object(
            avatar.profile_repository, "extension", new_callable=AsyncMock, return_value=extension
        ),
        patch.object(
            avatar.avatar_repository, "file_object", new_callable=AsyncMock, return_value=old
        ),
        patch.object(
            avatar,
            "publish_avatar_bounded",
            new_callable=AsyncMock,
            return_value=PublishedAvatar(final, 512, sha256(final).digest()),
        ),
        patch.object(avatar, "read_profile", new_callable=AsyncMock, return_value=profile()),
    ):
        await avatar.complete_intent(session, current, row.id, 4, b"original-upload")
    published = mock.add.call_args.args[0]
    assert (
        published.content == final
        and published.user_id == current.user_id
        and published.media_type == "image/jpeg"
    )
    assert (
        published.content != b"original-upload"
        and row.file_object_id == published.id
        and row.status == "completed"
    )
    assert (
        extension.avatar_asset_id == published.id
        and extension.avatar_revision == 3
        and extension.profile_revision == 5
    )
    assert old.retention_state == "gc_pending" and old.gc_not_before_at is not None
    assert repo_intent.await_args_list[1].kwargs["lock"] is True


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", ["no-reference", "missing", "purpose", "retention", "wrong-id", "missing-profile"]
)
async def test_avatar_read_never_returns_detached_or_mismatched_private_asset(failure: str) -> None:
    session, _ = database()
    current = scope()
    identifier = uuid4()
    extension = UserExtension(avatar_asset_id=None if failure == "no-reference" else identifier)
    asset = FileObject(
        id=uuid4() if failure == "wrong-id" else identifier,
        purpose="source" if failure == "purpose" else "avatar",
        retention_state="gc_pending" if failure == "retention" else "referenced",
        content=b"private-final",
    )
    with (
        patch.object(avatar, "verify_scope_in_transaction", new_callable=AsyncMock),
        patch.object(
            avatar.profile_repository,
            "extension",
            new_callable=AsyncMock,
            return_value=None if failure == "missing-profile" else extension,
        ),
        patch.object(
            avatar.avatar_repository,
            "file_object",
            new_callable=AsyncMock,
            return_value=None if failure == "missing" else asset,
        ),
        pytest.raises(AppError) as error,
    ):
        await avatar.read_avatar(session, current)
    assert error.value.code == (
        ErrorCode.SERVICE_UNAVAILABLE
        if failure == "missing-profile"
        else ErrorCode.RESOURCE_NOT_FOUND
    )


@pytest.mark.asyncio
@pytest.mark.parametrize("present,stale", [(False, False), (True, False), (True, True)])
async def test_avatar_delete_changes_only_existing_reference_under_current_revision(
    present: bool, stale: bool
) -> None:
    session, _ = database()
    current = scope()
    old = FileObject(id=uuid4(), retention_state="referenced")
    extension = UserExtension(
        profile_revision=4, avatar_revision=2, avatar_asset_id=old.id if present else None
    )
    with (
        patch.object(avatar, "verify_scope_in_transaction", new_callable=AsyncMock),
        patch.object(
            avatar.profile_repository, "extension", new_callable=AsyncMock, return_value=extension
        ),
        patch.object(
            avatar.avatar_repository, "file_object", new_callable=AsyncMock, return_value=old
        ) as file_repo,
        patch.object(avatar, "read_profile", new_callable=AsyncMock, return_value=profile()),
    ):
        if stale:
            with pytest.raises(AppError) as error:
                await avatar.delete_avatar(session, current, 3)
            assert error.value.code == ErrorCode.REVISION_CONFLICT
        else:
            await avatar.delete_avatar(session, current, 4)
    assert extension.profile_revision == (5 if present and not stale else 4)
    assert file_repo.await_count == (1 if present and not stale else 0)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", ["invalid-key", "unsupported-notebook", "invalid-digest", "revoked"]
)
async def test_collection_rejects_before_persistence(failure: str) -> None:
    from app.schemas.learning_reference import CollectionCreate
    from app.services import learning_reference

    session, mock = database()
    current = scope()
    payload = CollectionCreate(
        card_id=uuid4(),
        card_revision=1,
        notebook_ids=[uuid4()] if failure == "unsupported-notebook" else [],
    )
    denial = AppError(ErrorCode.PERMISSION_DENIED)
    with (
        patch.object(
            learning_reference,
            "verify_scope_in_transaction",
            new_callable=AsyncMock,
            side_effect=denial if failure == "revoked" else None,
        ) as verify,
        patch.object(learning_reference.repository, "owned", new_callable=AsyncMock) as owned,
        patch.object(
            learning_reference.repository, "persist_collection_result", new_callable=AsyncMock
        ) as persist,
        pytest.raises(AppError) as error,
    ):
        await learning_reference.create_collection(
            session,
            current,
            instance_id="test-haruka",
            payload=payload,
            key=" bad key" if failure == "invalid-key" else "safe-key",
            key_digest=b"x" if failure == "invalid-digest" else b"x" * 32,
            operation_id=uuid4(),
        )
    expected = (
        ErrorCode.CAPABILITY_UNSUPPORTED
        if failure == "unsupported-notebook"
        else ErrorCode.PERMISSION_DENIED
        if failure == "revoked"
        else ErrorCode.INPUT_INVALID
    )
    assert error.value.code == expected
    owned.assert_not_awaited()
    persist.assert_not_awaited()
    mock.add.assert_not_called()
    if failure == "revoked":
        assert verify.await_args is not None
        assert verify.await_args.kwargs["user_id"] == current.user_id
        assert verify.await_args.kwargs["permissions"] == (
            "client.collection.create",
            "client.material.read",
        )
        assert verify.await_args.kwargs["lock_user"] is True


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "invalid_cursor", ["not-a-uuid", "1", "00000000-0000-0000-0000-00000000000z"]
)
async def test_material_cursor_rejects_after_current_read_authorization(
    invalid_cursor: str,
) -> None:
    from app.services import learning_reference

    session, _ = database()
    current = scope()
    with (
        patch.object(
            learning_reference, "require_permissions", new_callable=AsyncMock
        ) as permissions,
        patch.object(
            learning_reference.repository, "material_page", new_callable=AsyncMock
        ) as listing,
        pytest.raises(AppError) as error,
    ):
        await learning_reference.list_materials(session, current, cursor=invalid_cursor, limit=20)
    assert error.value.code == ErrorCode.INPUT_INVALID
    assert permissions.await_args is not None
    assert permissions.await_args.kwargs["user_id"] == current.user_id
    listing.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    [
        "stale-card",
        "unsupported-kind",
        "unsupported-schema",
        "invalid-payload",
        "language-mismatch",
    ],
)
async def test_collection_rejects_invalid_persisted_card_before_parent_or_write(
    failure: str,
) -> None:
    from app.models.learning_reference import Card
    from app.schemas.learning_reference import CollectionCreate
    from app.services import learning_reference

    session, mock = database()
    current = scope()
    card = Card(
        id=uuid4(),
        library_id=uuid4(),
        card_revision=2 if failure == "stale-card" else 1,
        card_kind="sentence" if failure == "unsupported-kind" else "word",
        schema_version=2 if failure == "unsupported-schema" else 1,
        target_language="ja",
        payload={}
        if failure == "invalid-payload"
        else {
            "term": "learn",
            "part_of_speech": "verb",
            "context_meaning": "study",
            "other_meanings": [],
            "examples": [{"text": "one", "meaning": "first"}, {"text": "two", "meaning": "second"}],
        },
    )
    with (
        patch.object(learning_reference, "verify_scope_in_transaction", new_callable=AsyncMock),
        patch.object(
            learning_reference.repository, "owned", new_callable=AsyncMock, return_value=card
        ) as owned,
        patch.object(
            learning_reference.repository, "persist_collection_result", new_callable=AsyncMock
        ) as persist,
        pytest.raises(AppError) as error,
    ):
        await learning_reference.create_collection(
            session,
            current,
            instance_id="test-haruka",
            payload=CollectionCreate(
                card_id=card.id,
                card_revision=1,
                confirmed_target_language="en" if failure == "language-mismatch" else None,
            ),
            key="valid-key",
            key_digest=b"x" * 32,
            operation_id=uuid4(),
        )
    assert error.value.code == (
        ErrorCode.RESOURCE_NOT_FOUND
        if failure == "stale-card"
        else ErrorCode.INPUT_INVALID
        if failure == "language-mismatch"
        else ErrorCode.SERVICE_UNAVAILABLE
    )
    assert owned.await_count == 1
    persist.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    [
        "foreign-instance",
        "tombstone",
        "late-revision",
        "deleted-generation",
        "foreign-chapter",
        "foreign-mapping",
        "corrupt-length",
        "foreign-source-unit",
        "split-grapheme",
        "altered-quote",
        "altered-context",
        "altered-title",
    ],
)
async def test_explanation_source_rejects_late_or_corrupt_references_before_result_lookup(
    failure: str,
) -> None:
    from app.models.identity import Library
    from app.models.learning_reference import (
        Material,
        MaterialContentBlock,
        MaterialRevision,
        MaterialSourceUnit,
        NovelChapter,
        NovelChapterBlock,
    )
    from app.schemas.learning_reference import (
        ExplanationResolveRequest,
        NovelContentLocator,
        ResolveTarget,
        SourceSpan,
    )
    from app.services import learning_reference

    session, mock = database()
    current = scope()
    library = Library(id=uuid4())
    material = Material(
        id=uuid4(),
        library_id=library.id,
        current_revision_id=uuid4(),
        material_type="novel",
        source_status="published",
        deleted_at=None,
        delete_generation=2,
        language="ja",
        title="book",
    )
    revision = MaterialRevision(
        id=material.current_revision_id,
        library_id=library.id,
        material_id=material.id,
        status="published",
        structure_status="readable",
        text_protocol_version="canonical-text-v1",
        input_delete_generation=2,
    )
    chapter = NovelChapter(
        id=uuid4(),
        library_id=library.id,
        material_id=material.id,
        material_revision_id=revision.id,
        title="chapter",
    )
    unit = MaterialSourceUnit(
        id=uuid4(), library_id=library.id, material_id=material.id, material_revision_id=revision.id
    )
    block = MaterialContentBlock(
        id=uuid4(),
        library_id=library.id,
        material_id=material.id,
        material_revision_id=revision.id,
        source_unit_id=unit.id,
        canonical_text="a\u0301b",
        scalar_length=3,
    )
    mapping = NovelChapterBlock(
        id=uuid4(),
        library_id=library.id,
        material_id=material.id,
        material_revision_id=revision.id,
        chapter_id=chapter.id,
        content_block_id=block.id,
        start_scalar=0,
        end_scalar=3,
    )
    locator = NovelContentLocator(
        instance_id="test-haruka",
        library_id=library.id,
        material_id=material.id,
        material_revision_id=revision.id,
        novel_chapter_id=chapter.id,
        chapter_block_id=mapping.id,
        quote="a\u0301",
        prefix="",
        suffix="b",
        source_title="book",
        node_title="chapter",
        spans=[SourceSpan(block_id=block.id, start=0, end=2)],
    )
    if failure == "foreign-instance":
        locator.instance_id = "other-instance"
    elif failure == "tombstone":
        material.deleted_at = datetime.now(UTC)
    elif failure == "late-revision":
        material.current_revision_id = uuid4()
    elif failure == "deleted-generation":
        revision.input_delete_generation = 1
    elif failure == "foreign-chapter":
        chapter.material_id = uuid4()
    elif failure == "foreign-mapping":
        mapping.chapter_id = uuid4()
    elif failure == "corrupt-length":
        block.scalar_length = 4
    elif failure == "foreign-source-unit":
        unit.material_id = uuid4()
    elif failure == "split-grapheme":
        locator.spans[0].end = 1
        locator.quote = "a"
        locator.suffix = "\u0301b"
    elif failure == "altered-quote":
        locator.quote = "other"
    elif failure == "altered-context":
        locator.suffix = "x"
    elif failure == "altered-title":
        locator.node_title = "other chapter"
    rows = {row.id: row for row in (library, material, revision, chapter, unit, block, mapping)}

    def read_owned(
        _session: AsyncSession, _scope: ScopeContext, _model: object, entity_id: UUID, *, lock: bool
    ) -> object:
        assert lock is False
        return rows[entity_id]

    with (
        patch.object(
            learning_reference, "require_permissions", new_callable=AsyncMock
        ) as permissions,
        patch.object(
            learning_reference.repository,
            "owned",
            new_callable=AsyncMock,
            side_effect=read_owned,
        ) as owned,
        patch.object(
            learning_reference.repository, "latest_resolved_binding", new_callable=AsyncMock
        ) as result_lookup,
        pytest.raises(AppError) as error,
    ):
        await learning_reference.resolve_explanations(
            session,
            current,
            instance_id="test-haruka",
            payload=ExplanationResolveRequest(
                targets=[
                    ResolveTarget(
                        source_locator=locator, target_language="ja", explanation_language="zh"
                    )
                ]
            ),
        )
    assert error.value.code == ErrorCode.RESOURCE_NOT_FOUND
    assert permissions.await_args is not None and permissions.await_args.kwargs["codes"] == (
        "client.ai.explain",
        "client.material.read",
    )
    result_lookup.assert_not_awaited()
    mock.add.assert_not_called()
    for call in owned.await_args_list:
        assert call.args[1] is current and call.kwargs["lock"] is False
