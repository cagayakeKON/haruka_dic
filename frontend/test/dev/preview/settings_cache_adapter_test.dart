import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';

void main() {
  test('scope closure hides old account usage before another scope attaches', () async {
    final coordinator = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final adapter = PreviewSettingsCacheAdapter(coordinator: coordinator);
    addTearDown(adapter.dispose);
    await adapter.initialize();
    expect(adapter.ready, isTrue);
    await coordinator.closeScope();
    expect(adapter.ready, isFalse);
    expect(adapter.usage, isNull);
    await coordinator.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://another.example/api'),
        instanceId: 'other-instance',
        userId: 'other-account',
        audience: 'client',
        sessionRef: 'other-session',
      ),
    );
    await adapter.refresh();
    expect(adapter.ready, isTrue);
  });

  test('failed preview cache initialization can retry', () async {
    var attempts = 0;
    final coordinator = CacheCoordinator(
      openBackend: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('transient storage failure');
        return OpenedCacheBackend(
          executor: NativeDatabase.memory(),
          mode: CacheStorageMode.memoryOnly,
          closeOwner: () async {},
        );
      },
    );
    final adapter = PreviewSettingsCacheAdapter(coordinator: coordinator);
    addTearDown(adapter.dispose);
    await adapter.initialize();
    expect(adapter.ready, isFalse);
    expect(adapter.lastError, isNotNull);
    await adapter.retry();
    expect(attempts, 2);
    expect(adapter.ready, isTrue);
    expect(adapter.lastError, isNull);
  });

  test('mock cache settings write real Drift quotas and report pending audio cleanup', () async {
    final executor = NativeDatabase.memory();
    final coordinator = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: executor,
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final adapter = PreviewSettingsCacheAdapter(coordinator: coordinator);
    addTearDown(adapter.dispose);

    await adapter.initialize();
    expect(adapter.ready, isTrue);
    expect(adapter.usage!.textQuotaBytes, 100000000);
    expect(adapter.usage!.audioQuotaBytes, 500000000);
    expect(adapter.usage!.textEntries, 0);

    expect(await adapter.saveLimits(textMb: 250, audioMb: 1000), isTrue);
    expect(adapter.usage!.textQuotaBytes, 250000000);
    expect(adapter.usage!.audioQuotaBytes, 1000000000);

    // Seed an index record with unavailable bytes to exercise the real
    // coordinator's partial deletion path, without a fake clear result.
    const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final now = DateTime.now().toUtc().toIso8601String();
    await executor.runInsert(
      'INSERT INTO local_assets '
      '(asset_key, version, format, sha256, expected_bytes, actual_bytes, state, '
      'blob_ref, last_access_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      ['audio-1', 'v1', 'audio/wav', digest, 8, 8, 'ready', 'ready-$digest', now, now, now],
    );
    await adapter.refresh();
    expect(adapter.usage!.audioAssets, 1);
    expect(adapter.usage!.audioBytes, 8);

    final result = await adapter.clear();
    expect(result?.deletedAudio, 0);
    expect(result?.pendingAudio, 1);
    expect(adapter.lastClear?.pendingAudio, 1);
    expect(adapter.usage!.audioAssets, 0);
    expect(adapter.usage!.audioBytes, 8);
    final control = await executor.runSelect(
      'SELECT clear_state FROM cache_control WHERE id = 1',
      [],
    );
    expect(control.single['clear_state'], 'pending');
  });
}
