import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../api/request_ids.dart';
import 'telemetry_store.dart';

/// Immutable event files share a process-wide lock and a durable scope closure.
final class PlatformTelemetryStore implements TelemetryStore {
  PlatformTelemetryStore(this._instanceId);

  final String _instanceId;
  final _known = <String, Map<String, DateTime>>{};
  // The application writes telemetry on its main isolate. POSIX file locks are
  // process-wide, so serialize store objects in that isolate before taking the
  // cross-process lock. A separate telemetry-writing isolate is unsupported.
  static final _isolateTails = <String, Future<void>>{};
  static Future<void>? _oldScopeSweep;
  static DateTime? _lastOldScopeSweep;
  static String? _lastOldScopeSweepRoot;
  static final _scopeName = RegExp(r'^[0-9a-f]{32}$');
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
  static final _eventName = RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\.json$');
  static const _maxEvents = 5000;
  static const _maxBytes = 10 * 1024 * 1024;
  static const _maxEventBytes = 16 * 1024;
  static const _retention = Duration(hours: 24);

  Future<Directory> _directory(String scope) async {
    final support = await getApplicationSupportDirectory();
    final parent = Directory('${support.path}${Platform.pathSeparator}haruka-telemetry');
    await _collectOldScopes(parent);
    return Directory(
      '${parent.path}'
      '${Platform.pathSeparator}${telemetryScopeKey('$_instanceId:$scope')}',
    );
  }

  Future<void> _collectOldScopes(Directory parent) async {
    final current = DateTime.now().toUtc();
    if (_lastOldScopeSweepRoot == parent.absolute.path &&
        _lastOldScopeSweep != null &&
        current.difference(_lastOldScopeSweep!) < const Duration(hours: 1)) {
      return;
    }
    final pending = _oldScopeSweep;
    if (pending != null) return pending;
    final sweep = () async {
      if (!await parent.exists()) return;
      await for (final entry in parent.list(followLinks: false)) {
        if (entry is! Directory ||
            !_scopeName.hasMatch(entry.path.split(Platform.pathSeparator).last)) {
          continue;
        }
        await _locked(entry, () async {
          await _sweep(entry);
        });
      }
    }();
    _oldScopeSweep = sweep;
    try {
      await sweep;
      _lastOldScopeSweep = current;
      _lastOldScopeSweepRoot = parent.absolute.path;
    } finally {
      _oldScopeSweep = null;
    }
  }

  File _file(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

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

  Future<T> _locked<T>(Directory directory, Future<T> Function() action) async {
    final key = directory.absolute.path;
    final previous = _isolateTails[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _isolateTails[key] = gate.future;
    await previous;
    try {
      await directory.create(recursive: true);
      final handle = await _file(directory, '.lock').open(mode: FileMode.append);
      var locked = false;
      try {
        final wait = Stopwatch()..start();
        while (true) {
          try {
            await handle.lock(FileLock.exclusive);
            break;
          } on FileSystemException catch (error) {
            // Windows reports a contended byte-range lock immediately.
            if (error.osError?.errorCode != 33 || wait.elapsed >= const Duration(seconds: 3)) {
              rethrow;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
        locked = true;
        return await action();
      } finally {
        if (locked) await handle.unlock();
        await handle.close();
      }
    } finally {
      gate.complete();
      if (identical(_isolateTails[key], gate.future)) {
        unawaited(_isolateTails.remove(key)!);
      }
    }
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

  Future<List<({String id, String session, Map<String, Object?> event, int bytes, DateTime at})>>
  _sweep(Directory directory) async {
    final now = DateTime.now().toUtc();
    final retained =
        <({String id, String session, Map<String, Object?> event, int bytes, DateTime at})>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        await entry.delete();
        continue;
      }
      if (!_eventName.hasMatch(name)) continue;
      final size = await entry.length();
      Map<String, dynamic>? document;
      if (size > 0 && size <= _maxEventBytes) {
        try {
          final decoded = jsonDecode(await entry.readAsString());
          if (decoded is Map<String, dynamic>) document = decoded;
        } on FormatException {
          // Damaged records never enter an upload batch.
        }
      }
      final eventValue = document?['event'];
      final session = document?['client_session_id'];
      final at = document == null ? null : _recordTime(document);
      Map<String, Object?>? event;
      if (eventValue is Map<String, dynamic>) {
        try {
          event = Map<String, Object?>.from(eventValue);
        } on TypeError {
          // Malformed records are removed below.
        }
      }
      final id = event?['event_id'];
      if (session is! String ||
          !_uuid.hasMatch(session) ||
          id is! String ||
          !_uuid.hasMatch(id) ||
          name.toLowerCase() != '${id.toLowerCase()}.json' ||
          at == null ||
          at.isBefore(now.subtract(_retention)) ||
          at.isAfter(now.add(const Duration(minutes: 5)))) {
        await entry.delete();
        continue;
      }
      retained.add((id: id, session: session, event: event!, bytes: size, at: at));
    }
    retained.sort((a, b) {
      final order = a.at.compareTo(b.at);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    var bytes = retained.fold<int>(0, (sum, item) => sum + item.bytes);
    while (retained.length > _maxEvents || bytes > _maxBytes) {
      final oldest = retained.removeAt(0);
      bytes -= oldest.bytes;
      await _file(directory, '${oldest.id}.json').delete();
    }
    return retained;
  }

  @override
  Future<TelemetrySnapshot?> read(String scope) async {
    final directory = await _directory(scope);
    if (!await directory.exists()) return null;
    return _locked(directory, () async {
      if (await _file(directory, '.closed').exists()) return null;
      final records = await _sweep(directory);
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
    });
  }

  @override
  Future<void> write(String scope, TelemetrySnapshot snapshot) async {
    if (!_uuid.hasMatch(snapshot.clientSessionId) || snapshot.events.length > _maxEvents) {
      throw const FormatException('Invalid telemetry snapshot');
    }
    final directory = await _directory(scope);
    await _locked(directory, () async {
      if (await _file(directory, '.closed').exists()) {
        throw StateError('Telemetry scope is closed');
      }
      await _sweep(directory);
      final known = _known.putIfAbsent(scope, () => <String, DateTime>{});
      final current = <String>{};
      for (final event in snapshot.events) {
        final id = event['event_id'];
        if (id is! String || !_uuid.hasMatch(id) || !current.add(id)) {
          throw const FormatException('Invalid telemetry event identity');
        }
        if (known.containsKey(id)) continue;
        final file = _file(directory, '$id.json');
        if (!await file.exists()) {
          final raw = jsonEncode({
            'stored_at': DateTime.now().toUtc().toIso8601String(),
            'client_session_id': snapshot.clientSessionId,
            'event': event,
          });
          if (utf8.encode(raw).length > _maxEventBytes) {
            throw const FormatException('Telemetry event exceeds storage limit');
          }
          final temporary = _file(directory, '$id.json.${newRequestId()}.tmp');
          try {
            await temporary.writeAsString(raw, flush: true);
            await temporary.rename(file.path);
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
        }
        known[id] = DateTime.now().toUtc();
      }
      for (final id in known.keys.where((id) => !current.contains(id)).toList()) {
        final file = _file(directory, '$id.json');
        if (await file.exists()) await file.delete();
      }
      _pruneKnown(known, current);
      final retained = await _sweep(directory);
      if (!retained.map((record) => record.id).toSet().containsAll(current)) {
        throw StateError('Telemetry storage capacity was reached');
      }
    });
  }

  @override
  Future<void> clear(String scope) async {
    final directory = await _directory(scope);
    await _locked(directory, () async {
      final closed = _file(directory, '.closed');
      if (!await closed.exists()) await closed.writeAsString('closed\n', flush: true);
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File &&
            (_eventName.hasMatch(entry.uri.pathSegments.last) ||
                entry.uri.pathSegments.last.endsWith('.tmp'))) {
          await entry.delete();
        }
      }
      _known.remove(scope);
    });
  }
}
