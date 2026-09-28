import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
// Drift transports worker errors as a remote cause, including on Web.
// ignore: experimental_member_use
import 'package:drift/remote.dart';

import '../api/responses.dart';
import 'audio_blob_backend.dart';
import 'audio_blob_store.dart';
import 'cache_backend.dart';
import 'cache_audio_manager.dart';
import 'cache_database.dart';
import 'cache_invalidation_channel.dart';
import 'cache_models.dart';
import 'cache_partition_lock.dart';
import 'cache_read_retry.dart';
import 'cache_entry_lock.dart';

bool _isSchemaTooNew(Object error) {
  Object cause = error;
  for (var depth = 0; depth < 8; depth++) {
    if (cause is CacheSchemaTooNew || cause == const CacheSchemaTooNew().toString()) {
      return true;
    }
    if (cause is! DriftRemoteException) return false;
    cause = cause.remoteCause;
  }
  return false;
}

const _sharedDependencyTags = {
  'material:list',
  'collection:list',
  'vocabulary_notebook:list',
  'notification:list',
  'settings:profile',
  'settings:study-profile',
  'settings:preferences',
};

abstract interface class CacheRemote<T> {
  Future<CacheValidation> validate(CacheResource resource, CacheVersion known, CancelToken cancel);
  Future<CachePayload<T>> fetch(CacheResource resource, CancelToken cancel);
}

final class CacheReadLease<T> {
  CacheReadLease._(this.future, this._release);
  final Future<CacheView<T>> future;
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

final class CachePin {
  CachePin._(this._release);
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

final class CacheClearResult {
  const CacheClearResult({required this.deletedAudio, required this.pendingAudio});
  final int deletedAudio;
  final int pendingAudio;
}

final class _Flight<T> {
  _Flight(this.key, this.tags);
  final String key;
  final Set<String> tags;
  final CancelToken cancel = CancelToken();
  late final Future<CacheView<T>> future;
  int consumers = 0;
  bool retired = false;
}

final class _MemoryEntry<T> {
  const _MemoryEntry(
    this.data,
    this.version,
    this.tags,
    this.validatedAt, {
    this.pendingPublication = false,
    this.storageEpoch,
    this.expectedEntryKey,
    this.expectedPublicationEpoch = 0,
    this.expectedInvalidations = const {},
  });
  final T data;
  final CacheVersion version;
  final Set<String> tags;
  final DateTime validatedAt;
  final bool pendingPublication;
  final String? storageEpoch;
  final String? expectedEntryKey;
  final int expectedPublicationEpoch;
  final Map<String, int> expectedInvalidations;
}

final class _GrantAnchor {
  _GrantAnchor(this.grant, Duration roundTrip, [_GrantAnchor? previous])
    : serverUpperAtAccept = _maxTime(
        grant.serverTime.add(roundTrip),
        previous?.serverUpperAtAccept.add(previous.elapsed.elapsed),
      ),
      elapsed = Stopwatch()..start();
  final CacheGrant grant;
  final DateTime serverUpperAtAccept;
  final Stopwatch elapsed;

  static DateTime _maxTime(DateTime current, DateTime? previous) =>
      previous != null && previous.isAfter(current) ? previous : current;

  bool allows(CacheScope scope, String key, CacheVersion version) {
    final granted = grant.version;
    return grant.scopeBinding == scope.binding &&
        grant.resourceKey == key &&
        granted.resource == version.resource &&
        granted.representation == version.representation &&
        granted.artifact == version.artifact &&
        granted.nlp == version.nlp &&
        granted.binding == version.binding &&
        scope.securityEpoch >= 0 &&
        scope.authzVersion > 0 &&
        scope.policyVersion > 0 &&
        grant.securityEpoch == scope.securityEpoch &&
        grant.authzVersion == scope.authzVersion &&
        grant.policyVersion == scope.policyVersion &&
        serverUpperAtAccept.add(elapsed.elapsed).isBefore(grant.expiresAt);
  }
}

/// Owns all private cache reads, publication, invalidation and scope disposal.
final class CacheCoordinator {
  CacheCoordinator({
    Future<OpenedCacheBackend> Function(String)? openBackend,
    Future<OpenedCacheBackend> Function()? openMemoryBackend,
    this.onEvent,
    Future<void> Function(Duration)? retryDelay,
  }) : _openBackend = openBackend ?? openCacheBackend,
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _openMemoryBackend = openMemoryBackend ?? openMemoryCacheBackend;

  final Future<OpenedCacheBackend> Function(String) _openBackend;
  final Future<OpenedCacheBackend> Function() _openMemoryBackend;
  final Future<void> Function(Duration) _retryDelay;
  final void Function(String event, Map<String, Object?> attributes)? onEvent;
  CacheScope? _scope;
  CacheDatabase? _database;
  OpenedCacheBackend? _backend;
  CacheAudioManager? _audio;
  CacheInvalidationChannel? _channel;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  String _storageEpoch = '';
  Map<String, int> _knownInvalidations = {};
  final Set<String> _unsafeDependencies = {};
  bool _unsafeAllDependencies = false;
  final Map<String, int> _inFlightInvalidations = {};
  final Map<String, int> _unsafeDependencyVersions = {};
  int _invalidationAttempt = 0;
  int _accountGeneration = 0;
  int _scopeGeneration = 0;
  int _invalidationGeneration = 0;
  Set<String>? _lastInvalidatedTags;
  final Map<String, int> _dependencyRevisions = {};
  int _unknownDependencyRevision = 0;
  bool _offline = false;
  bool _leaseForeground = true;
  int _leaseRevision = 0;
  bool _blocked = true;
  bool _storageClearing = false;
  int _storageRevision = 0;
  String? _terminalReason;
  final _flights = <String, _Flight<dynamic>>{};
  final _memory = <String, _MemoryEntry<dynamic>>{};
  final _pins = <String, int>{};
  final _activePins = <CachePin>{};
  final _grants = <String, _GrantAnchor>{};
  final _deniedLogicalGrants = <String>{};
  final _deniedExactGrants = <String>{};
  final _reauthorizedExactGrants = <String, Set<String>>{};
  bool _denyAllOfflineGrants = false;
  _GrantAnchor? _latestServerAnchor;
  final _readGeneration = <String, int>{};
  final _policies = <String, Object>{};
  Future<void> _scopeTransitionTail = Future<void>.value();
  int _lifecycleRevision = 0;
  final _tagsByKey = <String, Set<String>>{};
  bool _persistenceSuspended = false;
  final _explicitPersistenceKeys = <String>{};

  CacheScope? get scope => _scope;
  bool get accessReady => _scope != null && !_blocked;
  bool get displayAuthorized =>
      _scope != null && (!_blocked || _storageClearing) && _terminalReason == null;
  int get storageRevision => _storageRevision;
  bool get isOffline => _offline;
  CacheStorageMode get storageMode => _backend?.mode ?? CacheStorageMode.memoryOnly;
  String? get degradedReason => _terminalReason ?? _backend?.degradedReason;
  String? get terminalReason => _terminalReason;
  int get accountGeneration => _accountGeneration;
  int get scopeGeneration => _scopeGeneration;
  int get invalidationGeneration => _invalidationGeneration;

  /// Tags for the latest invalidation generation. Null means that a cross-tab
  /// hint did not identify its dependencies, so visible lists must recheck.
  Set<String>? get lastInvalidatedTags => _lastInvalidatedTags;
  bool dependenciesSafe(Set<String> tags) =>
      !_unsafeAllDependencies && tags.intersection(_unsafeDependencies).isEmpty;
  (int, int) dependencyRevision(String tag) =>
      (_unknownDependencyRevision, _dependencyRevisions[tag] ?? 0);
  CacheAudioManager? get audio => _audio;
  Stream<void> get changes => _changes.stream;

  /// Device-local figures only. The server's saved learning results are not
  /// inferred from this cache index.
  Future<CacheUsage> usage() async {
    final database = _database;
    final generation = _accountGeneration;
    if (_scope == null || database == null || _blocked) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    final value = await database.usage();
    if (_accountGeneration != generation || _blocked) {
      throw const CacheBlocked('scope_changed');
    }
    return value;
  }

  /// Changes only this account partition's local capacity preferences.
  Future<CacheUsage> setQuotas({int? textBytes, int? audioBytes}) async {
    final scope = _scope;
    final database = _database;
    final generation = _accountGeneration;
    final epoch = _storageEpoch;
    if (scope == null || database == null || _blocked) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    Future<CacheUsage> update() async {
      if (_scope?.binding != scope.binding ||
          _accountGeneration != generation ||
          _storageEpoch != epoch ||
          _blocked) {
        throw const CacheBlocked('scope_changed');
      }
      await database.setQuotas(textBytes: textBytes, audioBytes: audioBytes);
      return database.usage();
    }

    final result = storageMode == CacheStorageMode.persistent
        ? await withCachePartitionPublishLock(scope.partition, update)
        : await update();
    if (_scope?.binding != scope.binding || _accountGeneration != generation || _blocked) {
      throw const CacheBlocked('scope_changed');
    }
    _changes.add(null);
    return result;
  }

  void register<T>(CachePolicy<T> policy) {
    if (_policies.containsKey(policy.kind)) {
      throw StateError('Duplicate cache policy: ${policy.kind}');
    }
    if (policy.persistent && !CacheResource.allowsPersistentKind(policy.kind, policy.disposition)) {
      throw StateError('Persistent cache policy is not registered for ${policy.kind}');
    }
    _policies[policy.kind] = policy;
  }

  /// A visible reader or active player holds this lease while using a local
  /// result. Ordinary LRU admission cannot evict the matching disk entry.
  Future<CachePin> pin(CacheResource resource) async {
    await synchronizeStorage();
    final scope = _scope;
    if (scope == null || _blocked) throw const CacheBlocked('identity_unconfirmed');
    if (!_policies.containsKey(resource.kind)) throw const CacheBlocked('unregistered_resource');
    final key = resource.keyFor(scope);
    final generation = _scopeGeneration;
    final storageRevision = _storageRevision;
    final storageEpoch = _storageEpoch;
    final releaseLock = storageMode == CacheStorageMode.persistent
        ? await acquireCacheEntryPin(scope.partition, key)
        : () {};
    String? pinnedExact;
    void Function()? releaseExact;
    final database = _database;
    if (storageMode == CacheStorageMode.persistent && database != null) {
      try {
        await withCachePartitionPublishLock(scope.partition, () async {
          final snapshot = await database.snapshot(key, _policyDependencies(resource));
          pinnedExact = snapshot.entry?.entryKey;
          if (pinnedExact != null) {
            releaseExact = await acquireCacheEntryPin(scope.partition, pinnedExact!);
          }
        });
      } on Object {
        releaseExact?.call();
        releaseLock();
        rethrow;
      }
    }
    if (_scopeGeneration != generation ||
        _storageRevision != storageRevision ||
        _storageEpoch != storageEpoch ||
        _blocked) {
      releaseExact?.call();
      releaseLock();
      throw const CacheBlocked('scope_changed');
    }
    _pins[key] = (_pins[key] ?? 0) + 1;
    if (pinnedExact != null) _pins[pinnedExact!] = (_pins[pinnedExact!] ?? 0) + 1;
    late final CachePin pin;
    pin = CachePin._(() {
      releaseExact?.call();
      releaseLock();
      _activePins.remove(pin);
      final count = _pins[key] ?? 0;
      if (count <= 1) {
        _pins.remove(key);
      } else {
        _pins[key] = count - 1;
      }
      if (pinnedExact != null) {
        final exactCount = _pins[pinnedExact!] ?? 0;
        if (exactCount <= 1) {
          _pins.remove(pinnedExact!);
        } else {
          _pins[pinnedExact!] = exactCount - 1;
        }
      }
      _pruneIdleMetadata(key);
      final database = _database;
      if (database != null) _scheduleRetiredCleanup(scope, database);
    });
    _activePins.add(pin);
    return pin;
  }

  /// Leases the exact completed row represented by an accepted view. The
  /// acquisition rechecks the row after taking the shared eviction pin, so a
  /// read cannot report a visible local copy that vanished in the handoff.
  Future<CachePin> pinVersion(CacheView<dynamic> view) async {
    final resource = view.resource;
    final version = view.version;
    final exact = view.entryKey;
    final publication = view.publicationEpoch;
    if (resource == null || version == null || exact == null || publication == null) {
      throw const CacheBlocked('entry_not_persisted');
    }
    final scope = _scope;
    final database = _database;
    final generation = _accountGeneration;
    final epoch = _storageEpoch;
    if (scope == null || database == null || _blocked || !view.localReady) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    final logical = resource.keyFor(scope);
    if (cacheEntryKey(logical, version) != exact) {
      throw const CacheBlocked('entry_identity_changed');
    }
    final releaseLock = await acquireCacheEntryPin(scope.partition, exact);
    try {
      final snapshot = await withCachePartitionPublishLock(
        scope.partition,
        () => database.snapshot(logical, _policyDependencies(resource), version: version),
      );
      if (_accountGeneration != generation ||
          _scope?.binding != scope.binding ||
          _storageEpoch != epoch ||
          _blocked ||
          snapshot.storageEpoch != epoch ||
          snapshot.entry?.entryKey != exact ||
          snapshot.entry == null ||
          !_sameVersion(snapshot.entry!.version, version)) {
        throw const CacheBlocked('entry_identity_changed');
      }
      _tagsByKey[logical] = _policyDependencies(resource);
      _pins[logical] = (_pins[logical] ?? 0) + 1;
      _pins[exact] = (_pins[exact] ?? 0) + 1;
      late final CachePin pin;
      pin = CachePin._(() {
        releaseLock();
        _activePins.remove(pin);
        final count = _pins[exact] ?? 0;
        if (count <= 1) {
          _pins.remove(exact);
        } else {
          _pins[exact] = count - 1;
        }
        final logicalCount = _pins[logical] ?? 0;
        if (logicalCount <= 1) {
          _pins.remove(logical);
        } else {
          _pins[logical] = logicalCount - 1;
        }
        _pruneIdleMetadata(logical);
        _scheduleRetiredCleanup(scope, database);
      });
      _activePins.add(pin);
      return pin;
    } on Object {
      releaseLock();
      rethrow;
    }
  }

  Set<String> _policyDependencies(CacheResource resource) {
    final policy = _policies[resource.kind];
    if (policy is CachePolicy<dynamic>) return policy.dependencies(resource);
    throw const CacheBlocked('unregistered_resource');
  }

  void _releasePins() {
    for (final pin in _activePins.toList()) {
      pin.release();
    }
  }

  Future<void Function()?> _tryEvictionLocks(
    String partition,
    String exactKey,
    String? logicalKey,
  ) async {
    final releaseLogical = logicalKey == null
        ? null
        : await tryCacheEntryEviction(partition, logicalKey);
    if (logicalKey != null && releaseLogical == null) return null;
    final releaseExact = await tryCacheEntryEviction(partition, exactKey);
    if (releaseExact == null) {
      releaseLogical?.call();
      return null;
    }
    return () {
      releaseExact();
      releaseLogical?.call();
    };
  }

  void _scheduleRetiredCleanup(CacheScope scope, CacheDatabase database) {
    unawaited(() async {
      if (_scope?.binding != scope.binding || !identical(_database, database)) return;
      try {
        await withCachePartitionPublishLock(
          scope.partition,
          () => database.pruneRetiredEntries(
            acquireEviction: (exact, logical) => _tryEvictionLocks(scope.partition, exact, logical),
          ),
        );
      } on Object {
        // A later mutation or release retries retired rows; never revive them.
      }
    }());
  }

  Future<T> _scopeTransition<T>(Future<T> Function() operation) async {
    final previous = _scopeTransitionTail;
    final done = Completer<void>();
    _scopeTransitionTail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  Future<void> attach(CacheScope confirmedScope, {bool revokePreviousGrants = false}) {
    final revision = ++_lifecycleRevision;
    return _scopeTransition(() => _attachScope(confirmedScope, revision, revokePreviousGrants));
  }

  Future<void> _attachScope(
    CacheScope confirmedScope,
    int revision,
    bool revokePreviousGrants,
  ) async {
    if (revision != _lifecycleRevision) throw const CacheBlocked('scope_changed');
    await _closeScope();
    if (revision != _lifecycleRevision) throw const CacheBlocked('scope_changed');
    late OpenedCacheBackend backend;
    try {
      backend = await _openBackend(confirmedScope.partition);
    } on CacheBlocked catch (error) {
      _terminalReason = error.reason;
      _changes.add(null);
      rethrow;
    } on Object catch (error) {
      if (!_isSchemaTooNew(error)) rethrow;
      _terminalReason = 'cache_update_required';
      _changes.add(null);
      throw const CacheBlocked('cache_update_required');
    }
    var database = CacheDatabase(
      backend.executor,
      onCorruptEntry: () => onEvent?.call('cache.storage.degraded', {'reason': 'invalid_payload'}),
      onMigration: () => onEvent?.call('schema.migration', {'result': 'success'}),
      onEvicted: () => onEvent?.call('cache.evicted', {'result': 'success'}),
    );
    Future<void> closeCandidate(CacheDatabase candidate, OpenedCacheBackend owner) async {
      try {
        await candidate.close();
      } finally {
        await owner.closeOwner();
      }
    }

    late String epoch;
    try {
      epoch = backend.mode == CacheStorageMode.persistent
          ? await withCachePartitionPublishLock(confirmedScope.partition, database.storageEpoch)
          : await database.storageEpoch();
    } on Object catch (error) {
      if (!_isSchemaTooNew(error)) {
        final failedPersistent = backend.mode == CacheStorageMode.persistent;
        await closeCandidate(database, backend);
        if (!failedPersistent) rethrow;
        backend = await _openMemoryBackend();
        if (backend.mode != CacheStorageMode.memoryOnly) {
          try {
            await backend.executor.close();
          } finally {
            await backend.closeOwner();
          }
          throw StateError('Cache fallback must be memory only');
        }
        database = CacheDatabase(
          backend.executor,
          onCorruptEntry: () =>
              onEvent?.call('cache.storage.degraded', {'reason': 'invalid_payload'}),
          onMigration: () => onEvent?.call('schema.migration', {'result': 'success'}),
          onEvicted: () => onEvent?.call('cache.evicted', {'result': 'success'}),
        );
        try {
          epoch = await database.storageEpoch();
        } on Object {
          await closeCandidate(database, backend);
          rethrow;
        }
      } else {
        await closeCandidate(database, backend);
        _terminalReason = 'cache_update_required';
        _changes.add(null);
        throw const CacheBlocked('cache_update_required');
      }
    }
    CacheAudioManager? candidateAudio;
    CacheInvalidationChannel? candidateChannel;
    var published = false;
    var suspended = false;
    try {
      if (revokePreviousGrants) {
        if (backend.mode == CacheStorageMode.persistent) {
          await withCachePartitionPublishLock(
            confirmedScope.partition,
            database.clearOfflineGrants,
          );
        } else {
          await database.clearOfflineGrants();
        }
      }
      final invalidations = await database.allInvalidationEpochs();
      if (backend.mode == CacheStorageMode.persistent) {
        try {
          final byteBackend = await openAudioByteBackend(confirmedScope.partition);
          candidateAudio = CacheAudioManager(
            scope: confirmedScope,
            database: database,
            bytes: AudioBlobStore(confirmedScope, byteBackend),
            storageEpoch: () => published ? _storageEpoch : epoch,
            authorizationGeneration: () => _accountGeneration,
            persistenceSuspended: () => _persistenceSuspended,
            authorizationChanges: _changes.stream,
            onEvent: onEvent,
            isCurrent: (capturedEpoch) =>
                _scope?.binding == confirmedScope.binding &&
                _storageEpoch == capturedEpoch &&
                !_blocked,
          );
          if (await database.clearState() != 'ready') {
            suspended = true;
            await _drainPendingAudioDeletions(
              confirmedScope,
              database,
              candidateAudio,
              expectedStorageEpoch: epoch,
              persistent: true,
            );
          }
          if (await database.clearState() == 'ready') await candidateAudio.recover();
        } on Object {
          final failedAudio = candidateAudio;
          candidateAudio = null;
          await failedAudio?.close();
          onEvent?.call('cache.storage.degraded', {'reason': 'audio_unavailable'});
        }
      } else {
        onEvent?.call('cache.storage.degraded', {
          'reason':
              backend.degradedReason == 'cache_writer_unavailable' ||
                  backend.degradedReason == 'persistent_schema_unavailable'
              ? 'writer_unavailable'
              : 'browser_storage_unsafe',
        });
      }
      candidateChannel = CacheInvalidationChannel(
        confirmedScope.partition,
        handleExternalCacheHint,
      );
      if (revision != _lifecycleRevision) throw const CacheBlocked('scope_changed');
      _scope = confirmedScope;
      _terminalReason = null;
      _backend = backend;
      _database = database;
      _audio = candidateAudio;
      _channel = candidateChannel;
      _storageEpoch = epoch;
      _knownInvalidations = _boundedInvalidations(invalidations);
      _unsafeDependencies.clear();
      _unsafeAllDependencies = false;
      _inFlightInvalidations.clear();
      _unsafeDependencyVersions.clear();
      _offline = false;
      _blocked = false;
      _persistenceSuspended = suspended;
      _explicitPersistenceKeys.clear();
      published = true;
      _changes.add(null);
    } on Object {
      if (published) {
        await _closeScope();
      } else {
        candidateChannel?.close();
        try {
          await candidateAudio?.close();
        } finally {
          await closeCandidate(database, backend);
        }
      }
      rethrow;
    }
  }

  Future<void> closeScope() {
    _lifecycleRevision++;
    // The queued close may wait for an earlier attachment. Hide the outgoing
    // identity before returning to callers or notifying domain repositories.
    _accountGeneration++;
    _blocked = true;
    _storageClearing = false;
    _offline = false;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('scope_closed');
    }
    _flights.clear();
    _memory.clear();
    _grants.clear();
    _latestServerAnchor = null;
    _releasePins();
    _changes.add(null);
    return _scopeTransition(() => _closeScope(skipGeneration: true));
  }

  Future<void> _closeScope({bool skipGeneration = false}) async {
    if (!skipGeneration) _accountGeneration++;
    _scopeGeneration++;
    _blocked = true;
    _storageClearing = false;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('scope_closed');
    }
    _flights.clear();
    _memory.clear();
    _releasePins();
    _grants.clear();
    _latestServerAnchor = null;
    _tagsByKey.clear();
    _clearOfflineDenials();
    _readGeneration.clear();
    _explicitPersistenceKeys.clear();
    _persistenceSuspended = false;
    _scope = null;
    _changes.add(null);
    final database = _database;
    final backend = _backend;
    final audio = _audio;
    final channel = _channel;
    _database = null;
    _backend = null;
    _audio = null;
    _channel = null;
    _storageEpoch = '';
    _knownInvalidations = {};
    _unsafeDependencies.clear();
    _unsafeAllDependencies = false;
    _dependencyRevisions.clear();
    _unknownDependencyRevision++;
    _inFlightInvalidations.clear();
    _unsafeDependencyVersions.clear();
    channel?.close();
    try {
      if (audio != null) await audio.close();
    } finally {
      try {
        if (database != null) await database.close();
      } finally {
        if (backend != null) await backend.closeOwner();
      }
    }
  }

  /// Call only after establishing true network unreachability. Timeouts, 5xx,
  /// 429 and identity uncertainty do not authorize offline reads.
  void enterOfflineForUnreachableNetwork() {
    if (!_blocked && _scope != null && _leaseForeground) _offline = true;
  }

  /// Foreground transitions invalidate this run's monotonic grant clock, but
  /// leave confirmed online bodies and visible pins in place.
  void setOfflineLeaseForeground(bool foreground) {
    _leaseForeground = foreground;
    _leaseRevision++;
    _offline = false;
    _grants.clear();
    _latestServerAnchor = null;
  }

  void requireOnlineRevalidation() {
    _lifecycleRevision++;
    _accountGeneration++;
    _offline = false;
    _blocked = true;
    _storageClearing = false;
    _grants.clear();
    _latestServerAnchor = null;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('access_revalidation_required');
    }
    _flights.clear();
    _changes.add(null);
  }

  void completeOnlineRevalidation(CacheScope confirmedScope) {
    if (_terminalReason != null) throw CacheBlocked(_terminalReason!);
    if (_scope?.binding != confirmedScope.binding) {
      blockForAuthorizationFailure();
      throw const CacheBlocked('scope_changed');
    }
    if (_scope?.securityEpoch != confirmedScope.securityEpoch ||
        _scope?.authzVersion != confirmedScope.authzVersion ||
        _scope?.policyVersion != confirmedScope.policyVersion) {
      blockForAuthorizationFailure();
      throw const CacheBlocked('authorization_changed');
    }
    _offline = false;
    _blocked = false;
    _changes.add(null);
  }

  /// A policy/security revision closes all old leases without deleting saved
  /// text or audio. Only a fresh online validation can issue new grants.
  Future<void> updateConfirmedAuthorization(CacheScope confirmedScope) async {
    if (_terminalReason != null) throw CacheBlocked(_terminalReason!);
    final current = _scope;
    final database = _database;
    if (current?.binding != confirmedScope.binding || database == null) {
      throw const CacheBlocked('scope_changed');
    }
    blockForAuthorizationFailure();
    final generation = _accountGeneration;
    _releasePins();
    try {
      await withCachePartitionPublishLock(current!.partition, database.clearOfflineGrants);
      if (!identical(database, _database) ||
          _scope?.binding != confirmedScope.binding ||
          _accountGeneration != generation) {
        throw const CacheBlocked('scope_changed');
      }
      _scope = confirmedScope;
      _scopeGeneration++;
      _blocked = false;
      _changes.add(null);
    } on Object {
      // A failed durable revoke leaves the partition closed until it succeeds.
      rethrow;
    }
  }

  void blockForAuthorizationFailure() {
    _lifecycleRevision++;
    _accountGeneration++;
    _offline = false;
    _blocked = true;
    _storageClearing = false;
    _grants.clear();
    _latestServerAnchor = null;
    _memory.clear();
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('authorization_failed');
    }
    _flights.clear();
    _changes.add(null);
  }

  /// A cross-tab hint only invalidates local state; it never supplies access.
  /// The channel and future platform transports share this fail-closed path.
  void handleExternalCacheHint(String type, [Set<String>? tags]) {
    if (type != 'invalidate' && type != 'clear' && type != 'identity') return;
    if (_scope == null) return;
    if (type == 'invalidate') {
      final expanded = tags == null ? null : <String>{...tags};
      if (expanded != null) {
        for (final known in _tagsByKey.values.expand((value) => value)) {
          if (tags!.contains('learning-result:*') && known.startsWith('learning-result:') ||
              tags.contains('material:*') && known.startsWith('material:')) {
            expanded.add(known);
          }
        }
      }
      _invalidationGeneration++;
      _lastInvalidatedTags = expanded == null ? null : Set.unmodifiable(expanded);
      if (expanded == null) {
        _unknownDependencyRevision++;
      } else {
        final tracked = _tagsByKey.values.expand((value) => value).toSet();
        for (final tag in expanded) {
          if (tracked.contains(tag) || _sharedDependencyTags.contains(tag)) {
            _dependencyRevisions[tag] = (_dependencyRevisions[tag] ?? 0) + 1;
          }
        }
      }
      for (final entry in _tagsByKey.entries.toList()) {
        if (expanded == null || entry.value.intersection(expanded).isNotEmpty) {
          _retireKey(entry.key);
          _memory.remove(entry.key);
          _retireGrantsForLogical(entry.key);
          _pruneIdleMetadata(entry.key);
        }
      }
      _changes.add(null);
      return;
    }
    final canRestoreAccess = displayAuthorized;
    if (type == 'identity') _accountGeneration++;
    if (type == 'clear') {
      _storageRevision++;
      _storageClearing = canRestoreAccess;
    } else {
      _storageClearing = false;
    }
    final signalGeneration = _accountGeneration;
    final signalStorageRevision = _storageRevision;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('cross_tab_change');
    }
    _flights.clear();
    _memory.clear();
    _releasePins();
    _grants.clear();
    _latestServerAnchor = null;
    _readGeneration.clear();
    _clearOfflineDenials();
    if (type == 'identity') {
      _blocked = true;
      _changes.add(null);
      return;
    }
    if (type == 'clear') {
      _blocked = true;
      _changes.add(null);
      final scope = _scope!;
      final database = _database!;
      unawaited(() async {
        try {
          final epoch = await database.storageEpoch();
          if (_scope?.binding != scope.binding ||
              _accountGeneration != signalGeneration ||
              _storageRevision != signalStorageRevision) {
            return;
          }
          _storageEpoch = epoch;
          _offline = false;
          _persistenceSuspended = true;
          _explicitPersistenceKeys.clear();
          _blocked = !canRestoreAccess;
          _storageClearing = false;
          _changes.add(null);
        } on Object {
          // Storage uncertainty keeps private reads blocked.
        }
      }());
      return;
    }
    _changes.add(null);
  }

  /// Broadcasts are advisory. Every new read and foreground recovery checks
  /// the durable control row, including for memory-only domain projections.
  Future<void> synchronizeStorage() async {
    final database = _database;
    final scope = _scope;
    final generation = _accountGeneration;
    final storageRevision = _storageRevision;
    if (database == null || scope == null || _blocked) return;
    late final String epoch;
    late final Map<String, int> invalidations;
    try {
      final state = await database.storageState();
      epoch = state.$1;
      invalidations = state.$2;
    } on Object catch (error) {
      if (!_isSchemaTooNew(error)) rethrow;
      if (!identical(database, _database) ||
          _scope?.binding != scope.binding ||
          _accountGeneration != generation ||
          _storageRevision != storageRevision) {
        throw const CacheBlocked('scope_changed');
      }
      _terminalReason = 'cache_update_required';
      await closeScope();
      _changes.add(null);
      throw const CacheBlocked('cache_update_required');
    }
    if (!identical(database, _database) ||
        _scope?.binding != scope.binding ||
        _accountGeneration != generation ||
        _storageRevision != storageRevision ||
        _blocked) {
      throw const CacheBlocked('scope_changed');
    }
    if (epoch != _storageEpoch) {
      _adoptStorageEpoch(epoch);
      _knownInvalidations = _boundedInvalidations(invalidations);
      return;
    }
    _adoptInvalidations(invalidations, withheld: _unsafeDependencies);
    if (_unsafeDependencies.isNotEmpty) {
      final pending = _unsafeDependencies
          .where((tag) => !_inFlightInvalidations.containsKey(tag))
          .toSet();
      if (pending.isEmpty) return;
      final versions = {for (final tag in pending) tag: _unsafeDependencyVersions[tag]};
      try {
        await withCachePartitionPublishLock(
          scope.partition,
          () => database.invalidate(
            pending,
            acquireEviction: (exact, logical) => _tryEvictionLocks(scope.partition, exact, logical),
          ),
        );
        if (!identical(database, _database) || _accountGeneration != generation) {
          throw const CacheBlocked('scope_changed');
        }
        for (final tag in pending) {
          if (_unsafeDependencyVersions[tag] == versions[tag]) {
            _unsafeDependencies.remove(tag);
            _unsafeDependencyVersions.remove(tag);
          }
        }
        final (latestEpoch, latest) = await database.storageState();
        if (!identical(database, _database) ||
            _accountGeneration != generation ||
            _scope?.binding != scope.binding ||
            _storageRevision != storageRevision ||
            _blocked) {
          throw const CacheBlocked('scope_changed');
        }
        if (latestEpoch != _storageEpoch) {
          _adoptStorageEpoch(latestEpoch);
          _knownInvalidations = _boundedInvalidations(latest);
          return;
        }
        _adoptInvalidations(latest, withheld: _unsafeDependencies);
      } on Object {
        // Affected resources remain locally denied while storage is uncertain.
      }
    }
  }

  void _adoptStorageEpoch(String epoch) {
    _storageRevision++;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('storage_epoch_changed');
    }
    _flights.clear();
    _memory.clear();
    _releasePins();
    _grants.clear();
    _latestServerAnchor = null;
    _readGeneration.clear();
    _tagsByKey.clear();
    _dependencyRevisions.clear();
    _storageEpoch = epoch;
    _knownInvalidations = {};
    _offline = false;
    _persistenceSuspended = true;
    _explicitPersistenceKeys.clear();
    _changes.add(null);
  }

  Set<String> _adoptInvalidations(
    Map<String, int> latest, {
    Set<String> withheld = const {},
    Set<String> alreadySignaled = const {},
    bool notify = true,
  }) {
    final tracked = _trackedDependencyTags();
    final changed = <String>{};
    final accepted = <String, int>{
      for (final entry in _knownInvalidations.entries)
        if (tracked.contains(entry.key)) entry.key: entry.value,
    };
    for (final entry in latest.entries) {
      if (!tracked.contains(entry.key)) continue;
      if (withheld.contains(entry.key)) continue;
      if (entry.value != (_knownInvalidations[entry.key] ?? 0) &&
          !alreadySignaled.contains(entry.key)) {
        changed.add(entry.key);
      }
      accepted[entry.key] = entry.value;
    }
    _knownInvalidations = accepted;
    if (notify && changed.isNotEmpty) handleExternalCacheHint('invalidate', changed);
    return changed;
  }

  Set<String> _trackedDependencyTags() => {
    ..._sharedDependencyTags,
    ..._unsafeDependencies,
    for (final tags in _tagsByKey.values) ...tags,
  };

  Map<String, int> _boundedInvalidations(Map<String, int> epochs) {
    final tracked = _trackedDependencyTags();
    return {
      for (final entry in epochs.entries)
        if (tracked.contains(entry.key)) entry.key: entry.value,
    };
  }

  CacheReadLease<T> beginRead<T>({
    required CacheResource resource,
    required CacheRemote<T> remote,
    bool forceRefresh = false,
    bool explicitUserAction = false,
    CacheVersion? knownVersion,
  }) {
    final scope = _scope;
    if (scope == null || _blocked) throw const CacheBlocked('identity_unconfirmed');
    final policy = _policies[resource.kind];
    if (policy == null) throw const CacheBlocked('unregistered_resource');
    if (policy is! CachePolicy<T>) throw StateError('Cache policy type mismatch: ${resource.kind}');
    if (policy.persistent && !resource.allowsPersistent(policy.disposition)) {
      throw const CacheBlocked('persistent_projection_forbidden');
    }
    final key = resource.keyFor(scope);
    if (explicitUserAction && _persistenceSuspended) {
      _explicitPersistenceKeys.add(key);
      _retireKey(key);
      if (knownVersion == null ||
          _sameVersion(_memory[key]?.version ?? knownVersion, knownVersion)) {
        _memory.remove(key);
        _grants.remove(key);
      }
    }
    final tags = policy.dependencies(resource);
    if (_offline && !dependenciesSafe(tags)) {
      throw const CacheBlocked('invalidation_not_durable');
    }
    _tagsByKey[key] = tags;
    if (forceRefresh) _retireKey(key);
    final generation = _readGeneration[key] ?? 0;
    final versionKey = knownVersion == null ? '' : cacheEntryKey(key, knownVersion);
    final flightKey =
        '$key:$versionKey:$_accountGeneration:$_storageEpoch:$generation:${_offline ? 1 : 0}';
    var flight = _flights[flightKey] as _Flight<T>?;
    if (flight == null || flight.retired) {
      flight = _Flight<T>(flightKey, tags);
      final created = flight;
      created.future =
          _execute(
            scope: scope,
            resource: resource,
            policy: policy,
            remote: remote,
            key: key,
            generation: generation,
            accountGeneration: _accountGeneration,
            leaseRevision: _leaseRevision,
            storageEpoch: _storageEpoch,
            cancel: created.cancel,
            requestedVersion: knownVersion,
          ).whenComplete(() {
            if (identical(_flights[flightKey], created)) _flights.remove(flightKey);
            if (explicitUserAction &&
                _persistenceSuspended &&
                (_readGeneration[key] ?? 0) == generation) {
              _explicitPersistenceKeys.remove(key);
            }
            _pruneIdleMetadata(key);
          });
      _flights[flightKey] = created;
    }
    flight.consumers++;
    return CacheReadLease._(flight.future, () {
      flight!.consumers--;
      if (flight.consumers == 0 && !flight.retired) {
        flight.retired = true;
        if (identical(_flights[flightKey], flight)) _flights.remove(flightKey);
        flight.cancel.cancel('last_consumer_left');
      }
    });
  }

  Future<CacheView<T>> read<T>({
    required CacheResource resource,
    required CacheRemote<T> remote,
    bool forceRefresh = false,
    bool explicitUserAction = false,
    CacheVersion? knownVersion,
    bool preserveCurrent = false,
    void Function(CacheView<T>)? onView,
  }) async {
    await synchronizeStorage();
    final scope = _scope;
    final account = _accountGeneration;
    final key = scope == null ? null : resource.keyFor(scope);
    final candidate = preserveCurrent && key != null && accessReady
        ? _memory[key] as _MemoryEntry<T>?
        : null;
    final previous =
        candidate != null && (knownVersion == null || _sameVersion(candidate.version, knownVersion))
        ? candidate
        : null;
    if (previous != null && onView != null) {
      onView(
        CacheView(
          data: previous.data,
          source: CacheSource.memory,
          freshness: CacheFreshness.refreshing,
          serverSaved: true,
          localReady: false,
          lastValidatedAt: previous.validatedAt,
          resource: resource,
          version: previous.version,
        ),
      );
    }
    CacheReadLease<T>? lease;
    int? generation;
    try {
      lease = beginRead(
        resource: resource,
        remote: remote,
        forceRefresh: forceRefresh,
        explicitUserAction: explicitUserAction,
        knownVersion: knownVersion,
      );
      generation = key == null ? null : _readGeneration[key] ?? 0;
      final view = await lease.future;
      onView?.call(view);
      return view;
    } on Object catch (error) {
      final keepPrevious =
          previous != null &&
          accessReady &&
          account == _accountGeneration &&
          _scope?.binding == scope?.binding &&
          (_readGeneration[key] ?? 0) == generation &&
          error is! CacheBlocked &&
          cacheReadRetryDelay(error, 0) != null;
      onView?.call(
        CacheView(
          data: keepPrevious ? previous.data : null,
          source: CacheSource.memory,
          freshness: keepPrevious ? CacheFreshness.stale : CacheFreshness.blocked,
          serverSaved: keepPrevious,
          localReady: false,
          lastValidatedAt: keepPrevious ? previous.validatedAt : null,
          error: error,
          resource: resource,
          version: keepPrevious ? previous.version : null,
        ),
      );
      rethrow;
    } finally {
      lease?.release();
    }
  }

  Future<CacheView<T>> _execute<T>({
    required CacheScope scope,
    required CacheResource resource,
    required CachePolicy<T> policy,
    required CacheRemote<T> remote,
    required String key,
    required int generation,
    required int accountGeneration,
    required int leaseRevision,
    required String storageEpoch,
    required CancelToken cancel,
    bool fetchOnly = false,
    CacheVersion? requestedVersion,
  }) async {
    final grantSlot = requestedVersion == null
        ? key
        : '$key:${cacheEntryKey(key, requestedVersion)}';
    bool acceptLeaseGrant() => _leaseForeground && _leaseRevision == leaseRevision;
    bool currentRequest() =>
        _scope?.binding == scope.binding &&
        _accountGeneration == accountGeneration &&
        _storageEpoch == storageEpoch &&
        (_readGeneration[key] ?? 0) == generation &&
        !_blocked &&
        !cancel.isCancelled;
    void checkCurrent() {
      if (!currentRequest()) {
        onEvent?.call('cache.stale_response.discarded', {'result': 'cancelled'});
        throw const CacheBlocked('stale_response');
      }
    }

    Future<CacheReadSnapshot> readSnapshot({CacheVersion? version}) =>
        withCachePartitionPublishLock(scope.partition, () {
          checkCurrent();
          return _database!.snapshot(key, policy.dependencies(resource), version: version);
        });

    var memory = _memory[key] as _MemoryEntry<T>?;
    if (requestedVersion != null &&
        memory != null &&
        !_sameVersion(memory.version, requestedVersion)) {
      memory = null;
    }
    // A failed durable invalidation denies the old disk row and grant, but an
    // online fetch may still show the freshly committed server projection.
    final unsafe = !dependenciesSafe(policy.dependencies(resource));
    if (unsafe) memory = null;
    final useDisk = policy.persistent && storageMode == CacheStorageMode.persistent && !unsafe;
    final mayPublish =
        !unsafe && (!_persistenceSuspended || _explicitPersistenceKeys.contains(key));
    StoredCacheEntry? stored;
    T? storedValue;
    CacheReadSnapshot? diskSnapshot;
    var pendingUsesHeadSnapshot = false;
    _GrantAnchor? grantForPublication(CacheVersion version) {
      if (!acceptLeaseGrant()) return null;
      final direct = _grants[grantSlot];
      if (direct?.allows(scope, key, version) ?? false) return direct;
      // An exact-version retry can inherit only the still-valid grant from
      // the same unpersisted logical candidate, never another head version.
      final exact = cacheEntryKey(key, version);
      if (pendingUsesHeadSnapshot && !_deniedExactGrants.contains(exact)) {
        final pendingGrant = _grants[key];
        if (pendingGrant?.allows(scope, key, version) ?? false) return pendingGrant;
      }
      return null;
    }

    Future<void> verifyAfterStorageFailure({String? publishedKey, String? publishedHash}) async {
      final before = diskSnapshot;
      if (before == null || _database == null) return;
      try {
        final current = await readSnapshot(
          version: pendingUsesHeadSnapshot ? null : requestedVersion,
        );
        checkCurrent();
        if (current.storageEpoch != before.storageEpoch ||
            !_sameInvalidations(current.invalidations, before.invalidations)) {
          throw const CacheBlocked('stale_response');
        }
        final previous = before.entry;
        final now = current.entry;
        final unchanged =
            now?.entryKey == previous?.entryKey &&
            now?.publicationEpoch == previous?.publicationEpoch;
        final ownPublication =
            publishedKey != null &&
            now?.entryKey == publishedKey &&
            now?.payloadHash == publishedHash;
        if (!unchanged && !ownPublication) {
          throw const CacheBlocked('stale_response');
        }
      } on Object catch (error) {
        if (error is CacheBlocked || _isSchemaTooNew(error)) rethrow;
        // An unreadable index cannot overrule the fresh server response. Its
        // offline grant remains denied until a durable write succeeds.
        checkCurrent();
      }
    }

    if (useDisk) {
      diskSnapshot = await readSnapshot(version: requestedVersion);
      checkCurrent();
      if (diskSnapshot.storageEpoch != storageEpoch) {
        _adoptStorageEpoch(diskSnapshot.storageEpoch);
        throw const CacheBlocked('storage_epoch_changed');
      }
      for (final tag in diskSnapshot.invalidations.entries) {
        _knownInvalidations.putIfAbsent(tag.key, () => tag.value);
      }
      stored = diskSnapshot.entry;
      if (diskSnapshot.corruptPublicationEpoch != null) {
        final deleted = await withCachePartitionPublishLock(
          scope.partition,
          () => _database!.deleteEntryIfCurrent(
            expectedStorageEpoch: storageEpoch,
            entryKey: key,
            exactEntryKey: diskSnapshot!.corruptEntryKey,
            requireHead: requestedVersion == null,
            expectedPublicationEpoch: diskSnapshot.corruptPublicationEpoch!,
            expectedPayloadHash: diskSnapshot.corruptPayloadHash,
            expectedPayloadJson: diskSnapshot.corruptPayloadJson,
          ),
        );
        checkCurrent();
        if (!deleted) throw const CacheBlocked('stale_response');
        onEvent?.call('cache.storage.degraded', {'reason': 'invalid_payload'});
        _changes.add(null);
      }
      if (stored != null &&
          (!resource.acceptsStoredKind(stored.kind) ||
              stored.sourceBinding != resource.sourceBinding ||
              stored.projection != resource.projection)) {
        final deleted = await withCachePartitionPublishLock(
          scope.partition,
          () => _database!.deleteEntryIfCurrent(
            expectedStorageEpoch: storageEpoch,
            entryKey: key,
            exactEntryKey: stored!.entryKey,
            requireHead: requestedVersion == null,
            expectedPublicationEpoch: stored.publicationEpoch,
          ),
        );
        checkCurrent();
        if (!deleted) throw const CacheBlocked('stale_response');
        _changes.add(null);
        stored = null;
        diskSnapshot = CacheReadSnapshot(storageEpoch, null, diskSnapshot.invalidations);
      }
      if (stored != null) {
        try {
          storedValue = policy.decode(stored.payload);
        } catch (_) {
          final deleted = await withCachePartitionPublishLock(
            scope.partition,
            () => _database!.deleteEntryIfCurrent(
              expectedStorageEpoch: storageEpoch,
              entryKey: key,
              exactEntryKey: stored!.entryKey,
              requireHead: requestedVersion == null,
              expectedPublicationEpoch: stored.publicationEpoch,
            ),
          );
          checkCurrent();
          if (!deleted) throw const CacheBlocked('stale_response');
          _changes.add(null);
          stored = null;
          diskSnapshot = CacheReadSnapshot(storageEpoch, null, diskSnapshot.invalidations);
          onEvent?.call('cache.storage.degraded', {'reason': 'invalid_payload'});
        }
      }
      var pendingSnapshot = diskSnapshot;
      final pendingCandidate =
          memory != null &&
          memory.pendingPublication &&
          (requestedVersion == null || _sameVersion(memory.version, requestedVersion));
      if (requestedVersion != null && stored == null && pendingCandidate) {
        pendingSnapshot = await readSnapshot();
        checkCurrent();
      }
      final pendingMatches =
          pendingCandidate &&
          memory.storageEpoch == storageEpoch &&
          pendingSnapshot.storageEpoch == storageEpoch &&
          pendingSnapshot.dependenciesCurrent &&
          pendingSnapshot.corruptPublicationEpoch == null &&
          memory.expectedEntryKey == pendingSnapshot.entry?.entryKey &&
          memory.expectedPublicationEpoch == (pendingSnapshot.entry?.publicationEpoch ?? 0) &&
          _sameInvalidations(memory.expectedInvalidations, pendingSnapshot.invalidations) &&
          (requestedVersion == null ||
              _sameInvalidations(diskSnapshot.invalidations, pendingSnapshot.invalidations));
      if (requestedVersion != null && stored == null && pendingMatches) {
        diskSnapshot = pendingSnapshot;
        pendingUsesHeadSnapshot = true;
      }
      if (stored != null &&
              memory != null &&
              !_sameVersion(memory.version, stored.version) &&
              !pendingMatches ||
          stored == null && !pendingMatches) {
        final rejectedPending =
            memory?.pendingPublication == true && _sameVersion(memory!.version, requestedVersion);
        memory = null;
        if (requestedVersion == null || rejectedPending) {
          _memory.remove(key);
        }
        _grants.remove(grantSlot);
      }
    }
    if (requestedVersion != null && stored == null && memory == null) {
      throw const CacheBlocked('version_unavailable');
    }

    Future<(bool, int?)> publishValidatedBody(T value, CacheVersion version) async {
      if (!useDisk || !mayPublish) return (false, null);
      final database = _database!;
      final expected = diskSnapshot!;
      final encoded = policy.encode(value);
      final encodedHash = sha256.convert(utf8.encode(jsonEncode(encoded))).toString();
      CachePublishStatus publication;
      try {
        publication = await withCachePartitionPublishLock(scope.partition, () {
          checkCurrent();
          return database.publish(
            expectedStorageEpoch: storageEpoch,
            entryKey: key,
            kind: resource.kind,
            sourceBinding: resource.sourceBinding,
            projection: resource.projection,
            version: version,
            payload: encoded,
            expectedInvalidations: expected.invalidations,
            expectedPublicationEpoch: expected.entry?.publicationEpoch ?? 0,
            protectedEntryKeys: _pins.keys.toSet(),
            acquireEviction: (exact, logical) => _tryEvictionLocks(scope.partition, exact, logical),
            grant: grantForPublication(version)?.grant,
          );
        });
      } on Object catch (error) {
        if (_isSchemaTooNew(error)) rethrow;
        checkCurrent();
        await verifyAfterStorageFailure(
          publishedKey: cacheEntryKey(key, version),
          publishedHash: encodedHash,
        );
        onEvent?.call('cache.storage.degraded', {'reason': 'writer_unavailable'});
        publication = CachePublishStatus.deferred;
      }
      checkCurrent();
      if (publication == CachePublishStatus.stale) {
        _memory.remove(key);
        _grants.remove(grantSlot);
        throw const CacheBlocked('stale_response');
      }
      var localReady = publication == CachePublishStatus.published;
      int? publishedEpoch;
      if (localReady) {
        CacheReadSnapshot? confirmed;
        try {
          confirmed = await readSnapshot();
        } on Object catch (error) {
          if (_isSchemaTooNew(error)) rethrow;
          checkCurrent();
          onEvent?.call('cache.storage.degraded', {'reason': 'writer_unavailable'});
          localReady = false;
        }
        checkCurrent();
        if (confirmed != null) {
          if (confirmed.storageEpoch != storageEpoch ||
              confirmed.entry?.entryKey != cacheEntryKey(key, version) ||
              !_sameInvalidations(confirmed.invalidations, expected.invalidations)) {
            _memory.remove(key);
            _grants.remove(grantSlot);
            throw const CacheBlocked('stale_response');
          }
          publishedEpoch = confirmed.entry!.publicationEpoch;
        }
      }
      if (localReady) _changes.add(null);
      final persistedGrant = grantForPublication(version);
      if (localReady && persistedGrant != null && persistedGrant.allows(scope, key, version)) {
        final exact = cacheEntryKey(key, version);
        _deniedExactGrants.remove(exact);
        _markReauthorizedExact(key, exact);
      }
      if (publication == CachePublishStatus.quotaExceeded) {
        onEvent?.call('cache.storage.degraded', {'reason': 'quota_exceeded'});
      }
      return (localReady, publishedEpoch);
    }

    if (_offline) {
      if (!acceptLeaseGrant()) throw const CacheBlocked('offline_grant_unavailable');
      final candidate = storedValue;
      final version = stored?.version;
      final exact = stored?.entryKey;
      if (_denyAllOfflineGrants ||
          (exact != null && _deniedExactGrants.contains(exact)) ||
          (_deniedLogicalGrants.contains(key) &&
              (exact == null || !(_reauthorizedExactGrants[key]?.contains(exact) ?? false)))) {
        throw const CacheBlocked('offline_grant_unavailable');
      }
      // A stored grant cannot create its own clock after restart. Restore it
      // only under an existing conservative clock from this confirmed run.
      final persisted = diskSnapshot?.grant;
      final trusted = _latestServerAnchor;
      if (version != null &&
          persisted != null &&
          trusted != null &&
          !persisted.serverTime.isAfter(trusted.serverUpperAtAccept.add(trusted.elapsed.elapsed)) &&
          _validGrant(scope, key, version, persisted)) {
        _grants[grantSlot] = _GrantAnchor(persisted, Duration.zero, trusted);
      }
      final anchor = diskSnapshot?.grant == null ? null : _grants[grantSlot];
      if (!policy.persistent ||
          candidate == null ||
          version == null ||
          anchor == null ||
          !anchor.allows(scope, key, version)) {
        throw const CacheBlocked('offline_grant_unavailable');
      }
      if (useDisk && stored != null) {
        final accepted = await withCachePartitionPublishLock(scope.partition, () {
          checkCurrent();
          return _database!.touchEntryIfCurrent(
            expectedStorageEpoch: storageEpoch,
            entryKey: key,
            exactEntryKey: stored!.entryKey,
            requireHead: requestedVersion == null,
            expectedPublicationEpoch: stored.publicationEpoch,
            expectedInvalidations: diskSnapshot!.invalidations,
            expectedPayloadHash: stored.payloadHash,
            expectedVersion: stored.version,
          );
        });
        checkCurrent();
        if (!accepted) throw const CacheBlocked('stale_response');
      }
      if (!acceptLeaseGrant() || !_offline) {
        throw const CacheBlocked('offline_grant_unavailable');
      }
      return CacheView(
        data: candidate,
        source: CacheSource.disk,
        freshness: CacheFreshness.offline,
        serverSaved: true,
        localReady: true,
        lastValidatedAt: stored?.verifiedAt,
        resource: resource,
        version: version,
        entryKey: stored?.entryKey,
        publicationEpoch: stored?.publicationEpoch,
      );
    }

    final existingVersion = memory?.version ?? stored?.version;
    if (policy.persistent && existingVersion != null && !fetchOnly) {
      final clock = Stopwatch()..start();
      final validation = await _authorizedRemoteCall(
        () => remote.validate(resource, existingVersion, cancel),
        cancel,
        currentRequest,
      );
      clock.stop();
      checkCurrent();
      onEvent?.call('cache.validation', {
        'result':
            validation.state == ValidationState.same &&
                !_sameVersion(existingVersion, validation.version)
            ? 'changed'
            : validation.state.name,
      });
      if (validation.state == ValidationState.unavailable) {
        _denyOfflineLogical(key);
        _memory.remove(key);
        _grants.remove(grantSlot);
        if (useDisk && stored != null) {
          final deleted = await withCachePartitionPublishLock(
            scope.partition,
            () => _database!.deleteEntryIfCurrent(
              expectedStorageEpoch: storageEpoch,
              entryKey: key,
              exactEntryKey: diskSnapshot!.entry!.entryKey,
              requireHead: requestedVersion == null,
              expectedPublicationEpoch: diskSnapshot.entry!.publicationEpoch,
            ),
          );
          checkCurrent();
          if (!deleted) throw const CacheBlocked('stale_response');
          _changes.add(null);
        }
        throw const CacheBlocked('resource_unavailable');
      }
      if (validation.state == ValidationState.same &&
          _sameVersion(existingVersion, validation.version)) {
        var sameLocalReady = stored != null && _sameVersion(stored.version, existingVersion);
        if (useDisk) {
          try {
            final current = await readSnapshot(
              version: requestedVersion != null && stored == null ? null : requestedVersion,
            );
            checkCurrent();
            if (current.storageEpoch != diskSnapshot!.storageEpoch ||
                current.entry?.publicationEpoch != diskSnapshot.entry?.publicationEpoch ||
                !_sameInvalidations(current.invalidations, diskSnapshot.invalidations)) {
              throw const CacheBlocked('stale_response');
            }
          } on Object catch (error) {
            if (error is CacheBlocked || _isSchemaTooNew(error)) rethrow;
            checkCurrent();
            await verifyAfterStorageFailure();
            sameLocalReady = false;
            onEvent?.call('cache.storage.degraded', {'reason': 'writer_unavailable'});
          }
        }
        if (validation.revokeGrant ||
            (validation.grant != null &&
                !_validGrant(scope, key, existingVersion, validation.grant!))) {
          _denyOfflineExact(cacheEntryKey(key, existingVersion));
        }
        _updateGrant(
          scope,
          key,
          existingVersion,
          acceptLeaseGrant() ? validation.grant : null,
          clock.elapsed,
          revoke: validation.revokeGrant,
          slot: grantSlot,
        );
        if (useDisk && diskSnapshot!.entry != null && sameLocalReady) {
          try {
            final accepted =
                (validation.grant == null || !acceptLeaseGrant()) && !validation.revokeGrant
                ? true
                : await withCachePartitionPublishLock(
                    scope.partition,
                    () => _database!.replaceGrantIfCurrent(
                      expectedStorageEpoch: storageEpoch,
                      entryKey: key,
                      exactEntryKey: diskSnapshot!.entry!.entryKey,
                      requireHead: requestedVersion == null,
                      expectedPublicationEpoch: diskSnapshot.entry!.publicationEpoch,
                      expectedInvalidations: diskSnapshot.invalidations,
                      expectedPayloadHash: diskSnapshot.entry!.payloadHash,
                      expectedVersion: diskSnapshot.entry!.version,
                      grant: validation.revokeGrant
                          ? null
                          : (acceptLeaseGrant() &&
                                (_grants[grantSlot]?.allows(scope, key, existingVersion) ?? false))
                          ? _grants[grantSlot]!.grant
                          : null,
                    ),
                  );
            checkCurrent();
            if (!accepted) {
              _grants.remove(grantSlot);
              _memory.remove(key);
              throw const CacheBlocked('stale_response');
            }
            if (validation.revokeGrant || validation.grant != null && acceptLeaseGrant()) {
              final exact = cacheEntryKey(key, existingVersion);
              if (validation.grant != null && _grants[grantSlot] != null) {
                _deniedExactGrants.remove(exact);
                _markReauthorizedExact(key, exact);
              } else {
                _deniedExactGrants.remove(exact);
              }
            }
            final touched = await withCachePartitionPublishLock(scope.partition, () {
              checkCurrent();
              return _database!.touchEntryIfCurrent(
                expectedStorageEpoch: storageEpoch,
                entryKey: key,
                exactEntryKey: diskSnapshot!.entry!.entryKey,
                requireHead: requestedVersion == null,
                expectedPublicationEpoch: diskSnapshot.entry!.publicationEpoch,
                expectedInvalidations: diskSnapshot.invalidations,
                expectedPayloadHash: diskSnapshot.entry!.payloadHash,
                expectedVersion: diskSnapshot.entry!.version,
              );
            });
            checkCurrent();
            if (!touched) throw const CacheBlocked('stale_response');
          } on Object catch (error) {
            if (error is CacheBlocked || _isSchemaTooNew(error)) rethrow;
            checkCurrent();
            await verifyAfterStorageFailure();
            sameLocalReady = false;
            onEvent?.call('cache.storage.degraded', {'reason': 'writer_unavailable'});
          }
        }
        final value = memory?.data ?? storedValue as T;
        final now = DateTime.now().toUtc();
        int? samePublishedEpoch = stored?.publicationEpoch;
        if (!sameLocalReady && memory?.pendingPublication == true) {
          final retried = await publishValidatedBody(value, existingVersion);
          sameLocalReady = retried.$1;
          samePublishedEpoch = retried.$2;
        }
        if (requestedVersion == null || sameLocalReady && memory?.pendingPublication == true) {
          _remember(
            key,
            _MemoryEntry<T>(
              value,
              existingVersion,
              policy.dependencies(resource),
              now,
              pendingPublication: !sameLocalReady && memory?.pendingPublication == true,
              storageEpoch: memory?.storageEpoch,
              expectedEntryKey: memory?.expectedEntryKey,
              expectedPublicationEpoch: memory?.expectedPublicationEpoch ?? 0,
              expectedInvalidations: memory?.expectedInvalidations ?? const {},
            ),
          );
        }
        onEvent?.call('cache.read.hit', {'source': memory == null ? 'disk' : 'memory'});
        return CacheView(
          data: value,
          source: memory == null ? CacheSource.disk : CacheSource.memory,
          freshness: CacheFreshness.validated,
          serverSaved: true,
          localReady: sameLocalReady,
          lastValidatedAt: now,
          resource: resource,
          version: existingVersion,
          entryKey: sameLocalReady ? cacheEntryKey(key, existingVersion) : null,
          publicationEpoch: sameLocalReady ? samePublishedEpoch : null,
        );
      }
      if (requestedVersion != null) throw const CacheBlocked('version_changed');
      _denyOfflineExact(cacheEntryKey(key, existingVersion));
      _memory.remove(key);
      _grants.remove(grantSlot);
      if (useDisk && stored != null) {
        final removed = await withCachePartitionPublishLock(
          scope.partition,
          () => _database!.replaceGrantIfCurrent(
            expectedStorageEpoch: storageEpoch,
            entryKey: key,
            exactEntryKey: diskSnapshot!.entry!.entryKey,
            requireHead: requestedVersion == null,
            expectedPublicationEpoch: diskSnapshot.entry!.publicationEpoch,
            expectedInvalidations: diskSnapshot.invalidations,
            expectedPayloadHash: diskSnapshot.entry!.payloadHash,
            expectedVersion: diskSnapshot.entry!.version,
            grant: null,
          ),
        );
        checkCurrent();
        if (!removed) throw const CacheBlocked('stale_response');
        _deniedExactGrants.remove(cacheEntryKey(key, existingVersion));
      }
      final target = validation.readResource ?? resource;
      if (target.kind != resource.kind ||
          target.action != resource.action ||
          !target.allowsPersistent(policy.disposition)) {
        throw const CacheBlocked('invalid_read_projection');
      }
      final targetKey = target.keyFor(scope);
      if (targetKey != key) {
        _tagsByKey[targetKey] = policy.dependencies(target);
        final view = await _execute(
          scope: scope,
          resource: target,
          policy: policy,
          remote: remote,
          key: targetKey,
          generation: _readGeneration[targetKey] ?? 0,
          accountGeneration: accountGeneration,
          leaseRevision: leaseRevision,
          storageEpoch: storageEpoch,
          cancel: cancel,
          fetchOnly: true,
        );
        checkCurrent();
        if (stored != null && useDisk) {
          await withCachePartitionPublishLock(scope.partition, () {
            checkCurrent();
            return _database!.deleteEntryIfCurrent(
              expectedStorageEpoch: storageEpoch,
              entryKey: key,
              exactEntryKey: stored!.entryKey,
              requireHead: requestedVersion == null,
              expectedPublicationEpoch: stored.publicationEpoch,
              expectedPayloadHash: stored.payloadHash,
            );
          });
          checkCurrent();
        }
        return view;
      }
    }

    final fetchClock = Stopwatch()..start();
    onEvent?.call('cache.read.miss', {'source': 'network'});
    final payload = await _authorizedRemoteCall(
      () => remote.fetch(resource, cancel),
      cancel,
      currentRequest,
    );
    fetchClock.stop();
    checkCurrent();
    if (!payload.serverSaved) {
      return CacheView(
        data: payload.value,
        source: CacheSource.network,
        freshness: CacheFreshness.validated,
        serverSaved: false,
        localReady: false,
        resource: resource,
        version: payload.version,
      );
    }
    final now = DateTime.now().toUtc();
    _remember(
      key,
      _MemoryEntry<T>(
        payload.value,
        payload.version,
        policy.dependencies(resource),
        now,
        pendingPublication: useDisk && mayPublish,
        storageEpoch: storageEpoch,
        expectedEntryKey: diskSnapshot?.entry?.entryKey,
        expectedPublicationEpoch: diskSnapshot?.entry?.publicationEpoch ?? 0,
        expectedInvalidations: diskSnapshot?.invalidations ?? const {},
      ),
    );
    if (payload.grant != null && !_validGrant(scope, key, payload.version, payload.grant!)) {
      _denyOfflineExact(cacheEntryKey(key, payload.version));
    }
    _updateGrant(
      scope,
      key,
      payload.version,
      acceptLeaseGrant() ? payload.grant : null,
      fetchClock.elapsed,
      slot: grantSlot,
    );
    final publication = await publishValidatedBody(payload.value, payload.version);
    final localReady = publication.$1;
    final publishedEpoch = publication.$2;
    if (localReady) {
      _remember(
        key,
        _MemoryEntry<T>(payload.value, payload.version, policy.dependencies(resource), now),
      );
    }
    return CacheView(
      data: payload.value,
      source: CacheSource.network,
      freshness: CacheFreshness.validated,
      serverSaved: true,
      localReady: localReady,
      lastValidatedAt: now,
      resource: resource,
      version: payload.version,
      entryKey: localReady ? cacheEntryKey(key, payload.version) : null,
      publicationEpoch: publishedEpoch,
    );
  }

  bool _sameVersion(CacheVersion a, CacheVersion? b) =>
      b != null &&
      a.resource == b.resource &&
      a.representation == b.representation &&
      a.artifact == b.artifact &&
      a.nlp == b.nlp &&
      a.binding == b.binding;

  Future<R> _authorizedRemoteCall<R>(
    Future<R> Function() request,
    CancelToken cancel,
    bool Function() stillCurrent,
  ) async {
    for (var retries = 0; ; retries++) {
      if (cancel.isCancelled) throw const CacheBlocked('stale_response');
      try {
        return await _authorizedAttempt(request, stillCurrent);
      } on Object catch (error) {
        final delay = cacheReadRetryDelay(error, retries);
        if (delay == null || !stillCurrent()) rethrow;
        await Future.any<void>([
          _retryDelay(delay),
          cancel.whenCancel.then<void>((_) => throw const CacheBlocked('stale_response')),
        ]);
      }
    }
  }

  Future<R> _authorizedAttempt<R>(
    Future<R> Function() request,
    bool Function() stillCurrent,
  ) async {
    try {
      return await request();
    } on ApiFailure catch (error) {
      // Transport 401/403 remains authoritative even when an error envelope
      // is malformed or uses a code this client version does not know.
      if (error.statusCode == 401 ||
          error.statusCode == 403 ||
          const {
            'AUTH_REQUIRED',
            'ACCESS_EXPIRED',
            'SESSION_REVOKED',
            'SESSION_INVALID',
            'AUTH_SCOPE_CHANGED',
            'AUTH_SCOPE_REQUIRED',
            'INSTANCE_MISMATCH',
            'PERMISSION_DENIED',
            'CSRF_FAILED',
          }.contains(error.code)) {
        if (!stillCurrent()) rethrow;
        blockForAuthorizationFailure();
      }
      rethrow;
    } on DioException catch (error) {
      // A definite identity or permission refusal can never be recast as
      // network unreachability and must close existing offline grants.
      if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
        if (stillCurrent()) blockForAuthorizationFailure();
      }
      rethrow;
    }
  }

  bool _validGrant(CacheScope scope, String key, CacheVersion version, CacheGrant grant) =>
      grant.scopeBinding == scope.binding &&
      grant.resourceKey == key &&
      grant.securityEpoch == scope.securityEpoch &&
      grant.authzVersion == scope.authzVersion &&
      grant.policyVersion == scope.policyVersion &&
      _sameVersion(version, grant.version);

  void _denyOfflineLogical(String key) {
    _grants.removeWhere((slot, _) => slot == key || slot.startsWith('$key:'));
    if (_denyAllOfflineGrants) return;
    _deniedLogicalGrants.add(key);
    _reauthorizedExactGrants.remove(key);
    _limitDeniedGrants();
  }

  void _denyOfflineExact(String exact) {
    _grants.removeWhere(
      (_, anchor) => cacheEntryKey(anchor.grant.resourceKey, anchor.grant.version) == exact,
    );
    if (_denyAllOfflineGrants) return;
    _deniedExactGrants.add(exact);
    for (final exacts in _reauthorizedExactGrants.values) {
      exacts.remove(exact);
    }
    _limitDeniedGrants();
  }

  void _markReauthorizedExact(String key, String exact) {
    if (_denyAllOfflineGrants || !_deniedLogicalGrants.contains(key)) return;
    _reauthorizedExactGrants.putIfAbsent(key, () => <String>{}).add(exact);
    _limitDeniedGrants();
  }

  void _limitDeniedGrants() {
    if (_deniedLogicalGrants.length +
            _deniedExactGrants.length +
            _reauthorizedExactGrants.values.fold<int>(0, (sum, exacts) => sum + exacts.length) >
        256) {
      _deniedLogicalGrants.clear();
      _deniedExactGrants.clear();
      _reauthorizedExactGrants.clear();
      _denyAllOfflineGrants = true;
    }
  }

  void _clearOfflineDenials() {
    _deniedLogicalGrants.clear();
    _deniedExactGrants.clear();
    _reauthorizedExactGrants.clear();
    _denyAllOfflineGrants = false;
  }

  void _updateGrant(
    CacheScope scope,
    String key,
    CacheVersion version,
    CacheGrant? candidate,
    Duration roundTrip, {
    bool revoke = false,
    String? slot,
  }) {
    final grantSlot = slot ?? key;
    if (revoke || (candidate != null && !_validGrant(scope, key, version, candidate))) {
      _grants.remove(grantSlot);
      return;
    }
    if (candidate == null) {
      final currentForKey = _grants[grantSlot];
      if (currentForKey != null && !currentForKey.allows(scope, key, version)) {
        _grants.remove(grantSlot);
      }
      return;
    }
    final currentForKey = _grants[grantSlot];
    if (currentForKey != null &&
        _validGrant(scope, key, version, currentForKey.grant) &&
        candidate.serverTime.isBefore(currentForKey.grant.serverTime)) {
      return;
    }
    final previous = _latestServerAnchor;
    final accepted = _GrantAnchor(candidate, roundTrip, previous);
    _grants[grantSlot] = accepted;
    _latestServerAnchor = accepted;
  }

  void _remember<T>(String key, _MemoryEntry<T> entry) {
    _memory.remove(key);
    _memory[key] = entry;
    while (_memory.length > 128) {
      final victim = _memory.keys.firstWhere(
        (candidate) => !_pins.containsKey(candidate),
        orElse: () => '',
      );
      if (victim.isEmpty) break;
      _memory.remove(victim);
      _pruneIdleMetadata(victim);
    }
  }

  void _pruneIdleMetadata(String key) {
    if (_memory.containsKey(key) ||
        _pins.containsKey(key) ||
        _flights.keys.any((flight) => flight.startsWith('$key:'))) {
      return;
    }
    final tags = _tagsByKey.remove(key);
    if (tags != null) {
      for (final tag in tags) {
        if (!_sharedDependencyTags.contains(tag) &&
            !_tagsByKey.values.any((current) => current.contains(tag))) {
          _dependencyRevisions.remove(tag);
          if (!_unsafeDependencies.contains(tag)) _knownInvalidations.remove(tag);
        }
      }
    }
    _readGeneration.remove(key);
    _explicitPersistenceKeys.remove(key);
    _grants.removeWhere((slot, _) => slot == key || slot.startsWith('$key:'));
  }

  bool _sameInvalidations(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.keys.every((key) => a[key] == b[key]);

  void _retireKey(String key) {
    _readGeneration[key] = (_readGeneration[key] ?? 0) + 1;
    for (final entry in _flights.entries.toList()) {
      if (entry.value.key.startsWith('$key:')) {
        entry.value.retired = true;
        entry.value.cancel.cancel('resource_invalidated');
        _flights.remove(entry.key);
      }
    }
  }

  void _retireGrantsForLogical(String key) {
    _grants.remove(key);
    _grants.removeWhere((slot, _) => slot.startsWith('$key:'));
  }

  /// Domain repositories call this only after a confirmed server commit.
  Future<void> applyCommittedMutation(Set<String> dependencyTags) async {
    if (_scope == null || _blocked) throw const CacheBlocked('identity_unconfirmed');
    final scope = _scope!;
    final generation = _accountGeneration;
    final database = _database;
    final backend = _backend;
    final channel = _channel;
    final attempt = ++_invalidationAttempt;
    for (final tag in dependencyTags) {
      _unsafeDependencies.add(tag);
      _unsafeDependencyVersions[tag] = attempt;
      _inFlightInvalidations[tag] = attempt;
    }
    if (_unsafeDependencies.length > 256) {
      // Keep this failure mode bounded. A full explicit cache clear is the
      // recovery path; trimming individual tags would revive old disk grants.
      _unsafeAllDependencies = true;
      _unsafeDependencies.clear();
      _unsafeDependencyVersions.clear();
    }
    for (final entry in _tagsByKey.entries.toList()) {
      if (entry.value.intersection(dependencyTags).isNotEmpty) {
        _retireKey(entry.key);
        _memory.remove(entry.key);
        _retireGrantsForLogical(entry.key);
      }
    }
    Map<String, int>? durableEpochs;
    Map<String, int>? ownEpochs;
    try {
      final changed = <String>{};
      if (backend?.mode == CacheStorageMode.persistent) {
        ownEpochs = await withCachePartitionPublishLock(
          scope.partition,
          () => database!.invalidate(
            dependencyTags,
            acquireEviction: (exact, logical) => _tryEvictionLocks(scope.partition, exact, logical),
          ),
        );
        durableEpochs = await database!.allInvalidationEpochs();
        if (!identical(database, _database) ||
            _scope?.binding != scope.binding ||
            _accountGeneration != generation) {
          throw const CacheBlocked('scope_changed');
        }
      }
      for (final tag in dependencyTags) {
        if (_unsafeDependencyVersions[tag] == attempt) {
          _unsafeDependencies.remove(tag);
          _unsafeDependencyVersions.remove(tag);
        }
        if (!_unsafeDependencies.contains(tag)) changed.add(tag);
      }
      if (backend?.mode == CacheStorageMode.persistent) {
        final onlyOwnIncrement = {
          for (final tag in dependencyTags)
            if (durableEpochs![tag] == ownEpochs![tag]) tag,
        };
        changed.addAll(
          _adoptInvalidations(
            durableEpochs!,
            withheld: _unsafeDependencies,
            alreadySignaled: onlyOwnIncrement,
            notify: false,
          ),
        );
      }
      if (changed.isNotEmpty) handleExternalCacheHint('invalidate', changed);
    } on Object {
      if (identical(database, _database) &&
          _scope?.binding == scope.binding &&
          _accountGeneration == generation) {
        handleExternalCacheHint('invalidate', dependencyTags);
      }
      rethrow;
    } finally {
      for (final tag in dependencyTags) {
        if (_inFlightInvalidations[tag] == attempt) _inFlightInvalidations.remove(tag);
      }
    }
    if (_scope?.binding != scope.binding || _accountGeneration != generation || _blocked) {
      throw const CacheBlocked('scope_changed');
    }
    channel?.publish('invalidate', dependencyTags);
    onEvent?.call('cache.invalidated', {'result': 'success'});
  }

  Future<void> clearTextScope() async {
    final scope = _scope;
    final database = _database;
    final backend = _backend;
    final audio = _audio;
    if (scope == null || database == null || backend == null || (_blocked && !_storageClearing)) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    final generation = _accountGeneration;
    final clearRevision = ++_storageRevision;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('cache_cleared');
    }
    _flights.clear();
    _memory.clear();
    _releasePins();
    _grants.clear();
    _readGeneration.clear();
    _tagsByKey.clear();
    _persistenceSuspended = true;
    _explicitPersistenceKeys.clear();
    _storageClearing = true;
    _blocked = true;
    _changes.add(null);
    return _scopeTransition(
      () => _clearTextScopeCaptured(scope, database, backend, audio, generation, clearRevision),
    );
  }

  Future<void> _clearTextScopeCaptured(
    CacheScope scope,
    CacheDatabase database,
    OpenedCacheBackend backend,
    CacheAudioManager? audio,
    int generation,
    int clearRevision,
  ) async {
    void checkClearOwner() {
      if (_scope?.binding != scope.binding ||
          !identical(_database, database) ||
          _accountGeneration != generation ||
          _storageRevision != clearRevision) {
        throw const CacheBlocked('scope_changed');
      }
    }

    checkClearOwner();
    final nextEpoch = backend.mode == CacheStorageMode.persistent
        ? await withCachePartitionPublishLock(scope.partition, database.clearText)
        : await database.clearText();
    checkClearOwner();
    _storageEpoch = nextEpoch;
    try {
      // Text clearing also retires downloads from the previous storage epoch.
      // Their byte deletion runs outside the index transaction and does not
      // undo the already committed text clear when a byte owner is busy.
      await audio?.cleanupRetiredOperations();
    } on Object {
      onEvent?.call('cache.storage.degraded', {'reason': 'audio_unavailable'});
    }
    checkClearOwner();
    try {
      Future<int> finish() {
        checkClearOwner();
        return database.finishClearAll(expectedStorageEpoch: nextEpoch);
      }

      if (backend.mode == CacheStorageMode.persistent) {
        await withCachePartitionPublishLock(scope.partition, finish);
      } else {
        await finish();
      }
    } on Object catch (error) {
      if (error is CacheBlocked || _isSchemaTooNew(error)) rethrow;
      onEvent?.call('cache.storage.degraded', {'reason': 'audio_unavailable'});
    }
    checkClearOwner();
    _clearOfflineDenials();
    _unsafeDependencies.clear();
    _unsafeDependencyVersions.clear();
    _unsafeAllDependencies = false;
    _blocked = false;
    _storageClearing = false;
    _channel?.publish('clear');
    _changes.add(null);
    onEvent?.call('cache.cleared', {'result': 'success'});
  }

  /// Clears both index and audio copies; pinned bytes remain recorded for retry.
  Future<CacheClearResult> clearScope({bool afterIdentityChange = false}) async {
    final scope = _scope;
    final database = _database;
    final backend = _backend;
    final audio = _audio;
    if (scope == null ||
        database == null ||
        backend == null ||
        (_blocked && !afterIdentityChange)) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    _lifecycleRevision++;
    _accountGeneration++;
    final generation = _accountGeneration;
    final clearRevision = ++_storageRevision;
    _blocked = true;
    _storageClearing = false;
    for (final flight in _flights.values) {
      flight.retired = true;
      flight.cancel.cancel('cache_cleared');
    }
    _flights.clear();
    _memory.clear();
    _releasePins();
    _grants.clear();
    _readGeneration.clear();
    _tagsByKey.clear();
    _persistenceSuspended = true;
    _explicitPersistenceKeys.clear();
    _changes.add(null);
    return _scopeTransition(
      () => _clearScopeCaptured(
        scope,
        database,
        backend,
        audio,
        generation,
        clearRevision,
        afterIdentityChange,
      ),
    );
  }

  Future<CacheClearResult> _clearScopeCaptured(
    CacheScope scope,
    CacheDatabase database,
    OpenedCacheBackend backend,
    CacheAudioManager? audio,
    int generation,
    int clearRevision,
    bool afterIdentityChange,
  ) async {
    void checkClearOwner() {
      if (_scope?.binding != scope.binding ||
          !identical(_database, database) ||
          _accountGeneration != generation ||
          _storageRevision != clearRevision) {
        throw const CacheBlocked('scope_changed');
      }
    }

    checkClearOwner();
    final nextEpoch = backend.mode == CacheStorageMode.persistent
        ? await withCachePartitionPublishLock(scope.partition, database.beginClearAll)
        : await database.beginClearAll();
    checkClearOwner();
    _storageEpoch = nextEpoch;
    final result = await _drainPendingAudioDeletions(
      scope,
      database,
      audio,
      expectedStorageEpoch: nextEpoch,
      persistent: backend.mode == CacheStorageMode.persistent,
    );
    checkClearOwner();
    _blocked = afterIdentityChange;
    _channel?.publish('clear');
    _changes.add(null);
    onEvent?.call('cache.cleared', {'result': result.pendingAudio == 0 ? 'success' : 'failure'});
    return result;
  }

  Future<CacheClearResult> _drainPendingAudioDeletions(
    CacheScope scope,
    CacheDatabase database,
    CacheAudioManager? audio, {
    required String expectedStorageEpoch,
    required bool persistent,
  }) async {
    var deleted = 0;
    final references = await database.pendingAudioDeletions();
    for (final reference in references) {
      if (audio == null) break;
      bool removed;
      try {
        removed = await audio.bytes.tryDeleteReference(reference);
      } on Object {
        removed = false;
      }
      if (!removed) continue;
      deleted++;
      await withCachePartitionPublishLock(
        scope.partition,
        () => database.completeAudioDeletion(reference),
      );
    }
    Future<int> finish() => database.finishClearAll(expectedStorageEpoch: expectedStorageEpoch);
    final pending = persistent
        ? await withCachePartitionPublishLock(scope.partition, finish)
        : await finish();
    return CacheClearResult(deletedAudio: deleted, pendingAudio: pending);
  }
}
