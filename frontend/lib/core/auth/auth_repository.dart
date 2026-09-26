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
    bool open,
    int revision,
    Map<String, String> headers,
  ) async => (await api.patchJson(
    '/api/v1/admin/auth-policy',
    {'registration_mode': open ? 'open' : 'closed', 'expected_revision': revision},
    AdminPolicy.fromJson,
    headers: headers,
  )).data;

  /// A stable random UUID is kept for a single in-flight native refresh.
  static String newRequestId() => ids.newRequestId();
}
