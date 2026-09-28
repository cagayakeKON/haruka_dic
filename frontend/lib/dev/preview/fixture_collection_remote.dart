import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/cache/cache_models.dart';
import '../../features/collections/data/collection_catalog.dart';
import '../../features/collections/domain/collection_entry.dart';
import '../../features/collections/domain/notebook_record.dart';
import '../../features/collections/domain/vocabulary_csv.dart';
import 'fixture_store.dart';

/// Development transport for mutable collection and notebook lists. The
/// action gate is explicit so tests can prove each list uses its own read
/// permission; production transport will obtain that decision from the API.
final class FixtureCollectionSource implements CollectionSource {
  const FixtureCollectionSource(this.store, {this.permits});

  final PreviewFixtureStore store;
  final bool Function(String action)? permits;

  void _require(CacheResource resource, String action) {
    if (resource.action != action || permits?.call(action) == false) {
      throw const CacheBlocked('forbidden');
    }
  }

  void _requireMutation(String action) {
    if (permits?.call(action) == false) throw const CacheBlocked('forbidden');
  }

  CacheVersion _version(Object value, String projection) {
    final digest = sha256.convert(utf8.encode(jsonEncode(value))).toString();
    return CacheVersion(resource: digest, representation: projection, artifact: digest);
  }

  @override
  Future<CachePayload<List<CollectionEntry>>> fetchCollections(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    _require(resource, 'collection.read');
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final query = CollectionListQuery.fromKey(resource.queryKey);
    final items = List<CollectionEntry>.unmodifiable(
      store.filterCollections(query.kind, query.search, notebookId: query.notebookId),
    );
    return CachePayload(
      value: items,
      version: _version([for (final item in items) item.toJson()], resource.projection),
    );
  }

  @override
  Future<CachePayload<NotebookListSnapshot>> fetchNotebooks(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    _require(resource, 'vocabulary_notebook.read');
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final snapshot = NotebookListSnapshot(
      notebooks: store.notebooks,
      counts: {
        for (final notebook in store.notebooks)
          notebook.id: store.filterCollections(null, '', notebookId: notebook.id).length,
      },
    );
    return CachePayload(value: snapshot, version: _version(snapshot.toJson(), resource.projection));
  }

  @override
  Future<NotebookRecord> createNotebook(String name, String language, String description) async {
    _requireMutation('vocabulary_notebook.create');
    return store.addNotebook(name, language, description);
  }

  @override
  Future<void> updateNotebook(String id, {String? name, String? description}) async {
    _requireMutation('vocabulary_notebook.update');
    store.updateNotebook(id, name: name, description: description);
  }

  @override
  Future<void> deleteNotebook(String id) async {
    _requireMutation('vocabulary_notebook.delete');
    store.deleteNotebook(id);
  }

  @override
  Future<void> setCollectionNotebooks(String id, Set<String> notebookIds) async {
    _requireMutation('collection.read');
    _requireMutation('vocabulary_notebook.read');
    _requireMutation('vocabulary_notebook.update');
    store.setCollectionNotebooks(id, notebookIds);
  }

  @override
  Future<void> addCollection(CollectionEntry item) async {
    _requireMutation('collection.create');
    if (item.notebookIds.isNotEmpty) {
      _requireMutation('vocabulary_notebook.read');
      _requireMutation('vocabulary_notebook.update');
    }
    store.addCollection(item);
  }

  @override
  Future<void> updateCollection(
    String id, {
    required String displayText,
    required String meaning,
    required String notes,
  }) async {
    _requireMutation('collection.update');
    store.updateCollection(id, displayText: displayText, meaning: meaning, notes: notes);
  }

  @override
  Future<void> saveCollectionNotes(String id, String notes) async {
    _requireMutation('collection.update');
    store.saveCollectionNotes(id, notes);
  }

  @override
  Future<VocabularyCsvImportOutcome> importVocabularyCsv(
    VocabularyCsvPreview preview, {
    required CsvDuplicateAction duplicateAction,
    required bool excludeErrors,
  }) async {
    // Check every action before the fixture's atomic commit. A skipped row
    // cannot create a notebook or merge an existing collection.
    _requireMutation('vocabulary.csv.import');
    _requireMutation('collection.read');
    _requireMutation('collection.create');
    final knownKeys = {
      for (final item in store.collections)
        if (item.kind == CollectionKind.word)
          vocabularyCsvDuplicateKey(
            word: item.displayText,
            language: item.targetLanguage,
            context: item.context,
            sourceTitle: item.sourceTitle,
          ),
    };
    final activeRows = <VocabularyCsvRow>[];
    var mergesExisting = false;
    for (final row in preview.rows) {
      if (!row.valid) continue;
      final key = vocabularyCsvDuplicateKey(
        word: row.word,
        language: row.language,
        context: row.context,
        sourceTitle: row.sourceTitle,
      );
      final existing = knownKeys.contains(key);
      if (existing && duplicateAction == CsvDuplicateAction.skip) continue;
      if (existing && duplicateAction == CsvDuplicateAction.merge) mergesExisting = true;
      activeRows.add(row);
      knownKeys.add(key);
    }
    if (mergesExisting) {
      _requireMutation('collection.update');
    }
    final names = {
      for (final row in activeRows)
        for (final name in row.notebookNames)
          if (name.trim().isNotEmpty) '${row.language}:${name.trim().toLowerCase()}',
    };
    if (names.isNotEmpty) {
      _requireMutation('vocabulary_notebook.read');
      _requireMutation('vocabulary_notebook.update');
      final existingNames = {
        for (final notebook in store.notebooks)
          '${notebook.targetLanguage}:${notebook.name.trim().toLowerCase()}',
      };
      if (names.difference(existingNames).isNotEmpty) {
        _requireMutation('vocabulary_notebook.create');
      }
    }
    final result = store.importVocabularyCsv(
      preview,
      duplicateAction: duplicateAction,
      excludeErrors: excludeErrors,
    );
    return VocabularyCsvImportOutcome(
      added: result.added,
      merged: result.merged,
      skipped: result.skipped,
      excluded: result.excluded,
    );
  }
}
