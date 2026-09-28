import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../../../core/cache/cache_read_retry.dart';
import '../domain/settings_snapshot.dart';
import 'settings_source.dart';

enum SettingsReadStatus { initial, loading, refreshing, ready, stale, blocked, failed }

CacheResource settingsResource(SettingsGroup group) => CacheResource(
  kind: 'settings_snapshot',
  id: group.sourceId,
  projection: 'user-settings-v1',
  action: 'client.profile.read',
  sourceBinding: 'users/me/${group.sourceId}',
);

/// In-memory projections for three independently versioned settings endpoints.
/// Device quota and secrets are deliberately outside this repository.
final class CachedSettingsRepository extends ChangeNotifier {
  CachedSettingsRepository({
    required CacheCoordinator cache,
    required this.source,
    this.waitForReadiness,
  }) : _cache = cache {
    cache.register(
      CachePolicy<SettingsSnapshot>(
        kind: 'settings_snapshot',
        disposition: CacheDisposition.memoryOnly,
        decode: SettingsSnapshot.fromJson,
        encode: (value) => value.toJson(),
        dependencies: (resource) => {
          SettingsGroup.values.singleWhere((group) => group.sourceId == resource.id).dependency,
        },
      ),
    );
    _binding = cache.scope?.binding;
    _accountGeneration = cache.accountGeneration;
    _invalidationGeneration = cache.invalidationGeneration;
    _accessReady = cache.accessReady;
    _changes = cache.changes.listen((_) => _onCacheChange());
  }

  final CacheCoordinator _cache;
  final SettingsSource source;
  final Future<void> Function()? waitForReadiness;
  late final StreamSubscription<void> _changes;
  final _snapshots = <SettingsGroup, SettingsSnapshot>{};
  final _statuses = <SettingsGroup, SettingsReadStatus>{};
  final _requestGenerations = <SettingsGroup, int>{};
  final _acceptedGenerations = <SettingsGroup, int>{};
  final _acceptedDependencyRevisions = <SettingsGroup, (int, int)>{};
  final _mutating = <SettingsGroup>{};
  String? _binding;
  late int _accountGeneration;
  late int _invalidationGeneration;
  late bool _accessReady;
  int? _selfHandledGeneration;
  Set<String> _selfHandledTags = const {};
  bool _disposed = false;

  SettingsReadStatus status(SettingsGroup group) => _visible(group)
      ? (_acceptedGenerations[group] != _cache.invalidationGeneration
            ? SettingsReadStatus.refreshing
            : _statuses[group] ?? SettingsReadStatus.initial)
      : ((_statuses[group] == SettingsReadStatus.ready ||
                _statuses[group] == SettingsReadStatus.stale)
            ? SettingsReadStatus.blocked
            : _statuses[group] ?? SettingsReadStatus.initial);

  SettingsSnapshot? snapshot(SettingsGroup group) => _visible(group) ? _snapshots[group] : null;

  bool busy(SettingsGroup group) => _mutating.contains(group);

  int get scopeGeneration => _cache.scopeGeneration;

  bool _visible(SettingsGroup group) =>
      !_disposed &&
      _cache.accessReady &&
      _binding == _cache.scope?.binding &&
      _accountGeneration == _cache.accountGeneration &&
      (_statuses[group] == SettingsReadStatus.ready ||
          _statuses[group] == SettingsReadStatus.refreshing ||
          _statuses[group] == SettingsReadStatus.stale);

  SettingsSnapshot? _currentForWrite(SettingsGroup group) =>
      !_disposed &&
          _cache.accessReady &&
          _cache.dependenciesSafe({group.dependency}) &&
          _binding == _cache.scope?.binding &&
          _accountGeneration == _cache.accountGeneration &&
          (_statuses[group] == SettingsReadStatus.ready ||
              _statuses[group] == SettingsReadStatus.refreshing) &&
          _acceptedGenerations[group] == _cache.invalidationGeneration &&
          _acceptedDependencyRevisions[group] == _cache.dependencyRevision(group.dependency)
      ? _snapshots[group]
      : null;

  void _publish(SettingsGroup group, SettingsSnapshot? value, SettingsReadStatus status) {
    if (_disposed) return;
    if ((status == SettingsReadStatus.ready || status == SettingsReadStatus.stale) &&
        value?.group != group) {
      throw StateError('Settings source returned the wrong revision group');
    }
    if (value == null) {
      _snapshots.remove(group);
      _acceptedGenerations.remove(group);
      _acceptedDependencyRevisions.remove(group);
    } else {
      _snapshots[group] = value;
      _acceptedGenerations[group] = _cache.invalidationGeneration;
      if (status == SettingsReadStatus.ready || status == SettingsReadStatus.stale) {
        _acceptedDependencyRevisions[group] = _cache.dependencyRevision(group.dependency);
      }
    }
    _statuses[group] = status;
    notifyListeners();
  }

  void _onCacheChange() {
    if (_disposed) return;
    final binding = _cache.scope?.binding;
    final accountGeneration = _cache.accountGeneration;
    final generation = _cache.invalidationGeneration;
    final scopeChanged = binding != _binding;
    final readsRetired = accountGeneration != _accountGeneration;
    final readinessChanged = _cache.accessReady != _accessReady;
    final invalidated = generation != _invalidationGeneration;
    final missed = invalidated && generation != _invalidationGeneration + 1;
    final tags = missed ? null : _cache.lastInvalidatedTags;
    _binding = binding;
    _accountGeneration = accountGeneration;
    _invalidationGeneration = generation;
    _accessReady = _cache.accessReady;

    if (scopeChanged || readsRetired || !_accessReady) {
      for (final group in SettingsGroup.values) {
        _requestGenerations[group] = (_requestGenerations[group] ?? 0) + 1;
        if (_statuses[group] != null && _statuses[group] != SettingsReadStatus.initial) {
          _publish(group, null, SettingsReadStatus.blocked);
        }
      }
      if (!scopeChanged && readsRetired && _accessReady) {
        for (final group in SettingsGroup.values) {
          if (_statuses[group] == SettingsReadStatus.blocked)
            unawaited(refresh(group, force: true));
        }
      }
      return;
    }
    if (!invalidated && !readinessChanged && !readsRetired) return;
    final affected = <SettingsGroup>{};
    for (final group in SettingsGroup.values) {
      if (readsRetired || (invalidated && (tags == null || tags.contains(group.dependency)))) {
        affected.add(group);
        _requestGenerations[group] = (_requestGenerations[group] ?? 0) + 1;
        if (_statuses[group] != null && _statuses[group] != SettingsReadStatus.initial) {
          if (!_cache.dependenciesSafe({group.dependency})) {
            _publish(group, null, SettingsReadStatus.blocked);
          } else {
            _acceptedGenerations[group] = generation;
            _statuses[group] = _snapshots.containsKey(group)
                ? SettingsReadStatus.refreshing
                : SettingsReadStatus.loading;
          }
        }
      } else if (_snapshots.containsKey(group)) {
        _acceptedGenerations[group] = generation;
      }
    }
    notifyListeners();
    final skipSelf =
        !readinessChanged &&
        !readsRetired &&
        !missed &&
        generation == _selfHandledGeneration &&
        tags != null;
    for (final group in SettingsGroup.values) {
      if ((_statuses[group] != null && _statuses[group] != SettingsReadStatus.initial) &&
          (readinessChanged || affected.contains(group)) &&
          !(skipSelf && _selfHandledTags.contains(group.dependency)) &&
          _cache.dependenciesSafe({group.dependency})) {
        unawaited(refresh(group, force: true));
      }
    }
  }

  Future<void> refresh(SettingsGroup group, {bool force = false}) async {
    final requestGeneration = (_requestGenerations[group] ?? 0) + 1;
    _requestGenerations[group] = requestGeneration;
    final previous = _visible(group) ? _snapshots[group] : null;
    final binding = _cache.scope?.binding;
    final account = _cache.accountGeneration;
    final invalidation = _cache.dependencyRevision(group.dependency);
    bool canRetain() =>
        previous != null &&
        _cache.accessReady &&
        _cache.scope?.binding == binding &&
        _cache.accountGeneration == account &&
        _cache.dependencyRevision(group.dependency) == invalidation;
    // A refresh can hide the old value from UI while retaining its revision
    // for an explicit PATCH. A conflicting server revision still rejects it.
    _statuses[group] = _visible(group) ? SettingsReadStatus.refreshing : SettingsReadStatus.loading;
    notifyListeners();
    try {
      await waitForReadiness?.call();
      if (!_cache.accessReady) throw const CacheBlocked('identity_unconfirmed');
      final view = await _cache.read<SettingsSnapshot>(
        resource: settingsResource(group),
        remote: _SettingsRemote(source, group),
        forceRefresh: force,
      );
      if (_disposed || requestGeneration != _requestGenerations[group]) return;
      if (view.freshness == CacheFreshness.stale && view.data != null && canRetain()) {
        _publish(group, view.data, SettingsReadStatus.stale);
      } else if (view.freshness == CacheFreshness.blocked || view.data == null) {
        _publish(group, null, SettingsReadStatus.blocked);
      } else {
        _publish(group, view.data, SettingsReadStatus.ready);
      }
    } on CacheBlocked {
      if (!_disposed && requestGeneration == _requestGenerations[group]) {
        _publish(group, null, SettingsReadStatus.blocked);
      }
    } on Object catch (error) {
      if (!_disposed && requestGeneration == _requestGenerations[group]) {
        if (cacheReadMayKeepSnapshot(error) && canRetain()) {
          _publish(group, previous, SettingsReadStatus.stale);
        } else {
          _publish(group, null, SettingsReadStatus.failed);
        }
      }
    }
  }

  Future<SettingsSnapshot> save(SettingsGroup group, Map<String, Object?> fields) async {
    if (_mutating.contains(group)) throw const CacheBlocked('mutation_in_progress');
    if (!_cache.accessReady) throw const CacheBlocked('identity_unconfirmed');
    final binding = _cache.scope?.binding;
    final accountGeneration = _cache.accountGeneration;
    void checkScope() {
      if (!_cache.accessReady ||
          binding != _cache.scope?.binding ||
          accountGeneration != _cache.accountGeneration) {
        throw const CacheBlocked('scope_changed');
      }
    }

    await waitForReadiness?.call();
    checkScope();
    if (_currentForWrite(group) == null) await refresh(group, force: true);
    checkScope();
    final current = _currentForWrite(group);
    if (current == null) throw const CacheBlocked('settings_snapshot_unavailable');

    _mutating.add(group);
    notifyListeners();
    try {
      if (!_cache.dependenciesSafe({group.dependency}))
        throw const CacheBlocked('invalidation_not_durable');
      final committed = await source.patch(
        group,
        SettingsPatch(expectedRevision: current.revision, fields: fields),
      );
      checkScope();
      if (committed.group != group || committed.revision <= current.revision) {
        throw StateError('Settings source returned an invalid revision');
      }
      // The server has committed. Keep the prior draft visible while durable
      // invalidation waits for the partition lock, but bar another PATCH.
      _statuses[group] = SettingsReadStatus.refreshing;
      notifyListeners();
      _selfHandledGeneration = _cache.invalidationGeneration + 1;
      _selfHandledTags = {group.dependency};
      try {
        await _cache.applyCommittedMutation({group.dependency});
      } on Object {
        checkScope();
        _selfHandledGeneration = null;
        _selfHandledTags = const {};
        _publish(group, null, SettingsReadStatus.blocked);
      }
      _selfHandledGeneration = null;
      _selfHandledTags = const {};
      checkScope();
      await refresh(group, force: true);
      checkScope();
      return committed;
    } finally {
      _mutating.remove(group);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    super.dispose();
  }
}

final class _SettingsRemote implements CacheRemote<SettingsSnapshot> {
  const _SettingsRemote(this.source, this.group);
  final SettingsSource source;
  final SettingsGroup group;

  @override
  Future<CachePayload<SettingsSnapshot>> fetch(CacheResource resource, CancelToken cancel) async {
    final value = await source.fetch(group, cancel);
    if (value.group != group) throw StateError('Settings source returned the wrong revision group');
    return CachePayload(
      value: value,
      version: CacheVersion(
        resource: value.revision.toString(),
        representation: 'user-settings-v1',
        artifact: value.revision.toString(),
      ),
    );
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async => const CacheValidation(state: ValidationState.changed);
}
