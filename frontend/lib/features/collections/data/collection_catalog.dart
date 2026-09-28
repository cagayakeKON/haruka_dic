import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/cache/cache_models.dart';
import '../domain/collection_entry.dart';
import '../domain/notebook_record.dart';
import '../domain/vocabulary_csv.dart';

enum CollectionCatalogStatus { initial, loading, ready, stale, blocked, failed }

/// The first-page collection identity. Future cursor, page size and sort
/// values belong in this key before pagination is enabled.
final class CollectionListQuery {
  const CollectionListQuery({this.kind, this.notebookId, this.search = ''});

  final CollectionKind? kind;
  final String? notebookId;
  final String search;

  String get normalizedSearch => search.trim().toLowerCase();
  String get key => jsonEncode([kind?.name, notebookId, normalizedSearch]);

  factory CollectionListQuery.fromKey(String key) {
    final parts = jsonDecode(key);
    if (parts is! List || parts.length != 3 || parts[2] is! String) {
      throw const FormatException('Invalid collection list query');
    }
    final kindName = parts[0];
    final notebookId = parts[1];
    if ((kindName != null && kindName is! String) ||
        (notebookId != null && notebookId is! String)) {
      throw const FormatException('Invalid collection list filter');
    }
    return CollectionListQuery(
      kind: kindName == null ? null : CollectionKind.values.byName(kindName as String),
      notebookId: notebookId as String?,
      search: parts[2] as String,
    );
  }
}

final class NotebookListSnapshot {
  NotebookListSnapshot({required List<NotebookRecord> notebooks, required Map<String, int> counts})
    : notebooks = List.unmodifiable(notebooks),
      counts = Map.unmodifiable(counts);

  final List<NotebookRecord> notebooks;
  final Map<String, int> counts;

  Map<String, Object?> toJson() => {
    'notebooks': [for (final notebook in notebooks) notebook.toJson()],
    'counts': counts,
  };

  factory NotebookListSnapshot.fromJson(Map<String, Object?> json) {
    final rows = json['notebooks'];
    final counts = json['counts'];
    if (rows is! List || counts is! Map) {
      throw const FormatException('Invalid notebook list snapshot');
    }
    return NotebookListSnapshot(
      notebooks: [
        for (final row in rows) NotebookRecord.fromJson((row as Map).cast<String, Object?>()),
      ],
      counts: counts.map((key, value) => MapEntry(key as String, value as int)),
    );
  }
}

/// A typed transport boundary. The preview implementation is replaceable by
/// authenticated API calls without changing the page/controller contract.
abstract interface class CollectionSource {
  Future<CachePayload<List<CollectionEntry>>> fetchCollections(
    CacheResource resource,
    CancelToken cancel,
  );

  Future<CachePayload<NotebookListSnapshot>> fetchNotebooks(
    CacheResource resource,
    CancelToken cancel,
  );

  Future<NotebookRecord> createNotebook(String name, String language, String description);
  Future<void> updateNotebook(String id, {String? name, String? description});
  Future<void> deleteNotebook(String id);
  Future<void> setCollectionNotebooks(String id, Set<String> notebookIds);
  Future<void> addCollection(CollectionEntry item);
  Future<void> updateCollection(
    String id, {
    required String displayText,
    required String meaning,
    required String notes,
  });
  Future<void> saveCollectionNotes(String id, String notes);
  Future<VocabularyCsvImportOutcome> importVocabularyCsv(
    VocabularyCsvPreview preview, {
    required CsvDuplicateAction duplicateAction,
    required bool excludeErrors,
  });
}

abstract interface class CollectionCatalog implements Listenable {
  int get scopeGeneration;
  CollectionCatalogStatus get collectionStatus;
  CollectionCatalogStatus get allCollectionStatus;
  CollectionCatalogStatus get notebookStatus;
  CollectionListQuery get currentQuery;
  List<CollectionEntry> get collections;
  List<CollectionEntry> get allCollections;
  List<NotebookRecord> get notebooks;
  int notebookCount(String notebookId);
  CollectionEntry? findCollection(String id);

  Future<void> refreshCollections({
    CollectionListQuery query = const CollectionListQuery(),
    bool force = false,
    bool preserveCurrent = false,
  });
  Future<void> refreshAllCollections({bool force = false, bool preserveCurrent = false});
  Future<void> refreshNotebooks({bool force = false, bool preserveCurrent = false});

  Future<NotebookRecord> createNotebook(String name, String language, String description);
  Future<void> updateNotebook(String id, {String? name, String? description});
  Future<void> deleteNotebook(String id);
  Future<void> setCollectionNotebooks(String id, Set<String> notebookIds);
  Future<void> addCollection(CollectionEntry item);
  Future<void> updateCollection(
    String id, {
    required String displayText,
    required String meaning,
    required String notes,
  });
  Future<void> saveCollectionNotes(String id, String notes);
  Future<VocabularyCsvImportOutcome> importVocabularyCsv(
    VocabularyCsvPreview preview, {
    required CsvDuplicateAction duplicateAction,
    required bool excludeErrors,
  });
}
