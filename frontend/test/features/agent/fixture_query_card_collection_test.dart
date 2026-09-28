import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_collection_remote.dart';
import 'package:haruka/dev/preview/fixture_query_card_collection.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/agent/data/query_card_collection_repository.dart';
import 'package:haruka/features/agent/domain/learning_card.dart';
import 'package:haruka/features/agent/domain/query_request.dart';
import 'package:haruka/features/collections/data/cached_collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';

void main() {
  Future<
    (PreviewFixtureStore, CacheCoordinator, CachedCollectionCatalog, FixtureQueryCardCollection)
  >
  setup() async {
    final store = PreviewFixtureStore();
    final cache = CacheCoordinator(
      openBackend: (_) async {
        final executor = NativeDatabase.memory();
        return OpenedCacheBackend(
          executor: executor,
          mode: CacheStorageMode.memoryOnly,
          closeOwner: executor.close,
        );
      },
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/mock-preview'),
        instanceId: 'preview-fixtures',
        userId: 'preview-user',
        audience: 'client',
        sessionRef: 'preview-session',
      ),
    );
    final catalog = CachedCollectionCatalog(cache: cache, source: FixtureCollectionSource(store));
    await catalog.refreshAllCollections();
    await catalog.refreshNotebooks();
    final adapter = FixtureQueryCardCollection(store: store, catalog: catalog, cache: cache);
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
      store.dispose();
    });
    return (store, cache, catalog, adapter);
  }

  test('confirmed card reference writes through catalog once with notebook assignment', () async {
    final (store, cache, catalog, adapter) = await setup();
    final card = await store.generateQuery(
      const QueryRequest(text: 'そっと', targetLanguage: 'ja', explanationLanguage: 'zh-Hans'),
      scopeBinding: cache.scope!.binding,
    );
    final before = store.collections.length;
    final beforeIds = store.collections.map((item) => item.id).toSet();
    expect(adapter.isSaved(card.id, card.version), isFalse);
    final request = QueryCardSaveRequest(
      cardId: card.id,
      cardRevision: card.version,
      notebookIds: {'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
    );
    expect(await adapter.save(request), QueryCardSaveOutcome.saved);
    final saved = catalog.allCollections.singleWhere((item) => !beforeIds.contains(item.id));
    expect(saved.targetLanguage, 'ja');
    expect(saved.notebookIds, contains('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
    expect(saved.meaning, card.explanation);
    expect(saved.learningCardId, card.id);
    expect(saved.learningCardRevision, card.version);
    final roundTrip = CollectionEntry.fromJson(saved.toJson());
    final restoredCard = LearningCard.fromJson(roundTrip.learningCardSnapshot!);
    expect(restoredCard.toJson(), card.toJson());
    expect(roundTrip.copyWith(notes: 'memo').learningCardSnapshot, saved.learningCardSnapshot);
    expect(store.savedQueryCard(card.id, scopeBinding: 'another-user'), isNull);
    expect(store.collections, hasLength(before + 1));
    expect(adapter.isSaved(card.id, card.version), isTrue);
    expect(await adapter.save(request), QueryCardSaveOutcome.alreadySaved);
    expect(store.collections, hasLength(before + 1));
  });

  test('wrong language and changed account cannot write a query card', () async {
    final (store, cache, catalog, adapter) = await setup();
    final card = await store.generateQuery(
      const QueryRequest(text: 'そっと', targetLanguage: 'ja', explanationLanguage: 'zh-Hans'),
      scopeBinding: cache.scope!.binding,
    );
    final before = store.collections.length;
    await expectLater(
      adapter.save(
        QueryCardSaveRequest(
          cardId: card.id,
          cardRevision: card.version,
          notebookIds: {'cccccccc-cccc-4ccc-8ccc-cccccccccccc'},
        ),
      ),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.collections, hasLength(before));
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/mock-preview'),
        instanceId: 'preview-fixtures',
        userId: 'another-user',
        audience: 'client',
        sessionRef: 'another-session',
      ),
    );
    expect(adapter.isSaved(card.id, card.version), isFalse);
    await expectLater(
      adapter.save(
        QueryCardSaveRequest(cardId: card.id, cardRevision: card.version, notebookIds: {}),
      ),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.collections, hasLength(before));
  });
}
