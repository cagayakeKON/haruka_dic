import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor, ApplyInterceptor;
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/audio_blob_store.dart';
import 'package:haruka/core/cache/cache_audio_manager.dart';
import 'package:haruka/core/cache/cache_database.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/cache/cache_partition_lock.dart';

import '../../support/test_database.dart';

final class _Bytes implements AudioByteBackend {
  final data = <String, List<int>>{};
  final writtenChunks = <List<int>>[];
  bool rejectDeletion = false;
  final undeletableReferences = <String>{};
  int quotaFailures = 0;
  int promotionQuotaFailures = 0;
  bool publishHeld = false;
  String? evictionVictim;
  void Function()? onAdd;
  String? blockedOpenReference;
  Completer<void>? openStarted;
  Completer<void>? releaseOpen;

  @override
  Future<AudioStageWriter> beginStage(String reference) async {
    data[reference] = [];
    return _Writer(this, reference);
  }

  @override
  Future<void> promote(String from, String to) async {
    if (promotionQuotaFailures > 0) {
      promotionQuotaFailures--;
      throw const AudioStorageQuotaExceeded();
    }
    data[to] = data.remove(from)!;
  }

  @override
  Future<Stream<List<int>>?> open(String reference) async {
    if (reference == blockedOpenReference) {
      if (openStarted != null && !openStarted!.isCompleted) openStarted!.complete();
      await releaseOpen?.future;
    }
    final value = data[reference];
    if (value == null) return null;
    final split = value.length ~/ 2;
    return Stream.fromIterable([value.sublist(0, split), value.sublist(split)]);
  }

  @override
  Future<bool> tryDelete(String reference) async {
    if (publishHeld && reference == evictionVictim) {
      throw StateError('eviction reentered publish lock');
    }
    if (rejectDeletion || undeletableReferences.contains(reference)) return false;
    data.remove(reference);
    return true;
  }

  @override
  Future<Set<String>> references() async => data.keys.toSet();
  @override
  Future<T> withPublishLock<T>(Future<T> Function() action) async {
    if (publishHeld) throw StateError('publish lock reentered');
    publishHeld = true;
    try {
      return await action();
    } finally {
      publishHeld = false;
    }
  }

  @override
  Future<T> withReadLock<T>(String reference, Future<T> Function() action) => action();
  @override
  Future<T?> withOperationLock<T>(
    String id,
    Future<T> Function() action, {
    bool ifAvailable = false,
  }) async => action();
  @override
  Future<void> close() async {}
}

final class _Writer implements AudioStageWriter {
  _Writer(this.backend, this.reference);
  final _Bytes backend;
  final String reference;
  @override
  Future<void> add(List<int> bytes) async {
    if (backend.quotaFailures > 0) {
      backend.quotaFailures--;
      throw const AudioStorageQuotaExceeded();
    }
    backend.data[reference]!.addAll(bytes);
    backend.writtenChunks.add(List<int>.of(bytes));
    backend.onAdd?.call();
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> abort() async {
    await backend.tryDelete(reference);
  }
}

final class _PausePendingStateRead extends QueryInterceptor {
  final reached = Completer<void>();
  final release = Completer<void>();
  bool armed = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (armed && statement.contains('SELECT clear_state FROM cache_control')) {
      armed = false;
      reached.complete();
      await release.future;
    }
    return rows;
  }
}

void main() {
  setUpAll(initializeTestDatabase);
  final scope = CacheScope.confirmed(
    endpoint: Uri.parse('https://cache.example.test/api'),
    instanceId: 'test',
    userId: 'learner',
    audience: 'client',
    sessionRef: 'session',
  );
  const resource = CacheResource(
    kind: 'speech_asset',
    id: 'one',
    projection: 'ordinary-audio-v1',
    action: 'speech.play',
    sourceBinding: 'sentence:one',
  );
  const sample = [1, 2, 3, 4];

  test('revocation ends a paused audio consumer and releases its read pin', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final changes = StreamController<void>.broadcast(sync: true);
    final epoch = await database.storageEpoch();
    var generation = 0;
    var allowed = true;
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => generation,
      authorizationChanges: changes.stream,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
      await changes.close();
    });
    await manager.download(
      resource: resource,
      version: 'v1',
      format: 'audio/wav',
      sha256Hex: sha256.convert(sample).toString(),
      expectedBytes: sample.length,
      chunks: Stream.value(sample),
      readAllowedNow: () async => allowed,
    );
    final first = Completer<void>();
    final hold = Completer<void>();
    final delivered = <int>[];
    final reading = manager.read<int>(
      resource: resource,
      version: 'v1',
      readAllowedNow: () async => allowed,
      consume: (chunks) async {
        await for (final chunk in chunks) {
          delivered.addAll(chunk);
          if (!first.isCompleted) {
            first.complete();
            await hold.future;
          }
        }
        return delivered.length;
      },
    );
    await first.future;
    allowed = false;
    generation++;
    changes.add(null);
    await expectLater(reading, throwsA(isA<CacheBlocked>()));
    hold.complete();
    expect(delivered, [1, 2]);
  });

  test('failed deletion keeps staged bytes charged and clear pending', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes()..rejectDeletion = true;
    final epoch = await database.storageEpoch();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
    });
    Stream<List<int>> interrupted() async* {
      yield sample.sublist(0, 2);
      throw StateError('interrupted transfer');
    }

    await expectLater(
      manager.download(
        resource: resource,
        version: 'v1',
        format: 'audio/wav',
        sha256Hex: sha256.convert(sample).toString(),
        expectedBytes: sample.length,
        chunks: interrupted(),
        readAllowedNow: () async => true,
      ),
      throwsStateError,
    );
    expect(backend.data.values.single, [1, 2]);
    expect((await database.usage()).audioBytes, greaterThanOrEqualTo(2));
    expect(await database.audioOperations(), hasLength(1));
    final clearEpoch = await database.beginClearAll();
    expect(await database.pendingAudioDeletions(), hasLength(1));
    expect(await database.finishClearAll(expectedStorageEpoch: clearEpoch), 1);
    backend.rejectDeletion = false;
    await manager.recover();
    expect(await database.finishClearAll(expectedStorageEpoch: clearEpoch), 0);
    expect(backend.data, isEmpty);
  });

  test('storage quota failure evicts one ready asset and retries the same chunk once', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final epoch = await database.storageEpoch();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
    });
    Future<ReadyAudio?> download(CacheResource item) => manager.download(
      resource: item,
      version: 'v1',
      format: 'audio/wav',
      sha256Hex: sha256.convert(sample).toString(),
      expectedBytes: sample.length,
      chunks: Stream.value(sample),
      readAllowedNow: () async => true,
    );
    final first = await download(resource);
    expect(first, isNotNull);
    backend.quotaFailures = 1;
    const second = CacheResource(
      kind: 'speech_asset',
      id: 'two',
      projection: 'ordinary-audio-v1',
      action: 'speech.play',
      sourceBinding: 'sentence:two',
    );
    final ready = await download(second);
    expect(ready, isNotNull);
    expect(await database.audioAsset(resource.keyFor(scope)), isNull);
    expect((await database.audioAsset(second.keyFor(scope)))?.reference, ready!.reference);
    expect(backend.data[ready.reference], sample);
    expect(backend.quotaFailures, 0);
  });

  test('promotion quota retry evicts only after releasing publish lock', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final epoch = await database.storageEpoch();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
    });
    Future<ReadyAudio?> download(CacheResource item) => manager.download(
      resource: item,
      version: 'v1',
      format: 'audio/wav',
      sha256Hex: sha256.convert(sample).toString(),
      expectedBytes: sample.length,
      chunks: Stream.value(sample),
      readAllowedNow: () async => true,
    );
    final first = await download(resource);
    expect(first, isNotNull);
    backend.promotionQuotaFailures = 1;
    backend.evictionVictim = first!.reference;
    const second = CacheResource(
      kind: 'speech_asset',
      id: 'promotion',
      projection: 'ordinary-audio-v1',
      action: 'speech.play',
      sourceBinding: 'sentence:promotion',
    );
    expect(await download(second), isNotNull);
    expect(await database.audioAsset(resource.keyFor(scope)), isNull);
    expect(backend.promotionQuotaFailures, 0);
  });

  test('text clear cancels a stalled old-epoch transfer and releases its slot', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final changes = StreamController<void>.broadcast(sync: true);
    final chunks = StreamController<List<int>>();
    var epoch = await database.storageEpoch();
    final firstStored = Completer<void>();
    backend.onAdd = () {
      if (!firstStored.isCompleted) firstStored.complete();
    };
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      authorizationChanges: changes.stream,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
      await changes.close();
      await chunks.close();
    });
    final transfer = manager.download(
      resource: resource,
      version: 'v1',
      format: 'audio/wav',
      sha256Hex: sha256.convert(sample).toString(),
      expectedBytes: sample.length,
      chunks: chunks.stream,
      readAllowedNow: () async => true,
    );
    chunks.add(sample.sublist(0, 2));
    await firstStored.future;
    epoch = await database.clearText();
    changes.add(null);
    await expectLater(transfer.timeout(const Duration(seconds: 3)), throwsA(isA<CacheBlocked>()));
    expect((await database.usage()).activeDownloads, 0);
    expect(await database.clearState(), 'ready');
    expect(await database.finishClearAll(expectedStorageEpoch: epoch), 0);
    expect(backend.data, isEmpty);
  });

  test('persistent epoch change rejects the next chunk without an invalidation hint', () async {
    final index = await TestDatabaseFile.create('haruka-audio-epoch-');
    final database = CacheDatabase(index.executor());
    final external = CacheDatabase(index.executor());
    final backend = _Bytes();
    final chunks = StreamController<List<int>>();
    final oldEpoch = await database.storageEpoch();
    final firstStored = Completer<void>();
    backend.onAdd = () {
      if (!firstStored.isCompleted) firstStored.complete();
    };
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => oldEpoch,
      isCurrent: (_) => true,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    try {
      final transfer = manager.download(
        resource: resource,
        version: 'v1',
        format: 'audio/wav',
        sha256Hex: sha256.convert(sample).toString(),
        expectedBytes: sample.length,
        chunks: chunks.stream,
        readAllowedNow: () async => true,
      );
      chunks.add(sample.sublist(0, 2));
      await firstStored.future;
      await external.clearText();
      chunks.add(sample.sublist(2));
      await chunks.close();
      await expectLater(transfer, throwsA(isA<CacheBlocked>()));
      expect(backend.writtenChunks, [sample.sublist(0, 2)]);
      expect(await database.audioAsset(resource.keyFor(scope)), isNull);
    } finally {
      await manager.close();
      await external.close();
      await database.close();
      await index.close();
    }
  });

  test('old download cleanup cannot finish a newer clear generation', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final chunks = StreamController<List<int>>();
    final oldEpoch = await database.storageEpoch();
    final firstStored = Completer<void>();
    backend.onAdd = () {
      if (!firstStored.isCompleted) firstStored.complete();
    };
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => oldEpoch,
      isCurrent: (_) => true,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    try {
      final transfer = manager.download(
        resource: resource,
        version: 'v1',
        format: 'audio/wav',
        sha256Hex: sha256.convert(sample).toString(),
        expectedBytes: sample.length,
        chunks: chunks.stream,
        readAllowedNow: () async => true,
      );
      chunks.add(sample.sublist(0, 2));
      await firstStored.future;
      final newerEpoch = await database.beginClearAll();
      chunks.add(sample.sublist(2));
      await chunks.close();
      await expectLater(transfer, throwsA(isA<CacheBlocked>()));
      expect(await database.clearState(), 'clearing');
      expect(await database.finishClearAll(expectedStorageEpoch: newerEpoch), 0);
      expect(await database.clearState(), 'ready');
    } finally {
      await manager.close();
      await database.close();
      await chunks.close();
    }
  });

  test('pending read cannot finish a newer clear after waiting for its lock', () async {
    final index = await TestDatabaseFile.create('haruka-audio-clear-race-');
    final pause = _PausePendingStateRead();
    final database = CacheDatabase(index.executor().interceptWith(pause));
    final external = CacheDatabase(index.executor());
    var epoch = await database.storageEpoch();
    final oldReference = AudioBlobStore(scope, _Bytes()).stageReference(epoch, 'old', 'old-asset');
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, _Bytes()),
      storageEpoch: () => epoch,
      isCurrent: (_) => true,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    try {
      expect(
        await database.beginAudioOperation(
          expectedStorageEpoch: epoch,
          operationId: 'old',
          assetKey: 'old-asset',
          reserveBytes: 1,
          stagingReference: oldReference,
        ),
        isTrue,
      );
      final pendingEpoch = await database.beginClearAll();
      expect(await database.finishClearAll(expectedStorageEpoch: pendingEpoch), 1);
      epoch = pendingEpoch;
      pause.armed = true;
      const other = CacheResource(
        kind: 'speech_asset',
        id: 'clear-race',
        projection: 'ordinary-audio-v1',
        action: 'speech.play',
        sourceBinding: 'sentence:clear-race',
      );
      final download = manager.download(
        resource: other,
        version: 'v1',
        format: 'audio/wav',
        sha256Hex: sha256.convert(sample).toString(),
        expectedBytes: sample.length,
        chunks: Stream.value(sample),
        readAllowedNow: () async => true,
        explicitUserAction: true,
      );
      await pause.reached.future;
      final lockEntered = Completer<void>();
      final releaseLock = Completer<void>();
      final heldLock = withCachePartitionPublishLock(scope.partition, () async {
        lockEntered.complete();
        await releaseLock.future;
      });
      await lockEntered.future;
      pause.release.complete();
      late String newerEpoch;
      try {
        newerEpoch = await external.beginClearAll();
      } finally {
        releaseLock.complete();
        await heldLock;
      }
      await expectLater(
        download,
        throwsA(
          isA<CacheBlocked>().having((error) => error.reason, 'reason', 'storage_epoch_changed'),
        ),
      );
      expect(await database.storageEpoch(), newerEpoch);
      expect(await database.clearState(), 'clearing');
    } finally {
      if (!pause.release.isCompleted) pause.release.complete();
      await manager.close();
      await external.close();
      await database.close();
      await index.close();
    }
  });

  test('retired promoted bytes stay charged until deletion succeeds', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final store = AudioBlobStore(scope, backend);
    final oldEpoch = await database.storageEpoch();
    final key = resource.keyFor(scope);
    const operationId = 'promoted-crash';
    final stage = store.stageReference(oldEpoch, operationId, key);
    final ready = store.readyReference(oldEpoch, operationId, key);
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: oldEpoch,
        operationId: operationId,
        assetKey: key,
        reserveBytes: 100,
        stagingReference: stage,
      ),
      isTrue,
    );
    final writer = await backend.beginStage(stage);
    await writer.add([1, 2]);
    await writer.close();
    await backend.promote(stage, ready);
    backend.undeletableReferences.add(ready);
    final epoch = await database.clearText();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: store,
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
    });
    await manager.cleanupRetiredOperations();
    expect(backend.data[ready], [1, 2]);
    expect((await database.audioOperations()).single.reference, ready);
    expect((await database.usage()).audioBytes, 2);
    expect(await database.clearState(), 'pending');
    backend.undeletableReferences.clear();
    await manager.cleanupRetiredOperations();
    expect(await database.audioOperations(), isEmpty);
    expect((await database.usage()).audioBytes, 0);
    expect(backend.data, isEmpty);
  });

  test('pending cleanup for one asset does not block another explicit download', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final store = AudioBlobStore(scope, backend);
    final oldEpoch = await database.storageEpoch();
    final key = resource.keyFor(scope);
    final oldReference = store.stageReference(oldEpoch, 'old-transfer', key);
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old-transfer',
        assetKey: key,
        reserveBytes: 2,
        stagingReference: oldReference,
      ),
      isTrue,
    );
    final writer = await backend.beginStage(oldReference);
    await writer.add(sample.sublist(0, 2));
    await writer.close();
    backend.undeletableReferences.add(oldReference);
    final epoch = await database.clearText();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: store,
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => true,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
    });
    await manager.cleanupRetiredOperations();
    expect(await database.clearState(), 'pending');
    const other = CacheResource(
      kind: 'speech_asset',
      id: 'other',
      projection: 'ordinary-audio-v1',
      action: 'speech.play',
      sourceBinding: 'sentence:other',
    );
    final ready = await manager.download(
      resource: other,
      version: 'v1',
      format: 'audio/wav',
      sha256Hex: sha256.convert(sample).toString(),
      expectedBytes: sample.length,
      chunks: Stream.value(sample),
      readAllowedNow: () async => true,
      explicitUserAction: true,
    );
    expect(ready, isNotNull);
    expect((await database.audioOperations()).single.reference, oldReference);
    await expectLater(
      manager.download(
        resource: resource,
        version: 'v1',
        format: 'audio/wav',
        sha256Hex: sha256.convert(sample).toString(),
        expectedBytes: sample.length,
        chunks: Stream.value(sample),
        readAllowedNow: () async => true,
        explicitUserAction: true,
      ),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('recovery hashes outside the publish lock and preserves a later ready asset', () async {
    final database = CacheDatabase(memoryTestDatabase());
    final backend = _Bytes();
    final epoch = await database.storageEpoch();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      isCurrent: (value) => value == epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
    );
    addTearDown(() async {
      await manager.close();
      await database.close();
    });
    Future<ReadyAudio?> download(CacheResource item) => manager.download(
      resource: item,
      version: 'v1',
      format: 'audio/wav',
      sha256Hex: sha256.convert(sample).toString(),
      expectedBytes: sample.length,
      chunks: Stream.value(sample),
      readAllowedNow: () async => true,
    );
    final first = (await download(resource))!;
    backend.blockedOpenReference = first.reference;
    backend.openStarted = Completer<void>();
    backend.releaseOpen = Completer<void>();
    final recovery = manager.recover();
    await backend.openStarted!.future;
    try {
      await withCachePartitionPublishLock(
        scope.partition,
        database.usage,
      ).timeout(const Duration(seconds: 2));
      const other = CacheResource(
        kind: 'speech_asset',
        id: 'published-during-recovery',
        projection: 'ordinary-audio-v1',
        action: 'speech.play',
        sourceBinding: 'sentence:published-during-recovery',
      );
      final newer = await download(other);
      expect(newer, isNotNull);
      backend.releaseOpen!.complete();
      await recovery;
      expect((await database.audioAsset(other.keyFor(scope)))?.reference, newer!.reference);
      expect(backend.data[newer.reference], sample);
    } finally {
      if (!backend.releaseOpen!.isCompleted) backend.releaseOpen!.complete();
    }
  });
}
