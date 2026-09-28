import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../../../core/cache/cache_read_retry.dart';
import '../domain/collection_entry.dart';
import '../domain/notebook_record.dart';
import '../domain/vocabulary_csv.dart';
import 'collection_catalog.dart';

const collectionListDependency = 'collection:list';
const notebookListDependency = 'vocabulary_notebook:list';

CacheResource collectionListResourceFor(CollectionListQuery query) => CacheResource(
  kind: 'collection_catalog',
  id: 'list',
  projection: 'collection-summary-v1',
  action: 'collection.read',
  sourceBinding: 'collection:list',
  queryKey: query.key,
);

CacheResource notebookListResource() => const CacheResource(
  kind: 'notebook_catalog',
  id: 'list',
  projection: 'notebook-summary-v1',
  action: 'vocabulary_notebook.read',
  sourceBinding: 'vocabulary-notebook:list',
  queryKey: '[]',
);

final class CachedCollectionCatalog extends ChangeNotifier implements CollectionCatalog {
  CachedCollectionCatalog({
    required CacheCoordinator cache,
    required this.source,
    this.waitForReadiness,
  }) : _cache = cache {
    _observedBinding = cache.scope?.binding;
    _observedAccountGeneration = cache.accountGeneration;
    _observedInvalidationGeneration = cache.invalidationGeneration;
    _observedAccessReady = cache.accessReady;
    _changes = cache.changes.listen((_) => _onCacheChange());
    cache.register(
      CachePolicy<List<CollectionEntry>>(
        kind: 'collection_catalog',
        disposition: CacheDisposition.memoryOnly,
        decode: (json) {
          final rows = json['items'];
          if (rows is! List) throw const FormatException('Collection items missing');
          return [
            for (final row in rows) CollectionEntry.fromJson((row as Map).cast<String, Object?>()),
          ];
        },
        encode: (items) => {
          'items': [for (final item in items) item.toJson()],
        },
        dependencies: (_) => {collectionListDependency},
      ),
    );
    cache.register(
      CachePolicy<NotebookListSnapshot>(
        kind: 'notebook_catalog',
        disposition: CacheDisposition.memoryOnly,
        decode: NotebookListSnapshot.fromJson,
        encode: (snapshot) => snapshot.toJson(),
        dependencies: (_) => {notebookListDependency},
      ),
    );
  }

  final CacheCoordinator _cache;
  late final StreamSubscription<void> _changes;
  final CollectionSource source;
  final Future<void> Function()? waitForReadiness;
  List<CollectionEntry> _collections = const [];
  List<CollectionEntry> _allCollections = const [];
  NotebookListSnapshot _notebookSnapshot = NotebookListSnapshot(
    notebooks: const [],
    counts: const {},
  );
  CollectionCatalogStatus _collectionStatus = CollectionCatalogStatus.initial;
  CollectionCatalogStatus _allCollectionStatus = CollectionCatalogStatus.initial;
  CollectionCatalogStatus _notebookStatus = CollectionCatalogStatus.initial;
  String? _collectionBinding;
  String? _allCollectionBinding;
  String? _notebookBinding;
  int? _collectionAccountGeneration;
  int? _allCollectionAccountGeneration;
  int? _notebookAccountGeneration;
  int? _collectionInvalidationGeneration;
  int? _allCollectionInvalidationGeneration;
  int? _notebookInvalidationGeneration;
  String? _observedBinding;
  late int _observedAccountGeneration;
  late int _observedInvalidationGeneration;
  late bool _observedAccessReady;
  int? _selfHandledInvalidationGeneration;
  Set<String> _selfHandledTags = const {};
  CollectionListQuery _currentQuery = const CollectionListQuery();
  int _collectionGeneration = 0;
  int _allCollectionGeneration = 0;
  int _notebookGeneration = 0;
  bool _disposed = false;

  @override
  int get scopeGeneration => _cache.scopeGeneration;

  bool _visible(String? binding, int? generation, int? invalidationGeneration) =>
      _cache.accessReady &&
      binding != null &&
      binding == _cache.scope?.binding &&
      generation == _cache.accountGeneration &&
      invalidationGeneration == _cache.invalidationGeneration;

  void _carryUnchangedSnapshots({
    required bool collectionsChanged,
    required bool notebooksChanged,
    required int invalidationGeneration,
  }) {
    if (!collectionsChanged &&
        (_collectionStatus == CollectionCatalogStatus.ready ||
            _collectionStatus == CollectionCatalogStatus.stale)) {
      _collectionInvalidationGeneration = invalidationGeneration;
    }
    if (!collectionsChanged &&
        (_allCollectionStatus == CollectionCatalogStatus.ready ||
            _allCollectionStatus == CollectionCatalogStatus.stale)) {
      _allCollectionInvalidationGeneration = invalidationGeneration;
    }
    if (!notebooksChanged &&
        (_notebookStatus == CollectionCatalogStatus.ready ||
            _notebookStatus == CollectionCatalogStatus.stale)) {
      _notebookInvalidationGeneration = invalidationGeneration;
    }
  }

  void _onCacheChange() {
    if (_disposed) return;
    final binding = _cache.scope?.binding;
    final accountGeneration = _cache.accountGeneration;
    final invalidationGeneration = _cache.invalidationGeneration;
    final accessReady = _cache.accessReady;
    final scopeChanged =
        binding != _observedBinding || accountGeneration != _observedAccountGeneration;
    final priorInvalidationGeneration = _observedInvalidationGeneration;
    final invalidated = invalidationGeneration != priorInvalidationGeneration;
    final missedInvalidations =
        invalidated && invalidationGeneration != priorInvalidationGeneration + 1;
    final readinessChanged = accessReady != _observedAccessReady;
    // A queued stream event may observe two already committed generations.
    // The last tag set alone cannot describe both mutations.
    final tags = missedInvalidations ? null : _cache.lastInvalidatedTags;
    final collectionsInvalidated =
        invalidated && (tags == null || tags.contains(collectionListDependency));
    final notebooksInvalidated =
        invalidated && (tags == null || tags.contains(notebookListDependency));
    _observedBinding = binding;
    _observedAccountGeneration = accountGeneration;
    _observedInvalidationGeneration = invalidationGeneration;
    _observedAccessReady = accessReady;
    if (!scopeChanged && !readinessChanged && invalidated) {
      // The coordinator generation is shared. Carry unaffected accepted
      // snapshots forward without rereading or exposing a stale affected row.
      _carryUnchangedSnapshots(
        collectionsChanged: collectionsInvalidated,
        notebooksChanged: notebooksInvalidated,
        invalidationGeneration: invalidationGeneration,
      );
    }
    if (!scopeChanged && !collectionsInvalidated && !notebooksInvalidated && !readinessChanged) {
      return;
    }
    notifyListeners();
    if (!accessReady) return;
    final skipSelf =
        !scopeChanged &&
        !readinessChanged &&
        !missedInvalidations &&
        invalidationGeneration == _selfHandledInvalidationGeneration &&
        tags != null;
    final selfTags = skipSelf ? Set<String>.of(_selfHandledTags) : const <String>{};
    final scheduledCollectionGeneration = _collectionGeneration;
    final scheduledAllCollectionGeneration = _allCollectionGeneration;
    final scheduledNotebookGeneration = _notebookGeneration;
    // Changes are emitted for both local and cross-tab invalidation. The
    // generation check above prevents read publication from causing a loop.
    scheduleMicrotask(() {
      if (_disposed ||
          !_cache.accessReady ||
          _cache.scope?.binding != binding ||
          _cache.accountGeneration != accountGeneration)
        return;
      if ((scopeChanged || readinessChanged || collectionsInvalidated) &&
          _collectionGeneration == scheduledCollectionGeneration &&
          _collectionStatus != CollectionCatalogStatus.initial &&
          !selfTags.contains(collectionListDependency) &&
          _cache.dependenciesSafe({collectionListDependency})) {
        unawaited(refreshCollections(query: _currentQuery, force: true));
      }
      if ((scopeChanged || readinessChanged || collectionsInvalidated) &&
          _allCollectionGeneration == scheduledAllCollectionGeneration &&
          _allCollectionStatus != CollectionCatalogStatus.initial &&
          !selfTags.contains(collectionListDependency) &&
          _cache.dependenciesSafe({collectionListDependency})) {
        unawaited(refreshAllCollections(force: true));
      }
      if ((scopeChanged || readinessChanged || notebooksInvalidated) &&
          _notebookGeneration == scheduledNotebookGeneration &&
          _notebookStatus != CollectionCatalogStatus.initial &&
          !selfTags.contains(notebookListDependency) &&
          _cache.dependenciesSafe({notebookListDependency})) {
        unawaited(refreshNotebooks(force: true));
      }
    });
  }

  @override
  CollectionCatalogStatus get collectionStatus =>
      (_collectionStatus == CollectionCatalogStatus.ready ||
              _collectionStatus == CollectionCatalogStatus.stale) &&
          !_visible(
            _collectionBinding,
            _collectionAccountGeneration,
            _collectionInvalidationGeneration,
          )
      ? CollectionCatalogStatus.blocked
      : _collectionStatus;
  @override
  CollectionCatalogStatus get allCollectionStatus =>
      (_allCollectionStatus == CollectionCatalogStatus.ready ||
              _allCollectionStatus == CollectionCatalogStatus.stale) &&
          !_visible(
            _allCollectionBinding,
            _allCollectionAccountGeneration,
            _allCollectionInvalidationGeneration,
          )
      ? CollectionCatalogStatus.blocked
      : _allCollectionStatus;
  @override
  CollectionCatalogStatus get notebookStatus =>
      (_notebookStatus == CollectionCatalogStatus.ready ||
              _notebookStatus == CollectionCatalogStatus.stale) &&
          !_visible(_notebookBinding, _notebookAccountGeneration, _notebookInvalidationGeneration)
      ? CollectionCatalogStatus.blocked
      : _notebookStatus;
  @override
  CollectionListQuery get currentQuery => _currentQuery;
  @override
  List<CollectionEntry> get collections =>
      collectionStatus == CollectionCatalogStatus.ready ||
          collectionStatus == CollectionCatalogStatus.stale
      ? _collections
      : const [];
  @override
  List<CollectionEntry> get allCollections =>
      allCollectionStatus == CollectionCatalogStatus.ready ||
          allCollectionStatus == CollectionCatalogStatus.stale
      ? _allCollections
      : const [];
  @override
  List<NotebookRecord> get notebooks =>
      notebookStatus == CollectionCatalogStatus.ready ||
          notebookStatus == CollectionCatalogStatus.stale
      ? _notebookSnapshot.notebooks
      : const [];
  @override
  int notebookCount(String notebookId) =>
      notebookStatus == CollectionCatalogStatus.ready ||
          notebookStatus == CollectionCatalogStatus.stale
      ? _notebookSnapshot.counts[notebookId] ?? 0
      : 0;
  @override
  CollectionEntry? findCollection(String id) {
    if (collectionStatus == CollectionCatalogStatus.ready) {
      for (final item in _collections) {
        if (item.id == id) return item;
      }
    }
    if (allCollectionStatus != CollectionCatalogStatus.ready) return null;
    for (final item in _allCollections) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _publishCollections(List<CollectionEntry> items, CollectionCatalogStatus status) {
    if (_disposed) return;
    _collections = List.unmodifiable(items);
    _collectionStatus = status;
    _collectionBinding =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.scope?.binding
        : null;
    _collectionAccountGeneration =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.accountGeneration
        : null;
    _collectionInvalidationGeneration =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.invalidationGeneration
        : null;
    notifyListeners();
  }

  void _publishAllCollections(List<CollectionEntry> items, CollectionCatalogStatus status) {
    if (_disposed) return;
    _allCollections = List.unmodifiable(items);
    _allCollectionStatus = status;
    _allCollectionBinding =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.scope?.binding
        : null;
    _allCollectionAccountGeneration =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.accountGeneration
        : null;
    _allCollectionInvalidationGeneration =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.invalidationGeneration
        : null;
    notifyListeners();
  }

  void _publishNotebooks(NotebookListSnapshot snapshot, CollectionCatalogStatus status) {
    if (_disposed) return;
    _notebookSnapshot = snapshot;
    _notebookStatus = status;
    _notebookBinding =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.scope?.binding
        : null;
    _notebookAccountGeneration =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.accountGeneration
        : null;
    _notebookInvalidationGeneration =
        status == CollectionCatalogStatus.ready || status == CollectionCatalogStatus.stale
        ? _cache.invalidationGeneration
        : null;
    notifyListeners();
  }

  Future<void> _ready() async {
    await waitForReadiness?.call();
    if (!_cache.accessReady) throw const CacheBlocked('identity_unconfirmed');
  }

  @override
  Future<void> refreshCollections({
    CollectionListQuery query = const CollectionListQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) async {
    final generation = ++_collectionGeneration;
    final previous =
        (collectionStatus == CollectionCatalogStatus.ready ||
                collectionStatus == CollectionCatalogStatus.stale) &&
            _currentQuery.key == query.key
        ? _collections
        : null;
    final binding = _cache.scope?.binding;
    final account = _cache.accountGeneration;
    final invalidation = _cache.dependencyRevision(collectionListDependency);
    bool canRetain() =>
        previous != null &&
        _cache.accessReady &&
        _cache.scope?.binding == binding &&
        _cache.accountGeneration == account &&
        _cache.dependencyRevision(collectionListDependency) == invalidation &&
        _currentQuery.key == query.key;
    final keepVisible = preserveCurrent && previous != null && _currentQuery.key == query.key;
    _currentQuery = query;
    if (!keepVisible) _publishCollections(const [], CollectionCatalogStatus.loading);
    try {
      await _ready();
      final view = await _cache.read<List<CollectionEntry>>(
        resource: collectionListResourceFor(query),
        remote: _CollectionRemote(source),
        forceRefresh: force,
      );
      if (generation != _collectionGeneration || _disposed) return;
      if (view.freshness == CacheFreshness.stale && view.data != null && canRetain()) {
        _publishCollections(view.data!, CollectionCatalogStatus.stale);
      } else if (view.freshness == CacheFreshness.blocked || view.data == null) {
        _publishCollections(const [], CollectionCatalogStatus.blocked);
      } else {
        _publishCollections(view.data!, CollectionCatalogStatus.ready);
      }
    } on CacheBlocked {
      if (generation == _collectionGeneration) {
        _publishCollections(const [], CollectionCatalogStatus.blocked);
      }
    } on Object catch (error) {
      if (generation == _collectionGeneration) {
        if (cacheReadMayKeepSnapshot(error) && canRetain()) {
          _publishCollections(previous!, CollectionCatalogStatus.stale);
        } else {
          _publishCollections(const [], CollectionCatalogStatus.failed);
        }
      }
    }
  }

  @override
  Future<void> refreshAllCollections({bool force = false, bool preserveCurrent = false}) async {
    final generation = ++_allCollectionGeneration;
    final previous =
        allCollectionStatus == CollectionCatalogStatus.ready ||
            allCollectionStatus == CollectionCatalogStatus.stale
        ? _allCollections
        : null;
    final binding = _cache.scope?.binding;
    final account = _cache.accountGeneration;
    final invalidation = _cache.dependencyRevision(collectionListDependency);
    bool canRetain() =>
        previous != null &&
        _cache.accessReady &&
        _cache.scope?.binding == binding &&
        _cache.accountGeneration == account &&
        _cache.dependencyRevision(collectionListDependency) == invalidation;
    final keepVisible = preserveCurrent && previous != null;
    if (!keepVisible) _publishAllCollections(const [], CollectionCatalogStatus.loading);
    try {
      await _ready();
      final view = await _cache.read<List<CollectionEntry>>(
        resource: collectionListResourceFor(const CollectionListQuery()),
        remote: _CollectionRemote(source),
        forceRefresh: force,
      );
      if (generation != _allCollectionGeneration || _disposed) return;
      if (view.freshness == CacheFreshness.stale && view.data != null && canRetain()) {
        _publishAllCollections(view.data!, CollectionCatalogStatus.stale);
      } else if (view.freshness == CacheFreshness.blocked || view.data == null) {
        _publishAllCollections(const [], CollectionCatalogStatus.blocked);
      } else {
        _publishAllCollections(view.data!, CollectionCatalogStatus.ready);
      }
    } on CacheBlocked {
      if (generation == _allCollectionGeneration) {
        _publishAllCollections(const [], CollectionCatalogStatus.blocked);
      }
    } on Object catch (error) {
      if (generation == _allCollectionGeneration) {
        if (cacheReadMayKeepSnapshot(error) && canRetain()) {
          _publishAllCollections(previous!, CollectionCatalogStatus.stale);
        } else {
          _publishAllCollections(const [], CollectionCatalogStatus.failed);
        }
      }
    }
  }

  @override
  Future<void> refreshNotebooks({bool force = false, bool preserveCurrent = false}) async {
    final generation = ++_notebookGeneration;
    final previous =
        notebookStatus == CollectionCatalogStatus.ready ||
            notebookStatus == CollectionCatalogStatus.stale
        ? _notebookSnapshot
        : null;
    final binding = _cache.scope?.binding;
    final account = _cache.accountGeneration;
    final invalidation = _cache.dependencyRevision(notebookListDependency);
    bool canRetain() =>
        previous != null &&
        _cache.accessReady &&
        _cache.scope?.binding == binding &&
        _cache.accountGeneration == account &&
        _cache.dependencyRevision(notebookListDependency) == invalidation;
    final keepVisible = preserveCurrent && previous != null;
    if (!keepVisible) {
      _publishNotebooks(
        NotebookListSnapshot(notebooks: const [], counts: const {}),
        CollectionCatalogStatus.loading,
      );
    }
    try {
      await _ready();
      final view = await _cache.read<NotebookListSnapshot>(
        resource: notebookListResource(),
        remote: _NotebookRemote(source),
        forceRefresh: force,
      );
      if (generation != _notebookGeneration || _disposed) return;
      if (view.freshness == CacheFreshness.stale && view.data != null && canRetain()) {
        _publishNotebooks(view.data!, CollectionCatalogStatus.stale);
      } else if (view.freshness == CacheFreshness.blocked || view.data == null) {
        _publishNotebooks(
          NotebookListSnapshot(notebooks: const [], counts: const {}),
          CollectionCatalogStatus.blocked,
        );
      } else {
        _publishNotebooks(view.data!, CollectionCatalogStatus.ready);
      }
    } on CacheBlocked {
      if (generation == _notebookGeneration) {
        _publishNotebooks(
          NotebookListSnapshot(notebooks: const [], counts: const {}),
          CollectionCatalogStatus.blocked,
        );
      }
    } on Object catch (error) {
      if (generation == _notebookGeneration) {
        if (cacheReadMayKeepSnapshot(error) && canRetain()) {
          _publishNotebooks(previous!, CollectionCatalogStatus.stale);
        } else {
          _publishNotebooks(
            NotebookListSnapshot(notebooks: const [], counts: const {}),
            CollectionCatalogStatus.failed,
          );
        }
      }
    }
  }

  Future<T> _write<T>(
    Future<T> Function() commit,
    Set<String> dependencies, {
    bool refreshCollectionsAfter = false,
    bool refreshNotebooksAfter = false,
  }) async {
    await _ready();
    if (!_cache.dependenciesSafe(dependencies))
      throw const CacheBlocked('invalidation_not_durable');
    if ((dependencies.contains(collectionListDependency) &&
            (_collectionStatus == CollectionCatalogStatus.stale ||
                _allCollectionStatus == CollectionCatalogStatus.stale)) ||
        (dependencies.contains(notebookListDependency) &&
            _notebookStatus == CollectionCatalogStatus.stale)) {
      throw const CacheBlocked('catalog_revalidation_required');
    }
    final binding = _cache.scope?.binding;
    final accountGeneration = _cache.accountGeneration;
    // Only a changed dependency needs a new list. Unrelated accepted snapshots
    // are carried forward when the coordinator emits its invalidation signal.
    final refreshActive =
        dependencies.contains(collectionListDependency) &&
        (refreshCollectionsAfter || collectionStatus == CollectionCatalogStatus.ready);
    final refreshAll =
        dependencies.contains(collectionListDependency) &&
        _allCollectionStatus != CollectionCatalogStatus.initial;
    final refreshNotebook =
        dependencies.contains(notebookListDependency) &&
        (refreshNotebooksAfter || notebookStatus == CollectionCatalogStatus.ready);
    void checkScope() {
      if (!_cache.accessReady ||
          binding != _cache.scope?.binding ||
          accountGeneration != _cache.accountGeneration) {
        throw const CacheBlocked('scope_changed');
      }
    }

    if (!_cache.dependenciesSafe(dependencies))
      throw const CacheBlocked('invalidation_not_durable');
    final result = await commit();
    checkScope();
    _selfHandledInvalidationGeneration = _cache.invalidationGeneration + 1;
    _selfHandledTags = Set.unmodifiable(dependencies);
    var invalidationFailed = false;
    try {
      await _cache.applyCommittedMutation(dependencies);
    } on Object {
      checkScope();
      invalidationFailed = true;
      _selfHandledInvalidationGeneration = null;
      _selfHandledTags = const {};
    }
    _selfHandledInvalidationGeneration = null;
    _selfHandledTags = const {};
    checkScope();
    if (invalidationFailed) {
      // The server commit already happened. Retire visible projections and
      // attempt a forced read without turning that commit into a UI failure.
      _carryUnchangedSnapshots(
        collectionsChanged: dependencies.contains(collectionListDependency),
        notebooksChanged: dependencies.contains(notebookListDependency),
        invalidationGeneration: _cache.invalidationGeneration,
      );
      if (refreshActive) _publishCollections(const [], CollectionCatalogStatus.blocked);
      if (refreshAll) _publishAllCollections(const [], CollectionCatalogStatus.blocked);
      if (refreshNotebook) {
        _publishNotebooks(
          NotebookListSnapshot(notebooks: const [], counts: const {}),
          CollectionCatalogStatus.blocked,
        );
      }
    }
    if (refreshActive) await refreshCollections(query: _currentQuery, force: true);
    checkScope();
    if (refreshAll) {
      await refreshAllCollections(force: true);
    }
    checkScope();
    if (refreshNotebook) await refreshNotebooks(force: true);
    checkScope();
    return result;
  }

  @override
  Future<NotebookRecord> createNotebook(String name, String language, String description) => _write(
    () => source.createNotebook(name, language, description),
    {notebookListDependency},
    refreshNotebooksAfter: true,
  );

  @override
  Future<void> updateNotebook(String id, {String? name, String? description}) => _write(
    () => source.updateNotebook(id, name: name, description: description),
    {notebookListDependency},
    refreshNotebooksAfter: true,
  );

  @override
  Future<void> deleteNotebook(String id) => _write(
    () => source.deleteNotebook(id),
    {notebookListDependency, collectionListDependency},
    refreshCollectionsAfter: true,
    refreshNotebooksAfter: true,
  );

  @override
  Future<void> setCollectionNotebooks(String id, Set<String> notebookIds) => _write(
    () => source.setCollectionNotebooks(id, notebookIds),
    {collectionListDependency, notebookListDependency},
    refreshCollectionsAfter: true,
    refreshNotebooksAfter: true,
  );

  @override
  Future<void> addCollection(CollectionEntry item) => _write(
    () => source.addCollection(item),
    {collectionListDependency, notebookListDependency},
    refreshCollectionsAfter: true,
    refreshNotebooksAfter: true,
  );

  @override
  Future<void> updateCollection(
    String id, {
    required String displayText,
    required String meaning,
    required String notes,
  }) => _write(
    () => source.updateCollection(id, displayText: displayText, meaning: meaning, notes: notes),
    {collectionListDependency},
    refreshCollectionsAfter: true,
  );

  @override
  Future<void> saveCollectionNotes(String id, String notes) => _write(
    () => source.saveCollectionNotes(id, notes),
    {collectionListDependency},
    refreshCollectionsAfter: true,
  );

  @override
  Future<VocabularyCsvImportOutcome> importVocabularyCsv(
    VocabularyCsvPreview preview, {
    required CsvDuplicateAction duplicateAction,
    required bool excludeErrors,
  }) => _write(
    () => source.importVocabularyCsv(
      preview,
      duplicateAction: duplicateAction,
      excludeErrors: excludeErrors,
    ),
    {collectionListDependency, notebookListDependency},
    refreshCollectionsAfter: true,
    refreshNotebooksAfter: true,
  );

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    _collectionGeneration++;
    _allCollectionGeneration++;
    _notebookGeneration++;
    super.dispose();
  }
}

final class _CollectionRemote implements CacheRemote<List<CollectionEntry>> {
  const _CollectionRemote(this.source);
  final CollectionSource source;

  @override
  Future<CachePayload<List<CollectionEntry>>> fetch(CacheResource resource, CancelToken cancel) =>
      source.fetchCollections(resource, cancel);

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async => CacheValidation(
    state: ValidationState.changed,
    version: (await fetch(resource, cancel)).version,
  );
}

final class _NotebookRemote implements CacheRemote<NotebookListSnapshot> {
  const _NotebookRemote(this.source);
  final CollectionSource source;

  @override
  Future<CachePayload<NotebookListSnapshot>> fetch(CacheResource resource, CancelToken cancel) =>
      source.fetchNotebooks(resource, cancel);

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async => CacheValidation(
    state: ValidationState.changed,
    version: (await fetch(resource, cancel)).version,
  );
}
