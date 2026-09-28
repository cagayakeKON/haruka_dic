import '../api/request_ids.dart';
import 'audio_blob_store.dart';
import 'cache_database.dart';
import 'cache_models.dart';
import 'cache_partition_lock.dart';

/// Coordinates one authorized audio transfer with shared Drift reservations.
/// Domain repositories supply the current read permission and server manifest.
final class CacheAudioManager {
  CacheAudioManager({
    required this.scope,
    required this.database,
    required this.bytes,
    required this.storageEpoch,
    required this.isCurrent,
    required this.authorizationGeneration,
    required this.persistenceSuspended,
    this.authorizationChanges,
    this.onEvent,
  });

  final CacheScope scope;
  final CacheDatabase database;
  final AudioBlobStore bytes;
  final String Function() storageEpoch;
  final bool Function(String capturedEpoch) isCurrent;
  final int Function() authorizationGeneration;
  final bool Function() persistenceSuspended;
  final Stream<void>? authorizationChanges;
  final void Function(String, Map<String, Object?>)? onEvent;

  Future<ReadyAudio?> download({
    required CacheResource resource,
    required String version,
    required String format,
    required String sha256Hex,
    required Stream<List<int>> chunks,
    required Future<bool> Function() readAllowedNow,
    int? expectedBytes,
    bool explicitUserAction = false,
  }) async {
    if (!resource.allowsPersistent(CacheDisposition.validatedAudio)) {
      throw const CacheBlocked('unregistered_audio');
    }
    if (expectedBytes != null && expectedBytes < 0) throw ArgumentError.value(expectedBytes);
    final key = resource.keyFor(scope);
    final epoch = storageEpoch();
    final generation = authorizationGeneration();
    bool current() => isCurrent(epoch) && authorizationGeneration() == generation;
    if (persistenceSuspended() && !explicitUserAction) {
      throw const CacheBlocked('explicit_download_required');
    }
    if (!current() || !await readAllowedNow()) throw const CacheBlocked('audio_not_authorized');
    final existing = await database.audioAsset(key, includeBroken: true, includeDeleting: true);
    if (existing != null) {
      final ready = _ready(existing, epoch);
      final validBytes = !existing.isDeleting && await bytes.verify(ready);
      if (existing.isReady &&
          existing.version == version &&
          existing.format == format &&
          existing.sha256 == sha256Hex &&
          validBytes) {
        if (!current() || !await readAllowedNow()) throw const CacheBlocked('audio_not_authorized');
        final touched = await withCachePartitionPublishLock(
          scope.partition,
          () async => current() && await database.touchAudioIfCurrent(key, ready.reference, epoch),
        );
        if (!touched || !current()) throw const CacheBlocked('audio_not_authorized');
        onEvent?.call('cache.download', {'result': 'hit'});
        return ready;
      }
      if (!validBytes && !existing.isDeleting) await _markBroken(existing, epoch);
      if (!await bytes.tryDeleteReady(ready)) {
        throw const CacheBlocked('audio_cleanup_pending');
      }
      final removed = await withCachePartitionPublishLock(
        scope.partition,
        () => database.forgetAudioAssetIfCurrent(key, ready.reference),
      );
      if (!removed || !current()) throw const CacheBlocked('audio_cleanup_pending');
    }
    // A failed deletion for another asset must not block this explicit
    // download. Only this asset's own retired operation is drained here.
    await cleanupRetiredOperations(assetKey: key);
    if (await database.hasPendingAudioForAsset(key)) {
      throw const CacheBlocked('audio_cleanup_pending');
    }
    var clearState = await database.clearState();
    if (clearState == 'pending') {
      await withCachePartitionPublishLock(
        scope.partition,
        () => database.finishClearAll(expectedStorageEpoch: epoch),
      );
      clearState = await database.clearState();
    }
    if (clearState == 'clearing' || clearState == 'pending' && !explicitUserAction) {
      throw const CacheBlocked('audio_cleanup_pending');
    }
    if (!current() || !await readAllowedNow()) throw const CacheBlocked('audio_not_authorized');
    final operationId = newRequestId();
    return bytes.withOperationLock<ReadyAudio?>(operationId, () async {
      final stagingReference = bytes.stageReference(epoch, operationId, key);
      final readyReference = bytes.readyReference(epoch, operationId, key);
      Future<bool> reserve() => withCachePartitionPublishLock(
        scope.partition,
        () => database.beginAudioOperation(
          expectedStorageEpoch: epoch,
          operationId: operationId,
          assetKey: key,
          reserveBytes: expectedBytes ?? 0,
          stagingReference: stagingReference,
          allowDuringPending: explicitUserAction,
        ),
      );
      var accepted = await reserve();
      var evictionAttempted = false;
      if (!accepted && current()) {
        final usage = await database.usage();
        final needed = expectedBytes ?? 0;
        final clear = await database.clearState();
        if (await database.storageEpoch() == epoch &&
            (clear == 'ready' || explicitUserAction && clear == 'pending') &&
            !await database.hasPendingAudioForAsset(key) &&
            usage.activeDownloads < 2 &&
            needed <= usage.audioQuotaBytes &&
            usage.audioBytes + needed > usage.audioQuotaBytes) {
          evictionAttempted = true;
          await _evictFor(needed, epoch, current, excluding: key);
          accepted = await reserve();
        }
      }
      if (!accepted) return null;
      StagedAudio? staged;
      var writtenBytes = 0;
      var publishedReady = false;
      var storageEvictionAttempted = false;
      Future<bool> evictOnStorageQuota() async {
        if (storageEvictionAttempted || !current()) return false;
        if (!await database.isAudioOperationCurrent(
          epoch,
          operationId,
          allowDuringPending: explicitUserAction,
        )) {
          return false;
        }
        storageEvictionAttempted = true;
        return _evictFor(0, epoch, current, excluding: key, forceOne: true);
      }

      try {
        staged = await bytes.stage(
          storageEpoch: epoch,
          operationId: operationId,
          assetKey: key,
          expectedSha256: sha256Hex,
          expectedBytes: expectedBytes,
          chunks: chunks,
          isCurrent: current,
          isPersistentlyCurrent: () => database.isAudioOperationCurrent(
            epoch,
            operationId,
            allowDuringPending: explicitUserAction,
          ),
          invalidationChanges: authorizationChanges,
          onWrittenBytes: (length) => writtenBytes = length,
          onStorageQuotaExceeded: evictOnStorageQuota,
          reserveChunk: expectedBytes == null
              ? (length) async {
                  Future<bool> reserveChunk() => withCachePartitionPublishLock(
                    scope.partition,
                    () => database.reserveAudioChunk(
                      expectedStorageEpoch: epoch,
                      operationId: operationId,
                      additionalBytes: length,
                    ),
                  );
                  if (await reserveChunk()) return true;
                  if (evictionAttempted || !current()) return false;
                  if (!await database.isAudioOperationCurrent(
                    epoch,
                    operationId,
                    allowDuringPending: explicitUserAction,
                  )) {
                    return false;
                  }
                  final usage = await database.usage();
                  if (usage.audioBytes + length <= usage.audioQuotaBytes) return false;
                  evictionAttempted = true;
                  await _evictFor(length, epoch, current, excluding: key);
                  return reserveChunk();
                }
              : null,
        );
        if (!current() || !await readAllowedNow()) return null;
        final published = await bytes.publish(
          staged,
          onStorageQuotaExceeded: evictOnStorageQuota,
          recordReadyIfCurrent: (ready) async {
            if (!current() || !await readAllowedNow()) return false;
            // AudioBlobStore already holds the partition publish lock here.
            return database.publishAudioReady(
              expectedStorageEpoch: epoch,
              operationId: operationId,
              assetKey: key,
              version: version,
              format: format,
              sha256Hex: sha256Hex,
              actualBytes: ready.byteLength,
              readyReference: ready.reference,
            );
          },
        );
        publishedReady = published != null;
        onEvent?.call('cache.download', {'result': published == null ? 'failure' : 'success'});
        return published;
      } finally {
        try {
          // Promotion may have moved the bytes even when index publication
          // failed. Keep the operation charged until every residual reference
          // is confirmed absent.
          final references = publishedReady
              ? <String>[stagingReference]
              : <String>[stagingReference, readyReference];
          String? pending;
          for (final reference in references) {
            final removed = await bytes.tryDeleteReference(reference);
            if (!removed) {
              pending ??= reference;
            }
          }
          if (pending == null) {
            await withCachePartitionPublishLock(scope.partition, () async {
              await database.abandonAudioOperation(epoch, operationId);
              if (await database.clearState() == 'pending') {
                final pendingEpoch = await database.storageEpoch();
                await database.finishPendingCleanup(expectedStorageEpoch: pendingEpoch);
              }
            });
          } else {
            await withCachePartitionPublishLock(
              scope.partition,
              () => database.markAudioOperationDeleting(
                expectedStorageEpoch: epoch,
                operationId: operationId,
                reference: pending!,
                actualBytes: staged?.byteLength ?? writtenBytes,
              ),
            );
            for (final reference in references.where((reference) => reference != pending)) {
              if (await bytes.containsReference(reference)) {
                await withCachePartitionPublishLock(
                  scope.partition,
                  () => database.recordAudioOrphanForDeletion(
                    reference: reference,
                    actualBytes: staged?.byteLength ?? writtenBytes,
                  ),
                );
              }
            }
          }
        } on Object {
          // A closed scope or failed index keeps its operation for recovery.
        }
      }
    });
  }

  Future<T?> read<T>({
    required CacheResource resource,
    required String version,
    required Future<bool> Function() readAllowedNow,
    required Future<T> Function(Stream<List<int>>) consume,
  }) async {
    if (!resource.allowsPersistent(CacheDisposition.validatedAudio)) {
      throw const CacheBlocked('unregistered_audio');
    }
    final epoch = storageEpoch();
    final key = resource.keyFor(scope);
    final generation = authorizationGeneration();
    bool current() => isCurrent(epoch) && authorizationGeneration() == generation;
    if (!current() || !await readAllowedNow()) return null;
    final asset = await database.audioAsset(key);
    if (asset == null || asset.version != version) return null;
    final ready = _ready(asset, epoch);
    return bytes.withReadyStream(
      ready,
      (chunks) async {
        final touched = await withCachePartitionPublishLock(
          scope.partition,
          () async =>
              current() &&
              await database.touchAudioIfCurrent(asset.assetKey, asset.reference, epoch),
        );
        if (!touched || !current()) throw const CacheBlocked('audio_not_authorized');
        return consume(chunks);
      },
      readAllowedIfCurrent: (_) async => current() && await readAllowedNow(),
      authorizationChanges: authorizationChanges,
      onInvalidBytes: () => _markBroken(asset, epoch),
    );
  }

  /// Attempts retired byte cleanup without taking the partition publish lock
  /// around a platform delete. A busy owner remains charged for later retry.
  Future<void> cleanupRetiredOperations({String? assetKey}) async {
    final operations = assetKey == null
        ? await database.audioOperations()
        : await database.audioOperationsForAsset(assetKey);
    for (final operation in operations) {
      if (!operation.isDeleting) continue;
      await bytes.withOperationLock(operation.operationId, () async {
        Future<bool> stillDeleting() async =>
            (await database.audioOperationsForAsset(operation.assetKey)).any(
              (candidate) =>
                  candidate.operationId == operation.operationId &&
                  candidate.storageEpoch == operation.storageEpoch &&
                  candidate.reference == operation.reference &&
                  candidate.isDeleting,
            );
        if (!await withCachePartitionPublishLock(scope.partition, stillDeleting)) return true;
        final promotedReference = bytes.readyReference(
          operation.storageEpoch,
          operation.operationId,
          operation.assetKey,
        );
        final published = await database.audioAsset(
          operation.assetKey,
          includeBroken: true,
          includeDeleting: true,
        );
        final references = <String>{
          if (operation.reference.isNotEmpty) operation.reference,
          if (published?.reference != promotedReference) promotedReference,
        };
        final failed = <String>[];
        for (final reference in references) {
          if (!await bytes.tryDeleteReference(reference)) failed.add(reference);
        }
        final failedLengths = <String, int>{};
        for (final reference in failed) {
          failedLengths[reference] = await bytes.referenceLength(reference);
        }
        await withCachePartitionPublishLock(scope.partition, () async {
          if (!await stillDeleting()) return;
          if (failed.isEmpty) {
            await database.completeAudioOperationDeletion(
              expectedStorageEpoch: operation.storageEpoch,
              operationId: operation.operationId,
              expectedReference: operation.reference,
            );
            return;
          }
          if (failed.first != operation.reference) {
            await database.reconcileRetiredAudioOperation(
              expectedStorageEpoch: operation.storageEpoch,
              operationId: operation.operationId,
              expectedReference: operation.reference,
              remainingReference: failed.first,
              actualBytes: failedLengths[failed.first]!,
            );
          } else {
            await database.reconcileRetiredAudioOperation(
              expectedStorageEpoch: operation.storageEpoch,
              operationId: operation.operationId,
              expectedReference: operation.reference,
              remainingReference: operation.reference,
              actualBytes: failedLengths[operation.reference]!,
            );
          }
          for (final reference in failed.skip(1)) {
            await database.recordAudioOrphanForDeletion(
              reference: reference,
              actualBytes: failedLengths[reference]!,
            );
          }
        });
        return true;
      }, ifAvailable: true);
    }
  }

  Future<AudioRecoveryReport> recover() async {
    // Capture a coherent index and reference set, then hash outside both
    // partition locks. The second short lock rechecks identity before any
    // deletion so a newly published ready reference cannot become an orphan.
    final snapshot = await bytes.withPublishLock(
      () => withCachePartitionRecoveryIndexLock(
        scope.partition,
        () async => (
          assets: await database.readyAudioAssets(includeBroken: true),
          operations: await database.audioOperations(),
          deletingReferences: await database.pendingAudioDeletions(),
          epoch: await database.storageEpoch(),
          references: await bytes.references(),
        ),
      ),
    );
    final broken = <String>{};
    for (final asset in snapshot.assets) {
      if (!snapshot.references.contains(asset.reference) ||
          !await bytes.verify(_ready(asset, snapshot.epoch))) {
        broken.add(asset.reference);
      }
    }
    final originalKeep = {
      for (final asset in snapshot.assets) asset.reference,
      for (final operation in snapshot.operations) operation.reference,
      ...snapshot.deletingReferences,
    };
    final orphanLengths = <String, int>{};
    for (final reference in snapshot.references.difference(originalKeep)) {
      orphanLengths[reference] = await bytes.referenceLength(reference);
    }

    final deleted = <String>{};
    final pending = <String>{};
    Future<T> shortLock<T>(Future<T> Function() action) =>
        bytes.withPublishLock(() => withCachePartitionRecoveryIndexLock(scope.partition, action));
    for (final asset in snapshot.assets) {
      if (!broken.contains(asset.reference)) continue;
      await shortLock(() async {
        if (await database.storageEpoch() != snapshot.epoch) return;
        final live = await database.audioAsset(asset.assetKey, includeBroken: true);
        if (live == null ||
            live.reference != asset.reference ||
            live.version != asset.version ||
            live.sha256 != asset.sha256 ||
            live.bytes != asset.bytes) {
          return;
        }
        final missing = !await bytes.containsReference(asset.reference);
        await database.markAudioBroken(
          asset.assetKey,
          asset.reference,
          expectedStorageEpoch: snapshot.epoch,
          missing: missing,
        );
        if (await bytes.tryDeleteReady(_ready(asset, snapshot.epoch))) {
          await database.forgetAudioAssetIfCurrent(asset.assetKey, asset.reference);
        }
      });
    }
    for (final entry in orphanLengths.entries) {
      await shortLock(() async {
        if (await database.storageEpoch() != snapshot.epoch) return;
        final reference = entry.key;
        final liveKeep = {
          for (final asset in await database.readyAudioAssets(includeBroken: true)) asset.reference,
          for (final operation in await database.audioOperations()) operation.reference,
          ...await database.pendingAudioDeletions(),
        };
        if (liveKeep.contains(reference) || !await bytes.containsReference(reference)) return;
        if (await bytes.tryDeleteReference(reference)) {
          deleted.add(reference);
        } else {
          pending.add(reference);
          await database.recordAudioOrphanForDeletion(
            reference: reference,
            actualBytes: entry.value,
          );
        }
      });
    }
    for (final operation in snapshot.operations) {
      await shortLock(() async {
        if (await database.storageEpoch() != snapshot.epoch) return;
        final live = (await database.audioOperationsForAsset(operation.assetKey))
            .where((candidate) => candidate.operationId == operation.operationId)
            .firstOrNull;
        if (live == null ||
            live.storageEpoch != operation.storageEpoch ||
            live.reference != operation.reference ||
            live.state != operation.state) {
          return;
        }
        // This is nonblocking: an active owner keeps its stage and slot.
        await bytes.withOperationLock(operation.operationId, () async {
          if (operation.reference.isEmpty || await bytes.tryDeleteReference(operation.reference)) {
            if (operation.isDeleting) {
              await database.completeAudioOperationDeletion(
                expectedStorageEpoch: operation.storageEpoch,
                operationId: operation.operationId,
                expectedReference: operation.reference,
              );
            } else {
              await database.abandonAudioOperation(operation.storageEpoch, operation.operationId);
            }
          }
          return true;
        }, ifAvailable: true);
      });
    }
    return AudioRecoveryReport(
      missingOrBroken: broken,
      deletedOrphans: deleted,
      pendingDeletion: pending,
    );
  }

  ReadyAudio _ready(StoredAudioAsset asset, String epoch) => ReadyAudio(
    partition: scope.partition,
    storageEpoch: epoch,
    assetKey: asset.assetKey,
    reference: asset.reference,
    byteLength: asset.bytes,
    sha256Hex: asset.sha256,
  );

  Future<void> _markBroken(StoredAudioAsset asset, String epoch) async {
    final missing = !await bytes.containsReference(asset.reference);
    await withCachePartitionPublishLock(
      scope.partition,
      () => database.markAudioBroken(
        asset.assetKey,
        asset.reference,
        expectedStorageEpoch: epoch,
        missing: missing,
      ),
    );
  }

  Future<bool> _evictFor(
    int requiredBytes,
    String epoch,
    bool Function() current, {
    required String excluding,
    bool forceOne = false,
  }) async {
    final usage = await database.usage();
    if (!current() ||
        requiredBytes > usage.audioQuotaBytes ||
        !forceOne && usage.audioBytes + requiredBytes <= usage.audioQuotaBytes) {
      return false;
    }
    final candidates = await database.readyAudioAssets(includeBroken: true);
    for (final asset in candidates) {
      if (!current()) return false;
      if (asset.assetKey == excluding) continue;
      // Nonblocking exclusive resource lock; active players in any tab win.
      if (!await bytes.tryDeleteReady(_ready(asset, epoch))) continue;
      final removed = await withCachePartitionPublishLock(
        scope.partition,
        () => database.forgetAudioAssetIfCurrent(asset.assetKey, asset.reference),
      );
      if (removed) {
        onEvent?.call('cache.evicted', {'result': 'success'});
        if (forceOne) return true;
      }
      final currentUsage = await database.usage();
      if (currentUsage.audioBytes + requiredBytes <= currentUsage.audioQuotaBytes) return true;
    }
    return false;
  }

  Future<void> close() => bytes.close();
}
