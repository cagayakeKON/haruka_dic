import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/telemetry/telemetry_store.dart';
import 'package:haruka/core/telemetry/telemetry_store_native.dart';

const _instance = 'haruka-test-0123456789abcdef0123456789abcdef';
const _scope = 'instance:synthetic-user:client:session';
const _session = '018f1234-1234-7123-8123-123456789abc';
const _otherSession = '018f1234-1234-7123-8123-123456789abd';

Map<String, Object?> _event(int number) => {
  'event_id': '018f1234-0000-7000-8000-${number.toString().padLeft(12, '0')}',
  'event': 'app.started',
  'occurred_at': DateTime.now().toUtc().toIso8601String(),
};

Future<Directory> _fixture() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('haruka-telemetry-store-');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (_) async => root.path,
  );
  addTearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    await root.delete(recursive: true);
  });
  return Directory(
    '${root.path}${Platform.pathSeparator}haruka-telemetry'
    '${Platform.pathSeparator}${telemetryScopeKey('$_instance:$_scope')}',
  );
}

void main() {
  test('failed native commit is visible and same event retries durably', () async {
    final directory = await _fixture();
    await directory.create(recursive: true);
    final event = _event(1);
    final id = event['event_id']! as String;
    final obstruction = Directory('${directory.path}${Platform.pathSeparator}$id.json');
    await obstruction.create();
    final store = PlatformTelemetryStore(_instance);
    final snapshot = TelemetrySnapshot(clientSessionId: _session, events: [event]);

    await expectLater(store.write(_scope, snapshot), throwsA(isA<FileSystemException>()));
    expect(await store.read(_scope), isNull);
    await obstruction.delete();
    await store.write(_scope, snapshot);
    expect((await PlatformTelemetryStore(_instance).read(_scope))!.events, [event]);
    expect(
      directory.listSync().whereType<File>().where((file) => file.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('native reader removes stale, malformed and interrupted files', () async {
    final directory = await _fixture();
    await directory.create(recursive: true);
    final old = _event(2);
    old['occurred_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 25))
        .toIso8601String();
    final bad = _event(3);
    final oldFile = File('${directory.path}${Platform.pathSeparator}${old['event_id']}.json');
    final badFile = File('${directory.path}${Platform.pathSeparator}${bad['event_id']}.json');
    final temporary = File('${directory.path}${Platform.pathSeparator}orphan.tmp');
    await oldFile.writeAsString(
      jsonEncode({
        'stored_at': DateTime.now().toUtc().toIso8601String(),
        'client_session_id': _session,
        'event': old,
      }),
    );
    await badFile.writeAsString('{');
    await temporary.writeAsString('partial');
    final current = _event(4);
    final store = PlatformTelemetryStore(_instance);
    await store.write(_scope, TelemetrySnapshot(clientSessionId: _session, events: [current]));
    expect((await store.read(_scope))!.events, [current]);
    expect(await oldFile.exists(), isFalse);
    expect(await badFile.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
  });

  test('two native writers converge and logout closes the scope against late writes', () async {
    final directory = await _fixture();
    final first = PlatformTelemetryStore(_instance);
    final second = PlatformTelemetryStore(_instance);
    final a = _event(5);
    final b = _event(6);
    await Future.wait([
      first.write(_scope, TelemetrySnapshot(clientSessionId: _session, events: [a])),
      second.write(_scope, TelemetrySnapshot(clientSessionId: _otherSession, events: [b])),
    ]);
    expect((await PlatformTelemetryStore(_instance).read(_scope))!.events, containsAll([a, b]));
    await first.write(_scope, const TelemetrySnapshot(clientSessionId: _session, events: []));
    expect((await PlatformTelemetryStore(_instance).read(_scope))!.events, [b]);
    await first.clear(_scope);
    await expectLater(
      second.write(_scope, TelemetrySnapshot(clientSessionId: _session, events: [b])),
      throwsA(isA<StateError>()),
    );
    expect(await PlatformTelemetryStore(_instance).read(_scope), isNull);
    expect(
      directory.listSync().whereType<File>().where((file) => file.path.endsWith('.json')),
      isEmpty,
    );
  });

  test('native startup sweeps expired events from an abandoned scope', () async {
    final currentDirectory = await _fixture();
    final oldDirectory = Directory(
      '${currentDirectory.parent.path}${Platform.pathSeparator}aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await oldDirectory.create(recursive: true);
    final old = _event(7);
    old['occurred_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 25))
        .toIso8601String();
    final oldFile = File('${oldDirectory.path}${Platform.pathSeparator}${old['event_id']}.json');
    await oldFile.writeAsString(
      jsonEncode({
        'stored_at': DateTime.now().toUtc().toIso8601String(),
        'client_session_id': _session,
        'event': old,
      }),
    );
    await PlatformTelemetryStore(_instance)
        .write(_scope, TelemetrySnapshot(clientSessionId: _session, events: [_event(8)]));
    expect(await oldFile.exists(), isFalse);
  });

  test('native disk scan bounds a mixed-writer queue to 5000 events', () async {
    final directory = await _fixture();
    await directory.create(recursive: true);
    for (var number = 10000; number <= 15000; number++) {
      final event = _event(number);
      await File('${directory.path}${Platform.pathSeparator}${event['event_id']}.json')
          .writeAsString(
            jsonEncode({
              'stored_at': DateTime.now().toUtc().toIso8601String(),
              'client_session_id': _session,
              'event': event,
            }),
          );
    }
    final loaded = await PlatformTelemetryStore(_instance).read(_scope);
    expect(loaded!.events, hasLength(5000));
    expect(
      directory.listSync().whereType<File>().where((file) => file.path.endsWith('.json')).length,
      5000,
    );
  });
  test('native per-event queue survives restart and two writers do not overwrite', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final root = await Directory.systemTemp.createTemp('haruka-telemetry-test-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => root.path,
    );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      await root.delete(recursive: true);
    });
    const scope = 'instance:user:client:session';
    const session = '018f1234-1234-7123-8123-123456789abc';
    Map<String, Object?> event(String id) => {'event_id': id, 'event': 'app.started'};
    final a = PlatformTelemetryStore('haruka-test-0123456789abcdef0123456789abcdef');
    final b = PlatformTelemetryStore('haruka-test-0123456789abcdef0123456789abcdef');
    final first = event('018f1234-0000-7000-8000-000000000001');
    final second = event('018f1234-0000-7000-8000-000000000002');
    final third = event('018f1234-0000-7000-8000-000000000003');
    await a.write(scope, TelemetrySnapshot(clientSessionId: session, events: [first]));
    expect((await b.read(scope))!.events, hasLength(1));
    await b.write(scope, TelemetrySnapshot(clientSessionId: session, events: [first, second]));
    await a.write(scope, TelemetrySnapshot(clientSessionId: session, events: [first, third]));
    final restart = PlatformTelemetryStore('haruka-test-0123456789abcdef0123456789abcdef');
    expect((await restart.read(scope))!.events.map((item) => item['event_id']).toSet(), {
      first['event_id'],
      second['event_id'],
      third['event_id'],
    });
    await a.write(scope, TelemetrySnapshot(clientSessionId: session, events: [third]));
    expect(
      (await PlatformTelemetryStore('haruka-test-0123456789abcdef0123456789abcdef').read(scope))!
          .events
          .map((item) => item['event_id'])
          .toSet(),
      {second['event_id'], third['event_id']},
    );
  });
}
