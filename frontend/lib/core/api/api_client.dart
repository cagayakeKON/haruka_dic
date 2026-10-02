import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'browser_credentials_stub.dart'
    if (dart.library.js_interop) 'browser_credentials_web.dart'
    as browser_credentials;
import 'auth_models.dart';
import 'request_ids.dart';
import 'responses.dart';

typedef RequestObservation = void Function(
  bool success,
  int? statusCode,
  Duration elapsed,
  String? serverRequestId,
);

/// A confirmed, non-secret account binding. It is never inferred from a
/// resource payload, URL, or caller-supplied request header.
final class ApiSessionBinding {
  const ApiSessionBinding._({
    required this.instanceId,
    required this.userId,
    required this.audience,
    required this.sessionRef,
    required this.generation,
  });

  final String instanceId;
  final String userId;
  final String audience;
  final String sessionRef;
  final int generation;
}

const _sessionHeader = 'X-Haruka-Expected-Session';
const _instanceResponseHeader = 'X-Haruka-Instance-ID';
const _sessionResponseHeader = 'X-Haruka-Session-Ref';
final Object _retiredSignOutZone = Object();

/// Authentication/bootstrap calls establish identity and must not be fenced
/// by a previous session. Every other route is private by default.
const _unboundMethods = <String, Set<String>>{
  '/health/ready': {'GET'},
  '/api/v1/meta': {'GET'},
  '/api/v1/auth/policy': {'GET'},
  '/api/v1/auth/register': {'POST'},
  '/api/v1/auth/email/resend': {'POST'},
  '/api/v1/auth/email/verify': {'POST'},
  '/api/v1/auth/recovery/request': {'POST'},
  '/api/v1/auth/recovery/manual': {'POST'},
  '/api/v1/auth/recovery/complete': {'POST'},
  '/api/v1/auth/activation/status': {'GET'},
  '/api/v1/auth/login': {'POST'},
  '/api/v1/admin/auth/login': {'POST'},
  '/api/v1/auth/native/login': {'POST'},
  '/api/v1/auth/native/refresh': {'POST'},
  '/api/v1/auth/refresh': {'POST'},
  '/api/v1/admin/auth/refresh': {'POST'},
  '/api/v1/auth/csrf': {'GET'},
  '/api/v1/admin/auth/csrf': {'GET'},
  '/api/v1/me/access': {'GET'},
  '/api/v1/admin/me/access': {'GET'},
  '/api/v1/frontend-logs/anonymous': {'POST'},
};

bool _unboundRequest(String path, String method) =>
    _unboundMethods[path]?.contains(method.toUpperCase()) ?? false;

/// Owns one transport per app instance and verifies account scope.
final class ApiClient {
  ApiClient(AppConfig config, {HttpClientAdapter? adapter, this.requireSessionBinding = false})
    : _instanceId = config.instanceId,
      _dio = Dio(
        BaseOptions(
          baseUrl: config.apiBaseUrl.toString(),
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          followRedirects: false,
          headers: const {'Accept': 'application/json', 'Accept-Language': 'zh-Hans'},
        ),
      ) {
    final selectedAdapter = adapter ?? browser_credentials.credentialedAdapter();
    if (selectedAdapter != null) _dio.httpClientAdapter = selectedAdapter;
  }

  final Dio _dio;
  String _instanceId;
  final bool requireSessionBinding;
  ApiSessionBinding? _binding;
  ApiSessionBinding? _retiredSignOutBinding;
  int _bindingGeneration = 0;
  RequestObservation? Function(String operationId, String clientRequestId)? beginRequestObservation;

  /// Called only after AuthController has accepted a fresh me/access result.
  /// Same-session token rotation keeps the current generation and in-flight reads.
  ApiSessionBinding bindConfirmedAccess(AccessRead access) {
    if (access.instanceId != _instanceId ||
        (access.audience != 'client' && access.audience != 'admin') ||
        access.userId.isEmpty ||
        access.sessionRef.isEmpty) {
      throw const ApiFailure(code: 'INSTANCE_MISMATCH');
    }
    final current = _binding;
    if (current != null &&
        current.instanceId == access.instanceId &&
        current.userId == access.userId &&
        current.audience == access.audience &&
        current.sessionRef == access.sessionRef) {
      return current;
    }
    final bound = ApiSessionBinding._(
      instanceId: access.instanceId,
      userId: access.userId,
      audience: access.audience,
      sessionRef: access.sessionRef,
      generation: ++_bindingGeneration,
    );
    _binding = bound;
    return bound;
  }

  /// Call synchronously before clearing the local account on logout/switch.
  void clearSessionBinding() {
    ++_bindingGeneration;
    _binding = null;
  }

  void clearSessionBindingIfCurrent(ApiSessionBinding captured) {
    if (identical(_binding, captured)) clearSessionBinding();
  }

  Future<T> withRetiredSignOutBinding<T>(
    ApiSessionBinding captured,
    Future<T> Function() action,
  ) async {
    if (_retiredSignOutBinding != null || _binding != null) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    _retiredSignOutBinding = captured;
    try {
      return await runZoned<Future<T>>(action, zoneValues: {_retiredSignOutZone: captured});
    } finally {
      if (identical(_retiredSignOutBinding, captured)) _retiredSignOutBinding = null;
    }
  }

  ApiSessionBinding? get sessionBinding => _binding;

  String get instanceId => _instanceId;

  Uri get endpoint => Uri.parse(_dio.options.baseUrl);

  /// Points this client at a probed origin. An active session must already be cleared.
  void retarget(Uri endpoint, String instanceId) {
    if (_binding != null || _retiredSignOutBinding != null) {
      throw StateError('Cannot retarget an active session');
    }
    if (!RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(instanceId)) {
      throw const FormatException('Invalid instance');
    }
    if (!endpoint.isAbsolute ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty && endpoint.path != '/') ||
        (endpoint.scheme != 'https' && endpoint.scheme != 'http')) {
      throw const FormatException('Invalid endpoint');
    }
    _instanceId = instanceId;
    _dio.options.baseUrl = Uri(
      scheme: endpoint.scheme,
      host: endpoint.host,
      port: endpoint.hasPort ? endpoint.port : null,
    ).toString();
    ++_bindingGeneration;
  }

  /// The caller must immediately hide private UI and rebind through access.
  /// The callback is never fired by a stale response from a prior generation.
  void Function()? onSessionBindingLost;

  /// Fail closed before any account action if an isolated run reaches a service
  /// from another instance/schema. The same check protects normal targets.
  Future<void> verifyInstance({CancelToken? cancelToken}) async {
    final result = await getJson('/api/v1/meta', MetaRead.fromJson, cancelToken: cancelToken);
    if (result.data.instanceId != _instanceId || result.data.apiVersion != 'v1') {
      throw const ApiFailure(code: 'INSTANCE_MISMATCH');
    }
  }

  Future<SuccessResponse<HealthRead>> checkReadiness({CancelToken? cancelToken}) =>
      getJson('/health/ready', HealthRead.fromJson, cancelToken: cancelToken);

  Future<SuccessResponse<T>> getJson<T>(
    String path,
    T Function(Object?) decode, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(path, cancelToken: cancelToken, headers: headers);
    _ensureCurrentGeneration(path, bindingGeneration);
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    } finally {
      _ensureCurrentGeneration(path, bindingGeneration);
    }
  }

  Future<PageResponse<T>> getPage<T>(
    String path,
    T Function(Object?) decode, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(path, cancelToken: cancelToken, headers: headers);
    _ensureCurrentGeneration(path, bindingGeneration);
    try {
      return PageResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    } finally {
      _ensureCurrentGeneration(path, bindingGeneration);
    }
  }

  Future<SuccessResponse<T>> postJson<T>(
    String path,
    Object body,
    T Function(Object?) decode, {
    int expectedStatus = 200,
    Set<int>? acceptedStatuses,
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      method: 'POST',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
    _ensureCurrentGeneration(path, bindingGeneration, method: 'POST');
    if (!(acceptedStatuses ?? {expectedStatus}).contains(response.statusCode)) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    } finally {
      _ensureCurrentGeneration(path, bindingGeneration, method: 'POST');
    }
  }

  Future<void> postEmpty(
    String path,
    Object body, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      method: 'POST',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
    _ensureCurrentGeneration(path, bindingGeneration, method: 'POST');
    if (response.statusCode != 204 || (response.data != null && response.data != '')) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  Future<SuccessResponse<T>> patchJson<T>(
    String path,
    Object body,
    T Function(Object?) decode, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      method: 'PATCH',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
    _ensureCurrentGeneration(path, bindingGeneration, method: 'PATCH');
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    } finally {
      _ensureCurrentGeneration(path, bindingGeneration, method: 'PATCH');
    }
  }

  Future<SuccessResponse<T>> deleteJson<T>(
    String path,
    Object body,
    T Function(Object?) decode, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      method: 'DELETE',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
    _ensureCurrentGeneration(path, bindingGeneration, method: 'DELETE');
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    } finally {
      _ensureCurrentGeneration(path, bindingGeneration, method: 'DELETE');
    }
  }

  /// Native transport semantics are explicit, never decoded as JSON envelopes.
  Future<void> deleteEmpty(
    String path, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      method: 'DELETE',
      cancelToken: cancelToken,
      headers: headers,
    );
    _ensureCurrentGeneration(path, bindingGeneration, method: 'DELETE');
    if (response.statusCode != 204 || (response.data != null && response.data != '')) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  Future<Uint8List> download(
    String path, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      responseType: ResponseType.bytes,
      cancelToken: cancelToken,
      headers: headers,
    );
    _ensureCurrentGeneration(path, bindingGeneration);
    final value = response.data;
    if (value is! List<int>) throw const ApiFailure(code: 'INVALID_RESPONSE');
    return Uint8List.fromList(value);
  }

  Future<void> uploadBytes(String path, Uint8List bytes, {CancelToken? cancelToken}) async {
    final bindingGeneration = _bindingGeneration;
    final response = await _request(
      path,
      method: 'PUT',
      data: bytes,
      contentType: 'application/octet-stream',
      cancelToken: cancelToken,
    );
    _ensureCurrentGeneration(path, bindingGeneration, method: 'PUT');
    if (response.statusCode != 204 || (response.data != null && response.data != '')) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  Future<Response<Object?>> _request(
    String path, {
    String method = 'GET',
    ResponseType responseType = ResponseType.json,
    Object? data,
    String? contentType,
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.tryParse(path);
    if (uri == null || uri.hasAuthority || uri.hasScheme || !path.startsWith('/')) {
      throw const ApiFailure(code: 'INVALID_REQUEST');
    }
    final privateRequest = !_unboundRequest(uri.path, method);
    final signOutOnly =
        uri.path == '/api/v1/auth/logout' ||
        uri.path == '/api/v1/admin/auth/logout' ||
        RegExp(r'^/api/v1/auth/sessions/[^/]+/revoke$').hasMatch(uri.path);
    final zonedBinding = Zone.current[_retiredSignOutZone];
    final inSignOut =
        zonedBinding is ApiSessionBinding &&
        identical(zonedBinding, _retiredSignOutBinding) &&
        signOutOnly;
    if (inSignOut && _binding != null) throw const ApiFailure(code: 'SESSION_INVALID');
    final retiredSignOut = inSignOut ? _retiredSignOutBinding : null;
    final binding = _binding ?? retiredSignOut;
    final bindingGeneration = _bindingGeneration;
    if (requireSessionBinding && privateRequest && binding == null) {
      throw const ApiFailure(code: 'AUTH_SCOPE_REQUIRED');
    }
    final deferJson = requireSessionBinding && privateRequest && responseType == ResponseType.json;
    final watch = Stopwatch()..start();
    final observable = !uri.path.contains('/frontend-logs');
    final requestHeaders = <String, String>{...?headers};
    // A caller cannot supply or override the trusted binding header.
    requestHeaders.removeWhere((key, _) => key.toLowerCase() == _sessionHeader.toLowerCase());
    if (requireSessionBinding && privateRequest) {
      requestHeaders[_sessionHeader] = binding!.sessionRef;
    }
    final operationId =
        requestHeaders['X-Operation-ID'] ??
        requestHeaders['Idempotency-Key'] ??
        (data is Map<String, Object?> && data['refresh_request_id'] is String
            ? data['refresh_request_id']! as String
            : newRequestId());
    final clientRequestId = newRequestId();
    requestHeaders['X-Operation-ID'] = operationId;
    requestHeaders['X-Client-Request-ID'] = clientRequestId;
    final observe = observable ? beginRequestObservation?.call(operationId, clientRequestId) : null;
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          responseType: deferJson ? ResponseType.bytes : responseType,
          contentType: contentType,
          headers: requestHeaders,
        ),
      );
      try {
        _verifyResponseBinding(
          response,
          privateRequest,
          binding,
          bindingGeneration,
          retiredSignOut: retiredSignOut != null,
        );
        if (deferJson) _decodeJsonAfterBinding(response);
      } on ApiFailure catch (failure) {
        observe?.call(false, response.statusCode, watch.elapsed, null);
        throw failure.withStatusCode(response.statusCode);
      }
      observe?.call(true, response.statusCode, watch.elapsed, _serverRequestId(response));
      return response;
    } on DioException catch (error) {
      if (bindingGeneration != _bindingGeneration) {
        throw const ApiFailure(code: 'SESSION_INVALID');
      }
      if (error.type == DioExceptionType.cancel) throw const ApiFailure(code: 'CANCELLED');
      final response = error.response;
      if (response != null) {
        try {
          _verifyResponseBinding(
            response,
            privateRequest,
            binding,
            bindingGeneration,
            retiredSignOut: retiredSignOut != null,
          );
          if (deferJson) _decodeJsonAfterBinding(response);
        } on ApiFailure catch (failure) {
          observe?.call(false, response.statusCode, watch.elapsed, null);
          throw failure.withStatusCode(response.statusCode);
        }
        final scopeError = privateRequest ? _scopeErrorCode(response) : null;
        if (scopeError != null) {
          if (binding != null) _loseCurrentBinding(binding);
          observe?.call(false, response.statusCode, watch.elapsed, null);
          throw ApiFailure(code: scopeError, statusCode: response.statusCode);
        }
      }
      observe?.call(false, response?.statusCode, watch.elapsed, _serverRequestId(response));
      if (response != null) {
        try {
          throw ApiFailure.fromJson(
            response.data,
            retryAfter: _retryAfter(response.headers.value('retry-after')),
            statusCode: response.statusCode,
          );
        } on FormatException {
          throw ApiFailure(code: 'INVALID_RESPONSE', statusCode: response.statusCode);
        }
      }
      throw ApiFailure(
        code: 'NETWORK_UNAVAILABLE',
        retryableTransport: const {
          DioExceptionType.connectionError,
          DioExceptionType.connectionTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.sendTimeout,
        }.contains(error.type),
      );
    }
  }

  void _ensureCurrentGeneration(String path, int generation, {String method = 'GET'}) {
    if (generation != _bindingGeneration) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
  }

  void _verifyResponseBinding(
    Response<Object?> response,
    bool privateRequest,
    ApiSessionBinding? issuedBinding,
    int issuedGeneration, {
    bool retiredSignOut = false,
  }) {
    if (issuedGeneration != _bindingGeneration) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    if (!privateRequest) return;
    final instance = response.headers.value(_instanceResponseHeader);
    final session = response.headers.value(_sessionResponseHeader);
    if (issuedGeneration != _bindingGeneration ||
        (issuedBinding != null &&
            !identical(issuedBinding, _binding) &&
            !(retiredSignOut && identical(issuedBinding, _retiredSignOutBinding)))) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    if (!requireSessionBinding && instance == null && session == null) return;
    // The normal app requires the matching server binding on every private
    // response. The opt-out constructor exists only for isolated legacy tests.
    if (response.statusCode == 401 && instance == null && session == null) return;
    if (issuedBinding == null ||
        instance != issuedBinding.instanceId ||
        session != issuedBinding.sessionRef) {
      if (issuedBinding != null) _loseCurrentBinding(issuedBinding);
      throw const ApiFailure(code: 'AUTH_SCOPE_CHANGED');
    }
  }

  void _decodeJsonAfterBinding(Response<Object?> response) {
    final raw = response.data;
    if (raw is! List<int>) throw const ApiFailure(code: 'INVALID_RESPONSE');
    if (raw.isEmpty && response.statusCode == 204) {
      response.data = null;
      return;
    }
    try {
      response.data = jsonDecode(utf8.decode(raw));
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  String? _scopeErrorCode(Response<Object?> response) {
    if (response.statusCode != 409) return null;
    final body = response.data;
    if (body is! Map<String, dynamic>) return null;
    final error = body['error'];
    if (error is! Map<String, dynamic>) return null;
    final code = error['code'];
    return code == 'AUTH_SCOPE_CHANGED' || code == 'AUTH_SCOPE_REQUIRED' ? code as String : null;
  }

  void _loseCurrentBinding(ApiSessionBinding issuedBinding) {
    if (!identical(_binding, issuedBinding)) return;
    clearSessionBinding();
    try {
      onSessionBindingLost?.call();
    } on Object {
      // A UI hook must not replace the trusted scope error returned to callers.
    }
  }

  String? _serverRequestId(Response<Object?>? response) {
    if (response == null) return null;
    final body = response.data;
    final meta = body is Map<String, dynamic> ? body['meta'] : null;
    final fromBody = meta is Map<String, dynamic> ? meta['request_id'] : null;
    final candidate = fromBody is String ? fromBody : response.headers.value('x-request-id');
    return candidate != null &&
            RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(candidate)
        ? candidate
        : null;
  }

  Duration? _retryAfter(String? value) {
    if (value == null || value.length > 64) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) return Duration(seconds: seconds.clamp(1, 300));
    final date = RegExp(r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$')
        .firstMatch(value);
    if (date == null) return null;
    const months = <String, int>{
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final month = months[date[2]];
    if (month == null) return null;
    final target = DateTime.utc(
      int.parse(date[3]!),
      month,
      int.parse(date[1]!),
      int.parse(date[4]!),
      int.parse(date[5]!),
      int.parse(date[6]!),
    );
    final delta = target.difference(DateTime.now().toUtc());
    return Duration(seconds: delta.inSeconds.clamp(1, 300));
  }

  void close() => _dio.close(force: true);
}
