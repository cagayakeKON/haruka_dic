import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../../../core/cache/cache_read_retry.dart';
import '../domain/material_summary.dart';
import 'material_catalog.dart';

CacheResource materialCatalogResourceFor(MaterialCatalogQuery query) => CacheResource(
  kind: 'material_catalog',
  id: 'list',
  projection: 'material-summary-v1',
  action: 'material.list',
  sourceBinding: 'material-catalog:list',
  queryKey: query.key,
);

const materialCatalogDependency = 'material:list';

/// One application data path for preview transport and future API transport.
final class CachedMaterialCatalog extends ChangeNotifier implements MaterialCatalog {
  CachedMaterialCatalog({
    required CacheCoordinator cache,
    required this.remote,
    required this.importSource,
    required this.deleteSource,
  }) : _cache = cache {
    cache.register(
      CachePolicy<List<MaterialSummary>>(
        kind: 'material_catalog',
        disposition: CacheDisposition.memoryOnly,
        decode: (json) {
          final rows = json['items'];
          if (rows is! List) throw const FormatException('Material catalog items missing');
          return [
            for (final row in rows) MaterialSummary.fromJson((row as Map).cast<String, Object?>()),
          ];
        },
        encode: (items) => {
          'items': [for (final item in items) item.toJson()],
        },
        dependencies: (_) => {materialCatalogDependency},
      ),
    );
    _observedInvalidationGeneration = cache.invalidationGeneration;
    _observedAccessReady = cache.accessReady;
    _scopeChanges = cache.changes.listen((_) {
      if (_disposed) return;
      final invalidated = _observedInvalidationGeneration != cache.invalidationGeneration;
      final readinessRestored = !_observedAccessReady && cache.accessReady;
      _observedInvalidationGeneration = cache.invalidationGeneration;
      _observedAccessReady = cache.accessReady;
      final tags = cache.lastInvalidatedTags;
      final relevantInvalidation =
          invalidated &&
          (tags == null || tags.contains(materialCatalogDependency)) &&
          !(_ownInvalidation && tags != null);
      if (invalidated &&
          !relevantInvalidation &&
          _visibleGeneration == cache.accountGeneration &&
          cache.accessReady) {
        _acceptedInvalidationGeneration = cache.invalidationGeneration;
      }
      if ((_status == MaterialCatalogStatus.ready || _status == MaterialCatalogStatus.stale) &&
          !_visibleScopeIsCurrent) {
        _requestGeneration++;
        _publish(const [], MaterialCatalogStatus.blocked);
      }
      if (!cache.accessReady || _status == MaterialCatalogStatus.initial) {
        return;
      }
      if (!readinessRestored && !relevantInvalidation) return;
      if (!_cache.dependenciesSafe({materialCatalogDependency})) {
        _requestGeneration++;
        _publish(const [], MaterialCatalogStatus.blocked);
        return;
      }
      unawaited(refresh(query: MaterialCatalogQuery.fromKey(_activeQueryKey), force: true));
    });
  }

  final CacheCoordinator _cache;
  final CacheRemote<List<MaterialSummary>> remote;
  final Future<void> Function(LearningMaterialType, String, String) importSource;
  final Future<void> Function(String) deleteSource;
  List<MaterialSummary> _items = const [];
  MaterialCatalogStatus _status = MaterialCatalogStatus.initial;
  int _requestGeneration = 0;
  String _activeQueryKey = const MaterialCatalogQuery().key;
  bool _disposed = false;
  late final StreamSubscription<void> _scopeChanges;
  int? _visibleGeneration;
  int? _acceptedInvalidationGeneration;
  late int _observedInvalidationGeneration;
  late bool _observedAccessReady;
  bool _ownInvalidation = false;

  bool get _visibleScopeIsCurrent =>
      _cache.accessReady &&
      _visibleGeneration == _cache.accountGeneration &&
      _acceptedInvalidationGeneration == _cache.invalidationGeneration;

  @override
  MaterialCatalogStatus get status =>
      (_status == MaterialCatalogStatus.ready || _status == MaterialCatalogStatus.stale) &&
          !_visibleScopeIsCurrent
      ? MaterialCatalogStatus.blocked
      : _status;

  void _publish(List<MaterialSummary> items, MaterialCatalogStatus status) {
    if (_disposed) return;
    _items = List.unmodifiable(items);
    _status = status;
    _visibleGeneration =
        status == MaterialCatalogStatus.ready || status == MaterialCatalogStatus.stale
        ? _cache.accountGeneration
        : null;
    _acceptedInvalidationGeneration =
        status == MaterialCatalogStatus.ready || status == MaterialCatalogStatus.stale
        ? _cache.invalidationGeneration
        : null;
    notifyListeners();
  }

  @override
  MaterialSummary? findById(String id) {
    if (status != MaterialCatalogStatus.ready && status != MaterialCatalogStatus.stale) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  List<MaterialSummary> filterMaterials(MaterialCatalogQuery query) {
    if (status != MaterialCatalogStatus.ready && status != MaterialCatalogStatus.stale) {
      return const [];
    }
    final term = query.normalizedSearch;
    return [
      for (final item in _items)
        if ((query.type == null || item.type == query.type) &&
            (term.isEmpty ||
                item.title.toLowerCase().contains(term) ||
                item.language.toLowerCase().contains(term)))
          item,
    ];
  }

  @override
  Future<void> refresh({
    MaterialCatalogQuery query = const MaterialCatalogQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) async {
    final generation = ++_requestGeneration;
    final previous =
        (status == MaterialCatalogStatus.ready || status == MaterialCatalogStatus.stale) &&
            _activeQueryKey == query.key
        ? _items
        : null;
    final previousBinding = _cache.scope?.binding;
    final previousAccount = _cache.accountGeneration;
    final previousInvalidation = _cache.dependencyRevision(materialCatalogDependency);
    bool canRetain() =>
        previous != null &&
        _cache.accessReady &&
        _cache.scope?.binding == previousBinding &&
        _cache.accountGeneration == previousAccount &&
        _cache.dependencyRevision(materialCatalogDependency) == previousInvalidation &&
        _activeQueryKey == query.key;
    final keepVisible = preserveCurrent && previous != null && _activeQueryKey == query.key;
    _activeQueryKey = query.key;
    if (!keepVisible) {
      _publish(const [], MaterialCatalogStatus.loading);
    }
    try {
      final view = await _cache.read<List<MaterialSummary>>(
        resource: materialCatalogResourceFor(query),
        remote: remote,
        forceRefresh: force,
      );
      if (generation != _requestGeneration) return;
      if (view.freshness == CacheFreshness.stale && view.data != null && canRetain()) {
        _publish(view.data!, MaterialCatalogStatus.stale);
      } else if (view.freshness == CacheFreshness.blocked || view.data == null) {
        _publish(const [], MaterialCatalogStatus.blocked);
      } else {
        _publish(view.data!, MaterialCatalogStatus.ready);
      }
    } on CacheBlocked {
      if (generation == _requestGeneration) _publish(const [], MaterialCatalogStatus.blocked);
    } on Object catch (error) {
      if (generation == _requestGeneration) {
        if (cacheReadMayKeepSnapshot(error) && canRetain()) {
          _publish(previous!, MaterialCatalogStatus.stale);
        } else {
          _publish(const [], MaterialCatalogStatus.failed);
        }
      }
    }
  }

  @override
  Future<void> importMaterial(LearningMaterialType type, String title, String language) async {
    if (!_cache.accessReady || !_cache.dependenciesSafe({materialCatalogDependency})) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    if (status == MaterialCatalogStatus.stale) {
      throw const CacheBlocked('catalog_revalidation_required');
    }
    final generation = _cache.accountGeneration;
    final binding = _cache.scope?.binding;
    try {
      await importSource(type, title, language);
      if (!_cache.accessReady ||
          _cache.accountGeneration != generation ||
          _cache.scope?.binding != binding) {
        throw const CacheBlocked('scope_changed');
      }
      _ownInvalidation = true;
      try {
        await _cache.applyCommittedMutation({materialCatalogDependency});
      } finally {
        _ownInvalidation = false;
      }
      await refresh(force: true);
    } on CacheBlocked {
      rethrow;
    } on Object {
      _publish(const [], MaterialCatalogStatus.failed);
      rethrow;
    }
  }

  @override
  Future<void> deleteMaterial(String id) async {
    if (!_cache.accessReady || !_cache.dependenciesSafe({materialCatalogDependency})) {
      throw const CacheBlocked('identity_unconfirmed');
    }
    if (status != MaterialCatalogStatus.ready || findById(id) == null) {
      throw const CacheBlocked('catalog_revalidation_required');
    }
    final generation = _cache.accountGeneration;
    final binding = _cache.scope?.binding;
    try {
      await deleteSource(id);
      if (!_cache.accessReady ||
          _cache.accountGeneration != generation ||
          _cache.scope?.binding != binding) {
        throw const CacheBlocked('scope_changed');
      }
      _ownInvalidation = true;
      try {
        await _cache.applyCommittedMutation({materialCatalogDependency});
      } finally {
        _ownInvalidation = false;
      }
      await refresh(force: true);
    } on CacheBlocked {
      rethrow;
    } on Object {
      _publish(const [], MaterialCatalogStatus.failed);
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    unawaited(_scopeChanges.cancel());
    super.dispose();
  }
}
