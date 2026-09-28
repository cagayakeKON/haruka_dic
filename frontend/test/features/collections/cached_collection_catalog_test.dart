import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/data/cached_collection_catalog.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/collections/domain/notebook_record.dart';
import 'package:haruka/features/collections/domain/vocabulary_csv.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'cached_collection_catalog_test.mocks.dart';
import 'collection_catalog_test_harness.dart';

@GenerateNiceMocks([MockSpec<CollectionSource>()])
void main() {
  test('query identity includes notebook, type and normalized search', () {
    final first = CollectionListQuery(
      kind: CollectionKind.word,
      notebookId: 'book-a',
      search: '  SoTTo  ',
    );
    expect(
      first.key,
      CollectionListQuery(kind: CollectionKind.word, notebookId: 'book-a', search: 'sotto').key,
    );
    expect(
      first.key,
      isNot(
        CollectionListQuery(kind: CollectionKind.word, notebookId: 'book-b', search: 'sotto').key,
      ),
    );
    expect(
      first.key,
      isNot(
        CollectionListQuery(kind: CollectionKind.phrase, notebookId: 'book-a', search: 'sotto').key,
      ),
    );
    expect(CollectionListQuery.fromKey(first.key).normalizedSearch, 'sotto');
    expect(collectionListResourceFor(first).action, 'collection.read');
    expect(notebookListResource().action, 'vocabulary_notebook.read');
  });

  test('notebook denial does not grant notebook rows through collection read', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(
      store,
      permits: (action) => action != 'vocabulary_notebook.read',
    );
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshCollections();
    await harness.catalog.refreshNotebooks();
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.collections, isNotEmpty);
    expect(harness.catalog.notebookStatus, CollectionCatalogStatus.blocked);
    expect(harness.catalog.notebooks, isEmpty);
  });

  test('membership commit refreshes collection rows and notebook counts', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(store);
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshAllCollections();
    await harness.catalog.refreshNotebooks();
    final word = store.collections.first;
    final target = store.notebooks[1];
    expect(harness.catalog.notebookCount(target.id), 1);

    await harness.catalog.setCollectionNotebooks(word.id, {...word.notebookIds, target.id});
    expect(harness.catalog.findCollection(word.id)!.notebookIds, contains(target.id));
    expect(harness.catalog.notebookCount(target.id), 2);
  });

  test('membership update requires collection and notebook read before write', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(
      store,
      permits: (action) => action != 'collection.read',
    );
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    final before = store.collections.first.notebookIds;
    await expectLater(
      harness.catalog.setCollectionNotebooks(store.collections.first.id, {
        ...before,
        store.notebooks[1].id,
      }),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.collections.first.notebookIds, before);
  });

  test('manual collection with notebook requires notebook write permission', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(
      store,
      permits: (action) => action != 'vocabulary_notebook.update',
    );
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    final before = store.collections.length;
    final item = CollectionEntry.fromJson({
      ...store.collections.first.toJson(),
      'id': store.nextCollectionId(),
    });
    await expectLater(harness.catalog.addCollection(item), throwsA(isA<CacheBlocked>()));
    expect(store.collections, hasLength(before));
  });

  test('CSV import checks write permission before the atomic fixture commit', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(
      store,
      permits: (action) => action.endsWith('.read'),
    );
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    final before = store.collections.length;
    final preview = VocabularyCsvPreview(
      filename: 'words.csv',
      rows: [
        const VocabularyCsvRow(
          number: 1,
          word: '未保存の語',
          language: 'ja',
          meaning: '未保存',
          issues: [],
          duplicate: CsvDuplicateKind.none,
          notebookNames: [],
          tags: [],
        ),
      ],
    );
    await expectLater(
      harness.catalog.importVocabularyCsv(
        preview,
        duplicateAction: CsvDuplicateAction.skip,
        excludeErrors: false,
      ),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.collections, hasLength(before));
  });

  test('CSV import requires its entry action even with item write grants', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(
      store,
      permits: (action) => action != 'vocabulary.csv.import',
    );
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    final before = store.collections.length;
    const preview = VocabularyCsvPreview(
      filename: 'words.csv',
      rows: [
        VocabularyCsvRow(
          number: 1,
          word: '未保存の語',
          language: 'ja',
          meaning: '未保存',
          issues: [],
          duplicate: CsvDuplicateKind.none,
          notebookNames: [],
          tags: [],
        ),
      ],
    );
    await expectLater(
      harness.catalog.importVocabularyCsv(
        preview,
        duplicateAction: CsvDuplicateAction.skip,
        excludeErrors: false,
      ),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.collections, hasLength(before));
  });

  test('CSV commit rechecks a duplicate that appeared after preview', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(
      store,
      permits: (action) => action != 'collection.update',
    );
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    final existing = store.collections.first;
    final before = existing.revision;
    final preview = VocabularyCsvPreview(
      filename: 'words.csv',
      rows: [
        VocabularyCsvRow(
          number: 1,
          word: existing.displayText,
          language: existing.targetLanguage,
          meaning: '新释义',
          context: existing.context,
          sourceTitle: existing.sourceTitle,
          issues: const [],
          duplicate: CsvDuplicateKind.none,
          notebookNames: const [],
          tags: const [],
        ),
      ],
    );
    await expectLater(
      harness.catalog.importVocabularyCsv(
        preview,
        duplicateAction: CsvDuplicateAction.merge,
        excludeErrors: false,
      ),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.collections.first.revision, before);
  });

  test('external committed invalidation hides and reloads an accepted list', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(store);
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshCollections();
    final priorCount = harness.catalog.collections.length;
    store.addCollection(
      CollectionEntry.fromJson({
        ...store.collections.first.toJson(),
        'id': store.nextCollectionId(),
        'display_text': '外部更新',
      }),
    );
    final invalidation = harness.cache.applyCommittedMutation({collectionListDependency});
    expect(harness.catalog.collections, isEmpty);
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.blocked);
    await invalidation;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.collections, hasLength(priorCount + 1));
  });

  test('unrelated invalidation leaves collection snapshots visible without refetch', () async {
    final store = PreviewFixtureStore();
    final source = MockCollectionSource();
    final collections = CachePayload<List<CollectionEntry>>(
      value: [store.collections.first],
      version: const CacheVersion(
        resource: 'collections',
        representation: 'collection-summary-v1',
        artifact: 'collections',
      ),
    );
    final notebooks = CachePayload<NotebookListSnapshot>(
      value: NotebookListSnapshot(notebooks: store.notebooks, counts: const {}),
      version: const CacheVersion(
        resource: 'notebooks',
        representation: 'notebook-summary-v1',
        artifact: 'notebooks',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(collections);
    provideDummy<CachePayload<NotebookListSnapshot>>(notebooks);
    when(source.fetchCollections(any, any)).thenAnswer((_) async => collections);
    when(source.fetchNotebooks(any, any)).thenAnswer((_) async => notebooks);
    final harness = await CollectionCatalogTestHarness.create(store, source: source);
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshCollections();
    await harness.catalog.refreshAllCollections();
    await harness.catalog.refreshNotebooks();
    verify(source.fetchCollections(any, any)).called(2);
    verify(source.fetchNotebooks(any, any)).called(1);

    await harness.cache.applyCommittedMutation({'notification:list'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.allCollectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.notebookStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.collections.single.id, store.collections.first.id);
    expect(harness.catalog.notebooks, isNotEmpty);
    verifyNever(source.fetchCollections(any, any));
    verifyNever(source.fetchNotebooks(any, any));
  });

  test('overlapping persistent mutations recheck both dependency groups', () async {
    final fixture = PreviewFixtureStore();
    final source = MockCollectionSource();
    final firstCollection = fixture.collections.first;
    final addedCollection = CollectionEntry.fromJson({
      ...firstCollection.toJson(),
      'id': 'added-by-other-device',
      'display_text': '外部新收藏',
    });
    final firstNotebook = fixture.notebooks.first;
    final addedNotebook = NotebookRecord(
      id: 'added-by-other-device',
      name: '外部新词本',
      targetLanguage: firstNotebook.targetLanguage,
      description: '',
      revision: 1,
    );
    var collectionRows = [firstCollection];
    var notebookRows = [firstNotebook];
    CachePayload<List<CollectionEntry>> collectionsPayload() => CachePayload(
      value: collectionRows,
      version: CacheVersion(
        resource: 'collections-${collectionRows.length}',
        representation: 'collection-summary-v1',
        artifact: 'collections-${collectionRows.length}',
      ),
    );
    CachePayload<NotebookListSnapshot> notebooksPayload() => CachePayload(
      value: NotebookListSnapshot(notebooks: notebookRows, counts: const {}),
      version: CacheVersion(
        resource: 'notebooks-${notebookRows.length}',
        representation: 'notebook-summary-v1',
        artifact: 'notebooks-${notebookRows.length}',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(collectionsPayload());
    provideDummy<CachePayload<NotebookListSnapshot>>(notebooksPayload());
    when(source.fetchCollections(any, any)).thenAnswer((_) async => collectionsPayload());
    when(source.fetchNotebooks(any, any)).thenAnswer((_) async => notebooksPayload());
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-overlap'),
        instanceId: 'collection-test',
        userId: 'test-user',
        audience: 'client',
        sessionRef: 'test-session',
      ),
    );
    final catalog = CachedCollectionCatalog(cache: cache, source: source);
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
      fixture.dispose();
    });
    await catalog.refreshCollections();
    await catalog.refreshNotebooks();
    verify(source.fetchCollections(any, any)).called(1);
    verify(source.fetchNotebooks(any, any)).called(1);

    collectionRows = [firstCollection, addedCollection];
    notebookRows = [firstNotebook, addedNotebook];
    final collectionMutation = cache.applyCommittedMutation({collectionListDependency});
    final notebookMutation = cache.applyCommittedMutation({notebookListDependency});
    await Future.wait([collectionMutation, notebookMutation]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(catalog.notebookStatus, CollectionCatalogStatus.ready);
    expect(catalog.collections.map((item) => item.id), contains(addedCollection.id));
    expect(catalog.notebooks.map((item) => item.id), contains(addedNotebook.id));
    verify(source.fetchCollections(any, any)).called(1);
    verify(source.fetchNotebooks(any, any)).called(1);
  });

  test('confirmed notebook and collection edits refresh only their own dependency', () async {
    final store = PreviewFixtureStore();
    final source = MockCollectionSource();
    var collection = store.collections.first;
    var notebooks = [store.notebooks.first];
    final created = NotebookRecord(
      id: 'new-notebook',
      name: 'New notebook',
      targetLanguage: collection.targetLanguage,
      description: '',
      revision: 1,
    );
    final initialCollections = CachePayload<List<CollectionEntry>>(
      value: [collection],
      version: const CacheVersion(
        resource: 'collection-1',
        representation: 'collection-summary-v1',
        artifact: 'collection-1',
      ),
    );
    final initialNotebooks = CachePayload<NotebookListSnapshot>(
      value: NotebookListSnapshot(notebooks: notebooks, counts: const {}),
      version: const CacheVersion(
        resource: 'notebook-1',
        representation: 'notebook-summary-v1',
        artifact: 'notebook-1',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(initialCollections);
    provideDummy<CachePayload<NotebookListSnapshot>>(initialNotebooks);
    provideDummy<NotebookRecord>(created);
    when(source.fetchCollections(any, any)).thenAnswer(
      (_) async => CachePayload(
        value: [collection],
        version: CacheVersion(
          resource: 'collection-${collection.revision}',
          representation: 'collection-summary-v1',
          artifact: 'collection-${collection.revision}',
        ),
      ),
    );
    when(source.fetchNotebooks(any, any)).thenAnswer(
      (_) async => CachePayload(
        value: NotebookListSnapshot(notebooks: notebooks, counts: const {}),
        version: CacheVersion(
          resource: 'notebook-${notebooks.length}',
          representation: 'notebook-summary-v1',
          artifact: 'notebook-${notebooks.length}',
        ),
      ),
    );
    when(source.createNotebook(any, any, any)).thenAnswer((_) async {
      notebooks = [...notebooks, created];
      return created;
    });
    when(
      source.updateCollection(
        any,
        displayText: anyNamed('displayText'),
        meaning: anyNamed('meaning'),
        notes: anyNamed('notes'),
      ),
    ).thenAnswer((_) async {
      collection = collection.copyWith(displayText: 'Edited');
    });
    final harness = await CollectionCatalogTestHarness.create(store, source: source);
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshCollections();
    await harness.catalog.refreshAllCollections();
    await harness.catalog.refreshNotebooks();
    verify(source.fetchCollections(any, any)).called(2);
    verify(source.fetchNotebooks(any, any)).called(1);

    await harness.catalog.createNotebook(created.name, created.targetLanguage, created.description);
    expect(harness.cache.lastInvalidatedTags, {notebookListDependency});
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.allCollectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.collections.single.displayText, collection.displayText);
    expect(harness.catalog.notebooks.map((item) => item.id), contains(created.id));
    verifyNever(source.fetchCollections(any, any));
    verify(source.fetchNotebooks(any, any)).called(1);

    await harness.catalog.updateCollection(
      collection.id,
      displayText: 'Edited',
      meaning: collection.meaning,
      notes: collection.notes,
    );
    expect(harness.cache.lastInvalidatedTags, {collectionListDependency});
    expect(harness.catalog.notebookStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.notebooks.map((item) => item.id), contains(created.id));
    expect(harness.catalog.collections.single.displayText, 'Edited');
    expect(harness.catalog.allCollections.single.displayText, 'Edited');
    verifyNever(source.fetchNotebooks(any, any));
    verify(source.fetchCollections(any, any)).called(2);
  });

  test('revalidation generation recovery reloads a hidden collection list', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(store);
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshCollections();
    final priorCount = harness.catalog.collections.length;
    final generation = harness.cache.accountGeneration;
    harness.cache.requireOnlineRevalidation();
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.blocked);
    expect(harness.catalog.collections, isEmpty);
    store.addCollection(
      CollectionEntry.fromJson({
        ...store.collections.first.toJson(),
        'id': store.nextCollectionId(),
        'display_text': '恢复后新增',
      }),
    );
    harness.cache.completeOnlineRevalidation(harness.cache.scope!);
    expect(harness.cache.accountGeneration, greaterThan(generation));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(harness.catalog.collections, hasLength(priorCount + 1));
  });

  test('closing and switching account hides every accepted private snapshot', () async {
    final store = PreviewFixtureStore();
    final harness = await CollectionCatalogTestHarness.create(store);
    addTearDown(() async {
      await harness.close();
      store.dispose();
    });
    await harness.catalog.refreshCollections();
    await harness.catalog.refreshAllCollections();
    await harness.catalog.refreshNotebooks();
    expect(harness.catalog.collections, isNotEmpty);
    expect(harness.catalog.allCollections, isNotEmpty);
    expect(harness.catalog.notebooks, isNotEmpty);

    await harness.cache.closeScope();
    expect(harness.catalog.collectionStatus, CollectionCatalogStatus.blocked);
    expect(harness.catalog.allCollectionStatus, CollectionCatalogStatus.blocked);
    expect(harness.catalog.notebookStatus, CollectionCatalogStatus.blocked);
    expect(harness.catalog.collections, isEmpty);
    expect(harness.catalog.allCollections, isEmpty);
    expect(harness.catalog.notebooks, isEmpty);
    expect(harness.catalog.findCollection(store.collections.first.id), isNull);

    await harness.cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-test'),
        instanceId: 'collection-test',
        userId: 'other-user',
        audience: 'client',
        sessionRef: 'other-session',
      ),
    );
    expect(harness.catalog.collections, isEmpty);
    expect(harness.catalog.allCollections, isEmpty);
    expect(harness.catalog.notebooks, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.catalog.allCollectionStatus, CollectionCatalogStatus.ready);
  });

  test('an A write completing after B attach cannot invalidate or return into B', () async {
    final source = MockCollectionSource();
    final fixture = PreviewFixtureStore();
    final started = Completer<void>();
    final finish = Completer<void>();
    when(source.addCollection(any)).thenAnswer((_) {
      started.complete();
      return finish.future;
    });
    final payload = CachePayload<List<CollectionEntry>>(
      value: [fixture.collections.first],
      version: const CacheVersion(
        resource: 'b',
        representation: 'collection-summary-v1',
        artifact: 'b',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(payload);
    when(source.fetchCollections(any, any)).thenAnswer((_) async => payload);
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    Future<void> attach(String user) => cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-write-race'),
        instanceId: 'collection-test',
        userId: user,
        audience: 'client',
        sessionRef: '$user-session',
      ),
    );
    await attach('user-a');
    final catalog = CachedCollectionCatalog(cache: cache, source: source);
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
      fixture.dispose();
    });

    final oldWrite = catalog.addCollection(fixture.collections.last);
    await started.future;
    await cache.closeScope();
    await attach('user-b');
    await catalog.refreshCollections();
    final before = cache.invalidationGeneration;
    finish.complete();
    await expectLater(oldWrite, throwsA(isA<CacheBlocked>()));
    expect(cache.invalidationGeneration, before);
    expect(catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(catalog.collections.single.id, fixture.collections.first.id);
  });

  test('CSV commit result survives a failed post-commit list refresh', () async {
    final source = MockCollectionSource();
    final fixture = PreviewFixtureStore();
    final row = fixture.collections.first;
    final initial = CachePayload<List<CollectionEntry>>(
      value: [row],
      version: const CacheVersion(
        resource: 'initial',
        representation: 'collection-summary-v1',
        artifact: 'initial',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(initial);
    const committed = VocabularyCsvImportOutcome(added: 1, merged: 0, skipped: 0, excluded: 0);
    provideDummy<VocabularyCsvImportOutcome>(committed);
    var collectionReads = 0;
    when(source.fetchCollections(any, any)).thenAnswer((_) async {
      if (++collectionReads > 1) throw StateError('refresh offline');
      return initial;
    });
    when(
      source.importVocabularyCsv(
        any,
        duplicateAction: anyNamed('duplicateAction'),
        excludeErrors: anyNamed('excludeErrors'),
      ),
    ).thenAnswer((_) async => committed);
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-csv-fault'),
        instanceId: 'collection-test',
        userId: 'test-user',
        audience: 'client',
        sessionRef: 'test-session',
      ),
    );
    final catalog = CachedCollectionCatalog(cache: cache, source: source);
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
      fixture.dispose();
    });
    await catalog.refreshCollections();
    expect(catalog.collectionStatus, CollectionCatalogStatus.ready);
    const preview = VocabularyCsvPreview(filename: 'words.csv', rows: []);
    final result = await catalog.importVocabularyCsv(
      preview,
      duplicateAction: CsvDuplicateAction.skip,
      excludeErrors: false,
    );
    expect(result.added, 1);
    expect(catalog.collectionStatus, CollectionCatalogStatus.failed);
    expect(catalog.collections, isEmpty);
    verify(
      source.importVocabularyCsv(
        preview,
        duplicateAction: CsvDuplicateAction.skip,
        excludeErrors: false,
      ),
    ).called(1);
  });

  test('confirmed mutation retires an older in-flight collection read', () async {
    final source = MockCollectionSource();
    final fixture = PreviewFixtureStore();
    final oldItem = fixture.collections.first;
    final newItem = oldItem.copyWith(displayText: '新的词');
    final oldPayload = CachePayload<List<CollectionEntry>>(
      value: [oldItem],
      version: const CacheVersion(
        resource: 'old',
        representation: 'collection-summary-v1',
        artifact: 'old',
      ),
    );
    final newPayload = CachePayload<List<CollectionEntry>>(
      value: [newItem],
      version: const CacheVersion(
        resource: 'new',
        representation: 'collection-summary-v1',
        artifact: 'new',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(newPayload);
    final started = Completer<void>();
    final slow = Completer<CachePayload<List<CollectionEntry>>>();
    var calls = 0;
    when(source.fetchCollections(any, any)).thenAnswer((_) {
      calls++;
      if (calls == 1) {
        started.complete();
        return slow.future;
      }
      return Future.value(newPayload);
    });
    when(source.addCollection(any)).thenAnswer((_) async {});
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-race'),
        instanceId: 'collection-test',
        userId: 'test-user',
        audience: 'client',
        sessionRef: 'test-session',
      ),
    );
    final catalog = CachedCollectionCatalog(cache: cache, source: source);
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
      fixture.dispose();
    });

    final oldRead = catalog.refreshCollections();
    await started.future;
    await catalog.addCollection(newItem);
    slow.complete(oldPayload);
    await oldRead;
    expect(catalog.collectionStatus, CollectionCatalogStatus.ready);
    expect(catalog.collections.single.displayText, '新的词');
    verify(source.fetchCollections(any, any)).called(2);
    verify(source.addCollection(newItem)).called(1);
  });

  for (final failPersistentInvalidation in [false, true]) {
    test(
      'confirmed edit replaces a slow all-collection detail read '
      '${failPersistentInvalidation ? 'after invalidation storage failure' : 'after invalidation'}',
      () async {
        final source = MockCollectionSource();
        final fixture = PreviewFixtureStore();
        final original = fixture.collections.first;
        final edited = original.copyWith(displayText: '已编辑');
        final oldPayload = CachePayload<List<CollectionEntry>>(
          value: [original],
          version: const CacheVersion(
            resource: 'old-detail',
            representation: 'collection-summary-v1',
            artifact: 'old-detail',
          ),
        );
        final newPayload = CachePayload<List<CollectionEntry>>(
          value: [edited],
          version: const CacheVersion(
            resource: 'new-detail',
            representation: 'collection-summary-v1',
            artifact: 'new-detail',
          ),
        );
        provideDummy<CachePayload<List<CollectionEntry>>>(newPayload);
        final oldStarted = Completer<void>();
        final oldResponse = Completer<CachePayload<List<CollectionEntry>>>();
        var collectionReads = 0;
        when(source.fetchCollections(any, any)).thenAnswer((_) {
          collectionReads++;
          if (collectionReads == 1) {
            oldStarted.complete();
            return oldResponse.future;
          }
          return Future.value(newPayload);
        });
        when(
          source.updateCollection(
            original.id,
            displayText: '已编辑',
            meaning: original.meaning,
            notes: original.notes,
          ),
        ).thenAnswer((_) async {});
        final executor = NativeDatabase.memory();
        final cache = CacheCoordinator(
          openBackend: (_) async => OpenedCacheBackend(
            executor: executor,
            mode: failPersistentInvalidation
                ? CacheStorageMode.persistent
                : CacheStorageMode.memoryOnly,
            closeOwner: () async {},
          ),
        );
        await cache.attach(
          CacheScope.confirmed(
            endpoint: Uri.parse('http://127.0.0.1/collection-detail-race'),
            instanceId: 'collection-test',
            userId: 'test-user',
            audience: 'client',
            sessionRef: 'test-session',
          ),
        );
        if (failPersistentInvalidation) {
          await executor.runCustom(
            'CREATE TRIGGER fail_collection_invalidation '
            'BEFORE INSERT ON cache_invalidations '
            "BEGIN SELECT RAISE(FAIL, 'invalidation failed'); END",
          );
        }
        final catalog = CachedCollectionCatalog(cache: cache, source: source);
        addTearDown(() async {
          catalog.dispose();
          await cache.closeScope();
          fixture.dispose();
        });

        final oldRead = catalog.refreshAllCollections();
        await oldStarted.future;
        expect(catalog.allCollectionStatus, CollectionCatalogStatus.loading);
        await catalog.updateCollection(
          original.id,
          displayText: '已编辑',
          meaning: original.meaning,
          notes: original.notes,
        );
        expect(catalog.allCollectionStatus, CollectionCatalogStatus.ready);
        expect(catalog.findCollection(original.id)?.displayText, '已编辑');
        expect(collectionReads, 3);

        oldResponse.complete(oldPayload);
        await oldRead;
        expect(catalog.allCollectionStatus, CollectionCatalogStatus.ready);
        expect(catalog.findCollection(original.id)?.displayText, '已编辑');
        verify(
          source.updateCollection(
            original.id,
            displayText: '已编辑',
            meaning: original.meaning,
            notes: original.notes,
          ),
        ).called(1);
      },
    );
  }
}
