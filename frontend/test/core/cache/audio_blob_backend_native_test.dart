import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/audio_blob_backend_native.dart';
import 'package:haruka/core/cache/audio_blob_store.dart';
import 'package:haruka/core/cache/audio_process_lock.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:path/path.dart' as path;

void main() {
  test('waiting shared reader remains on the same process lock after writer exits', () async {
    const key = 'same-process-waiter-regression';
    final first = (await AudioProcessLock.acquire(key, shared: true))!;
    final writerFuture = AudioProcessLock.acquire(key);
    final readerFuture = AudioProcessLock.acquire(key, shared: true);
    first.release();
    final writer = (await writerFuture)!;
    writer.release();
    final reader = (await readerFuture)!;
    expect(await AudioProcessLock.acquire(key, ifAvailable: true), isNull);
    reader.release();
    final after = await AudioProcessLock.acquire(key, ifAvailable: true);
    expect(after, isNotNull);
    after!.release();
  });

  test('native same-process readers and operations exclude deletion and recovery', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-audio-lock-');
    try {
      final first = NativeAudioByteBackend(directory);
      final second = NativeAudioByteBackend(directory);
      const reference = 'ready-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await File(path.join(directory.path, reference)).writeAsBytes([1]);
      final reading = Completer<void>();
      final release = Completer<void>();
      final player = first.withReadLock(reference, () async {
        reading.complete();
        await release.future;
      });
      await reading.future;
      expect(await second.tryDelete(reference), isFalse);
      release.complete();
      await player;
      expect(await second.tryDelete(reference), isTrue);

      final operationEntered = Completer<void>();
      final operationRelease = Completer<void>();
      final operation = first.withOperationLock('transfer', () async {
        operationEntered.complete();
        await operationRelease.future;
      });
      await operationEntered.future;
      expect(
        await second.withOperationLock('transfer', () async => true, ifAvailable: true),
        isNull,
      );
      operationRelease.complete();
      await operation;
      expect(
        await second.withOperationLock('transfer', () async => true, ifAvailable: true),
        isTrue,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('native private file is pinned during consumption and corruption is detected', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-audio-test-');
    try {
      final scope = CacheScope.confirmed(
        endpoint: Uri.parse('https://haruka.example.test/api'),
        instanceId: 'instance',
        userId: 'learner',
        audience: 'client',
        sessionRef: 'session',
      );
      final backend = NativeAudioByteBackend(directory);
      final store = AudioBlobStore(scope, backend);
      final bytes = List<int>.generate(8193, (index) => index % 251);
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
      expect(await File(path.join(directory.path, ready.reference)).exists(), isTrue);
      expect(await store.verify(ready), isTrue);

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
      expect(await store.tryDeleteReady(ready), isFalse);
      release.complete();
      expect(await reading, bytes);

      await File(path.join(directory.path, ready.reference)).writeAsBytes([1, 2]);
      expect(await store.verify(ready), isFalse);
      expect(
        await store.withReadyStream(ready, (_) async => 1, readAllowedIfCurrent: (_) async => true),
        isNull,
      );
      expect(await store.tryDeleteReady(ready), isTrue);
      expect(await File(path.join(directory.path, ready.reference)).exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
