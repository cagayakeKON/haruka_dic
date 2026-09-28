@TestOn('browser')
library;

import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/audio_blob_backend_web.dart';
import 'package:haruka/core/cache/audio_blob_store.dart';
import 'package:haruka/core/cache/cache_invalidation_channel_web.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/cache/cache_entry_lock_web.dart';

void main() {
  test('text entry eviction skips a shared Web Lock and proceeds after release', () async {
    final partition = 'text-${DateTime.now().microsecondsSinceEpoch}';
    final release = await acquireCacheEntryPin(partition, 'entry');
    expect(await tryCacheEntryEviction(partition, 'entry'), isNull);
    release();
    final eviction = await tryCacheEntryEviction(partition, 'entry');
    expect(eviction, isNotNull);
    eviction!();
  });
  test('IndexedDB blobs are verified and Web Locks protect an active reader', () async {
    final scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example.test/api'),
      instanceId: 'instance',
      userId: 'learner-${DateTime.now().microsecondsSinceEpoch}',
      audience: 'client',
      sessionRef: 'session',
    );
    final backend = await openAudioByteBackend(scope.partition);
    final store = AudioBlobStore(scope, backend);
    AudioBlobStore? secondStore;
    try {
      final secondBackend = await openAudioByteBackend(scope.partition);
      secondStore = AudioBlobStore(scope, secondBackend);
      final bytes = List<int>.generate(10001, (index) => index % 241);
      final staged = await store.stage(
        storageEpoch: 'epoch',
        operationId: 'operation',
        assetKey: 'asset-v1',
        expectedSha256: sha256.convert(bytes).toString(),
        expectedBytes: bytes.length,
        chunks: Stream.fromIterable([bytes.sublist(0, 4096), bytes.sublist(4096)]),
        isCurrent: () => true,
      );
      final ready = (await store.publish(staged, recordReadyIfCurrent: (_) async => true))!;
      expect(await store.verify(ready), isTrue);
      expect(await secondStore.verify(ready), isTrue);

      final entered = Completer<void>();
      final release = Completer<void>();
      final reading = store.withReadyStream(ready, (chunks) async {
        entered.complete();
        await release.future;
        final result = <int>[];
        await for (final chunk in chunks) {
          result.addAll(chunk);
        }
        return result;
      }, readAllowedIfCurrent: (_) async => true);
      await entered.future;
      expect(await secondStore.tryDeleteReady(ready), isFalse);
      release.complete();
      expect(await reading, bytes);
      expect(await secondStore.tryDeleteReady(ready), isTrue);
      expect(await store.verify(ready), isFalse);
    } finally {
      await secondStore?.close();
      await store.close();
    }
  });

  test('BroadcastChannel sends only an invalidation hint to another channel', () async {
    final partition = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example.test/api'),
      instanceId: 'instance',
      userId: 'hint-${DateTime.now().microsecondsSinceEpoch}',
      audience: 'client',
      sessionRef: 'session',
    ).partition;
    final received = Completer<(String, Set<String>?)>();
    final sender = CacheInvalidationChannel(partition, (_, _) {});
    final receiver = CacheInvalidationChannel(partition, (type, tags) {
      if (!received.isCompleted) received.complete((type, tags));
    });
    try {
      sender.publish('secret-body');
      sender.publish('invalidate', {'settings:profile'});
      final hint = await received.future.timeout(const Duration(seconds: 5));
      expect(hint.$1, 'invalidate');
      expect(hint.$2, {'settings:profile'});
    } finally {
      receiver.close();
      sender.close();
    }
  });
}
