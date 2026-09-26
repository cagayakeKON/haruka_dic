"""Release-owned permission codes and initial templates, never runtime wildcards.

The catalog declares authorization vocabulary, not implemented HTTP capabilities.
Existing grants are not reconciled to these templates by a later seed run.
"""

from types import MappingProxyType

CLIENT_CODES = tuple(
    [
        "client.login",
        "client.material.list",
        "client.material.read",
        "client.material.import",
        "client.material.update",
        "client.material.reparse",
        "client.material.analyze",
        "client.material.delete",
        "client.reading.progress.update",
        "client.bookmark.read",
        "client.bookmark.create",
        "client.bookmark.delete",
        "client.collection.read",
        "client.collection.create",
        "client.collection.update",
        "client.collection.delete",
        "client.vocabulary_notebook.read",
        "client.vocabulary_notebook.create",
        "client.vocabulary_notebook.update",
        "client.vocabulary_notebook.delete",
        "client.vocabulary.csv.export",
        "client.vocabulary.csv.import",
        "client.vocabulary.photo.import",
        "client.practice.read",
        "client.practice.start",
        "client.practice.answer",
        "client.practice.generate",
        "client.practice.mistake.read",
        "client.practice.mistake.favorite",
        "client.practice.grade.request",
        "client.practice.review.request",
        "client.diagnosis.read",
        "client.diagnosis.generate",
        "client.ai.explain",
        "client.ai.feedback",
        "client.agent.read",
        "client.agent.use",
        "client.agent.delete",
        "client.speech.generate",
        "client.speech.play",
        "client.exam.list",
        "client.exam.read",
        "client.exam.import",
        "client.exam.edit",
        "client.exam_session.start",
        "client.exam_session.read",
        "client.exam_session.save",
        "client.exam_session.submit",
        "client.exam_grade.request",
        "client.exam_grade.read",
        "client.exam_grade.regrade",
        "client.profile.read",
        "client.profile.update",
        "client.profile.avatar.update",
        "client.credential.read",
        "client.credential.manage",
        "client.credential.test",
        "client.job.read",
        "client.job.cancel",
        "client.job.retry",
    ]
)

ADMIN_CODES = tuple(
    [
        "admin.login",
        "admin.dashboard.view",
        "admin.user.read",
        "admin.user.create",
        "admin.user.approve",
        "admin.user.update",
        "admin.user.enable",
        "admin.user.disable",
        "admin.user.role.assign",
        "admin.session.read",
        "admin.session.revoke",
        "admin.role.read",
        "admin.role.create",
        "admin.role.update",
        "admin.role.delete",
        "admin.role.permission.assign",
        "admin.permission.read",
        "admin.grant_boundary.read",
        "admin.grant_boundary.update",
        "admin.protected_role.manage",
        "admin.menu.read",
        "admin.menu.update",
        "admin.auth_policy.read",
        "admin.auth_policy.update",
        "admin.quota.read",
        "admin.quota.update",
        "admin.model_catalog.read",
        "admin.model_catalog.update",
        "admin.resource_metadata.read",
        "admin.job.read",
        "admin.job.cancel",
        "admin.job.retry",
        "admin.audit.read",
        "admin.diagnostics.read",
    ]
)

ROLE_TEMPLATES = MappingProxyType(
    {
        "learner": CLIENT_CODES,
        "client_readonly": tuple(
            [
                "client.login",
                "client.material.list",
                "client.material.read",
                "client.bookmark.read",
                "client.collection.read",
                "client.vocabulary_notebook.read",
                "client.practice.read",
                "client.diagnosis.read",
                "client.agent.read",
                "client.speech.play",
                "client.exam.list",
                "client.exam.read",
                "client.exam_session.read",
                "client.exam_grade.read",
                "client.profile.read",
                "client.credential.read",
                "client.job.read",
                "client.vocabulary.csv.export",
            ]
        ),
        "operator": tuple(
            [
                "admin.login",
                "admin.dashboard.view",
                "admin.resource_metadata.read",
                "admin.job.read",
                "admin.job.cancel",
                "admin.job.retry",
                "admin.diagnostics.read",
            ]
        ),
        "account_admin": tuple(
            [
                "admin.login",
                "admin.user.read",
                "admin.user.create",
                "admin.user.approve",
                "admin.user.update",
                "admin.user.enable",
                "admin.user.disable",
                "admin.user.role.assign",
                "admin.session.read",
                "admin.session.revoke",
                "admin.role.read",
            ]
        ),
        "security_admin": tuple(
            [
                "admin.login",
                "admin.role.read",
                "admin.role.create",
                "admin.role.update",
                "admin.role.delete",
                "admin.role.permission.assign",
                "admin.permission.read",
                "admin.menu.read",
                "admin.menu.update",
                "admin.auth_policy.read",
                "admin.auth_policy.update",
            ]
        ),
        "auditor": ("admin.login", "admin.audit.read", "admin.diagnostics.read"),
        "super_admin": ADMIN_CODES,
    }
)


def permission_document() -> dict[str, object]:
    """Export exact registered vocabulary without implying implemented endpoints."""
    codes = (*CLIENT_CODES, *ADMIN_CODES)
    if len(set(codes)) != len(codes) or any(
        permission not in codes for grants in ROLE_TEMPLATES.values() for permission in grants
    ):
        raise ValueError("permission registration is duplicated or references unknown codes")
    return {
        "schema_version": 1,
        "catalog_version": "identity-permissions-v3",
        "implemented_business_routes": [],
        "permissions": [
            {
                "code": code,
                "audience": code.split(".", 1)[0],
                "data_scope": "self" if code.startswith("client.") else "platform_metadata",
            }
            for code in sorted(codes)
        ],
        "role_templates": {code: sorted(grants) for code, grants in sorted(ROLE_TEMPLATES.items())},
        "menus": [
            {
                "code": "administration",
                "route_key": "/admin",
                "audience": "admin",
                "permission_code": "admin.login",
                "enabled": False,
            }
        ],
        "registration_policy": {"mode": "closed", "default_role": "learner"},
    }
