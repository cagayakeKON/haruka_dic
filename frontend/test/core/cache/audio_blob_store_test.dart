import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/audio_blob_store.dart';
import 'package:haruka/core/cache/cache_models.dart';

void main() {
  final scope = CacheScope.confirmed(
    endpoint: Uri.parse('https://haruka.example.test/api'),
    instanceId: 'instance',
    userId: 'learner',
    audience: 'client',
    sessionRef: 'session',
  );
  const bytes = [1, 2, 3, 4, 5];
  final digest = sha256.convert(bytes).toString();

  test('streamed stage verifies bytes before ready publication', () async {
    final backend = _MemoryAudioBackend();
    final store = AudioBlobStore(scope, backend);
    final staged = await store.stage(
      storageEpoch: 'epoch-a',
      operationId: 'download-a',
      assetKey: 'speech-v2',
      expectedSha256: digest,
      expectedBytes: bytes.length,
      chunks: Stream.fromIterable([bytes.sublist(0, 2), bytes.sublist(2)]),
      isCurrent: () => true,
    );
    expect(backend.data.keys, contains(staged.reference));
    final ready = await store.publish(staged, recordReadyIfCurrent: (_) async => true);
    expect(ready, isNotNull);
    expect(backend.data.keys, isNot(contains(staged.reference)));
    expect(await store.verify(ready!), isTrue);
    final played = await store.withReadyStream(ready, (chunks) async {
      final result = <int>[];
      await for (final chunk in chunks) {
        result.addAll(chunk);
      }
      return result;
    }, readAllowedIfCurrent: (_) async => true);
    expect(played, bytes);
    expect(
      await store.withReadyStream(ready, (_) async => 1, readAllowedIfCurrent: (_) async => false),
      isNull,
    );
  });

  test('account generation change during streaming removes staging bytes', () async {
    final backend = _MemoryAudioBackend();
    final store = AudioBlobStore(scope, backend);
    var current = true;
    Stream<List<int>> source() async* {
      yield bytes.sublist(0, 2);
      current = false;
      yield bytes.sublist(2);
    }

    await expectLater(
      store.stage(
        storageEpoch: 'epoch',
        operationId: 'stale-stream',
        assetKey: 'speech',
        expectedSha256: digest,
        expectedBytes: bytes.length,
        chunks: source(),
        isCurrent: () => current,
      ),
      throwsA(isA<CacheBlocked>()),
    );
    expect(backend.data, isEmpty);
  });

  test('truncated and digest-mismatched stages never survive', () async {
    final backend = _MemoryAudioBackend();
    final store = AudioBlobStore(scope, backend);
    Future<void> attempt(int length, String hash) async {
      await expectLater(
        store.stage(
          storageEpoch: 'epoch-a',
          operationId: 'download-$length-$hash',
          assetKey: 'speech',
          expectedSha256: hash,
          expectedBytes: length,
          chunks: Stream.value(bytes),
          isCurrent: () => true,
        ),
        throwsFormatException,
      );
      expect(backend.data, isEmpty);
    }

    await attempt(bytes.length + 1, digest);
    await attempt(bytes.length, sha256.convert(utf8.encode('other')).toString());
  });

  test('stale generation rejects ready publication and removes bytes', () async {
    final backend = _MemoryAudioBackend();
    final store = AudioBlobStore(scope, backend);
    final staged = await store.stage(
      storageEpoch: 'old-epoch',
      operationId: 'download',
      assetKey: 'speech',
      expectedSha256: digest,
      expectedBytes: bytes.length,
      chunks: Stream.value(bytes),
      isCurrent: () => true,
    );
    final ready = await store.publish(staged, recordReadyIfCurrent: (_) async => false);
    expect(ready, isNull);
    expect(backend.data, isEmpty);
  });

  test('unknown length stops before writing a chunk without reserved quota', () async {
    final backend = _MemoryAudioBackend();
    final store = AudioBlobStore(scope, backend);
    final reserved = <int>[];
    await expectLater(
      store.stage(
        storageEpoch: 'epoch',
        operationId: 'unknown-length',
        assetKey: 'speech',
        expectedSha256: digest,
        chunks: Stream.fromIterable([bytes.sublist(0, 2), bytes.sublist(2)]),
        isCurrent: () => true,
        reserveChunk: (length) async {
          reserved.add(length);
          return reserved.length == 1;
        },
      ),
      throwsStateError,
    );
    expect(reserved, [2, 3]);
    expect(backend.data, isEmpty);
  });

  test('byte-store corruption during staging fails before publication', () async {
    final backend = _MemoryAudioBackend()..corruptOnClose = true;
    final store = AudioBlobStore(scope, backend);
    await expectLater(
      store.stage(
        storageEpoch: 'epoch',
        operationId: 'corrupt',
        assetKey: 'speech',
        expectedSha256: digest,
        expectedBytes: bytes.length,
        chunks: Stream.value(bytes),
        isCurrent: () => true,
      ),
      throwsFormatException,
    );
    expect(backend.data, isEmpty);
  });

  test('recovery reports corrupted ready and leaves pinned orphan pending', () async {
    final backend = _MemoryAudioBackend();
    final store = AudioBlobStore(scope, backend);
    final staged = await store.stage(
      storageEpoch: 'epoch-a',
      operationId: 'download',
      assetKey: 'speech',
      expectedSha256: digest,
      expectedBytes: bytes.length,
      chunks: Stream.value(bytes),
      isCurrent: () => true,
    );
    final ready = (await store.publish(staged, recordReadyIfCurrent: (_) async => true))!;
    backend.data[ready.reference] = [1, 2];
    final orphan = 'ready-${List.filled(64, '0').join()}';
    backend.data[orphan] = [8];
    backend.pinned.add(orphan);
    final report = await store.recover(
      indexedReady: {ready.reference: ready},
      activeStagingReferences: {},
    );
    expect(report.missingOrBroken, {ready.reference});
    expect(report.pendingDeletion, {orphan});
    expect(report.deletedOrphans, isEmpty);
  });

  test('cross-account ready reference is rejected before read', () async {
    final store = AudioBlobStore(scope, _MemoryAudioBackend());
    final foreign = ReadyAudio(
      partition: 'different',
      storageEpoch: 'epoch',
      assetKey: 'speech',
      reference: 'ready-${List.filled(64, '0').join()}',
      byteLength: 5,
      sha256Hex: digest,
    );
    await expectLater(
      store.withReadyStream(foreign, (_) async => 1, readAllowedIfCurrent: (_) async => true),
      throwsStateError,
    );
  });
}

final class _MemoryAudioBackend implements AudioByteBackend {
  final Map<String, List<int>> data = {};
  final Set<String> pinned = {};
  bool corruptOnClose = false;

  @override
  Future<AudioStageWriter> beginStage(String reference) async {
    if (data.containsKey(reference)) throw StateError('Duplicate operation');
    data[reference] = [];
    return _MemoryWriter(data, reference, () => corruptOnClose);
  }

  @override
  Future<void> promote(String stagingReference, String readyReference) async {
    data[readyReference] = data.remove(stagingReference)!;
  }

  @override
  Future<Stream<List<int>>?> open(String reference) async {
    final bytes = data[reference];
    return bytes == null ? null : Stream.value(bytes);
  }

  @override
  Future<bool> tryDelete(String reference) async {
    if (pinned.contains(reference)) return false;
    data.remove(reference);
    return true;
  }

  @override
  Future<Set<String>> references() async => data.keys.toSet();

  @override
  Future<T> withPublishLock<T>(Future<T> Function() action) => action();

  @override
  Future<T?> withOperationLock<T>(
    String operationId,
    Future<T> Function() action, {
    bool ifAvailable = false,
  }) => action();

  @override
  Future<T> withReadLock<T>(String reference, Future<T> Function() action) => action();

  @override
  Future<void> close() async {}
}

final class _MemoryWriter implements AudioStageWriter {
  _MemoryWriter(this.data, this.reference, this.corruptOnClose);
  final Map<String, List<int>> data;
  final String reference;
  final bool Function() corruptOnClose;

  @override
  Future<void> add(List<int> bytes) async => data[reference]!.addAll(bytes);

  @override
  Future<void> close() async {
    if (corruptOnClose() && data[reference]!.isNotEmpty) data[reference]![0] ^= 0xff;
  }

  @override
  Future<void> abort() async => data.remove(reference);
}
