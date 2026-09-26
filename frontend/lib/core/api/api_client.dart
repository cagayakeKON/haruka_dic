import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'request_ids.dart';
import 'responses.dart';

typedef RequestObservation = void Function(
  bool success,
  int? statusCode,
  Duration elapsed,
  String? serverRequestId,
);

/// Owns one transport per app instance and verifies account scope.
final class ApiClient {
  ApiClient(AppConfig config, {HttpClientAdapter? adapter})
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
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final Dio _dio;
  final String _instanceId;
  RequestObservation? Function(String operationId, String clientRequestId)? beginRequestObservation;

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
    final response = await _request(path, cancelToken: cancelToken, headers: headers);
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  Future<PageResponse<T>> getPage<T>(
    String path,
    T Function(Object?) decode, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final response = await _request(path, cancelToken: cancelToken, headers: headers);
    try {
      return PageResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
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
    final response = await _request(
      path,
      method: 'POST',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
    if (!(acceptedStatuses ?? {expectedStatus}).contains(response.statusCode)) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  Future<void> postEmpty(
    String path,
    Object body, {
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      path,
      method: 'POST',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
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
    final response = await _request(
      path,
      method: 'PATCH',
      data: body,
      contentType: 'application/json',
      cancelToken: cancelToken,
      headers: headers,
    );
    try {
      return SuccessResponse<T>.fromJson(response.data, decode);
    } on FormatException {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  /// Native transport semantics are explicit, never decoded as JSON envelopes.
  Future<void> deleteEmpty(String path, {CancelToken? cancelToken}) async {
    final response = await _request(path, method: 'DELETE', cancelToken: cancelToken);
    if (response.statusCode != 204 || (response.data != null && response.data != '')) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
  }

  Future<Uint8List> download(String path, {CancelToken? cancelToken}) async {
    final response = await _request(
      path,
      responseType: ResponseType.bytes,
      cancelToken: cancelToken,
    );
    final value = response.data;
    if (value is! List<int>) throw const ApiFailure(code: 'INVALID_RESPONSE');
    return Uint8List.fromList(value);
  }

  Future<void> uploadBytes(String path, Uint8List bytes, {CancelToken? cancelToken}) async {
    final response = await _request(
      path,
      method: 'PUT',
      data: bytes,
      contentType: 'application/octet-stream',
      cancelToken: cancelToken,
    );
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
    final watch = Stopwatch()..start();
    final observable = !uri.path.contains('/frontend-logs');
    final requestHeaders = <String, String>{...?headers};
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
          responseType: responseType,
          contentType: contentType,
          headers: requestHeaders,
        ),
      );
      observe?.call(true, response.statusCode, watch.elapsed, _serverRequestId(response));
      return response;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) throw const ApiFailure(code: 'CANCELLED');
      final response = error.response;
      observe?.call(false, response?.statusCode, watch.elapsed, _serverRequestId(response));
      if (response != null) {
        try {
          throw ApiFailure.fromJson(
            response.data,
            retryAfter: _retryAfter(response.headers.value('retry-after')),
          );
        } on FormatException {
          throw const ApiFailure(code: 'INVALID_RESPONSE');
        }
      }
      throw const ApiFailure(code: 'NETWORK_UNAVAILABLE');
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
