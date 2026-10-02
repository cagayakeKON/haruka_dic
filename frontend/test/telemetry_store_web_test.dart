@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/telemetry/telemetry_store.dart';
import 'package:haruka/core/telemetry/telemetry_store_web.dart';
import 'package:web/web.dart' as web;

const _instance = 'haruka-test-0123456789abcdef0123456789abcdef';
const _scope = 'web:synthetic-user:client:session';
const _session = '018f1234-1234-7123-8123-123456789abc';
const _otherSession = '018f1234-1234-7123-8123-123456789abd';

Map<String, Object?> _event(int number, {String? padding}) => {
  'event_id': '018f1234-0000-7000-8000-${number.toString().padLeft(12, '0')}',
  'event': 'app.started',
  'occurred_at': DateTime.now().toUtc().toIso8601String(),
  'padding': ?padding,
};

void main() {
  test('localStorage cleans corrupt and expired events, then closes old scope', () async {
    final storage = web.window.localStorage;
    final prefix = 'haruka.telemetry.${telemetryScopeKey('$_instance:$_scope')}.';
    for (var index = storage.length - 1; index >= 0; index--) {
      final key = storage.key(index);
      if (key != null && key.startsWith(prefix)) storage.removeItem(key);
    }
    addTearDown(() {
      for (var index = storage.length - 1; index >= 0; index--) {
        final key = storage.key(index);
        if (key != null && key.startsWith(prefix)) storage.removeItem(key);
      }
    });
    final first = _event(1);
    final second = _event(2);
    final a = PlatformTelemetryStore(_instance);
    final b = PlatformTelemetryStore(_instance);
    await a.write(_scope, TelemetrySnapshot(clientSessionId: _session, events: [first]));
    await b.write(_scope, TelemetrySnapshot(clientSessionId: _otherSession, events: [second]));
    final corruptId = _event(3)['event_id'] as String;
    storage.setItem('$prefix$corruptId', '{');
    final old = _event(4);
    old['occurred_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 25))
        .toIso8601String();
    storage.setItem(
      '$prefix${old['event_id']}',
      jsonEncode({
        'stored_at': DateTime.now().toUtc().toIso8601String(),
        'client_session_id': _session,
        'event': old,
      }),
    );
    expect(
      (await PlatformTelemetryStore(_instance).read(_scope))!.events,
      containsAll([first, second]),
    );
    await a.write(_scope, const TelemetrySnapshot(clientSessionId: _session, events: []));
    expect((await PlatformTelemetryStore(_instance).read(_scope))!.events, [second]);
    expect(storage.getItem('$prefix$corruptId'), isNull);
    expect(storage.getItem('$prefix${old['event_id']}'), isNull);

    await a.clear(_scope);
    await expectLater(
      b.write(_scope, TelemetrySnapshot(clientSessionId: _session, events: [second])),
      throwsA(isA<StateError>()),
    );
    expect(await PlatformTelemetryStore(_instance).read(_scope), isNull);
    expect(storage.getItem('$prefix${second['event_id']}'), isNull);
  });

  test('oversize localStorage write fails without marking event committed', () async {
    final storage = web.window.localStorage;
    final scope = '${_scope}2';
    final prefix = 'haruka.telemetry.${telemetryScopeKey('$_instance:$scope')}.';
    addTearDown(() {
      for (var index = storage.length - 1; index >= 0; index--) {
        final key = storage.key(index);
        if (key != null && key.startsWith(prefix)) storage.removeItem(key);
      }
    });
    final store = PlatformTelemetryStore(_instance);
    final large = _event(5, padding: 'x' * 16384);
    await expectLater(
      store.write(scope, TelemetrySnapshot(clientSessionId: _session, events: [large])),
      throwsA(isA<FormatException>()),
    );
    expect(storage.getItem('$prefix${large['event_id']}'), isNull);
    final small = _event(5);
    await store.write(scope, TelemetrySnapshot(clientSessionId: _session, events: [small]));
    expect((await PlatformTelemetryStore(_instance).read(scope))!.events, [small]);
  });
}
