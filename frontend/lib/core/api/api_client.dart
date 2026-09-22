import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'responses.dart';

/// Owns one transport per app instance. Account-scoped authentication is B1.
final class ApiClient {
  ApiClient(AppConfig config, {HttpClientAdapter? adapter})
    : _dio = Dio(
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

  Future<SuccessResponse<HealthRead>> checkReadiness({CancelToken? cancelToken}) =>
      getJson('/health/ready', HealthRead.fromJson, cancelToken: cancelToken);

  Future<SuccessResponse<T>> getJson<T>(
    String path,
    T Function(Object?) decode, {
    CancelToken? cancelToken,
  }) async {
    final response = await _request(path, cancelToken: cancelToken);
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
  }) async {
    final uri = Uri.tryParse(path);
    if (uri == null || uri.hasAuthority || uri.hasScheme || !path.startsWith('/')) {
      throw const ApiFailure(code: 'INVALID_REQUEST');
    }
    try {
      return await _dio.request<Object?>(
        path,
        data: data,
        cancelToken: cancelToken,
        options: Options(method: method, responseType: responseType, contentType: contentType),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) throw const ApiFailure(code: 'CANCELLED');
      final response = error.response;
      if (response != null) {
        try {
          throw ApiFailure.fromJson(response.data);
        } on FormatException {
          throw const ApiFailure(code: 'INVALID_RESPONSE');
        }
      }
      throw const ApiFailure(code: 'NETWORK_UNAVAILABLE');
    }
  }

  void close() => _dio.close(force: true);
}
