import 'dart:math';

import 'package:dio/dio.dart';

import '../api/responses.dart';

/// Only idempotent reads use this budget. Domain writes/generation never do.
Duration? cacheReadRetryDelay(Object error, int retries) {
  if (retries >= 2) return null;
  int? status;
  Duration? retryAfter;
  var transientTransport = false;
  if (error is ApiFailure) {
    if (const {
      'INVALID_RESPONSE',
      'CANCELLED',
      'SESSION_INVALID',
      'AUTH_SCOPE_CHANGED',
    }.contains(error.code)) {
      return null;
    }
    status = error.statusCode;
    transientTransport = error.retryableTransport;
    retryAfter = error.retryAfter;
  } else if (error is DioException) {
    status = error.response?.statusCode;
    transientTransport = const {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    }.contains(error.type);
    final seconds = int.tryParse(error.response?.headers.value('retry-after') ?? '');
    if (seconds != null) retryAfter = Duration(seconds: seconds);
  }
  if (!transientTransport && status != 429 && !(status != null && status >= 500 && status <= 599)) {
    return null;
  }
  final backoff = Duration(milliseconds: (retries == 0 ? 500 : 1500) + Random().nextInt(101));
  // A long Retry-After is surfaced for explicit retry, never retried too early.
  if (retryAfter != null && retryAfter > const Duration(seconds: 30)) return null;
  return retryAfter != null && retryAfter > backoff ? retryAfter : backoff;
}

/// Retain an already displayed same-scope read on an uncertain transport
/// failure. Definite authorization or resource refusals never qualify.
bool cacheReadMayKeepSnapshot(Object error) {
  int? status;
  var transient = false;
  if (error is ApiFailure) {
    status = error.statusCode;
    transient = error.retryableTransport;
  } else if (error is DioException) {
    status = error.response?.statusCode;
    transient = const {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    }.contains(error.type);
  }
  if (status == 401 || status == 403) return false;
  return transient || status == 429 || (status != null && status >= 500 && status <= 599);
}
