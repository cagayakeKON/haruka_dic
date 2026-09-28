import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../../../core/cache/cache_read_retry.dart';
import 'notification_repository.dart';
import '../domain/notification_record.dart';

const notificationListDependency = 'notification:list';

CacheResource notificationListResourceFor(NotificationListQuery query) => CacheResource(
  kind: 'notification_list',
  id: 'list',
  projection: 'notification-summary-v1',
  action: 'client.notification.read',
  sourceBinding: 'notification:list',
  queryKey: query.key,
);

/// A mutable list never becomes an offline or persistent cache entry.
final class CachedNotificationRepository extends ChangeNotifier implements NotificationRepository {
  CachedNotificationRepository({
    required CacheCoordinator cache,
    required this.remote,
    required this.readSource,
    required this.readAllSource,
    required this.waitForReadiness,
  }) : _cache = cache {
    cache.register(
      CachePolicy<NotificationListSnapshot>(
        kind: 'notification_list',
        disposition: CacheDisposition.memoryOnly,
        decode: NotificationListSnapshot.fromJson,
        encode: (snapshot) => snapshot.toJson(),
        dependencies: (_) => {notificationListDependency},
      ),
    );
    _observedBinding = cache.scope?.binding;
    _observedAccountGeneration = cache.accountGeneration;
    _observedAccessReady = cache.accessReady;
    _observedInvalidationGeneration = cache.invalidationGeneration;
    _cacheChanges = cache.changes.listen((_) {
      if (_disposed) return;
      final scopeChanged =
          _observedBinding != cache.scope?.binding ||
          _observedAccountGeneration != cache.accountGeneration;
      final readinessChanged = _observedAccessReady != cache.accessReady;
      final invalidated = _observedInvalidationGeneration != cache.invalidationGeneration;
      _observedBinding = cache.scope?.binding;
      _observedAccountGeneration = cache.accountGeneration;
      _observedAccessReady = cache.accessReady;
      _observedInvalidationGeneration = cache.invalidationGeneration;
      final tags = cache.lastInvalidatedTags;
      final relevantInvalidation =
          invalidated &&
          (tags == null || tags.contains(notificationListDependency)) &&
          !_ownInvalidation;
      if (invalidated &&
          !relevantInvalidation &&
          !scopeChanged &&
          cache.accessReady &&
          _snapshot != null) {
        _publishedInvalidationGeneration = cache.invalidationGeneration;
      }
      final discarded = _discardForeignSnapshot();
      if (discarded) notifyListeners();
      final needsRefresh =
          cache.accessReady && (scopeChanged || readinessChanged || relevantInvalidation);
      if (_mutating) {
        if (discarded || needsRefresh) _refreshAfterMutation = true;
        return;
      }
      if (needsRefresh && !_cache.dependenciesSafe({notificationListDependency})) {
        _publish(
          null,
          NotificationListStatus.blocked,
          const CacheBlocked('invalidation_not_durable'),
        );
        return;
      }
      if (needsRefresh && _status != NotificationListStatus.initial) {
        unawaited(refresh(force: true));
      }
    });
  }

  final CacheCoordinator _cache;
  final CacheRemote<NotificationListSnapshot> remote;
  final Future<void> Function(String) readSource;
  final Future<void> Function(String) readAllSource;
  final Future<void> Function() waitForReadiness;
  late final StreamSubscription<void> _cacheChanges;
  NotificationListSnapshot? _snapshot;
  NotificationListStatus _status = NotificationListStatus.initial;
  Object? _lastError;
  String? _publishedScopeBinding;
  int? _publishedAccountGeneration;
  int? _publishedInvalidationGeneration;
  int _requestGeneration = 0;
  String _activeQueryKey = const NotificationListQuery().key;
  bool _disposed = false;
  bool _mutating = false;
  bool _refreshAfterMutation = false;
  bool _ownInvalidation = false;
  late String? _observedBinding;
  late int _observedAccountGeneration;
  late bool _observedAccessReady;
  late int _observedInvalidationGeneration;

  @override
  NotificationListStatus get status {
    _discardForeignSnapshot();
    return _status;
  }

  @override
  List<NotificationRecord> get items {
    _discardForeignSnapshot();
    return _status == NotificationListStatus.ready || _status == NotificationListStatus.stale
        ? _snapshot?.items ?? const []
        : const [];
  }

  @override
  int get unreadCount {
    _discardForeignSnapshot();
    return _status == NotificationListStatus.ready || _status == NotificationListStatus.stale
        ? _snapshot?.unreadCount ?? 0
        : 0;
  }

  @override
  bool get busy => _mutating;
  @override
  Object? get lastError => _lastError;

  bool get _publicationCurrent =>
      _publishedScopeBinding != null &&
      _cache.accessReady &&
      _cache.scope?.binding == _publishedScopeBinding &&
      _cache.accountGeneration == _publishedAccountGeneration &&
      _cache.invalidationGeneration == _publishedInvalidationGeneration;

  bool _discardForeignSnapshot() {
    if (_snapshot == null || _publicationCurrent) return false;
    _snapshot = null;
    _publishedScopeBinding = null;
    _publishedAccountGeneration = null;
    _publishedInvalidationGeneration = null;
    _status = NotificationListStatus.blocked;
    _lastError = const CacheBlocked('scope_changed');
    _requestGeneration++;
    return true;
  }

  void _finishMutation() {
    _mutating = false;
    if (_disposed) return;
    notifyListeners();
    final refreshNeeded = _refreshAfterMutation;
    _refreshAfterMutation = false;
    if (refreshNeeded && _cache.accessReady) {
      unawaited(refresh(force: true));
    }
  }

  Future<void> _invalidateCommittedList() async {
    _ownInvalidation = true;
    try {
      await _cache.applyCommittedMutation({notificationListDependency});
    } finally {
      _ownInvalidation = false;
    }
  }

  void _publish(
    NotificationListSnapshot? snapshot,
    NotificationListStatus status, [
    Object? error,
  ]) {
    if (_disposed) return;
    _snapshot = snapshot;
    _status = status;
    _lastError = error;
    _publishedScopeBinding =
        status == NotificationListStatus.ready || status == NotificationListStatus.stale
        ? _cache.scope?.binding
        : null;
    _publishedAccountGeneration =
        status == NotificationListStatus.ready || status == NotificationListStatus.stale
        ? _cache.accountGeneration
        : null;
    _publishedInvalidationGeneration =
        status == NotificationListStatus.ready || status == NotificationListStatus.stale
        ? _cache.invalidationGeneration
        : null;
    notifyListeners();
  }

  @override
  Future<void> refresh({
    NotificationListQuery query = const NotificationListQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) async {
    _discardForeignSnapshot();
    final generation = ++_requestGeneration;
    final previous =
        (_status == NotificationListStatus.ready || _status == NotificationListStatus.stale) &&
            _activeQueryKey == query.key &&
            _publicationCurrent
        ? _snapshot
        : null;
    final binding = _cache.scope?.binding;
    final accountGeneration = _cache.accountGeneration;
    final invalidationGeneration = _cache.dependencyRevision(notificationListDependency);
    bool canRetain() =>
        previous != null &&
        _cache.accessReady &&
        _cache.scope?.binding == binding &&
        _cache.accountGeneration == accountGeneration &&
        _cache.dependencyRevision(notificationListDependency) == invalidationGeneration &&
        _activeQueryKey == query.key;
    final keepVisible = preserveCurrent && previous != null;
    _activeQueryKey = query.key;
    if (!keepVisible) _publish(null, NotificationListStatus.loading);
    try {
      await waitForReadiness();
      if (!_cache.accessReady) throw const CacheBlocked('identity_unconfirmed');
      final view = await _cache.read<NotificationListSnapshot>(
        resource: notificationListResourceFor(query),
        remote: remote,
        forceRefresh: force,
      );
      if (generation != _requestGeneration || _disposed) return;
      if (view.freshness == CacheFreshness.stale && view.data != null && canRetain()) {
        _publish(view.data, NotificationListStatus.stale, view.error);
      } else if (view.freshness == CacheFreshness.blocked || view.data == null) {
        _publish(null, NotificationListStatus.blocked);
      } else {
        _publish(view.data!, NotificationListStatus.ready);
      }
    } on CacheBlocked catch (error) {
      if (generation == _requestGeneration) _publish(null, NotificationListStatus.blocked, error);
    } on Object catch (error) {
      if (generation == _requestGeneration) {
        if (cacheReadMayKeepSnapshot(error) && canRetain()) {
          _publish(previous, NotificationListStatus.stale, error);
        } else {
          _publish(null, NotificationListStatus.failed, error);
        }
      }
    }
  }

  @override
  Future<void> markRead(String id) async {
    if (_mutating) throw const CacheBlocked('mutation_in_progress');
    if (!_cache.dependenciesSafe({notificationListDependency}))
      throw const CacheBlocked('invalidation_not_durable');
    _discardForeignSnapshot();
    if (_status != NotificationListStatus.ready ||
        _snapshot == null ||
        !_snapshot!.items.any((item) => item.id == id)) {
      throw const CacheBlocked('notification_snapshot_unavailable');
    }
    _mutating = true;
    notifyListeners();
    try {
      await waitForReadiness();
      if (!_publicationCurrent || !_cache.dependenciesSafe({notificationListDependency}))
        throw const CacheBlocked('scope_changed');
      await readSource(id);
      if (!_publicationCurrent) throw const CacheBlocked('scope_changed');
      await _invalidateCommittedList();
      await refresh(force: true);
    } finally {
      _finishMutation();
    }
  }

  @override
  Future<void> markAllRead() async {
    if (_mutating) throw const CacheBlocked('mutation_in_progress');
    if (!_cache.dependenciesSafe({notificationListDependency}))
      throw const CacheBlocked('invalidation_not_durable');
    _discardForeignSnapshot();
    final snapshot = _snapshot;
    if (_status != NotificationListStatus.ready || snapshot == null) {
      throw const CacheBlocked('notification_snapshot_unavailable');
    }
    _mutating = true;
    notifyListeners();
    try {
      await waitForReadiness();
      if (!_publicationCurrent || !_cache.dependenciesSafe({notificationListDependency}))
        throw const CacheBlocked('scope_changed');
      await readAllSource(snapshot.snapshotToken);
      if (!_publicationCurrent) throw const CacheBlocked('scope_changed');
      await _invalidateCommittedList();
      await refresh(force: true);
    } finally {
      _finishMutation();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    unawaited(_cacheChanges.cancel());
    super.dispose();
  }
}
