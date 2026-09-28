import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cache_models.dart';

/// Byte storage is deliberately separate from the Drift index. The caller must
/// reserve capacity and a download slot in local_operations before staging.
abstract interface class AudioByteBackend {
  Future<AudioStageWriter> beginStage(String reference);
  Future<void> promote(String stagingReference, String readyReference);
  Future<Stream<List<int>>?> open(String reference);
  Future<bool> tryDelete(String reference);
  Future<Set<String>> references();
  Future<T> withPublishLock<T>(Future<T> Function() action);
  Future<T?> withOperationLock<T>(
    String operationId,
    Future<T> Function() action, {
    bool ifAvailable = false,
  });
  Future<T> withReadLock<T>(String reference, Future<T> Function() action);
  Future<void> close();
}

abstract interface class AudioStageWriter {
  Future<void> add(List<int> bytes);
  Future<void> close();
  Future<void> abort();
}

/// Browser storage can be exhausted before the application's own quota is.
final class AudioStorageQuotaExceeded implements Exception {
  const AudioStorageQuotaExceeded();
}

final class StagedAudio {
  const StagedAudio({
    required this.partition,
    required this.storageEpoch,
    required this.operationId,
    required this.assetKey,
    required this.reference,
    required this.byteLength,
    required this.sha256Hex,
  });

  final String partition;
  final String storageEpoch;
  final String operationId;
  final String assetKey;
  final String reference;
  final int byteLength;
  final String sha256Hex;
}

final class ReadyAudio {
  const ReadyAudio({
    required this.partition,
    required this.storageEpoch,
    required this.assetKey,
    required this.reference,
    required this.byteLength,
    required this.sha256Hex,
  });

  final String partition;
  final String storageEpoch;
  final String assetKey;
  final String reference;
  final int byteLength;
  final String sha256Hex;
}

final class AudioRecoveryReport {
  const AudioRecoveryReport({
    required this.missingOrBroken,
    required this.deletedOrphans,
    required this.pendingDeletion,
  });

  final Set<String> missingOrBroken;
  final Set<String> deletedOrphans;
  final Set<String> pendingDeletion;
}

/// A scope-local byte store. It never grants access: callers check the current
/// session, action grant and local_assets=ready before entering a read callback.
final class AudioBlobStore {
  AudioBlobStore(CacheScope scope, this._backend) : partition = scope.partition;

  final String partition;
  final AudioByteBackend _backend;

  static final RegExp _hexDigest = RegExp(r'^[a-f0-9]{64}$');

  String _reference(String prefix, String operationId, String assetKey, String epoch) {
    if (operationId.isEmpty || assetKey.isEmpty || epoch.isEmpty) {
      throw ArgumentError('Audio operation, asset and epoch are required');
    }
    final digest = sha256.convert(
      utf8.encode(jsonEncode([partition, epoch, operationId, assetKey])),
    );
    return '$prefix-$digest';
  }

  String stageReference(String storageEpoch, String operationId, String assetKey) =>
      _reference('stage', operationId, assetKey, storageEpoch);

  String readyReference(String storageEpoch, String operationId, String assetKey) =>
      _reference('ready', operationId, assetKey, storageEpoch);

  /// The optional per-chunk reservation callback is mandatory for manifests
  /// without a length. A failed reservation stops the stream before storage.
  Future<StagedAudio> stage({
    required String storageEpoch,
    required String operationId,
    required String assetKey,
    required String expectedSha256,
    required Stream<List<int>> chunks,
    required bool Function() isCurrent,
    Future<bool> Function()? isPersistentlyCurrent,
    Stream<void>? invalidationChanges,
    int? expectedBytes,
    Future<bool> Function(int nextBytes)? reserveChunk,
    void Function(int writtenBytes)? onWrittenBytes,
    Future<bool> Function()? onStorageQuotaExceeded,
  }) async {
    if (!_hexDigest.hasMatch(expectedSha256) || expectedBytes != null && expectedBytes < 0) {
      throw ArgumentError('Invalid audio manifest length or SHA-256');
    }
    if (expectedBytes == null && reserveChunk == null) {
      throw ArgumentError('Unknown-length audio requires incremental reservation');
    }
    if (!isCurrent() || isPersistentlyCurrent != null && !await isPersistentlyCurrent()) {
      throw const CacheBlocked('stale_audio_generation');
    }
    final reference = _reference('stage', operationId, assetKey, storageEpoch);
    var storageRetryUsed = false;
    AudioStageWriter writer;
    try {
      writer = await _backend.beginStage(reference);
    } on AudioStorageQuotaExceeded {
      storageRetryUsed = true;
      if (onStorageQuotaExceeded == null || !await onStorageQuotaExceeded()) rethrow;
      writer = await _backend.beginStage(reference);
    }
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var total = 0;
    final source = StreamIterator<List<int>>(chunks);
    Completer<bool>? pendingChunk;
    var invalidated = false;
    void invalidate() {
      if (invalidated) return;
      invalidated = true;
      final waiter = pendingChunk;
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(const CacheBlocked('stale_audio_generation'));
      }
      unawaited(source.cancel().catchError((Object _) {}));
    }

    final invalidationSubscription = invalidationChanges?.listen((_) async {
      try {
        if (!isCurrent() || isPersistentlyCurrent != null && !await isPersistentlyCurrent()) {
          invalidate();
        }
      } on Object {
        invalidate();
      }
    });
    try {
      while (true) {
        if (invalidated) throw const CacheBlocked('stale_audio_generation');
        final waiter = Completer<bool>();
        pendingChunk = waiter;
        unawaited(
          source.moveNext().then(
            (hasNext) {
              if (!waiter.isCompleted) waiter.complete(hasNext);
            },
            onError: (Object error, StackTrace trace) {
              if (!waiter.isCompleted) waiter.completeError(error, trace);
            },
          ),
        );
        final hasNext = await waiter.future;
        pendingChunk = null;
        if (!hasNext) break;
        final chunk = source.current;
        if (!isCurrent() || isPersistentlyCurrent != null && !await isPersistentlyCurrent()) {
          throw const CacheBlocked('stale_audio_generation');
        }
        if (chunk.isEmpty) continue;
        final next = total + chunk.length;
        if (next < total || expectedBytes != null && next > expectedBytes) {
          throw const FormatException('Audio exceeds manifest length');
        }
        if (reserveChunk != null && !await reserveChunk(chunk.length)) {
          throw StateError('Audio quota reservation failed');
        }
        try {
          await writer.add(chunk);
        } on AudioStorageQuotaExceeded {
          if (storageRetryUsed || onStorageQuotaExceeded == null) rethrow;
          storageRetryUsed = true;
          if (!await onStorageQuotaExceeded()) rethrow;
          await writer.add(chunk);
        }
        hasher.add(chunk);
        total = next;
        onWrittenBytes?.call(total);
      }
      hasher.close();
      await writer.close();
      if (expectedBytes != null && total != expectedBytes) {
        throw const FormatException('Audio is shorter than manifest length');
      }
      if (digestSink.digest.toString() != expectedSha256) {
        throw const FormatException('Audio SHA-256 mismatch');
      }
      if (!await _verifyReference(reference, total, expectedSha256)) {
        throw const FormatException('Stored audio stage is missing or corrupt');
      }
      if (!isCurrent() || isPersistentlyCurrent != null && !await isPersistentlyCurrent()) {
        throw const CacheBlocked('stale_audio_generation');
      }
      return StagedAudio(
        partition: partition,
        storageEpoch: storageEpoch,
        operationId: operationId,
        assetKey: assetKey,
        reference: reference,
        byteLength: total,
        sha256Hex: expectedSha256,
      );
    } catch (_) {
      try {
        await writer.abort();
      } on Object {
        // The operation journal remains until deletion can be confirmed.
      }
      rethrow;
    } finally {
      await invalidationSubscription?.cancel();
      try {
        await source.cancel();
      } on Object {
        // A failed upstream cancellation cannot restore a stale operation.
      }
    }
  }

  /// The callback must atomically check storage_epoch, session/account
  /// generation, permission/grant and quota, then update local_assets and
  /// local_operations in Drift. A false result leaves no readable ready index.
  Future<ReadyAudio?> publish(
    StagedAudio staged, {
    required Future<bool> Function(ReadyAudio) recordReadyIfCurrent,
    Future<bool> Function()? onStorageQuotaExceeded,
  }) async {
    _checkPartition(staged.partition);
    final ready = ReadyAudio(
      partition: partition,
      storageEpoch: staged.storageEpoch,
      assetKey: staged.assetKey,
      reference: _reference('ready', staged.operationId, staged.assetKey, staged.storageEpoch),
      byteLength: staged.byteLength,
      sha256Hex: staged.sha256Hex,
    );
    Future<ReadyAudio?> attempt() => _backend.withPublishLock(() async {
      await _backend.promote(staged.reference, ready.reference);
      try {
        if (await recordReadyIfCurrent(ready)) return ready;
      } catch (_) {
        await _backend.tryDelete(ready.reference);
        rethrow;
      }
      await _backend.tryDelete(ready.reference);
      return null;
    });
    try {
      return await attempt();
    } on AudioStorageQuotaExceeded {
      // Releasing publish first is essential: eviction takes the partition's
      // publish lock too (the same Web Lock in a browser).
      if (onStorageQuotaExceeded == null || !await onStorageQuotaExceeded()) rethrow;
      return attempt();
    }
  }

  /// Holds a shared resource lock until the consumer releases the stream.
  /// The consumer must fully consume or cancel its stream before returning.
  Future<T?> withReadyStream<T>(
    ReadyAudio ready,
    Future<T> Function(Stream<List<int>> chunks) consume, {
    required Future<bool> Function(ReadyAudio) readAllowedIfCurrent,
    Stream<void>? authorizationChanges,
    Future<void> Function()? onInvalidBytes,
  }) async {
    _checkPartition(ready.partition);
    return _backend.withReadLock(ready.reference, () async {
      if (!await readAllowedIfCurrent(ready)) return null;
      if (!await _verifyOpened(ready.reference, ready.byteLength, ready.sha256Hex)) {
        await onInvalidBytes?.call();
        return null;
      }
      if (!await readAllowedIfCurrent(ready)) return null;
      final chunks = await _backend.open(ready.reference);
      if (chunks == null) return null;
      final revoked = Completer<T>();
      revoked.future.ignore();
      StreamSubscription<void>? authorizationSubscription;
      StreamSubscription<List<int>>? byteSubscription;
      var stopped = false;
      late final StreamController<List<int>> delivery;
      Future<void> stop() async {
        if (stopped) return;
        stopped = true;
        try {
          await byteSubscription?.cancel();
        } on Object {
          // Revocation still ends the consumer if the byte source cannot close.
        }
        if (!revoked.isCompleted) {
          revoked.completeError(const CacheBlocked('audio_not_authorized'));
        }
        if (!delivery.isClosed) unawaited(delivery.close());
      }

      delivery = StreamController<List<int>>(
        onListen: () {
          byteSubscription = chunks
              .asyncMap((chunk) async {
                if (!await readAllowedIfCurrent(ready)) {
                  throw const CacheBlocked('audio_not_authorized');
                }
                return chunk;
              })
              .listen(
                (chunk) {
                  if (!stopped) delivery.add(chunk);
                },
                onError: (Object error, StackTrace trace) {
                  if (!stopped) delivery.addError(error, trace);
                },
                onDone: () {
                  if (!delivery.isClosed) unawaited(delivery.close());
                },
              );
        },
        onPause: () => byteSubscription?.pause(),
        onResume: () => byteSubscription?.resume(),
        onCancel: () => byteSubscription?.cancel(),
      );
      authorizationSubscription = authorizationChanges?.listen((_) async {
        try {
          if (!await readAllowedIfCurrent(ready)) await stop();
        } on Object {
          await stop();
        }
      });
      try {
        if (!await readAllowedIfCurrent(ready)) return null;
        return await Future.any([consume(delivery.stream), revoked.future]);
      } finally {
        await authorizationSubscription?.cancel();
        await byteSubscription?.cancel();
        if (!delivery.isClosed) unawaited(delivery.close());
      }
    });
  }

  Future<bool> verify(ReadyAudio ready) async {
    _checkPartition(ready.partition);
    return _verifyReference(ready.reference, ready.byteLength, ready.sha256Hex);
  }

  Future<bool> containsReference(String reference) async =>
      (await _backend.references()).contains(reference);

  Future<Set<String>> references() => _backend.references();

  Future<int> referenceLength(String reference) async {
    if (!RegExp(r'^(stage|ready)-[a-f0-9]{64}$').hasMatch(reference)) {
      throw ArgumentError.value(reference, 'reference');
    }
    // Recovery already owns publish/index locks. Waiting for a read lock here
    // could invert the order against a player that is touching the index.
    final chunks = await _backend.open(reference);
    if (chunks == null) return 0;
    var length = 0;
    await for (final chunk in chunks) {
      length += chunk.length;
    }
    return length;
  }

  Future<bool> _verifyReference(String reference, int expectedLength, String expectedSha256) async {
    return _backend.withReadLock(
      reference,
      () => _verifyOpened(reference, expectedLength, expectedSha256),
    );
  }

  Future<bool> _verifyOpened(String reference, int expectedLength, String expectedSha256) async {
    try {
      final chunks = await _backend.open(reference);
      if (chunks == null) return false;
      final sink = _DigestSink();
      final hasher = sha256.startChunkedConversion(sink);
      var length = 0;
      await for (final chunk in chunks) {
        length += chunk.length;
        if (length > expectedLength) return false;
        hasher.add(chunk);
      }
      hasher.close();
      return length == expectedLength && sink.digest.toString() == expectedSha256;
    } catch (_) {
      return false;
    }
  }

  /// Returns false while another reader holds the asset lock.
  Future<bool> tryDeleteReady(ReadyAudio ready) {
    _checkPartition(ready.partition);
    return _backend.tryDelete(ready.reference);
  }

  Future<bool> discardStaged(StagedAudio staged) {
    _checkPartition(staged.partition);
    return _backend.tryDelete(staged.reference);
  }

  Future<bool> tryDeleteReference(String reference) {
    if (!RegExp(r'^(stage|ready)-[a-f0-9]{64}$').hasMatch(reference)) {
      throw ArgumentError.value(reference, 'reference');
    }
    return _backend.tryDelete(reference);
  }

  /// Serializes reconciliation with a pending byte promotion. The caller also
  /// holds the partition's index lock while taking its authoritative snapshot.
  Future<T> withPublishLock<T>(Future<T> Function() action) => _backend.withPublishLock(action);

  Future<T?> withOperationLock<T>(
    String operationId,
    Future<T> Function() action, {
    bool ifAvailable = false,
  }) => _backend.withOperationLock(operationId, action, ifAvailable: ifAvailable);

  /// Reconciles byte references against the authoritative Drift operation and
  /// asset rows. Callers mark missingOrBroken entries broken in Drift and keep
  /// pendingDeletion rows for retry; active operations remain protected.
  Future<AudioRecoveryReport> recover({
    required Map<String, ReadyAudio> indexedReady,
    required Set<String> activeStagingReferences,
  }) async {
    for (final value in indexedReady.values) {
      _checkPartition(value.partition);
    }
    for (final entry in indexedReady.entries) {
      if (entry.key != entry.value.reference) throw ArgumentError('Ready audio reference mismatch');
    }
    final existing = await _backend.references();
    final broken = <String>{};
    for (final entry in indexedReady.entries) {
      if (!existing.contains(entry.key) || !await verify(entry.value)) broken.add(entry.key);
    }
    final keep = {...indexedReady.keys, ...activeStagingReferences};
    final deleted = <String>{};
    final pending = <String>{};
    for (final reference in existing.difference(keep)) {
      if (await _backend.tryDelete(reference)) {
        deleted.add(reference);
      } else {
        pending.add(reference);
      }
    }
    return AudioRecoveryReport(
      missingOrBroken: broken,
      deletedOrphans: deleted,
      pendingDeletion: pending,
    );
  }

  Future<void> close() => _backend.close();

  void _checkPartition(String value) {
    if (value != partition) throw StateError('Audio belongs to another cache scope');
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _digest;
  Digest get digest => _digest ?? (throw StateError('SHA-256 has not completed'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
