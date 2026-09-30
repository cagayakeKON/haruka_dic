import '../api/api_client.dart';
import '../api/request_ids.dart' as ids;
import '../api/responses.dart';
import '../api/auth_models.dart';
import '../config/app_config.dart';

/// Account wire calls live here; widgets see use-case methods only.
final class AuthRepository {
  const AuthRepository(this.api, this.config);
  final ApiClient api;
  final AppConfig config;

  Future<void> verifyInstance() => api.verifyInstance();

  Future<AuthPolicy> policy() async =>
      (await api.getJson('/api/v1/auth/policy', AuthPolicy.fromJson)).data;

  Future<MailReceipt> register(String email, String password, {String? operationId}) async =>
      (await api.postJson(
        '/api/v1/auth/register',
        {'email': email, 'password': password},
        MailReceipt.fromJson,
        expectedStatus: 202,
        headers: {'X-Operation-ID': ?operationId},
      )).data;

  Future<MailReceipt> resend(String email) async => (await api.postJson(
    '/api/v1/auth/email/resend',
    {'email': email},
    MailReceipt.fromJson,
    expectedStatus: 202,
  )).data;

  Future<MailReceipt> requestRecovery(String email) async => (await api.postJson(
    '/api/v1/auth/recovery/request',
    {'email': email},
    MailReceipt.fromJson,
    expectedStatus: 202,
  )).data;

  Future<MailReceipt> requestManualRecovery(String email) async => (await api.postJson(
    '/api/v1/auth/recovery/manual',
    {'email': email},
    MailReceipt.fromJson,
    expectedStatus: 202,
  )).data;

  Future<void> verifyEmail(String token) =>
      api.postEmpty('/api/v1/auth/email/verify', {'token': token});

  Future<void> completeRecovery(String token, String password) =>
      api.postEmpty('/api/v1/auth/recovery/complete', {'token': token, 'new_password': password});

  Future<ActivationStatus> activationStatus(String continuationToken) async => (await api.getJson(
    '/api/v1/auth/activation/status',
    ActivationStatus.fromJson,
    headers: {'Authorization': 'Continuation $continuationToken'},
  )).data;

  Future<LoginResult> login(
    String email,
    String password, {
    required bool admin,
    String? operationId,
  }) async {
    if (config.platform == AppPlatform.web) {
      return (await api.postJson(
        admin ? '/api/v1/admin/auth/login' : '/api/v1/auth/login',
        {'email': email, 'password': password},
        LoginResult.web,
        headers: {'X-Operation-ID': ?operationId},
      )).data;
    }
    if (admin) throw const ApiFailure(code: 'PERMISSION_DENIED');
    return (await api.postJson(
      '/api/v1/auth/native/login',
      {'email': email, 'password': password, 'platform': config.platform.name},
      LoginResult.native,
      headers: {'X-Operation-ID': ?operationId},
    )).data;
  }

  Future<LoginResult> nativeRefresh(String secret, String requestId) async => (await api.postJson(
    '/api/v1/auth/native/refresh',
    {'refresh_token': secret, 'refresh_request_id': requestId},
    LoginResult.native,
  )).data;

  Future<CsrfRead> csrf({required bool admin}) async {
    final response = await api.getJson(
      admin ? '/api/v1/admin/auth/csrf' : '/api/v1/auth/csrf',
      CsrfRead.fromJson,
    );
    return response.data;
  }

  Future<AccessRead> access({required bool admin, required Map<String, String> headers}) async =>
      (await api.getJson(
        admin ? '/api/v1/admin/me/access' : '/api/v1/me/access',
        AccessRead.fromJson,
        headers: headers,
      )).data;

  Future<AccountRead> account(Map<String, String> headers) async =>
      (await api.getJson('/api/v1/users/me/account', AccountRead.fromJson, headers: headers)).data;

  Future<PageResponse<SessionSummary>> sessions({
    required bool admin,
    required Map<String, String> headers,
    String? cursor,
  }) => api.getPage(
    '${admin ? '/api/v1/admin/auth/sessions' : '/api/v1/auth/sessions'}'
    '?limit=20${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
    SessionSummary.fromJson,
    headers: headers,
  );

  Future<void> revoke(
    String id, {
    required bool admin,
    required Map<String, String> headers,
    String? operationId,
  }) => api.postEmpty(
    admin ? '/api/v1/admin/auth/sessions/$id/revoke' : '/api/v1/auth/sessions/$id/revoke',
    const <String, Object?>{},
    headers: {...headers, 'X-Operation-ID': ?operationId},
  );

  Future<void> revokeAll({required bool admin, required Map<String, String> headers}) =>
      api.postEmpty(
        admin ? '/api/v1/admin/auth/sessions/revoke-all' : '/api/v1/auth/sessions/revoke-all',
        const <String, Object?>{},
        headers: headers,
      );

  Future<void> logout({
    required bool admin,
    required Map<String, String> headers,
    String? operationId,
  }) => api.postEmpty(
    admin ? '/api/v1/admin/auth/logout' : '/api/v1/auth/logout',
    const <String, Object?>{},
    headers: {...headers, 'X-Operation-ID': ?operationId},
  );

  Future<void> changePassword(
    String current,
    String next, {
    required bool admin,
    required Map<String, String> headers,
    String? operationId,
  }) => api.postEmpty(
    admin ? '/api/v1/admin/auth/password/change' : '/api/v1/auth/password/change',
    {'current_password': current, 'new_password': next},
    headers: {...headers, 'X-Operation-ID': ?operationId},
  );

  Future<AdminPolicy> adminPolicy(Map<String, String> headers) async =>
      (await api.getJson('/api/v1/admin/auth-policy', AdminPolicy.fromJson, headers: headers)).data;

  Future<AdminPolicy> updateAdminPolicy(
    String registrationMode,
    int revision,
    Map<String, String> headers, {
    String? recoveryMode,
  }) async => (await api.patchJson(
    '/api/v1/admin/auth-policy',
    {
      'registration_mode': registrationMode,
      'expected_revision': revision,
      'recovery_mode': ?recoveryMode,
    },
    AdminPolicy.fromJson,
    headers: headers,
  )).data;

  Future<List<RoleRead>> adminRoles(Map<String, String> headers) async {
    final roles = <RoleRead>[];
    final seen = <String>{};
    String? cursor;
    while (true) {
      final page = await api.getPage(
        '/api/v1/admin/roles?limit=100'
        '${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
        RoleRead.fromJson,
        headers: headers,
      );
      roles.addAll(page.data);
      final next = page.nextCursor;
      if (next == null || !seen.add(next) || seen.length > 20) {
        return List.unmodifiable(roles);
      }
      cursor = next;
    }
  }

  Future<RoleRead> adminRole(String roleId, Map<String, String> headers) async =>
      (await api.getJson('/api/v1/admin/roles/$roleId', RoleRead.fromJson, headers: headers)).data;

  Future<List<PermissionCatalogRead>> adminPermissions(Map<String, String> headers) async =>
      (await api.getJson(
        '/api/v1/admin/permissions',
        PermissionCatalogRead.list,
        headers: headers,
      )).data;

  Future<List<GrantBoundaryRead>> adminGrantBoundaries(
    String roleId,
    Map<String, String> headers,
  ) async => (await api.getJson(
    '/api/v1/admin/roles/$roleId/grant-boundaries',
    GrantBoundaryRead.list,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> createAdminRole(
    String code,
    String name,
    String? description,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/roles',
    {'code': code, 'name': name, 'description': description},
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> updateAdminRole(
    String roleId,
    int revision,
    String name,
    String? description,
    Map<String, String> headers,
  ) async => (await api.patchJson(
    '/api/v1/admin/roles/$roleId',
    {'expected_revision': revision, 'name': name, 'description': description},
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> setAdminRoleEnabled(
    String roleId,
    int revision,
    bool enabled,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/roles/$roleId/enabled',
    {'expected_revision': revision, 'enabled': enabled},
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> replaceAdminRoleGrants(
    String roleId,
    int revision,
    List<RoleGrantRead> grants,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/roles/$roleId/grants',
    {
      'expected_revision': revision,
      'grants': [
        for (final grant in grants)
          {
            'permission_code': grant.permissionCode,
            'effect': grant.effect,
            'data_scope': grant.dataScope,
          },
      ],
    },
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> replaceAdminRoleParents(
    String roleId,
    int revision,
    List<String> parentRoleIds,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/roles/$roleId/inheritance',
    {'expected_revision': revision, 'parent_role_ids': parentRoleIds},
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> deleteAdminRole(
    String roleId,
    int revision,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/roles/$roleId/deletion',
    {'expected_revision': revision},
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AuthorizationWriteResult> replaceAdminGrantBoundaries(
    String roleId,
    int revision,
    List<GrantBoundaryRead> boundaries,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/roles/$roleId/grant-boundaries',
    {
      'expected_revision': revision,
      'boundaries': [
        for (final boundary in boundaries)
          {
            'boundary_kind': boundary.boundaryKind,
            'target_role_id': boundary.targetRoleId,
            'permission_code': boundary.permissionCode,
            'data_scope': boundary.dataScope,
          },
      ],
    },
    AuthorizationWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<List<GovernedAccountRead>> adminAccounts(Map<String, String> headers) async {
    final accounts = <GovernedAccountRead>[];
    final seen = <String>{};
    String? cursor;
    while (true) {
      final page = await api.getPage(
        '/api/v1/admin/users?limit=100'
        '${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
        GovernedAccountRead.fromJson,
        headers: headers,
      );
      accounts.addAll(page.data);
      final next = page.nextCursor;
      if (next == null || !seen.add(next) || seen.length > 20) {
        return List.unmodifiable(accounts);
      }
      cursor = next;
    }
  }

  Future<GovernedAccountRead> adminAccount(String userId, Map<String, String> headers) async =>
      (await api.getJson(
        '/api/v1/admin/users/$userId',
        GovernedAccountRead.fromJson,
        headers: headers,
      )).data;

  Future<GovernanceSummaryRead> adminGovernanceSummary(Map<String, String> headers) async =>
      (await api.getJson(
        '/api/v1/admin/governance-summary',
        GovernanceSummaryRead.fromJson,
        headers: headers,
      )).data;

  Future<PageResponse<AuditEventRead>> adminAuditEvents(
    Map<String, String> headers, {
    String? cursor,
    String? result,
  }) {
    final query = [
      'limit=50',
      if (cursor != null) 'cursor=${Uri.encodeQueryComponent(cursor)}',
      if (result != null) 'result=${Uri.encodeQueryComponent(result)}',
    ].join('&');
    return api.getPage(
      '/api/v1/admin/audit-events?$query',
      AuditEventRead.fromJson,
      headers: headers,
    );
  }

  Future<AccountCeilingsRead> adminAccountCeilings(Map<String, String> headers) async =>
      (await api.getJson(
        '/api/v1/admin/account-ceilings',
        AccountCeilingsRead.fromJson,
        headers: headers,
      )).data;

  Future<AccountWriteResult> createAdminAccount(
    String email,
    String? displayName,
    List<String> roleIds,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/users',
    {'email': email, 'display_name': displayName, 'role_ids': roleIds},
    AccountWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AccountWriteResult> setAdminAccountStatus(
    String userId,
    int revision,
    String status,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/users/$userId/status',
    {'expected_revision': revision, 'status': status},
    AccountWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AccountWriteResult> decideAdminApproval(
    String userId,
    int revision,
    String decision,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/users/$userId/approval',
    {'expected_revision': revision, 'decision': decision},
    AccountWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<AccountWriteResult> replaceAdminAccountRoles(
    String userId,
    int revision,
    List<String> roleIds,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/users/$userId/roles',
    {'expected_revision': revision, 'role_ids': roleIds},
    AccountWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<List<ManualRecoveryRead>> adminRecoveryRequests(
    String userId,
    Map<String, String> headers,
  ) async => (await api.getJson(
    '/api/v1/admin/users/$userId/recovery-requests',
    ManualRecoveryRead.list,
    headers: headers,
  )).data;

  Future<ManualRecoveryDecisionResult> decideAdminRecovery(
    String userId,
    String challengeId,
    int revision,
    String decision,
    String? verificationMethod,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/users/$userId/recovery-decisions',
    {
      'challenge_id': challengeId,
      'expected_revision': revision,
      'decision': decision,
      'verification_method': ?verificationMethod,
    },
    ManualRecoveryDecisionResult.fromJson,
    headers: headers,
  )).data;

  Future<List<AccountSessionRead>> adminAccountSessions(
    String userId,
    Map<String, String> headers,
  ) async => (await api.getJson(
    '/api/v1/admin/users/$userId/sessions',
    AccountSessionRead.list,
    headers: headers,
  )).data;

  Future<List<MenuRead>> adminMenus(Map<String, String> headers) async =>
      (await api.getJson('/api/v1/admin/menus', MenuRead.list, headers: headers)).data;

  Future<MenuCatalogRead> adminMenuCatalog(Map<String, String> headers) async => (await api.getJson(
    '/api/v1/admin/menu-catalog',
    MenuCatalogRead.fromJson,
    headers: headers,
  )).data;

  Future<MenuWriteResult> createAdminMenuGroup(
    String code,
    String audience,
    String title,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/menus',
    {'code': code, 'audience': audience, 'title': title, 'parent_menu_id': null, 'sort_order': 0},
    MenuWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<MenuWriteResult> replaceAdminMenuLayout(
    List<MenuRead> items,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/menus/layout',
    {
      'items': [
        for (final item in items)
          {
            'menu_id': item.id,
            'expected_revision': item.revision,
            'title': item.title,
            'parent_menu_id': item.parentMenuId,
            'sort_order': item.sortOrder,
            'icon_key': item.iconKey,
            'enabled': item.enabled,
            'permission_match': item.permissionMatch,
            'permission_codes': item.permissionCodes,
          },
      ],
    },
    MenuWriteResult.fromJson,
    headers: headers,
  )).data;

  Future<MenuPreviewRead> previewAdminMenus(
    String userId,
    String audience,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/menus/preview',
    {'user_id': userId, 'audience': audience},
    MenuPreviewRead.fromJson,
    headers: headers,
  )).data;

  Future<AccountWriteResult> revokeAdminAccountSessions(
    String userId,
    int revision,
    Map<String, Object?> body,
    Map<String, String> headers,
  ) async => (await api.postJson(
    '/api/v1/admin/users/$userId/session-revocations',
    body,
    AccountWriteResult.fromJson,
    headers: headers,
  )).data;

  /// A stable random UUID is kept for a single in-flight native refresh.
  static String newRequestId() => ids.newRequestId();
}
