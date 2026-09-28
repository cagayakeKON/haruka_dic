import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite;

CacheScope _scope() => CacheScope.confirmed(
  endpoint: Uri.parse('https://cache.example.test/api'),
  instanceId: 'platform-recovery',
  userId: 'learner',
  audience: 'client',
  sessionRef: 'session',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native corrupt index enters memory mode and preserves original bytes', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-cache-corrupt-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    final owner = _scope();
    final partition = Directory(path.join(directory.path, 'haruka-cache', owner.partition));
    final index = File(path.join(partition.path, 'index.sqlite'));
    final cache = CacheCoordinator();
    try {
      await partition.create(recursive: true);
      final corrupt = List<int>.filled(512, 0x41);
      await index.writeAsBytes(corrupt);

      // Exercise the real native preflight rather than an injected executor.
      await cache.attach(owner);
      expect(cache.accessReady, isTrue);
      expect(cache.scope?.binding, owner.binding);
      expect(cache.storageMode, CacheStorageMode.memoryOnly);
      expect(cache.degradedReason, 'persistent_schema_unavailable');
      expect(await index.readAsBytes(), corrupt);
    } finally {
      try {
        await cache.closeScope();
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    }
  });

  test('future schema over Drift remote requires update without touching index', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-cache-future-');
    final index = File(path.join(directory.path, 'index.sqlite'));
    CacheCoordinator? cache;
    try {
      final raw = sqlite.sqlite3.open(index.path);
      try {
        raw.execute('CREATE TABLE original_marker (value TEXT NOT NULL)');
        raw.execute("INSERT INTO original_marker VALUES ('keep')");
        raw.execute('PRAGMA user_version = 5');
      } finally {
        raw.close();
      }

      var memoryOpened = 0;
      cache = CacheCoordinator(
        // Background native uses Drift's remote error transport, as Web does.
        openBackend: (_) async => OpenedCacheBackend(
          executor: NativeDatabase.createInBackground(index),
          mode: CacheStorageMode.persistent,
          closeOwner: () async {},
        ),
        openMemoryBackend: () async {
          memoryOpened++;
          return OpenedCacheBackend(
            executor: NativeDatabase.memory(),
            mode: CacheStorageMode.memoryOnly,
            degradedReason: 'persistent_schema_unavailable',
            closeOwner: () async {},
          );
        },
      );
      await expectLater(
        cache.attach(_scope()),
        throwsA(
          isA<CacheBlocked>().having((error) => error.reason, 'reason', 'cache_update_required'),
        ),
      );
      expect(memoryOpened, 0);
      expect(cache.accessReady, isFalse);
      expect(cache.scope, isNull);
      expect(cache.terminalReason, 'cache_update_required');
      final unchanged = sqlite.sqlite3.open(index.path, mode: sqlite.OpenMode.readOnly);
      try {
        expect(unchanged.select('PRAGMA user_version').single.values.single, 5);
        expect(unchanged.select('SELECT value FROM original_marker').single['value'], 'keep');
      } finally {
        unchanged.close();
      }
    } finally {
      try {
        await cache?.closeScope();
      } finally {
        await directory.delete(recursive: true);
      }
    }
  });
}
