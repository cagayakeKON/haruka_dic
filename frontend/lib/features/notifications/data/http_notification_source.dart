import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/api/responses.dart';
import '../../../core/api/wire.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../domain/notification_record.dart';
import 'notification_repository.dart';

/// Persistent owner notifications are projected by the server. This adapter
/// never resolves a job, arbitrary route, private title or object URL.
final class HttpNotificationSource implements CacheRemote<NotificationListSnapshot> {
  HttpNotificationSource(this.auth, {this.onEvent});
  final AuthController auth;
  final void Function(String, Map<String, Object>)? onEvent;
  String? _preparedKey;
  CachePayload<NotificationListSnapshot>? _prepared;
  Object? _preparedBinding;

  bool allows(String action) => auth.isAuthenticated && (auth.access?.allows(action) ?? false);
  void _require({bool write = false}) {
    if (!allows('client.notification.read') || (write && !allows('client.notification.update'))) {
      throw const ApiFailure(code: 'PERMISSION_DENIED');
    }
  }

  Future<T> _observe<T>(String event, Future<T> Function() action) async {
    try {
      final result = await action();
      onEvent?.call(event, {'result': 'success'});
      return result;
    } on Object catch (error) {
      onEvent?.call(event, {
        'result': error is ApiFailure && error.code == 'PERMISSION_DENIED' ? 'denied' : 'failure',
      });
      rethrow;
    }
  }

  Future<CachePayload<NotificationListSnapshot>> _load(
    CacheResource resource,
    CancelToken cancel,
  ) => _observe('notification.list.loaded', () async {
    _require();
    if (resource.action != 'client.notification.read') throw const CacheBlocked('forbidden');
    final query = NotificationListQuery.fromKey(resource.queryKey);
    if (query.cursor.length > 2048) throw const FormatException('Invalid notification cursor');
    final params = Uri(
      queryParameters: {
        'unread_only': '${query.unreadOnly}',
        'limit': '50',
        if (query.cursor.isNotEmpty) 'cursor': query.cursor,
      },
    ).query;
    final page = await auth.authorizedRead(
      (headers) => auth.repository.api.getPage(
        '/api/v1/notifications?$params',
        NotificationRecord.fromApiJson,
        headers: headers,
        cancelToken: cancel,
      ),
    );
    final snapshot = NotificationListSnapshot.fromApiPage(page);
    final digest = sha256.convert(utf8.encode(jsonEncode(snapshot.toJson()))).toString();
    return CachePayload(
      value: snapshot,
      version: CacheVersion(
        resource: digest,
        representation: 'notification-summary-v1',
        artifact: digest,
      ),
    );
  });

  @override
  Future<CachePayload<NotificationListSnapshot>> fetch(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    _require();
    final prepared = _prepared;
    if (_preparedKey == resource.queryKey &&
        prepared != null &&
        identical(_preparedBinding, auth.repository.api.sessionBinding) &&
        !cancel.isCancelled) {
      _prepared = null;
      return prepared;
    }
    _prepared = null;
    return _load(resource, cancel);
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    _prepared = null;
    final binding = auth.repository.api.sessionBinding;
    final payload = await _load(resource, cancel);
    if (!identical(binding, auth.repository.api.sessionBinding)) {
      throw const CacheBlocked('scope_changed');
    }
    final same = payload.version.resource == known.resource;
    if (!same) {
      _preparedKey = resource.queryKey;
      _preparedBinding = binding;
      _prepared = payload;
    }
    return CacheValidation(
      state: same ? ValidationState.same : ValidationState.changed,
      version: payload.version,
    );
  }

  Future<void> markRead(String id) => _observe('notification.read.updated', () async {
    _require(write: true);
    final row = await auth.authorizedWrite(
      (headers) async => (await auth.repository.api.postJson(
        '/api/v1/notifications/${wireUuid(id)}/read',
        const <String, Object?>{},
        NotificationRecord.fromApiJson,
        headers: headers,
      )).data,
    );
    if (row.id != id || row.readAt == null) throw const ApiFailure(code: 'INVALID_RESPONSE');
    _prepared = null;
  });

  Future<void> markAllRead(String token) => _observe('notification.read_all.updated', () async {
    _require(write: true);
    if (token.isEmpty || token.length > 2048) {
      throw const FormatException('Invalid notification snapshot');
    }
    await auth.authorizedWrite(
      (headers) => auth.repository.api.postJson(
        '/api/v1/notifications/read-all',
        {'snapshot_token': token},
        NotificationReadAllResult.fromJson,
        headers: headers,
      ),
    );
    _prepared = null;
  });
}
