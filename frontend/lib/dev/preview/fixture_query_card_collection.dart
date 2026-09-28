import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/agent/data/query_card_collection_repository.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';

import 'fixture_store.dart';

/// Development source for the card-reference write contract. The UI never
/// publishes a client-provided card body or bypasses the catalog mutation.
final class FixtureQueryCardCollection implements QueryCardCollectionRepository {
  const FixtureQueryCardCollection({
    required this.store,
    required this.catalog,
    required this.cache,
  });

  final PreviewFixtureStore store;
  final CollectionCatalog catalog;
  final CacheCoordinator cache;

  String _collectionId(String cardId, int revision) {
    final digest = sha256.convert(utf8.encode('$cardId:$revision')).toString();
    return '${digest.substring(0, 8)}-${digest.substring(8, 12)}-4${digest.substring(13, 16)}-8${digest.substring(17, 20)}-${digest.substring(20, 32)}';
  }

  void _requireScope() {
    final scope = cache.scope;
    if (!cache.accessReady ||
        scope?.endpointKey != 'http://127.0.0.1/mock-preview' ||
        scope?.instanceId != 'preview-fixtures' ||
        scope?.userId != 'preview-user' ||
        scope?.audience != 'client') {
      throw const CacheBlocked('identity_unconfirmed');
    }
  }

  @override
  String? targetLanguage(String cardId, int cardRevision) {
    try {
      _requireScope();
    } on CacheBlocked {
      return null;
    }
    final binding = cache.scope!.binding;
    if (store.savedQueryCard(cardId, scopeBinding: binding)?.version != cardRevision) return null;
    final language = store.savedQueryTargetLanguage(cardId, scopeBinding: binding);
    return language == null || language.isEmpty ? null : language;
  }

  @override
  bool isSaved(String cardId, int cardRevision) {
    try {
      _requireScope();
    } on CacheBlocked {
      return false;
    }
    return catalog.allCollectionStatus == CollectionCatalogStatus.ready &&
        store.savedQueryCard(cardId, scopeBinding: cache.scope!.binding)?.version == cardRevision &&
        catalog.findCollection(_collectionId(cardId, cardRevision)) != null;
  }

  @override
  Future<QueryCardSaveOutcome> save(QueryCardSaveRequest request) async {
    _requireScope();
    final binding = cache.scope!.binding;
    final generation = cache.accountGeneration;
    void requireCurrent() {
      _requireScope();
      if (cache.scope?.binding != binding || cache.accountGeneration != generation) {
        throw const CacheBlocked('scope_changed');
      }
    }

    if (catalog.allCollectionStatus != CollectionCatalogStatus.ready ||
        catalog.notebookStatus != CollectionCatalogStatus.ready) {
      throw const CacheBlocked('collection_snapshot_unavailable');
    }
    final card = store.savedQueryCard(request.cardId, scopeBinding: binding);
    if (card == null || card.version != request.cardRevision) {
      throw const CacheBlocked('learning_result_unavailable');
    }
    final savedLanguage =
        store.savedQueryTargetLanguage(request.cardId, scopeBinding: binding) ?? '';
    if (savedLanguage.isNotEmpty && request.confirmedTargetLanguage != null) {
      throw const CacheBlocked('language_already_known');
    }
    final language = savedLanguage.isNotEmpty
        ? savedLanguage
        : request.confirmedTargetLanguage ?? '';
    if (!const {'ja', 'en'}.contains(language)) {
      throw const CacheBlocked('target_language_unconfirmed');
    }
    for (final notebookId in request.notebookIds) {
      final book = catalog.notebooks.where((row) => row.id == notebookId).firstOrNull;
      if (book == null || book.targetLanguage != language) {
        throw const CacheBlocked('notebook_language_mismatch');
      }
    }
    final collectionId = _collectionId(card.id, card.version);
    if (catalog.findCollection(collectionId) != null) return QueryCardSaveOutcome.alreadySaved;
    requireCurrent();
    await catalog.addCollection(
      CollectionEntry(
        id: collectionId,
        kind: card.kind,
        displayText: card.title,
        targetLanguage: language,
        reading: card.wordDetail?.romanization,
        meaning: card.explanation,
        context: card.examples.isEmpty ? null : card.examples.join('\n'),
        notebookIds: request.notebookIds,
        createdAt: DateTime.now().toUtc(),
        learningCardId: card.id,
        learningCardRevision: card.version,
        learningCardSnapshot: card.toJson(),
      ),
    );
    requireCurrent();
    return QueryCardSaveOutcome.saved;
  }
}
