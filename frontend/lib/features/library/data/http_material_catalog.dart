import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/api/responses.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../domain/material_metadata.dart';
import '../domain/material_import.dart';
import '../domain/material_summary.dart';
import 'material_catalog.dart';
import 'material_import_repository.dart';
import 'material_repository.dart';

/// One navigation-independent draft, bound to the catalog's current identity.
/// The repository owns the bounded byte snapshot; this keeps its existing intent.
final class MaterialImportDraft {
  MaterialImportDraft({
    required this.scope,
    required this.key,
    required this.type,
    required this.language,
    required this.title,
    this.file,
    this.source,
  });
  final Object scope;
  final String key;
  final LearningMaterialType type;
  final String language, title;
  XFile? file;
  final MaterialMetadata? source;
  MaterialImport? intent;
  bool busy = false, unknown = false;
  Object? error;
}

/// Safe source metadata uses the existing account/permission cache boundary.
/// It is memory-only; source bytes and learning content are separate resources.
final class HttpMaterialCatalog extends ChangeNotifier implements MaterialCatalog {
  HttpMaterialCatalog({
    required this.auth,
    required this.cache,
    required this.repository,
    required this.imports,
    this.onEvent,
  }) {
    cache.register(
      CachePolicy<_MetadataPage>(
        kind: 'material_metadata_catalog',
        disposition: CacheDisposition.memoryOnly,
        decode: (json) => _MetadataPage(
          (json['items'] as List).map(MaterialMetadata.fromJson).toList(),
          json['next_cursor'] as String?,
        ),
        encode: (page) => page.toJson(),
        dependencies: (_) => {'material:list'},
      ),
    );
    _remote = _MetadataRemote(repository);
    _scope = _scopeStamp;
    _accessReady = cache.accessReady;
    auth.addListener(_onAuth);
    _invalidation = cache.dependencyRevision('material:list');
    _changes = cache.changes.listen((_) {
      if (_disposed) return;
      if (_scope != _scopeStamp) {
        _onAuth();
        _accessReady = cache.accessReady;
        _invalidation = cache.dependencyRevision('material:list');
        if (_hasQuery && cache.accessReady && auth.isAuthenticated) {
          unawaited(refresh(query: _query));
        }
        return;
      }
      final restored = !_accessReady && cache.accessReady;
      _accessReady = cache.accessReady;
      final revision = cache.dependencyRevision('material:list');
      if (revision == _invalidation) {
        if (restored &&
            _hasQuery &&
            (_status == MaterialCatalogStatus.initial ||
                _status == MaterialCatalogStatus.blocked)) {
          unawaited(refresh(query: _query));
        } else {
          _publish();
        }
        return;
      }
      _invalidation = revision;
      if (!_ownMutation && cache.accessReady && auth.isAuthenticated) {
        unawaited(refresh(query: _query, force: true, preserveCurrent: true));
      }
    });
  }
  final AuthController auth;
  final CacheCoordinator cache;
  final MaterialRepository repository;
  final MaterialImportRepository imports;
  final void Function(String, Map<String, Object?>)? onEvent;
  Object get scopeIdentity => _scopeStamp;
  bool isCurrent(Object identity) =>
      !_disposed && status != MaterialCatalogStatus.blocked && _scopeStamp == identity;
  void record(String event, LearningMaterialType type, String result) =>
      onEvent?.call(event, {'material_type': type.name, 'result': result});
  late final _MetadataRemote _remote;
  late final StreamSubscription<void> _changes;
  final Map<String, MaterialMetadata> _details = {};
  final Map<String, int> _materialEpochs = {};
  List<MaterialMetadata> _rows = [];
  MaterialCatalogQuery _query = const MaterialCatalogQuery();
  MaterialCatalogStatus _status = MaterialCatalogStatus.initial;
  String? _nextCursor;
  Object? _scope;
  int _generation = 0;
  (int, int) _invalidation = (0, 0);
  bool _disposed = false, _ownMutation = false;
  bool _accessReady = false, _hasQuery = false;
  Future<void>? _request;
  String? _requestKey;
  ApiFailure? failure;
  MaterialImportDraft? _importDraft;
  MaterialImportDraft? get importDraft {
    final draft = _importDraft;
    if (draft == null || !isCurrent(draft.scope) || !allows('client.material.import')) {
      _importDraft = null;
      return null;
    }
    if (draft.intent?.upload case final upload?) {
      if (!upload.expiresAt.isAfter(DateTime.now().toUtc())) {
        draft.file = null;
        draft.unknown = true;
      }
    }
    return draft;
  }

  void retainImport(MaterialImportDraft draft) {
    if (!isCurrent(draft.scope) || !allows('client.material.import')) return;
    _importDraft = draft;
    _publish();
  }

  void clearImport(MaterialImportDraft draft) {
    if (identical(_importDraft, draft)) {
      _importDraft = null;
      _publish();
    }
  }

  Object get _scopeStamp => (
    auth.actionEpoch,
    auth.boundInstanceId,
    auth.repository.api.endpoint,
    auth.access?.userId,
    auth.access?.sessionRef,
    auth.access?.authzVersion.user,
    auth.access?.authzVersion.policy,
    auth.access?.securityEpoch,
    cache.scope?.binding,
    cache.accountGeneration,
  );
  bool allows(String action) =>
      auth.isAuthenticated && !auth.admin && (auth.access?.allows(action) ?? false);
  bool get hasMore => _nextCursor != null;
  bool get loadingMore => _request != null;
  @override
  MaterialCatalogStatus get status => auth.isAuthenticated && !auth.admin && cache.accessReady
      ? _status
      : MaterialCatalogStatus.blocked;
  MaterialMetadata? metadata(String id) =>
      status == MaterialCatalogStatus.blocked ? null : _details[id];

  void _onAuth() {
    final scope = _scopeStamp;
    if (_scope == scope && auth.isAuthenticated) return;
    _scope = scope;
    _generation++;
    _request = null;
    _requestKey = null;
    _remote.clear();
    _rows = [];
    _details.clear();
    _materialEpochs.clear();
    _importDraft = null;
    _nextCursor = null;
    _status = auth.isAuthenticated ? MaterialCatalogStatus.initial : MaterialCatalogStatus.blocked;
    _publish();
  }

  bool _current(Object scope, int generation) =>
      !_disposed &&
      auth.isAuthenticated &&
      !auth.admin &&
      cache.accessReady &&
      _scopeStamp == scope &&
      _generation == generation;
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  static MaterialSummary _summary(MaterialMetadata row) => MaterialSummary(
    id: row.id,
    type: row.type,
    title: row.title,
    language: row.language ?? '',
    status: row.sourceStatus == 'parsing' ? 'processing' : row.sourceStatus,
    revision: row.revision,
    updatedAt: row.updatedAt,
    description: '',
    cover: row.title.isEmpty ? '' : String.fromCharCode(row.title.runes.first),
  );
  @override
  List<MaterialSummary> filterMaterials(MaterialCatalogQuery query) =>
      status == MaterialCatalogStatus.ready || status == MaterialCatalogStatus.stale
      ? [
          for (final row in _rows)
            if ((query.type == null || row.type == query.type) &&
                (query.language == null || row.language == query.language) &&
                (query.normalizedSearch.isEmpty ||
                    row.title.toLowerCase().contains(query.normalizedSearch)))
              _summary(row),
        ]
      : [];
  @override
  MaterialSummary? findById(String id) => switch (metadata(id)) {
    final row? => _summary(row),
    null => null,
  };

  @override
  Future<void> refresh({
    MaterialCatalogQuery query = const MaterialCatalogQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) {
    _hasQuery = true;
    if (!force && _query.key == query.key && status == MaterialCatalogStatus.ready) {
      return Future.value();
    }
    if (_request != null && _requestKey == query.key) return _request!;
    _query = query;
    final scope = _scopeStamp;
    final generation = ++_generation;
    _requestKey = query.key;
    final request = _load(
      query,
      null,
      scope,
      generation,
      keep: preserveCurrent && _rows.isNotEmpty,
      force: force,
    );
    _request = request;
    return request.whenComplete(() {
      if (identical(_request, request)) {
        _request = null;
        _requestKey = null;
      }
    });
  }

  Future<void> more() {
    if (_request != null) return _request!;
    final cursor = _nextCursor;
    if (cursor == null) return Future.value();
    final request = _load(_query, cursor, _scopeStamp, ++_generation, keep: true, force: false);
    _request = request;
    return request.whenComplete(() {
      if (identical(_request, request)) {
        _request = null;
        _requestKey = null;
        _publish();
      }
    });
  }

  Future<void> _load(
    MaterialCatalogQuery query,
    String? cursor,
    Object scope,
    int generation, {
    required bool keep,
    required bool force,
  }) async {
    failure = null;
    if (!keep) _status = MaterialCatalogStatus.loading;
    _publish();
    try {
      final view = await cache.read<_MetadataPage>(
        resource: CacheResource(
          kind: 'material_metadata_catalog',
          id: 'list',
          projection: 'material-metadata-v1',
          action: 'material.list',
          sourceBinding: 'material-catalog:list',
          queryKey: jsonEncode([query.key, cursor]),
        ),
        remote: _remote,
        forceRefresh: force,
      );
      if (!_current(scope, generation)) return;
      final page = view.data;
      if (page == null || view.freshness == CacheFreshness.blocked) {
        _status = MaterialCatalogStatus.blocked;
        return;
      }
      if (cursor == null) _rows = [];
      final seen = _rows.map((row) => row.id).toSet();
      _rows = [..._rows, ...page.items.where((row) => !seen.contains(row.id))];
      for (final row in page.items) {
        _details[row.id] = row;
      }
      _nextCursor = page.nextCursor;
      _status = MaterialCatalogStatus.ready;
    } on Object catch (error) {
      if (!_current(scope, generation)) return;
      failure = error is ApiFailure ? error : const ApiFailure(code: 'NETWORK_ERROR');
      _status = keep ? MaterialCatalogStatus.stale : MaterialCatalogStatus.failed;
    } finally {
      if (_current(scope, generation)) _publish();
    }
  }

  Future<MaterialMetadata> detail(String id, {bool fresh = false}) async {
    final present = metadata(id);
    if (present != null && !fresh) return present;
    final scope = _scopeStamp;
    final epoch = _materialEpochs[id] ?? 0;
    final result = await repository.find(id);
    if (_disposed ||
        _scopeStamp != scope ||
        !auth.isAuthenticated ||
        !cache.accessReady ||
        (_materialEpochs[id] ?? 0) != epoch) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    if (result.id != id) throw const ApiFailure(code: 'INVALID_RESPONSE');
    _details[id] = result;
    _publish();
    return result;
  }

  Future<void> acceptedImport() => _committed(_scopeStamp);
  Future<void> rename(String id, int revision, String title) async {
    final scope = _scopeStamp;
    final updated = await repository.rename(id, revision, title);
    if (_scopeStamp != scope || !cache.accessReady) throw const ApiFailure(code: 'SESSION_INVALID');
    if (updated.id != id) throw const ApiFailure(code: 'INVALID_RESPONSE');
    _materialEpochs[id] = (_materialEpochs[id] ?? 0) + 1;
    _details[id] = updated;
    _rows = [for (final row in _rows) row.id == id ? updated : row];
    _publish();
    record('material.metadata.updated', updated.type, 'success');
    await _committed(scope);
  }

  @override
  Future<void> deleteMaterial(String id) async {
    final row = await detail(id);
    await deleteRevision(row);
  }

  Future<void> deleteRevision(MaterialMetadata row) async {
    final id = row.id;
    final scope = _scopeStamp;
    await repository.delete(id, row.revision);
    if (_scopeStamp != scope || !cache.accessReady) throw const ApiFailure(code: 'SESSION_INVALID');
    _materialEpochs[id] = (_materialEpochs[id] ?? 0) + 1;
    _details.remove(id);
    _rows = _rows.where((row) => row.id != id).toList();
    _publish();
    record('material.deleted', row.type, 'success');
    await _committed(scope);
  }

  Future<void> _committed(Object scope) async {
    if (!isCurrent(scope)) return;
    _ownMutation = true;
    try {
      await cache.applyCommittedMutation({'material:list'});
    } on Object {
      if (isCurrent(scope)) {
        failure = const ApiFailure(code: 'CACHE_UNAVAILABLE');
        _status = MaterialCatalogStatus.stale;
        _publish();
      }
      return;
    } finally {
      _ownMutation = false;
    }
    if (isCurrent(scope)) await refresh(query: _query, force: true, preserveCurrent: true);
  }

  @override
  Future<void> importMaterial(LearningMaterialType type, String title, String language) =>
      Future.error(const ApiFailure(code: 'INPUT_INVALID'));
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_onAuth);
    unawaited(_changes.cancel());
    _remote.clear();
    super.dispose();
  }
}

final class _MetadataPage {
  const _MetadataPage(this.items, this.nextCursor);
  final List<MaterialMetadata> items;
  final String? nextCursor;
  Map<String, Object?> toJson() => {
    'next_cursor': nextCursor,
    'items': [
      for (final row in items)
        {
          'id': row.id,
          'library_id': row.libraryId,
          'material_type': row.type.name,
          'title': row.title,
          'language': row.language,
          'source_format': row.sourceFormat,
          'source_status': row.sourceStatus,
          'analysis_status': row.analysisStatus,
          'revision': row.revision,
          'delete_generation': row.deleteGeneration,
          'revision_id': row.contentRevisionId,
          'first_chapter_id': row.firstChapterId,
          'job_id': row.jobId,
          'progress_percent': row.progressPercent,
          'readable': row.readable,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
        },
    ],
  };
}

final class _MetadataRemote implements CacheRemote<_MetadataPage> {
  _MetadataRemote(this.repository);
  final MaterialRepository repository;
  final Map<String, CachePayload<_MetadataPage>> _validated = {};
  void clear() => _validated.clear();
  @override
  Future<CachePayload<_MetadataPage>> fetch(CacheResource resource, CancelToken cancel) async {
    final previous = _validated.remove(resource.queryKey);
    if (previous != null) return previous;
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final parts = jsonDecode(resource.queryKey) as List;
    final query = MaterialCatalogQuery.fromKey(parts[0] as String);
    final page = await repository.list(
      type: query.type,
      language: query.language,
      search: query.search,
      cursor: parts[1] as String?,
    );
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final value = _MetadataPage(page.data, page.nextCursor);
    final digest = sha256.convert(utf8.encode(jsonEncode(value.toJson()))).toString();
    return CachePayload(
      value: value,
      version: CacheVersion(
        resource: digest,
        representation: 'material-metadata-v1',
        artifact: digest,
      ),
    );
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    final value = await fetch(resource, cancel);
    if (value.version.resource != known.resource) _validated[resource.queryKey] = value;
    return CacheValidation(
      state: value.version.resource == known.resource
          ? ValidationState.same
          : ValidationState.changed,
      version: value.version,
    );
  }
}
