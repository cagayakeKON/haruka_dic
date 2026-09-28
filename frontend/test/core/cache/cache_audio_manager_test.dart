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

void main() {
  test(
    'authorized audio is reserved, verified, published and reused without a new download',
    () async {
      final directory = await Directory.systemTemp.createTemp('haruka-audio-manager-');
      final database = CacheDatabase(NativeDatabase.memory());
      final scope = CacheScope.confirmed(
        endpoint: Uri.parse('https://haruka.example.test/api'),
        instanceId: 'instance',
        userId: 'learner',
        audience: 'client',
        sessionRef: 'session',
      );
      final store = AudioBlobStore(scope, NativeAudioByteBackend(directory));
      addTearDown(() async {
        await store.close();
        await database.close();
        await directory.delete(recursive: true);
      });
      var epoch = await database.storageEpoch();
      var suspended = false;
      final manager = CacheAudioManager(
        scope: scope,
        database: database,
        bytes: store,
        storageEpoch: () => epoch,
        authorizationGeneration: () => 0,
        persistenceSuspended: () => suspended,
        isCurrent: (captured) => captured == epoch,
      );
      const resource = CacheResource(
        kind: 'speech_asset',
        id: 'sentence-1',
        projection: 'ordinary-audio-v1',
        action: 'speech.play',
        sourceBinding: 'material-1:sentence-1',
      );
      final sample = <int>[1, 2, 3, 4, 5];
      final digest = sha256.convert(sample).toString();
      final ready = await manager.download(
        resource: resource,
        version: 'audio-v1',
        format: 'audio/mpeg',
        sha256Hex: digest,
        expectedBytes: sample.length,
        chunks: Stream.value(sample),
        readAllowedNow: () async => true,
      );
      expect(ready, isNotNull);
      expect((await database.audioAsset(resource.keyFor(scope)))?.reference, ready!.reference);
      final read = await manager.read(
        resource: resource,
        version: 'audio-v1',
        readAllowedNow: () async => true,
        consume: (chunks) async => [await for (final chunk in chunks) ...chunk],
      );
      expect(read, sample);
      final reused = await manager.download(
        resource: resource,
        version: 'audio-v1',
        format: 'audio/mpeg',
        sha256Hex: digest,
        expectedBytes: sample.length,
        chunks: const Stream<List<int>>.empty(),
        readAllowedNow: () async => true,
      );
      expect(reused?.reference, ready.reference);
      expect(
        await manager.read(
          resource: resource,
          version: 'audio-v1',
          readAllowedNow: () async => false,
          consume: (_) async => 1,
        ),
        isNull,
      );
      const limitedListening = CacheResource(
        kind: 'speech_asset',
        id: 'exam-attempt-1',
        projection: 'finite-listening-v1',
        action: 'speech.play',
        sourceBinding: 'exam-session-1:attempt-1',
      );
      var authorizationChecks = 0;
      Future<bool> allow() async {
        authorizationChecks++;
        return true;
      }

      await expectLater(
        manager.download(
          resource: limitedListening,
          version: 'frozen-audio-v1',
          format: 'audio/mpeg',
          sha256Hex: digest,
          chunks: Stream.value(sample),
          readAllowedNow: allow,
        ),
        throwsA(isA<CacheBlocked>()),
      );
      await expectLater(
        manager.read(
          resource: limitedListening,
          version: 'frozen-audio-v1',
          readAllowedNow: allow,
          consume: (_) async => sample,
        ),
        throwsA(isA<CacheBlocked>()),
      );
      expect(authorizationChecks, 0);
      expect(await database.audioAsset(limitedListening.keyFor(scope)), isNull);
      epoch = await database.clearText();
      suspended = true;
      expect(
        await manager.read(
          resource: resource,
          version: 'audio-v1',
          readAllowedNow: () async => true,
          consume: (chunks) async => [await for (final chunk in chunks) ...chunk],
        ),
        sample,
      );
      expect(await database.audioOperations(), isEmpty);
    },
  );

  test('authorization lost before publish cannot make staged audio ready', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-audio-denied-');
    final database = CacheDatabase(NativeDatabase.memory());
    final scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example.test/api'),
      instanceId: 'instance',
      userId: 'learner',
      audience: 'client',
      sessionRef: 'session',
    );
    final store = AudioBlobStore(scope, NativeAudioByteBackend(directory));
    addTearDown(() async {
      await store.close();
      await database.close();
      await directory.delete(recursive: true);
    });
    final epoch = await database.storageEpoch();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: store,
      storageEpoch: () => epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
      isCurrent: (_) => true,
    );
    const resource = CacheResource(
      kind: 'speech_asset',
      id: 'sentence-2',
      projection: 'ordinary-audio-v1',
      action: 'speech.play',
      sourceBinding: 'material-1:sentence-2',
    );
    var allowed = true;
    Stream<List<int>> source() async* {
      yield [7, 8, 9];
      allowed = false;
    }

    final result = await manager.download(
      resource: resource,
      version: 'audio-v1',
      format: 'audio/mpeg',
      sha256Hex: sha256.convert([7, 8, 9]).toString(),
      expectedBytes: 3,
      chunks: source(),
      readAllowedNow: () async => allowed,
    );
    expect(result, isNull);
    expect(await database.audioAsset(resource.keyFor(scope)), isNull);
    expect(await database.audioOperations(), isEmpty);
    expect(await NativeAudioByteBackend(directory).references(), isEmpty);
  });

  test('recovery removes an old-epoch stage but preserves an active stage', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-audio-recover-');
    final database = CacheDatabase(NativeDatabase.memory());
    final scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example.test/api'),
      instanceId: 'instance',
      userId: 'learner',
      audience: 'client',
      sessionRef: 'session',
    );
    final backend = NativeAudioByteBackend(directory);
    final store = AudioBlobStore(scope, backend);
    addTearDown(() async {
      await store.close();
      await database.close();
      await directory.delete(recursive: true);
    });
    final oldEpoch = await database.storageEpoch();
    final oldReference = store.stageReference(oldEpoch, 'old', 'old-asset');
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old',
        assetKey: 'old-asset',
        reserveBytes: 2,
        stagingReference: oldReference,
      ),
      isTrue,
    );
    final oldWriter = await backend.beginStage(oldReference);
    await oldWriter.add([1, 2]);
    await oldWriter.close();
    final currentEpoch = await database.clearText();
    final activeReference = store.stageReference(currentEpoch, 'active', 'new-asset');
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: currentEpoch,
        operationId: 'active',
        assetKey: 'new-asset',
        reserveBytes: 2,
        stagingReference: activeReference,
        allowDuringPending: true,
      ),
      isTrue,
    );
    final activeWriter = await backend.beginStage(activeReference);
    await activeWriter.add([3, 4]);
    await activeWriter.close();
    final ownerReady = Completer<void>();
    final releaseOwner = Completer<void>();
    final owner = store.withOperationLock('active', () async {
      ownerReady.complete();
      await releaseOwner.future;
      return true;
    });
    await ownerReady.future;
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: store,
      storageEpoch: () => currentEpoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
      isCurrent: (captured) => captured == currentEpoch,
    );
    await manager.recover();
    expect(await backend.references(), {activeReference});
    expect((await database.audioOperations()).map((op) => op.operationId), ['active']);
    releaseOwner.complete();
    await owner;
    await manager.recover();
    expect(await backend.references(), isEmpty);
    expect(await database.audioOperations(), isEmpty);
  });

  test('recovery while a transfer is receiving bytes preserves publication', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-audio-overlap-');
    final database = CacheDatabase(NativeDatabase.memory());
    final scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example.test/api'),
      instanceId: 'instance',
      userId: 'learner',
      audience: 'client',
      sessionRef: 'session',
    );
    final backend = NativeAudioByteBackend(directory);
    final store = AudioBlobStore(scope, backend);
    addTearDown(() async {
      await store.close();
      await database.close();
      await directory.delete(recursive: true);
    });
    final epoch = await database.storageEpoch();
    final manager = CacheAudioManager(
      scope: scope,
      database: database,
      bytes: store,
      storageEpoch: () => epoch,
      authorizationGeneration: () => 0,
      persistenceSuspended: () => false,
      isCurrent: (captured) => captured == epoch,
    );
    const resource = CacheResource(
      kind: 'speech_asset',
      id: 'sentence',
      projection: 'ordinary-audio-v1',
      action: 'speech.play',
      sourceBinding: 'material-one',
    );
    final listening = Completer<void>();
    final stream = StreamController<List<int>>(onListen: listening.complete);
    final transfer = manager.download(
      resource: resource,
      version: 'v1',
      format: 'audio/mpeg',
      sha256Hex: sha256.convert([1, 2, 3]).toString(),
      expectedBytes: 3,
      chunks: stream.stream,
      readAllowedNow: () async => true,
    );
    await listening.future;
    await manager.recover();
    expect(await database.audioOperations(), hasLength(1));
    stream.add([1, 2, 3]);
    await stream.close();
    expect(await transfer, isNotNull);
    expect(await database.audioOperations(), isEmpty);
    expect(await database.audioAsset(resource.keyFor(scope)), isNotNull);
  });
}
