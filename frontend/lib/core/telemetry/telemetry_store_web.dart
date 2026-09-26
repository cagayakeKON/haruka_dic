import 'dart:convert';

import 'package:web/web.dart' as web;

import 'telemetry_store.dart';

/// Per-event localStorage entries avoid replacing another tab's whole queue.
/// A durable closed marker prevents a delayed old-account write from reviving it.
final class PlatformTelemetryStore implements TelemetryStore {
  PlatformTelemetryStore(this._instanceId);

  final String _instanceId;
  final _known = <String, Map<String, DateTime>>{};
  static DateTime? _lastOldScopeSweep;
  static final _scopePrefix = RegExp(r'^haruka\.telemetry\.[0-9a-f]{32}\.$');
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
  static const _maxEvents = 5000;
  static const _maxBytes = 10 * 1024 * 1024;
  static const _maxEventBytes = 16 * 1024;
  static const _retention = Duration(hours: 24);

  String _prefix(String scope) => 'haruka.telemetry.${telemetryScopeKey('$_instanceId:$scope')}.';

  void _pruneKnown(Map<String, DateTime> known, Set<String> current) {
    final cutoff = DateTime.now().toUtc().subtract(_retention);
    known.removeWhere((id, seen) => !current.contains(id) && seen.isBefore(cutoff));
    if (known.length <= _maxEvents) return;
    final removable = known.entries.where((entry) => !current.contains(entry.key)).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in removable) {
      if (known.length <= _maxEvents) break;
      known.remove(entry.key);
    }
  }

  void _collectOldScopes(web.Storage storage) {
    final now = DateTime.now().toUtc();
    if (_lastOldScopeSweep != null &&
        now.difference(_lastOldScopeSweep!) < const Duration(hours: 1)) {
      return;
    }
    final prefixes = <String>{};
    for (var index = 0; index < storage.length; index++) {
      final key = storage.key(index);
      if (key == null || !key.startsWith('haruka.telemetry.')) continue;
      final suffix = key.lastIndexOf('.');
      if (suffix < 0) continue;
      final prefix = key.substring(0, suffix + 1);
      if (_scopePrefix.hasMatch(prefix)) prefixes.add(prefix);
    }
    for (final prefix in prefixes) {
      _sweep(storage, prefix);
    }
    _lastOldScopeSweep = now;
  }

  List<String> _keys(web.Storage storage, String prefix) {
    final keys = <String>[];
    for (var index = 0; index < storage.length; index++) {
      final key = storage.key(index);
      if (key != null && key.startsWith(prefix) && _uuid.hasMatch(key.substring(prefix.length))) {
        keys.add(key);
      }
    }
    return keys;
  }

  DateTime? _recordTime(Map<String, dynamic> document) {
    final event = document['event'];
    final stamp = event is Map<String, dynamic> && event['occurred_at'] is String
        ? event['occurred_at'] as String
        : document['stored_at'] is String
        ? document['stored_at'] as String
        : null;
    return stamp == null ? null : DateTime.tryParse(stamp)?.toUtc();
  }

  List<
    ({String key, String id, String session, Map<String, Object?> event, int bytes, DateTime at})
  >
  _sweep(web.Storage storage, String prefix) {
    final now = DateTime.now().toUtc();
    final records =
        <
          ({
            String key,
            String id,
            String session,
            Map<String, Object?> event,
            int bytes,
            DateTime at,
          })
        >[];
    for (final key in _keys(storage, prefix)) {
      final raw = storage.getItem(key);
      Map<String, dynamic>? document;
      final size = raw == null ? 0 : utf8.encode(raw).length;
      if (raw != null && size > 0 && size <= _maxEventBytes) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) document = decoded;
        } on FormatException {
          // Remove malformed records, never send their contents.
        }
      }
      final eventValue = document?['event'];
      Map<String, Object?>? event;
      if (eventValue is Map<String, dynamic>) {
        try {
          event = Map<String, Object?>.from(eventValue);
        } on TypeError {
          // Remove malformed records below.
        }
      }
      final session = document?['client_session_id'];
      final id = event?['event_id'];
      final at = document == null ? null : _recordTime(document);
      if (session is! String ||
          !_uuid.hasMatch(session) ||
          id is! String ||
          !_uuid.hasMatch(id) ||
          key != '$prefix$id' ||
          at == null ||
          at.isBefore(now.subtract(_retention)) ||
          at.isAfter(now.add(const Duration(minutes: 5)))) {
        storage.removeItem(key);
        continue;
      }
      records.add((key: key, id: id, session: session, event: event!, bytes: size, at: at));
    }
    records.sort((a, b) {
      final order = a.at.compareTo(b.at);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    var bytes = records.fold<int>(0, (sum, item) => sum + item.bytes);
    while (records.length > _maxEvents || bytes > _maxBytes) {
      final oldest = records.removeAt(0);
      bytes -= oldest.bytes;
      storage.removeItem(oldest.key);
    }
    return records;
  }

  @override
  Future<TelemetrySnapshot?> read(String scope) async {
    final storage = web.window.localStorage;
    _collectOldScopes(storage);
    final prefix = _prefix(scope);
    if (storage.getItem('${prefix}closed') != null) return null;
    final records = _sweep(storage, prefix);
    if (storage.getItem('${prefix}closed') != null) return null;
    final known = _known.putIfAbsent(scope, () => <String, DateTime>{});
    final now = DateTime.now().toUtc();
    for (final record in records) {
      known[record.id] = now;
    }
    _pruneKnown(known, records.map((record) => record.id).toSet());
    if (records.isEmpty) return null;
    final session = records.first.session;
    return TelemetrySnapshot(
      clientSessionId: session,
      events: records.map((record) => record.event).toList(),
    );
  }

  @override
  Future<void> write(String scope, TelemetrySnapshot snapshot) async {
    if (!_uuid.hasMatch(snapshot.clientSessionId) || snapshot.events.length > _maxEvents) {
      throw const FormatException('Invalid telemetry snapshot');
    }
    final storage = web.window.localStorage;
    _collectOldScopes(storage);
    final prefix = _prefix(scope);
    final closed = '${prefix}closed';
    if (storage.getItem(closed) != null) throw StateError('Telemetry scope is closed');
    _sweep(storage, prefix);
    final known = _known.putIfAbsent(scope, () => <String, DateTime>{});
    final current = <String>{};
    for (final event in snapshot.events) {
      final id = event['event_id'];
      if (id is! String || !_uuid.hasMatch(id) || !current.add(id)) {
        throw const FormatException('Invalid telemetry event identity');
      }
      if (known.containsKey(id)) continue;
      final key = '$prefix$id';
      if (storage.getItem(closed) != null) throw StateError('Telemetry scope is closed');
      if (storage.getItem(key) == null) {
        final raw = jsonEncode({
          'stored_at': DateTime.now().toUtc().toIso8601String(),
          'client_session_id': snapshot.clientSessionId,
          'event': event,
        });
        if (utf8.encode(raw).length > _maxEventBytes) {
          throw const FormatException('Telemetry event exceeds storage limit');
        }
        storage.setItem(key, raw);
        if (storage.getItem(closed) != null) {
          storage.removeItem(key);
          throw StateError('Telemetry scope is closed');
        }
        if (storage.getItem(key) != raw) throw StateError('Telemetry write was not retained');
      }
      known[id] = DateTime.now().toUtc();
    }
    for (final id in known.keys.where((id) => !current.contains(id)).toList()) {
      storage.removeItem('$prefix$id');
    }
    _pruneKnown(known, current);
    final retained = _sweep(storage, prefix);
    if (!retained.map((record) => record.id).toSet().containsAll(current)) {
      throw StateError('Telemetry storage capacity was reached');
    }
    if (storage.getItem(closed) != null) throw StateError('Telemetry scope is closed');
  }

  @override
  Future<void> clear(String scope) async {
    final storage = web.window.localStorage;
    final prefix = _prefix(scope);
    storage.setItem('${prefix}closed', DateTime.now().toUtc().toIso8601String());
    for (final key in _keys(storage, prefix)) {
      storage.removeItem(key);
    }
    _known.remove(scope);
  }
}
