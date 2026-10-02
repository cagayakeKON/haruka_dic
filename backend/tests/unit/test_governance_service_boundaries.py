"""Governance rejects unsafe writes and preserves authoritative policy boundaries.

Database results are isolated fixtures: these tests prove service rules, not PG locking.
"""

from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from typing import Literal, cast
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest
from pydantic import BaseModel, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.bootstrap import Resources, Runtime
from app.contracts.errors import ErrorCode
from app.core.settings import Settings
from app.domain.errors import AppError
from app.domain.scope import ScopeContext
from app.models import (
    AuthChallenge,
    AuthorizationRevision,
    AuthPolicy,
    PermissionCatalog,
    Role,
    User,
    UserExtension,
)
from app.schemas.auth import AdminAuthPolicyUpdate
from app.schemas.role_governance import (
    GrantBoundariesUpdate,
    GrantBoundaryWrite,
    RoleCreate,
    RoleMetadataUpdate,
)
from app.schemas.user_governance import AccountCreate, AccountRolesUpdate, ManualRecoveryDecision
from app.services import auth_policy as policy
from app.services import role_governance as roles
from app.services import user_governance as users
from app.services.auth_crypto import AuthCrypto
from app.services.authorization import GrantGraph


def db() -> tuple[AsyncSession, AsyncMock]:
    mock = AsyncMock(spec=AsyncSession)
    mock.__aenter__.return_value = mock

    async def flush() -> None:
        for call in mock.add.call_args_list:
            row = call.args[0]
            if hasattr(row, "id") and row.id is None:
                row.id = uuid4()

    mock.flush.side_effect = flush
    return cast(AsyncSession, mock), mock


def result(values: Sequence[object]) -> MagicMock:
    value = MagicMock()
    value.all.return_value = values
    return value


def scope() -> ScopeContext:
    return ScopeContext(uuid4(), uuid4(), "admin", "web", 1, 1, 1, datetime.now(UTC))


def runtime(mock: AsyncMock) -> Runtime:
    resources = MagicMock(spec=Resources)
    resources.database = MagicMock()
    resources.database.sessions.return_value = mock
    return Runtime(
        Settings(
            app_env="test",
            instance_id="haruka-test-governance",
            public_base_url="http://127.0.0.1:8080",
        ),
        resources=cast(Resources, resources),
        schema_compatible=True,
    )


def stored_policy(**changes: object) -> AuthPolicy:
    values: dict[str, object] = {
        "code": "registration",
        "registration_mode": "closed",
        "recovery_mode": "disabled",
        "require_email_verification": True,
        "revision": 4,
        "default_role_id": uuid4(),
    }
    return AuthPolicy(**(values | changes))


def role() -> Role:
    return Role(
        id=uuid4(),
        code="operator",
        name="Operator",
        description=None,
        enabled=True,
        protected=False,
        revision=4,
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "mode,recovery,expected",
    [("closed", "manual", True), ("open", "email", False), ("approval", "disabled", False)],
)
async def test_public_policy_exposes_only_available_recovery_and_registration(
    mode: str,
    recovery: str,
    expected: bool,
) -> None:
    _, mock = db()
    with patch.object(
        policy,
        "registration_policy",
        new_callable=AsyncMock,
        return_value=stored_policy(registration_mode=mode, recovery_mode=recovery),
    ):
        value = await policy.read_public_policy(runtime(mock))
    assert value.registration_enabled is False and value.recovery_enabled == expected
    assert value.approval_required == (mode == "approval")
    assert "smtp" not in value.model_dump_json() and "secret" not in value.model_dump_json()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "stored",
    [
        None,
        stored_policy(registration_mode="unknown"),
        stored_policy(recovery_mode="unknown"),
        stored_policy(require_email_verification=False),
    ],
)
async def test_public_policy_fails_closed_on_invalid_persistent_policy(
    stored: AuthPolicy | None,
) -> None:
    _, mock = db()
    with (
        patch.object(policy, "registration_policy", new_callable=AsyncMock, return_value=stored),
        pytest.raises(AppError) as error,
    ):
        await policy.read_public_policy(runtime(mock))
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE


@pytest.mark.asyncio
@pytest.mark.parametrize("admin", [False, True])
async def test_policy_database_failure_is_safe_service_error(admin: bool) -> None:
    _, mock = db()
    with (
        patch.object(
            policy,
            "registration_policy",
            new_callable=AsyncMock,
            side_effect=RuntimeError("synthetic database failure"),
        ),
        patch.object(policy, "verify_scope_in_transaction", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        if admin:
            await policy.read_admin_policy(runtime(mock), scope())
        else:
            await policy.read_public_policy(runtime(mock))
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    assert str(error.value) == "SERVICE_UNAVAILABLE"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "mode,recovery", [("open", "disabled"), ("approval", "manual"), ("closed", "email")]
)
async def test_policy_cannot_offer_mail_flow_without_delivery(mode: str, recovery: str) -> None:
    session, mock = db()
    payload = AdminAuthPolicyUpdate.model_validate(
        {"registration_mode": mode, "recovery_mode": recovery, "expected_revision": 4}
    )
    with pytest.raises(AppError) as error:
        await policy.write_admin_policy(session, scope(), payload, mail_available=False)
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    mock.scalar.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "condition,code",
    [
        ("missing-root", ErrorCode.SESSION_INVALID),
        ("missing-policy", ErrorCode.SERVICE_UNAVAILABLE),
        ("stale", ErrorCode.REVISION_CONFLICT),
    ],
)
async def test_policy_write_missing_authority_or_cas_does_not_write(
    condition: str, code: ErrorCode
) -> None:
    session, mock = db()
    with (
        patch.object(
            policy,
            "global_revision_for_update",
            new_callable=AsyncMock,
            return_value=None if condition == "missing-root" else AuthorizationRevision(revision=7),
        ),
        patch.object(policy, "require_permissions", new_callable=AsyncMock),
        patch.object(
            policy,
            "registration_policy",
            new_callable=AsyncMock,
            return_value=None if condition == "missing-policy" else stored_policy(),
        ),
        pytest.raises(AppError) as error,
    ):
        await policy.write_admin_policy(
            session,
            scope(),
            AdminAuthPolicyUpdate(
                registration_mode="closed", expected_revision=3 if condition == "stale" else 4
            ),
            mail_available=False,
        )
    assert error.value.code == code
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("changed", [False, True])
async def test_policy_recovery_change_writes_one_audit_and_outbox_without_touching_accounts(
    changed: bool,
) -> None:
    session, mock = db()
    stored, revision = stored_policy(), AuthorizationRevision(revision=7)
    with (
        patch.object(
            policy, "global_revision_for_update", new_callable=AsyncMock, return_value=revision
        ),
        patch.object(policy, "require_permissions", new_callable=AsyncMock),
        patch.object(policy, "registration_policy", new_callable=AsyncMock, return_value=stored),
    ):
        value = await policy.write_admin_policy(
            session,
            scope(),
            AdminAuthPolicyUpdate(
                registration_mode="closed",
                recovery_mode="manual" if changed else None,
                expected_revision=4,
            ),
            mail_available=False,
        )
    assert value.revision == (5 if changed else 4) and revision.revision == (8 if changed else 7)
    assert mock.add.call_count == (2 if changed else 0)
    assert all(not isinstance(call.args[0], User) for call in mock.add.call_args_list)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "problem",
    [
        "missing",
        "disabled",
        "protected",
        "no-login",
        "denied-login",
        "admin-grant",
        "disabled-catalog",
        "wrong-scope",
    ],
)
async def test_public_registration_role_never_accepts_admin_or_denied_login(problem: str) -> None:
    session, mock = db()
    stored = role()
    stored.enabled = problem != "disabled"
    stored.protected = problem == "protected"
    mock.scalar.return_value = None if problem == "missing" else stored
    grants: list[object] = [] if problem == "no-login" else [("client.login", "allow", "self")]
    if problem in {"denied-login", "admin-grant", "wrong-scope"}:
        grants.append(
            (
                "client.login" if problem == "denied-login" else "admin.login",
                "deny" if problem == "denied-login" else "allow",
                "self" if problem == "denied-login" else "platform_metadata",
            )
        )
    mock.execute.return_value = result(grants)
    mock.scalars.return_value = result(
        [
            PermissionCatalog(
                code="client.login",
                audience="client",
                data_scope="self",
                enabled=problem != "disabled-catalog",
            ),
            PermissionCatalog(
                code="admin.login", audience="admin", data_scope="platform_metadata", enabled=True
            ),
        ]
    )
    with pytest.raises(AppError) as error:
        await policy.validate_public_registration_role(session, stored.id)
    assert error.value.code == ErrorCode.SERVICE_UNAVAILABLE
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "self_target,stale,approval",
    [
        (True, False, "pending"),
        (False, True, "pending"),
        (False, False, "pending"),
        (False, False, "rejected"),
    ],
)
async def test_account_activation_rejects_self_stale_and_unapproved_accounts(
    self_target: bool, stale: bool, approval: str
) -> None:
    session, mock = db()
    actor = uuid4()
    user = User(
        id=actor if self_target else uuid4(), revision=4, status="pending", approval_status=approval
    )
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), user]
    mock.scalars.return_value = result([])
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "_assert_manageable", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await users.set_account_status(
            session,
            actor_id=actor,
            user_id=user.id,
            expected_revision=3 if stale else 4,
            status="active",
        )
    assert error.value.code == (
        ErrorCode.PERMISSION_DENIED
        if self_target
        else ErrorCode.REVISION_CONFLICT
        if stale
        else ErrorCode.STATE_CONFLICT
    )
    assert user.status == "pending" and user.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "decision,approval,verified,status",
    [
        ("approve", "approved", False, "pending"),
        ("reject", "rejected", True, "pending"),
        ("approve", "not_required", True, "active"),
    ],
)
async def test_approval_repeat_is_noop_and_not_required_cannot_be_approved(
    decision: str, approval: str, verified: bool, status: str
) -> None:
    session, mock = db()
    user = User(
        id=uuid4(),
        revision=4,
        status=status,
        approval_status=approval,
        email_verified_at=datetime.now(UTC) if verified else None,
    )
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), user]
    mock.scalars.return_value = result([])
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "_assert_manageable", new_callable=AsyncMock),
    ):
        if approval == "not_required":
            with pytest.raises(AppError) as error:
                await users.decide_account_approval(
                    session,
                    actor_id=uuid4(),
                    user_id=user.id,
                    expected_revision=4,
                    decision="approve",
                )
            assert error.value.code == ErrorCode.STATE_CONFLICT
        else:
            value = await users.decide_account_approval(
                session,
                actor_id=uuid4(),
                user_id=user.id,
                expected_revision=4,
                decision=cast(Literal["approve", "reject"], decision),
            )
            assert value.audit_id is None and value.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "missing_root,missing_role,stale,protected",
    [
        (True, False, False, False),
        (False, True, False, False),
        (False, False, True, False),
        (False, False, False, True),
    ],
)
async def test_role_metadata_writes_require_authority_revision_and_protected_permission(
    missing_root: bool, missing_role: bool, stale: bool, protected: bool
) -> None:
    session, mock = db()
    stored = role()
    stored.protected = protected
    mock.scalar.side_effect = [
        None if missing_root else AuthorizationRevision(revision=7),
        None if missing_role else stored,
    ]
    permission = AsyncMock(
        side_effect=[None, AppError(ErrorCode.PERMISSION_DENIED)] if protected else None
    )
    with (
        patch.object(roles, "require_permissions", new=permission),
        pytest.raises(AppError) as error,
    ):
        await roles.update_role_metadata(
            session,
            actor_id=uuid4(),
            role_id=stored.id,
            expected_revision=3 if stale else 4,
            name="Updated",
            description=None,
        )
    assert error.value.code == (
        ErrorCode.SERVICE_UNAVAILABLE
        if missing_root
        else ErrorCode.RESOURCE_NOT_FOUND
        if missing_role
        else ErrorCode.REVISION_CONFLICT
        if stale
        else ErrorCode.PERMISSION_DENIED
    )
    assert stored.name == "Operator" and stored.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
async def test_role_self_inheritance_is_rejected_before_role_writes() -> None:
    session, mock = db()
    mock.scalar.return_value = AuthorizationRevision(revision=7)
    identifier = uuid4()
    with (
        patch.object(roles, "require_permissions", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await roles.replace_role_parents(
            session,
            actor_id=uuid4(),
            role_id=identifier,
            expected_revision=4,
            parent_role_ids=(identifier,),
        )
    assert error.value.code == ErrorCode.STATE_CONFLICT
    mock.execute.assert_not_awaited()


@pytest.mark.parametrize(
    "schema,payload",
    [
        (RoleCreate, {"code": "Invalid", "name": "Valid"}),
        (RoleCreate, {"code": "valid", "name": " "}),
        (RoleMetadataUpdate, {"expected_revision": 1, "name": "valid", "description": "x" * 2001}),
        (AccountCreate, {"email": "test@example.com", "role_ids": [str(UUID(int=1))] * 2}),
        (AccountRolesUpdate, {"expected_revision": 1, "role_ids": [str(UUID(int=1))] * 2}),
        (
            ManualRecoveryDecision,
            {
                "challenge_id": str(UUID(int=1)),
                "expected_revision": 1,
                "decision": "reject",
                "verification_method": "in_person",
            },
        ),
        (
            ManualRecoveryDecision,
            {"challenge_id": str(UUID(int=1)), "expected_revision": 1, "decision": "issue"},
        ),
        (GrantBoundaryWrite, {"boundary_kind": "assign_role", "permission_code": "admin.login"}),
        (
            GrantBoundaryWrite,
            {"boundary_kind": "assign_permission", "target_role_id": str(UUID(int=1))},
        ),
        (
            GrantBoundariesUpdate,
            {
                "expected_revision": 1,
                "boundaries": [{"boundary_kind": "manage_unassigned_accounts"}] * 2,
            },
        ),
    ],
)
def test_governance_dto_rejects_ambiguous_or_overpowered_writes(
    schema: type[BaseModel], payload: dict[str, object]
) -> None:
    with pytest.raises(ValidationError):
        schema.model_validate(payload)


@pytest.mark.asyncio
async def test_account_listing_keeps_metadata_projection_and_normalized_query_cursor() -> None:
    session, mock = db()
    actor, parent = uuid4(), uuid4()
    page = User(
        id=uuid4(),
        email="First@example.com",
        email_normalized="first@example.com",
        status="disabled",
        approval_status="rejected",
        revision=4,
        email_verified_at=None,
        locked_until=datetime.now(UTC) + timedelta(minutes=1),
    )
    next_row = User(email_normalized="next@example.com")
    mock.scalars.return_value = result([page, next_row])
    mock.scalar.side_effect = [UserExtension(display_name="Visible"), 2]
    mock.execute.return_value = result([(parent, "operator", "Operator", True, False)])
    graph = GrantGraph(
        direct_role_ids=(str(parent),),
        edges=(),
        grants=(
            (str(parent), "client.login", "allow", "self"),
            (str(parent), "admin.login", "allow", "platform_metadata"),
        ),
    )
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "load_graph", new_callable=AsyncMock, return_value=graph),
    ):
        items, cursor = await users.list_accounts(
            session, actor_id=actor, limit=1, after_email="a@example.com", query="  VISIBLE  "
        )
    assert cursor == "first@example.com" and len(items) == 1
    value = items[0]
    assert value.audiences == ["client", "admin"] and value.locked and value.status == "disabled"
    assert value.approval_status == "rejected" and value.live_session_count == 2
    assert "password" not in value.model_dump_json()
    parameters = mock.scalars.call_args.args[0].compile().params
    assert "visible" in parameters.values() and "a@example.com" in parameters.values()


@pytest.mark.asyncio
async def test_role_listing_pages_grants_and_disabled_parents_without_private_accounts() -> None:
    session, mock = db()
    stored = role()
    mock.scalars.return_value = result([stored, role()])
    parent = uuid4()
    mock.execute.side_effect = [
        result([("client.login", "deny", "self")]),
        result([(parent, "parent", False)]),
    ]
    mock.scalar.return_value = 3
    with patch.object(roles, "require_permissions", new_callable=AsyncMock):
        items, more = await roles.list_roles(session, actor_id=uuid4(), limit=1, after_code="a")
    assert more and len(items) == 1
    assert items[0].grants[0].effect == "deny" and items[0].member_count == 3
    assert items[0].parents[0].enabled is False
    assert "email" not in items[0].model_dump_json()


@pytest.mark.asyncio
@pytest.mark.parametrize("deleted", [True, False])
async def test_deleted_role_receipt_allows_only_explicit_delete_receipt(deleted: bool) -> None:
    session, mock = db()
    mock.get.return_value = None
    if deleted:
        await roles.authorize_role_receipt(session, actor_id=uuid4(), role_id=uuid4(), deleted=True)
    else:
        with pytest.raises(AppError) as error:
            await roles.authorize_role_receipt(
                session, actor_id=uuid4(), role_id=uuid4(), deleted=False
            )
        assert error.value.code == ErrorCode.RESOURCE_NOT_FOUND


@pytest.mark.asyncio
async def test_manual_recovery_list_statuses_come_from_challenge_and_issuance_history() -> None:
    session, mock = db()
    now, user_id = datetime.now(UTC), uuid4()
    mock.get.return_value = User(id=user_id)
    challenges = [
        AuthChallenge(
            id=uuid4(),
            created_at=now,
            expires_at=now + timedelta(minutes=1),
            revoked_at=None,
            consumed_at=None,
        )
        for _ in range(5)
    ]
    challenges[0].revoked_at = now
    challenges[1].consumed_at = now
    challenges[2].expires_at = now - timedelta(seconds=1)
    mock.scalars.side_effect = [result([]), result(challenges), result([challenges[3].id, None])]
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "_assert_manageable", new_callable=AsyncMock),
    ):
        values = await users.list_manual_recoveries(session, actor_id=uuid4(), user_id=user_id)
    assert [value.status for value in values] == [
        "rejected",
        "consumed",
        "expired",
        "issued",
        "requested",
    ]
    assert all("token" not in value.model_dump_json() for value in values)


@pytest.mark.asyncio
@pytest.mark.parametrize("problem", ["grant", "parent", "own-boundary"])
async def test_role_enable_cannot_expand_permission_parent_or_own_ceiling(problem: str) -> None:
    session, mock = db()
    stored = role()
    stored.enabled = False
    parent = uuid4()
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), stored]
    mock.scalars.return_value = result([stored.id])
    mock.execute.return_value = result([])
    empty = GrantGraph(direct_role_ids=(), edges=(), grants=())
    with (
        patch.object(roles, "require_permissions", new_callable=AsyncMock),
        patch.object(
            roles,
            "_grant_key",
            new_callable=AsyncMock,
            return_value={("admin.login", "allow", "platform_metadata")}
            if problem == "grant"
            else set(),
        ),
        patch.object(roles, "_permission_ceiling", new_callable=AsyncMock, return_value=set()),
        patch.object(roles, "_role_ceiling", new_callable=AsyncMock, return_value=set()),
        patch.object(
            roles,
            "_parent_ids",
            new_callable=AsyncMock,
            return_value=[parent] if problem == "parent" else [],
        ),
        patch.object(roles, "load_graph", new_callable=AsyncMock, return_value=empty),
        patch.object(roles, "_enabled_boundary_keys", new_callable=AsyncMock, return_value=set()),
        patch.object(
            roles,
            "_boundary_key",
            new_callable=AsyncMock,
            return_value={("manage_unassigned_accounts", None, None, None)},
        ),
        pytest.raises(AppError) as error,
    ):
        await roles.set_role_enabled(
            session, actor_id=uuid4(), role_id=stored.id, expected_revision=4, enabled=True
        )
    assert error.value.code == ErrorCode.PERMISSION_DENIED
    assert stored.enabled is False and stored.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
async def test_disabled_ancestor_boundary_is_still_actor_owned_and_cannot_self_raise() -> None:
    session, mock = db()
    stored, direct = role(), uuid4()
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), stored]
    mock.scalars.return_value = result([direct])
    mock.execute.return_value = result([(direct, stored.id)])
    empty = GrantGraph(direct_role_ids=(), edges=(), grants=())
    with (
        patch.object(roles, "require_permissions", new_callable=AsyncMock),
        patch.object(roles, "_boundary_key", new_callable=AsyncMock, return_value=set()),
        patch.object(roles, "load_graph", new_callable=AsyncMock, return_value=empty),
        pytest.raises(AppError) as error,
    ):
        await roles.replace_grant_boundaries(
            session,
            actor_id=uuid4(),
            role_id=stored.id,
            expected_revision=4,
            boundaries=(GrantBoundaryWrite(boundary_kind="manage_unassigned_accounts"),),
        )
    assert error.value.code == ErrorCode.PERMISSION_DENIED
    assert stored.revision == 4
    mock.add_all.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "problem",
    ["wrong-owner", "wrong-purpose", "consumed", "revoked", "expired", "issued", "no-verification"],
)
async def test_manual_recovery_issue_refuses_replay_expiry_and_mismatched_target(
    problem: str,
) -> None:
    session, mock = db()
    now = datetime.now(UTC)
    user = User(id=uuid4(), revision=4, status="active")
    challenge = AuthChallenge(
        id=uuid4(),
        user_id=uuid4() if problem == "wrong-owner" else user.id,
        purpose="email_verification" if problem == "wrong-purpose" else "manual_recovery",
        consumed_at=now if problem == "consumed" else None,
        revoked_at=now if problem == "revoked" else None,
        expires_at=now - timedelta(seconds=1)
        if problem == "expired"
        else now + timedelta(minutes=1),
    )
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), user]
    mock.scalars.side_effect = [result([]), result([challenge.id] if problem == "issued" else [])]
    crypto = AuthCrypto(b"s" * 32, b"d" * 32, "synthetic", "v1", "v1", None, "v1")
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "_assert_manageable", new_callable=AsyncMock),
        patch.object(
            users, "challenge_by_id_for_update", new_callable=AsyncMock, return_value=challenge
        ),
        pytest.raises(AppError) as error,
    ):
        await users.decide_manual_recovery(
            session,
            actor_id=uuid4(),
            user_id=user.id,
            challenge_id=challenge.id,
            expected_revision=4,
            decision="issue",
            verification_method=None if problem == "no-verification" else "in_person",
            crypto=crypto,
        )
    assert error.value.code == (
        ErrorCode.RESOURCE_NOT_FOUND
        if problem in {"wrong-owner", "wrong-purpose"}
        else ErrorCode.RESOURCE_EXPIRED
        if problem == "expired"
        else ErrorCode.STATE_CONFLICT
    )
    assert user.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("state", ["revoked", "consumed"])
async def test_manual_recovery_rejection_is_idempotent_but_cannot_reject_consumed(
    state: str,
) -> None:
    session, mock = db()
    now = datetime.now(UTC)
    user = User(id=uuid4(), revision=4)
    challenge = AuthChallenge(
        id=uuid4(),
        user_id=user.id,
        purpose="manual_recovery",
        revoked_at=now if state == "revoked" else None,
        consumed_at=now if state == "consumed" else None,
        expires_at=now + timedelta(minutes=1),
    )
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), user]
    mock.scalars.side_effect = [result([]), result([])]
    crypto = AuthCrypto(b"s" * 32, b"d" * 32, "synthetic", "v1", "v1", None, "v1")
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "_assert_manageable", new_callable=AsyncMock),
        patch.object(
            users, "challenge_by_id_for_update", new_callable=AsyncMock, return_value=challenge
        ),
    ):
        if state == "consumed":
            with pytest.raises(AppError) as error:
                await users.decide_manual_recovery(
                    session,
                    actor_id=uuid4(),
                    user_id=user.id,
                    challenge_id=challenge.id,
                    expected_revision=4,
                    decision="reject",
                    verification_method=None,
                    crypto=crypto,
                )
            assert error.value.code == ErrorCode.STATE_CONFLICT
        else:
            value = await users.decide_manual_recovery(
                session,
                actor_id=uuid4(),
                user_id=user.id,
                challenge_id=challenge.id,
                expected_revision=4,
                decision="reject",
                verification_method=None,
                crypto=crypto,
            )
            assert value.status == "rejected" and value.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("unassigned", [False, True])
async def test_account_receipt_requires_management_of_all_ancestor_roles(unassigned: bool) -> None:
    session, mock = db()
    actor, target, direct, ancestor = uuid4(), uuid4(), uuid4(), uuid4()
    mock.get.return_value = User(id=target)
    mock.scalars.side_effect = [result([] if unassigned else [direct]), result([direct])]
    mock.scalar.return_value = None
    mock.execute.return_value = result([(direct, ancestor)])
    graph = GrantGraph(direct_role_ids=(str(uuid4()),), edges=(), grants=())
    with (
        patch.object(users, "load_graph", new_callable=AsyncMock, return_value=graph),
        pytest.raises(AppError) as error,
    ):
        await users.authorize_account_receipt(session, actor_id=actor, user_id=target)
    assert error.value.code == ErrorCode.PERMISSION_DENIED


@pytest.mark.asyncio
@pytest.mark.parametrize("problem", ["missing", "disabled", "scope", "ceiling"])
async def test_role_grants_cannot_assign_unknown_disabled_scope_or_over_ceiling(
    problem: str,
) -> None:
    session, mock = db()
    stored = role()
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), stored]
    catalog = PermissionCatalog(
        code="admin.login",
        enabled=problem != "disabled",
        data_scope="self" if problem == "scope" else "platform_metadata",
    )
    mock.scalars.return_value = result([] if problem == "missing" else [catalog])
    graph = GrantGraph(direct_role_ids=(), edges=(), grants=())
    with (
        patch.object(roles, "require_permissions", new_callable=AsyncMock),
        patch.object(roles, "load_graph", new_callable=AsyncMock, return_value=graph),
        pytest.raises(AppError) as error,
    ):
        await roles.replace_role_grants(
            session,
            actor_id=uuid4(),
            role_id=stored.id,
            expected_revision=4,
            grants=(("admin.login", "allow", "platform_metadata"),),
        )
    assert error.value.code == (
        ErrorCode.PERMISSION_DENIED if problem == "ceiling" else ErrorCode.STATE_CONFLICT
    )
    mock.execute.assert_not_awaited()
    mock.add_all.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("problem", ["default", "members", "child"])
async def test_role_delete_preserves_registration_members_and_child_references(
    problem: str,
) -> None:
    session, mock = db()
    stored = role()
    mock.scalar.side_effect = [
        AuthorizationRevision(revision=7),
        stored,
        1 if problem == "members" else 0,
        1 if problem == "child" else 0,
    ]
    mock.get.return_value = AuthPolicy(
        default_role_id=stored.id if problem == "default" else uuid4()
    )
    with (
        patch.object(roles, "require_permissions", new_callable=AsyncMock),
        pytest.raises(AppError) as error,
    ):
        await roles.delete_role(session, actor_id=uuid4(), role_id=stored.id, expected_revision=4)
    assert error.value.code == ErrorCode.STATE_CONFLICT
    mock.delete.assert_not_awaited()
    mock.execute.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "problem",
    [
        "cycle",
        "no-policy",
        "disabled-public",
        "protected-public",
        "admin-public",
        "last-admin",
        "self-elevation",
    ],
)
async def test_grant_replacement_preserves_graph_public_role_last_admin_and_actor_ceiling(
    problem: str,
) -> None:
    session, mock = db()
    stored, public = role(), role()
    public.enabled = problem != "disabled-public"
    public.protected = problem == "protected-public"
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), stored]
    mock.get.side_effect = [
        None if problem == "no-policy" else AuthPolicy(default_role_id=public.id),
        public,
    ]
    edges = (
        ((str(stored.id), str(public.id)), (str(public.id), str(stored.id)))
        if problem == "cycle"
        else ()
    )
    public_grants = (
        ((str(public.id), "admin.login", "allow", "platform_metadata"),)
        if problem == "admin-public"
        else ()
    )
    pairs = AsyncMock(
        side_effect=[set(), {("admin.login", "platform_metadata")}]
        if problem == "self-elevation"
        else None,
        return_value=set(),
    )
    with (
        patch.object(roles, "require_permissions", new_callable=AsyncMock),
        patch.object(roles, "_permission_ceiling", new_callable=AsyncMock, return_value=set()),
        patch.object(
            roles,
            "_grant_key",
            new_callable=AsyncMock,
            return_value={("client.login", "allow", "self")},
        ),
        patch.object(roles, "_actor_pairs", new=pairs),
        patch.object(roles, "_affected_users", new_callable=AsyncMock, return_value=[]),
        patch.object(roles, "_all_edges", new_callable=AsyncMock, return_value=edges),
        patch.object(roles, "_all_grants", new_callable=AsyncMock, return_value=public_grants),
        patch.object(roles, "revoke_lost_login", new_callable=AsyncMock),
        patch.object(
            roles,
            "count_login_capable_super_admins",
            new_callable=AsyncMock,
            return_value=0 if problem == "last-admin" else 1,
        ),
        pytest.raises(AppError) as error,
    ):
        await roles.replace_role_grants(
            session, actor_id=uuid4(), role_id=stored.id, expected_revision=4, grants=()
        )
    assert error.value.code == (
        ErrorCode.SERVICE_UNAVAILABLE
        if problem == "no-policy"
        else ErrorCode.PERMISSION_DENIED
        if problem == "self-elevation"
        else ErrorCode.STATE_CONFLICT
    )
    assert stored.revision == 4
    mock.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("missing_role", [False, True])
async def test_role_boundary_read_checks_existence_and_projects_only_allowed_metadata(
    missing_role: bool,
) -> None:
    from app.models import RoleGrantBoundary

    session, mock = db()
    stored = role()
    mock.get.return_value = None if missing_role else stored
    mock.scalars.return_value = result(
        [
            RoleGrantBoundary(
                boundary_kind="manage_account_role",
                target_role_id=uuid4(),
                data_scope=None,
                permission_code=None,
                revision=2,
            )
        ]
    )
    with patch.object(roles, "require_permissions", new_callable=AsyncMock):
        if missing_role:
            with pytest.raises(AppError) as error:
                await roles.read_grant_boundaries(session, actor_id=uuid4(), role_id=stored.id)
            assert error.value.code == ErrorCode.RESOURCE_NOT_FOUND
        else:
            values = await roles.read_grant_boundaries(session, actor_id=uuid4(), role_id=stored.id)
            assert values[0].boundary_kind == "manage_account_role" and values[0].revision == 2
            assert "user_id" not in values[0].model_dump_json()


@pytest.mark.asyncio
async def test_account_creation_cannot_assign_child_with_ungranted_ancestor() -> None:
    session, mock = db()
    direct, ancestor = uuid4(), uuid4()
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), direct]
    mock.execute.return_value = result([(direct, ancestor)])
    mock.scalars.return_value = result([direct])
    graph = GrantGraph(direct_role_ids=(str(uuid4()),), edges=(), grants=())
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "load_graph", new_callable=AsyncMock, return_value=graph),
        patch.object(users, "hash_password", new_callable=AsyncMock) as hash_password,
        pytest.raises(AppError) as error,
    ):
        await users.create_account(
            session,
            actor_id=uuid4(),
            email="synthetic@example.com",
            display_name=None,
            role_ids=(direct,),
        )
    assert error.value.code == ErrorCode.PERMISSION_DENIED
    hash_password.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
async def test_duplicate_account_creation_never_hashes_or_adds_new_identity() -> None:
    session, mock = db()
    mock.scalar.side_effect = [AuthorizationRevision(revision=7), uuid4()]
    with (
        patch.object(users, "require_permissions", new_callable=AsyncMock),
        patch.object(users, "hash_password", new_callable=AsyncMock) as hash_password,
        pytest.raises(AppError) as error,
    ):
        await users.create_account(
            session, actor_id=uuid4(), email="synthetic@example.com", display_name=None, role_ids=()
        )
    assert error.value.code == ErrorCode.STATE_CONFLICT
    hash_password.assert_not_awaited()
    mock.add.assert_not_called()


@pytest.mark.asyncio
async def test_admin_policy_read_revalidates_exact_admin_scope_and_public_role_validates() -> None:
    session, mock = db()
    current = scope()
    stored = stored_policy()
    public = role()
    mock.scalar.return_value = public
    mock.execute.return_value = result([("client.login", "allow", "self")])
    mock.scalars.return_value = result(
        [PermissionCatalog(code="client.login", audience="client", data_scope="self", enabled=True)]
    )
    with (
        patch.object(policy, "registration_policy", new_callable=AsyncMock, return_value=stored),
        patch.object(policy, "verify_scope_in_transaction", new_callable=AsyncMock) as verify,
    ):
        view = await policy.read_admin_policy(runtime(mock), current)
        assert view.revision == 4
    assert verify.await_args is not None
    assert verify.await_args.kwargs["user_id"] == current.user_id and verify.await_args.kwargs[
        "permissions"
    ] == ("admin.auth_policy.read",)
    assert await policy.validate_public_registration_role(session, public.id) is public
