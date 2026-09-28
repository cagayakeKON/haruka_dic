import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/audio_blob_backend_native.dart';
import 'package:haruka/core/cache/audio_blob_store.dart';
import 'package:haruka/core/cache/cache_audio_manager.dart';
import 'package:haruka/core/cache/cache_database.dart';
import 'package:haruka/core/cache/cache_models.dart';

class _DeleteFault implements AudioByteBackend {
  _DeleteFault(this.delegate);
  final AudioByteBackend delegate;
  bool rejectDeletion = false;
  @override
  Future<bool> tryDelete(String reference) async =>
      !rejectDeletion && await delegate.tryDelete(reference);
  @override
  Future<AudioStageWriter> beginStage(String reference) => delegate.beginStage(reference);
  @override
  Future<void> promote(String from, String to) => delegate.promote(from, to);
  @override
  Future<Stream<List<int>>?> open(String reference) => delegate.open(reference);
  @override
  Future<Set<String>> references() => delegate.references();
  @override
  Future<T> withPublishLock<T>(Future<T> Function() action) => delegate.withPublishLock(action);
  @override
  Future<T> withReadLock<T>(String reference, Future<T> Function() action) =>
      delegate.withReadLock(reference, action);
  @override
  Future<T?> withOperationLock<T>(
    String id,
    Future<T> Function() action, {
    bool ifAvailable = false,
  }) => delegate.withOperationLock(id, action, ifAvailable: ifAvailable);
  @override
  Future<void> close() => delegate.close();
}

void main() {
  late Directory directory;
  late CacheDatabase database;
  late CacheScope scope;
  late _DeleteFault backend;
  late CacheAudioManager manager;
  const sample = [1, 2, 3, 4, 5];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('haruka-audio-recovery-');
    database = CacheDatabase(NativeDatabase.memory());
    scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://cache.example/api'),
      instanceId: 'test',
      userId: 'a',
      audience: 'client',
      sessionRef: 'session',
    );
    backend = _DeleteFault(NativeAudioByteBackend(directory));
    final epoch = await database.storageEpoch();
    manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: AudioBlobStore(scope, backend),
      storageEpoch: () => epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
      isCurrent: (value) => value == epoch,
    );
  });
  tearDown(() async {
    await manager.close();
    await database.close();
    await directory.delete(recursive: true);
  });
  CacheResource resource(String id) => CacheResource(
    kind: 'speech_asset',
    id: id,
    projection: 'ordinary-audio-v1',
    action: 'speech.play',
    sourceBinding: 'sentence:$id',
  );
  Future<ReadyAudio?> download(String id) => manager.download(
    resource: resource(id),
    version: '1',
    format: 'audio/wav',
    sha256Hex: sha256.convert(sample).toString(),
    chunks: Stream.value(sample),
    expectedBytes: sample.length,
    readAllowedNow: () async => true,
  );

  test('missing bytes become broken with zero occupancy even if deletion fails', () async {
    final ready = (await download('one'))!;
    await backend.delegate.tryDelete(ready.reference);
    backend.rejectDeletion = true;
    await manager.recover();
    expect(await database.audioAsset(resource('one').keyFor(scope)), isNull);
    final row =
        (await database.customSelect('SELECT state, actual_bytes FROM local_assets').get()).single;
    expect(row.read<String>('state'), 'broken');
    expect(row.read<int>('actual_bytes'), 0);
    expect((await database.usage()).audioBytes, 0);
    expect((await database.usage()).audioAssets, 0);
    backend.rejectDeletion = false;
    expect(await download('one'), isNotNull);
  });

  test('late damage discovery cannot revive an audio deletion record', () async {
    final ready = (await download('one'))!;
    final oldEpoch = await database.storageEpoch();
    final clearedEpoch = await database.beginClearAll();
    for (final epoch in [oldEpoch, clearedEpoch]) {
      await database.markAudioBroken(
        resource('one').keyFor(scope),
        ready.reference,
        expectedStorageEpoch: epoch,
        missing: true,
      );
      expect(await database.pendingAudioDeletions(), [ready.reference]);
      expect(await database.finishClearAll(expectedStorageEpoch: clearedEpoch), 1);
    }
  });

  test('playback discovers missing bytes without advertising a ready asset', () async {
    final ready = (await download('one'))!;
    await backend.delegate.tryDelete(ready.reference);
    var consumed = false;
    final result = await manager.read(
      resource: resource('one'),
      version: '1',
      readAllowedNow: () async => true,
      consume: (_) async {
        consumed = true;
        return 1;
      },
    );
    expect(result, isNull);
    expect(consumed, isFalse);
    expect((await database.usage()).audioAssets, 0);
    expect((await database.usage()).audioBytes, 0);
  });

  test('quota admission evicts least recently used audio and skips an active player', () async {
    await database.setQuotas(audioBytes: 10);
    await download('one');
    await download('two');
    await manager.read(
      resource: resource('one'),
      version: '1',
      readAllowedNow: () async => true,
      consume: (chunks) async {
        await chunks.drain<void>();
        return true;
      },
    );
    expect(await download('three'), isNotNull);
    expect(await database.audioAsset(resource('two').keyFor(scope)), isNull);
    expect(await database.audioAsset(resource('one').keyFor(scope)), isNotNull);

    await database.setQuotas(audioBytes: 5);
    final playing = Completer<void>();
    final release = Completer<void>();
    final playback = manager.read(
      resource: resource('one'),
      version: '1',
      readAllowedNow: () async => true,
      consume: (chunks) async {
        await chunks.drain<void>();
        playing.complete();
        await release.future;
        return true;
      },
    );
    await playing.future;
    expect(await download('four'), isNull);
    expect(await database.audioAsset(resource('one').keyFor(scope)), isNotNull);
    release.complete();
    await playback;
    expect(await download('four'), isNotNull);
    expect((await database.usage()).audioBytes, 5);
  });
}
