import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/request_ids.dart';
import '../api/responses.dart';
import '../api/telemetry_models.dart';
import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import 'telemetry_store.dart';

final telemetryProvider = Provider<Telemetry?>((ref) => null);

const _allowedAttributes = <String, Set<String>>{
  'app.started': {'duration_ms'},
  'screen.viewed': {'screen_name', 'duration_ms'},
  'app.crash.capture': {'error_category'},
  'auth.register.submitted': {},
  'auth.login.result': {'result', 'error_category', 'transport', 'duration_ms'},
  'auth.password.change.submitted': {},
  'auth.logout.requested': {},
  'auth.session.revoked': {'result'},
  'access.snapshot.updated': {'result'},
  'authz.denied': {'error_category'},
  'reading.chapter.opened': {'material_type', 'duration_ms'},
  'explanation.requested': {'target_kind', 'duration_ms'},
  'collection.saved': {'card_type', 'result', 'duration_ms'},
  'http.completed': {'status_code', 'duration_ms', 'retry_count'},
  'http.failed': {'status_code', 'duration_ms', 'retry_count', 'error_category'},
  'telemetry.delivery.recovered': {'dropped_count', 'drop_reason'},
  'cache.read.hit': {'source'},
  'cache.read.miss': {'source'},
  'cache.validation': {'result'},
  'cache.invalidated': {'result'},
  'cache.cleared': {'result'},
  'cache.storage.degraded': {'reason'},
  'cache.stale_response.discarded': {'result'},
  'cache.download': {'result'},
  'cache.evicted': {'result'},
  'schema.migration': {'result'},
  'connection.probed': {'result', 'duration_ms'},
  'account.scope.changed': {'reason', 'result'},
  'profile.updated': {},
  'study_profile.updated': {},
  'settings.updated': {},
  'profile.avatar.updated': {},
  'profile.avatar.deleted': {},
};
const _anonymousEvents = {
  'app.started',
  'app.crash.capture',
  'auth.register.submitted',
  'auth.login.result',
  'connection.probed',
  'account.scope.changed',
};
const _enumAttributes = <String, Set<String>>{
  'screen_name': {
    'welcome',
    'login',
    'register',
    'recovery',
    'verify_email',
    'reset_password',
    'account',
    'settings',
    'sessions',
    'materials',
    'chapter',
    'collection',
    'admin_policy',
  },
  'result': {
    'success',
    'failure',
    'cancelled',
    'denied',
    'hit',
    'miss',
    'same',
    'changed',
    'unavailable',
  },
  'source': {'network', 'memory', 'disk'},
  'reason': {
    'writer_unavailable',
    'browser_storage_unsafe',
    'quota_exceeded',
    'audio_unavailable',
    'invalid_payload',
    'instance_switch',
  },
  'error_category': {
    'authentication',
    'authorization',
    'conflict',
    'network',
    'timeout',
    'server',
    'validation',
    'flutter_framework',
    'dart_unhandled',
    'platform_channel',
    'other',
  },
  'transport': {'web', 'native'},
  'material_type': {'novel'},
  'target_kind': {'material_content'},
  'card_type': {'word'},
  'drop_reason': {
    'queue_full',
    'expired',
    'auth_scope_changed',
    'upload_failure',
    'invalid_event',
    'storage_unavailable',
  },
};

/// Keep only a symbol and numeric source position, never a path or source line.
List<String> safeStackFrames(StackTrace? stack) {
  if (stack == null) return const [];
  final frames = <String>[];
  for (final raw in stack.toString().split('\n').take(100)) {
    if (frames.length == 20) break;
    if (raw.length > 1024) continue;
    final line = raw.trim();
    final symbol = RegExp(r'^(?:#\d+\s+|at\s+)([^\(]+?)\s*\(').firstMatch(line)?.group(1);
    final location = RegExp(r':(\d+)(?::(\d+))?\)?$').firstMatch(line);
    if (symbol == null || location == null) continue;
    final cleaned = symbol.replaceAll(RegExp(r'[^A-Za-z0-9_.$]'), '_');
    final lineNumber = int.tryParse(location.group(1)!);
    final columnNumber = int.tryParse(location.group(2) ?? '');
    if (cleaned.isEmpty ||
        lineNumber == null ||
        lineNumber <= 0 ||
        lineNumber > 10000000 ||
        (columnNumber != null && (columnNumber <= 0 || columnNumber > 10000000))) {
      continue;
    }
    frames.add(
      '${cleaned.substring(0, min(cleaned.length, 64))}:$lineNumber'
      '${columnNumber == null ? '' : ':$columnNumber'}',
    );
  }
  return frames;
}

/// Bounded, identity-partitioned client telemetry. Values are from a strict
/// dictionary; no exception message, URL, source text, token or stack is kept.
final class Telemetry {
  Telemetry(this.config, this.api, this.auth, {TelemetryStore? store, DateTime Function()? now})
    : _store = store ?? TelemetryStore(config.instanceId),
      _now = now ?? DateTime.now {
    auth.addListener(_identityChanged);
    _identityChanged();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(flush()));
  }

  final AppConfig config;
  final ApiClient api;
  final AuthController auth;
  final TelemetryStore _store;
  final DateTime Function() _now;
  late final Timer _timer;
  Future<void> _tail = Future<void>.value();
  String? _scope;
  String? _pendingScope;
  String _anonymousGeneration = newRequestId();
  bool _previousAuthenticated = false;
  int _scopeEpoch = 0;
  String _clientSessionId = newRequestId();
  List<Map<String, Object?>> _events = [];
  int _residentBytes = 0;
  int _dropped = 0;
  String _dropReason = 'queue_full';
  int _backoffSeconds = 1;
  int _batchLimit = 20;
  DateTime? _retryAt;
  bool _uploading = false;
  bool _disposed = false;
  bool _storageUnavailable = false;
  int _pendingAdds = 0;
  int _pendingBytes = 0;

  int get queuedCount => _events.length;
  int get bufferedCount => _events.length + _pendingAdds;
  int get bufferedBytes => _residentBytes + _pendingBytes;

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
  static final _safeFrame = RegExp(r'^[A-Za-z0-9_.$]{1,64}:[1-9][0-9]{0,7}(?::[1-9][0-9]{0,7})?$');

  bool _validStoredEvent(Map<String, Object?> event, {required bool anonymous}) {
    if (event.keys.any(
          (key) => !const {
            'schema_version',
            'event_id',
            'record_type',
            'event',
            'level',
            'occurred_at',
            'client_platform',
            'release',
            'build',
            'operation_id',
            'request_id',
            'client_request_id',
            'attributes',
            'safe_stack_frames',
          }.contains(key),
        ) ||
        event['schema_version'] != 1 ||
        event['event_id'] is! String ||
        !_uuid.hasMatch(event['event_id']! as String) ||
        event['event'] is! String ||
        !_allowedAttributes.containsKey(event['event']) ||
        (anonymous && !_anonymousEvents.contains(event['event'])) ||
        !const {'log', 'analytics', 'performance', 'crash'}.contains(event['record_type']) ||
        !const {'debug', 'info', 'warn', 'error', 'fatal'}.contains(event['level']) ||
        event['client_platform'] != config.platform.name ||
        event['release'] is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(event['release']! as String) ||
        event['build'] is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(event['build']! as String)) {
      return false;
    }
    final stamp = DateTime.tryParse(
      event['occurred_at'] is String ? event['occurred_at']! as String : '',
    );
    final now = _now().toUtc();
    if (stamp == null ||
        stamp.isBefore(now.subtract(const Duration(hours: 24))) ||
        stamp.isAfter(now.add(const Duration(minutes: 5)))) {
      return false;
    }
    for (final key in const ['operation_id', 'request_id', 'client_request_id']) {
      final id = event[key];
      if (id != null && (id is! String || !_uuid.hasMatch(id))) return false;
    }
    final attributes = event['attributes'];
    if (attributes != null &&
        (attributes is! Map<String, Object?> ||
            !_validAttributes(event['event']! as String, attributes))) {
      return false;
    }
    final frames = event['safe_stack_frames'];
    if (frames != null &&
        (event['record_type'] != 'crash' ||
            frames is! List ||
            frames.length > 20 ||
            frames.any((frame) => frame is! String || !_safeFrame.hasMatch(frame)))) {
      return false;
    }
    return utf8.encode(jsonEncode(event)).length <= 16 * 1024;
  }

  String _desiredScope() {
    final access = auth.access;
    if (!auth.isAuthenticated || access == null) {
      return '${config.instanceId}:anonymous:$_anonymousGeneration';
    }
    return [
      config.instanceId,
      access.userId,
      access.audience,
      access.sessionRef,
      access.authzVersion.user,
      access.authzVersion.policy,
    ].join(':');
  }

  void _identityChanged() {
    if (_disposed) return;
    final authenticated = auth.isAuthenticated;
    if (_previousAuthenticated && !authenticated) {
      // A closed authenticated scope cannot be reused. Anonymous events are
      // best effort within one lifecycle and are never attributed after a
      // restart to a different unauthenticated visitor.
      _anonymousGeneration = newRequestId();
    }
    _previousAuthenticated = authenticated;
    final next = _desiredScope();
    if (_pendingScope != next) {
      _pendingScope = next;
      ++_scopeEpoch;
    }
    unawaited(
      _serialize(() async {
        if (_scope == next) return;
        final old = _scope;
        if (old != null) {
          // An old identity's delivery diagnostics must never enter a new
          // identity's queue after sign-out or account switch.
          _dropped = 0;
          _dropReason = 'queue_full';
          _events = [];
          _residentBytes = 0;
          _storageUnavailable = false;
          try {
            await _store.clear(old);
          } on Object {
            /* memory fallback */
          }
        }
        _scope = next;
        try {
          final saved = await _store.read(next);
          _events = [];
          _residentBytes = 0;
          var bytes = 0;
          for (final item in (saved?.events ?? const <Map<String, Object?>>[]).take(5000)) {
            if (!_validStoredEvent(
              item,
              anonymous: next.startsWith('${config.instanceId}:anonymous:'),
            )) {
              _dropped++;
              _dropReason = 'invalid_event';
              continue;
            }
            final size = utf8.encode(jsonEncode(item)).length;
            if (bytes + size > 10 * 1024 * 1024) break;
            bytes += size;
            _events.add(item);
            _residentBytes += size;
          }
          _clientSessionId = saved != null && _uuid.hasMatch(saved.clientSessionId)
              ? saved.clientSessionId
              : newRequestId();
          if (!next.startsWith('${config.instanceId}:anonymous:')) {
            track('access.snapshot.updated', attributes: {'result': 'success'});
          }
        } on Object {
          _events = [];
          _residentBytes = 0;
          _clientSessionId = newRequestId();
          _storageUnavailable = true;
          _dropReason = 'storage_unavailable';
        }
      }),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  bool _validAttributes(String event, Map<String, Object?> attributes) {
    final allowed = _allowedAttributes[event];
    if (allowed == null || attributes.keys.any((key) => !allowed.contains(key))) return false;
    for (final entry in attributes.entries) {
      final possible = _enumAttributes[entry.key];
      if (possible != null && (entry.value is! String || !possible.contains(entry.value))) {
        return false;
      }
      if (entry.key == 'duration_ms' &&
          (entry.value is! num || (entry.value as num) < 0 || (entry.value as num) > 86400000)) {
        return false;
      }
      if (entry.key == 'status_code' &&
          (entry.value is! int || (entry.value as int) < 100 || (entry.value as int) > 599)) {
        return false;
      }
      if (const {'retry_count', 'dropped_count'}.contains(entry.key) &&
          (entry.value is! int ||
              (entry.value as int) < 0 ||
              (entry.value as int) > (entry.key == 'retry_count' ? 100 : 5000))) {
        return false;
      }
    }
    return true;
  }

  void track(
    String event, {
    Map<String, Object?> attributes = const {},
    String recordType = 'analytics',
    String level = 'info',
    String? operationId,
    String? requestId,
    String? clientRequestId,
    int? expectedScopeEpoch,
    List<String> safeFrames = const [],
  }) {
    if (_disposed ||
        !_validAttributes(event, attributes) ||
        !const {'log', 'analytics', 'performance', 'crash'}.contains(recordType) ||
        !const {'debug', 'info', 'warn', 'error', 'fatal'}.contains(level) ||
        safeFrames.length > 20 ||
        (recordType != 'crash' && safeFrames.isNotEmpty) ||
        safeFrames.any((frame) => !_safeFrame.hasMatch(frame))) {
      return;
    }
    final anonymous = !auth.isAuthenticated;
    if (anonymous && !_anonymousEvents.contains(event)) return;
    final expectedScope = _desiredScope();
    final expectedEpoch = expectedScopeEpoch ?? _scopeEpoch;
    final entry = <String, Object?>{
      'schema_version': 1,
      'event_id': newRequestId(),
      'record_type': recordType,
      'event': event,
      'level': level,
      'occurred_at': _now().toUtc().toIso8601String(),
      'client_platform': config.platform.name,
      'release': const String.fromEnvironment('HARUKA_RELEASE', defaultValue: '0.1.0'),
      'build': const String.fromEnvironment('HARUKA_BUILD', defaultValue: '1'),
      'operation_id': ?operationId,
      'request_id': ?requestId,
      'client_request_id': ?clientRequestId,
      if (recordType == 'crash' && safeFrames.isNotEmpty) 'safe_stack_frames': safeFrames,
      if (attributes.isNotEmpty) 'attributes': Map<String, Object?>.from(attributes),
    };
    final entryBytes = utf8.encode(jsonEncode(entry)).length;
    if (entryBytes > 16 * 1024 ||
        _events.length + _pendingAdds >= 5000 ||
        _residentBytes + _pendingBytes + entryBytes >= 10 * 1024 * 1024) {
      _dropped++;
      _dropReason = 'queue_full';
      return;
    }
    _pendingAdds++;
    _pendingBytes += entryBytes;
    unawaited(
      _serialize(() async {
        try {
          if (_disposed ||
              _scope != expectedScope ||
              _desiredScope() != expectedScope ||
              _scopeEpoch != expectedEpoch) {
            return;
          }
          _events.add(entry);
          _residentBytes += entryBytes;
          final expiry = _now().toUtc().subtract(const Duration(hours: 24));
          final before = _events.length;
          _events.removeWhere((item) {
            final stamp = DateTime.tryParse(item['occurred_at'] as String? ?? '');
            final expired = stamp == null || stamp.isBefore(expiry);
            if (expired) _residentBytes -= utf8.encode(jsonEncode(item)).length;
            return expired;
          });
          if (_events.length != before) {
            _dropped += before - _events.length;
            _dropReason = 'expired';
          }
          while (_events.length > 5000 || _residentBytes > 10 * 1024 * 1024) {
            _residentBytes -= utf8.encode(jsonEncode(_events.removeAt(0))).length;
            _dropped++;
            _dropReason = 'queue_full';
          }
          await _persist();
          if (_events.length >= (anonymous ? 5 : 20)) {
            Timer.run(() => unawaited(flush()));
          }
        } finally {
          _pendingAdds--;
          _pendingBytes -= entryBytes;
        }
      }),
    );
  }

  void log(
    String event, {
    Map<String, Object?> attributes = const {},
    String level = 'info',
    String? operationId,
    String? requestId,
    String? clientRequestId,
    int? expectedScopeEpoch,
  }) => track(
    event,
    attributes: attributes,
    recordType: 'log',
    level: level,
    operationId: operationId,
    requestId: requestId,
    clientRequestId: clientRequestId,
    expectedScopeEpoch: expectedScopeEpoch,
  );

  RequestObservation? beginHttpObservation(String operationId, String clientRequestId) {
    final capturedScope = _desiredScope();
    final capturedEpoch = _scopeEpoch;
    return (success, status, elapsed, requestId) {
      if (_disposed || _desiredScope() != capturedScope || _scopeEpoch != capturedEpoch) return;
      log(
        success ? 'http.completed' : 'http.failed',
        level: success ? 'info' : 'warn',
        operationId: operationId,
        clientRequestId: clientRequestId,
        requestId: requestId,
        expectedScopeEpoch: capturedEpoch,
        attributes: {
          'status_code': ?status,
          'duration_ms': elapsed.inMilliseconds,
          'retry_count': 0,
          if (!success)
            'error_category': status == null
                ? 'network'
                : status >= 500
                ? 'server'
                : status == 401
                ? 'authentication'
                : status == 403
                ? 'authorization'
                : status == 409
                ? 'conflict'
                : 'validation',
        },
      );
      if (status == 403) {
        track(
          'authz.denied',
          attributes: {'error_category': 'authorization'},
          recordType: 'log',
          level: 'warn',
          expectedScopeEpoch: capturedEpoch,
        );
      }
    };
  }

  void recordTiming(
    String event,
    Duration duration, {
    Map<String, Object?> attributes = const {},
  }) => track(
    event,
    attributes: {...attributes, 'duration_ms': duration.inMilliseconds},
    recordType: 'performance',
  );

  void captureException({required String category, StackTrace? stack}) => track(
    'app.crash.capture',
    attributes: {'error_category': category},
    recordType: 'crash',
    level: 'error',
    safeFrames: safeStackFrames(stack),
  );

  Future<void> _persist() async {
    final scope = _scope;
    if (scope == null) return;
    try {
      await _store.write(
        scope,
        TelemetrySnapshot(
          clientSessionId: _clientSessionId,
          events: List<Map<String, Object?>>.from(_events),
        ),
      );
      if (_storageUnavailable) {
        _storageUnavailable = false;
        if (auth.isAuthenticated) {
          track(
            'telemetry.delivery.recovered',
            attributes: {'dropped_count': 0, 'drop_reason': 'storage_unavailable'},
            recordType: 'log',
          );
        }
      }
    } on Object {
      _storageUnavailable = true;
      _dropReason = 'storage_unavailable';
    }
  }

  Future<void> flush() async {
    if (_disposed || _uploading || (_retryAt != null && _now().isBefore(_retryAt!))) return;
    _uploading = true;
    String? requestScope;
    int? requestEpoch;
    var sentCount = 0;
    String? singleEventId;
    var drainMore = false;
    try {
      await _tail;
      if (_events.isEmpty) return;
      final scope = _scope;
      if (scope == null || scope != _desiredScope()) return;
      requestScope = scope;
      requestEpoch = _scopeEpoch;
      final anonymous = !auth.isAuthenticated;
      final audience = auth.access?.audience;
      final max = min(_batchLimit, anonymous ? 5 : 20);
      final maxBytes = anonymous ? 16 * 1024 : 128 * 1024;
      final batch = <Map<String, Object?>>[];
      for (final event in _events.take(max)) {
        final candidate = [...batch, event];
        final encoded = utf8.encode(
          jsonEncode({
            'schema_version': 1,
            'client_session_id': _clientSessionId,
            'events': candidate,
          }),
        );
        if (encoded.length > maxBytes) break;
        batch.add(event);
      }
      if (batch.isEmpty) {
        await _serialize(() async {
          if (requestScope != _scope || requestEpoch != _scopeEpoch) return;
          _residentBytes -= utf8.encode(jsonEncode(_events.removeAt(0))).length;
          _dropped++;
          _dropReason = 'invalid_event';
          await _persist();
        });
        return;
      }
      sentCount = batch.length;
      if (sentCount == 1) singleEventId = batch.first['event_id'] as String?;
      final payload = {'schema_version': 1, 'client_session_id': _clientSessionId, 'events': batch};
      final path = anonymous
          ? '/api/v1/frontend-logs/anonymous'
          : audience == 'admin'
          ? '/api/v1/admin/frontend-logs'
          : '/api/v1/frontend-logs';
      final response = anonymous
          ? await api.postJson(path, payload, TelemetryBatchRead.fromJson)
          : await auth.authorizedWrite(
              (headers) =>
                  api.postJson(path, payload, TelemetryBatchRead.fromJson, headers: headers),
            );
      await _serialize(() async {
        if (scope != _scope ||
            scope != _desiredScope() ||
            requestEpoch != _scopeEpoch ||
            _disposed) {
          return;
        }
        final acknowledged = <String>{};
        for (final item in response.data.results) {
          if (item.index >= batch.length ||
              (item.eventId != null && item.eventId != batch[item.index]['event_id'])) {
            continue;
          }
          acknowledged.add(batch[item.index]['event_id']! as String);
          if (item.status == 'rejected') {
            _dropped++;
            _dropReason = 'invalid_event';
          }
        }
        if (acknowledged.isEmpty) {
          _scheduleRetry();
          return;
        }
        _events.removeWhere((item) {
          final accepted = acknowledged.contains(item['event_id']);
          if (accepted) _residentBytes -= utf8.encode(jsonEncode(item)).length;
          return accepted;
        });
        await _persist();
        _backoffSeconds = 1;
        _batchLimit = 20;
        _retryAt = null;
        drainMore = _events.isNotEmpty;
        if (_dropped > 0 && !anonymous) {
          final count = _dropped.clamp(0, 5000);
          final reason = _dropReason;
          _dropped = 0;
          track(
            'telemetry.delivery.recovered',
            attributes: {'dropped_count': count, 'drop_reason': reason},
            recordType: 'log',
          );
        }
      });
    } on ApiFailure catch (error) {
      await _serialize(() async {
        if (requestScope != _scope ||
            requestScope != _desiredScope() ||
            requestEpoch != _scopeEpoch ||
            _disposed) {
          return;
        }
        if (error.code == 'PAYLOAD_TOO_LARGE' || error.code == 'INPUT_INVALID') {
          if (sentCount > 1) {
            _batchLimit = (sentCount ~/ 2).clamp(1, 20);
          } else if (singleEventId != null) {
            final before = _events.length;
            _events.removeWhere((item) {
              final rejected = item['event_id'] == singleEventId;
              if (rejected) _residentBytes -= utf8.encode(jsonEncode(item)).length;
              return rejected;
            });
            if (_events.length != before) {
              _dropped++;
              _dropReason = 'invalid_event';
              await _persist();
            }
          }
        }
        _scheduleRetry(error.retryAfter);
      });
    } on Object {
      await _serialize(() async {
        if (requestScope != _scope ||
            requestScope != _desiredScope() ||
            requestEpoch != _scopeEpoch ||
            _disposed) {
          return;
        }
        _scheduleRetry();
      });
    } finally {
      _uploading = false;
      if (drainMore && !_disposed) Timer.run(() => unawaited(flush()));
    }
  }

  void _scheduleRetry([Duration? serverDelay]) {
    final delay =
        serverDelay ??
        Duration(milliseconds: _backoffSeconds * 1000 + Random.secure().nextInt(500));
    _retryAt = _now().add(delay);
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 60);
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer.cancel();
    auth.removeListener(_identityChanged);
    await _tail;
  }
}
